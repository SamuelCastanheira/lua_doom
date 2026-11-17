# Passo 2: fluxo de telas em concorrência estruturada

- Branch: `atmos`
- Referência: tag `passo1`
- Resultado: tag `passo2`

## Resumo

As decisões de troca de tela do lua_doom (título, nível, intermissão, finale,
novo jogo, load, End Game, morte, `idclev`, Quit) saíram de quatro funções Lua
e de chamadas espalhadas pelo menu, pelos cheats e pelo save. Elas viraram uma
hierarquia de sete tasks Atmos em `main.atm`. Cada tela é uma task que monta o
que precisa, entra na tela e **devolve como terminou**; quem decide a próxima
tela é a task logo acima. Pedidos externos (menu, cheats, janela) chegam como
eventos e abortam o escopo certo.

Resultados medidos:

- **Equivalência:** idêntico à versão imperativa, quadro a quadro (framebuffer
  e estado do jogo), em 4.478 a 6.000 quadros por roteiro, incluindo um
  roteiro que passa por todas as transições.
- **Sensibilidade:** 10 de 10 erros plausíveis injetados foram detectados, e
  2 mutantes equivalentes foram justificados.
- **Custo:** +0,06 ms por quadro em relação ao driver Atmos do passo 1 e
  +0,14 ms em relação ao laço imperativo, o que é 0,5% de um tic de 28,6 ms.

---

## 1. Situação antes (tag `passo1`)

No passo 1 o laço do jogo já era Atmos, mas as tasks de tela só
**observavam** as trocas: depois de cada fase, o `main.atm` comparava
`game.gamestate` com o valor anterior (`G.screen_changed()`) e reiniciava a
task da tela. A decisão estava em Lua, espalhada assim
(números de linha da tag `passo1`):

| Transição | Onde era decidida |
|---|---|
| Nível → intermissão ou finale, saída secreta | `game.begin_exit` (`game.lua:273`), chamado de dentro de `G.tic_view` |
| Intermissão → próximo nível ou título | `game.advance` (`game.lua:365`), chamado de dentro de `G.tic_intermission` |
| Finale → título ou próximo mapa | `game.finish_finale` (`game.lua:345`), chamado de dentro de `G.tic_finale` |
| End Game → título | `game.end_game` (`game.lua:389`), chamado pelo menu |
| Novo jogo | `menu.lua:307`, que chamava `game.start_level` |
| `idclev` | `cheats.lua:225`, que chamava `game.start_level` |
| Load game | `saveg.lua:650` (`start_level`) e `saveg.lua:766` (`gamestate = "view"`) |
| Morte → renascer | `game.lua:763`, `start_level` dentro de `G.tic_view` |
| Quit | `menu.lua`, `game.running = false`, lido pelo laço |

Consequências:

- `game.gamestate` era escrito em **8 lugares, em 2 arquivos**, e
  `start_level` era chamado de **7 lugares, em 4 arquivos**
  (`tools/metricas_passo2.py`).
- Uma transição acontecia no fundo de uma pilha de chamadas. Por exemplo,
  `handle_input → menu.responder → do_action → game.start_level` monta um
  nível novo de dentro do tratamento de uma tecla. Para saber o que o jogo
  faz depois do mapa 9, era preciso ler `begin_exit`, `advance` e o código
  que chama cada um.
- O próximo mapa e o fim de episódio eram decididos em duas funções
  diferentes (`begin_exit` decide o mapa; `advance` decide se o mapa existe e
  se há finale do Doom 2) e comunicados por campos globais (`pending_map`,
  `was_secret`).

---

## 2. Solução

### 2.1 Princípio: decidir no escopo, montar no Lua

O código foi dividido por responsabilidade:

- **Lua (`game.lua`) monta:** o nível (`build_level`), a intermissão
  (`make_intermission`), o finale (`make_finale`), a limpeza ao voltar ao
  título (`to_title`, `clear_game`) e o fim do nível sem decisão (`end_level`:
  automapa, saída secreta, `carry`).
- **Atmos (`main.atm`) decide:** qual tela vem depois, e quando cada tela
  começa e termina.

Nenhuma regra de jogo foi reescrita. O conteúdo de `begin_exit` foi separado
em "o que acontece sempre" (`end_level`), "para onde ir" (`proximo_mapa` e a
task `Saida`, em Atmos) e "montar a intermissão" (`make_intermission`).

### 2.2 Pedidos em vez de chamadas, emitidos nas fronteiras de fase

Menu, cheats e janela não chamam mais funções que trocam de tela. Eles
registram um **pedido**:

```lua
-- game.lua
function game.request(tag, data)
  local ev = data or {}
  ev.tag = tag
  requests[#requests + 1] = ev
end
```

```lua
-- menu.lua, acao "skill" (antes: game.skill = ...; game.start_level(game))
self.game.request("jogo.novo", { episode = self.epi + 1, mapn = 1, skill = choice })
```

O `main.atm` emite os pedidos **depois** que a fase de Lua terminou:

```
func pedidos () {
    loop _, r in G.take_requests() {
        emit(r)
    }
}

spawn {                       ;; entrada
    loop ev on :input {
        G.handle_input(ev)
        pedidos()
    }
}
```

**Por quê:** se o menu emitisse `:jogo.novo` de dentro do `handle_input`, o
evento abortaria a task `Jogo` enquanto a pilha Lua do menu ainda estivesse
executando, e o código Lua depois do `emit` ficaria pela metade. Com a fila,
**nenhuma task é abortada no meio de uma chamada Lua**. A ordem também é a
mesma da versão imperativa: o pedido é emitido logo depois do evento de
entrada que o gerou, antes do próximo evento e antes dos tics do quadro. É o
mesmo ponto em que o `start_level` acontecia antes.

Os cinco pedidos:

| Pedido | Origem | Efeito no `main.atm` |
|---|---|---|
| `jogo.novo {episode, mapn, skill}` | menu "New Game", `-warp` | `Fluxo` descarta o `Jogo` atual e começa outro |
| `jogo.carregar {data}` | menu "Load Game" | idem, com o nível montado a partir do save |
| `jogo.fim` | menu "End Game" | `Fluxo` descarta o `Jogo`, limpa e volta ao título |
| `nivel.trocar {episode, mapn}` | cheat `idclev` | `Nivel` termina; `Jogo` vai ao mapa pedido |
| `jogo.sair` | menu "Quit", fechar janela | o programa termina depois do quadro atual |

### 2.3 Hierarquia de tasks

```
Fluxo ── Titulo                         devolve o pedido (novo ou load)
     └── Jogo(pedido)                   um jogo, do primeiro mapa ao fim
          ├── Nivel(save)               uma instância de nível
          │                             devolve [fim=:morte|:saida|:trocar]
          └── Saida()                   devolve true (continua) ou false (título)
               ├── Intermissao(nxt)
               └── Finale(anuncia)      devolve "title" ou "worlddone"
```

Cada nível de tela devolve um **resultado**, e quem está acima decide:

```
task Nivel (save) {
    if save { G.load_level(save) } else { G.start_level() }
    G.enter(:view)
    par :any {
        loop on :game.tic {
            val fim = G.tic_view()            ;; nil | "morte" | "saida"
            if fim == :saida {
                env.cancel_catchup()          ;; nao recupera mais tics neste quadro
            }
            until (fim, [fim=fim])
        }
    } with {
        val t = await :nivel.trocar           ;; idclev
        [fim=:trocar, episode=t.episode, mapn=t.mapn]
    }
}

task Jogo (pedido) {
    ...
    loop {
        val r = await Nivel(save)
        set save = nil
        val continua = ifs {
            (r.fim == :morte)  => true        ;; renasce no mesmo mapa
            (r.fim == :trocar) => { G.set_level(r.episode, r.mapn) ; true }
            else => await Saida()
        }
        until (!continua)
    }
    G.to_title()
}

task Fluxo () {
    var pedido = G.initial_request()          ;; -warp: comeca num nivel
    loop {
        if !pedido {
            set pedido = await Titulo()
        }
        set pedido = par :any {
            await Jogo(pedido)
            false                             ;; jogo acabou: titulo
        } with {
            await :jogo.novo
        } with {
            await :jogo.carregar
        } with {
            await :jogo.fim
            G.end_game()
            false
        }
    }
}
```

Para o artigo, o ponto central é que **cada pedido externo aborta
exatamente o escopo a que pertence**:

- `:nivel.trocar` só é aguardado dentro de `Nivel`. Fora de um nível ele não
  tem efeito, como no original, em que o cheat só funciona em jogo.
- `:jogo.novo`, `:jogo.carregar` e `:jogo.fim` são aguardados por `Fluxo` em
  paralelo com `Jogo`. Quando um deles chega, `Jogo` e tudo dentro dele
  (`Nivel`, `Saida`, `Intermissao`, `Finale`) terminam juntos, sem limpeza
  manual de estado de tela.
- No título, só `Titulo` aguarda `:jogo.novo` e `:jogo.carregar`. A versão
  imperativa precisava de `if gamestate == "title"` no menu para recusar
  "End Game" no título; esse teste continua no menu, mas o fluxo não depende
  dele.

### 2.4 Mapeamento antes → depois

| Antes (`passo1`) | Depois (`passo2`) |
|---|---|
| `begin_exit`: fecha automapa, segredo, `carry` | `game.end_level` (Lua), chamado por `Saida` |
| `begin_exit`: E1M8 → finale | `Saida`: `(!G.commercial()) && (G.game.mapn == 8)` |
| `begin_exit`: próximo mapa (secreto, volta do 9) | `func proximo_mapa` (Atmos) |
| `begin_exit`: monta `wi` | `game.make_intermission` (Lua), chamado por `Intermissao` |
| `advance`: finale do Doom 2 | `Saida`: `G.commercial() && G.commercial_finale()` |
| `advance`: mapa inexistente → título | `Saida`: `!G.map_exists(nxt) => false` |
| `advance` / `finish_finale`: `start_level` | `Jogo` continua o `loop`; `Nivel` monta |
| `finish_finale`: `"worlddone"` | `func depois_do_finale` (Atmos) |
| `finish_finale` / `advance`: limpeza do título | `game.to_title` (Lua), chamado por `Jogo` ao terminar |
| `end_game`: limpeza e título | menu pede `jogo.fim`; `Fluxo` aborta `Jogo` e chama `game.clear_game` |
| `tic_view`: `start_level` ao renascer | `tic_view` devolve `"morte"`; `Jogo` cria outro `Nivel` |
| `tic_view`: `begin_exit` + `break` | `tic_view` devolve `"saida"`; `Nivel` chama `cancel_catchup` |
| `tic_intermission`: `advance` | `tic_intermission` devolve `true` |
| `tic_finale`: `finish_finale` | `tic_finale` devolve a ação |
| `G.screen_changed()` + `emit :state` | removido |
| `game.level_gen` para reiniciar a task | mantido só como contador (entra no hash de estado) |
| `main.lua`: laço imperativo | lançador do `main.atm` (`lua5.4 main.lua` continua funcionando) |

### 2.5 O que ficou em Lua, e por quê

- **`game.gamestate` continua existindo**, como "tela exibida". Ele é lido
  pelo redesenho, pela paleta, pelo mouse, pelos cheats (só em jogo), pelo
  menu (Save e End Game) e pelo automapa. Agora só uma função o escreve,
  `G.enter`, chamada apenas pelas tasks de tela. A escrita que sobrou em
  `saveg.apply` é do caminho antigo, usado só quando não há `main.atm`
  (testes unitários com um `game` falso).
- **A transição visual (wipe) continua no redesenho (Lua).** Ela é detectada
  na fase de quadro, comparando a tela atual com a do quadro anterior, e é um
  efeito de apresentação. Movê-la para uma task explícita não muda nenhuma
  decisão de fluxo e aumentaria o risco de mudar a temporização (o wipe pausa
  menu e tela). Fica como passo opcional.
- **O `carry` continua global** (`game.carry`), para preservar um
  comportamento da referência (seção 8.1).

---

## 3. Exemplo comparado: o que acontece depois de um nível

**Antes** (`passo1`): três funções, ligadas por campos globais e chamadas de
lugares diferentes.

```lua
-- G.tic_view (fase de tic)
if game.specials and game.specials.exit_requested then
  game.begin_exit(game)
  return true                       -- o laco faz "break"
end

function game.begin_exit(self)
  ... automapa, segredo, carry ...
  if not commercial and self.mapn == 8 then
    self.finale = finale_mod.new(self)
    self.gamestate = "finale"
    return
  end
  local nxt
  if secret then nxt = 9
  elseif self.mapn == 9 then nxt = ({4, 6, 7, 3})[self.episode] or 1
  else nxt = self.mapn + 1 end
  self.pending_map = nxt
  self.wi = wi_mod.new(self, { ... })
  self.gamestate = "intermission"
end

-- G.tic_intermission (outra fase, tics depois)
if game.wi.done then
  game.wi = nil
  game.advance(game)
end

function game.advance(self)
  if commercial and finale_mod.commercial_map(self.mapn, self.was_secret) then
    self.finale = finale_mod.new(self)
    self.gamestate = "finale"
    return
  end
  if <mapa pending_map nao existe> then
    self.gamestate = "title"; ... limpeza ...; return
  end
  self.mapn = self.pending_map
  self.start_level(self)
end

-- G.tic_finale (outra fase) -> game.finish_finale -> "worlddone": start_level
```

**Depois** (`passo2`): uma task, lida de cima para baixo.

```
task Saida () {
    val secreta = G.end_level()
    ifs {
        (!G.commercial()) && (G.game.mapn == 8) => {
            depois_do_finale(await Finale(true))      ;; fim do episodio
        }
        else => {
            val nxt = proximo_mapa(G.game.episode, G.game.mapn, secreta)
            await Intermissao(nxt)
            ifs {
                G.commercial() && G.commercial_finale() => {
                    depois_do_finale(await Finale(false))   ;; Doom 2
                }
                !G.map_exists(nxt) => false
                else => { G.set_mapn(nxt) ; true }
            }
        }
    }
}
```

O que mudou na leitura:

- A sequência "intermissão, depois finale do Doom 2 ou próximo mapa" está
  numa só construção. Antes ela estava dividida entre `begin_exit` (tic N) e
  `advance` (tic N + k), ligadas pelo campo `pending_map`.
- `nxt` é uma variável local da task, viva enquanto a intermissão dura. No
  Lua ela precisava ser guardada em `game.pending_map` para atravessar os
  tics. O campo ainda existe porque `wi_mod` e o caminho `"worlddone"` o
  leem.
- A volta ao título deixa de ser um efeito colateral espalhado (duas cópias
  da limpeza, em `advance` e `finish_finale`) e passa a ser o fim natural de
  `Jogo` (`G.to_title()` depois do `loop`).

---

## 4. Propriedades do runtime usadas

O fluxo depende de seis propriedades do lua-atmos, verificadas em
`tests/atmos_semantica.atm` (roda antes do teste de equivalência em
`make test-drivers`):

| # | Propriedade | Por que o fluxo precisa |
|---|---|---|
| P1 | Uma task que termina dentro de um `emit` acorda quem a aguarda antes de o `emit` retornar | `Nivel` termina num `:game.tic` e `Jogo` monta o próximo nível no mesmo tic, como o `start_level` síncrono do original |
| P2 | Uma task criada durante um `emit` não recebe esse mesmo `emit` | o `Nivel` novo não roda no tic em que o anterior terminou |
| P3 | `par :any` devolve o valor do ramo que terminou primeiro | `Fluxo` recebe o pedido que encerrou o `Jogo` |
| P4 | `watching` devolve o evento que o encerrou | (usada nos esboços dos próximos passos) |
| P5 | Eventos-tabela com tag hierárquica casam com `:jogo.novo` | pedidos carregam dados (`episode`, `data`) |
| P6 | Ramos de `par` que acordam com o mesmo evento rodam na ordem do código | Quit: o quadro atual é desenhado antes de o programa terminar |

Versões: `atmos-lang dev-4` e `atmos dev-3` (lua-atmos), Lua 5.4.

---

## 5. Validação

### 5.1 Cadeia de equivalência

O modo replay (`DOOM_REPLAY`, em `video.lua`) roda o jogo sem janela, com
tempo simulado (cada `poll` avança um tic) e teclas lidas de um roteiro. A
cada quadro, grava o hash do framebuffer e o hash do estado do jogo:

- tela atual e `leveltime`;
- posição na tabela aleatória (`P_Random`);
- episódio e mapa;
- wipe e menu;
- de cada mobj: posição, ângulo, vida, estado e tics;
- de cada setor: alturas e luz;
- do jogador: vida, armadura, arma e posição da arma.

| Elo | Comparação | Resultado |
|---|---|---|
| branch `lua` → `passo1` | `main.lua` original × `main.lua` do passo 1, só framebuffer (a branch `lua` não tem o hash de estado) | idêntico em 3 roteiros × 5.000 quadros (6 a 7 níveis carregados por roteiro) |
| `passo1` → `passo2` | `main.lua` imperativo (`passo1`) × `atmos main.atm` (atual), framebuffer e estado | idêntico em todos os roteiros (tabela abaixo) |
| `passo1` → `passo2` | o mesmo, com o lançador `lua5.4 main.lua` (atual) | idêntico em todos os roteiros |

| Roteiro | Quadros | Estados distintos | Cobre |
|---|---|---|---|
| `fluxo` | 4.478 | 1.680 | todas as transições (5.2) |
| semente 1 | 4.000 | 2.707 | menu, movimento, tiro, `use`, automapa, `idclev` (4 níveis) |
| semente 2, `exits` | 6.000 | 1.437 | E1M8, finale, volta ao título |

A referência roda com um patch mínimo de teste (`tests/ref-passo1.patch`, 32
linhas). Ele só acrescenta o comando `die` do replay, que não existia quando
a tag foi criada.

### 5.2 Roteiro `fluxo`: cobertura verificada

`tools/make_replay.lua <saida> 0 1 fluxo` gera um roteiro fixo que passa, em
ordem, por:

1. título → New Game → E1M1;
2. saída → intermissão → E1M2;
3. saída secreta → intermissão → E1M9;
4. saída do E1M9 → intermissão → volta ao E1M4;
5. Save Game no slot 5;
6. morte (comando de teste `die`) → renascer no E1M4;
7. Load Game no meio do jogo → E1M4;
8. New Game no meio do jogo → E2M1;
9. `idclev28` → E2M8;
10. saída do E2M8 → finale → título;
11. New Game no título → E2M1;
12. Options > End Game → título;
13. Load Game no título → E1M4;
14. Quit Game.

`tests/test_drivers.sh` confere que cada transição aconteceu de fato:
contagem de pedidos emitidos e de telas montadas. Se o menu não chegar onde o
roteiro pretendia (o menu lembra a última posição de cada submenu), o teste
falha com `COBERTURA INCOMPLETA`.

Saída da execução:

```
identico a passo1: 4478 quadros, 1680 estados distintos (semente 1 fluxo )
  telas (referencia, em ordem):
    vista E1M1 > intermissao E1M2 > vista E1M2 > intermissao E1M9 > vista E1M9 >
    intermissao E1M4 > vista E1M4 > vista E1M4 > vista E1M4 > vista E2M1 >
    vista E2M8 > finale > vista E2M1 > vista E1M4
  pedidos emitidos (atmos):
         2 jogo.carregar
         1 jogo.fim
         3 jogo.novo
         1 jogo.sair
         1 nivel.trocar
  cobertura do fluxo: completa
```

### 5.3 Sensibilidade (mutações)

`tools/mutacoes.py` aplica, uma de cada vez, uma alteração plausível no
`main.atm`, roda o roteiro `fluxo` e compara com a referência.

| Mutação | Erro simulado | 1º quadro divergente | Quadros diferentes |
|---|---|---|---|
| `sem-cancel-catchup` | ao sair do nível, continua recuperando tics atrasados | 297 | 600 |
| `fim-sem-limpeza` | End Game encerra o `Jogo` mas esquece a limpeza | 4.226 | 82 |
| `morte-encerra-jogo` | morrer volta ao título em vez de renascer | 2.278 | 2.201 |
| `secreto-sem-volta` | do mapa 9 vai ao 10 (esquece a volta do secreto) | 1.568 | 3.134 |
| `pedidos-so-no-tic` | pedidos da entrada só emitidos no tic seguinte | 4.051 | 429 |
| `load-mantem-jogo` | Load Game não descarta o jogo em andamento | 2.456 | 2.023 |
| `sair-sem-ultimo-quadro` | Quit termina antes de desenhar o quadro atual | 4.478 | 1 |
| `trocar-ignora-mapa` | `idclev` reinicia o nível atual | 2.820 | 1.659 |
| `wipe-nao-pausa` | durante o wipe, menu e tela continuam andando | 287 | 3.541 |
| `novo-nao-descarta` | New Game no meio do jogo é ignorado | 2.636 | 1.843 |

Resultado: **10/10 detectadas.** Duas mutações sobreviveram, e as duas são
equivalentes (não mudam o comportamento):

- **`menu-depois-da-tela`** (rodar a tela antes do menu dentro do tic):
  `menu.ticker` só altera `skull_tics` e `which_skull` (o cursor), e nenhuma
  fase de tela lê esses campos.
- **`entra-antes-de-montar`** (`G.enter(:view)` antes de montar o nível):
  `build_level` não lê `game.gamestate`. A única leitura fora das telas é
  `am_map.responder`, na fase de entrada.

Isso também é um resultado: o teste mostra quais restrições de ordem
importam (pedidos logo após a entrada, `cancel_catchup`, wipe antes de tudo)
e quais não importam.

### 5.4 Problemas encontrados durante a validação

Registro porque são lições de método, não só de código:

1. **O roteiro antigo não cobria as transições movidas.** Os roteiros do
   passo 1 com `exits` iam direto ao E1M8 e ao finale, e não passavam por
   intermissão comum, saída secreta, morte, load, End Game nem novo jogo no
   meio da partida. O teste ficaria verde sem testar o passo 2. Daí o
   roteiro `fluxo` e a **verificação automática de cobertura**.
2. **O próprio teste causou uma divergência falsa.** A primeira versão do
   roteiro abria o menu de save enquanto a intermissão ainda estava na tela.
   O menu recusava o save, e as teclas seguintes iam parar no Load Game e
   gravavam no slot 0. O slot 0 era o save versionado do usuário
   (`doomsav0.dsg`), na pasta de onde o jogo roda. A execução seguinte via
   outra descrição de slot no menu, e só o framebuffer divergia. Correções:
   - o arquivo do usuário foi restaurado do commit `75c5e67`;
   - **cada execução do teste roda numa pasta isolada**, com links para o
     código e sem saves;
   - o roteiro passou a esperar a intermissão terminar.
3. **Medições improvisadas reaproveitavam a pasta.** Um save de uma execução
   aparecia no menu da seguinte e produzia uma "divergência" do `main.atm`
   do passo 1. Por isso a medição de custo virou um script com pastas
   limpas (`tools/custo_drivers.py`).

Lição para o artigo: no replay determinístico, **arquivos persistentes
(saves) fazem parte do estado de entrada**. Eles precisam ser isolados como
o relógio e o RNG.

---

## 6. Métricas de código

`python3 tools/metricas_passo2.py` (passo1 × árvore atual):

| Métrica | passo1 | passo2 |
|---|---|---|
| Escritas de `game.gamestate` (fora do valor inicial) | 8 | 1 (+1 legado) |
| Pontos que iniciam um nível (`start_level(...)`) | 7 | 1 (+2 legado) |
| Funções Lua que decidem a próxima tela | 4 | 0 |
| Linhas Lua de decisão de tela | 125 | 0 |
| Linhas Lua de apoio (montar telas, pedidos, limpeza) | – | 104 |
| Linhas Atmos de fluxo (tasks e funções de tela) | 42 | 124 |
| Tasks de tela | 5 | 7 (`Titulo`, `Nivel`, `Intermissao`, `Finale`, `Saida`, `Jogo`, `Fluxo`) |

"Legado" são os ramos `-- caminho antigo (sem main.atm)` em `menu.lua`,
`cheats.lua` e `saveg.lua`, que só rodam nos testes unitários com um `game`
falso.

Interpretação, com os números contra também:

- **O total de linhas cresceu** (125 → 104 + 124). A maior parte das 104
  linhas Lua é código movido sem mudança: `begin_exit` tinha 70 linhas, e
  delas saíram `end_level` (25, a parte inicial) e `make_intermission` (33,
  a parte final). As 12 restantes eram a decisão (finale do E1M8, próximo
  mapa) e as escritas de `gamestate`; a decisão foi para o
  Atmos. O crescimento real está no Atmos: as telas passaram de observadoras
  (42 linhas) a donas do fluxo (124).
- **O que diminuiu foi a dispersão.** A tela é trocada por 1 função em vez
  de 8 escritas em 2 arquivos. Um nível é montado em 1 ponto em vez de 7,
  em 4 arquivos. As decisões "o que vem depois" estão num arquivo, na ordem
  em que acontecem.
- **Estado de controle eliminado:** `G.screen_changed` e a comparação de
  `gamestate` e `level_gen` a cada fase deixaram de existir. `pending_map`
  continua só porque `wi_mod` e o `"worlddone"` o leem.

---

## 7. Custo

`python3 tools/custo_drivers.py 5` (roteiro `fluxo`, 4.478 quadros, mínimo
de 5 execuções, pastas limpas, inicialização descontada):

| Driver | ms/quadro | Diferença |
|---|---|---|
| `passo1` `main.lua` (imperativo) | 0,836 | – |
| `passo1` `main.atm` (telas observadas) | 0,915 | +9,5% |
| `passo2` `main.atm` (fluxo em tasks) | 0,976 | +16,9% |

O valor por quadro inclui todo o jogo: lógica, renderer em C e carregamento
de níveis. Um tic dura 28,6 ms (35 Hz), então o custo total do Atmos
(+0,14 ms) equivale a 0,5% de um tic. O passo 2 acrescenta +0,06 ms em
relação ao passo 1. São alguns `emit` a mais por quadro (pedidos, nos dois
pontos de cada tic e depois de cada evento de entrada).

Microbenchmark de tasks (`N=… atmos tools/bench_tasks.atm`): 2,2 µs por
task acordada com 100 tasks, 2,3 µs com 500 e 2,6 µs com 1.000.

---

## 8. Comportamentos preservados e diferenças conhecidas

### 8.1 Bug preservado: o `carry` vaza para um novo jogo

Na versão imperativa, `begin_exit` guarda em `game.carry` o que o jogador
leva para o próximo nível (vida, armas, munição), e `start_level` aplica e
apaga o `carry`. Se o jogador escolhe **New Game** no menu durante a
intermissão, o novo jogo começa com o `carry` do jogo anterior. No Doom
original, `G_InitNew` zera o jogador.

Verificado com um roteiro curto: novo jogo, `idkfa` (todas as armas), saída,
New Game na intermissão. O E1M1 do novo jogo começa com **9 armas**, em vez
de 2 (punho e pistola). O resultado é idêntico na referência e na versão
Atmos.

O comportamento foi mantido para não misturar correção com refatoração, já
que o critério deste passo é a equivalência. A estrutura nova deixa o erro
evidente: o `carry` é um dado do escopo `Jogo` (passa de um `Nivel` ao
próximo), mas vive num global que sobrevive ao `Jogo` abortado. A correção
proposta é um commit separado:

```lua
function G.new_game(episode, mapn, skill)
  game.carry = nil          -- G_InitNew: jogo novo, jogador novo
  ...
end
```

Com essa correção, o teste de equivalência diverge de propósito nesse
roteiro, e a referência precisa ser atualizada.

### 8.2 Diferença num caminho de erro

Antes, `load_game` lia e aplicava o save. Se a aplicação falhasse (nível sem
jogador), o menu tocava "oof" e continuava aberto. Agora `load_game` só lê o
arquivo e pede; a aplicação acontece em `Nivel`. Se ela falhar, o menu já
fechou. Isso só acontece com um save corrompido de um WAD diferente; não foi
exercitado pelos testes.

### 8.3 `idclev` e cheats na mesma tecla

Antes, `idclev` montava o nível novo dentro do `cheats.feed`, e outro cheat
completado pela mesma tecla agiria no nível novo. Agora ele age no nível
antigo, que é descartado em seguida. Nenhuma combinação real de cheats do
Doom completa duas sequências com o mesmo caractere (`idclev` e `idmus`
exigiriam teclas intercaladas, que reiniciam o casamento), então a diferença
é teórica.

---

## 9. Como reproduzir

```sh
git checkout passo2
make                         # modulos em C
make test-drivers            # semantica do Atmos + equivalencia (3 roteiros)
make test-mutacoes           # sensibilidade (tabela 5.3)
make metricas                # tabelas 6 e 7
python3 tools/custo_drivers.py 5
for n in 100 500 1000; do N=$n atmos tools/bench_tasks.atm; done
```

Na primeira execução, `tests/test_drivers.sh` cria o worktree
`build/ref-passo1` a partir da tag `passo1` e aplica `tests/ref-passo1.patch`.
Os logs ficam em `build/drivers/`: `ref.log`, `atm.log` e `lan.log` (um hash
por quadro) e as respectivas saídas `.out`. Para ver um quadro:
`DOOM_REPLAY_DUMP=1450,1460` grava os quadros pedidos em
`<log>.<quadro>.raw`.

---

## 10. Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `main.atm` | fluxo de telas em tasks (`Titulo`, `Nivel`, `Intermissao`, `Finale`, `Saida`, `Jogo`, `Fluxo`), `proximo_mapa`, `pedidos` |
| `main.lua` | passou a ser o lançador do `main.atm` |
| `game.lua` | `game.request`; `begin_exit`, `advance` e `finish_finale` divididos em `end_level`, `make_intermission`, `make_finale`, `to_title` e `clear_game`; `start_level` → `build_level` (sem trocar de tela); fases devolvem resultado; API `G.*` para o fluxo; comando de teste `die` |
| `menu.lua` | New Game e Quit fazem pedidos |
| `cheats.lua` | `idclev` faz pedido |
| `saveg.lua` | `apply` monta com `build_level` e não troca de tela |
| `video.lua` | replay: comando `die`, `DOOM_REPLAY_DUMP` |
| `tests/test_drivers.sh` | referência = tag `passo1` em worktree; execuções isoladas; verificação de cobertura |
| `tests/ref-passo1.patch` | instrumentação de teste para a referência |
| `tests/atmos_semantica.atm` | propriedades P1 a P6 do runtime |
| `tools/make_replay.lua` | roteiro `fluxo` |
| `tools/mutacoes.py`, `tools/metricas_passo2.py`, `tools/custo_drivers.py`, `tools/bench_tasks.atm` | avaliação |
| `Makefile` | `test-drivers`, `test-mutacoes`, `metricas` |
