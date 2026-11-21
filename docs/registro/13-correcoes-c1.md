# C1: as revisões do próprio port (o `carry` e o jogador esmagado)

Primeiro item da fase de correções (`docs/PLANO_ATMOS.md`, seção 6, "C").
É a primeira mudança **de comportamento** do projeto: cada correção foi
feita nas duas branches, `atmos` e `lua`, e a referência de equivalência
passou a ser a tag nova **`c1`** (a branch `lua` com as correções). A tag
`passo1` continua existindo; contra ela, as divergências são as esperadas
(abaixo).

## Resumo

| Correção | Antes | Depois | `atmos` | `lua` |
|---|---|---|---|---|
| O `carry` vaza para um jogo novo | um New Game na intermissão começava com as armas, a vida e a munição do jogo anterior | o jogo novo começa do zero, como o `G_InitNew` do Doom | `defer` no início de `task Jogo` (`main.atm`) | `game.carry = nil` no New Game (`menu.lua`) |
| O jogador esmagado não morre | o esmagamento tirava 10 de vida direto: sem cara de dor, ignorando o modo deus, e com vida 0 o jogador ficava de pé | o dano passa por `game.damage_mobj` (o `P_DamageMobj`): dor, armadura, modo deus, morte | `collision.dano_esmagar`, ligado em `game.lua` | o mesmo, ligado em `main.lua` |

As duas branches continuam idênticas em todos os roteiros (a tag `c1` é a
própria branch `lua`).

## 1. O `carry`

**O problema** (registro do passo 2, seção 8.1). `begin_exit` guarda em
`game.carry` o que o jogador leva ao próximo nível, e `start_level` aplica e
apaga. Um New Game escolhido no menu durante a intermissão começa com o
`carry` do jogo anterior.

**As duas correções.** Elas não são escritas no mesmo lugar, e a diferença
é o ponto para a monografia:

```
;; atmos (main.atm): o carry e do escopo Jogo
task Jogo (pedido) {
    defer {
        set G.game.carry = nil          ;; o carry e do Jogo: nao sobrevive a ele
    }                                   ;; (nem quando :jogo.novo o aborta)
    ...
}
```

```lua
-- lua (menu.lua): o New Game apaga o carry
elseif action == "skill" then
  self.game.carry = nil               -- jogo novo: nada do jogo anterior (G_InitNew)
  self.game.skill = choice
```

Na branch `atmos`, a correção diz **de quem** é o dado: o `carry` passa de
um `Nivel` ao seguinte dentro de um `Jogo`, e o `defer` o apaga quando o
`Jogo` termina, por qualquer motivo. Isso inclui o fim natural, o End Game,
o load e o aborto por `:jogo.novo` (o `par :any` do `Fluxo` aborta o `Jogo`
e roda o `defer` antes de começar o novo). Na branch `lua`, a correção diz
**quando** apagar: no ponto em que o menu começa um jogo novo. As outras
saídas já apagavam (`to_title`, `end_game`, `saveg.apply`), cada uma no seu
lugar. As duas dão o mesmo jogo, porque o `carry` só é lido em
`start_level`; mas a versão Lua depende de lembrar de todos os caminhos que
começam um jogo, e a Atmos não.

## 2. O jogador esmagado

**O problema** (`docs/DIFERENCAS_DOOM.md`, specials; achado no passo 3d).
`collision.change_sector` tirava 10 de vida por tic de quem não cabia, sem
passar pelo dano do jogo. O jogador ficava sem cara de dor (`damagecount`),
o modo deus não protegia e, com vida 0, `playerstate` não virava
`PST_DEAD`: o jogador continuava de pé e não tinha como renascer.

**A correção.** No Doom, o `PIT_ChangeSector` chama
`P_DamageMobj(thing, NULL, NULL, 10)`. Aqui, `change_sector` não tem o
`game` (é chamado por `specials.move_plane`, que só recebe o mundo). Em vez
de passar o `game` por todas as chamadas, `collision.lua` ganhou um gancho,
`collision.dano_esmagar`, que o jogo liga ao criar `game.damage_mobj`. Sem o
gancho (testes unitários), a vida continua sendo subtraída direto. O texto
de `change_sector` é o mesmo nas duas branches.

Para monstros, o dano agora também passa por `damage_mobj` (chance de dor,
morte com estado e item largado), como no Doom.

**Fica para o C4:** o Doom só esmaga a cada 4 tics (`leveltime & 3`) e solta
sangue com `P_Random`; este port continua esmagando a cada tic, sem sangue
(`docs/DIFERENCAS_DOOM.md`, "Esmagamento sem sangue nem restos").

## Roteiros

- **`correcoes`** (novo, `-warp 1 1`), o roteiro da fase de correções:
  `idkfa`, saída, New Game na intermissão e, no E1M1 do jogo novo, a troca
  para a escopeta e o tiro. Antes da correção, o jogador tinha a escopeta;
  depois, não.
- **`pisos`**: o segundo `iddqd` desliga o modo deus antes do esmagador do
  E2M2, e o jogador morre esmagado (prints numa cópia de
  `G.tic_mundo_fim`: a vida desce de 10 em 10, `damagecount` sobe e
  `playerstate` vira 1, `PST_DEAD`). Sem isso, com a correção, o modo deus o
  protegeria e o esmagamento não apareceria.

## Validação

**Contra a referência nova** (`make test-drivers`, tag `c1`): idêntico nos
14 roteiros, com os saves iguais byte a byte. A tag `c1` é a própria branch
`lua`, então o `make test-branches` compara o mesmo código. `make test`: 12
passam, as 8 falhas conhecidas. A janela abre e fecha limpo.

**Contra a referência antiga** (`REF_TAG=passo1`), as divergências são só
as esperadas:

| Roteiro | Contra `passo1` | Por quê |
|---|---|---|
| `correcoes` | diverge do quadro 236 ao fim | o jogo novo da intermissão não tem mais a escopeta do anterior |
| `pisos` | quadros 772–774 e 777–1.449; 2.295 ao fim | E2M2: o jogador morre esmagado (o `idclev` do quadro 1.429 começa o E2M4 e as duas versões voltam a ser iguais). E3M5: com o modo deus, o esmagador não tira mais vida |
| `fluxo` | quadros 4.076–4.238 | **o `carry`, num caminho que ninguém tinha notado** (abaixo) |
| os outros 11 | idênticos | |

**O `carry` já estava no roteiro `fluxo`.** O `fluxo` termina o E2M8 (fim
do episódio 2) e, no finale, escolhe New Game no menu. A tela final do
finale do Doom 1 não volta sozinha ao título, então o New Game acontece
durante o finale, com o `carry` da saída do E2M8 ainda guardado: o E2M1 do
jogo novo começava com a vida, as armas e a munição do jogo anterior. O
registro do passo 2 achou o bug com um roteiro à parte (New Game na
intermissão) e o considerou fora dos roteiros. Ele estava no `fluxo` desde
o passo 2, invisível porque a referência e a versão Atmos tinham o mesmo
defeito. Conferido rodando o `fluxo` com a `main.atm` sem o `defer`: diverge
da `c1` exatamente nos quadros 4.076–4.238. É outro limite do oráculo de
equivalência: ele prova que as duas versões fazem a mesma coisa, inclusive
o mesmo erro.

## Mutações

| Mutação | Erro simulado | Roteiro | 1º quadro | Quadros dif. |
|---|---|---|---|---|
| `carry-sem-defer` | o `Jogo` não apaga o `carry` ao terminar | `correcoes` | 236 | 199 |
| `esmagar-sem-dano-do-jogo` | o esmagamento volta a tirar a vida direto | `pisos` | 772 | 1.000 |

A `specials-no-fim-do-tic` (passo 3, subpasso 0), que dependia da vida 0 na
barra no esmagador do `pisos`, continua detectada (quadro 771, 6 quadros):
agora o que aparece é a cara de dor e a morte.

`make test-mutacoes`: **90/90 não equivalentes detectadas**, 7
equivalentes, nenhuma pendente.

## Como reproduzir

```sh
make test-drivers                 # contra a tag c1
make test-branches                # contra a branch lua
make test-mutacoes
sh tests/test_drivers.sh 0 1 correcoes -warp 1 1
REF_TAG=passo1 sh tests/test_drivers.sh 0 1 correcoes -warp 1 1   # diverge (esperado)
```

## Arquivos alterados

| Arquivo | Branch | Mudança |
|---|---|---|
| `main.atm` | `atmos` | `defer` no início de `task Jogo` |
| `menu.lua` | `lua` | `game.carry = nil` no New Game |
| `collision.lua` | as duas | gancho `dano_esmagar` em `change_sector` |
| `game.lua` / `main.lua` | `atmos` / `lua` | liga o gancho a `game.damage_mobj` |
| `tools/make_replay.lua` | `atmos` | roteiro `correcoes`; `pisos` sem o modo deus no esmagador |
| `tests/test_drivers.sh` | `atmos` | referência padrão `c1`; cobertura do roteiro `correcoes` |
| `Makefile` | `atmos` | roteiro `correcoes` nos três alvos |
| `tools/mutacoes.py` | `atmos` | roteiro `correcoes`; mutações do C1 |
| `tools/metricas_finais.py` | `atmos` | aceita a seção `# --- C1` |
