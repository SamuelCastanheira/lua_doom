# Passo 3: specials de setor em concorrência estruturada

- Branch: `atmos`
- Referência de equivalência: tag `passo1` (a mesma do passo 2; nenhum
  subpasso muda o comportamento)
- Linhas citadas como "antes": tag `passo2`
- Resultado: tag `passo3` (ao fim de todos os subpassos)

Este registro cresce a cada commit do passo 3: uma seção por subpasso, na
ordem em que foram feitos.

| Subpasso | Commit | Situação |
|---|---|---|
| 0. Ponto do evento `:game.specials` | `fc557ad` | concluído |
| 3a. Luzes | (este commit) | concluído |
| 3e. Botões | – | próximo |
| 3b. Portas | – | planejado |
| 3c. Elevadores | – | planejado |
| 3d. Pisos, tetos, esmagadores, escadas, donut | – | planejado |

Ordem e justificativa: luzes primeiro porque só nascem ao montar o nível e o
save não as grava; botões em seguida porque são o caso mais simples criado
pelo Lua (`spawn_in`) e o primeiro com save; depois portas, elevadores e o
resto. Diferente do plano original, **o save de cada tipo é feito no mesmo
subpasso** (e não num 3f no fim): o roteiro `fluxo` salva e carrega no E1M4,
e uma porta em movimento sumiria no load assim que as portas virassem tasks.

---

## Subpasso 0: o ponto do evento `:game.specials`

### Resumo

Antes de migrar qualquer special, o tic de nível foi dividido para que as
tasks de setor possam acordar **no mesmo ponto** em que `specials_mod.tick`
rodava. Nada foi migrado neste subpasso; o replay continua idêntico.

### Situação antes (tag `passo2`)

`G.tic_view` (`game.lua:779`) fazia o tic inteiro e chamava
`specials_mod.tick(game.specials)` (`game.lua:808`) de dentro do Lua, entre
`thinker.tick` (mobjs) e `res:update_anims`.

### Solução

`G.tic_view` virou três funções, chamadas em ordem pela task `Nivel`:

```
loop on :game.tic {
    val antes = G.tic_view_antes()        ;; etapas 1-6: automapa ... mobjs
    val fim = ifs {
        (antes == :segue) => {
            emit :game.specials           ;; etapa 7: specials de setor
            G.tic_view_depois()           ;; etapas 8-11: texturas ... status
        }
        (antes == :morte) => :morte
        else => nil                       ;; "parado": fora da vista
    }
    ...
}
```

O que ainda é Lua roda numa task transparente do `Nivel`:

```
spawn {
    loop on :game.specials { G.specials_resto() }   ;; = specials_mod.tick
}
```

A cada subpasso, uma parte sai de `G.specials_resto` e ganha uma pool
declarada **antes** (luzes) ou **depois** (botões) dessa task. Pela
propriedade P7 (`tests/atmos_semantica.atm`), a ordem de declaração é a ordem
em que acordam, então a ordem do antigo `M.tick` (luzes → scroll → thinkers
→ botões) se mantém durante toda a migração.

O alcance padrão de um `emit` é a task corrente: `:game.specials` só alcança
a subárvore do `Nivel`, que é onde estão as pools.

### Validação

- `make test-drivers`: idêntico ao `passo1` nos 3 roteiros da época.
- Mutação nova `specials-no-fim-do-tic` (emitir `:game.specials` depois de
  `tic_view_depois`): **sobreviveu**, mas não é equivalente. Um esmagador
  fere o jogador dentro dos specials (`move_plane` → `change_sector`), e a
  barra de status leria a vida um tic antes. Nenhum roteiro passa por um
  esmagador. Para registrar isso sem esconder, `tools/mutacoes.py` ganhou a
  categoria `PENDENTES` (sobrevive sem falhar o teste, com o motivo e o
  roteiro que deve detectá-la, o de esmagadores do 3d). Discussão em
  `docs/NOTAS_MONOGRAFIA.md`, seção 3.

---

## Subpasso 3a: luzes

### Resumo

As quatro luzes animadas do Doom (pisca, estroboscópica, pulsante e fogo)
deixaram de ser itens de uma lista com `kind` e contador, despachados por um
`if` a cada tic, e viraram quatro tasks lineares em `setores.atm`. O
`specials.lua` só calcula a geometria (luz mínima dos vizinhos) e cria a
task com `spawn_in`. A lista `self.lights` e a função `tick_lights` sumiram.

### Situação antes (tag `passo2`)

- `M.new` criava `lights = {}` (`specials.lua:289`).
- `spawn_light_flash`, `spawn_strobe`, `spawn_glow` e `spawn_fire`
  (`specials.lua:309-369`) montavam uma tabela por luz e a acrescentavam a
  `self.lights`. `spawn_light_flash` e `spawn_strobe` consumiam `P_Random`
  na criação.
- `tick_lights` (`specials.lua:499`) percorria a lista a cada tic e
  despachava por `light.kind`: `glow` com `direction`; os outros com
  `count`, decrementado a cada tic, e uma ação quando chegava a zero.
- `M.spawn_specials` (`specials.lua:464`) cria as luzes na ordem dos setores
  do mapa, durante `game.build_level`, logo depois de `rng.clear()`.

### Solução

**Onde as tasks nascem.** As luzes nascem dentro de `game.build_level`, e o
`P_Random` da criação precisa ser consumido nesse mesmo ponto. Por isso a
pool existe **antes** de o nível ser montado:

```
task Nivel (save) {
    pin luzes = tasks()                   ;; 3a: luzes (setores.atm)
    G.set_pools([luzes=luzes])            ;; specials.lua cria as tasks nelas
    defer {
        G.set_pools(nil)
    }
    if save { G.load_level(save) } else { G.start_level() }
    ...
```

`build_level` passa `game.pools` a `specials_mod.new`, e cada `spawn_*`
chama `spawn_in(self.pools.luzes, T, ...)`. O `spawn_in` é síncrono (P8): a
task roda até o primeiro `await` antes de o Lua continuar, então o
`P_Random` do começo da task acontece exatamente onde o Lua o chamava. A
ordem da pool é a ordem dos setores, a mesma de `self.lights`.

**Fim do nível.** Quando o `Nivel` termina (saída, morte, `idclev`, load,
End Game), a pool e todas as luzes terminam juntas, e o `defer` limpa
`game.pools`. Antes, a lista era simplesmente recriada no nível seguinte.

**Testes unitários.** Sem `main.atm`, `pools` é `nil` e as luzes ficam
paradas (o mesmo padrão dos ramos "caminho antigo" do passo 2). O
`make test` não mudou.

### Comparação de código: a luz que pisca

Antes (`specials.lua`, tag `passo2`; criação e um ramo do despacho):

```lua
local function spawn_light_flash(self, sector)
  sector.special = 0
  local flash = {
    sector = sector, kind = "flash",
    maxlight = sector.lightlevel,
    minlight = min_surrounding_light(sector, sector.lightlevel),
    maxtime = 64, mintime = 7, count = 0,
  }
  flash.count = band(rng.p_random(), flash.maxtime) + 1
  self.lights[#self.lights + 1] = flash
  mark(self)
end

-- em tick_lights, a cada tic, para cada luz:
light.count = light.count - 1
if light.count == 0 then
  if light.kind == "flash" then
    if light.sector.lightlevel == light.maxlight then
      light.sector.lightlevel = light.minlight
      light.count = band(rng.p_random(), light.mintime) + 1
    else
      light.sector.lightlevel = light.maxlight
      light.count = band(rng.p_random(), light.maxtime) + 1
    end
  elseif light.kind == "strobe" then
  ...
```

Depois (`setores.atm`):

```
val task Pisca (setor, maxl, minl) {
    espera(band(rng.p_random(), 64) + 1)
    loop {
        if setor.lightlevel == maxl {
            set setor.lightlevel = minl
            espera(band(rng.p_random(), 7) + 1)
        } else {
            set setor.lightlevel = maxl
            espera(band(rng.p_random(), 64) + 1)
        }
    }
}
```

e no `specials.lua` sobra só a geometria e a criação:

```lua
local function spawn_light_flash(self, sector)
  sector.special = 0
  spawn_luz(self, "Pisca", sector, sector.lightlevel,
    min_surrounding_light(sector, sector.lightlevel))
end
```

O que mudou na leitura:

- O contador `count` deixou de ser um campo decrementado por um laço externo
  e virou o argumento de `espera(n)` (`loop in n { await :game.specials }`).
  "Esperar n tics e então trocar a luz" está escrito literalmente.
- O despacho por `kind` desapareceu: cada tipo é um programa. O glow, que
  antes guardava `direction`, virou dois laços em sequência (escurecer até o
  mínimo, clarear até o máximo):

```
val task Brilho (setor, maxl, minl) {
    loop {
        loop {                                ;; escurece ate o minimo
            await :game.specials
            set setor.lightlevel = setor.lightlevel - GLOWSPEED
            until (setor.lightlevel <= minl)
        }
        set setor.lightlevel = setor.lightlevel + GLOWSPEED
        loop {                                ;; clareia ate o maximo
            await :game.specials
            set setor.lightlevel = setor.lightlevel + GLOWSPEED
            until (setor.lightlevel >= maxl)
        }
        set setor.lightlevel = setor.lightlevel - GLOWSPEED
    }
}
```

- Constantes que eram campos por luz (`maxtime = 64`, `mintime = 7`,
  `brighttime`) voltaram a ser constantes no texto da task.

### Validação

**Equivalência.** `make test-drivers`, idêntico à tag `passo1`:

| Roteiro | Quadros | Estados distintos | Cobre |
|---|---|---|---|
| `fluxo` | 4.478 | 1.680 | todas as transições; luzes de E1M1, E1M2, E1M9, E1M4, E2M1 |
| semente 1 | 4.000 | 2.707 | jogo pseudoaleatório, 4 níveis |
| semente 2, `exits` | 6.000 | 1.437 | E1M8, finale |
| **`luzes`** (novo) | 2.619 | 1.964 | E4M1 (12 fogos, 1 pisca) e E1M2 (13 glows, 3 piscas, 10 strobes de todos os tipos) |

O hash de estado já inclui a luz de **todos** os setores a cada quadro,
olhando ou não para eles. Por isso nenhum campo novo entrou no
`G.state_string`: qualquer diferença de tempo numa luz aparece no
`lightlevel` em no máximo 64 tics (a maior espera, a do pisca).

**Roteiro `luzes`** (`tools/make_replay.lua <saida> 1200 1 luzes`, rodado
com `-warp 4 1`). Contagem por script dos setores com luz nos mapas dos
roteiros antigos mostrou que **nenhum tinha fogo** (o tipo 17 só existe no
episódio 4: E4M1, E4M2, E4M5, E4M6, E4M7, E4M8). O roteiro novo fica parado
(`iddqd`, girando de vez em quando) no E4M1 e, depois de `idclev12`, no
E1M2. Os monstros continuam atacando e consumindo `P_Random` entre as luzes,
o que testa a ordem dentro do tic. `tests/test_drivers.sh` confere que os
dois mapas foram visitados ("cobertura das luzes").

**Mutações.** `tools/mutacoes.py` passou a aceitar mutações em qualquer
arquivo e em qualquer roteiro (cada roteiro tem o seu log de referência,
`build/drivers/ref_<roteiro>.log`). Mutações do 3a, no roteiro `luzes`:

| Mutação | Arquivo | Erro simulado | 1º quadro | Quadros dif. |
|---|---|---|---|---|
| `pisca-sem-espera-inicial` | `setores.atm` | a luz age no tic em que nasce | 1 | 2.619 |
| `fogo-intervalo-3` | `setores.atm` | fogo a cada 3 tics em vez de 4 | 3 | 1.290 |
| `strobe-sincronizado-sorteia` | `setores.atm` | strobe sincronizado consome `P_Random` | 1.309 | 1.311 |
| `brilho-nao-volta` | `setores.atm` | glow inverte sem desfazer o último passo | 1.309 | 1.311 |
| `luzes-ordem-inversa` | `specials.lua` | pool criada na ordem inversa dos setores | 4 | 1.881 |
| `luzes-depois-do-resto` | `main.atm` | pool de luzes acorda depois do resto em Lua | – | 0 (equivalente) |

Resultado geral de `make test-mutacoes`: **15/16 mutações não equivalentes
detectadas**, 3 equivalentes justificadas, 1 pendente
(`specials-no-fim-do-tic`, do subpasso 0).

**Mutante equivalente `luzes-depois-do-resto`.** As luzes só escrevem
`lightlevel` e consomem `P_Random`. O resto ainda em Lua (scroll, portas,
elevadores, pisos, botões) não lê `lightlevel` e não consome `P_Random` no
tick: conferido nas funções `tick_*` e em `collision.change_sector`, que no
esmagamento só tira vida. No Doom original, `P_ChangeSector` solta sangue
com `P_Random` durante o esmagamento; num port fiel, esse mutante deixaria
de ser equivalente. Isso também é um resultado: a ordem entre luzes e
movimentadores só importa através do gerador aleatório compartilhado.

**Propriedades do runtime** (`tests/atmos_semantica.atm`, antes deste
subpasso): P7 (ordem das pools), P8 (`spawn_in` síncrono a partir do Lua) e
P9 (uma task criada no evento A acorda no evento B seguinte). P7 e P9 foram
conferidas com mutantes do próprio teste.

### Problemas encontrados

1. **Um mutante mal construído.** A primeira versão de
   `luzes-depois-do-resto` inseria uma segunda task do resto em vez de mover
   a existente, o que rodaria os specials Lua duas vezes por tic e testaria
   outra coisa. O trecho agora é extraído do `main.atm` e movido inteiro.
2. **Script de custo com caminho relativo.** `tools/custo_drivers.py` passava
   o roteiro com caminho relativo para um processo rodando em outra pasta, e
   a referência falhava. O caminho agora é absoluto.
3. **Linha 17 (strobe por linha) sem cobertura possível.**
   `M.start_light_strobing` também cria luzes (pelo mesmo `spawn_strobe`),
   mas nenhum mapa do `doom.wad` usa a linha 17. O caminho está migrado, mas
   não é exercitado por nenhum roteiro.

### Métricas

`python3 tools/metricas_passo3.py` (tag `passo2` × árvore atual; funções de
luz em `specials.lua` e `setores.atm`):

| Métrica | Antes | Depois |
|---|---|---|
| Linhas de código (Lua) | 109 | 30 |
| Linhas de código (Atmos) | – | 53 |
| Linhas de código (total) | 109 | 83 |
| Estado por entidade (campos da tabela × parâmetros da task) | 10 | 5 |
| Ramos de despacho por tipo (`kind ==`) | 4 | 0 |
| Contadores manuais (`.count`) | 9 | 0 |
| Referências à lista (`self.lights`, `specials.lua` inteiro) | 10 | 0 |

Os campos antes: `sector`, `kind`, `maxlight`, `minlight`, `maxtime`,
`mintime`, `count`, `darktime`, `brighttime`, `direction`. Depois:
`setor`, `maxl`, `minl`, `escuro`, `sincronizado`. Nenhuma local das tasks
atravessa um `await`; a fase (`direction`, `count`) está na posição do
código.

### Custo

`python3 tools/custo_drivers.py 5 [roteiro]` (mínimo de 5 execuções, pastas
limpas, inicialização descontada; o script ganhou o driver `passo2-atm`,
num worktree em `build/ref-passo2`):

| Driver | `fluxo` (ms/quadro) | `luzes` (ms/quadro) |
|---|---|---|
| `passo1` `main.lua` (imperativo) | 0,733 | 0,904 |
| `passo1` `main.atm` | 0,790 | 0,959 |
| `passo2` `main.atm` | 0,826 | 0,996 |
| atual (3a) | 0,864 | 1,089 |

O 3a custa +0,038 ms por quadro no `fluxo` e +0,093 ms no `luzes`, que tem
13 luzes no E4M1 e 26 no E1M2. São 0,3% de um tic (28,6 ms). Nesta máquina,
nesta sessão, o `passo1` imperativo mediu 0,733 ms (no registro do passo 2,
0,836 ms): compare sempre drivers medidos na mesma execução.

### Diferenças conhecidas

Nenhuma no comportamento. Fora do jogo (testes unitários com `game` falso),
as luzes não são animadas.

### Como reproduzir

```sh
make
make test-drivers                  # P1-P9 + 4 roteiros contra a tag passo1
make test-mutacoes                 # inclui as mutacoes do 3a (roteiro luzes)
python3 tools/metricas_passo3.py
sh tests/test_drivers.sh 0 1 fluxo >/dev/null
python3 tools/custo_drivers.py 5
sh tests/test_drivers.sh 1200 1 luzes -warp 4 1 >/dev/null
python3 tools/custo_drivers.py 5 build/drivers/replay_1luzes.txt -warp 4 1
```

### Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `setores.atm` (novo) | tasks `Pisca`, `Strobe`, `Brilho`, `Fogo` e `espera(n)` |
| `specials.lua` | `M.new` recebe `pools`; `spawn_*` de luz criam tasks com `spawn_in`; saíram `self.lights`, `tick_lights`, `GLOWSPEED`, `STROBEBRIGHT` |
| `game.lua` | `G.set_pools`; `build_level` passa `game.pools` a `specials_mod.new` |
| `main.atm` | `Nivel` declara a pool `luzes` antes de montar o nível, com `defer` |
| `tools/make_replay.lua` | roteiro `luzes` |
| `tests/test_drivers.sh` | cópia `ref_<roteiro>.log`; cobertura do roteiro `luzes` |
| `tools/mutacoes.py` | mutações em qualquer arquivo e roteiro; 6 mutações do 3a |
| `tools/metricas_passo3.py` (novo) | métricas por subpasso |
| `tools/custo_drivers.py` | driver `passo2-atm`; argumentos do jogo; caminho absoluto |
| `Makefile` | roteiro `luzes` em `test-drivers` e `test-mutacoes` |
