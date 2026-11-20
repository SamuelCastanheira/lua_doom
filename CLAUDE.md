# CLAUDE.md: contexto para agentes de IA

Guia para continuar o trabalho em `docs/PLANO_ATMOS.md`. Leia este arquivo
inteiro antes de mudar código. Ele resume o que foi descoberto e decidido; os
detalhes de cada passo estão em `docs/registro/`.

O usuário é estudante (TCC sob orientação do Francisco, autor do Céu e do
Atmos) e escreve em **português**. Responda em português.

---

## 1. O projeto em uma página

- **O que é:** um port do Doom para Lua 5.4 (derivado de um port em Python).
  O renderer foi migrado inteiro para C; a lógica de jogo está sendo migrada
  de Lua imperativo (thinkers, como o Doom original) para **concorrência
  estruturada com Atmos**.
- **Objetivo do TCC:** comparar as duas formas de escrever a lógica de jogo
  (expressividade, correção e custo), provando a equivalência por replay
  determinístico.
- **Diretório:** `/home/happyname/dev/lua_doom` (Linux, bash). O WAD é
  `doom.wad` (Doom registrado/Ultimate, episódios 1 a 4), na raiz, e não é
  versionado.

### Branches e tags

| Ref | O que é |
|---|---|
| branch `lua` (`92e6ab3`) | renderer em C, lógica em Lua com thinkers, laço `while` no `main.lua` (original); desde `09d8078`, com o modo replay e o hash de estado (só instrumentação de teste; o hash das telas em `855183a`; o do rosto, do menu e do automapa até `92e6ab3`). Worktree em `build/branch-lua` |
| branch `atmos` | trabalho atual |
| tag `passo1` (`75c5e67`) | `game.lua` em fases, ambiente `atmos.env.doom`, `main.atm` só observando as telas; `main.lua` ainda é o laço imperativo. **É a referência de equivalência atual.** |
| tag `passo2` | fluxo de telas inteiro em tasks Atmos; `main.lua` virou lançador |
| tag `passo3` | specials de setor (luzes, botões, portas, elevadores, pisos, tetos) em tasks (`setores.atm`); comportamento ainda igual ao `passo1` |
| tag `passo4` | a arma (`arma.atm`) e o jogador (`jogador.atm`) em tasks |
| tag `passo5` | o Zombieman em task (`monstro.atm`); laço dos mobjs no `Nivel` |
| tag `passo6` | o wipe como fase do relógio; cada tela desenha a si mesma |
| tag `passo7` | a intermissão e o finale em tasks (`telas.atm`) |
| tag `passo8` | a task `Mundo`, o rosto da barra (`barra.atm`), o menu e o automapa (`interface.atm`). **Estado atual da migração** |
| tag `luaV.1` | marco antigo do usuário (sem relação com a migração) |
| commit `522b06f` | renderer 100% Lua (referência pixel a pixel do renderer em C, usada por `make compare`) |

### Andamento (`docs/PLANO_ATMOS.md`)

| Passo | Situação |
|---|---|
| Renderer em C (3D e 2D) | concluído; idêntico pixel a pixel ao renderer Lua |
| Recursos visuais do Doom original (céu por episódio, texturas animadas, luz de sprites e arma, contraste falso, gama F11, R_CheckBBox) | concluído |
| 1. Ambiente e driver Atmos | concluído (`passo1`) |
| 2. Fluxo de telas em tasks | concluído (`passo2`) |
| 3. Specials de setor (luzes, portas, elevadores, pisos, botões, save) | concluído (`passo3`): subpassos 0, 3a, 3e, 3b, 3c e 3d |
| 4. Arma e jogador | concluído (`passo4`): 4a (arma) e 4c (jogador como task); 4b fica para a fase de correções |
| 5. Um monstro | concluído (`passo5`): o Zombieman como task `Zumbi` |
| 6. Wipe e quadro (opcional) | concluído (`passo6`): o wipe como fase do relógio; cada tela desenha a si mesma |
| 7. Intermissão e finale | concluído (`passo7`): tasks `Contagem` e `Texto` (`telas.atm`) |
| 8. Mundo, barra, menu, automapa | concluído (`passo8`): itens A5, A2, A1 e A3 do plano (o A4 ficou de fora) |

---

## 2. Arquitetura

```
 main.lua ──(lancador)──> main.atm  (Atmos: entrada, relogio, quadro, fluxo de telas)
                             │ require
                             ├── atmos/env/doom/init.lua   (ambiente: poll, tics, frame)
                             └── game.lua                  (estado, regras, fases, API G.*)
                                   │ require
   menu  player  enemy  thinker  specials  collision  saveg  cheats  status
   am_map  finale  wi_stuff  wipe  sound  world  info  sprites  render  ...  (Lua)
                                   │
   C:  render_c (src/render/*.c)   r_data_c   tables_c   framebuffer_c (+ src/v_draw.c)
       video_c (SDL2 + SDL2_mixer: janela, paleta/gama, audio, musica)
```

### 2.1 Módulos em C (`src/`, compilados como `.so` na raiz)

| Módulo | Fonte | Papel |
|---|---|---|
| `render_c` | `src/render/r_*.c`, `r_local.h` | renderer 3D inteiro: BSP, `R_CheckBBox`, paredes, visplanes, céu, masked, sprites e arma; userdata `Renderer` |
| `r_data_c` | `src/r_data_c.c`, `src/r_data.h` | texturas, flats, colormaps, sprites; `prepare_render`, `update_anims`, `set_sky` |
| `tables_c` | `src/tables_c.c` | `finesine`, `finetangent`, `tantoangle` (idênticas às do `tables.lua`) |
| `framebuffer_c` | `src/framebuffer_c.c`, `src/v_draw.c` | framebuffer 320×200 indexado; desenho 2D (`draw_patch`, `am_line`, `fill_flat`, `copy_span`…); `framebuffer_c.hash` (FNV-1a) |
| `video_c` | `src/video_c.c`, `src/gammatable.h` | SDL2: janela, eventos, paleta com gama (`set_gamma`), áudio, MIDI |
| `test_fixed_c` | `tests/test_fixed_c.c` | só testes |

O renderer usa aritmética que **espelha a do `compat.lua`**: um tipo `lnum`
(`int64_t`) com wrap de 32 bits nos mesmos pontos (`r_i32`, `r_shar`,
`r_fixed_mul`, `r_fixed_div`). Não troque por `int32_t` puro sem rodar
`make compare`. A compilação usa `-fwrapv`.

### 2.2 `game.lua`: o jogo sem laço e sem fluxo

`game.new(argv)` monta tudo (WAD, recursos, renderer, menu, status, som,
vídeo) e devolve a tabela **`G`**, a API usada pelo `main.atm`. O estado do
jogo fica em `G.game` (a tabela `game`, lida por todos os módulos).

Um quadro tem três fases, sempre nesta ordem:

```
1. G.handle_input(ev)        para cada evento
2. ate 4 tics:   na transicao de tela: G.tic_wipe() (fase do relogio, passo 6)
                 senao: emit :menu.tic (task Menu, passo 8c), depois a tela atual:
                        G.tic_view_antes()   -> "segue" | "parado"
                          emit :automapa.tic   (Nivel; task Automapa, 8d)
                          emit :mundo.tic      (Nivel; task Mundo, 8a): tic_comando,
                                               :game.jogador, tic_view_meio, mobjs,
                                               :game.specials, tic_mundo_fim
                          emit :barra.tic      (Nivel; task Rosto, 8b)
                        G.tic_view_depois()  -> nil | "saida"
                        intermissao e finale: tasks Contagem e Texto
                        (telas.atm, passo 7), que acordam com :game.tic
3. G.quadro_antes()          (emit :game.frame: a tela viva desenha a si mesma)
   G.quadro_depois()         wipe, menu, paleta (emit :tela.transicao se o wipe comecou)
   G.quadro_fim()            som, present
```

API do fluxo, chamada só pelo `main.atm`:

| Função | O que faz |
|---|---|
| `G.take_requests()` | devolve e esvazia a fila de pedidos (`game.request`) |
| `G.enter(tela)` | **único** lugar que escreve `game.gamestate` (`"title"`, `"view"`, `"intermission"`, `"finale"`) |
| `G.initial_request()` | `-warp`: pedido `jogo.novo` inicial, ou `nil` |
| `G.new_game(ep, mapn, skill)`, `G.set_level(ep, mapn)`, `G.set_mapn(m)` | mudam `game.episode/mapn/skill` |
| `G.start_level()` / `G.load_level(data)` | montam o nível (`game.build_level`) / a partir de um save (`saveg.apply`) |
| `G.end_level()` | fim do nível sem decisão: automapa, saída secreta, `carry`; devolve `true` se secreta |
| `G.make_intermission(nxt)`, `G.make_finale(anuncia)` | montam as telas |
| `G.commercial()`, `G.commercial_finale()`, `G.map_exists(m)` | consultas para decidir o fluxo |
| `G.to_title()`, `G.end_game()` | limpeza ao voltar ao título (fim natural / "End Game") |
| `G.state_string()` | resumo do estado para o hash do replay |

### 2.3 `main.atm`: o fluxo de telas (passo 2)

```
Fluxo ── Titulo                     devolve o pedido (jogo.novo | jogo.carregar)
     └── Jogo(pedido)               niveis em sequencia ate o fim do episodio
          ├── Nivel(save)           uma instancia de nivel -> [fim=:morte|:saida|:trocar]
          └── Saida()               -> true (continua) | false (titulo)
               ├── Intermissao(nxt)
               └── Finale(anuncia)  -> "title" | "worlddone"
```

Mais três tasks no nível superior: **entrada** (`loop ev on :input`),
**relógio** (`loop on :tic`) e **quadro** (`loop on :frame`), dentro de um
`par :any` com o `Fluxo` e o tratamento do `:jogo.sair`.

### 2.4 O ambiente `atmos/env/doom/init.lua`

A cada `step()`, emite nesta ordem:
1. um evento por entrada: `{tag="input.key.down"|"input.key.up"|"input.mouse"|"input.quit", key=, ...}`;
2. de 0 a 4 `{tag="tic", n=}` (35 Hz, acumulador igual ao laço original);
3. `"frame"`.

O relógio real (números em µs) **não é emitido de propósito** (commit
`14ac179`): `await 1s` e `loop on 1s` nunca acordam, em vez de quebrarem o
determinismo do replay.

`env.cancel_catchup()` interrompe os tics restantes do `step` (usado quando
o nível termina, como o `break` do laço original).

### 2.5 Modo replay (`video.lua`)

`DOOM_REPLAY=<roteiro>` substitui o `video_c`: sem janela nem som, cada
`poll()` avança exatamente um tic, as teclas vêm do roteiro, e cada
`present()` grava `quadro hash_framebuffer hash_estado` em `DOOM_REPLAY_OUT`.
Também fixa `math.randomseed(1)`.

Formato do roteiro (uma linha por evento; quadro = número do `poll`, a
partir de 1):

```
40 escape down
41 escape up
200 exit            # comando de teste: termina o nivel (switch de saida)
300 exit secret     # saida secreta
500 die             # comando de teste: o jogador morre
600 use 136         # comando de teste: "use" na linha 136 do WAD (passo 3e)
700 cross 602       # comando de teste: cruza a linha 602 pela frente (passo 3b)
800 goto 672 -352   # comando de teste: poe o jogador no ponto (x, y) do mapa (passo 3d)
900 quit            # fecha a janela
```

`DOOM_REPLAY_DUMP=1450,1460` grava esses quadros em
`<DOOM_REPLAY_OUT>.<quadro>.raw` (64.000 índices de paleta).

`DOOM_REPLAY_SIDES=1` acrescenta ao hash de estado as texturas e o
deslocamento de todos os lados (passo 3e: um botão só muda uma textura de
lado, e sem isso as mutações de botão sobreviviam). `tests/test_drivers.sh`
e `tools/mutacoes.py` ligam; `tools/custo_drivers.py` não liga, porque o
hash dos lados é caro e falsearia o custo. Desde o passo 3d, o mesmo
`DOOM_REPLAY_SIDES=1` acrescenta as texturas de chão e teto de cada setor
(o donut e o "baixar e trocar" mudam o `floorpic`).

**Tics aos pares no replay.** O relógio do replay soma `1000/35` por
`poll`; pelo arredondamento, a partir de certo ponto os quadros alternam 0 e
2 tics. Toda entrada do roteiro cai no início de um par, e o primeiro tic do
par nunca é desenhado. Um efeito de um tic só aparece no quadro se cair no
segundo; deslocar a entrada em quadros não muda isso (passo 3d, mutação
`specials-no-fim-do-tic`).

---

## 3. Atmos na prática

Versões: `atmos-lang dev-4` (linguagem, CLI `atmos v0.8`), `atmos dev-3`
(lua-atmos, runtime), `f-streams 0.2-4`, em `/usr/local/share/lua/5.4/atmos/`.
A linguagem compila para Lua; um `.atm` pode fazer `require` de módulos
`.lua` normalmente.

### 3.1 Sintaxe, com exemplos reais do `main.atm`

```
val env  = require "atmos.env.doom"        ;; val = constante, var = variavel
val G    = game.new(game.atmos_args(arg))
;; comentario de linha

func pedidos () {                          ;; funcao comum
    loop _, r in G.take_requests() {       ;; laco sobre tabela
        emit(r)                            ;; emit de uma variavel: com parenteses
    }
}

val VOLTA_DO_SECRETO = [4, 6, 7, 3]        ;; tabela/vetor (1-based)
func proximo_mapa (episode, mapn, secreta) {
    ifs {                                  ;; ifs e expressao: devolve o ramo
        secreta       => 9
        (mapn == 9)   => (VOLTA_DO_SECRETO@episode) || 1   ;; @ indexa; || com nil
        else          => mapn + 1
    }
}

task Nivel (save) {                        ;; task: a ultima expressao e o retorno
    if save { G.load_level(save) } else { G.start_level() }
    G.enter(:view)                         ;; :view e a string "view"
    spawn {                                ;; task transparente no escopo do Nivel
        loop on :game.specials { G.specials_resto() }
    }
    par :any {                             ;; termina quando o 1o ramo termina
        loop on :game.tic {                ;; acorda a cada evento :game.tic
            val antes = G.tic_view_antes()
            val fim = ifs {
                (antes == :segue) => {
                    emit :game.specials    ;; alcanca so a subarvore do Nivel
                    G.tic_view_depois()
                }
                (antes == :morte) => :morte
                else => nil
            }
            if fim == :saida {
                env.cancel_catchup()
            }
            until (fim, [fim=fim])         ;; sai do loop devolvendo o valor
        }
    } with {
        val t = await :nivel.trocar        ;; espera um evento; devolve o evento
        [fim=:trocar, episode=t.episode, mapn=t.mapn]   ;; tabela com campos
    }
}

task Jogo (pedido) {
    var save = nil
    loop {
        val r = await Nivel(save)          ;; inicia a task filha e espera o fim
        set save = nil                     ;; atribuicao sempre com "set"
        val continua = ifs {
            (r.fim == :morte)  => true
            (r.fim == :trocar) => {        ;; bloco: o valor e a ultima expressao
                G.set_level(r.episode, r.mapn)
                true
            }
            else => await Saida()
        }
        until (!continua)
    }
    G.to_title()
}

spawn {                                    ;; task anonima no escopo atual
    loop ev on :input {                    ;; o evento vai para "ev"
        G.handle_input(ev)
        pedidos()
    }
}
```

Outras construções usadas pelo usuário (repositório
`SamuelCastanheira/pico-tcc`, pasta `src/codes_tcc/atmos_ilha_geladeira`) e
nos testes:

```
pin puffles = tasks(10)                    ;; pool ligada ao escopo
spawn @(puffles) Puffle(...)               ;; spawn em pool (exige task NOMEADA)
emit @2 :puffle.entrou                     ;; emit com alcance (2 niveis acima)
watching :parar { ... }                    ;; executa o bloco ate o evento
loop in 3 { ... }                          ;; repete N vezes
match v { :CENTRO => ... :SAIR => break() }
await until (num_capturados == 10)
await <:jogo.novo || :jogo.carregar>       ;; padrao composto (usado no main.atm)
loop on 1s { ... }                         ;; relogio real: NAO usar no jogo
```

### 3.1.1 Recursos do Atmos para o passo 3

Lidos no manual (`github.com/atmos-lang/atmos`, `doc/manual.md`) e no
runtime instalado (`/usr/local/share/lua/5.4/atmos/run.lua` e `init.lua`):

| Recurso | Uso previsto |
|---|---|
| `spawn_in(pool, T, ...)` (função global, chamável de **Lua puro**) | `specials.lua`/`collision.lua` criam a task da porta no meio do tic. O spawn é **síncrono**: a task roda até o primeiro `await` antes de voltar ao Lua (P8), então `sector.specialdata` fica marcado na hora e `use_special` devolve o resultado sincronamente (o `enemy.lua:345` usa o retorno). `spawn` não aborta ninguém, então não fere a regra 4.3. |
| `task` como expressão | a task corrente: `set setor.specialdata = task` |
| `defer { ... }` | limpar `specialdata` no fim **ou** no aborto (fim de nível) |
| `emit @t (e)` | evento direcionado (por exemplo, `:reabrir` à porta do setor) |
| `toggle t(false)` / `toggle t(true)` | elevador "em estase" do Doom (`P_StopPlat` / `P_ActivateInStasis`): a task fica viva, surda a eventos, e retoma de onde parou |
| `tasks(n)` | pool com limite (como `MAXPLATS`, `MAXCEILINGS`, `MAXBUTTONS`); spawn em pool cheia devolve `nil` |
| `loop _, t in pool`, `t.pub`, `#pool` | percorrer as tasks vivas (save, passo 3f) |
| `abort(t)` | encerrar uma task de fora |

Cuidados:
- **Toda task que termina emite um evento** (a própria task) para o escopo
  pai (`task_result` em `run.lua`). Cada porta que fecha gera um `emit`
  extra: não use `await(true)` (qualquer evento) em `Nivel`, e conte isso no
  custo.
- **O alcance padrão do `emit` é a task corrente** (não global). Um
  `:game.specials` emitido em `Nivel` só alcança a subárvore de `Nivel`.
- **O custo do `emit` é proporcional à subárvore que ele percorre.** Um
  evento que só uma task escuta deve ser direcionado (`emit @(t) (:ev)`, com
  a task guardada em `pin t = spawn ...`; `val` não serve). No passo 8, os
  quatro eventos novos por tic com o alcance padrão custavam +13%;
  direcionados, +3,4%. `emit @1 (:ev)` alcança o escopo do pai (uma task
  irmã).
- **Um `spawn` dentro de `if c { ... }` fica preso ao bloco do `if`** e é
  abortado quando ele termina. Em `Nivel`, crie tasks nas pools
  (`spawn @pool` ou `spawn_in`), não em blocos condicionais.
- **Versão:** o repositório já está na v0.9 em desenvolvimento (muda o
  recolhimento de pools com `atmos.gc` e o evento de fim de task). Não
  atualize no meio do TCC; se atualizar, rode `make test-drivers` antes e
  depois.

### 3.2 Armadilhas de sintaxe (todas já aconteceram)

| Errado | Certo |
|---|---|
| `a or b`, `a and b`, `not a` | `a \|\| b`, `a && b`, `!a` |
| `"a" .. "b"` | `"a" ++ "b"` |
| `t[k] = v`, `t[#t+1] = v` | `set t@k = v`, `set t@(#t+1) = v` |
| `until true` | `until (true)`; com valor: `until (cond, valor)` |
| `spawn @(pool) { ... }` | `spawn @(pool) NomeDaTask(...)` |
| `x = 1` (atribuição) | `set x = 1` |
| `emit r` com variável | `emit(r)` |
| misturar operadores sem parênteses | `(!G.commercial()) && (G.game.mapn == 8)` |

### 3.3 Propriedades do runtime de que o código depende

Verificadas em `tests/atmos_semantica.atm` (`atmos tests/atmos_semantica.atm`):

- **P1.** Uma task que termina dentro de um `emit` acorda quem a aguarda
  antes de o `emit` retornar, o que torna as transições síncronas.
- **P2.** Uma task criada durante um `emit` não recebe esse mesmo `emit`.
- **P3.** `par :any` devolve o valor do ramo vencedor.
- **P4.** `watching` devolve o evento que o encerrou.
- **P5.** Eventos-tabela com tag hierárquica casam com `:a.b`; `await :a`
  casa com `a.qualquer`.
- **P6.** Ramos que acordam com o mesmo evento rodam na ordem do código.
- **P7.** Pools declaradas em sequência acordam na **ordem de declaração**
  (não na de criação das tasks); dentro de cada pool, na ordem de criação.
  Uma task transparente declarada entre duas pools acorda entre elas
  (luzes → scroll → movers). No runtime: o `emit` percorre `t._.dns` em
  ordem de índice.
- **P8.** `spawn_in(pool, T, ...)` chamado de uma função Lua roda a task até
  o primeiro `await` antes de voltar ao Lua.
- **P9.** Uma task criada durante o evento A acorda no evento B seguinte,
  mesmo no mesmo tic. Uma task criada durante B, por outra task da mesma
  pool, só acorda no próximo B. No runtime: cada `emit` incrementa
  `M.TIME` e só acorda tasks com `t._.time < time`; o laço é
  `for i = 1, #t._.dns`, com o tamanho fixado no início, como o
  `for i = 1, #self.thinkers` do `M.tick`.

Os testes P7 e P9 foram conferidos com mutantes: invertendo a ordem das
pools, o P7 falha; tirando o `await` inicial da task, o P9 falha.

### 3.4 CLI e execução

- `atmos main.atm -- -fps -scale 4`: o **`--` é obrigatório**, senão o
  `atmos` tenta ler `-fps` como opção dele.
- No `atmos`, o nome do script fica em `arg[1]` e o `--` em `arg[2]`;
  `game.atmos_args(arg)` remove os dois.
- `lua5.4 main.lua ...` roda o mesmo jogo: o `main.lua` chama
  `atmos.loop(atm_loadfile("main.atm"))` (de `atmos.lang.exec`).
- O runtime registra um searcher: `require "x"` encontra `x.atm`.

---

## 4. Regras rígidas (quebrar qualquer uma faz o replay divergir)

### 4.1 Tempo em tics

Tudo no Doom é contado em tics de 35 Hz. Use `:tic` ou `:game.tic` e, para
esperar, `loop in n { await :game.tic }`. **Nunca** use `await 2s` nem
`loop on 1s` na lógica de jogo: são relógio real e quebram o determinismo.

### 4.2 A ordem dentro do tic é semântica (`P_Random`)

`random.lua` é a tabela fixa de 256 valores do Doom (`P_Random`). Ela é
consumida na ordem em que as entidades pensam. Se a ordem mudar, a sequência
aleatória muda e o jogo diverge.

Ordem atual de um tic de nível (`G.tic_view_antes`, 1 e 2;
`emit :game.jogador`, 3; `G.tic_view_meio`, 4 a 6; `emit :game.specials`, 7;
`G.tic_view_depois`, 8 a 11):
1. automapa
2. comando do jogador (`build_ticcmd`)
3. `emit :game.jogador` em `Nivel`: a task `Jogador` (`jogador.atm`, passo
   4c). Vivo: `mover`, `pisar`, `usar`, `escolher_arma`, `contar_poderes`,
   `contar_avisos` (partes em `player.lua`) e então `emit :jogador.arma`,
   que acorda a filha `Arma` (`arma.atm`; ramo do clarão antes da fase, P6).
   Morto: `cair`, `emit :jogador.arma`, "use" → `PST_REBORN`. No Doom a arma
   ficava no meio do `P_PlayerThink`; depois de tudo é equivalente (mutação
   `arma-no-meio-do-jogador`, em `EQUIVALENTES`)
4. `player_mod.tick_fx`
5. renascer? → `"morte"`
6. os mobjs, na ordem de `world.mobjs` (passo 5: o laço `mobjs()` fica no
   `Nivel`; o Zombieman recebe `emit @(mo.task) (:mobj.tic)` na sua posição,
   os outros chamam `mobj_thinker` por `G.mobj_pensar`)
7. `emit :game.specials` em `Nivel`. Acorda, na ordem de declaração em
   `Nivel` (P7):
   1. pool `luzes` (tasks de `setores.atm`, passo 3a), na ordem dos setores;
   2. a task que chama `G.specials_resto()` → `specials_mod.tick`, que só
      faz as linhas com scroll (efeito 48);
   3. pool `movers` (passo 3b), na ordem de criação: portas (task `Porta`),
      elevadores (task `Elevador`, 3c), pisos (task `Piso`, 3d) e tetos
      (task `Teto`, 3d);
   4. pool `botoes` (task `Botao`, passo 3e), na ordem de criação.
8. `res:update_anims(leveltime)`
9. saída? → `"saida"`
10. `leveltime + 1`
11. `status_mod.ticker`

Fora do nível, o relógio do `main.atm` tem duas fases (passo 6): na
transição de tela (depois de `:tela.transicao`, emitido pelo quadro) só
`tic_wipe`, até ela terminar; fora dela,
senão `tic_menu`, `pedidos()`, `emit :game.tic`, `pedidos()`.

Ao transformar thinkers em tasks:
- **Pools em ordem de criação:** faça `spawn @(pool)` na mesma ordem em que
  a lista Lua recebia itens, e declare as pools na ordem das fases do
  `M.tick` (P7).
- **Emit direcionado:** para entidades misturadas numa lista
  (`world.mobjs`), mantenha o laço Lua e faça `emit @(mo.task) :mobj.tic`.
- **Criar a partir do Lua:** use `spawn_in(pool, T, ...)` no ponto em que o
  Lua hoje acrescenta o thinker à lista (seção 3.1.1, P8). A fila de pedidos
  da regra 4.3 não serve aqui: ela só é esvaziada depois do `:game.tic`, e a
  task nasceria tarde demais.
- **Toda task de setor começa com `await`** do evento da sua fase, antes de
  mexer no setor. O thinker original se mexe na **próxima fase de specials**
  depois de criado: no **mesmo tic** se foi criado pelo jogador (etapa 3) ou
  por um monstro (etapa 6), como no Doom (`P_PlayerThink` antes de
  `P_RunThinkers`); no tic seguinte só se foi criado durante a própria fase
  de specials. O `await` inicial reproduz exatamente isso (P9).
- `luzes` do tipo flash e fire consomem `P_Random`: a ordem é crítica.

### 4.3 Fila de pedidos: o Lua nunca emite

Funções Lua que querem mudar o fluxo **registram um pedido**:

```lua
game.request("jogo.novo", { episode = 1, mapn = 1, skill = 2 })
game.request("jogo.carregar", { data = data })
game.request("jogo.fim")
game.request("nivel.trocar", { episode = e, mapn = m })
game.request("jogo.sair")
```

O `main.atm` emite os pedidos com `pedidos()` **nas fronteiras de fase**:
depois de cada `handle_input`, depois de `tic_menu` e depois de
`emit :game.tic`. Motivo: um `emit` de dentro de uma chamada Lua poderia
abortar a task que fez a chamada, e o restante do código Lua não rodaria.
Para novos eventos que precisem sair do Lua, use o mesmo mecanismo.
Criar tasks é diferente: `spawn_in` a partir do Lua é permitido, porque
não aborta ninguém (regra 4.2).

### 4.4 Outras fontes de não determinismo

- `math.random` (usado em `wipe.lua` e `wi_stuff.lua`): só é determinístico
  porque o replay fixa a semente. Na lógica de jogo, use `random.p_random()`
  ou `enemy.p_random()`.
- **Saves são estado de entrada.** O jogo salva em `doomsavN.dsg` na pasta
  do IWAD (a pasta de onde roda). Um arquivo deixado por uma execução
  aparece no menu da seguinte e muda o framebuffer. Por isso
  `tests/test_drivers.sh` e as ferramentas rodam cada execução numa **pasta
  isolada** (links para o código, sem `.dsg`).
- **Nunca rode roteiros na raiz do repositório:** `doomsav0.dsg` é um save
  versionado do usuário. Ele já foi sobrescrito uma vez por um teste e
  restaurado do commit `75c5e67`.
- Iterar com `pairs` sobre tabelas com chaves-objeto tem ordem que pode
  variar entre processos. Evite isso em código que afete o estado.

---

## 5. Comandos

### 5.1 Build e jogo

```sh
make                       # compila os modulos C (release)
make debug                 # -O0 + AddressSanitizer/UBSan (troca .so; "make" volta)
make help                  # mostra o que foi detectado (Lua, SDL, plataforma)

lua5.4 main.lua -fps -scale 4              # comando habitual do usuario
atmos main.atm -- -fps -scale 4            # equivalente
make run ARGS="-fps -scale 4 -warp 1 3"
```

Opções do jogo: `-iwad`, `-file`, `-warp E M`, `-skill N`, `-scale N`,
`-fps`, `-crt`, `-nomonsters`, `-fast`, `-respawn`, `-nosound`, `-nomusic`,
`-nocheats`.

Teclas: F11 é a gama, F12 liga e desliga o contador de FPS, Tab abre o
automapa, `-`/`=` mudam o tamanho da tela.

### 5.2 Equivalência da lógica (driver Atmos × referência)

```sh
make test-drivers          # semantica do Atmos (P1-P9) + 11 roteiros contra a tag passo1; saves comparados byte a byte
sh tests/test_drivers.sh 0 1 fluxo         # roteiro com todas as transicoes
sh tests/test_drivers.sh 4000 1            # pseudoaleatorio, 4000 quadros, semente 1
sh tests/test_drivers.sh 6000 2 exits      # tambem termina niveis
sh tests/test_drivers.sh 1200 1 luzes -warp 4 1   # passo 3a: E4M1 e E1M2 parados
sh tests/test_drivers.sh 0 1 botoes -warp 1 1     # passo 3e: switches, save e load
sh tests/test_drivers.sh 0 1 portas -warp 1 1     # passo 3b: portas em cada fase, save e load
sh tests/test_drivers.sh 0 1 elevadores -warp 1 3 # passo 3c: elevadores em cada fase, parados, save e load
sh tests/test_drivers.sh 0 1 pisos -warp 2 2      # passo 3d: pisos, escadas, donut, esmagadores (jogador embaixo), save e load
sh tests/test_drivers.sh 0 1 arma -warp 1 1       # passo 4: cada arma, trocas, sem municao, save e load no tiro, morte e renascer
sh tests/test_drivers.sh 0 1 monstro -warp 1 2 -respawn  # passo 5: zumbis em todos os comportamentos, save e load, pesadelo
sh tests/test_drivers.sh 0 1 telas -warp 1 1      # passo 7: intermissao acelerada e completa, E1M8, finale
REF_TAG=passo2 sh tests/test_drivers.sh 0 1 fluxo   # outra referencia
```

- Argumentos: `quadros semente [exits|fluxo] [args do jogo]`.
- A referência é **`REF_TAG`** (padrão `passo1`). O script cria um worktree
  em `build/ref-<tag>`, aplica `tests/ref-<tag>.patch` se existir, compila e
  roda o `lua5.4 main.lua` de lá. Compara com `atmos main.atm` e com
  `lua5.4 main.lua` atuais.
- **`make test-branches`** compara a branch `lua` com a `atmos` nos 11
  roteiros (`REF_TAG=lua REF_DIR=build/branch-lua`): idênticas, com o estado
  completo (`docs/registro/08-branch-lua-replay.md`). É o teste da fase de
  correções: cada correção nas duas branches, e elas continuam iguais.
- O roteiro `fluxo` confere a cobertura: pedidos e telas esperados. Se você
  mudar o menu ou os tempos, ajuste `tools/make_replay.lua` até aparecer
  `cobertura do fluxo: completa`.
- Saídas em `build/drivers/`: `ref.log`, `atm.log`, `lan.log` (hashes) e
  `*.out` (stdout de cada driver).

**Quando o passo mudar o comportamento de propósito** (por exemplo,
corrigir o bug do `carry`), a comparação com `passo1` vai divergir.
Documente a divergência esperada, crie uma tag nova e use-a como `REF_TAG`.
Se a tag nova não tiver algum comando de teste do replay, crie
`tests/ref-<tag>.patch`.

### 5.3 Sensibilidade, métricas e custo

```sh
make test-mutacoes         # tools/mutacoes.py: 82/85 detectadas, 6 equivalentes, 3 pendentes
make metricas              # tools/metricas_passo2.py + tools/custo_drivers.py
python3 tools/metricas_finais.py --custo --memoria   # tabelas finais de todos os passos (le build/test-drivers.log e build/mutacoes.log)
python3 tools/custo_drivers.py 5           # ms/quadro dos 3 drivers
N=500 atmos tools/bench_tasks.atm          # custo por task acordada
```

Para um passo novo: acrescente mutações em `tools/mutacoes.py` (trecho
original → trecho mutado). Se uma sobreviver, ou o roteiro não cobre aquilo
ou o mutante é equivalente; neste caso, ponha em `EQUIVALENTES` com a
justificativa.

### 5.4 Renderer (só quando mexer em C)

```sh
make compare MAP=1 SPRITES=full BLOCKS=10 DETAIL=0   # pixel a pixel x renderer Lua (522b06f)
make baseline              # congela quadros atuais do renderer C (com tags por pixel)
make check-baseline        # o que mudou, por tipo de superficie (parede, flat, ceu...)
lua5.4 tests/test_v_draw.lua                          # desenho 2D x versao Lua original
lua5.4 tools/dump_screens.lua build/screens/cur       # telas 2D (menu, automapa, finale, wipe)
```

### 5.5 Testes unitários

```sh
make test                  # tests/test_*.lua: 12 passam, 8 falham (falhas conhecidas)
```

As 8 falhas existiam antes da migração, e não são regressões:
`test_c_data`, `test_enemy`, `test_menu`, `test_player`, `test_r_data`,
`test_specials`, `test_view` e `test_world`. A maioria espera o `doom1.wad`
shareware (125 texturas, 467 vértices) ou o antigo `r_data.lua`. Compare
**antes e depois** da sua mudança; o resultado tem de ser o mesmo.

---

## 6. Ambiente e dependências

| Item | Versão / caminho |
|---|---|
| Lua | 5.4.6 (`lua5.4`); `pkg-config lua5.4` |
| Atmos | `atmos-lang dev-4`, `atmos dev-3`, `f-streams 0.2-4` (luarocks, `/usr/local/lib/luarocks/rocks-5.4`, código em `/usr/local/share/lua/5.4/atmos/`) |
| SDL | SDL2 2.30.0, SDL2_mixer 2.8.0 |
| Compilador | gcc 13.3 |
| Python | 3, com Pillow 10.2 (só para PNGs e comparações) |
| Ferramentas ausentes | `curl` (para baixar, use `python3 urllib`) |
| Fonte do Doom original | `github.com/id-Software/DOOM`, `linuxdoom-1.10/` (consultado para `p_spec.c`, `r_bsp.c`, `v_video.c`, `g_game.c`…) |

O `Makefile` funciona em Linux, macOS e MSYS2 (Windows). O `video_c.dll`
versionado é antigo (sem a gama); no Windows, recompile.

---

## 7. Armadilhas de runtime já encontradas

| Sintoma | Causa | Como evitar |
|---|---|---|
| `unknown option '-n'` ao rodar `atmos` | faltou o `--` | `atmos main.atm -- -nosound` |
| `main.lua` divergia de si mesmo no wipe | `math.random` sem semente | o replay fixa a semente; na lógica, use `P_Random` |
| Divergência só no framebuffer, a partir de um save | arquivo `.dsg` de outra execução aparecia no menu | executar em pasta isolada (o script já faz) |
| Roteiro "não fazia" save, load ou End Game | menu aberto durante a intermissão; menu lembra a posição de cada submenu (`last_on`); o menu de load tem posição própria, separada da do save | esperar a tela terminar (padrão `exit_level` em `make_replay.lua`); conferir a cobertura |
| `attempt to index a number (src)` em `damage_mobj` | ordem dos argumentos | `game.damage_mobj(alvo, origem, dano, inflictor)` |
| Script sh terminava calado | `shift 3` com menos argumentos aborta no `dash`; `trap` devolvia 0 | laço de `shift`; `trap` preservando `$?` |
| `Terminated` ao testar janela | `\| head` no comando de teste | testar com `kill -TERM` e `wait`; o jogo fecha limpo ("janela fechada") |
| Task agindo uma fase antes do thinker | a task age no próprio spawn, antes do evento da sua fase | começar a task com `await` (regra 4.2, P9) |
| Medição de custo com "divergência" | pasta reaproveitada com save residual | `tools/custo_drivers.py` (pastas limpas) |

---

## 8. Comportamentos conhecidos (não "consertar" sem decidir)

Lista completa do que difere do Doom original (specials, save, som, demos,
multiplayer): `docs/DIFERENCAS_DOOM.md`. Ao corrigir algo, mova o item para
a seção "Corrigido" desse arquivo.

**Nada disso é corrigido antes do fim de todos os passos** (decisão do
usuário). Durante os passos, só acrescente itens ao
`docs/DIFERENCAS_DOOM.md` (diferenças do Doom na seção certa; bugs e
revisões do próprio port na seção 5). No fim, as correções são feitas nas
**duas** branches, `atmos` e `lua`, com nova referência a cada correção.

- **Bug preservado:** o `carry` de um nível vaza para um novo jogo iniciado
  na intermissão (o novo jogo começa com as armas do anterior). Correção
  proposta: `game.carry = nil` em `G.new_game`, num commit separado, com nova
  referência. Detalhes no registro do passo 2, seção 8.1. Alternativa que
  expressa a causa (o `carry` pertence ao escopo `Jogo`):
  `defer { G.game.carry = nil }` no início de `task Jogo`, que roda também
  quando o `Jogo` é abortado por `:jogo.novo`.
- `game.gamestate` continua existindo (tela exibida, lida por redesenho,
  paleta, mouse, cheats, menu e automapa), mas só `G.enter` o escreve.
- O wipe (a imagem) continua em Lua (`wipe.lua`); desde o passo 6 a
  transição é uma fase do relógio, e a troca de tela ainda é detectada no
  quadro, comparando `wipe_state` com `gamestate` (equivalência).
- Ramos `-- caminho antigo (sem main.atm)` em `menu.lua`, `cheats.lua` e
  `saveg.lua` existem para os testes unitários com um `game` falso. Não
  remova.
- Animação da arma usa tabelas próprias em `player.lua` (`WEAPON_PATCH`,
  `WEAPON_READY`, `WEAPON_ATK`), não a máquina de estados do `p_pspr.c`. Isso
  é o passo 4.
- Sprites e arma usam a luz do setor (como o Doom); flashes de arma
  (`PISFA0`, `SHT2I0`…) são `FF_FULLBRIGHT`, lidos de `info.STATES`.

---

## 9. Passos 3 a 8 e métricas finais concluídos; próximo: correções e escrita

**Passo 4a (feito):** a arma como task `Arma` (`arma.atm`), por
equivalência com a lógica de `player.lua` (as tabelas `WEAPON_*` e as
partes de um tic continuam lá). No 4a, `player.think` foi partido em
`think_antes` e `think_depois`, com `emit :game.arma` entre os dois; o 4c
trocou isso pela task `Jogador` (abaixo), e a `Arma` passou a acordar com
`:jogador.arma`. A fase continua em `psprite_state` (renderer, save e hash
a leem; o Lua escreve `pendingweapon` no meio do tic). O clarão é um ramo do
`par`, **antes** da fase (P6). O hash (com `DOOM_REPLAY_SIDES=1`) inclui
todos os campos da arma; roteiro `arma`, com as teclas de arma presas por 3
quadros (tics aos pares). Expressividade **negativa** em tamanho
(79 → 135 linhas; os mesmos 16 campos): registrado em
`docs/registro/04-arma.md`. O 4b (estados de `info.STATES` e ações do
`p_pspr.c`) muda o jogo e fica para a fase de correções.

**Passo 4c (feito):** o jogador como task `Jogador` (`jogador.atm`), com a
`Arma` como filha. Motivo: as metades `think_antes`/`think_depois` do 4a
eram um corte por posição, sem significado (notas, seção 9). Agora o tic do
jogador são partes com nome do domínio em `player.lua` e as fases vivo e
morto são dois laços; `morto_no_tic` sumiu. A arma vem depois de todas as
partes (experimento: idêntico nos roteiros; mutação equivalente). O laço do
morto age já no tic em que a morte é percebida. A morte **não** aborta a
`Arma` (a arma desce depois da morte, e isso aparece). O `Nivel` ainda lê
`playerstate` para renascer (`G.tic_view_meio`), porque o `tick_fx` roda
antes no tic de renascer.

**Passo 5 (feito):** o Zombieman como task `Zumbi` (`monstro.atm`); os
outros mobjs continuam Lua, na mesma lista. O laço dos mobjs saiu de
`thinker.tick` (o Lua não emite) e foi para o `Nivel` (`mobjs()`), com
`thinker.pensantes` montando a lista. A task nasce em `spawn_mobj` (pool
`monstros`). Ela "descompila" as linhas `S_POSS_*` de `info.STATES` em sete
comportamentos com nome; cada quadro ainda vem da tabela
(`thinker.aplicar_estado`). As ações e o dano trocam `istate` de fora: a
task percebe o salto (`:aplicado`, `:salto`, com `vencido` quando os tics do
estado novo acabaram no mesmo tic). Caso `estranho`: o load aplica os mobjs
por índice e um zumbi pode receber o estado de outro tipo; a task segue a
tabela (`thinker.seguir_tabela`). Cuidado no Atmos: `until (c, v)` devolve
`c` quando `v` é `nil` ou `false`. Roteiro `monstro` (`-warp 1 2
-respawn`). Resultado em tamanho negativo (87 → 221 linhas), ganho de nome
e forma: `docs/registro/05-monstro.md`.

**Passo 6 (feito):** o relógio tem duas fases em sequência (tic normal;
depois do `:tela.transicao`, só o wipe), em vez de `if G.wiping()` a cada
tic. O quadro emite `:game.frame` entre `G.quadro_antes` e
`G.quadro_depois`, e cada tela (`Titulo`, `Nivel`, `Intermissao`, `Finale`)
desenha a si mesma; `paint_state` (o despacho por `gamestate`) e `redraw`
sumiram. Registro: `docs/registro/06-wipe-e-quadro.md`.

**Passo 7 (feito):** a intermissão e o finale do Doom 1 como tasks
`Contagem` e `Texto` (`telas.atm`); cada tela é uma sequência escrita na
ordem em que acontece. Pela régua, o lado bom: código do mesmo tamanho
(185 → 184), campos de fase de 5 para 2 (só `state` e `stage`, que o
desenho lê), 17 comparações com a fase a menos. "Acelerar" e "pular"
continuam lidos do teclado em Lua. As telas entraram no hash de estado (nos
três lugares: `atmos`, `tests/ref-passo1.patch`, branch `lua`): sem isso,
três mutações sobreviviam. Roteiro `telas` (E1M1 com os segredos, E1M2,
E1M8 e o finale). Registro: `docs/registro/09-intermissao-e-finale.md`.

**Passo 8 (feito):** itens A5, A2, A1 e A3 do plano. 8a: a task `Mundo`
(o `P_Ticker`: pools, `Jogador`, o tic do mundo) dentro do `Nivel`, com o
automapa e a barra fora; o resultado do tic volta em `r.fim`. 8b: o rosto
da barra como task `Rosto` (`barra.atm`), 5 campos → 1. 8c: o menu como
task `Menu` (`interface.atm`): a entrada oferece as teclas
(`G.tecla_para_menu`, `:menu.tecla`) e a task marca se usou; neutro. 8d: o
automapa como task `Automapa`; modesto. O rosto, o menu e o automapa
entraram no hash (nos três lugares). Os emits novos são direcionados (custo:
+13% com o alcance padrão, +3,4% direcionados). Registro:
`docs/registro/10-interface-e-mundo.md`.

**Próximo:** a lista do que vem depois do passo 7 está em
`docs/PLANO_ATMOS.md`, seção 6, "Depois do passo 7": A (migração por
equivalência: menu, barra de status, automapa, família de monstros, task
`Mundo`), B (oráculo: o rosto da barra no hash, as 3 mutações pendentes), C
(a fase de correções, com prioridades), D (experimentos: funcionalidade nova
das duas formas, save por ponto de controle) e M (métricas finais de novo
com o passo 7; escrita). Ordem sugerida: M1 e B1, depois A1 e A2.

Pela decisão registrada em `docs/DIFERENCAS_DOOM.md`, as
diferenças e revisões só são corrigidas depois de todos os passos, nas
branches `atmos` e `lua`. As métricas finais (seção 7 do `PLANO_ATMOS.md`)
estão em `docs/registro/07-metricas-finais.md`, geradas por
`tools/metricas_finais.py` sobre a tag `passo6`, antes das correções.
O pré-requisito das correções está feito: a branch `lua` tem o modo
replay e o hash de estado, e `make test-branches` mostra as duas branches
idênticas nos 11 roteiros (`docs/registro/08-branch-lua-replay.md`).

O passo 3, plano em `docs/PLANO_ATMOS.md`, seção 6, e registro em
`docs/registro/03-specials.md`. Como ficou o código (`specials.lua` guarda
a criação, a geometria e o scroll; as fases são tasks):

| Função | Papel hoje |
|---|---|
| `M.new` → `M.spawn_specials` | cria as luzes (tasks, desde o 3a) e as portas de setor a partir de `sector.special`, na ordem dos setores |
| `M.tick` | só as linhas com scroll (luzes, movimentadores e botões são tasks) |
| `setores.atm` | tasks de setor (3a: `Pisca`, `Strobe`, `Brilho`, `Fogo`); flash, strobe e fire usam `rng.p_random()` |
| `setores.atm`, movimentadores | `Porta` (3b), `Elevador` (3c), `Piso` e `Teto` (3d), todas na pool `movers`; `tick_floor`, `tick_ceiling`, `M.tick_thinker` e a `ThinkerLua` sumiram no 3d |
| `spawn_door`, `vertical_door`, `do_plat_*`, `do_floor`, `do_stairs`, `do_crusher`… | criam thinkers e marcam `sector.specialdata` |
| `M.move_plane` | geometria pura (mantenha em Lua) |
| `saveg.lua`, função de gravar e `M.apply` | percorrem as pools `movers` e `botoes` (`t.pub`) no mesmo formato de antes |

Ordem seguida: luzes → botões → portas → elevadores → pisos e tetos, com
o save de cada tipo no próprio subpasso. As luzes vêm primeiro porque só são criadas ao montar o nível
(`spawn_specials`), nunca por linhas: dá para validar pools, `await` e
`P_Random` antes de criar tasks a partir do Lua (`spawn_in`), o que começa
nos botões e nas portas. Os disparos vêm de `collision.lua:534`
(`cross_special`), `collision.lua:921` (`use_special`),
`collision.lua:1108` (`shoot_special`) e `enemy.lua:345` (monstro abre
porta, usa o retorno).

**Subpasso 0 (feito):** `G.tic_view` foi dividido em `tic_view_antes` e
`tic_view_depois`, com `emit :game.specials` no meio, em `Nivel`. Uma task
transparente em `Nivel` chama `G.specials_resto()` (todo o
`specials_mod.tick`, por enquanto). Replay idêntico ao `passo1`. A mutação
`specials-no-fim-do-tic` ficou em `PENDENTES` até o 3d, cujo roteiro a
detecta (o esmagador zera a vida do jogador).

**Subpasso 3a (feito):** luzes em `setores.atm` (`Pisca`, `Strobe`,
`Brilho`, `Fogo`). A pool `luzes` é declarada em `Nivel` **antes** de montar
o nível e passada ao Lua com `G.set_pools`; `specials.lua` cria as tasks com
`spawn_in(self.pools.luzes, ...)` dentro de `build_level`, no mesmo ponto do
`P_Random` de antes. Sem `main.atm` (testes unitários), `pools` é `nil` e as
luzes ficam paradas. Roteiro `luzes` (E4M1 tem fogo; nenhum mapa dos
roteiros antigos tinha). `tools/mutacoes.py` aceita mutações em qualquer
arquivo e roteiro; `tools/metricas_passo3.py` mede cada subpasso;
`tools/custo_drivers.py` compara também com a tag `passo2`. Detalhes,
números e problemas em `docs/registro/03-specials.md`.

**Subpasso 3e (feito):** botões como task `Botao` (`setores.atm`), pool
`botoes` declarada **depois** da task do resto. As três declarações (luzes,
resto, botões) vêm **antes** de montar o nível, porque o load recria
botões. `change_switch` chama `M.start_button` (`spawn_in` no meio do
tic). O save percorre a pool (`pairs`) e grava `t.pub`; o load chama
`M.start_button` com o timer gravado. O botão guarda `pub.timer` à mão
porque o save precisa dele (o custo do save, medido). Comando de teste
`use <linha>` (também no `tests/ref-passo1.patch`) e roteiro `botoes`
(E1M1 linha 136, E1M4 linhas 394 e 694, save com botão ativo, load).
Lição: **a cada tipo migrado, confira que o que ele escreve está no hash**
(daí os lados no hash, com `DOOM_REPLAY_SIDES`).

**Subpasso 3b (feito):** portas como task `Porta` numa pool única
`movers` (ordem de criação), com elevadores, pisos e tetos ainda Lua
embrulhados em `ThinkerLua`; `self.thinkers` sumiu. A fase da porta é
`porta.direction` no registro da porta (`sector.specialdata` = `pub`): o Lua
ainda a inverte em `spawn_door` (o **recado**, lido na fase de specials; um
`emit` imediato mudaria o jogo, mutação `recado-vira-evento`). O recado é a
direção, não um booleano (dois "use" no mesmo tic). Este port **não**
reabre a porta ao esmagar (o Doom original reabre). O save tem o mesmo
formato; `tests/test_drivers.sh` compara os `.dsg` byte a byte. Comando
`cross <linha>`. Resultado misto de expressividade (código 208 → 234,
estado 9 → 8), registrado.

**Subpasso 3c (feito):** elevadores como task `Elevador` na pool
`movers`, no mesmo desenho das portas: a fase é `plat.status` no registro,
e `stop_plat` (Lua) continua escrevendo `status = WAITING` e `count`
enorme (o recado). Parar com `toggle` **não** é equivalente: o original
continua descontando o `count` do elevador parado, e só o save mostra isso
(mutação `parar-com-toggle`, detectada só pela comparação de saves). O
roteiro `elevadores` para os elevadores **enquanto andam** (com eles
esperando, o recado não troca de fase e as mutações sobreviviam).
`tools/mutacoes.py` compara também os saves de cada roteiro
(`build/drivers/saves_<roteiro>/`). Resultado misto, como as portas
(código 157 → 180, estado 10 → 9).

**Subpasso 3d (feito):** pisos e tetos como tasks `Piso` e `Teto` na pool
`movers`; a `ThinkerLua` sumiu. O `Piso` guarda a fase no registro (o save
grava o piso). O `Teto` é o primeiro movimentador sem recado e sem save
(as linhas 57 e 74 param elevadores; tetos não são gravados): direção e
velocidade são variáveis da task, e o esmagador que vai e volta é um laço.
A escada depende do spawn síncrono (P8): o degrau fica ocupado na hora, e a
busca do próximo degrau o pula. Comando de teste `goto x y` (também no
`tests/ref-passo1.patch`) e roteiro `pisos` (E2M2, E2M4, E2M1, E3M5), com o
jogador embaixo de dois esmagadores. Achado: o jogador esmagado **não
morre** (vida 0, mas `playerstate` continua vivo; `docs/DIFERENCAS_DOOM.md`).
A mutação `specials-no-fim-do-tic` saiu de `PENDENTES`: só a vida 0 aparece
na barra (o esmagamento não mexe em `damagecount`), e a morte tem de cair
num tic desenhado (ver "Tics aos pares", seção 2.5). Código 196 → 202,
estado 11 → 12 (`dir` e `vel` do `Teto`).

Ferramentas: `tools/mutacoes.py` aceita mutações em vários arquivos e extrai
os trechos do `Nivel` na hora; confira que a execução mutada **terminou**
(número de quadros) antes de aceitar uma detecção. `tools/diagramas.py` +
preview "diagramas" (`.claude/launch.json`) conferem os Mermaid do
registro (`window.erros`).

Ao mudar o `tests/ref-passo1.patch`, apague o worktree antigo
(`git worktree remove --force build/ref-passo1`) ou aplique a mudança nele
à mão: o script só aplica o patch quando ele aplica limpo.

**Registro:** `docs/registro/03-specials.md` foi atualizado **em cada commit
do passo 3** (tabela de subpassos no topo e uma seção por subpasso), e o
mesmo nos passos seguintes (`04-arma.md`, `05-monstro.md`,
`06-wipe-e-quadro.md`).

Receita usada em cada subpasso (valeu também para os passos 4 a 6, trocando
o que é de specials pelo equivalente):
1. tire a parte migrada de `specials_mod.tick` (ou seja, de
   `G.specials_resto`) e declare a pool dela em `Nivel`, **antes** da task
   do resto (luzes, scroll) ou **depois** dela (botões), conforme a ordem
   do `M.tick`; o que ficar no meio continua no resto;
2. crie as pools dentro de `Nivel`, na ordem das listas;
3. acrescente o estado novo ao `G.state_string`;
4. crie um roteiro específico;
5. rode `make test-drivers`, acrescente mutações e rode
   `make test-mutacoes`;
6. registre em `docs/registro/03-...md`, no formato dos anteriores;
7. faça um commit por subpasso; a tag (`passoN`) só no fim do passo.

---

## 10. Convenções

- **Código:** comentários em português, **sem acento**, no estilo dos
  arquivos existentes. Lua com 2 espaços; Atmos com 4 espaços e comentários
  `;;`.
- **Documentação:** português com acentos. Um arquivo
  `docs/registro/NN-nome.md` por passo, com: resumo, situação antes (com
  linhas da tag anterior), solução, comparação de código lado a lado,
  validação (equivalência, cobertura, mutações, problemas encontrados),
  métricas, custo, diferenças conhecidas, como reproduzir e arquivos
  alterados. Números sempre medidos por script, nunca de memória.
- **Git:** um commit e uma tag (`passoN`) por passo concluído. Não faça push
  sem pedido. Não commite `build/`, `.so` nem `.mid` (estão no `.gitignore`).
- **Mudança de comportamento:** nunca junto com refatoração. Primeiro a
  equivalência, depois a correção, num commit separado, com nova referência
  e a divergência esperada documentada.
- **Antes de dizer que terminou:** `make`, `make test-drivers`,
  `make test-mutacoes`, `make test` (mesmo resultado de antes) e o jogo com
  janela (`lua5.4 main.lua -scale 2`, fechando com `kill -TERM`; deve
  imprimir "janela fechada").
