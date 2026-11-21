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

| Falta ou difere | Onde | No Doom original | Aqui |
|---|---|---|---|
| Porta não reabre ao esmagar | `setores.atm` (task `Porta`; antes `tick_door`) | `T_VerticalDoor`: porta fechando que bate em algo volta a abrir (exceto as rápidas que só fecham) | fica tentando fechar a cada tic |
| Esmagamento sem sangue nem restos | `collision.change_sector` | `P_ChangeSector` / `PIT_ChangeSector`: cadáveres viram restos (`S_GIBS`), itens largados são removidos, sangue com `P_Random` a cada 4 tics | esmaga a cada tic (o dano passa por `damage_mobj` desde o C1), sem sangue; não consome `P_Random` no esmagamento |
| Desaceleração ao esmagar | task `Teto` (antes `tick_ceiling`) | `T_MoveCeiling`: ao esmagar, desacelera (`CEILSPEED/8`) o esmagador comum (73, 25, 49), o silencioso (141) e o que só desce (44, 72); o rápido (77, 6) não desacelera | desacelera o comum, o rápido e o silencioso; o que só desce (44, 72) não desacelera |
| Esmagador que só desce | `do_crusher` | `EV_DoCeiling` cria o `lowerAndCrush` (44, 72) com `crush = false` | `crush = true` (também no 41/43, que o original não esmaga) |
| Teto que sobe não sobe | task `Teto` (antes `tick_ceiling`) | `raiseToHighest` (linha 40) sobe até o teto vizinho mais alto (`topheight = P_FindHighestCeilingSurrounding`) | `do_crusher` calcula esse destino em `dest`, mas o tick usa `topheight`, que é a altura atual: o teto não se move e a task termina no primeiro tic (mutação `teto-vai-ate-o-mais-alto` no passo 3d) |
| Sons de piso e teto | tasks `Piso` e `Teto` | `sfx_stnmov` a cada 8 tics em movimento (exceto o esmagador silencioso) e `sfx_pstop` quando um piso chega | silenciosos (só o esmagador silencioso toca "pstop" ao virar) |
| Piso não troca o special | task `Piso` | donut e "baixar e trocar" trocam a textura **e** o `special` do setor (`newspecial`) | só a textura |
| Escada | `do_stairs` | `EV_BuildStairs` só segue linhas em que o degrau atual está na frente, e soma a altura antes de testar se o setor está ocupado | segue linhas pelos dois lados; soma a altura só no degrau escolhido |
| Esmagador não para | `specials.lua`, tabela de linhas (tipos 57 e 74) | `EV_CeilingCrushStop` | as linhas 57 e 74 chamam `stop_plat` (param elevadores) |
| Elevador que sobe não volta ao bater | task `Elevador` (antes `tick_plat`) | `T_PlatRaise`: subindo, se bate em algo (sem esmagar), volta a descer | fica tentando subir |
| Elevador parado não volta | `do_plat_perpetual` | `P_ActivateInStasis`: a linha 87 reativa um elevador perpétuo parado | um elevador parado (linhas 54 e 89) fica parado; `do_plat_perpetual` só cria em setor livre |
| Esmagador parado não volta | (ausente) | `P_ActivateInStasisCeiling` | não existe |
| Botão duplicado | `change_switch` | `P_StartButton` não cria um segundo botão para a mesma linha | apertar de novo antes de voltar cria outro botão, que devolve a textura trocada depois |
| Botão sem som ao voltar | task `Botao` | `P_UpdateSpecials` toca "swtchn" ao devolver a textura | silencioso |
| Sem limites | `specials.lua` | `MAXPLATS` (30), `MAXCEILINGS` (30), `MAXBUTTONS` (16); estourar dá erro | sem limite |
| Velocidade do elevador "desce, espera, sobe" | `do_plat_dwus` | `EV_DoPlat` (`downWaitUpStay`): `PLATSPEED * 4` (4 unidades por tic) | `PLATSPEED` (1 por tic). Achado no C4d; corrigir muda o cenário do roteiro `ordem` (B2) |

Caminhos sem cobertura possível no `doom.wad` (migrados, mas nenhum mapa os
usa): linha 17 (strobe criado por linha), setores 10 e 14 (portas que
fecham em 30 s ou abrem em 5 min, nascidas do setor), linhas 41 e 43 (teto
desce até o piso) e 141 (esmagador silencioso).

## 2. Save game

| Falta ou difere | Onde | Efeito |
|---|---|---|
| Tetos e esmagadores não são gravados | `saveg.lua`, `dump_thinker` devolve `nil` para `ceiling` | um esmagador em movimento some ao carregar |
| Pisos gravados pela metade | `dump_thinker`, `kind == "floor"` | só `direction`, `dest` e `speed`; faltam `crush` e a troca de textura no fim (donut, baixar e trocar) |
| Luzes não são gravadas | `saveg.lua` | o Doom grava pisca, strobe e glow (o fogo também não, no original); aqui a fase recomeça no load |
| Descrição do save | `menu.lua`, ação `saveslot` | o Doom deixa digitar a descrição; aqui grava com o nome do mapa |

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
| Rosto da barra fora do hash de estado | `G.state_string` (ferramenta de teste) | um efeito de um tic na barra pode cair num tic que não vira quadro (tics aos pares no replay, passo 3d); pôr `face_index` no hash. Muda os logs da referência: fazer junto com uma tag nova |
| Load aplica os mobjs por índice | `saveg.apply` | os registros gravados vão para os mobjs que o nível acabou de criar, na ordem da lista; se ela mudou desde o save (itens apanhados, projéteis), um mobj recebe o estado de outro tipo (visto no passo 5: um zumbi com o estado 825; no passo 9, no E1M5, monstros dos quatro tipos com task recebem estados de outro tipo depois do load, e a task segue a tabela pelo caso `estranho`). O Doom recria os mobjs a partir do save (`P_UnArchiveThinkers`); corrigir isso muda o formato do save |

---

## Relação com os próximos passos

- **3c (elevadores, feito):** congelar a task com `toggle` **não** é
  equivalente: o elevador parado deste port continua descontando o `count`
  (só o save mostra; mutação `parar-com-toggle`). Por isso o parar ficou como
  recado no registro. A reativação (`P_ActivateInStasis`) seria uma correção
  posterior, com nova referência; aí o `toggle t(true)` passaria a servir.
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
| Mutações pendentes de cobertura (seção 5) | roteiro `ordem` (E1M3): "use" no tic em que a linha entra no alcance; porta e elevador vizinhos no mesmo tic, com o jogador na fronteira (`docs/registro/12-mutacoes-pendentes.md`). Só teste: o jogo não mudou | B2 (sem tag nova) |
