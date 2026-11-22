# Passo 1: ambiente `atmos.env.doom` e driver `main.atm`

- Branch: `atmos`
- Base: branch `lua` (commit `c230d9a`, renderer inteiro em C)
- Resultado: tag `passo1` (commits `844c6ed` e `75c5e67`)

## Resumo

O laço principal do jogo foi separado do estado e das regras, e passou a
existir em duas versões que executam o mesmo código de jogo:

- **`main.lua`:** o laço imperativo original (referência).
- **`main.atm`:** o laço em concorrência estruturada (Atmos).

Um ambiente Atmos próprio liga o jogo ao runtime. Um modo replay
determinístico prova que as duas versões produzem o mesmo jogo, quadro a
quadro. Neste passo as tasks de tela só **observam** as trocas de tela, que
continuam decididas em Lua. Mover essas decisões é o passo 2.

---

## 1. Decisões de arquitetura

### 1.1 `game.lua`: o jogo sem o laço

O `main.lua` original tinha 776 linhas: estado, regras e o laço `while`. O
estado e as regras foram para `game.lua`, **extraídos por script** (cópia
mecânica dos trechos, não reescrita), para não introduzir erro de cópia. O
laço foi dividido em fases, sempre executadas nesta ordem:

```
1. handle_input(ev)   para cada evento do video.poll()
2. ate 4 tics:        se wiping: tic_wipe()
                      senao: tic_menu(), depois a tela atual:
                             tic_view() / tic_intermission() / tic_finale()
3. frame()            redesenha, toca som, apresenta
```

O único ajuste não mecânico: o `break` do laço original, que deixava de
recuperar tics atrasados quando o nível terminava, virou um valor de retorno
de `tic_view`.

### 1.2 O ambiente `atmos/env/doom`

Um ambiente Atmos é um objeto com `step()`, que o runtime chama em laço, e
cada `step` emite eventos. Os ambientes existentes (`atmos.env.sdl`,
`atmos.env.pico`) usam outras bibliotecas de vídeo; este usa o `video_c` do
próprio jogo. Ordem dos eventos em um `step`:

| Evento | Quando |
|---|---|
| `{tag="input.key.down"/"input.key.up"/"input.mouse"/"input.quit", ...}` | cada evento de entrada |
| número (µs) | relógio real, para `await 1s` (não usado pelo jogo) |
| `{tag="tic", n=...}` | de 0 a 4 por `step`, a 35 Hz, com acumulador igual ao do laço original |
| `"frame"` | uma vez por `step` |

`cancel_catchup()` interrompe os tics restantes do `step`, que é o
equivalente ao `break`. Como o casamento de tags é hierárquico, `await
:input` acorda com qualquer entrada.

**Regra adotada: tempo em tics, nunca em segundos.** O Doom mede tudo em
tics, e o relógio real quebraria o determinismo.

### 1.3 O `main.atm` do passo 1

- **Entrada:** `loop ev on :input { G.handle_input(ev) }`.
- **Relógio:** `loop on :tic { ... emit :game.tic ... }`, acordando só a task
  da tela atual.
- **Quadro:** `loop on :frame { G.frame() }`.
- **Telas:** uma task por tela, encerrada pelo evento `:state`.

O `:state` é emitido quando `G.screen_changed()` detecta, numa fronteira de
fase, que `game.gamestate` ou `game.level_gen` mudou. As transições
continuavam em Lua; as tasks só acompanhavam.

**Regra adotada: nunca emitir um evento que aborte uma task de dentro de uma
chamada Lua feita por essa task.** Por isso `:state` só é emitido nas
fronteiras de fase. No passo 2 essa regra virou a fila de pedidos.

---

## 2. Modo replay (equivalência determinística)

`DOOM_REPLAY=<roteiro>` troca o backend de vídeo (`video.lua`):

- sem janela e sem som;
- **tempo simulado:** cada `poll()` avança exatamente um tic;
- teclas lidas do roteiro, no formato `<quadro> <tecla> down|up`, além dos
  comandos de teste `quit`, `exit [secret]` e, desde o passo 2, `die`;
- a cada `present()`, grava `quadro hash_framebuffer hash_estado`
  (FNV-1a de 32 bits, `framebuffer_c.hash`).

O hash de estado (`G.state_string`) inclui:
- tela, `leveltime`, posição na tabela aleatória (`random.index()`),
  episódio e mapa, wipe, menu e `level_gen`;
- cada mobj (posição, ângulo, vida, estado, tics);
- cada setor (alturas, luz);
- o jogador.

**Não determinismo encontrado e corrigido:** `wipe.lua` e `wi_stuff.lua` usam
`math.random`, que o Lua sorteia a cada execução. O próprio `main.lua`
divergia de si mesmo a partir do primeiro wipe. No replay, a semente é fixa
(`math.randomseed(1)`). O Doom original usava uma tabela fixa (`M_Random`)
para essas coisas.

Roteiros (`tools/make_replay.lua`): pseudoaleatórios com semente fixa
(movimento, tiro, `use`, automapa, menu, cheats `iddqd`, `idkfa` e `idclev`)
e, com `exits`, também saídas de nível.

---

## 3. Resultados

### 3.1 Equivalência

| Comparação | Roteiros | Resultado |
|---|---|---|
| `main.lua` × `main.atm` (passo 1) | semente 1 (4.000 quadros), sementes 2 a 4 com `exits` (6.000 e 8.000 quadros), semente 5 (finale) | idêntico, framebuffer e estado |
| branch `lua` original × `main.lua` do passo 1 (verificado no passo 2) | sementes 1, 3 e 7, 5.000 quadros cada, 6 a 7 níveis | framebuffer idêntico |

O segundo elo foi verificado depois, no passo 2, e fecha a cadeia: o jogo
original (sem `game.lua`) é idêntico ao `main.lua` extraído, que é idêntico
ao `main.atm`.

### 3.2 Sensibilidade

Para conferir que o teste detecta erro, a entrada foi processada um quadro
atrasada no `main.atm` (`await :frame` antes de `G.handle_input`). O
resultado divergiu no **quadro 48**, com **3.832 de 4.000** quadros
diferentes. Trocar a ordem entre menu e tela dentro do tic não mudou nada; no
passo 2 isso foi justificado como mutante equivalente.

### 3.3 Custo

`python3 tools/custo_drivers.py 5`, roteiro `fluxo`, 4.478 quadros:

| Driver | ms/quadro |
|---|---|
| `main.lua` (imperativo) | 0,836 |
| `main.atm` (passo 1) | 0,915 (+9,5%) |

Um tic dura 28,6 ms. Microbenchmark (`tools/bench_tasks.atm`): cerca de
2,2 µs por task acordada. Mil tasks acordando a cada tic custam 2,6 ms por
tic.

---

## 4. Armadilhas da linguagem e da CLI

| Situação | Correto |
|---|---|
| Operadores lógicos | `||`, `&&`, `!` (não `or`, `and`, `not`) |
| Concatenação | `++` (não `..`) |
| Indexação | `t@k`, `t@(expr)` |
| `until` | sempre com parênteses: `until (cond)` ou `until (cond, valor)` |
| `spawn @(pool) ...` | exige uma task nomeada |
| CLI | `atmos main.atm -- -fps`: sem `--`, o `atmos` lê `-fps` como opção dele |
| `arg` | no `atmos`, o nome do script fica em `arg[1]` (no Lua puro, em `arg[0]`); `game.atmos_args` trata isso |

---

## 5. Arquivos

| Arquivo | Papel |
|---|---|
| `game.lua` | estado, regras e fases (extraído do `main.lua`) |
| `main.lua` | laço imperativo (referência) |
| `main.atm` | laço com tasks |
| `atmos/env/doom/init.lua` | ambiente |
| `video.lua` | modo replay |
| `random.lua` | `index()` (leitura da posição na tabela, para o hash) |
| `src/framebuffer_c.c` | `framebuffer_c.hash` |
| `tools/make_replay.lua`, `tests/test_drivers.sh` | roteiros e comparação |
