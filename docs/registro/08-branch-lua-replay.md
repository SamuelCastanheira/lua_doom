# Preparação da fase de correções: o modo replay na branch `lua`

- Branches: `lua` (commit `09d8078`) e `atmos`
- Comando: `make test-branches` (na `atmos`)

## Resumo

Pela decisão registrada em `docs/DIFERENCAS_DOOM.md`, as diferenças em
relação ao Doom e as revisões do próprio port são corrigidas depois de
todos os passos, **nas duas branches**: a `lua` (o jogo imperativo
original, com thinkers) e a `atmos`. Para provar que elas continuam iguais
depois de cada correção, a branch `lua` precisava do modo replay e do hash
de estado, que até aqui só existiam a partir da tag `passo1`.

Com isso, as duas branches foram comparadas **diretamente**, com o hash de
estado completo: idênticas nos 10 roteiros.

## O que entrou na branch `lua` (commit `09d8078`)

Só instrumentação de teste; o jogo normal não muda (janela conferida, e
`make test` dá o mesmo resultado de sempre: 12 passam, as mesmas 8 falhas).

| Arquivo | Mudança |
|---|---|
| `video.lua` | o mesmo modo replay da `atmos`: `DOOM_REPLAY`, `DOOM_REPLAY_OUT`, `DOOM_REPLAY_DUMP` e os comandos de teste `exit`, `die`, `use`, `cross` e `goto` |
| `src/framebuffer_c.c` | `framebuffer_c.hash` (FNV-1a de 32 bits) |
| `random.lua` | `random.index()` |
| `main.lua` | `level_gen` (níveis montados); os comandos de teste no laço de eventos; `state_string`, no mesmo formato do `G.state_string` da `atmos`, ligado a `video.state_hook` |

O `main.lua` da branch `lua` ainda é o laço `while` original. Os comandos de
teste e o resumo do estado foram escritos ali com o mesmo código que o
`tests/ref-passo1.patch` põe no `game.lua` do `passo1`.

## Validação

`make test-branches` roda `tests/test_drivers.sh` com a referência apontada
para o worktree da branch `lua` (`REF_TAG=lua REF_DIR=build/branch-lua`). O
script ganhou a variável `REF_DIR` para isso.

| Roteiro | Quadros | Estados distintos | `lua` × `atmos` |
|---|---|---|---|
| `fluxo` | 4.478 | 1.682 | idêntico |
| semente 1 | 4.000 | 2.707 | idêntico |
| semente 2, `exits` | 6.000 | 1.437 | idêntico |
| `luzes` (`-warp 4 1`) | 2.619 | 1.964 | idêntico |
| `botoes` (`-warp 1 1`) | 851 | 587 | idêntico |
| `portas` (`-warp 1 1`) | 2.958 | 2.161 | idêntico |
| `elevadores` (`-warp 1 3`) | 2.098 | 1.615 | idêntico |
| `pisos` (`-warp 2 2`) | 2.593 | 1.954 | idêntico |
| `arma` (`-warp 1 1`) | 2.994 | 2.181 | idêntico |
| `monstro` (`-warp 1 2 -respawn`) | 2.755 | 2.045 | idêntico |

Framebuffer, estado e saves iguais byte a byte. A primeira execução divergiu
só no hash de estado dos primeiros 49 quadros (a tela de título): na branch
`lua`, `level_gen` era `nil` até o primeiro nível, e no `passo1` começa em
`0`. Inicializado do mesmo jeito, os 10 roteiros deram idêntico.

## A cadeia de equivalência, fechada

Antes, a branch `lua` tinha sido comparada com o `passo1` só pelo
framebuffer (registro do passo 2). Agora a comparação é direta, com o
estado completo, entre o jogo imperativo original e o estado final da
migração:

```
branch lua ──(framebuffer + estado + saves, 10 roteiros)──> atmos (passo6)
```

## Como usar nas correções

Para cada item do `docs/DIFERENCAS_DOOM.md`:

1. corrigir na `atmos` e na `lua` (no worktree `build/branch-lua`, que está
   na branch `lua`), um commit em cada;
2. `make test-branches`: as duas branches têm de continuar iguais;
3. a comparação com a referência antiga (`make test-drivers`, tag `passo1`)
   passa a divergir de propósito: documentar a divergência esperada e criar
   uma tag nova de referência.
