# Métricas finais da migração

Consolidação pedida na seção 7 do `docs/PLANO_ATMOS.md`, com os números de
todos os passos (1 a 6), para a monografia. As tabelas abaixo foram geradas
por `tools/metricas_finais.py` sobre a árvore da tag `passo6` (o estado
final da migração por equivalência), e só a tabela de casos de cancelamento
é qualitativa, montada a partir dos registros.

**Importante:** estas métricas se referem à versão **equivalente** (mesmo
jogo da tag `passo1`, quadro a quadro). A fase de correções
(`docs/DIFERENCAS_DOOM.md`) vem depois e muda o comportamento de propósito;
por isso as métricas foram tiradas antes dela.

---

## 1. Expressividade por entidade (na ordem da régua da fase)

Linhas de código sem comentários e sem linhas vazias; "estado" é o número
de campos guardados por entidade (ou lidos e escritos, na arma e no monstro),
como cada script o define. Antes: a tag anterior ao passo; depois: a árvore.

| Entidade | Exigências da régua | Linhas antes | Linhas depois | Variação | Estado antes | Estado depois |
|---|---|---|---|---|---|---|
| Luzes (3a) | nenhuma | 109 | 86 | -21% | 10 | 5 |
| Pisos e tetos (3d) | save (piso) | 196 | 202 | +3% | 11 | 12 |
| Botões (3e) | save | 55 | 49 | -11% | 4 | 4 |
| Portas (3b) | save, recado, interrupção | 208 | 215 | +3% | 9 | 8 |
| Elevadores (3c) | save, recado, interrupção | 157 | 180 | +15% | 10 | 9 |
| Jogador (4c) | as quatro | 82 | 118 | +44% | – | – |
| Arma (4a) | as quatro | 79 | 135 | +71% | 16 | 16 |
| Zombieman (5) | as quatro | 87 | 230 | +164% | 6 | 7 |
| Quadro e wipe (6) | nenhuma (o relógio) | 59 | 91 | +54% | – | – |

## 2. Pontos de limpeza manual

Ocorrências de `dead = true` e `specialdata = nil` no código (Lua e Atmos).
Hoje, as que restam estão nos `defer` das tasks: declaradas uma vez por
task e executadas também quando o `Nivel` aborta a task.

| Padrão | tag `passo2` | hoje | hoje, dentro de `defer` |
|---|---|---|---|
| `dead = true` | 5 | 4 | 4 |
| `specialdata = nil` | 5 | 4 | 4 |

## 3. Roteiros de equivalência (driver Atmos × tag `passo1`)

| Roteiro | Argumentos | Quadros | Estados distintos | Resultado |
|---|---|---|---|---|
| fluxo | `-` | 4.478 | 1.682 | idêntico |
| semente 1 | `-` | 4.000 | 2.707 | idêntico |
| exits | `-` | 6.000 | 1.437 | idêntico |
| luzes | `-warp 4 1` | 2.619 | 1.964 | idêntico |
| botoes | `-warp 1 1` | 851 | 587 | idêntico |
| portas | `-warp 1 1` | 2.958 | 2.161 | idêntico |
| elevadores | `-warp 1 3` | 2.098 | 1.615 | idêntico |
| pisos | `-warp 2 2` | 2.593 | 1.954 | idêntico |
| arma | `-warp 1 1` | 2.994 | 2.181 | idêntico |
| monstro | `-warp 1 2 -respawn` | 2.755 | 2.045 | idêntico |
| **total** | | 31.346 | | 0 divergências |

Semântica do Atmos: 9 propriedades verificadas (P1 a P9).

## 4. Mutações por passo

| Passo | Mutações | Detectadas | Equivalentes | Pendentes | Sobreviventes |
|---|---|---|---|---|---|
| 2 | 12 | 10 | 2 | 0 | 0 |
| 3 | 38 | 34 | 2 | 2 | 0 |
| 4 | 13 | 10 | 2 | 1 | 0 |
| 5 | 7 | 7 | 0 | 0 | 0 |
| 6 | 4 | 4 | 0 | 0 | 0 |
| **total** | 74 | 65 | 6 | 3 | 0 |

Resumo do `tools/mutacoes.py`: 65/68 não equivalentes detectadas.

## 5. Custo acumulado (ms por quadro, modo replay)

| Driver | `fluxo` | vs. `passo1` Lua | `monstro` | vs. `passo1` Lua |
|---|---|---|---|---|
| passo1 `main.lua` | 1,000 | +0,0% | 2,035 | +0,0% |
| passo1 `main.atm` | 1,070 | +7,0% | 2,110 | +3,7% |
| passo2 `main.atm` | 1,119 | +11,9% | 2,191 | +7,7% |
| passo3 `main.atm` | 1,180 | +18,0% | 2,419 | +18,9% |
| passo4 `main.atm` | 1,214 | +21,4% | 2,520 | +23,8% |
| passo5 `main.atm` | 1,434 | +43,4% | 3,193 | +56,9% |
| atual (`passo6`) | 1,498 | +49,8% | 3,281 | +61,2% |

O tic dura 28,6 ms a 35 Hz. As medições oscilam alguns por cento entre
séries (registro do passo 3d, seção de custo).

Os valores absolutos variam com a carga da máquina (nesta série, o `passo1`
em Lua deu 1,000 ms por quadro no `fluxo`; em outras, 0,74). As proporções
entre os drivers se repetem entre as séries.

## 6. Pico de memória Lua (roteiro `fluxo`)

`collectgarbage("count")` amostrado por um gancho de contagem (a cada 50.000
instruções da linha principal). É uma estimativa: as
tasks rodam em corrotinas, onde o gancho não está ativo, mas a memória é a
do estado Lua inteiro.

| Driver | Pico (KB) |
|---|---|
| passo1 `main.lua` | 21.910 |
| passo1 `main.atm` | 23.594 |
| atual (`passo6`) | 24.356 |

---

## 7. Casos de cancelamento

Quem trata cada interrupção, antes e depois. É a métrica "casos de
cancelamento" do plano; ela é qualitativa porque o que importa é **onde** o
caso é tratado, não quantas linhas tem.

| Caso | Lua (antes) | Atmos (hoje) |
|---|---|---|
| Usar a porta de novo enquanto ela anda (3b) | `spawn_door` inverte `door.direction`; `tick_door` lê no tic seguinte | o mesmo recado no registro (`porta.direction`); a task percebe na sua fase e troca de fase já nesse tic (`:troca`, `direto`) |
| Parar o elevador (3c) | `stop_plat` escreve `status` e um `count` enorme | o mesmo recado; `toggle` foi testado e **não** é equivalente (só o save mostrou) |
| Trocar de arma no meio do tiro (4a) | `enter_atk_step` não refaz o tiro se há `pendingweapon` | o mesmo trecho Lua (`arma_passo`), chamado pela fase `atirar` |
| Morrer com a arma em qualquer fase (4a) | o começo de `weapon_think` desvia para `lower_weapon` | `tic()`, comum a todas as fases, devolve `nil` e baixa a arma; a fase termina pela própria condição |
| Morrer (o jogador, 4c) | `if playerstate == PST_DEAD` no começo de `player.think` | o laço "vivo" termina e o laço "morto" começa no mesmo tic; a morte **não** aborta a `Arma` (a arma desce depois da morte) |
| Dor ou morte do monstro no meio de um comportamento (5) | o dano chama `set_mobj_state` e o interpretador segue a tabela | a task percebe o salto (`:salto`, `:aplicado`) e vai para o comportamento do estado novo |
| Fim do nível com entidades ativas (3 a 6) | as listas (`self.thinkers`, `self.lights`, `self.buttons`) são refeitas em `build_level`; campos `dead` e `specialdata = nil` à mão no fim de cada movimento | o `Nivel` termina e todas as tasks de dentro terminam juntas; os `defer` das tasks soltam o setor **também no aborto** |

O último caso é o único em que a concorrência estruturada trata o
cancelamento **sozinha**, pelo escopo. Nos outros, a exigência de
equivalência (o mesmo tic, o mesmo save) fez o cancelamento continuar sendo
um dado escrito por alguém de fora e lido pela task, como no código
imperativo.

## 8. Leitura dos números

**Expressividade.** A tabela 1 está na ordem da régua da fase
(`docs/NOTAS_MONOGRAFIA.md`, seção 8). O ganho cai à medida que as
exigências aumentam: as luzes, sem nenhuma, perderam 21% do código e metade
do estado; botões, pisos, portas e elevadores ficaram perto do empate; o
jogador, a arma e o monstro, com as quatro exigências, cresceram de 44% a
164%. O quadro e o wipe (passo 6) cresceram em linhas, mas tiraram o
despacho por `gamestate` do desenho e a pergunta "está no wipe?" de todo
tic (registro do passo 6). O Zombieman aparece com 230 linhas, e não as 221
do registro do passo 5, porque a medição é na árvore final: o caso
`estranho` e o laço otimizado (`G.pensar_ate_task`) entraram depois da
primeira medição.

**Limpeza manual.** Não diminuiu em número (de 5 para 4 de cada padrão),
mas mudou de natureza: as que restam estão todas nos `defer` das tasks, uma
por tipo de movimentador, e rodam também quando a task é abortada pelo fim
do nível. Antes, ficavam espalhadas no fim de cada `tick_*`, e o aborto do
nível era tratado pela reconstrução das listas.

**Correção.** Os 10 roteiros (31.346 quadros) deram idêntico à tag
`passo1`, com os saves iguais byte a byte, e as 9 propriedades do runtime
de que o código depende foram verificadas. Das 74 mutações, 65 foram
detectadas, 6 são equivalentes (com justificativa) e 3 dependem de cenários
que nenhum roteiro monta; nenhuma sobreviveu sem explicação.

**Custo.** Ao fim, o driver Atmos custa +49,8% por quadro no `fluxo` e
+61,2% no `monstro` em relação ao `passo1` em Lua. O maior salto é o do
passo 5 (de +21,4% para +43,4% no `fluxo`; de +23,8% para +56,9% no
`monstro`): um `emit` direcionado e o corpo da task por monstro, cerca de
16 µs por monstro por tic (registro do passo 5). Os outros passos somam de
3% a 7% cada. Em termos absolutos, todos os drivers ficam muito abaixo dos
28,6 ms de um tic.

**Memória.** O pico de memória Lua no `fluxo` passou de 21,9 MB (`passo1`
em Lua) para 24,4 MB hoje (+11%); só o driver Atmos do passo 1, sem nenhuma
task de jogo, já somava 1,7 MB (o runtime e as corrotinas das tasks de
tela).

## Como reproduzir

```sh
make test-drivers | tee build/test-drivers.log
make test-mutacoes | tee build/mutacoes.log
python3 tools/metricas_finais.py --custo --memoria
```
