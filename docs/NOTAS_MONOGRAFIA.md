# Notas para a monografia

Discussões e trabalhos futuros que surgiram durante a migração e que não
fazem parte dos passos do plano ([PLANO_ATMOS.md](PLANO_ATMOS.md)). Servem de
material para os capítulos de discussão (6) e de conclusão (7).

---

## 1. Save game e estado implícito no fluxo de controle

Ponto levantado durante o passo 2: o load pode não funcionar tão bem em
concorrência estruturada. Ele afeta diretamente o passo 3f.

### 1.1 Onde fica o estado em cada modelo

- **Thinker (Lua):** todo o estado de uma porta fica em campos de uma tabela
  (`direction`, `topcountdown`, `speed`, `topheight`). O save grava os
  campos e o load os recria (`saveg.lua`). A entidade é só dado.
- **Task (Atmos):** boa parte do estado fica em **que ponto do código a task
  está parada** (em qual `await`, em qual volta do `loop`, dentro de qual
  `watching`) e nas variáveis locais vivas. É isso que torna o código
  expressivo: `direction` e `topcountdown` somem porque a sequência "abrir,
  esperar, fechar" é o próprio texto do programa. Por baixo, porém, esse
  estado é uma corrotina Lua suspensa, e corrotinas Lua não se serializam.

O problema não é que a estrutura obrigue a passar pelas transições. É que
**o estado implícito no fluxo de controle não é um dado**: para gravá-lo, é
preciso transformá-lo de volta em dado.

No passo 2 isso não apareceu: um save sempre cai dentro de um nível, e a
posição na árvore de tasks (`Fluxo` → `Jogo` → `Nivel(save)`) é deduzida
dos dados (episódio e mapa). O problema real começa no passo 3, com uma
porta salva no meio do movimento.

### 1.2 Saídas possíveis

| Saída | Como funciona | Custo |
|---|---|---|
| **Retomada por `pub`** (plano, 3f) | a task mantém em `pub` a fase e o contador; o load faz `spawn Porta(..., retomar=pub)` e um `ifs` no começo pula para a fase gravada | reintroduz parte do estado explícito eliminado; o código de retomada é um segundo caminho de entrada |
| **Reexecutar as transições** | gravar a entrada desde o início do nível e reexecutar até o ponto salvo (como os demos do Doom) | load lento; o save depende da versão exata do código; só funciona por causa do determinismo |
| **Salvar só em fronteiras** | permitir save só quando nenhuma task está no meio de algo (por exemplo, no começo do nível) | perde funcionalidade em relação ao Doom |
| **Híbrido** | a task só controla; o dado essencial (alturas, texturas) fica nos setores | já acontece em parte (as alturas ficam no setor) |

### 1.3 Efeito sobre bugs

**A favor:** sem caminho de retomada, todo estado alcançável foi produzido
pelo próprio código. Não existe uma porta com `direction = 0` e contador
negativo, combinação que nenhuma sequência de transições produz, mas que um
load campo a campo aceita se o arquivo for antigo, corrompido ou de outra
versão. As invariantes valem por construção.

Exemplo do lado do thinker, neste projeto: o save não grava as luzes, e no
load a fase delas recomeça do zero (plano, 3a). O estado depois do load não
é um estado a que o jogo chegaria jogando.

**Ressalvas:**
1. A proteção só vale enquanto não houver atalho. Com a retomada por `pub`,
   o load volta a poder criar estados que o código normal não alcança, e o
   `ifs` de retomada vira o lugar onde esse bug mora. A vantagem não some,
   mas fica concentrada num ponto em vez de espalhada.
2. Não é exclusivo do Atmos. Qualquer modelo com estado em continuações tem
   o mesmo problema (corrotinas, async/await, Céu). Um dos poucos casos que
   resolveram foi o Stackless Python, que serializa tasklets com `pickle`,
   ao custo de depender do interpretador. Isso reforça o argumento: é um
   custo do modelo, e não do Atmos em particular.

### 1.4 Como apresentar

Como um trade-off central, não como defeito nem como vantagem:

> O mesmo mecanismo que elimina o estado explícito (guardar a fase no fluxo
> de controle) é o que impede a serialização direta. Recuperá-la exige
> reintroduzir estado explícito num ponto controlado (a retomada), e o
> tamanho desse código mede quanto do ganho se perde.

O plano já prevê medir isso no passo 3f, contando quanto código de retomada
foi preciso. Esse número é a evidência concreta para a discussão.

---

## 2. Trabalho futuro: quadro por evento (`:game.frame`) e wipe como task

### 2.1 Situação no fim do passo 2

O tic já é despachado pelas tasks: a tela viva recebe `:game.tic` e chama a
sua função (`Nivel` → `G.tic_view`, `Intermissao` → `G.tic_intermission`,
`Finale` → `G.tic_finale`). O desenho, não: `paint_state` (`game.lua`,
dentro de `game.new`) ainda escolhe o que pintar com
`if game.gamestate == ...`. Por isso `game.gamestate` continua existindo,
como espelho somente leitura da tela atual (escrito só por `G.enter`).

A frase do plano "retire delas a mudança de gamestate" (passo 2, mudança 2)
foi cumprida: as funções que montam as telas não escrevem mais
`gamestate`. O que sobrou são as leituras.

### 2.2 Proposta

A task do quadro divide o `redraw` em duas partes e emite um evento no
meio, simétrico ao `:game.tic`:

```
loop on :frame {
    G.frame_antes()          ;; captura a tela antiga do wipe, se a tela mudou
    emit :game.frame         ;; so a tela viva desenha a si mesma
    G.frame_depois()         ;; captura a tela nova, menu, FPS, paleta, present
}
```

Cada task de tela ganharia um ramo `loop on :game.frame { ... }` que chama a
sua função de desenho (`paint_view`, `wi_mod.draw`, `finale_mod.draw`). As
funções de desenho e o renderer em C não mudam; muda só quem escolhe qual
chamar. Isso não inverte a lógica do motor.

**Melhor se feita junto com o wipe como task** (mudança 6 do passo 2,
adiada). Hoje o wipe usa `gamestate` também como memória: compara
`game.wipe_state` (tela do quadro anterior) com `game.gamestate` para
descobrir que a tela mudou. Com o wipe como task explícita entre telas
(`await Wipe(antes, depois)`), a troca deixa de ser detectada no redesenho e
`game.gamestate` pode sumir de vez.

**Justificativa:** o quadro ficaria simétrico ao tic. As duas metades do
laço do jogo seriam despachadas pela tela viva, e não por uma string
consultada em vários módulos.

### 2.3 Por que não agora

- É apresentação, não lógica de jogo; a pergunta de pesquisa é sobre estado
  e ciclo de vida da lógica.
- O Doom original faz o mesmo despacho por `gamestate` (`D_Display`, em
  `d_main.c`); manter facilita a comparação.
- Risco de mudar a temporização: a ordem fixa do `redraw` (captura do wipe,
  pintura, menu por cima) depende da propriedade P6 e de dividir o `redraw`
  no ponto certo.
- Também seria preciso tirar as leituras de `gamestate` do menu, dos
  cheats, do mouse e do automapa (encaminhar a entrada pela tela ativa).

**Alternativa intermediária,** se quiser só remover o `if`: `G.enter`
registra a função de pintura (`game.paint = paint_view`) e `paint_state`
vira `game.paint()`. Elimina o despacho, mas a variável continua.

---

## 3. Mutações pendentes de cobertura: o teste mostra o que não cobre

Surgiu no subpasso 0 do passo 3 (commit `fc557ad`). A mutação
`specials-no-fim-do-tic` move a fase de specials para depois de texturas,
saída, `leveltime` e barra de status. Ela sobreviveu ao roteiro `fluxo`, mas
**não é equivalente**:

- um esmagador ou um piso com `crush` fere o jogador dentro dos specials
  (`move_plane` → `change_sector` → dano);
- a barra de status lê `health` e `damagecount` para escolher o rosto;
- com a mutação, o rosto mudaria um tic depois.

O roteiro simplesmente nunca passa por um esmagador. Para registrar isso sem
esconder, `tools/mutacoes.py` ganhou uma categoria `PENDENTES`, separada das
`EQUIVALENTES`:

- a mutação aparece como "pendente", com o motivo e o roteiro que deve
  detectá-la (o de esmagadores, no passo 3d);
- quando esse roteiro passar a detectá-la, o script avisa "agora detectada:
  tire de PENDENTES".

**Para a monografia:** o teste de sensibilidade classifica cada mutante
sobrevivente em três grupos, e não em dois:

| Grupo | Significado | O que fazer |
|---|---|---|
| detectada | o roteiro cobre o comportamento | nada |
| equivalente | o mutante não muda o comportamento (com justificativa) | registrar o porquê |
| pendente | o mutante muda o comportamento, mas o roteiro não passa pelo caso | registrar o caso e o roteiro que vai cobri-lo |

Isso é um resultado do método: o teste mostra explicitamente o que o roteiro
ainda não cobre, em vez de deixar uma lacuna invisível ou forçar uma
justificativa falsa de equivalência.

---

## 4. Expressividade e seus contrapontos

Registrado depois do subpasso 3a (commit `9dd1641`).

**O lado a favor**, com um exemplo concreto: na luz pulsante (`Brilho`,
`setores.atm`), a versão imperativa guardava um campo `direction` e testava
esse campo a cada tic para decidir se a luz subia ou descia. Na task, são
dois laços em sequência (escurecer até o mínimo, clarear até o máximo): a
fase deixou de ser um dado e virou a **posição no código**. O mesmo vale
para o `count` das outras luzes, que virou `espera(n)`. Números do 3a
(`tools/metricas_passo3.py`): estado por luz de 10 campos para 5
parâmetros; despachos por `kind` e contadores manuais foram a zero.

**Os contrapontos**, que precisam ficar à vista porque são eles que dão
credibilidade ao resultado:

- **A expressividade vem de esconder o estado no fluxo de controle, e isso
  cobra no save.** Nas luzes não apareceu, porque elas não são salvas. A
  partir dos botões e das portas, a retomada por fase vai reintroduzir parte
  do estado explícito. O tamanho desse código é a medida honesta de quanto
  do ganho se perde (seção 1).
- **A ordem continua sendo responsabilidade de quem programa.** O Atmos é
  determinístico, mas foi preciso entender o runtime (propriedades P7 a P9,
  `tests/atmos_semantica.atm`) para garantir que as tasks acordam no mesmo
  ponto dos thinkers. Um `await` inicial esquecido muda o jogo, e só o
  replay pega isso.
- **Nem sempre o código fica menor.** No passo 2 o total de linhas
  **cresceu** (125 → 104 + 124). O ganho ali foi concentrar decisões
  espalhadas, não encurtar. No 3a encolheu (109 → 83), mas as luzes são o
  caso mais favorável: sequências puras, sem interação.
- **Há custo.** É pequeno (cerca de 0,3% de um tic de 28,6 ms), mas existe e
  cresce com o número de tasks. Os passos com muitas portas ou monstros vão
  dizer se continua desprezível.

**O teste decisivo** são as portas (3b): ali há interrupção de verdade (uma
porta fechando que reabre com outro "use" ou ao bater num monstro). É onde
`watching`, `emit @t` e `defer` deveriam mostrar uma vantagem que um `if`
sobre `direction` não tem. Se a expressividade se mantiver nesse caso, e não
só em sequências simples, o argumento fica bem mais forte.

**Resultado do teste decisivo (passo 3b, portas): misto.** Medido por
`tools/metricas_passo3.py`:

- o código **cresceu** (208 → 234 linhas) e o estado da porta **não
  diminuiu** (9 → 8 campos; só `kind` saiu);
- a porta pode ser interrompida a qualquer momento por um evento de fora (o
  "use") e precisa salvar a fase: nas duas versões, a fase é um dado
  (`direction`). Em Atmos, a porta continua sendo uma máquina de três
  estados, escrita como um laço com um despachante por fase;
- os ganhos são **estruturais**: a lista de thinkers e sua reconstrução
  sumiram (32 referências → 0); a liberação do setor está num `defer`, que
  roda também quando o nível aborta a porta; a ordem entre movimentadores
  está garantida por construção (uma pool só);
- o save **não** precisou de código de retomada separado, porque a fase já
  estava no registro por causa do recado.

Leitura para a monografia: as tasks reduzem estado quando o comportamento é
uma **sequência** (luzes) e perdem essa vantagem quando é uma **máquina
interrompível e serializável** (porta). Nesse caso, o ganho está no ciclo de
vida (criação, término, aborto, ordem), não no tamanho do código.

---

## 5. Eventos são imediatos; o Doom adia para a fase: o "recado no `pub`"

Surgiu ao planejar as portas (passo 3b).

**O caso.** Quando alguém aperta "use" numa porta que já está se movendo, o
Doom inverte a direção dela. No Lua antigo, isso é
`door.direction = -door.direction`, feito durante o pensamento do jogador
(etapa 3 do tic). Nada se move nessa hora: a porta só anda na fase de
specials (etapa 7), já na direção nova.

**A tentação em Atmos** seria a porta reagir a um evento:
`emit @porta :reabrir`. Mas um `emit` acorda a task **imediatamente**,
dentro do pensamento do jogador. A porta se moveria antes dos monstros e das
luzes, fora da ordem do Doom, e o replay divergiria.

**A solução: um recado no `pub`.** A porta não sai da pool e nenhuma task
nova é criada. O Lua, que sabe que o setor está ocupado
(`setor.specialdata` aponta para a task), só deixa um recado:

```lua
sector.specialdata.pub.inverter = true     -- não cria nem emite nada
```

e a própria task, na próxima fase de specials, lê o recado e muda de fase:

```
loop {
    await :game.specials
    if pub.inverter {               ;; recado do Lua
        set pub.inverter = false
        ;; troca de fase
    } else {
        ;; anda um passo na fase atual
    }
}
```

O Lua escreve na etapa 3 e a task lê na etapa 7 do mesmo tic, exatamente
como a mudança de `direction` era lida pelo `tick_door`.

**Para a monografia:**

- Os eventos do Atmos têm semântica **síncrona e imediata** (quem espera
  acorda dentro do `emit`). O Doom tem uma semântica de **fases**: uma
  mudança pedida em qualquer ponto do tic só produz efeito na fase da
  entidade. Quando as duas não coincidem, o canal certo não é um evento, e
  sim um **dado lido na fase** (o recado no `pub`).
- O argumento pode ser **demonstrado** com uma mutação: a variante com
  `emit` imediato tem de ser detectada pelo replay.
- Isso não anula a vantagem das tasks: o recado é lido num único ponto, e a
  sequência abrir → esperar → fechar continua linear. O risco a evitar é a
  task virar a mesma máquina de estados do Lua, só que em Atmos. A ideia é
  manter as fases como funções em sequência, cada uma devolvendo `:ok`,
  `:inverter` ou `:esmagou`, com o laço da porta decidindo a próxima.

---

## 6. Monstros: comportamento orientado a dados

Discussão do fim do passo 3b, sobre o escopo do passo 5 e de uma migração
"de todos os monstros".

### A tabela é um programa; o thinker é o interpretador

No Doom, o comportamento dos monstros **já é dado, não código**. Cada linha
de `info.STATES` é uma instrução (sprite, quadro, **duração em tics**,
**ação**, **próximo estado**). O Imp, em `info.lua`:

```lua
[442] = {[0]=0, 0, 10, 29, 443},   -- S_TROO_STND:  10 tics, A_Look, vai para 443
[443] = {[0]=0, 1, 10, 29, 442},   -- S_TROO_STND2: 10 tics, A_Look, volta para 442
[444] = {[0]=0, 0,  3, 30, 445},   -- S_TROO_RUN1:  3 tics, A_Chase (444 a 451: andar)
[452] = {[0]=0, 4,  8, 31, 453},   -- S_TROO_ATK1:  8 tics, A_FaceTarget
[454] = {[0]=0, 6,  6, 53, 444},   -- S_TROO_ATK3:  6 tics, A_TroopAttack, volta a andar
[456] = {[0]=0, 7,  2, 25, 444},   -- S_TROO_PAIN2: 2 tics, A_Pain, volta a andar
```

O "próximo estado" é um `goto`; as decisões ficam nas **ações**, que pulam
para outro estado (`A_Look` → andar ao ver o jogador; `A_Chase` → atacar;
o dano → dor, de qualquer lugar).

Há **uma função só para todos os objetos** (monstros, projéteis, sangue,
barris, lâmpadas):

| Peça | Uma por… | No código |
|---|---|---|
| Interpretador | jogo inteiro | `thinker.mobj_thinker`, `thinker.set_mobj_state` |
| Ações | compartilhadas; algumas por monstro | `enemy.call_action` (`Look`, `Chase`, `FaceTarget`; `TroopAttack` só o Imp) |
| Programa | tipo de objeto | as linhas de `info.STATES` (Imp: 442–474) |
| Pontos de entrada | tipo de objeto | `info.MOBJINFO`: `spawnstate`, `seestate`, `painstate`, `missilestate`, `deathstate` |
| Posição atual | cada objeto no mapa | `mo.istate`, `mo.tics` |

### Dois caminhos para migrar

| Caminho | Como | Custo depois da base | Ganho para o TCC |
|---|---|---|---|
| Interpretador em Atmos | uma task `Mobj` que lê `STATES` | baixo, cobre todos | quase nenhum: é o mesmo interpretador em outra linguagem |
| Um programa por tipo | "descompilar" as linhas de cada tipo numa task | ~meia sessão por tipo, com roteiro e mutações | alto: é onde a expressividade aparece |

"Descompilar" é reescrever os `goto`s da tabela como código estruturado:
**uma task por tipo, uma instância por objeto, e as linhas viram
instruções**. Sequências viram linhas seguidas; o estado que volta vira
`loop`; o pulo decidido por uma ação vira `until`; o pulo vindo de fora (dor,
morte) vira `watching`:

```
task Imp (mo) {
    watching :mobj.morreu {
        await Procurar(mo)            ;; 442-443 (A_Look)
        loop {
            watching :mobj.dor {
                loop {
                    await Perseguir(mo)       ;; 444-451 (A_Chase)
                    await AtaqueImp(mo)       ;; 452-454
                }
            }
            await Dor(mo)                     ;; 455-456 (A_Pain)
        }
    }
    await Morrer(mo)
}
```

A exigência de equivalência torna isso trabalhoso: cada `espera(n)` e cada
`P_Random` das ações tem de cair no mesmo tic que a tabela produziria.

### Quantos tipos

`info.lua` tem 18 tipos de monstro (a tabela veio completa do port em
Python), mas só **10 existem no Doom 1** (contagem nos `THINGS` do
`doom.wad`): Imp (31 mapas), Shotgun Guy (30), Demon (30), Spectre (27),
Cacodemon (24), Zombieman (22), Baron of Hell (22), Cyberdemon (5), Spider
Mastermind (2) e a Lost Soul (que não conta como "kill"). Na prática são
**~6 programas**: o Spectre é o Demon (mesmas linhas); Zombieman e Shotgun
Guy, Imp, Cacodemon e Baron compartilham o esqueleto; a Lost Soul e os chefes
são diferentes. Além dos monstros, o mesmo interpretador roda projéteis,
sangue, faíscas, barris, teleportes e objetos animados: é a "cauda" que
torna a migração completa uma questão de semanas.

### Para a monografia

Um terceiro tipo de resultado, ao lado das luzes e das portas:

| Comportamento | Exemplo | Resultado das tasks |
|---|---|---|
| sequência | luzes (3a) | ganho claro em estado e legibilidade |
| máquina interrompível e serializável | portas (3b) | ganho estrutural (ciclo de vida, ordem, limpeza), não de tamanho |
| orientado a dados | monstros (`STATES`) | só há ganho se a tabela for "descompilada"; aí aparece o **reuso por composição** (`Procurar`, `Perseguir`, `Dor` compartilhados) |

Recorte sugerido: o passo 5 (um monstro) mostra a coexistência dos dois
modelos; se sobrar tempo, migrar uma **família** que compartilha ações
(Zombieman + Shotgun Guy, ou Imp + Cacodemon + Baron) mostra o reuso a custo
marginal baixo, sem enfrentar a cauda inteira.
