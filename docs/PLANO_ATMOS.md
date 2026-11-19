# Plano de migração da lógica de jogo para Atmos

Lógica de jogo do lua_doom com concorrência estruturada (Atmos / lua-atmos),
usando o Doom como estudo de caso do TCC.

- Branch de trabalho: `atmos`
- Branch de referência: `lua` (lógica com thinkers, igual ao Doom original)
- Orientação: Francisco

---

## 1. Objetivo

Reescrever partes da lógica de jogo do Doom com tasks, eventos e composição
estruturada (`par`, `watching`, `pin`, `tasks`). Depois comparar com a versão
imperativa original (thinkers, contadores de tics, campos de estado) em três
eixos:

1. **Expressividade**: linhas de código, variáveis de estado por entidade,
   caminhos de cancelamento tratados explicitamente.
2. **Correção**: o jogo continua o mesmo, comprovado por replay determinístico
   tic a tic.
3. **Custo**: tempo por tic e memória.

A pergunta de pesquisa é: concorrência estruturada reduz o estado explícito e
os bugs de ciclo de vida na lógica de jogos, com custo aceitável?

---

## Andamento

| Passo | Situação | Registro |
|---|---|---|
| 1. Ambiente e driver | concluído (tag `passo1`) | [registro/01-ambiente-e-driver.md](registro/01-ambiente-e-driver.md) |
| 4.1–4.3. Referência, hash, roteiros | concluído junto com o passo 2 | [registro/02-fluxo-de-telas.md](registro/02-fluxo-de-telas.md), seção 5 |
| 2. Fluxo do jogo por eventos | concluído (tag `passo2`) | [registro/02-fluxo-de-telas.md](registro/02-fluxo-de-telas.md) |
| 3. Specials de setor | concluído (tag `passo3`) | [registro/03-specials.md](registro/03-specials.md) |
| 4. Arma (4a) e jogador (4c) | concluído (tag `passo4`); 4b adiado para a fase de correções | [registro/04-arma.md](registro/04-arma.md) |
| 5. Um monstro | próximo | – |
| 6. Wipe e quadro por evento (opcional) | planejado | – |

Desvios em relação a este plano, decididos durante o passo 2:

- **A referência é a tag `passo1`, não a branch `lua`.** A branch `lua` não
  tem o modo replay nem o hash de estado. A tag `passo1` foi comparada com a
  branch `lua` (framebuffer idêntico) e usada como referência, com um patch
  só de teste (`tests/ref-passo1.patch`).
- **`game.gamestate` não sumiu.** Ele continua como "tela exibida", lido por
  vários módulos, mas é escrito só por `G.enter`, chamado pelas tasks de
  tela.
- **O wipe continua no redesenho (Lua).** Não decide nada do fluxo, e
  movê-lo arriscaria a temporização. Fica como passo opcional.
- **O `carry` continua global**, para preservar um bug da referência
  (registro do passo 2, seção 8.1). A correção é um commit separado.
- **Cada execução do teste roda numa pasta isolada.** O teste chegou a
  sobrescrever um save do usuário; saves fazem parte do estado de entrada.

## 2. Estado no fim do passo 1

| Componente | Situação |
|---|---|
| Renderer 3D e 2D | Em C (`src/render/`, `src/v_draw.c`). O Lua não desenha pixels. |
| `game.lua` | Estado e regras extraídos do antigo `main.lua`, divididos em fases. |
| `main.lua` | Driver imperativo: o laço original chamando as fases. |
| `atmos/env/doom` | Ambiente Atmos: emite `:input.*`, relógio em µs, `:tic` (35 Hz) e `:frame`. |
| `main.atm` | Driver Atmos: entrada, relógio, telas e quadro como tasks. |
| Modo replay | `DOOM_REPLAY`: sem janela, tempo simulado, hash de cada quadro e do estado. |
| `make test-drivers` | Prova que `main.lua` e `main.atm` produzem o mesmo jogo. |

No fim do passo 2, o fluxo de telas inteiro está em `main.atm`, e o
`main.lua` virou um lançador. A lógica de dentro do nível ainda usa thinkers
(`thinker.lua`, `specials.lua`, `enemy.lua`); os próximos passos mudam isso.

---

## 3. Regras que valem para todos os passos

### 3.1 Tempo em tics, nunca em segundos

Tudo no Doom é medido em tics de 35 Hz. Use `:tic`/`:game.tic` e um helper
`wait_tics(n)`. O `await 2s` usa relógio real e quebra o determinismo do
replay.

### 3.2 Ordem dentro do tic é parte da semântica

O Doom consome a tabela aleatória (`P_Random`, em `random.lua`) na ordem em que
as entidades pensam. Se a ordem mudar, a sequência aleatória muda e o jogo
diverge. A ordem atual de um tic de nível (`G.tic_view`) é:

1. automapa
2. comando do jogador (`build_ticcmd`)
3. `player_mod.think`
4. `player_mod.tick_fx`
5. `thinker.tick`: mobjs na ordem de `world.mobjs`
6. `specials_mod.tick`, nesta ordem interna:
   1. luzes (lista `self.lights`)
   2. linhas com scroll
   3. thinkers de setor (lista `self.thinkers`: portas, elevadores, pisos, tetos)
   4. botões
7. `res:update_anims`
8. saída do nível
9. `leveltime + 1`
10. barra de status

Qualquer task nova precisa acordar **no mesmo ponto e na mesma ordem** em que
o thinker equivalente rodava. Duas técnicas garantem isso:

- **Pools em ordem de criação.** O runtime acorda as tasks filhas na ordem em
  que foram criadas (`t._.dns`). Uma pool `tasks()` com spawns na mesma ordem
  em que a lista Lua recebia itens preserva a ordem.
- **Emit direcionado.** Para entidades misturadas numa lista (como
  `world.mobjs`), o laço Lua continua percorrendo a lista e faz
  `emit @(mo.task) :mobj.tic` para as entidades que já são tasks. A ordem fica
  exatamente a mesma.

### 3.3 Nunca abortar uma task de dentro de uma chamada Lua feita por ela

Se uma chamada Lua emite um evento que aborta a própria task chamadora, o
código Lua depois do `emit` não roda. O passo 1 resolve isso para as telas:
`:state` só é emitido nas fronteiras de fase. Siga a mesma regra:

- Funções Lua **registram pedidos** (`game.request(...)`).
- O driver Atmos **emite** os pedidos depois que a fase termina.

### 3.4 Uma task começa esperando

No Lua, `spawn_door` só cria a estrutura, e o primeiro movimento acontece no
próximo `tick_door`. A task equivalente precisa começar com
`await :game.specials` (ou o evento da sua fase) antes de mexer no setor.
Senão ela age um tic antes.

### 3.5 Aleatoriedade

Use `random.p_random()` / `enemy.p_random()`. Todo `math.random` novo precisa
ter semente fixa no replay (`video.lua` já fixa a semente 1).

### 3.6 Sintaxe Atmos (armadilhas já encontradas)

- Operadores: `||`, `&&`, `!`, e não `or`, `and`, `not`.
- Indexação: `t@k` e `t@(expr)`.
- `spawn @(pool) Nome(...)` exige uma task nomeada.
- A CLI precisa de `--` antes das opções do jogo:
  `atmos main.atm -- -fps -scale 4`.

---

## 4. Como provar equivalência

### 4.1 Referência fixa na branch `lua`

A partir do passo 2, `main.lua` e `main.atm` vão divergir por construção,
porque `game.lua` passa a ter lógica em tasks. A referência deixa de ser o
`main.lua` da branch `atmos` e passa a ser a branch `lua`, num worktree:

```sh
git worktree add build/ref-lua lua
```

**Tarefa 4.1:** estender `tests/test_drivers.sh` com o modo `REF=lua`:

1. Gerar o roteiro uma vez (`tools/make_replay.lua`).
2. Rodar `lua5.4 main.lua` dentro de `build/ref-lua`. Antes, copiar para lá o
   modo replay de `video.lua`, o `random.index()` e o `framebuffer_c.hash`, ou
   fazer cherry-pick do commit que os criou.
3. Rodar `atmos main.atm` na branch `atmos`.
4. Comparar os logs linha a linha. O primeiro quadro divergente aponta a fase
   que mudou de ordem.

### 4.2 Estado que entra no hash

`G.state_string()` já inclui tela, `leveltime`, posição da tabela aleatória,
mobjs (posição, ângulo, vida, estado, tics), setores (alturas e luz) e
jogador.

**Tarefa 4.2:** acrescentar, em cada passo, o estado das entidades migradas.
Exemplos:
- porta: tipo, direção, contador;
- elevador: status, contador;
- botões: timer.

Assim uma divergência aparece no tic em que acontece, e não só quando muda um
setor.

### 4.3 Roteiros

| Roteiro | Cobre |
|---|---|
| `make_replay.lua N 1` | Menu, novo jogo, movimento, tiro, `use`, automapa, cheats, `idclev`. |
| `make_replay.lua N 2 exits` | Também saídas de nível, intermissão e saída secreta (E1M9). |
| `make_replay.lua N 5 exits` | Finale do E1M8 e volta ao título. |

**Tarefa 4.3:** um roteiro por estudo de caso, em `tools/replays/`:
- `portas.txt`: mapa com muitas portas e elevadores, `use` em sequência, porta
  fechando sobre o jogador;
- `luzes.txt`: setores com luz piscando, vista parada;
- `save.txt`: salvar, jogar, carregar, jogar, comparando com a referência.

### 4.4 Sensibilidade

Para cada estudo de caso, injete de propósito um erro de ordem (por exemplo,
luzes depois dos thinkers) e confirme que o teste diverge. Isso vai para a
monografia como validação do método. No passo 1, atrasar a entrada um quadro
divergiu no quadro 48.

---

## 5. Arquitetura alvo

```
main.atm
 └─ Fluxo                          (passo 2)
     ├─ Titulo                     menu, demo de fundo
     └─ Jogo(ep, mapa, skill)      do primeiro mapa ao fim
         ├─ Nivel(ep, mapa)        uma instância por entrada no nível
         │   ├─ pin luzes   = tasks()   Luz(setor, tipo)          (passo 3a)
         │   ├─ pin movers  = tasks()   Porta / Elevador / Piso / Teto (3b–3d)
         │   ├─ pin botoes  = tasks()   Botao(linha, textura)     (3e)
         │   ├─ Arma(jogador)                                    (passo 4)
         │   └─ (monstros: emit direcionado a partir de thinker.tick) (passo 5)
         ├─ Intermissao(...)
         └─ Finale(...)
```

O ciclo de vida segue o escopo: quando `Nivel` termina (saída, morte,
`idclev`, load game, "End Game"), todas as tasks dentro dele terminam juntas.
Isso substitui:
- `door.dead`, `plat.dead` e `sector.specialdata = nil` ao fim do movimento;
- a reconstrução das listas `self.thinkers`, `self.buttons` e `self.lights` a
  cada nível;
- a limpeza manual em `game.end_game`, `game.finish_finale` e `game.advance`.

### Eventos (convenção de nomes)

| Evento | Quem emite | Quem escuta |
|---|---|---|
| `:input.key.down/up`, `:input.mouse`, `:input.quit` | ambiente | entrada |
| `:tic` | ambiente | relógio |
| `:frame` | ambiente | quadro |
| `:game.tic` | relógio | tela atual |
| `:game.specials` | `Nivel`, no ponto 6 do tic | luzes, movers, botões |
| `:linha.usada`, `:linha.cruzada`, `:linha.atingida` | `Nivel` (a partir de pedidos) | gatilhos de specials |
| `:nivel.saida [secreta=]` | `Nivel` | `Jogo` |
| `:jogo.fim`, `:jogo.novo`, `:jogo.carregar` | fluxo (a partir de pedidos do menu) | `Fluxo` |
| `:reabrir` (direcionado) | gatilho de porta | a `Porta` do setor |

---

## 6. Passos

Cada passo termina com `make test-drivers` (modo `REF=lua`) idêntico e um
commit. Os tempos são estimativas para quem já escreve Atmos.

### Passo 2: fluxo do jogo por eventos (1 semana)

**Objetivo:** a decisão "o que vem depois" sai dos callbacks Lua e vai para
`main.atm`.

**Situação atual:**
- `game.begin_exit`, `game.advance`, `game.finish_finale` e `game.end_game`
  mudam `game.gamestate`.
- `menu.lua:306` (novo jogo), `menu.lua:326` (End Game) e `menu.lua:324` (sair)
  chamam `game.*` diretamente.
- `cheats.lua:225` (`idclev`) e `saveg.lua:650` (load) chamam
  `game.start_level`.

**Mudanças:**

1. **Fila de pedidos em `game.lua`.** `game.request(tag, dados)` guarda o
   pedido numa fila, e `G.take_requests()` devolve e esvazia a fila. Trocas:

   | Hoje | Vira |
   |---|---|
   | `menu.lua`: `self.game.start_level(self.game)` | `game.request("jogo.novo", {ep=, skill=})` |
   | `menu.lua`: `self.game.end_game(self.game)` | `game.request("jogo.fim")` |
   | `cheats.lua`: `game.start_level(game)` | `game.request("nivel.trocar", {mapa=})` |
   | `saveg.load`: chamar `start_level` | `game.request("jogo.carregar", {slot=})`; a parte que aplica os dados vira `saveg.apply(game, data)` |
   | `begin_exit`, em vez de mudar `gamestate` | `game.request("nivel.saida", {secreta=})` |

2. **Funções que só montam.** Mantenha em `game.lua`:
   - `G.start_level(ep, mapa)`: monta mundo, specials, mobjs e música;
   - `G.make_intermission(...)`: monta `wi`;
   - `G.make_finale()`.

   Retire delas a mudança de `gamestate` e a decisão de próximo mapa.

3. **`main.atm`:** o relógio e a entrada, depois de cada fase, fazem
   `loop _, r in G.take_requests() { emit r }`, na fronteira de fase (regra
   3.3).

4. **Fluxo em tasks.** Esboço, com sintaxe a conferir:

   ```
   task Nivel (ep, mapa) {
       G.start_level(ep, mapa)
       par :any {
           loop on :game.tic { G.tic_view() }
       } with {
           val s = await :nivel.saida
           [saida=:normal, secreta=s.secreta]
       } with {
           await (:player.reborn)      ;; morte: o Jogo recomeça o mapa
           [saida=:morte]
       } with {
           val t = await :nivel.trocar ;; idclev
           [saida=:trocar, mapa=t.mapa]
       }
   }

   task Jogo (ep, mapa, skill) {
       loop {
           val r = await Nivel(ep, mapa)
           match r.saida {
               :morte  => {}                        ;; mesmo mapa
               :trocar => set mapa = r.mapa
               else    => {
                   if fim_de_episodio(ep, mapa) {
                       await Finale(ep)
                       break()
                   }
                   await Intermissao(ep, mapa, r.secreta)
                   set mapa = proximo_mapa(ep, mapa, r.secreta)
               }
           }
       }
   }

   task Fluxo () {
       loop {
           val pedido = await Titulo()             ;; :jogo.novo / :jogo.carregar
           watching :jogo.fim {
               await Jogo(pedido.ep, pedido.mapa, pedido.skill)
           }
       }
   }
   ```

5. **`proximo_mapa` e `fim_de_episodio`** vêm de `begin_exit`/`advance`:
   - E1M8 → finale;
   - saída secreta → mapa 9;
   - do mapa 9 → volta a 4/6/7/3 conforme o episódio;
   - Doom 2: `finale_mod.commercial_map`.

6. **Wipe.** Hoje `redraw` detecta a troca de tela e começa o wipe. No fluxo
   em tasks, o wipe vira uma task explícita entre telas
   (`await Wipe(antes, depois)`), o que torna visível algo que hoje é
   implícito.

**Cuidados:**
- O `carry` (vida, armas e munição entre níveis) vira parâmetro ou retorno de
  `Nivel`/`Jogo`, e não um campo global.
- O load game precisa reconstruir `Jogo`/`Nivel` com o episódio e o mapa do
  save, em vez de chamar `start_level` de dentro do menu.

**Pronto quando:**
- `game.gamestate` só é escrito por `main.atm` (ou some de vez);
- `main.lua` deixa de ser usado na branch `atmos`;
- o replay com `REF=lua` é idêntico nos roteiros 1, 2 e 5.

### Passo 3: specials de setor (2–3 semanas, principal estudo de caso)

Arquivo afetado: `specials.lua` (1.538 linhas). Crie `specials.atm` (ou
`atmos/doom/specials.atm`) com as tasks. Mantenha em Lua as funções puras de
geometria, que não guardam estado:
- `move_plane`;
- `lowest_ceiling`, `highest_floor`, `next_highest_floor`;
- `sectors_from_tag`, `min_surrounding_light`.

**Ordem:** `specials_mod.tick` vira `emit :game.specials` no mesmo ponto de
`G.tic_view`. Dentro de `Nivel`, declare as pools na ordem do tic (regra 3.2):

```
pin luzes  = tasks()
spawn {                    ;; linhas com scroll (efeito 48)
    loop on :game.specials { G.scroll_lines() }
}
pin movers = tasks()
pin botoes = tasks()
```

Confira no runtime que tasks em pools diferentes acordam na ordem léxica das
pools. Se não acordarem, use quatro eventos em sequência: `:sp.luzes`,
`:sp.scroll`, `:sp.movers`, `:sp.botoes`.

**Helpers** (`atmos/doom/util.atm`):

```
func wait_tics (n) { loop in n { await :game.specials } }
;; move o plano a cada tic ate o destino; devolve :ok ou :esmagou
func move_until (setor, vel, destino, chao_teto, dir, crush) { ... }
```

#### 3a. Luzes (2–3 dias)

São 4 tipos: `flash`, `strobe`, `glow`, `fire` (`tick_lights`). Hoje são um
`if light.kind == ...` com `count`, `direction`, `mintime` e `maxtime`.

```
task Fogo (setor, minlight, maxlight) {
    loop {
        wait_tics(4)
        val amount = band(rng.p_random(), 3) * 16
        set setor.lightlevel = if (setor.lightlevel - amount) < minlight => minlight
                               => maxlight - amount
    }
}
```

- `spawn_specials` faz `spawn @(luzes) Fogo(...)` na mesma ordem em que
  `self.lights` era preenchida. Essa ordem é crítica, porque `flash` e `fire`
  consomem `P_Random`.
- **Save:** as luzes são recriadas de `sector.special` ao carregar; o save
  atual não as grava. Confirme se o contador de fase precisa ir para o save.
  Hoje a fase é perdida, então o comportamento continua igual.

#### 3b. Portas (4–5 dias)

| Hoje (`tick_door`, `spawn_door`, `vertical_door`) | Com tasks |
|---|---|
| `direction` ∈ {-1, 0, 1}, `topcountdown`, `topwait` | sequência: abrir → esperar → fechar |
| `door.dead = true`, `sector.specialdata = nil` | a task termina |
| `vertical_door` inverte `door.direction` se a porta já existe | `emit @(setor.porta) :reabrir` |
| fechar e bater em algo → reabrir (`move_plane` devolve crushed) | `move_until` devolve `:esmagou` → volta a abrir |

```
task Porta (setor, tipo, vel, topwait) {
    set setor.specialdata = task           ;; ocupa o setor
    set pub = [tipo=tipo, fase=:abrindo]
    await :game.specials                   ;; regra 3.4
    loop {
        set pub.fase = :abrindo
        move_until(setor, vel, topo, :teto, 1)
        if tipo == :abrir_so { break() }
        set pub.fase = :esperando
        watching :reabrir {                ;; outro "use" enquanto espera
            wait_tics(topwait)
        }
        set pub.fase = :fechando
        val r = watching :reabrir {
            move_until(setor, vel, setor.floorheight, :teto, -1)
        }
        if r == :ok { break() }            ;; fechou: fim
        ;; reaberta ou esmagou: o loop abre de novo
    }
    set setor.specialdata = nil
}
```

Os tipos `VLD_CLOSE30` e `VLD_RAISEIN5` são sequências diferentes; cada um
pode virar sua própria task (`PortaFecha30`, `PortaAbreEm5`). Esse é um
argumento direto da monografia: estados que eram casos de `if` viram
programas lineares.

#### 3c. Elevadores (3 dias)

`tick_plat` usa `status` (`WAITING`/`UP`/`DOWN`), `count`, `wait`, `low` e
`high`.

- O elevador perpétuo vira `loop { descer; esperar; subir; esperar }`.
- `stop_plat` (linha que para elevadores) vira um
  `emit @(elevador) :parar`, tratado com `watching`. Hoje o elevador é marcado
  como "em espera"; confira como o original reativa.

#### 3d. Pisos, tetos, esmagadores, escadas, donut (4–5 dias)

- `tick_floor`/`tick_ceiling`: movimento até o destino e troca de textura no
  fim (`floorpic`).
- O esmagador (`do_crusher`) vira um laço de descer e subir com velocidade
  reduzida ao esmagar.
- Escadas (`do_stairs`) criam vários pisos de uma vez: um `spawn` por degrau,
  na mesma ordem.

#### 3e. Botões (1 dia)

Botão como task: `wait_tics(timer)` e restaurar a textura.

#### 3f. Save game das tasks (3–4 dias)

`saveg.lua` (linhas 380–495 gravam, 702–740 carregam) serializa
`specials.thinkers` e `specials.buttons` campo a campo. Uma task não é
serializável. Proposta:

1. Cada task mantém em `pub` tudo que define sua fase: tipo, `pub.fase`,
   contador restante e altura alvo.
2. O save percorre as pools (`loop _, t in movers`) e grava os `pub`.
3. O load faz `spawn @(movers) Porta(setor, tipo, ..., retomar=pub)`. A task
   entra direto na fase gravada, por exemplo com `ifs` no começo.
4. O teste usa o roteiro `save.txt`: salvar no meio de uma porta abrindo,
   carregar e comparar com a referência.

Isso é uma limitação real do modelo. Documente na monografia: quanto código
de retomada foi preciso e se ele anula parte do ganho.

**Pronto quando:** `specials.lua` não tem mais `self.thinkers`, `self.lights`,
`self.buttons`, `th.dead` nem `kind` despachado em `M.tick`, e o replay é
idêntico nos roteiros, incluindo `portas.txt`, `luzes.txt` e `save.txt`.

### Passo 4: arma / psprites (2 semanas)

Situação atual: `player.lua` (linhas 120–840) usa tabelas próprias
(`WEAPON_PATCH`, `WEAPON_READY`, `WEAPON_ATK`) e uma máquina de estados manual
(`psprite_state`: up/down/ready/atk/fire, `psprite_step`, `psprite_tics`,
`flash_tics`).

**4a, equivalência primeiro.** Reescreva a lógica *atual* como task, sem
mudar o comportamento:

```
task Arma (jogador) {
    loop {
        await Subir(jogador)                         ;; psprite_sy até WEAPONTOP
        val troca = watching :arma.trocar {
            loop {
                await Pronta(jogador)                ;; balanço, até atirar
                await Atirar(jogador)                ;; sequência WEAPON_ATK, refire
            }
        }
        await Baixar(jogador)
        set jogador.readyweapon = jogador.pendingweapon
    }
}
```

O flash vira uma task paralela (`par`) que termina sozinha, no lugar de
`flash_tics`. O replay precisa continuar idêntico.

**4b, fidelidade ao original (opcional, muda o jogo de propósito).** Usar os
estados de arma de `info.STATES` e as ações de `p_pspr.c` (`A_WeaponReady`,
`A_ReFire`, `A_GunFlash`, `A_Lower`, `A_Raise`, recarga da super shotgun).
Aqui o replay contra a branch `lua` deixa de valer. Valide a sequência de
estados e tics de cada arma contra o `info.c` original e congele uma nova
referência.

**Save:** os campos `psprite_*` do save viram o `pub` da task, com a mesma
técnica do 3f.

**4c, o jogador como task (acrescentado durante o passo 4).** No 4a,
`player.think` foi partido em duas metades sem significado só para encaixar
a arma no ponto do tic: um corte por posição, sintoma de que o jogador não
estava modelado (`docs/NOTAS_MONOGRAFIA.md`, seção 9). No 4c, a task
`Jogador` acorda com `:game.jogador`, faz o tic chamando partes com nomes do
domínio (mover, pisar, usar, escolher a arma, contar os poderes e os
avisos), tem as fases vivo e morto como dois laços e cria a `Arma` como
filha. Antes, testar se a arma precisa mesmo ficar no meio do tic do
jogador; se não, ela vem depois de todas as partes e o corte desaparece.

### Passo 5: um monstro (2 semanas, mostra a coexistência)

Escolha um, como o Imp (`MT_TROOP`) ou o Zombieman (`MT_POSSESSED`).

- **Ordem:** `thinker.tick` continua percorrendo `world.mobjs`. Para um mobj
  com `mo.task`, ele faz `emit @(mo.task) :mobj.tic` em vez de
  `mobj_thinker`. Essa é a técnica do emit direcionado (regra 3.2) e mantém a
  ordem e o RNG.
- **Comportamento** com `watching` e `par`:

  ```
  task Imp (mo) {
      watching :mobj.morreu {
          await Procurar(mo)                 ;; A_Look até ver o jogador
          loop {
              watching :mobj.dor {           ;; dor interrompe e volta a perseguir
                  await Perseguir(mo)        ;; A_Chase até poder atacar
                  await Atacar(mo)           ;; A_TroopAttack
              }
              await Dor(mo)
          }
      }
      await Morrer(mo)                       ;; animação e corpo
  }
  ```

- **Fronteira com o resto:** `enemy.damage_mobj` registra
  `game.request` de dor ou morte para o mobj, e `thinker.tick` emite na
  posição dele (regra 3.3).
- **Escopo:** os outros monstros ficam como thinkers, e isso também é um
  resultado: os dois modelos coexistem na mesma lista.

### Passo 6 (opcional): wipe como task e quadro por evento

Só se houver tempo depois do passo 5; é apresentação, não lógica de jogo
(`docs/NOTAS_MONOGRAFIA.md`, seção 2).

- **Wipe como task:** a transição de tela ("derreter") deixa de ser
  detectada no redesenho comparando `wipe_state` com `gamestate` e vira um
  programa linear entre duas telas. Pela régua da fase (notas, seção 8), é um
  bom candidato: ninguém de fora lê a fase do wipe, ele não vai para o save e
  o Lua não escreve nele no meio.
- **Quadro por evento:** cada task de tela desenha a si mesma em
  `:game.frame`, e o despacho por `gamestate` no `redraw` some.
- O renderer 3D em C continua como está: não tem dimensão de tempo.

---

## 7. Métricas (para a monografia)

Para cada estudo de caso (fluxo, luzes, portas, elevadores, arma, monstro),
nas duas versões:

| Métrica | Como medir |
|---|---|
| Linhas de código (sem comentários e linhas vazias) | `tools/metrics.lua` (a criar): conta por função/task listada num arquivo de configuração |
| Variáveis de estado por entidade | Campos gravados na estrutura do thinker (`door.direction`, `topcountdown`…) × variáveis do `pub` + locais vivas entre `await`s |
| Ramos de despacho | `if th.kind == ...`, `if status == ...` × 0 (a sequência é o próprio código) |
| Pontos de limpeza manual | `dead = true`, `specialdata = nil`, remoção de listas |
| Casos de cancelamento | Reabrir porta, parar elevador, trocar arma no meio do tiro, morte durante ataque: quantos são tratados explicitamente em cada versão |
| Custo por tic | Replay com `os.clock()` em volta de `G.tic_view`, nos dois drivers, nos mapas E1M1, E1M6 e E3M1 |
| Memória | `collectgarbage("count")` no meio do nível |

Referência de custo já medida: cerca de 2 µs por task acordada (1.000 tasks
dão 2,2 ms por tic, e o tic dura 28,6 ms). O driver Atmos do passo 1 custa
cerca de 0,06 ms por quadro a mais que o laço Lua.

---

## 8. Riscos e o que fazer

| Risco | Impacto | Mitigação |
|---|---|---|
| Ordem de acordar diferente da lista de thinkers | RNG diverge, o replay não bate | Pools em ordem de criação, emit direcionado, eventos separados por categoria (regra 3.2). Se for inevitável: medir e documentar a diferença. |
| Task abortada no meio de uma chamada Lua | Efeitos pela metade, bugs difíceis | Fila de pedidos e emit só nas fronteiras de fase (regra 3.3). |
| Save game | Tasks não serializam | `pub` com a fase e retomada no spawn (3f). Discutir o custo na monografia. |
| `await` dentro de função chamada por C ou por `table.sort` | Erro "attempt to yield across a C-call boundary" | Só faça `await` no corpo de tasks ou em funções Lua chamadas por elas, nunca em callbacks chamados pelo `render_c`/`video_c`. |
| Primeiro movimento um tic antes | Diverge no tic da ativação | Toda task de setor começa com `await` (regra 3.4). |
| Escopo grande demais | TCC atrasa | O mínimo publicável é passos 2 e 3 (fluxo, luzes, portas, elevadores) e as métricas. Arma e monstro são extensões. |
| Versões do Atmos | Sintaxe ou API mudam | Fixar a versão (hoje `atmos-lang dev-4` e `atmos dev-3`; estável v0.8) e registrar no README. |

---

## 9. Cronograma sugerido

| Semana | Entrega |
|---|---|
| 1 | 4.1–4.3: referência na branch `lua`, hash ampliado, roteiros por estudo de caso |
| 2 | Passo 2: fluxo por eventos |
| 3 | 3a luzes e 3e botões |
| 4–5 | 3b portas e 3c elevadores |
| 6 | 3d pisos, tetos, escadas e 3f save |
| 7–8 | Passo 4a, arma por equivalência |
| 9–10 | Passo 5, um monstro (ou 4b, fidelidade da arma) |
| 11 | Métricas (seção 7), tabelas e gráficos |
| 12+ | Escrita |

---

## 10. Sugestão de capítulos da monografia

1. **Introdução:** lógica de jogos como problema de concorrência; o Doom como
   referência histórica (thinkers, máquinas de estado à mão).
2. **Fundamentação:** programação síncrona (Esterel, Céu), concorrência
   estruturada, Atmos.
3. **O sistema:** arquitetura híbrida (renderer em C, lógica em Lua/Atmos),
   ambiente `atmos.env.doom`, determinismo e replay.
4. **Estudos de caso:** fluxo de telas, luzes, portas, elevadores, arma e
   monstro. Para cada um: código original × código com tasks, e o que mudou.
5. **Avaliação:** equivalência (replay e sensibilidade), métricas de código,
   custo.
6. **Discussão:** save game, ordem e RNG, coexistência dos dois modelos, o que
   não ficou melhor.
7. **Conclusão e trabalhos futuros:** todos os monstros, netgame/demos,
   Atmos no navegador (`atmos.env.js`).

---

## 11. Checklist por passo

- [ ] Roteiro de replay do estudo de caso em `tools/replays/`
- [ ] Estado novo incluído em `G.state_string()`
- [ ] Implementação em `.atm`, com o Lua antigo removido
- [ ] `make test-drivers` idêntico com `REF=lua`
- [ ] Teste de sensibilidade (erro injetado diverge)
- [ ] Save e load testados, quando aplicável
- [ ] Métricas registradas (seção 7)
- [ ] Commit com mensagem descrevendo o estudo de caso
