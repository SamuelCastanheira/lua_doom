# Diferenças em relação ao Doom original

O que o lua_doom faz diferente do Doom original (`linuxdoom-1.10`, em
`github.com/id-Software/DOOM`) ou não faz. Levantamento conferido no código
(busca e leitura das funções) em 2026-11-18, durante o passo 3. **Não é
exaustivo**: são as ausências verificadas até agora. Cheats, automapa, menu,
intermissão e barra de status foram conferidos e estão completos.

**Regra do projeto:** nada disto é corrigido junto com a migração para
Atmos. Primeiro a equivalência; a correção vem depois, num commit separado,
com uma nova referência e a divergência esperada documentada (como o bug do
`carry`, `CLAUDE.md`, seção 8). Ao corrigir um item, mova-o para a seção
"Corrigido" no fim deste arquivo, com o commit e a tag de referência nova.

**Quando corrigir (decisão do usuário, 2026-11-18):** todas as diferenças e
revisões deste arquivo ficam guardadas até **o fim de todos os passos** da
migração (`docs/PLANO_ATMOS.md`). Só então são corrigidas, **nas duas
versões**: na branch `atmos` (Atmos) e na branch `lua` (Lua imperativo), para
que a comparação do TCC continue sendo entre duas versões do mesmo jogo.
Até lá, cada passo só acrescenta itens aqui. Na hora de corrigir:

- um commit por correção em cada branch, com o mesmo comportamento nas duas;
- uma tag de referência nova depois de cada correção (ou grupo), e a
  divergência esperada documentada;
- **fora do escopo das correções** (decisão do autor, 2026-11-20): o save
  no formato do Doom (recriar os mobjs a partir do save, o que corrigiria o
  load por índice da seção 5; gravar tetos, luzes e pisos inteiros), o som
  posicional (estéreo, distância, canais por mobj) e as demos. Ficam
  registrados como diferenças conhecidas;
- a igualdade entre as duas depois de cada correção é conferida por
  `make test-branches` (a branch `lua` ganhou o modo replay e o hash de
  estado no commit `09d8078`; `docs/registro/08-branch-lua-replay.md`).

---

## 1. Specials de setor

Os itens desta seção foram corrigidos no C4 (seção "Corrigido"). Fica o
achado durante o C4:

| Falta ou difere | Onde | No Doom original | Aqui |
|---|---|---|---|
| Velocidade do elevador "desce, espera, sobe" | `do_plat_dwus` | `EV_DoPlat` (`downWaitUpStay`): `PLATSPEED * 4` (4 unidades por tic) | `PLATSPEED` (1 por tic). Achado no C4d; corrigir muda o cenário do roteiro `ordem` (B2) |

Caminhos sem cobertura possível no `doom.wad` (migrados, mas nenhum mapa os
usa): linha 17 (strobe criado por linha), setores 10 e 14 (portas que
fecham em 30 s ou abrem em 5 min, nascidas do setor), linhas 41 e 43 (teto
desce até o piso) e 141 (esmagador silencioso).

## 2. Save game

Os itens desta seção foram corrigidos no C5 (seção "Corrigido"): o save
tem o conteúdo do save do Doom, sem as perdas do original (o fogo, os
botões e os alvos dos monstros continuam gravados, por decisão do autor).

| Falta ou difere | Onde | Efeito |
|---|---|---|

## 3. Som

| Falta | Onde | No Doom original |
|---|---|---|
| Som posicional | `sound.lua`, `play(name)` sem origem | separação estéreo e atenuação por distância (`S_StartSound` com origem, `S_AdjustSoundParams`) |
| Um canal por mobj | `sound.lua` | um mobj que toca outro som corta o anterior |

## 4. Em volta do jogo

| Falta ou difere | Onde | Observação |
|---|---|---|
| Demos | tela de título (`main.atm`, task `Titulo`) | o Doom alterna TITLEPIC → créditos → demos gravadas (`DEMO1`..`DEMO3`) e grava/reproduz demos (`-record`, `-playdemo`). Para o TCC: o demo é o "replay" do próprio Doom |
| Multiplayer | – | cooperativo e deathmatch ausentes |
| Estados do mobj do jogador | `player.lua` (o mobj do jogador não tem `istate`) | o `p_pspr.c` põe o mobj do jogador em `S_PLAY_ATK1`/`S_PLAY_ATK2` ao atirar e volta a `S_PLAY` no `A_WeaponReady`; o `P_MovePlayer` o põe em `S_PLAY_RUN1` ao andar; esmagado morto, vira `S_GIBS`. Aqui o mobj do jogador não tem estados; no single player ele não aparece. Visto no C3 |
| Transição de tela (wipe) | `wipe.lua` | usa `math.random`, não a tabela fixa (`M_Random`); só é determinística porque o replay fixa a semente |

## 5. Revisões do próprio port (não são do Doom)

Bugs e pendências encontrados durante a migração, guardados para a mesma
fase de correção.

| Revisão | Onde | O que fazer |
|---|---|---|

(Nenhuma aberta. O rosto da barra entrou no hash no passo 8: seção "Corrigido".)

---

## Relação com os próximos passos

- **3c (elevadores, feito):** congelar a task com `toggle` **não** é
  equivalente: o elevador parado deste port continua descontando o `count`
  (só o save mostra; mutação `parar-com-toggle`). Por isso o parar ficou como
  recado no registro. A reativação (`P_ActivateInStasis`) seria uma correção
  posterior, com nova referência; aí o `toggle t(true)` passaria a servir.
  **Feito no C4d:** com o elevador parado do Doom (que não pensa), o parar
  virou `toggle` da task `Elevador` e o recado sumiu; no C4b, o mesmo para os
  tetos.
- **3d (pisos, tetos, esmagadores, feito):** como ninguém escreve no
  registro do teto (as linhas 57 e 74 param elevadores) e ele não é gravado,
  a fase do `Teto` ficou só no código. A mutação `specials-no-fim-do-tic`
  só é detectada quando o esmagador zera a vida do jogador: sem
  `damagecount`, a barra de status não reage antes disso. Corrigir o
  esmagamento (dano por `P_DamageMobj`) ou gravar os tetos mudaria o
  `Teto` (o save precisaria de direção e velocidade no registro).

---

## Corrigido

| Item | Como | Commit / referência |
|---|---|---|
| `carry` vaza para um jogo novo (seção 5) | `atmos`: `defer { G.game.carry = nil }` no início de `task Jogo`; `lua`: `game.carry = nil` no New Game (`docs/registro/13-correcoes-c1.md`) | C1, tag `c1` |
| Jogador esmagado não morre (specials) | o esmagamento passa por `game.damage_mobj` (gancho `collision.dano_esmagar`), nas duas branches: dor, armadura, modo deus, morte. A cadência (a cada 4 tics) e o sangue ficam no item "Esmagamento sem sangue nem restos" | C1, tag `c1` |
| Menu não pausa; sem tecla de pausa (seção 4) | com o menu aberto (depois do primeiro tic do nível) ou com a tecla Pause, o `Nivel` desliga a task `Mundo` com `toggle`; a barra e o automapa continuam, a figura `M_PAUSE` aparece e a música pausa. Na branch `lua`, um `if` em volta do tic do mundo (`docs/registro/14-correcoes-c2.md`). Fica diferente: a tecla Pause só vale no nível (no Doom, ela também mostra a figura na intermissão e no finale, que continuam) e é engolida pelas mensagens do menu | C2, tag `c2` |
| Arma (seção 4) | os dois psprites do Doom (a arma e o clarão) com os estados de `info.STATES` e as ações do `p_pspr.c` (`pspr.lua`); a task `Arma` com as fases do Doom por arma; o desenho só lê os psprites; a tecla 1, a motosserra e o soco como no Doom (`docs/registro/15-correcoes-c3.md`) | C3, tag `c3` |
| Porta não reabre ao esmagar (specials) | a porta fechando que bate em algo volta a abrir, menos as que só fecham; as rápidas tocam `bdcls` ao fechar (`docs/registro/16-correcoes-c4.md`, C4a) | C4a, tag `c4` |
| Teto que sobe não sobe; esmagador que só desce; desaceleração; esmagador não para; esmagador parado não volta; limite dos tetos (specials) | a linha 40 sobe até o teto vizinho mais alto; 44, 72, 41 e 43 não esmagam; desaceleram o comum, o silencioso e o que só desce; as linhas 57 e 74 param os tetos (a task `Teto` desligada com `toggle`) e as de esmagador os reativam; 30 tetos ativos (C4b) | C4b, tag `c4` |
| Esmagamento sem sangue nem restos (specials) | a cada 4 tics, com um jato de sangue (`MT_BLOOD`, `P_Random`); corpos viram restos (`S_GIBS`); itens largados somem (C4c). O mobj do jogador, sem estados, não vira restos (seção 4) | C4c, tag `c4` |
| Elevador que sobe não volta ao bater; elevador parado não volta; limite dos elevadores (specials) | subindo, o elevador que bate volta a descer; parado (`in_stasis`, `oldstatus` no save) não pensa (a task `Elevador` desligada com `toggle`; o recado do passo 3c sumiu) e as linhas 53 e 87 o reativam; 30 elevadores ativos, erro se estourar (C4d) | C4d, tag `c4` |
| Piso não troca o special; escada; sons de piso e teto (specials) | o donut e o "baixar e trocar" trocam o special (no hash de estado desde então); a escada do `EV_BuildStairs`; `stnmov` a cada 8 tics e `pstop` (C4e) | C4e, tag `c4` |
| Botão duplicado; botão sem som ao voltar; limite dos botões (specials) | um botão ativo para a linha impede outro; `swtchn` ao voltar; 16 botões, erro se estourar (C4f) | C4f, tag `c4` |
| Descrição do save (save game) | escolher o slot começa a digitação da descrição, como no `M_SaveSelect`; `enter` só grava com descrição (C4g) | C4g, tag `c4` |
| Load aplica os mobjs por índice (seção 5); tetos não gravados, pisos pela metade, luzes não gravadas (save game) | o save tem o conteúdo do save do Doom: grava o mobj inteiro, com o tipo, e o load apaga o que o nível montou e recria tudo a partir do save (`P_UnArchiveThinkers`, `P_UnArchiveSpecials`); grava os tetos (com o parado), as luzes (o fogo também) e os pisos inteiros. A task `Monstro` perdeu o caso `estranho` (`docs/registro/17-save-formato-doom.md`) | C5, tag `c5` |
| Rosto da barra fora do hash de estado (seção 5) | `face_index` no `G.state_string` (`r<face_index>`), nos três lugares: `atmos`, `tests/ref-passo1.patch` e a branch `lua` (`docs/registro/10-interface-e-mundo.md`, passo 8b). Só teste: o jogo não mudou | passo 8 (tag `passo8`) |
| Mutações pendentes de cobertura (seção 5) | roteiro `ordem` (E1M3): "use" no tic em que a linha entra no alcance; porta e elevador vizinhos no mesmo tic, com o jogador na fronteira (`docs/registro/12-mutacoes-pendentes.md`). Só teste: o jogo não mudou | B2 (sem tag nova) |
