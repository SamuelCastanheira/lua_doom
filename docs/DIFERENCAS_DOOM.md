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
- a branch `lua` não tem modo replay: a igualdade entre as duas depois da
  correção precisa de um método próprio (por exemplo, levar o modo replay e
  o hash de estado para a `lua` antes de começar).

---

## 1. Specials de setor

| Falta ou difere | Onde | No Doom original | Aqui |
|---|---|---|---|
| Porta não reabre ao esmagar | `setores.atm` (task `Porta`; antes `tick_door`) | `T_VerticalDoor`: porta fechando que bate em algo volta a abrir (exceto as rápidas que só fecham) | fica tentando fechar a cada tic |
| Esmagamento sem sangue nem restos | `collision.change_sector` | `P_ChangeSector` / `PIT_ChangeSector`: cadáveres viram restos (`S_GIBS`), itens largados são removidos, sangue com `P_Random` a cada 4 tics | só tira 10 de vida; não consome `P_Random` |
| Jogador esmagado não morre | `collision.change_sector` | o dano passa por `P_DamageMobj`: cara de dor na barra (`damagecount`) e morte com vida 0 | a vida é subtraída direto: sem cara de dor; com vida 0 o jogador continua de pé (`playerstate` não vira `PST_DEAD`) e não tem como renascer. Visto no roteiro `pisos` (passo 3d) |
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
| Arma | `player.lua` (`WEAPON_PATCH`, `WEAPON_READY`, `WEAPON_ATK`) | tabelas próprias, não a máquina de estados do `p_pspr.c`; é o passo 4b (`PLANO_ATMOS.md`) |
| Transição de tela (wipe) | `wipe.lua` | usa `math.random`, não a tabela fixa (`M_Random`); só é determinística porque o replay fixa a semente |

## 5. Revisões do próprio port (não são do Doom)

Bugs e pendências encontrados durante a migração, guardados para a mesma
fase de correção.

| Revisão | Onde | O que fazer |
|---|---|---|
| `carry` vaza para um jogo novo | `G.new_game` (registro do passo 2, seção 8.1) | um jogo novo iniciado na intermissão começa com as armas do anterior; correção proposta: `game.carry = nil` em `G.new_game` (ou `defer` no início de `task Jogo`) |
| Rosto da barra fora do hash de estado | `G.state_string` (ferramenta de teste) | um efeito de um tic na barra pode cair num tic que não vira quadro (tics aos pares no replay, passo 3d); pôr `face_index` no hash. Muda os logs da referência: fazer junto com uma tag nova |
| Mutações pendentes de cobertura | `tools/mutacoes.py`, `PENDENTES` | porta e elevador vizinhos andando no mesmo tic, com um mobj na fronteira: montar um roteiro com esse cenário |

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

(nenhum item ainda)
