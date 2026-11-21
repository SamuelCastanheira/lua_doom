# Registro da migração da lógica de jogo para Atmos

Diário técnico de cada passo, escrito para ser citado no artigo do TCC. Cada
passo tem uma tag no git, os comandos para reproduzir os números e a lista
do que mudou, do porquê e do que deu errado no caminho.

| Passo | Tag | Documento | Conteúdo |
|---|---|---|---|
| 0 | branch `lua` | – | renderer inteiro em C; lógica em Lua com thinkers (referência original) |
| 1 | `passo1` | [01-ambiente-e-driver.md](01-ambiente-e-driver.md) | ambiente `atmos.env.doom`, `game.lua` em fases, `main.atm`, modo replay |
| 2 | `passo2` | [02-fluxo-de-telas.md](02-fluxo-de-telas.md) | fluxo de telas em tasks; pedidos em vez de chamadas |
| 3 | `passo3` | [03-specials.md](03-specials.md) | specials de setor em tasks (subpasso 0, 3a: luzes, 3e: botões, 3b: portas, 3c: elevadores, 3d: pisos e tetos) |
| 4 | `passo4` | [04-arma.md](04-arma.md) | a arma (4a) e o jogador (4c) em tasks |
| 5 | `passo5` | [05-monstro.md](05-monstro.md) | o Zombieman em task; laço dos mobjs no `Nivel`, com emit direcionado |
| 6 | `passo6` | [06-wipe-e-quadro.md](06-wipe-e-quadro.md) | o wipe como fase do relógio; cada tela desenha a si mesma |
| – | – | [07-metricas-finais.md](07-metricas-finais.md) | métricas consolidadas de todos os passos (seção 7 do plano) |
| – | branch `lua` `09d8078` | [08-branch-lua-replay.md](08-branch-lua-replay.md) | modo replay na branch `lua`; as duas branches comparadas direto (`make test-branches`) |
| 7 | `passo7` | [09-intermissao-e-finale.md](09-intermissao-e-finale.md) | a intermissão e o finale em tasks (`telas.atm`) |
| 8 | `passo8` | [10-interface-e-mundo.md](10-interface-e-mundo.md) | a task `Mundo`, o rosto da barra, o menu e o automapa |

## Cadeia de equivalência

```
branch lua ──(framebuffer, 3 × 5.000 quadros)──> passo1 main.lua
passo1 main.lua ──(framebuffer + estado)──> passo1 main.atm
passo1 main.lua ──(framebuffer + estado, roteiro "fluxo" + 2)──> passo2 main.atm
branch lua ──(framebuffer + estado + saves, 10 roteiros)──> atmos (passo6)
```

Cada elo é verificado no modo replay (`DOOM_REPLAY`): sem janela, tempo
simulado, teclas de um roteiro, um hash do framebuffer e um hash do estado do
jogo por quadro.

## Reproduzir tudo

```sh
make                      # modulos em C
make test-drivers         # propriedades do Atmos + equivalencia com passo1
make test-mutacoes        # o teste detecta erros injetados?
make metricas             # metricas de codigo e custo
```

## Convenções dos documentos

- Números de linha citados são da tag indicada (por exemplo,
  `game.lua:273` na `passo1`).
- "Referência" é sempre a tag do passo anterior, rodada num worktree em
  `build/ref-<tag>`.
- Números de desempenho são o mínimo de 5 execuções em pastas limpas
  (`tools/custo_drivers.py`).
- Problemas encontrados durante a validação ficam registrados, inclusive os
  causados pelo próprio teste (por exemplo, a seção 5.4 do passo 2).
