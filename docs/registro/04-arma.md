# Passo 4: a arma do jogador em concorrência estruturada

- Branch: `atmos`
- Referência de equivalência: tag `passo1` (nenhum subpasso muda o
  comportamento)
- Linhas citadas como "antes": tag `passo3`
- Resultado: tag `passo4` (ao fim do passo)

Este registro cresce a cada commit do passo 4: uma seção por subpasso.

| Subpasso | Commit | Situação |
|---|---|---|
| 4a. Arma por equivalência | (este commit) | concluído |
| 4b. Fidelidade ao `p_pspr.c` | – | opcional; muda o jogo de propósito (fica para a fase de correções, `docs/DIFERENCAS_DOOM.md`) |

---

## Subpasso 4a: a arma como task, por equivalência

### Resumo

A máquina de estados da arma (`weapon_think`, chamada no meio de
`player.think`) virou a task `Arma` (`arma.atm`). O `Nivel` emite um evento
novo, `:game.arma`, entre as duas metades de `player.think`, no ponto exato
em que `weapon_think` era chamada, e a task acorda nele. Cada fase da arma
(subir, pronta, atirar, baixar) é uma função que roda um tic por vez até a
fase mudar, e o clarão do tiro é um ramo paralelo. A fase continua em
`player.psprite_state`, pelos mesmos motivos da porta (passo 3b). O replay é
idêntico nos 9 roteiros, mas o resultado de expressividade é **negativo** em
tamanho: é o caso em que a task rende menos (seção "Métricas").

### Situação antes (tag `passo3`)

- `weapon_think` (`player.lua:761`): a cada tic, na ordem:
  1. jogador morto: só `lower_weapon` e sai;
  2. sem munição: pede a troca em `pendingweapon`;
  3. conta o clarão (`flash_tics`; no fim apaga `psprite_flash` e
     `extralight`);
  4. despacha por `psprite_state`: `"atk"` (um passo da sequência
     `WEAPON_ATK` a cada `psprite_tics`); troca pedida ou `"down"`
     (`lower_weapon`); `"up"` (`raise_weapon`); gatilho (começa o tiro);
     senão, `"ready"` (balanço, `tick_ready`).

  São 7 `return` no meio do tic.
- `player.think` (`player.lua:877`) chama `weapon_think` depois do "use" e
  da troca de arma pelo teclado, e antes dos poderes (`player.lua:910`). O
  jogador morto chama pelo `death_think` (`player.lua:871`).
- As partes de um tic (`start_ready`, `tick_ready`, `enter_atk_step`,
  `lower_weapon`, `raise_weapon`, `player.lua:647` a `749`) e as tabelas
  (`WEAPON_PATCH`, `WEAPON_ATK`, `WEAPON_READY`…) leem e escrevem os campos
  `psprite_*` do jogador.
- Quem mais lê esses campos: o renderer (`psprite_body`, `psprite_flash`,
  `psprite_sy`), a barra de status (`attackdown`), o save (todos os
  `psprite_*`, `flash_tics`, `refire`, `extralight`) e o hash de estado
  (`psprite_state`, `psprite_sy`).
- Quem escreve `pendingweapon` de fora, no meio do tic: o teclado
  (`player.think`), os itens apanhados (`touch_special`, nos mobjs) e a
  falta de munição.

### Solução

**O ponto do tic.** `player.think` virou `think_antes` (até a troca de arma
pelo teclado; o morto faz o `death_think` sem a arma) e `think_depois`
(poderes, contadores; o morto só testa o "use" para renascer). No `game.lua`,
`G.tic_view_antes` termina em `think_antes`, e `G.tic_view_meio` (novo)
começa em `think_depois`. O `Nivel` fica:

```
val antes = G.tic_view_antes()    ;; "segue" | "parado"
val fim = ifs {
    (antes == :segue) => {
        emit :game.arma           ;; passo 4a: task Arma
        val meio = G.tic_view_meio()  ;; "segue" | "morte"
        ifs {
            (meio == :morte) => :morte
            else => {
                emit :game.specials
                G.tic_view_depois()   ;; nil | "saida"
            }
        }
    }
    else => nil
}
```

A task nasce no `Nivel` depois de montar o nível
(`spawn arma.Arma(G.game.player, G.game)`): o jogador é o do nível, e o load
já restaurou a fase.

**A task.**

```
val func tic (p, game) {          ;; morto: baixa e devolve nil
    await :game.arma
    A.arma_comeco(p, game)        ;; vivo: [firing, ammo_type, can_fire]
}

val func atirar (p, game) {       ;; fase "atk"
    loop {
        val c = tic(p, game)
        if c {
            if c.firing { set p.attackdown = true }
            if p.psprite_tics > 0 { set p.psprite_tics = p.psprite_tics - 1 }
            if p.psprite_tics <= 0 {
                set p.psprite_step = p.psprite_step + 1
                A.arma_passo(p, game, c.ammo_type, c.firing, c.can_fire)
            }
        }
        until (p.psprite_state != :atk)
    }
}
;; subir, baixar e pronta: o mesmo molde

val task Arma (p, game) {
    set pub = p
    par {
        clarao(p)                 ;; ramo 1: conta flash_tics
    } with {
        loop {                    ;; ramo 2: a fase
            val st = p.psprite_state
            ifs {
                (st == :up) => subir(p, game)
                (st == :down) => baixar(p, game)
                (st == :atk) || (st == :fire) => atirar(p, game)
                else => pronta(p, game)
            }
        }
    }
}
```

**Por que a fase continua no registro.** Três leitores de fora (renderer,
save, hash) e um escritor de fora no meio do tic (`pendingweapon`). É o
mesmo quadro da porta e do elevador, e pela regra registrada nas notas
(`docs/NOTAS_MONOGRAFIA.md`, seção 7), a fase fica no registro. O
`watching :arma.trocar` do plano não serve: um evento emitido de dentro do
Lua quebraria a regra 4.3 (`CLAUDE.md`), e um evento emitido depois mudaria
o tic em que a troca começa.

**O clarão.** O plano previa uma task que "termina sozinha". Não é
equivalente: o clarão novo sobrescreve o antigo (`flash_tics` é reescrito no
passo do tiro e no plasma), o save grava `flash_tics`, e o morto não conta.
Ficou um ramo do `par` que conta o campo. A ordem entre os ramos importa (P6):
o clarão conta **antes** da fase, porque o tiro deste tic liga um clarão novo
que só começa a contar no próximo. A mutação `clarao-depois-da-fase`
inverte os ramos e é detectada.

### Diagramas

**Fluxo em Lua, antes (tag `passo3`):**

```mermaid
flowchart TD
    NV["Nivel: loop on :game.tic"] --> TA["G.tic_view_antes"]
    TA --> TH["player.think"]
    TH --> P1["movimento, use, troca pelo teclado"]
    P1 --> WT["weapon_think"]
    WT --> M{"morto?"}
    M -->|sim| LW["lower_weapon"]
    M -->|não| AM["munição; clarão (flash_tics)"]
    AM --> D{"psprite_state"}
    D -->|atk| AT["enter_atk_step"]
    D -->|"troca ou down"| LW
    D -->|up| RW["raise_weapon"]
    D -->|"ready + gatilho"| AT
    D -->|ready| TR["tick_ready"]
    WT --> P2["poderes, contadores"]
    P2 --> FX["tick_fx, renascer, thinker.tick"]
```

**Fluxo depois:**

```mermaid
flowchart TD
    NV["Nivel: loop on :game.tic"] --> TA["G.tic_view_antes"]
    TA --> TH1["player.think_antes<br/>movimento, use, troca pelo teclado"]
    NV --> EA["emit :game.arma"]
    EA --> AR["task Arma"]
    AR --> CL["ramo 1: clarao (flash_tics)"]
    AR --> FS["ramo 2: subir / pronta / atirar / baixar"]
    FS --> AC["player.arma_comeco: morto? munição"]
    FS --> PT["arma_baixar, arma_subir, arma_passo,<br/>arma_pronta, arma_balanco (Lua)"]
    NV --> TM["G.tic_view_meio"]
    TM --> TH2["player.think_depois<br/>poderes, contadores, renascer"]
    TM --> FX["tick_fx, thinker.tick"]
    NV --> ES["emit :game.specials ..."]
```

**Máquina de estados da task `Arma`** (a fase é `psprite_state`):

```mermaid
stateDiagram-v2
    [*] --> Subindo: nível novo (up), ou a fase do load
    Subindo --> Pronta: chegou ao topo
    Subindo --> Baixando: troca pedida ou morto
    Pronta --> Atirando: gatilho, com munição
    Pronta --> Baixando: troca pedida ou morto
    Atirando --> Atirando: refire (gatilho preso)
    Atirando --> Pronta: fim da sequência
    Atirando --> Baixando: morto
    Baixando --> Subindo: embaixo, troca a arma
    Baixando --> Baixando: morto (fica embaixo)
```

O ramo do clarão não tem estados: conta `flash_tics` até zero, a cada tic,
com o jogador vivo.

### Validação

**Hash de estado.** Com `DOOM_REPLAY_SIDES=1`, o hash passou a incluir o
resto do que a arma escreve: `psprite_body`, `psprite_flash`, `flash_tics`,
`psprite_tics`, `psprite_step`, `pendingweapon`, `attackdown`, `refire` e
`extralight`. O mesmo trecho entrou na referência (`tests/ref-passo1.patch`).
Antes, só `psprite_state` e `psprite_sy` entravam.

**Roteiro `arma`** (`-warp 1 1`):

1. pistola atirando até acabar a munição: troca sozinha para o punho;
2. `iddqd`, `idkfa`, e cada arma atirando com o gatilho preso (pistola,
   escopeta, metralhadora, foguete, plasma, BFG, motosserra, punho);
3. troca no meio do tiro (a escopeta termina a sequência e só então baixa)
   e troca durante a subida;
4. a trava do lança-foguetes: trocar para ele atirando com a metralhadora
   (gatilho ainda preso desde a arma anterior) não atira até soltar; com o
   gatilho preso depois, ele atira em sequência (refire);
5. save no meio do tiro do BFG (slot 5: `psprite_state` `"atk"`, passo 3,
   arma 6) e load;
6. o jogador morre atirando (a arma baixa e fica embaixo) e renasce.

A cobertura foi conferida com prints numa cópia de `arma.atm` (cada fase,
com a arma e a troca pedida; um print na troca durante a subida). Dois
problemas apareceram assim:

- **toques perdidos:** duas trocas de arma não aconteciam. O toque de um
  quadro numa tecla de arma pode ser solto antes de algum tic o ver, porque a
  partir de certo ponto os quadros do replay alternam 0 e 2 tics (o mesmo
  efeito do passo 3d). As teclas de arma passaram a ficar presas por 3
  quadros;
- **troca na descida, não na subida:** a segunda tecla vinha cedo demais.
  Com 22 tics de espera, ela cai na subida (conferido pelo print);
- **a trava do lança-foguetes mal entendida:** o roteiro segurava o gatilho
  com o lança-foguetes já pronto, supondo que ele atirasse uma vez só. Ele
  atira em sequência (o refire acontece dentro de `enter_atk_step`, sem
  voltar à fase pronta). A trava (`arma_pode_atirar`, o `A_WeaponReady` do
  Doom) só vale ao chegar à fase pronta com o gatilho preso desde a arma
  anterior. A mutação `foguete-sem-soltar` sobreviveu e apontou isso; o
  roteiro passou a trocar para o lança-foguetes atirando com a metralhadora.

**Equivalência.** `make test-drivers`, idêntico à tag `passo1` nos 9
roteiros (incluindo `arma`: 2.993 quadros, 2.181 estados distintos); saves
iguais byte a byte. Os roteiros `fluxo` e semente 1 deram idêntico na
primeira execução.

**Mutações do 4a** (roteiro `arma`):

| Mutação | Erro simulado | 1º quadro | Quadros dif. | Save |
|---|---|---|---|---|
| `arma-depois-do-jogador` | a arma acorda depois do resto do jogador e dos mobjs | 45 | 843 | difere |
| `clarao-depois-da-fase` | o ramo do clarão depois da fase | 45 | 904 | – |
| `clarao-conta-morto` | o clarão conta com o jogador morto | 2.738 | 256 | – |
| `troca-ignorada-na-subida` | trocar durante a subida não baixa a arma | 1.906 | 37 | – |
| `tiro-sem-gatilho-preso` | no tiro, o gatilho não marca `attackdown` | – | 0 | **equivalente** |
| `pronta-nao-zera-refire` | soltar o gatilho não zera `refire` | 1.698 | 297 | – |
| `foguete-sem-soltar` | lança-foguetes e BFG sem a trava do gatilho | 1.785 | 1.209 | difere |
| `load-perde-fase-da-arma` | o load não restaura a fase da arma | 2.371 | 17 | – |

`tiro-sem-gatilho-preso` é **equivalente**: durante o tiro, `attackdown` já
é verdadeiro (ligado ao começar o tiro e por `do_shot`; só desligado na
saída para a fase pronta), e o save o grava verdadeiro no meio do tiro. A
linha é redundante na task como era no `weapon_think`; a justificativa está
em `EQUIVALENTES`.

`make test-mutacoes` (todas as mutações do projeto): **51/53 não equivalentes detectadas**, 5 equivalentes justificadas, 2 pendentes.

### Métricas

`python3 tools/metricas_passo4.py` (novo; compara `weapon_think` com a task
`Arma` mais `arma_comeco` e `arma_pode_atirar`; as partes de um tic que não
mudaram ficam de fora dos dois lados):

| Métrica | Antes | Depois |
|---|---|---|
| Linhas de código (Lua) | 79 | 31 |
| Linhas de código (Atmos) | – | 104 |
| Linhas de código (total) | 79 | 135 |
| Campos do jogador lidos ou escritos | 16 | 16 |
| Comparações com a fase | 4 | 12 |
| Decrementos de contador | 2 | 2 |
| `return` no meio do tic (Lua) | 7 | 3 |

**O resultado é negativo em tamanho**, e a monografia deve dizer isso com
clareza. A arma reúne tudo o que, pelas notas, devolve a fase para os dados:
é interrompível a qualquer momento (troca pedida, morte), tem um escritor de
fora no meio do tic e é lida por três consumidores. A task não guarda
nenhum estado a menos (os 16 campos são os mesmos), e cada fase precisa
testar a própria saída (`until (p.psprite_state != :atk)`), o que triplica
as comparações com a fase. O ganho é só de organização: cada fase é uma
função com um laço, sem os 7 `return` do despacho, e o clarão é um ramo
separado em vez de um trecho no meio do tic. Comparado com as luzes (3a),
em que a fase sumiu para dentro do código, a arma é o outro extremo da
mesma régua.

### Custo

`python3 tools/custo_drivers.py 5 [roteiro]` (ms por quadro):

Com `CUSTO_TAGS=passo2,passo3` (o script passou a aceitar as tags
intermediárias; antes só media a `passo2`):

| Driver | `fluxo` | `arma` |
|---|---|---|
| `passo1` `main.lua` | 0,748 | 0,700 |
| `passo1` `main.atm` | 0,803 | 0,687 |
| `passo2` `main.atm` | 0,836 | 0,744 |
| `passo3` `main.atm` | 0,875 | 0,777 |
| atual (4a) | 0,904 | 0,812 |

O custo do 4a sozinho (atual contra `passo3`) é de +3,3% no `fluxo` e +4,5%
no `arma`: um `emit` a mais por tic (`:game.arma`), que acorda dois ramos
(clarão e fase), e uma tabela nova por tic em `arma_comeco`. Contra o
`passo1` `main.lua`, o atual custa +20,8% no `fluxo`; esse é o custo
acumulado dos passos 1 a 4.

### Diferenças conhecidas

Nenhuma no comportamento. Do Doom original: a arma usa tabelas próprias, e
não os estados de `info.STATES` e as ações do `p_pspr.c`
(`docs/DIFERENCAS_DOOM.md`, seção 4). Corrigir isso é o 4b, que pela decisão
registrada no topo do `DIFERENCAS_DOOM.md` fica para a fase de correções,
depois de todos os passos, nas duas branches.

### Como reproduzir

```sh
make test-drivers                  # P1-P9 + 9 roteiros; saves comparados byte a byte
make test-mutacoes
python3 tools/metricas_passo4.py
sh tests/test_drivers.sh 0 1 arma -warp 1 1 >/dev/null
CUSTO_TAGS=passo2,passo3 python3 tools/custo_drivers.py 5
CUSTO_TAGS=passo2,passo3 python3 tools/custo_drivers.py 5 build/drivers/replay_1arma.txt -warp 1 1
python3 tools/diagramas.py
```

### Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `arma.atm` | novo: task `Arma`, fases `subir`, `pronta`, `atirar`, `baixar`, ramo `clarao` |
| `player.lua` | `think_antes` e `think_depois` (com `M.think` para os testes unitários); `arma_comeco`, `arma_pode_atirar` e as partes de um tic expostas; saiu o despacho de `weapon_think` |
| `game.lua` | `G.tic_view_meio`; campos da arma no hash de estado |
| `main.atm` | `emit :game.arma` no `Nivel`; a task `Arma` nasce depois de montar o nível |
| `tests/ref-passo1.patch` | campos da arma no hash da referência |
| `tools/make_replay.lua` | roteiro `arma` |
| `tests/test_drivers.sh` | cobertura do roteiro `arma` |
| `tools/mutacoes.py` | roteiro `arma`; 8 mutações do 4a (1 equivalente); trecho de `specials-no-fim-do-tic` com a indentação nova |
| `tools/metricas_passo4.py` | novo |
| `tools/custo_drivers.py` | `CUSTO_TAGS`: mede outras tags intermediárias além da `passo2` |
| `Makefile` | roteiro `arma` |
