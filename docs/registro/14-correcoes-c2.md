# C2: o menu e a tecla Pause param o mundo

Segundo item da fase de correções (`docs/PLANO_ATMOS.md`, seção 6, "C").
Muda o comportamento: foi feito nas duas branches, `atmos` e `lua`, e a
referência de equivalência passou a ser a tag nova **`c2`** (a branch `lua`
com o C2). Contra a `c1`, as divergências são as esperadas (abaixo).

## Resumo

| | Antes (`c1`) | Depois (`c2`) |
|---|---|---|
| Menu aberto no nível | o mundo continuava (monstros, specials, `leveltime`); só o comando do jogador era zerado | o mundo para, como no `P_Ticker` do Doom (`!netgame && menuactive && !demoplayback && viewz != 1`) |
| Tecla Pause | não existia (o SDL a entregava como tecla sem nome) | alterna a pausa no tic seguinte (`G_BuildTiccmd` → `G_Ticker`), com os botões do comando zerados nesse tic (`BT_SPECIAL`, zerados pelo `P_PlayerThink`) |
| Na pausa e no menu | – | a barra de status e o automapa continuam (`ST_Ticker` e `AM_Ticker` ficam fora do `P_Ticker`); o comando continua sendo montado a cada tic (o mouse não se acumula) |
| Figura e música | – | `M_PAUSE` no alto da vista (no alto da tela com o automapa), por baixo do menu, como no `D_Display`; a música pausa (`S_PauseSound`), os efeitos não |
| Fim da pausa | – | começar um nível (`G_InitNew`) ou voltar ao título (`D_AdvanceDemo`) |

## O desenho nas duas branches

O comando do jogador (`G.tic_comando`) estava dentro da task `Mundo`, mas no
Doom o `G_BuildTiccmd` fica fora do `P_Ticker`: o comando é montado a cada
tic, mesmo com o mundo parado (sem isso, o mouse se acumularia durante a
pausa, e a tecla Pause não teria como despausar). Por isso o C2 começou com
um commit **só de refatoração** (`c614b6e`): o `G.tic_comando()` saiu do
`Mundo` para o `Nivel`, logo antes do `emit :mundo.tic`. A ordem no tic não
muda; idêntico à `c1` nos 14 roteiros.

A decisão "o mundo para?" é a mesma função nas duas branches
(`mundo_parado`):

```lua
-- C2: o mundo para neste tic? Como o P_Ticker do Doom: com a pausa e, com o
-- menu aberto, depois do primeiro tic do nivel (no Doom, viewz ~= 1; aqui,
-- leveltime > 0, que tambem vale depois de um load).
function G.mundo_parado()
  return game.paused or (menu.active and (game.leveltime or 0) > 0)
end
```

O que muda é como cada branch **usa** essa decisão e **onde termina** a
pausa.

```
;; atmos (main.atm, task Nivel)
task Nivel (save) {
    val r = [fim=nil]
    pin mundo = spawn Mundo(r)
    var parado = false                    ;; C2: o mundo esta desligado
    defer {
        G.pausar(false)                   ;; C2: a pausa e do Nivel: nao
    }                                     ;; sobrevive a ele (G_InitNew)
    ...
        emit @(automapa) (:automapa.tic)
        G.tic_comando()                   ;; comando e tecla Pause
        val parar = G.mundo_parado()      ;; C2: pausa ou menu
        if parar != parado {
            toggle mundo(!parar)          ;; desligado, nao acorda
            set parado = parar            ;; nem com o :mundo.tic
        }
        emit @(mundo) (:mundo.tic)
        if !r.fim {
            emit @(rosto) (:barra.tic)    ;; a barra anda tambem na pausa
        ...
```

```lua
-- lua (main.lua, laco do tic)
local morte = false
if not mundo_parado(menu) then  -- C2: o P_Ticker
  player_mod.think(...)
  player_mod.tick_fx(game.world)
  if game.player and game.player.playerstate == player_mod.PST_REBORN then
    game.start_level(game)
    morte = true
  else
    thinker.tick(game.world, game)
    ...
    game.leveltime = (game.leveltime or 0) + 1
  end
end
if not morte and game.status then  -- a barra anda tambem na pausa (ST_Ticker)
  status_mod.ticker(game.status, game.player)
end
-- e pausar(false) em game.start_level e em game.end_game
```

**Atmos.** O `Mundo` já era a subárvore do `P_Ticker` (passo 8a, A5): as
pools dos specials e dos monstros, o `Jogador` e a `Arma`. Desligar o mundo
é um `toggle` nela; o automapa e o rosto, irmãos do `Mundo` no `Nivel`,
continuam sem mudança nenhuma. A pausa termina num `defer` do `Nivel`, que
roda em qualquer saída: idclev, load, New Game, End Game. É o mesmo
argumento do `carry` no C1: a correção diz **de quem** é o estado.

**Lua.** O tic do mundo ganhou um `if` em volta (17 linhas reindentadas), e a
barra de status, que ficava no fim do ramo "seguiu", teve de sair do `if` com
um sinalizador (`morte`) para continuar andando na pausa. A pausa termina
onde o nível começa (`start_level`, que cobre New Game, load, idclev e
renascer) e em `end_game`: dois lugares a lembrar.

**A alternativa com o `if`** (notas, seção 11) também vale na branch
`atmos`: como todas as tasks do mundo só acordam com eventos que o `Nivel`
emite, `if !G.mundo_parado() { emit @(mundo) (:mundo.tic) }` dá o mesmo jogo,
com uma linha a menos e sem o estado `parado`. O `toggle` foi escolhido
porque diz a intenção ("esta subárvore para") e não depende de saber quem
escuta o quê: uma task do mundo que esperasse `:game.tic` diretamente
também pararia. Pela notas, seção 11, é aí que o `toggle` ganha dos
motores com a lógica espalhada.

**Contraste com o elevador (passo 3c).** Lá o `toggle` não era equivalente:
o elevador parado deste port continuava descontando o contador, e só o save
mostrava. Na pausa, o Doom para tudo de verdade, e o `toggle` corresponde
exatamente ao original.

### Detalhes do Doom reproduzidos

- **O primeiro tic do nível roda com o menu aberto.** O Doom põe `viewz = 1`
  no `P_SetupLevel`, e o `P_Ticker` só pausa pelo menu com `viewz != 1`.
  Aqui, `leveltime > 0` (o `leveltime` volta a 0 em todo nível novo; num
  load, vem do save, como o `viewz`). O caso aparece quando o menu é aberto
  no fim da intermissão e o nível seguinte começa com ele aberto.
- **O tic da tecla Pause zera os botões.** No Doom, o comando desse tic
  leva `BT_SPECIAL | BTS_PAUSE` no lugar dos botões; ao despausar, o
  `P_PlayerThink` os zera. Um tiro segurado durante a pausa sai um tic
  depois de despausar.
- **O menu não usa a tecla Pause.** O `M_Responder` devolve falso para ela,
  e ela segue para o `G_Responder` mesmo com o menu aberto: dá para
  despausar com o menu aberto (o mundo continua parado pelo menu). Em
  `menu.lua`, a tecla é recusada logo depois das mensagens.

### Fica diferente do Doom

- A tecla Pause só vale no nível. No Doom ela também alterna `paused` na
  intermissão e no finale: a figura aparece, mas a tela continua (o
  `WI_Ticker` e o `F_Ticker` não olham `paused`), e o `BTS_PAUSE`, que vale
  1 como o `BT_ATTACK`, acelera a intermissão.
- Com uma mensagem de confirmação do menu na tela, a tecla Pause é engolida
  (no Doom, só as mensagens sem pergunta a engolem).

## O hash de estado

`G.state_string` (e o `state_string` da branch `lua`) acrescenta `pausado`
só quando a pausa está ligada, para que os logs antigos não mudem nos
quadros sem pausa. O resto da pausa aparece por si: `leveltime`, mobjs e
setores parados, e a figura no framebuffer.

## Roteiro

O roteiro `correcoes` ganhou o C2, depois do C1, no E1M1 do jogo novo:

1. Pause; 30 quadros parado; o automapa aberto e fechado na pausa;
   "andar" segurado; "atirar" segurado e Pause de novo (o tiro sai um tic
   depois).
2. O menu aberto por 40 quadros e fechado.
3. Pause, o menu aberto, Pause de novo com o menu aberto (despausa, o mundo
   continua parado) e o menu fechado.
4. Pause e `idclev12`: o E1M2 começa sem pausa.
5. No fim do E1M2, a contagem acelerada, o "entering", o menu aberto e o
   E1M3 começando com ele: o primeiro tic roda (`leveltime` 1) e o mundo
   para até o menu fechar.

Conferido com prints numa cópia de `G.state_string` (gamestate,
`leveltime`, pausa, menu): o `leveltime` fica em 139 durante a primeira
pausa e volta a andar no quadro 511; fica em 181 com o menu aberto; no E1M3,
fica em 0 durante o wipe, vai a 1 e para até o menu fechar no quadro 1.227.
A cobertura em `tests/test_drivers.sh` exige o idclev e o E1M3.

## Validação

**Contra a referência nova** (`make test-drivers`, tag `c2`): idêntico nos
14 roteiros, com os saves iguais byte a byte. `make test-branches`: idêntico
à branch `lua` nos 14. `make test`: 12 passam, as 8 falhas conhecidas. A
janela abre e fecha limpo nas duas branches. A figura conferida em quadros
gravados (`DOOM_REPLAY_DUMP`): no alto da vista; no alto da tela com o
automapa; por baixo do logo com o menu aberto.

**Contra a referência anterior** (`REF_TAG=c1`): diverge onde o roteiro abre
o menu com o nível rodando (save e load pelo menu); os roteiros que não
abrem o menu num nível continuam idênticos.

| Roteiro | Quadros | Diferentes | Faixas |
|---|---|---|---|
| `ordem` | 815 | 0 | – |
| `telas` | 4.732 | 0 | – |
| `luzes` | 2.619 | 0 | – |
| `botoes` | 861 | 307 | 240–546 (com o roteiro novo, abaixo) |
| `portas` | 2.958 | 917 | 321–1.237 |
| `elevadores` | 2.098 | 1.553 | 76–1.226; 1.697–2.098 |
| `pisos` | 2.618 | 1.338 | 112–1.449 |
| `arma` | 2.994 | 526 | 2.284–2.809 |
| `monstro` | 2.755 | 1.888 | 868–2.755 |
| `familia` | 3.226 | 1.268 | 1.959–3.226 |
| `fluxo` | 4.478 | 817 | 1.949–2.277; 2.423–2.635; 4.204–4.478 |
| pseudoaleatório (4000, semente 1) | 4.000 | 677 | 823–1.098; 3.600–4.000 |
| `exits` (6000, semente 2) | 6.000 | 5.379 | 206–1.096; 1.513–6.000 |
| `correcoes` | 1.310 | 456 | 414–743; 1.185–1.310 (o C2) |

Várias faixas fecham num load: o estado volta a ser o do save, gravado com o
mundo no mesmo ponto nas duas versões, e as duas voltam a ser iguais.

**Os cenários dos roteiros antigos continuam valendo.** Eles foram montados
com o mundo andando durante a navegação no menu (por exemplo, o save com
uma porta abrindo). Com o C2, o save grava o mundo do instante em que o
menu abriu, o que mantém a fase desejada (a porta continua abrindo). A
prova é a cobertura de cada roteiro, que continua passando, e as mutações
(abaixo), que continuam detectadas. A exceção foi o save do roteiro
`botoes`, ajustado (seção "Mutações").

## Mutações

| Mutação | Erro simulado | 1º quadro | Quadros dif. |
|---|---|---|---|
| `menu-nao-para` | o menu aberto não para o mundo (o comportamento da `c1`) | 552 | 318 |
| `pausa-nao-para` | a tecla Pause alterna a pausa, mas o mundo continua | 414 | 330 |
| `menu-para-no-primeiro-tic` | o menu para o mundo já no primeiro tic do nível | 1.185 | 126 |
| `pausa-sem-zerar-botoes` | o tic da tecla Pause não zera os botões | 510 | 38 |
| `menu-usa-pause` | o menu aberto engole a tecla Pause | 645 | 99 |
| `pausa-sobrevive-ao-nivel` | o `Nivel` não desfaz a pausa (o idclev começa o E1M2 pausado) | 744 | 567 |
| `barra-parada-na-pausa` | a barra para junto com o mundo | 414 | 263 |

Todas no roteiro `correcoes`.

**Duas mutações antigas precisaram de ajuste.**

- `automapa-depois-do-mundo` (passo 8d) deixou de se aplicar: o trecho
  mutado eram as duas linhas `emit` seguidas, e o `G.tic_comando()` e o
  `toggle` agora ficam entre elas. O trecho foi refeito com o texto atual;
  detectada (quadro 3.182, 10 quadros).
- `load-reinicia-timer` (passo 3e) **sobreviveu** no roteiro `botoes`. O
  "use" no botão acontecia com o menu de save já aberto, e o timer descia
  durante a espera até gravar. Com o C2, o mundo fica parado com o menu
  aberto, o save gravava o timer cheio (35), e recriar o botão com 35 no load
  (a mutação) dava o mesmo jogo. O roteiro passou a apertar o botão 10
  quadros antes de abrir o menu; detectada (quadro 445, 11 quadros). As
  outras cinco mutações do roteiro continuam detectadas (uma equivalente,
  como antes). É o primeiro caso em que uma correção tirou a sensibilidade
  de um roteiro: o cenário dependia do comportamento corrigido.

`make test-mutacoes`: **97/97 não equivalentes detectadas**, 7
equivalentes, nenhuma pendente.

## Métricas

Linhas alteradas (`git diff --numstat`, com comentários):

| Arquivo | `atmos` | `lua` |
|---|---|---|
| `main.atm` / `main.lua` (o fluxo e o tic) | +16 −4 | +78 −17 |
| `game.lua` (as partes Lua do jogo, só na `atmos`) | +60 | – |
| `menu.lua`, `keys.lua`, `sound.lua`, `video.lua`, `src/video_c.c` | +37 −1 | +37 −1 |

Na `atmos`, a pausa, a figura, a tecla e o hash ficam no `game.lua`, e o
`main.atm` só decide (o `toggle` e o `defer`, 9 linhas de código); na
`lua`, o mesmo código fica no `main.lua`, junto com o `if` e as 17 linhas
reindentadas. O código de pausa em si (`pausar`, `mundo_parado`, a figura,
a tecla, o hash) é o mesmo texto nas duas.

## Como reproduzir

```sh
make test-drivers                 # contra a tag c2
make test-branches                # contra a branch lua
make test-mutacoes
sh tests/test_drivers.sh 0 1 correcoes -warp 1 1
REF_TAG=c1 sh tests/test_drivers.sh 0 1 correcoes -warp 1 1   # diverge (esperado)
```

## Arquivos alterados

| Arquivo | Branch | Mudança |
|---|---|---|
| `main.atm` | `atmos` | `G.tic_comando()` no `Nivel` (commit de preparo); `toggle mundo` e `defer` da pausa no `Nivel` |
| `game.lua` | `atmos` | `pausar`, `G.mundo_parado`, `G.pausar`; a tecla Pause em `handle_input` e `tic_comando`; a figura; o hash |
| `main.lua` | `lua` | o mesmo código de pausa; o `if` em volta do tic do mundo; a barra fora dele; `pausar(false)` em `start_level` e `end_game` |
| `keys.lua` | as duas | a tecla Pause (`SDLK_PAUSE`) |
| `menu.lua` | as duas | o menu recusa a tecla Pause |
| `sound.lua`, `video.lua`, `src/video_c.c` | as duas | `pause_music` (`Mix_PauseMusic`/`Mix_ResumeMusic`); o laço da música não reinicia a música pausada |
| `tools/make_replay.lua` | `atmos` | o C2 no roteiro `correcoes`; no `botoes`, o "use" antes de abrir o menu de save |
| `tests/test_drivers.sh` | `atmos` | referência padrão `c2`; cobertura do C2 |
| `tools/mutacoes.py` | `atmos` | mutações do C2; o trecho da `automapa-depois-do-mundo` |
