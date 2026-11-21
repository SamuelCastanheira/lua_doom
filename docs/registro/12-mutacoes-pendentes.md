# B2: as mutações pendentes ganham roteiro

Item B2 do `docs/PLANO_ATMOS.md` (seção 6, "Depois do passo 7"). Só teste:
o jogo não muda. Referências: a tag `passo1` (com `tests/ref-passo1.patch`)
e a branch `lua`.

## Resumo

Três mutações sobreviviam por falta de cenário (`PENDENTES` em
`tools/mutacoes.py`):

| Mutação | Erro simulado | Cenário que faltava |
|---|---|---|
| `usar-antes-de-mover` (passo 4c) | o jogador usa as linhas antes de se mover no tic | "use" apertado no tic em que o movimento põe a linha ao alcance |
| `portas-fora-de-movers` (passo 3b) | as portas numa pool própria, depois dos outros movimentadores | porta e elevador vizinhos andando no mesmo tic, com um mobj na fronteira |
| `portas-fora-de-movers-fluxo` | a mesma, no roteiro `fluxo` | o mesmo |

O roteiro novo **`ordem`** (`-warp 1 3`) monta os dois cenários no E1M3, e
as duas mutações passam a ser detectadas. A terceira era a mesma mutação
num roteiro que nunca passa pelo cenário; ela saiu da lista. `PENDENTES`
ficou vazio.

## Cenário 1: "use" no tic em que a linha entra no alcance

No tic do jogador (`jogador.atm`), `mover` vem antes de `usar`. O "use"
traça 64 unidades a partir do centro, no ângulo do jogador
(`collision.use_lines`), então usar antes ou depois do movimento só muda
algo quando o movimento do tic põe a linha ao alcance (ou a tira).

**Montagem.** A porta da linha 995 (D1, a face sul da porta em frente ao
início do E1M3, em y = −3200) fica de frente para o jogador, que nasce
olhando para o norte (90°). O `goto` não muda o ângulo. O roteiro põe o
jogador a D unidades da linha, aperta "andar" e, dois quadros depois,
"use". Andando, o jogador anda 0,78, 1,49, 2,13… unidades por tic, e o
"use" cai no terceiro tic de movimento (no segundo ou no quarto, se o
relógio do replay der 0 ou 2 tics num quadro). D vai de 72 a 64. A porta é
D1 (abre uma vez), e a primeira tentativa em que ela abre é a do tic em que
o movimento chega ao alcance: a linha está ao alcance depois do movimento e
fora dele antes.

**Dois tropeços.** Na primeira montagem, o alvo era a linha 996 (y =
−3184), mas o "use" alcança antes a 995, a outra face da mesma porta (16
unidades mais perto); a porta abriu na primeira tentativa, "a 69
unidades". E o "use" apertado um quadro depois de "andar" caiu, numa das
tentativas, no mesmo tic do primeiro passo (o relógio do replay deu 0 e 2
tics nos dois quadros); com 0,78 unidade de movimento, nenhum D inteiro
separa as duas ordens. Os dois foram achados com prints numa cópia de
`collision.use_lines` (o tic, a posição e a fração da linha atingida).

## Cenário 2: porta e elevador vizinhos no mesmo tic

**Por que a ordem importa neste port.** `collision.change_sector` só
reajusta os mobjs cujo **centro** está no setor que andou (o Doom percorre
os mobjs dos blocos do setor). O reajuste (`thing_height_clip`) calcula o
chão e o teto pelos setores que o corpo toca. Um mobj com o centro numa
porta e o corpo sobre um elevador é reajustado só quando a porta anda, e vê
o chão do elevador do momento: o de antes ou o de depois de o elevador
andar no mesmo tic, conforme a ordem na pool `movers`.

**Montagem.** Um script procurou, em todos os mapas, setores de porta
vizinhos de elevadores com o chão acima do chão da porta. O E1M3 tem um
par: a porta-alçapão do setor 167 (aberta pela linha 231, W1, de 128 até
236) e o elevador do setor 165 (baixado pela linha 116, WR, de 176 até 128;
neste port, 1 unidade por tic), separados pela linha 233. O roteiro cruza a
231 e, um quadro depois, a 116: a porta é criada primeiro e anda antes do
elevador. Quando o jogador cabe entre o chão do elevador e o teto da porta,
o `goto` o põe com o centro na porta, a 10 unidades da linha 233, com o
corpo sobre o elevador. Durante 10 tics os dois andam juntos e o jogador
fica sobre o chão do elevador lido pela porta, 1 unidade acima do chão
atual (prints numa cópia de `G.tic_mundo_fim`):

| Tic | Teto da porta | Chão do elevador | `z` do jogador |
|---|---|---|---|
| 673 | 210 | 137 | 138 |
| 674 | 212 | 136 | 137 |
| … | … | … | … |
| 682 | 228 | 128 | 129 |
| 683 | 230 | 128 | 128 |

Com a mutação, as portas andam depois do elevador, e o jogador vê o chão do
mesmo tic. O hash grava o `z` dos mobjs.

**Um tropeço.** A primeira montagem baixava o elevador antes de abrir a
porta, com o jogador entrando enquanto o elevador subia. Os dois andaram
juntos, mas o elevador, criado antes, andava primeiro também com a
mutação (que só põe as portas depois dos outros): a ordem era a mesma. A
porta tem de ser criada antes.

## Validação

`sh tests/test_drivers.sh 0 1 ordem -warp 1 3`: idêntico à tag `passo1`
(815 quadros, 560 estados distintos) e à branch `lua`
(`REF_TAG=lua REF_DIR=build/branch-lua`).

| Mutação | 1º quadro | Quadros dif. |
|---|---|---|
| `usar-antes-de-mover` | 344 | 472 |
| `portas-fora-de-movers` | 674 | 10 |

A `portas-fora-de-movers` diverge exatamente nos 10 tics em que porta e
elevador andam juntos e depois volta a ser igual: o efeito é só o `z` do
jogador naqueles tics.

`make test-mutacoes` (todas as mutações do projeto): **88/88 não
equivalentes detectadas**, 7 equivalentes justificadas, **nenhuma
pendente** (antes: 86/89, com 3 pendentes; a variante no `fluxo` saiu da
conta).

## O que isto diz sobre o oráculo

As duas mutações eram plausíveis e não equivalentes, e sobreviveram desde
os passos 3b e 4c porque os roteiros não passavam pelo instante em que a
ordem decide. Montar os cenários exigiu saber, do código, **qual** estado a
ordem muda (o `z` de um mobj na fronteira; a fração da linha atingida pelo
"use") e onde no mapa isso acontece. É o limite do teste por replay já
visto no passo 9 (o caso `estranho`): a equivalência só é provada nos
caminhos que os roteiros percorrem, e os caminhos de uma condição de
corrida são estreitos (aqui, 10 tics e uma faixa de 1,5 unidade).

## Como reproduzir

```sh
sh tests/test_drivers.sh 0 1 ordem -warp 1 3
REF_TAG=lua REF_DIR=build/branch-lua sh tests/test_drivers.sh 0 1 ordem -warp 1 3
python3 tools/mutacoes.py usar-antes-de-mover portas-fora-de-movers
make test-mutacoes
```

## Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `tools/make_replay.lua` | roteiro `ordem` |
| `tests/test_drivers.sh` | cobertura do roteiro `ordem` |
| `Makefile` | roteiro `ordem` em `test-drivers`, `test-branches` e `test-mutacoes` |
| `tools/mutacoes.py` | roteiro `ordem`; `usar-antes-de-mover` e `portas-fora-de-movers` nele; `portas-fora-de-movers-fluxo` removida; `PENDENTES` vazio |
