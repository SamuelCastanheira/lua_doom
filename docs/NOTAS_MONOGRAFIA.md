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
