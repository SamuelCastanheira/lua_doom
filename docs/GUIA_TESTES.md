# Guia: rodar o jogo, testar e medir

Guia prático para o dia a dia do TCC. Cada seção diz o comando, o que ele
faz, como ler a saída e o que fazer quando algo dá errado.

> Resumo de bolso
>
> ```sh
> make                      # compila (sempre depois de um git pull ou checkout)
> lua5.4 main.lua -fps -scale 4
> make test-drivers         # o jogo continua igual? (o teste mais importante)
> make test-mutacoes        # o teste pega erros?
> make metricas             # numeros para o artigo
> ```

---

## 1. Compilar e jogar

```sh
make                         # compila os modulos em C (.so na raiz)
lua5.4 main.lua -fps -scale 4
```

`main.lua` só lança o `main.atm`. O comando abaixo é equivalente (o `--`
é obrigatório):

```sh
atmos main.atm -- -fps -scale 4
```

Opções úteis:

| Opção | Efeito |
|---|---|
| `-warp 1 3` | começa direto no E1M3 |
| `-skill 0..4` | dificuldade (padrão 2) |
| `-scale N` | tamanho da janela (320×200 × N) |
| `-fps` | mostra o contador de FPS |
| `-nosound`, `-nomusic` | sem som / sem música |
| `-nomonsters`, `-fast`, `-respawn` | como no Doom |

No jogo: **F11** troca a gama, **F12** liga e desliga o FPS, **Tab** abre o
automapa, **−/=** mudam o tamanho da tela.

Se algo der errado ao compilar, `make help` mostra o que o Makefile achou
(Lua, SDL, plataforma). `make clean && make` recompila tudo.

---

## 2. O teste mais importante: o jogo continua igual?

```sh
make test-drivers
```

### O que ele faz

1. Confere seis propriedades do Atmos de que o código depende
   (`tests/atmos_semantica.atm`).
2. Roda o jogo **três vezes, sem janela**, com as mesmas teclas, lidas de um
   roteiro:
   - a **referência**: o laço imperativo da tag `passo1`, num worktree em
     `build/ref-passo1`;
   - o **código atual** via `atmos main.atm`;
   - o **código atual** via `lua5.4 main.lua`.
3. Em cada quadro, guarda dois números:
   - um "resumo" (hash) da imagem;
   - um hash do estado do jogo: posições e vida de todos os monstros,
     alturas e luz dos setores, jogador, tela atual e a posição na tabela
     aleatória do Doom.
4. Compara os três, quadro a quadro.

### Saída quando está tudo certo

```
atmos: 6 propriedades ok
identico a passo1: 4478 quadros, 1680 estados distintos (semente 1 fluxo )
  telas (referencia, em ordem):
    vista E1M1 > intermissao E1M2 > vista E1M2 > ... > vista E1M4
  pedidos emitidos (atmos):
         2 jogo.carregar
         1 jogo.fim
         3 jogo.novo
         1 jogo.sair
         1 nivel.trocar
  cobertura do fluxo: completa
identico a passo1: 4000 quadros, 2707 estados distintos (semente 1  )
identico a passo1: 6000 quadros, 1437 estados distintos (semente 2 exits )
```

- **"identico a passo1"**: em todos os quadros, a imagem e o estado são os
  mesmos da referência.
- **"estados distintos"**: quantos estados diferentes o jogo passou. Um
  número grande mostra que o teste não ficou parado numa tela.
- **"cobertura do fluxo: completa"**: o roteiro passou de fato por todas as
  transições (novo jogo, intermissão, saída secreta, morte, save e load, End
  Game, `idclev`, finale, Quit).

### Saída quando algo mudou

```
DIVERGENCIA atm x passo1 (semente 1 fluxo ):
297,600c297,600
< 297 1286370161 4035111747
---
> 297 3013237676 4035111747
```

Cada linha do log é `quadro hash_imagem hash_estado`. Para ler:

- O **primeiro número** (297) é o quadro em que a diferença começou. Olhe o
  que o roteiro faz por volta desse quadro:

  ```sh
  awk '$1>=280 && $1<=300' build/drivers/replay_1fluxo.txt
  ```

- **Só o hash da imagem difere:** o jogo está igual, mas algo é desenhado
  diferente (menu, mensagem, slot de save).
- **O hash do estado difere:** a lógica mudou (ordem, tempo, número
  aleatório).
- Para **ver a imagem** de um quadro, rode à mão com
  `DOOM_REPLAY_DUMP` (seção 4).

Se a referência der erro, aparece `ERRO na referencia passo1:` com as
últimas linhas. Olhe `build/drivers/ref.out`.

### Rodar um roteiro só

```sh
sh tests/test_drivers.sh 0 1 fluxo        # todas as transicoes (o mais completo)
sh tests/test_drivers.sh 4000 1           # 4000 quadros pseudoaleatorios, semente 1
sh tests/test_drivers.sh 6000 2 exits     # tambem termina niveis (intermissao, finale)
sh tests/test_drivers.sh 4000 7           # outra semente = outra sequencia de teclas
```

Argumentos: `quadros semente [exits|fluxo] [opções do jogo]`. No modo
`fluxo`, o número de quadros é ignorado.

### Trocar a referência

```sh
REF_TAG=passo2 sh tests/test_drivers.sh 0 1 fluxo
```

Use isso quando o passo novo mudar o comportamento de propósito (por
exemplo, ao corrigir o bug do `carry`). Antes, crie a tag do estado que vai
servir de referência. A comparação com `passo1` vai divergir, e isso deve
ficar documentado.

### Seus saves estão seguros

Cada execução do teste roda numa pasta própria (`build/drivers/run_ref`,
`run_atm`, `run_lan`), sem saves. O `doomsav0.dsg` da raiz não é tocado.
**Não rode roteiros direto na raiz** com `DOOM_REPLAY`: o jogo salva na
pasta de onde roda.

---

## 3. O teste pega erros? (sensibilidade)

```sh
make test-mutacoes
```

Injeta, um de cada vez, um erro plausível no `main.atm` (por exemplo,
"morrer volta ao título" ou "Load não descarta o jogo atual"), roda o
roteiro `fluxo` e confere se a comparação acusa o erro.

```
mutacao                  resultado    1o quadro quadros dif.  descricao
sem-cancel-catchup       detectada          297          600  Nivel nao interrompe ...
menu-depois-da-tela      equivalente          -            0  Relogio roda a tela antes do menu
                                                                -> menu.ticker so muda ...
...
10/10 mutacoes nao equivalentes detectadas (2 equivalentes, justificadas acima)
```

- **detectada**: o teste pegou o erro, como deveria.
- **equivalente**: a mudança não altera o comportamento, e a justificativa
  aparece logo abaixo. Isso também é um resultado: mostra que aquela ordem
  não importa.
- **SOBREVIVEU**: problema. Ou o roteiro não passa por aquele comportamento
  (melhore o roteiro), ou a mudança é mesmo equivalente (justifique e
  acrescente em `EQUIVALENTES` em `tools/mutacoes.py`).

Para acrescentar uma mutação, edite a lista `MUTACOES` em
`tools/mutacoes.py`: nome, descrição, trecho original do `main.atm` e trecho
mutado.

---

## 4. Ver o que aconteceu num quadro

Para depurar uma divergência, gere as imagens dos dois lados. Sempre numa
pasta isolada:

```sh
S=$PWD/build/drivers/replay_1fluxo.txt
cd build/drivers/run_atm && rm -f *.dsg
DOOM_REPLAY=$S DOOM_REPLAY_OUT=/tmp/atm DOOM_REPLAY_DUMP=297,300 \
  atmos main.atm -- -nosound -nomusic
cd ../run_ref && rm -f *.dsg
DOOM_REPLAY=$S DOOM_REPLAY_OUT=/tmp/ref DOOM_REPLAY_DUMP=297,300 \
  lua5.4 main.lua -nosound -nomusic
cd ../../..
```

Isso grava `/tmp/atm.297.raw`, `/tmp/ref.297.raw` etc. (64.000 bytes cada,
índices de paleta). Para virar PNG:

```sh
python3 - <<'EOF'
from PIL import Image
pal = open("build/baseline/e1m1-b11d0/palette.raw", "rb").read()  # ou build/compare/*/ref/palette.raw
for n in ["atm.297", "ref.297"]:
    im = Image.frombytes("P", (320, 200), open(f"/tmp/{n}.raw", "rb").read())
    im.putpalette(pal)
    im.resize((640, 400), Image.NEAREST).save(f"/tmp/{n}.png")
EOF
```

Se `build/baseline` não existir, rode `make baseline` uma vez para gerar a
paleta.

### Escrever um roteiro à mão

Um roteiro é um arquivo de texto, com uma linha por evento. O quadro conta a
partir de 1:

```
40 escape down       # abre o menu
41 escape up
43 return down       # New Game
44 return up
...
200 exit             # (teste) termina o nivel como o switch de saida
300 exit secret      # (teste) saida secreta
500 die              # (teste) o jogador morre
900 quit             # fecha a janela
```

Para gerar um roteiro: `lua5.4 tools/make_replay.lua <arquivo> <quadros>
<semente> [exits|fluxo]`. O roteiro `fluxo` fica em
`tools/make_replay.lua`, no bloco `if fluxo then`.

Cuidado com o menu: ele lembra a última posição de cada submenu, e o de load
tem posição própria, separada da do save. Ao abrir o menu durante a
intermissão, o Save Game é recusado. Se mudar o roteiro, rode
`sh tests/test_drivers.sh 0 1 fluxo` e confira "cobertura do fluxo:
completa".

---

## 5. Métricas e custo para o artigo

```sh
make metricas
```

### 5.1 Métricas de código (`tools/metricas_passo2.py`)

Compara a tag `passo1` com o código atual:

```
| Metrica | passo1 | atual |
|---|---|---|
| Escritas de `game.gamestate` (fora do valor inicial) | 8 | 1 (+1 legado) |
| Pontos que iniciam um nivel (`start_level(...)`) | 7 | 1 (+2 legado) |
| Funcoes Lua que decidem a proxima tela | 4 | 0 |
...
```

A saída já é uma tabela Markdown, pronta para colar. "Legado" são os ramos
`-- caminho antigo (sem main.atm)`, usados só pelos testes unitários. As
linhas de baixo listam arquivo e linha de cada ocorrência, úteis para citar.

Para comparar duas tags: `python3 tools/metricas_passo2.py passo1 passo2`.

### 5.2 Custo por quadro (`tools/custo_drivers.py`)

```sh
python3 tools/custo_drivers.py 5        # 5 repeticoes por driver
```

```
driver        inicializacao     total  quadros  ms/quadro
passo1-lua           0.04 s    3.78 s     4478      0.836
passo1-atm           0.06 s    4.15 s     4478      0.915  (+9.5%)
atual-atm            0.06 s    4.44 s     4478      0.976  (+16.9%)
```

- Mede o **mínimo** de cada série (menos ruído do sistema), em pastas
  limpas, e desconta a inicialização.
- `ms/quadro` inclui tudo: lógica, renderer em C e carregamento de níveis.
- Para o artigo, compare com o orçamento de um tic: **28,6 ms** (35 Hz).
  Por exemplo, +0,14 ms ≈ 0,5% de um tic.
- Para resultados estáveis, feche outros programas e use 10 repetições.

### 5.3 Custo das tasks isoladas

```sh
for n in 100 500 1000; do N=$n atmos tools/bench_tasks.atm; done
```

```
N=100 tasks: 0.215 ms/tic (35000 despertares, 2.15 us cada)
N=500 tasks: 1.134 ms/tic (175000 despertares, 2.27 us cada)
N=1000 tasks: 2.643 ms/tic (350000 despertares, 2.64 us cada)
```

Serve para estimar o custo dos próximos passos. Um mapa com 300 portas e
luzes como tasks custaria cerca de 0,7 ms por tic.

### 5.4 Para um passo novo

`tools/metricas_passo2.py` foi escrito para o fluxo de telas. Para os
specials (passo 3), copie o script para `tools/metricas_passo3.py` e troque
o que é contado. Para os specials: campos de estado dos thinkers
(`direction`, `count`, `status`, `dead`), ramos `if th.kind == ...`, pontos
de limpeza (`specialdata = nil`) e linhas de código, antes e depois.

---

## 6. Renderer (só se mexer em C)

```sh
make compare MAP=1 SPRITES=full          # pixel a pixel contra o renderer Lua antigo
make baseline                            # congela os quadros atuais
make check-baseline                      # o que mudou, por tipo (parede, flat, ceu, sprite...)
lua5.4 tests/test_v_draw.lua             # desenho 2D contra a versao Lua original
make debug && lua5.4 main.lua -warp 1 1  # AddressSanitizer: acusa erro de memoria
make                                     # volta ao modo normal
```

`make compare` deve dar `total: 0 px diferentes`. Ele só vale para mudanças
que não alteram a imagem; para mudanças visuais de propósito, use
`check-baseline`.

---

## 7. Testes unitários

```sh
make test
```

Hoje passam 12 e falham 8. As 8 falhas são antigas, e não foram causadas
pela migração: a maioria espera o `doom1.wad` shareware (outra contagem de
texturas e vértices) ou o antigo `r_data.lua`. O que importa é **o
resultado não mudar** depois da sua alteração. Para comparar:

```sh
make test 2>&1 | grep -E "ok$|FALHOU" > /tmp/depois.txt
git stash && make test 2>&1 | grep -E "ok$|FALHOU" > /tmp/antes.txt; git stash pop
diff /tmp/antes.txt /tmp/depois.txt && echo "nada mudou"
```

---

## 8. Checklist antes de um commit de passo

- [ ] `make` sem avisos
- [ ] `make test-drivers`: tudo "identico" e "cobertura do fluxo: completa"
- [ ] `make test-mutacoes`: nenhuma "SOBREVIVEU"
- [ ] `make test`: mesmo resultado de antes
- [ ] jogo com janela abre, joga e fecha ("janela fechada")
- [ ] `make metricas` e números copiados para `docs/registro/NN-....md`
- [ ] `git status`: só os arquivos esperados; `doomsav0.dsg` sem mudança
- [ ] commit e tag `passoN` (`git tag -a passoN -m "..."`)

---

## 9. Problemas comuns

| Problema | Solução |
|---|---|
| `Error: unknown option '-f'` | faltou o `--`: `atmos main.atm -- -fps` |
| `module 'render_c' not found` | rode `make` |
| teste diverge só depois de um save | algum `.dsg` sobrando na pasta da execução; o script já isola, mas confira se você rodou algo à mão na raiz |
| "COBERTURA INCOMPLETA" | o roteiro não fez o que pretendia (geralmente o menu); veja a seção 4 |
| o teste dá "identico", mas você esperava diferença | sua mudança não é exercitada pelo roteiro; crie uma mutação parecida para confirmar |
| `build/ref-passo1` estragado | `git worktree remove --force build/ref-passo1`; o script recria |
| tempos de custo variando muito | feche outros programas; use `python3 tools/custo_drivers.py 10` |

Documentos relacionados:
- `docs/PLANO_ATMOS.md`: plano dos passos;
- `docs/registro/`: o que foi feito em cada passo, com os números;
- `CLAUDE.md`: contexto técnico completo, escrito para outro agente de IA
  continuar o trabalho.
