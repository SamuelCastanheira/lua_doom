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

### 2.4 Desfecho (passo 6)

Feito no passo 6, com o replay idêntico nos 10 roteiros. O quadro emite
`:game.frame` e cada tela desenha a si mesma, como proposto em 2.2; o
`paint_state` sumiu. Um caminho de reserva (o despacho antigo, para um
quadro sem tela viva) foi medido antes de ser removido: zero usos no
roteiro `fluxo`, que passa por todas as transições. O wipe virou uma
**fase do relógio** (o tic normal e a transição em sequência, trocados por
`:tela.transicao`), mas não o `await Wipe(antes, depois)` entre telas: a
troca de tela continua detectada no quadro, porque o wipe só começa se a
tela mudou entre dois quadros, e chamar o wipe na troca mudaria esse ponto.
Por isso `game.gamestate` continua existindo. Detalhes em
`docs/registro/06-wipe-e-quadro.md`.

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

**Desfecho (passo 3d, commit `844e4f8`).** O roteiro `pisos` detecta a
mutação, mas só depois de dois ajustes que o próprio teste apontou. A barra
de status deste port só reage ao esmagamento quando a vida chega a 0 (o
esmagamento não mexe em `damagecount`), e a morte precisa cair num tic que
vire quadro (seção 7). A mutação saiu de `PENDENTES`, e o ciclo previsto
aqui se fechou: pendente → roteiro novo → detectada.

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

**Desfecho (passo 5).** O Zombieman virou a task `Zumbi`: as 33 linhas
`S_POSS_*` da tabela viraram sete comportamentos com nome e cinco
transições no código ("atacar, dor e levantar voltam a correr"). A previsão
da régua (seção 8) se confirmou: as ações e o dano trocam o estado de fora,
no meio do tic, e o renderer, o save e o hash leem `istate` e `tics`. A
task precisa perceber esses saltos e voltar ao comportamento certo a partir
de `istate`, o que é um despacho pelo estado: a forma de um interpretador,
agora com nomes. Em tamanho, o código mais que dobrou (87 → 221 linhas,
porque o interpretador Lua continua para os outros mobjs). O ganho é de
legibilidade do comportamento, que antes só existia nos ponteiros "próximo"
da tabela. Um achado colateral: o load aplica os mobjs por índice, e um
zumbi pode receber o estado de outro tipo de mobj (registrado como revisão
do port em `docs/DIFERENCAS_DOOM.md`, seção 5). Detalhes em
`docs/registro/05-monstro.md`.

---

## 7. Passo 3d: a fase no código, e o que o replay não mostra

Surgiu no subpasso 3d (pisos e tetos, commit `844e4f8`). Três pontos.

### O critério de onde fica a fase

O `Teto` é o primeiro movimentador cuja fase (descendo, subindo) vive só
no código: direção e velocidade são variáveis da task, e o esmagador que vai
e volta é um laço. Porta, elevador e piso guardam a fase no registro. A
diferença não é de gosto. Ela segue dois critérios, que valem para qualquer
entidade migrada:

| Alguém escreve na entidade de fora, no meio do tic? | O save grava a entidade? | Onde fica a fase | Exemplos |
|---|---|---|---|
| não | não | só no código | luzes (3a), teto (3d) |
| não | sim | no registro (o save lê) | botão (3e, só o timer), piso (3d) |
| sim (o recado) | sim | no registro | porta (3b), elevador (3c), arma (4a) |

Para a monografia, isso dá uma regra prática e um resultado: a concorrência
estruturada rende o máximo (a fase **é** a posição no código) quando a
entidade não é interrompida nem serializada. Cada uma dessas exigências
devolve parte da fase para os dados. No Doom original os tetos **são**
gravados e **podem** ser parados (linhas 57 e 74); se este port os
corrigisse, o `Teto` teria de voltar a guardar a fase no registro.

A arma (passo 4a) é o caso extremo da última linha: além do recado
(`pendingweapon`) e do save, três consumidores leem a fase (renderer, save,
hash), e ela é interrompida em qualquer fase (troca, morte). A task não
guardou nenhum campo a menos (16 antes e depois), o código cresceu de 79
para 135 linhas, e cada fase testa a própria saída. O único ganho foi de
organização (uma função por fase, sem os 7 `return` do despacho; o clarão
como ramo paralelo). Com as luzes num extremo e a arma no outro, a régua
fica completa (`docs/registro/04-arma.md`, "Métricas").

### O oráculo também tem pontos cegos

A mutação `specials-no-fim-do-tic` atrasa em um tic a reação da barra de
status. No E3M5, a cara de morto aparecia um tic depois no mutante
(conferido com prints no `ticker`), e mesmo assim **nenhum quadro diferia**:

- o relógio do replay soma `1000/35` por quadro, e o arredondamento faz os
  quadros alternarem 0 e 2 tics a partir de certo ponto;
- toda entrada do roteiro cai no início de um par, então a morte caía
  sempre no primeiro tic do par, e esse tic nunca vira quadro;
- deslocar a entrada em quadros não muda a paridade.

A detecção veio mudando o cenário (o esmagador do E2M2, mais cedo, quando os
tics ainda vêm um por quadro). Lição de método: o teste de equivalência
compara o que é **observado** (framebuffer e hash de estado por quadro). Um
efeito que dura um tic e não entra no hash pode passar entre dois quadros.
Pôr o rosto da barra no hash de estado teria pego a mutação em qualquer
cenário. Fica registrado como limite do oráculo, junto com a lição do 3e
(conferir que tudo o que o tipo migrado escreve está no hash).

### A migração por equivalência expõe o legado

O roteiro previa que o jogador esmagado renascesse com "use", e a lista de
telas mostrou que o nível não recomeçou. Este port subtrai a vida direto no
esmagamento, sem `P_DamageMobj`: com vida 0, o jogador continua de pé e não
renasce. A leitura de `p_ceilng.c` e `p_floor.c`, feita para documentar o
3d, achou mais cinco diferenças (desaceleração ao esmagar, linha 40, sons,
`special` do piso, escada). Todas ficaram como estavam e foram para
`docs/DIFERENCAS_DOOM.md`: a migração prova a equivalência com o port, não
com o Doom. Para a monografia, isso mostra um efeito colateral útil do
método: escrever roteiros que exercitam cada caminho, e conferir a cobertura
com prints, revela comportamentos que ninguém tinha notado no código
imperativo.

---

## 8. A régua da fase: das luzes à arma

Explicação pedida depois do passo 4a, para detalhar a seção 7. A pergunta
que se repete a cada entidade migrada é: **onde fica a fase dela?** Fase é
o "em que ponto estou" (subindo, esperando, atirando...). Ela pode morar no
**código**, como a posição dentro de um laço, ou nos **dados**, como um campo
numa tabela. A promessa da concorrência estruturada só se cumpre no primeiro
caso, e quatro exigências empurram a fase de volta para os dados. A arma tem
as quatro; as luzes não têm nenhuma.

### A promessa: a fase vira posição no código

A luz que pisca, antes, era um registro com contador e um despacho a cada
tic:

```lua
-- tag passo2 (simplificado)
if light.kind == "flash" then
  light.count = light.count - 1
  if light.count <= 0 then
    if sector.lightlevel == light.maxlight then
      sector.lightlevel = light.minlight
      light.count = (p_random() & 7) + 1
    else ...
```

Depois virou um programa linear:

```
val task Pisca (setor, maxl, minl) {
    espera(band(rng.p_random(), 64) + 1)
    loop {
        if setor.lightlevel == maxl {
            set setor.lightlevel = minl
            espera(band(rng.p_random(), 7) + 1)   ;; o contador sumiu aqui dentro
        } else { ... }
    }
}
```

O campo `count` e o `if kind ==` sumiram. A fase ("estou na espera curta") é
a linha em que a task está parada. É aí que a task rende: menos estado,
menos código, e a leitura segue a ordem do tempo.

### As quatro exigências que devolvem a fase aos dados

A posição no código tem um defeito: **só a própria task a enxerga**. Ninguém
de fora consegue perguntar "em que linha você está?", e o Atmos não consegue
gravar essa posição num arquivo (seção 1, o Stackless Python). Toda vez que
alguém de fora precisa da fase, ela tem de existir como campo.

**a) Leitores de fora.** Se alguém precisa saber a fase a qualquer momento,
ela tem de estar num campo legível.

- Na arma: o renderer desenha a arma a cada quadro lendo `psprite_body`,
  `psprite_flash` e `psprite_sy`, e o hash do replay lê `psprite_state`.
- Nas luzes: ninguém pergunta em que fase a luz está; só o efeito importa
  (`lightlevel`).

**b) Save e load.** O save precisa gravar a fase, e o load precisa recriar a
task **no meio** dela.

- A arma é gravada com `psprite_state`, `psprite_tics`, `psprite_step`,
  `flash_tics` e mais.
- No load, a task nova lê `psprite_state` para saber em que fase começar.
  Se a fase estivesse só no código, não haveria o que gravar.
- As luzes não são gravadas (no load, recomeçam do zero), e o teto também
  não.

**c) Escritor de fora no meio do tic (o "recado", seção 5).** Alguém que não
é a task muda algo que altera a fase dela.

- Na arma, `pendingweapon` é escrito pelo teclado (`think_antes`), por um
  item apanhado (`touch_special`, durante os mobjs) e pela falta de munição.
- A task precisa perceber isso **na sua fase**, no tic certo.
- A alternativa "pura" seria um evento (`watching :arma.trocar`, como o
  plano previa), mas há dois problemas:
  - o Lua não pode emitir eventos (regra 4.3 do `CLAUDE.md`: o `emit`
    poderia abortar quem está chamando);
  - um evento é imediato: a arma reagiria fora do seu ponto no tic, e o
    replay divergiria (a mutação `recado-vira-evento`, das portas, mostrou
    isso).
- Então a task lê o campo a cada tic.

**d) Interrupção em qualquer fase.** Se a fase pode ser cortada a qualquer
momento, cada fase precisa testar isso a cada tic.

- Na arma, a morte interrompe todas as fases, e a troca de arma interrompe
  a subida e a pronta.
- Por isso cada função de fase tem o mesmo formato:

```
val func atirar (p, game) {
    loop {
        val c = tic(p, game)          ;; morto? (testado em toda fase, todo tic)
        if c { ...um passo do tiro... }
        until (p.psprite_state != :atk)   ;; a fase mudou? (cada fase testa a sua saída)
    }
}
```

- A luz nunca é interrompida: ela existe do começo ao fim do nível.

### A régua

| Entidade | a) leitores de fora | b) save | c) recado | d) interrupção | Onde ficou a fase | Resultado |
|---|---|---|---|---|---|---|
| Luzes (3a) | não | não | não | não | só no código | ganho claro |
| Teto (3d) | não | não | não | não | só no código (`dir`, `vel`) | o desce-sobe virou o laço |
| Botão (3e), piso (3d) | não | sim | não | não | no registro (o save lê) | neutro |
| Porta (3b), elevador (3c) | não | sim | sim | sim (usar de novo, parar) | no registro | misto |
| **Arma (4a)** | **sim (3)** | **sim** | **sim** | **sim (morte, troca)** | no registro | **negativo em tamanho** |

Cada "sim" puxa um pedaço da fase de volta para os dados, e a arma tem
todos. Por isso ela está na ponta oposta das luzes.

**Confirmação do lado bom (passo 7).** A intermissão e o finale foram
escolhidos depois da régua, como teste da previsão: só o próprio desenho lê
a fase, nada vai para o save, o Lua não escreve nelas e a única interrupção
é entrada do jogador. O resultado bateu: o mesmo tamanho de código
(185 → 184 linhas), os campos de fase de 5 para 2 (os dois que o desenho
lê), as comparações com a fase de 17 para 0 e nenhum contador guardado em
campo. A contagem lê como a descrição da tela ("pausa, conta as mortes,
pausa, conta os itens..."). Com isso, a régua tem exemplos do próprio Doom
nos dois extremos: luzes, intermissão e finale de um lado; arma e monstro
do outro (`docs/registro/09-intermissao-e-finale.md`).

### Por que o código da arma cresceu

O `weapon_think` antigo era **uma** função com um despacho, que testava a
fase uma vez por tic:

```lua
if player.psprite_state == "atk" then ... return end
if player.pendingweapon ~= WP_NOCHANGE or player.psprite_state == "down" then ... return end
if player.psprite_state == "up" then ... return end
...
```

Na task, cada fase virou uma função com o próprio laço. Mas os testes não
sumiram, só se espalharam:

- a pergunta "morto?" (o `tic()` comum) aparece em todas;
- cada fase testa a própria saída (`until (... != :atk)`);
- a troca pedida aparece em duas fases;
- o laço externo ainda despacha pela fase (`ifs { (st == :up) => subir ... }`),
  porque depois de um load a task precisa começar na fase gravada.

Somando (`tools/metricas_passo4.py`):

- **linhas:** de 79 para 135;
- **comparações com a fase:** de 4 para 12;
- **campos do jogador:** os mesmos 16, porque todos continuam necessários
  para o renderer, o save e o recado.

O que se ganhou de fato é organização:

- cada fase é um trecho legível;
- não há 7 `return` no meio do tic;
- o clarão é um ramo separado;
- a task morre junto com o nível.

É real, mas não reduz nem estado nem tamanho.

### O que isso significa para o TCC

O resultado **não** é "Atmos é pior para armas". O que limita a task são as
**restrições da migração por equivalência**:

- o save tem de ter o mesmo formato, byte a byte;
- o renderer lê os mesmos campos;
- a troca de arma tem de acontecer no mesmo tic.

Essas restrições fixam o layout de dados do código imperativo, e a task tem
de conviver com ele.

A contribuição é transformar isso num **critério**: o ganho da concorrência
estruturada é inversamente proporcional a quanto a fase de uma entidade
precisa ser **observada, gravada, alterada ou interrompida de fora**. Com
zero dessas exigências (luzes, teto), a fase vira código e o ganho é grande.
Com todas (arma), a task vira uma reorganização do mesmo estado. Porta e
elevador ficam no meio.

Essa régua também ajuda a prever o passo 5 (monstros). Eles são lidos de
fora (renderer, colisão, mira de outros monstros), gravados no save e
interrompidos a qualquer momento (dor, morte). Pela régua, a expectativa é
um resultado mais parecido com a arma do que com as luzes, a menos que o
recorte escolhido evite algumas dessas exigências.

---

## 9. Corte por posição: etapas do motor x entidade não modelada

Surgiu de uma crítica do autor ao passo 4a. Para encaixar a task `Arma` no
ponto exato do tic, `player.think` foi dividido em `think_antes` e
`think_depois`, com `emit :game.arma` entre os dois. Os nomes não dizem
**o que** o jogador faz, só **onde** o corte caiu: é como se o thinker
continuasse existindo como uma função monolítica chamada pelo motor, só que
partida em dois pedaços. O Atmos não modelou o jogador; apenas remendou a
ordem do tic.

**A mesma crítica vale um nível acima.** `G.tic_view_antes`,
`G.tic_view_meio` e `G.tic_view_depois` também são cortes por posição. A
diferença é que eles espelham as **etapas do tic do motor**, que é uma noção
real do Doom (`G_Ticker` → `P_Ticker`: jogadores, thinkers, specials,
texturas, saída). Ali o corte é aceitável, talvez com nomes melhores, porque
nomeia uma estrutura que existe no domínio. **Dentro de uma entidade**, como
o jogador, o corte por posição é sintoma de que a entidade não foi modelada.

**Critério para a monografia:** um corte só para encaixar um `emit` é
aceitável quando separa etapas que o domínio reconhece (as fases do tic do
motor). Dentro de uma entidade, o corte deve virar partes com nome do
domínio (mover, pisar, usar, escolher a arma, contar os poderes) e, se a
entidade tiver fases (vivo, morto), laços em sequência numa task própria.

**Desdobramento previsto (subpasso 4c):** a task `Jogador`, com a `Arma`
como filha, as partes nomeadas e as fases vivo e morto como dois laços. A
variável `morto_no_tic` do `game.lua`, que só existe para atravessar o
`emit`, vira uma local da task. Antes, testar se a arma precisa mesmo ficar
no meio do tic do jogador: o que vem depois dela (poderes, efeito de tela,
contadores) parece não interagir com ela, e, se o replay confirmar, o corte
desaparece. Isso separa a ordem **semântica** (a arma antes dos monstros,
por causa do `P_Random`) da ordem que é só **herança do código original** (a
arma no meio do `P_PlayerThink`).

**Desfecho (subpasso 4c).** O experimento confirmou a suspeita: com a arma
depois de todas as partes do jogador, o replay é idêntico nos quatro
roteiros testados, e a mutação que a devolve ao meio (como no Doom) é
equivalente. O corte desapareceu. A task `Jogador` lê como a descrição do
tic (mover, pisar, usar, escolher a arma, contar os poderes e os avisos,
arma), e as fases vivo e morto são dois laços. Dois limites, ambos pela
equivalência: a morte não aborta a `Arma` (a arma continua descendo depois
da morte, e isso aparece na tela), e o `Nivel` ainda lê `playerstate` para
renascer, porque no tic de renascer o `tick_fx` roda antes de o nível
recomeçar. Em números, o código cresceu (82 → 118 linhas), mas uma função
de 82 linhas com um `if` de fase virou seis partes com nome e uma task de 29
linhas (`docs/registro/04-arma.md`, seção 4c).


---

## 10. Impressões gerais sobre o Atmos (depois dos passos 1 a 6)

Balanço pedido pelo autor ao fim do passo 6, apoiado no que foi medido nos
registros.

### Onde o Atmos brilha

**1. Sequência no tempo vira código linear.** É o ganho mais claro e mais
repetido. A luz que pisca, o teto que desce e sobe, o relógio com a fase do
wipe e o fluxo de telas do passo 2 (`Titulo → Jogo → Nivel → Saida`) deixaram
de ser contadores e `if estado ==` e viraram programas que se leem na ordem
em que acontecem. Quando nada de fora precisa saber em que ponto a entidade
está, a fase some para dentro do código, e com ela o estado.

**2. Ciclo de vida pelo escopo.** Esse ganho aparece até nos casos em que o
tamanho piorou. Quando o `Nivel` termina (morte, saída, load, troca de
nível), todas as tasks de dentro terminam juntas, e o `defer` limpa o
`specialdata`. Sumiram as listas `self.thinkers`, `self.lights` e
`self.buttons`, o campo `dead`, a reconstrução das listas a cada nível e a
limpeza manual. É uma classe inteira de erros, o "thinker esquecido vivo",
que deixa de existir por construção.

**3. Determinismo com semântica precisa.** Foi a surpresa mais importante. O
modelo síncrono tem regras exatas: a ordem de declaração das pools (P7), o
tic exato em que uma task nasce e age (P9), a ordem dos ramos (P6). Por isso
foi possível provar a equivalência quadro a quadro, com o `P_Random` na
mesma ordem, em dez roteiros. Com threads ou corrotinas sem regra de
escalonamento, isso seria inviável. Para jogos com replay, rede
determinística ou testes por replay, essa previsibilidade vale muito.

**4. Composição.** `par`, `watching`, o `emit` com alcance (só a subárvore)
e o `emit` direcionado deixaram a hierarquia legível: o `Nivel` tem as
pools, o `Jogador` contém a `Arma`, cada tela desenha a si mesma.

### Onde o Atmos não rende

**1. A régua da fase** (seção 8). Quatro exigências devolvem a fase aos
dados:

- alguém de fora lê o estado (renderer, save, hash);
- o save grava o estado;
- o Lua escreve no meio do tic (o recado);
- a entidade é interrompida em qualquer fase.

Com todas elas, a task vira uma reorganização do mesmo estado. Foi o que
aconteceu com a arma (79 → 135 linhas, os mesmos 16 campos) e com o monstro
(87 → 221 linhas), que acabou com a forma de um interpretador com nomes. O
jogador e os monstros são justamente as entidades mais observadas do jogo.

**2. Não há como gravar uma continuação.** A posição no código não vai para
o save. Para um jogo com save no meio da ação, isso é estrutural: tudo o que
precisa sobreviver ao save tem de ser dado, e a task só pode guardar o que
não precisa (seção 1).

**3. Eventos são imediatos; o Doom adia para a fase.** O "recado no
registro" das portas, dos elevadores e da arma existe porque um `emit`
agiria no momento errado do tic (seção 5). Num jogo escrito do zero em
Atmos, isso seria desenhado de outro jeito. Numa migração, é atrito
constante.

**4. Maturidade.** A linguagem está em desenvolvimento (`dev-4`), e o
projeto tropeçou várias vezes:

- `until (c, v)` devolve `c` quando `v` é `nil` ou `false`;
- o `--` obrigatório na linha de comando;
- `a ++ b` no lugar de `a .. b`;
- o alcance padrão do `emit`;
- um `spawn` dentro de um `if` que morre com o bloco.

Nada disso é grave, mas cada um custou uma rodada de depuração. A
documentação é curta, e várias coisas foram confirmadas lendo o runtime e
escrevendo testes pequenos.

### Custo

Medido, não estimado (`tools/bench_tasks.atm`, `tools/custo_drivers.py` e o
teste de emit direcionado do registro do passo 5):

- uma task acordada por `emit` comum custa cerca de 2 µs, e um `emit`
  direcionado com o despertar, cerca de 3,5 µs;
- um zumbi custa cerca de 16 µs por tic, contando o corpo da task;
- **acumulado**, o atual custa +51% por quadro no roteiro `fluxo` em relação
  ao `passo1` em Lua puro (de 0,74 para 1,12 ms), e o monstro sozinho é a
  maior parte do passo 5.

Em termos absolutos, porém, 1,1 ms está muito abaixo dos 28,6 ms de um tic a
35 Hz. Para lógica de jogo, o custo é irrelevante enquanto o número de tasks
for de dezenas ou poucas centenas. Ele cresce de forma linear com as
entidades com task, então migrar centenas de monstros e projéteis começaria
a pesar. E o renderer não é lugar para tasks: ele não tem dimensão de tempo.

### Custo-benefício: onde usar em jogos

| Usaria | Evitaria (ou só para o fluxo de controle) |
|---|---|
| fluxo de telas, menus, transições | entidades lidas a cada quadro por muitos sistemas |
| roteiros: cenas, diálogos, eventos de fase, tutoriais | estado que precisa ir para o save no meio da ação |
| temporizadores, efeitos, luzes, sequências | IA orientada a dados, que já é uma máquina de estados em tabela |
| fases de chefe, ondas de inimigos, objetivos | sistemas de alta contagem (partículas, projéteis) |
| ciclo de vida: o que nasce e morre com a fase | o laço quente do motor (render, física, colisão) |

O desenho que parece certo é **híbrido**: os dados ficam em registros, que
todos podem ler e gravar, e as tasks cuidam do **fluxo de controle** e do
**ciclo de vida**. Foi para onde o projeto convergiu naturalmente: o
renderer em C, a geometria e as tabelas em Lua, e o "quando" e o "quanto
tempo" em Atmos.

### Um alerta sobre o resultado do TCC

Os números de expressividade estão enviesados contra o Atmos pela exigência
de **equivalência**. Ela obriga a manter o formato do save, os campos lidos
pelo renderer e o tic exato de cada reação. Um jogo pensado desde o início
em Atmos desenharia o save e a comunicação de outro jeito, e algumas
exigências da régua não existiriam.

O resultado justo é condicional: "numa migração equivalente, o ganho depende
de quanto o estado é observado, gravado, alterado e interrompido de fora". E
vale registrar na monografia o que só a migração equivalente permitiu medir:
o ciclo de vida, o determinismo e o custo.

---

## 11. Saves em pontos fixos e pausa com `toggle`

Reflexão do autor (2026-11-20), depois dos passos 1 a 7, com o resumo da
discussão.

### A reflexão

Na maioria dos jogos, não é comum salvar "a qualquer momento": os saves são
automáticos (ao atingir uma condição espacial ou de sequência) ou só em
"zonas seguras". Isso vem do game design ou da complexidade de um save
"instantâneo"? Se for o segundo caso, a desvantagem da concorrência
estruturada com o save (a continuação de uma task não pode ser gravada;
seções 1 e 8) deixaria de existir? E, já que o menu deste port não pausa o
jogo: se fosse preciso pausar, um `toggle` nas tasks bastaria? Seria mais
simples do que em C++ ou em linguagens sem concorrência estruturada?

### Saves em pontos fixos: os dois motivos

- **Design:** tensão e ritmo (perder progresso dá peso ao erro), evitar o
  "salvar e carregar até dar certo", e a herança dos consoles (memória
  limitada; regras de certificação que exigiam salvar em pontos
  conhecidos).
- **Técnica:** gravar um instantâneo arbitrário obriga a serializar tudo o
  que está no meio de alguma coisa (projéteis no ar, inimigos no meio de um
  ataque, roteiros de cena no meio da execução). Jogos com roteiros em
  corrotinas esbarram na mesma limitação do Atmos, e a saída comum é salvar
  só em **pontos de quietude**, onde se sabe em que estado cada roteiro
  está ("não é possível salvar agora" durante cenas e combates). Os jogos
  que salvam em qualquer lugar costumam reduzir o progresso a dados (o
  estágio da missão é um número), que é a régua da fase aplicada.

**A desvantagem diminui muito, mas não some:**

- num ponto de quietude, as tasks estão em posições conhecidas; o save grava
  pouco ("ponto de controle 3, estágio 2") e o load **recria** as tasks a
  partir disso, o que é natural no Atmos (`spawn` com parâmetros). A
  exigência "o save grava a entidade" quase desaparece para o que está em
  movimento;
- os fatos duráveis (inventário, inimigos mortos, portas abertas) continuam
  sendo dados, mas seriam dados em qualquer modelo;
- as outras exigências da régua (leitores de fora, recado, interrupção) não
  dependem do save;
- no Doom, salvar em qualquer lugar faz parte do jogo, e a equivalência
  obriga a mantê-lo. A monografia pode dizer que essa exigência é própria
  de jogos com save instantâneo.

**Ideia para trabalho futuro:** como o jogo é determinístico (provado pelos
replays), um save poderia ser "ponto de controle + as entradas desde
então", e o load reexecutaria as entradas em velocidade máxima. Isso elimina
a serialização de continuações, ao custo do tempo de carregamento.

### A pausa

**O Doom original pausa.** No `linuxdoom-1.10`, o `P_Ticker` retorna logo no
começo com o menu aberto no single player (`!netgame && menuactive &&
!demoplayback`), e a tecla Pause alterna `paused`. Jogador, thinkers,
specials e `leveltime` param; a barra de status, o automapa e o HUD
continuam (os seus tickers rodam fora do `P_Ticker`). **Este port não
pausa** (com o menu aberto, só zera o comando do jogador) e não tem tecla de
pausa: registrado em `docs/DIFERENCAS_DOOM.md`, para a fase de correções.

**Um `toggle` numa subárvore bastaria.** O tic do mundo iria para uma task
`Mundo` dentro do `Nivel` (as tasks e as partes Lua chamadas pelo laço do
`Nivel`), com a barra e o automapa fora dela; pausar seria
`toggle mundo(false)`. O resto vem de graça:

- as tasks contam tics, não relógio: nenhum contador precisa de correção na
  volta;
- os eventos perdidos durante a pausa não se acumulam;
- o que fica fora da subárvore continua andando, como no Doom.

**Mais simples que em C++? Depende de com o que se compara.**

- **Contra o próprio Doom:** não. Ele já pausa com uma linha
  (`if (paused) return;`), porque toda a lógica passa por um laço central
  de thinkers. Uma lógica centralizada e contada em tics deixa a pausa
  trivial em qualquer linguagem.
- **Contra motores com a lógica espalhada** (callbacks, temporizadores em
  tempo real, corrotinas sem hierarquia, um `Update` por objeto): aí o
  Atmos ganha. Esses motores precisam de escala de tempo (como o
  `Time.timeScale = 0` da Unity, com a interface em tempo "sem escala"),
  flags de "pausável" por objeto e cuidado para os temporizadores não
  dispararem na volta. Na concorrência estruturada a hierarquia já existe, e
  pausar uma parte dela é uma operação, sem contabilidade de tempo.

**Contraste com o elevador (passo 3c).** Lá o `toggle` não era equivalente,
porque o elevador parado do Doom continuava descontando o contador. Na
pausa, o Doom para tudo de verdade, então o `toggle` corresponde exatamente
ao original: uma correção pequena e boa para mostrar na monografia.

### Complemento: a task `Mundo` não substitui o fluxo

Pergunta do autor: a task `Mundo` seria uma substituição do fluxo atual?
**Não.** O fluxo de telas continua (`Fluxo → Titulo / Jogo → Nivel → Saida
→ Intermissao / Finale`). O `Mundo` ficaria **dentro do `Nivel`** e seria só
a parte do tic que o Doom chama de `P_Ticker`, a simulação do mundo. O
`Nivel` continua cuidando do ciclo de vida do nível (montar ou carregar;
perceber saída, morte e troca; desenhar).

```
Fluxo                         (igual)
 └─ Jogo                      (igual)
     └─ Nivel                 montar/carregar, fim (saída, morte, troca), desenho
         ├─ tic, em ordem:
         │    automapa (AM_Ticker)          ← fora do Mundo: continua na pausa
         │    Mundo  ←── toggle aqui
         │    │  comando, Jogador (e Arma), efeitos, mobjs (zumbis),
         │    │  specials (pools luzes, movers, botoes), texturas, leveltime
         │    │  → devolve "saida" | "morte" | nada
         │    barra de status (ST_Ticker)   ← fora do Mundo: continua na pausa
         └─ desenho (:game.frame)
```

É a mesma divisão do Doom: o `G_Ticker` chama o `P_Ticker` (o mundo, que
para na pausa) e depois `ST_Ticker`, `AM_Ticker` e `HU_Ticker` (que
continuam).

**As pools teriam de morar dentro do `Mundo`.** Hoje elas são declaradas no
`Nivel`, antes de montar o nível, porque o `build_level` e o load criam
tasks nelas. O `Mundo` teria de nascer antes de montar o nível e conter as
pools, para um único `toggle` alcançar tudo. Com as pools no `Nivel`, seriam
vários `toggle` (um por pool, mais o `Jogador`).

**Com o desenho atual, nem o `toggle` seria necessário.** Todas as tasks do
mundo só acordam com eventos que o próprio laço do `Nivel` emite
(`:game.jogador`, `:game.specials`, o `:mobj.tic` direcionado). Então "não
emitir" já é pausar: elas ficam paradas no `await`, e a pausa cabe num `if`
no laço do `Nivel`:

```
loop on :game.tic {
    G.tic_automapa()
    if !G.pausado() {
        ;; o tic do mundo, como hoje: jogador, mobjs, specials, leveltime
    }
    G.tic_status()
}
```

**Conclusão para a monografia.** O projeto acabou **centralizando o relógio
no `Nivel`**, como o Doom centraliza no `P_Ticker`, e por isso a pausa é
trivial (uma linha) nos dois modelos. O `toggle` vale a pena quando as tasks
acordam sozinhas, com eventos que ninguém controla centralmente: por
exemplo, se cada monstro esperasse `:game.tic` direto, ou se houvesse tasks
com relógio próprio. Aí um `toggle` numa subárvore pausa tudo sem precisar
saber quem escuta o quê, e é nesse cenário que ele supera os motores de
lógica espalhada. A versão com a task `Mundo` e o `toggle` expressa melhor a
intenção ("este pedaço do jogo para"); a versão com o `if` é mais curta. Na
fase de correções, dá para fazer a primeira e registrar a segunda como a
alternativa equivalente.

**Resultado (C2, tag `c2`; `docs/registro/14-correcoes-c2.md`).** Feito
assim: o `Nivel` desliga o `Mundo` com `toggle` quando a pausa ou o menu
param o mundo, e desfaz a pausa num `defer`. Duas coisas apareceram na
prática. Primeiro, o comando do jogador estava dentro do `Mundo`, mas é o
`G_BuildTiccmd`, que no Doom roda também com o mundo parado; ele teve de sair
(um commit só de refatoração antes da correção). A previsão "a pausa é uma
linha" vale para o mundo, não para o que fica em volta: a tecla, a figura, a
música e o primeiro tic do nível com o menu aberto deram o mesmo código nas
duas branches. Segundo, a diferença entre as branches ficou onde o C1 já
tinha mostrado: na `lua`, a barra teve de sair do ramo do tic com um
sinalizador para continuar andando, e a pausa é desfeita em dois lugares
(`start_level` e `end_game`); na `atmos`, o automapa e a barra já eram
irmãos do `Mundo`, e o `defer` do `Nivel` cobre todas as saídas.

---

## 12. O meio da régua: rosto, menu e automapa (passo 8)

O passo 8 migrou três peças de interface que a régua classificava no meio, e
os resultados ficaram onde ela previa:

| Peça | O que é lido ou escrito de fora | Campos escritos por tic | Resultado |
|---|---|---|---|
| Rosto da barra | só `face_index`, pelo desenho | 5 → 1 | médio |
| Menu | `menu.active`, lido e escrito por vários | 2 → 1 | neutro |
| Automapa | posição e escala, pelo desenho; aberto e fechado de fora | 1 → 1 | modesto |

Uma lição nova: **a régua mede o estado, mas a forma de sequência é outra
condição.** O rosto não tem leitores de fora além do desenho, e mesmo assim
não virou um programa linear: a sua regra é uma arbitragem ("a expressão
mais importante vence, e fica por um tempo"), reavaliada a cada tic. A
intermissão e o finale (passo 7) ganharam nas duas frentes porque, além de
não serem lidos de fora, **são sequências no tempo**. Para a monografia, o
ganho completo da concorrência estruturada exige as duas coisas: estado que
ninguém de fora precisa (a régua) e comportamento que é uma sequência no
tempo (pausa, conta, espera, mostra). Faltando a segunda, o ganho fica no
estado (campos que viram variáveis); faltando a primeira, a task só
reorganiza.

A task `Mundo` (8a) não mede expressividade: é a estrutura que a pausa com
`toggle` pede (seção 11), e agora existe no código, com o automapa e a barra
fora dela, como o `AM_Ticker` e o `ST_Ticker` do Doom ficam fora do
`P_Ticker` (`docs/registro/10-interface-e-mundo.md`).

