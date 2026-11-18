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

---

## 1. Specials de setor

| Falta ou difere | Onde | No Doom original | Aqui |
|---|---|---|---|
| Porta não reabre ao esmagar | `setores.atm` (task `Porta`; antes `tick_door`) | `T_VerticalDoor`: porta fechando que bate em algo volta a abrir (exceto as rápidas que só fecham) | fica tentando fechar a cada tic |
| Esmagamento sem sangue nem restos | `collision.change_sector` | `P_ChangeSector` / `PIT_ChangeSector`: cadáveres viram restos (`S_GIBS`), itens largados são removidos, sangue com `P_Random` a cada 4 tics | só tira 10 de vida; não consome `P_Random` |
| Esmagador não para | `specials.lua`, tabela de linhas (tipos 57 e 74) | `EV_CeilingCrushStop` | as linhas 57 e 74 chamam `stop_plat` (param elevadores) |
| Elevador parado não volta | `do_plat_perpetual` | `P_ActivateInStasis`: a linha 87 reativa um elevador perpétuo parado | um elevador parado (linhas 54 e 89) fica parado; `do_plat_perpetual` só cria em setor livre |
| Esmagador parado não volta | (ausente) | `P_ActivateInStasisCeiling` | não existe |
| Botão duplicado | `change_switch` | `P_StartButton` não cria um segundo botão para a mesma linha | apertar de novo antes de voltar cria outro botão, que devolve a textura trocada depois |
| Botão sem som ao voltar | task `Botao` | `P_UpdateSpecials` toca "swtchn" ao devolver a textura | silencioso |
| Sem limites | `specials.lua` | `MAXPLATS` (30), `MAXCEILINGS` (30), `MAXBUTTONS` (16); estourar dá erro | sem limite |

Caminhos sem cobertura possível no `doom.wad` (migrados, mas nenhum mapa os
usa): linha 17 (strobe criado por linha) e setores 10 e 14 (portas que
fecham em 30 s ou abrem em 5 min, nascidas do setor).

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

---

## Relação com os próximos passos

- **3c (elevadores):** como este port nunca reativa um elevador parado,
  migrar por equivalência significa só congelar a task. A reativação
  (`P_ActivateInStasis`) seria uma correção posterior, que com `toggle t(true)`
  ficaria trivial: um bom exemplo para a monografia.
- **3d (pisos, tetos, esmagadores):** as linhas 57 e 74 trocadas e a falta de
  sangue no esmagamento mudam o que o roteiro de esmagadores consegue
  detectar, inclusive a mutação pendente `specials-no-fim-do-tic`
  (`tools/mutacoes.py`).
- **Save:** os tetos não gravados limitam o roteiro de save do 3d (um
  esmagador em movimento não sobrevive ao load nem na referência).

---

## Corrigido

(nenhum item ainda)
