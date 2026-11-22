#!/usr/bin/env python3
"""Teste de sensibilidade: o teste de equivalencia detecta erros?

Para cada mutacao (um erro plausivel num arquivo, por padrao o main.atm),
roda a versao mutada num roteiro e compara com a referencia desse roteiro
(build/drivers/ref_<roteiro>.log, gravado por tests/test_drivers.sh). Uma
mutacao "sobrevive" se o log sair identico; nesse caso o roteiro nao cobre
aquele comportamento (ou o mutante e equivalente).

Uso (depois de rodar os roteiros usados, como faz "make test-mutacoes"):
    sh tests/test_drivers.sh 0 1 fluxo
    sh tests/test_drivers.sh 1200 1 luzes -warp 4 1
    sh tests/test_drivers.sh 0 1 botoes -warp 1 1
    sh tests/test_drivers.sh 0 1 portas -warp 1 1
    sh tests/test_drivers.sh 0 1 elevadores -warp 1 3
    python3 tools/mutacoes.py [nome-da-mutacao ...]
"""
import os
import shutil
import subprocess
import sys
import sys as _sys
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pastas

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "build", "drivers")

# Roteiros: (arquivo do roteiro, log da referencia, argumentos do jogo).
ROTEIROS = {
    "fluxo": ("replay_1fluxo.txt", "ref_1fluxo.log", []),
    "luzes": ("replay_1luzes.txt", "ref_1luzes.log", ["-warp", "4", "1"]),
    "botoes": ("replay_1botoes.txt", "ref_1botoes.log", ["-warp", "1", "1"]),
    "portas": ("replay_1portas.txt", "ref_1portas.log", ["-warp", "1", "1"]),
    "elevadores": ("replay_1elevadores.txt", "ref_1elevadores.log", ["-warp", "1", "3"]),
    "pisos": ("replay_1pisos.txt", "ref_1pisos.log", ["-warp", "2", "2"]),
    "arma": ("replay_1arma.txt", "ref_1arma.log", ["-warp", "1", "1"]),
    "monstro": ("replay_1monstro.txt", "ref_1monstro.log", ["-warp", "1", "2", "-respawn"]),
    "familia": ("replay_1familia.txt", "ref_1familia.log", ["-warp", "1", "5", "-respawn"]),
    "ordem": ("replay_1ordem.txt", "ref_1ordem.log", ["-warp", "1", "3"]),
    "correcoes": ("replay_1correcoes.txt", "ref_1correcoes.log", ["-warp", "1", "1"]),
    "telas": ("replay_1telas.txt", "ref_1telas.log", ["-warp", "1", "1"]),
    "exits": ("replay_2exits.txt", "ref_2exits.log", []),
    "semente1": ("replay_1.txt", "ref_1.log", []),
}

# Mutantes equivalentes: mudam o codigo mas nao o comportamento. Sobreviver
# e o esperado; a justificativa fica registrada.
EQUIVALENTES = {
    "load-sem-task-monstro":
        "C5: o monstro recriado sem a task Monstro cai no thinker Lua "
        "(G.pensar_ate_task roda mobj_thinker para os mobjs sem task), que "
        "interpreta a mesma tabela; a task e o thinker sao equivalentes desde "
        "o passo 5, e o jogo e o mesmo. A mutacao mostra o que o teste de "
        "equivalencia prova: a task nao muda o comportamento, so a forma",
    "salto-sem-vencido":
        "C5: o salto de fora que ja vence no mesmo tic so acontecia no load "
        "por indice, que aplicava tics arbitrarios aos mobjs. Os estados que "
        "podem ser postos de fora num monstro (dor, perseguicao, morte, "
        "explosao, restos) tem 2 tics ou mais, ou -1 (conferido em "
        "info.STATES para os quatro tipos): o salto desconta um tic e nao "
        "vence. Desde o C5 a task nasce no estado gravado, e o vencido da "
        "task Monstro ficou sem caminho (o da task Arma continua: a arma "
        "solta na morte tem 1 tic, mutacao salto-vencido-espera)",
    "pronta-nao-repete":
        "C3: o fim de qualquer faixa da arma volta ao primeiro quadro da arma "
        "pronta (entrar(W.pronta@1)), e o proximo da arma pronta e ela mesma "
        "(a da motosserra tem dois quadros, e o proximo do segundo e o "
        "primeiro): para a pronta, repetir e terminar dao o mesmo estado. A "
        "mesma mutacao na subida (subida-nao-repete) e detectada",
    "arma-no-meio-do-jogador":
        "a arma no meio do tic do jogador, como no P_PlayerThink do Doom "
        "(depois da troca pelo teclado, antes dos poderes). O que vem depois "
        "dela nao interage com ela: a forca so cresce e o soco so pergunta se "
        "e diferente de zero; tirar MF_SHADOW nao afeta o tiro; a arma nao le "
        "damagecount, bonuscount, mensagem nem fixedcolormap; e nenhuma dessas "
        "partes consome P_Random. Por isso o passo 4c poe a arma depois de "
        "todas as partes, sem corte (registro do passo 4, secao 4c)",
    "menu-depois-da-tela":
        "menu.ticker so muda skull_tics/which_skull (cursor do menu); nenhuma "
        "fase de tela le esses campos",
    "entra-antes-de-montar":
        "build_level nao le game.gamestate (a unica leitura fora das telas "
        "e am_map.responder, na fase de entrada)",
    "luzes-depois-do-resto":
        "as luzes so escrevem lightlevel e consomem P_Random; o resto em Lua "
        "(desde o 3b, so as linhas com scroll; no 3a tambem portas, "
        "elevadores e pisos) nao le lightlevel e nao consome P_Random no tick "
        "(o esmagamento deste port, "
        "collision.change_sector, so tira vida; o Doom original solta sangue "
        "com P_Random em P_ChangeSector, e la a ordem importaria)",
    "botoes-antes-do-resto":
        "os botoes so escrevem a textura (top/mid/bottom) do lado do switch; o "
        "resto em Lua (linhas com scroll: textureoffset) e os movimentadores "
        "(alturas de setor) nao leem texturas de lado e nao consomem P_Random "
        "no tick: campos disjuntos, sem dependencia de leitura",
}

# Mutantes NAO equivalentes que o roteiro ainda nao cobre. Sobreviver e
# esperado por enquanto (nao falha o teste), mas fica impresso com o motivo e
# com o roteiro que deve passar a detecta-lo. Quando esse roteiro existir,
# tire a mutacao daqui: ela tem de passar a "detectada".
PENDENTES = {
    # Desde o B2, as tres mutacoes que estavam aqui (usar-antes-de-mover,
    # portas-fora-de-movers e a mesma no roteiro fluxo) ganharam o roteiro
    # "ordem" (docs/registro/12-mutacoes-pendentes.md).
    "corpo-sem-restos":
        "C4c: nenhum roteiro esmaga o corpo de um monstro (os esmagadores dos "
        "roteiros, no E2M2 e no E2M4, nao tem monstros nos setores, conferido "
        "com prints; o jogador morto, que e esmagado, nao tem estados). Falta "
        "um cenario: matar um monstro dentro de um setor de esmagador e "
        "ligar o esmagador",
}

# Trechos do Nivel (main.atm) para as mutacoes de ordem das pools, extraidos
# na hora (o texto do Nivel muda a cada subpasso do passo 3).
def _trechos_nivel():
    m = open(os.path.join(ROOT, "main.atm")).read()
    i = m.index("    pin luzes = tasks()")
    luz = m[i:m.index("\n", i) + 1]
    ini = m.index("    spawn {", i)
    fim = m.index("\n    }\n", m.index("G.specials_resto()", ini)) + len("\n    }\n")
    resto = m[ini:fim]
    j = m.index("    pin botoes = tasks()")
    bot = m[j:m.index("\n", j) + 1]
    meio = m[fim:j]                       # o que esta entre o resto e os botoes
    return luz, resto, meio, bot


_LUZ, _RESTO, _MEIO, _BOT = _trechos_nivel()
LUZES_E_RESTO = _LUZ + _RESTO
RESTO_E_LUZES = _RESTO + _LUZ
RESTO_E_BOTOES = _RESTO + _MEIO + _BOT
BOTOES_E_RESTO = _BOT + _RESTO + _MEIO

# Mutacao de ordem do 3b: portas numa pool propria, depois dos outros
# movimentadores (main.atm, specials.lua e saveg.lua).
PORTAS_SEPARADAS = [
    ("main.atm", '    pin movers = tasks()                  ;; 3b-3d: portas, elevadores, pisos\n                                          ;; e tetos (setores.atm)\n', '    pin movers = tasks()                  ;; 3b-3d: portas, elevadores, pisos\n                                          ;; e tetos (setores.atm)\n    pin portas = tasks()\n'),
    ("main.atm", '    G.set_pools([luzes=luzes, movers=movers, botoes=botoes, monstros=monstros])', '    G.set_pools([luzes=luzes, movers=movers, portas=portas, botoes=botoes, monstros=monstros])'),
    ("specials.lua", "  return spawn_task(self, \"movers\", \"Porta\", self, porta)\n",
                     "  return spawn_task(self, \"portas\", \"Porta\", self, porta)\n"),
    ("saveg.lua", "    for _, t in pairs(movers) do\n",
                  "    local todas = {}\n    for _, t in pairs(movers) do todas[#todas + 1] = t end\n"
                  "    for _, t in pairs(game.pools.portas) do todas[#todas + 1] = t end\n"
                  "    for _, t in ipairs(todas) do\n"),
]

# (nome, descricao, trecho original, trecho mutado[, arquivo[, roteiro]])
# arquivo: padrao "main.atm"; roteiro: padrao "fluxo" (ver ROTEIROS).
# Mutacao em varios arquivos: "trecho original" e uma lista de
# (arquivo, original, mutado), e "trecho mutado" e arquivo ficam None.
MUTACOES = [
    # --- passo 2: fluxo de telas em tasks (roteiro "fluxo")
    ("sem-cancel-catchup",
     "Nivel nao interrompe a recuperacao de tics ao sair do nivel",
     "                env.cancel_catchup()      ;; nao recupera mais tics neste quadro\n",
     ""),
    ("fim-sem-limpeza",
     "End Game encerra a task Jogo mas esquece a limpeza (G.end_game)",
     "            await :jogo.fim\n            G.end_game()\n",
     "            await :jogo.fim\n"),
    ("morte-encerra-jogo",
     "Morrer termina o jogo em vez de renascer no mesmo mapa",
     "            (r.fim == :morte)  => true            ;; renasce no mesmo mapa\n",
     "            (r.fim == :morte)  => false\n"),
    ("secreto-sem-volta",
     "Do mapa 9 vai para o mapa 10 (esquece a volta do secreto)",
     "        (mapn == 9)   => (VOLTA_DO_SECRETO@episode) || 1\n",
     ""),
    ("menu-depois-da-tela",
     "Relogio roda a tela antes do menu (ordem do tic trocada)",
     "                emit @(menu) (:menu.tic)  ;; passo 8c: a caveira do menu\n                pedidos()\n                emit :game.tic\n",
     "                emit :game.tic\n                emit @(menu) (:menu.tic)\n                pedidos()\n"),
    ("pedidos-so-no-tic",
     "Pedidos da entrada so sao emitidos no tic seguinte",
     "        G.handle_input(ev)\n        pedidos()\n",
     "        G.handle_input(ev)\n"),
    ("entra-antes-de-montar",
     "Nivel entra em 'view' antes de montar o nivel",
     "        G.start_level()\n    }\n    G.enter(:view)\n",
     "        G.enter(:view)\n        G.start_level()\n    }\n    G.enter(:view)\n"),
    ("load-mantem-jogo",
     "Load Game nao descarta o jogo em andamento (pedido ignorado no Jogo)",
     "            await <:jogo.novo || :jogo.carregar>   ;; descarta o jogo atual\n",
     "            await :jogo.novo\n"),
    ("sair-sem-ultimo-quadro",
     "Quit encerra antes de desenhar o quadro atual",
     "    await :jogo.sair\n    await :frame                          ;; o quadro atual ainda e desenhado\n",
     "    await :jogo.sair\n"),
    ("trocar-ignora-mapa",
     "idclev reinicia o nivel atual em vez de ir ao mapa pedido",
     "                G.set_level(r.episode, r.mapn)\n",
     ""),
    ("wipe-nao-pausa",
     "Durante a transicao de tela, menu e tela continuam andando",
     "        loop on :tic {                    ;; so a transicao anda\n            until (G.tic_wipe())          ;; true quando termina\n        }\n",
     "        loop on :tic {\n            val fim = G.tic_wipe()\n            emit @(menu) (:menu.tic)\n            pedidos()\n            emit :game.tic\n            pedidos()\n            until (fim)\n        }\n"),
    # --- passo 3, subpasso 0: o ponto do :game.specials (roteiro "pisos")
    ("specials-no-fim-do-tic",
     "Specials de setor rodam depois de texturas, saida, leveltime e barra de status (fora do ponto do tic)",
     [("main.atm",
       "                mobjs()                   ;; passo 5: os mobjs, em ordem\n                emit :game.specials\n                G.tic_mundo_fim()         ;; nil | \"saida\"\n",
       "                mobjs()                   ;; passo 5: os mobjs, em ordem\n                val d = G.tic_mundo_fim()\n                if !d {\n                    emit @1 (:barra.tic)\n                    G.redesenhar()\n                }\n                emit :game.specials\n                d\n"),
      ("main.atm",
       "                    if !r.fim {\n                        emit @(rosto) (:barra.tic)     ;; passo 8b: o rosto\n                        G.redesenhar()\n                    }\n",
       "")],
     None, None, "pisos"),
    # --- passo 3a: luzes como tasks (roteiro "luzes": E4M1 e E1M2)
    ("pisca-sem-espera-inicial",
     "Luz que pisca age no proprio tic em que nasce (sem a espera inicial)",
     "    espera(pub, contagem || (band(rng.p_random(), 64) + 1))\n",
     "    rng.p_random()\n",
     "setores.atm", "luzes"),
    ("fogo-intervalo-3",
     "Fogo tremula a cada 3 tics em vez de 4",
     "    var n = contagem || 4\n    loop {\n        espera(pub, n)\n        set n = 4\n",
     "    var n = contagem || 3\n    loop {\n        espera(pub, n)\n        set n = 3\n",
     "setores.atm", "luzes"),
    ("strobe-sincronizado-sorteia",
     "Strobe sincronizado sorteia a primeira espera (consome P_Random a mais)",
     "        sincronizado => 1\n",
     "        sincronizado => (band(rng.p_random(), 7) + 1)\n",
     "setores.atm", "luzes"),
    ("brilho-nao-volta",
     "Glow inverte a direcao sem desfazer o ultimo passo (passa do minimo)",
     "            set setor.lightlevel = setor.lightlevel + GLOWSPEED\n            set pub.direction = 1\n",
     "            set pub.direction = 1\n",
     "setores.atm", "luzes"),
    ("luzes-ordem-inversa",
     "Luzes criadas na ordem inversa dos setores (ordem da pool trocada)",
     "  for i = 1, #self.world.sectors do\n    local sector = self.world.sectors[i]\n    local spec = sector.special\n",
     "  for i = #self.world.sectors, 1, -1 do\n    local sector = self.world.sectors[i]\n    local spec = sector.special\n",
     "specials.lua", "luzes"),
    ("luzes-depois-do-resto",
     "Pool de luzes acorda depois dos specials ainda em Lua (ordem do M.tick trocada)",
     # move a task do resto para antes da pool de luzes (sem duplica-la)
     LUZES_E_RESTO,
     RESTO_E_LUZES,
     "main.atm", "luzes"),
    # --- passo 3e: botoes como tasks (roteiro "botoes": E1M1, save/load, E1M4)
    ("botao-sem-espera-inicial",
     "Botao conta o primeiro tic no proprio spawn (age uma fase antes)",
     "    loop {\n        await :game.specials\n        set pub.timer = pub.timer - 1\n        until (pub.timer <= 0)\n    }\n",
     "    loop {\n        set pub.timer = pub.timer - 1\n        until (pub.timer <= 0)\n        await :game.specials\n    }\n",
     "setores.atm", "botoes"),
    ("botao-um-tic-a-mais",
     "Botao devolve a textura um tic depois (timer < 0 em vez de <= 0)",
     "        until (pub.timer <= 0)\n",
     "        until (pub.timer < 0)\n",
     "setores.atm", "botoes"),
    ("botao-nao-restaura",
     "Botao termina sem devolver a textura original",
     "    if lado {\n        set lado@attr = textura\n    }\n",
     "",
     "setores.atm", "botoes"),
    ("save-esquece-botoes",
     "Save nao grava os botoes ativos (a textura fica trocada depois do load)",
     "      if btn and btn.timer > 0 and not btn.dead then\n",
     "      if false then\n",
     "saveg.lua", "botoes"),
    ("load-reinicia-timer",
     "Load recria o botao com o timer cheio (35) em vez do gravado",
     "where_attr[rec.where or \"\"] or \"toptexture\", rec.texture or 0, rec.timer or 0)",
     "where_attr[rec.where or \"\"] or \"toptexture\", rec.texture or 0, 35)",
     "saveg.lua", "botoes"),
    ("botoes-antes-do-resto",
     "Pool de botoes acorda antes do resto em Lua e dos movimentadores (ordem do M.tick trocada)",
     RESTO_E_BOTOES,
     BOTOES_E_RESTO,
     "main.atm", "botoes"),
    # --- passo 3b: portas como tasks (roteiro "portas": E1M1, E1M6, E1M2)
    ("porta-sem-espera-inicial",
     "Porta anda no proprio spawn, antes da sua fase (sem o await inicial)",
     "val func mover (sp, porta, dir, direto) {\n    var espera = !direto\n",
     "val func mover (sp, porta, dir, direto) {\n    var espera = false\n",
     "setores.atm", "portas"),
    ("recado-ignorado-movendo",
     "Porta em movimento ignora o recado (outro use nao inverte)",
     "        until (porta.direction != dir, :troca)\n",
     "",
     "setores.atm", "portas"),
    ("recado-ignorado-esperando",
     "Porta esperando ignora o recado (outro use no topo nao fecha)",
     "        until (porta.direction != 0, :troca)\n",
     "",
     "setores.atm", "portas"),
    ("recado-um-tic-depois",
     "Depois do recado, a porta so anda no tic seguinte (perde o tic da troca)",
     "        set direto = (r == :troca)\n        ifs {\n            (r == :troca) => {}           ;; recado: segue na direcao nova",
     "        set direto = false\n        ifs {\n            (r == :troca) => {}           ;; recado: segue na direcao nova",
     "setores.atm", "portas"),
    ("recado-vira-evento",
     "O recado vira um evento imediato: o use emite :game.specials para os "
     "movimentadores na hora (dentro do pensamento do jogador)",
     "      if door.direction == -1 then\n        door.direction = 1\n      else\n        door.direction = -1\n      end\n",
     "      if door.direction == -1 then\n        door.direction = 1\n      else\n        door.direction = -1\n      end\n"
     "      emit_in(self.pools.movers, \"game.specials\")\n",
     "specials.lua", "portas"),
    ("porta-nao-libera-setor",
     "Porta termina sem liberar o setor (specialdata fica ocupado)",
     "        set porta.sector.specialdata = nil\n        set porta.dead = true\n",
     "        set porta.dead = true\n",
     "setores.atm", "portas"),
    ("load-perde-contagem",
     "Load recria a porta com a contagem zerada (topcountdown nao restaurado)",
     "          topcountdown = rec.topcountdown or 0,\n",
     "          topcountdown = 0,\n",
     "saveg.lua", "portas"),
    ("portas-fora-de-movers",
     "Portas numa pool propria depois dos outros movimentadores (ordem entre "
     "porta e elevador trocada)",
     PORTAS_SEPARADAS, None, None, "ordem"),
    # --- passo 3c: elevadores como tasks (roteiro "elevadores": E1M3, E2M3)
    ("elevador-sem-espera-inicial",
     "Elevador anda no proprio spawn, antes da sua fase (sem o await inicial)",
     "    loop {\n        await :game.specials\n        val r = S.move_plane(sp.world, plat.sector, plat.speed, destino, 0, dir, false)\n        until (r == S.RESULT_PASTDEST, :chegou)\n        until ((st == P.UP) && (r == S.RESULT_CRUSHED), :bateu)\n    }\n",
     "    loop {\n        val r = S.move_plane(sp.world, plat.sector, plat.speed, destino, 0, dir, false)\n        until (r == S.RESULT_PASTDEST, :chegou)\n        until ((st == P.UP) && (r == S.RESULT_CRUSHED), :bateu)\n        await :game.specials\n    }\n",
     "setores.atm", "elevadores"),
    ("perpetuo-para-no-topo",
     "Elevador perpetuo termina ao chegar em cima (tratado como desce-sobe)",
     "                until ((st != P.DOWN) && (plat.type != P.PERPETUAL))   ;; subiu: acabou\n",
     "                until (st != P.DOWN)\n",
     "setores.atm", "elevadores"),
    ("espera-um-tic-a-menos",
     "Elevador espera um tic a menos embaixo (count = wait - 1)",
     "                set plat.status = P.WAITING\n                set plat.count = plat.wait\n",
     "                set plat.status = P.WAITING\n                set plat.count = plat.wait - 1\n",
     "setores.atm", "elevadores"),
    ("load-perde-status",
     "Load recria o elevador sempre descendo (status nao restaurado)",
     "          status = rec.status or 0,\n",
     "          status = 0,\n",
     "saveg.lua", "elevadores"),
    # --- passo 3d: pisos e tetos como tasks (roteiro "pisos": E2M2, E2M4,
    # E2M1, E3M5; o jogador fica embaixo de dois esmagadores)
    ("piso-sem-espera-inicial",
     "Piso anda no proprio spawn, antes da sua fase (await no fim do laco)",
     "    loop {\n        await :game.specials\n        val r = S.move_plane(sp.world, piso.sector, piso.speed, piso.dest, 0, piso.direction, piso.crush)\n        S.som_de_pedra(sp)                ;; C4e: a cada 8 tics andando\n        until (r == S.RESULT_PASTDEST)\n    }\n",
     "    loop {\n        val r = S.move_plane(sp.world, piso.sector, piso.speed, piso.dest, 0, piso.direction, piso.crush)\n        S.som_de_pedra(sp)\n        until (r == S.RESULT_PASTDEST)\n        await :game.specials\n    }\n",
     "setores.atm", "pisos"),
    ("piso-nao-troca-textura",
     "Piso que chega ao destino nao troca a textura do chao (donut, baixar e trocar)",
     "    if piso.floorpic {\n        set piso.sector.floorpic = piso.floorpic\n",
     "    if piso.floorpic {\n",
     "setores.atm", "pisos"),
    ("piso-troca-textura-no-inicio",
     "Piso troca a textura do chao ao nascer, nao ao chegar",
     "val task Piso (sp, piso) {\n    set pub = piso\n",
     "val task Piso (sp, piso) {\n    set pub = piso\n    if piso.floorpic {\n        set piso.sector.floorpic = piso.floorpic\n    }\n",
     "setores.atm", "pisos"),
    ("esmagador-nao-desacelera",
     "Esmagador que vai e volta nao desce devagar depois de esmagar",
     "                set teto.speed = devagar\n",
     "",
     "setores.atm", "pisos"),
    ("esmagador-sobe-devagar",
     "Esmagador nao volta a velocidade normal ao chegar embaixo",
     "        if dir == -1 {                    ;; chegou embaixo: sobe na normal\n            set teto.speed = normal\n        }\n",
     "",
     "setores.atm", "pisos"),
    ("esmagador-para-no-fundo",
     "Esmagador que vai e volta termina ao chegar ao destino",
     "        until (!vai_e_volta)\n",
     "        until (true)\n",
     "setores.atm", "pisos"),
    ("esmagador-rapido-volta-normal",
     "Esmagador rapido (77) volta a velocidade normal, nao a dobrada",
     "    val normal = if t == C.FASTCRUSH => (S.CEILSPEED * 2) => S.CEILSPEED\n",
     "    val normal = S.CEILSPEED\n",
     "setores.atm", "pisos"),
    ("load-perde-piso",
     "Load nao recria os pisos em movimento",
     "          sp.start_floor(game.specials, th)      -- idem (passo 3d)\n",
     "",
     "saveg.lua", "pisos"),
    # --- passo 4a: arma como task (roteiro "arma": E1M1); a primeira e do 4c
    ("jogador-depois-dos-mobjs",
     "Jogador (e a arma) acordam depois dos mobjs (fora do ponto do tic)",
     "        emit :game.jogador                ;; passo 4c: task Jogador\n        val meio = G.tic_view_meio()      ;; \"segue\" | \"morte\"\n",
     "        val meio = G.tic_view_meio()      ;; \"segue\" | \"morte\"\n        emit :game.jogador\n",
     "main.atm", "arma"),
    # As mutacoes da task Arma do 4a (fases por nome, flash_tics) sairam no
    # C3, com o codigo que testavam (registro do C3); as do C3 estao abaixo,
    # na secao "# --- C3".
    # --- passo 4c: o jogador como task (roteiros "arma" e "fluxo")
    ("arma-no-meio-do-jogador",
     "A arma no meio do tic do jogador, como no Doom (antes dos poderes)",
     "        J.escolher_arma(p, game)          ;; pedido pelo teclado\n        J.contar_poderes(p)               ;; e o efeito de tela\n        J.contar_avisos(p)                ;; claroes e mensagem\n        emit :jogador.arma\n",
     "        J.escolher_arma(p, game)          ;; pedido pelo teclado\n        emit :jogador.arma\n        J.contar_poderes(p)               ;; e o efeito de tela\n        J.contar_avisos(p)                ;; claroes e mensagem\n",
     "jogador.atm", "arma"),
    ("morto-perde-o-tic-da-morte",
     "No tic em que percebe a morte, o Jogador espera o proximo tic para agir",
     "    loop {                                ;; morto (o tic corrente ja chegou)\n        J.arrancada(p)\n        J.cair(",
     "    loop {                                ;; morto (o tic corrente ja chegou)\n        await :game.jogador\n        J.arrancada(p)\n        J.cair(",
     "jogador.atm", "arma"),
    ("morto-sem-arma",
     "Com o jogador morto, a arma para (nao desce)",
     "        emit :jogador.arma                ;; a arma continua descendo\n",
     "",
     "jogador.atm", "arma"),
    ("renasce-sem-use",
     "O morto renasce sem apertar use",
     "        val renasce = J.usou(p)\n",
     "        val renasce = true\n",
     "jogador.atm", "arma"),
    ("usar-antes-de-mover",
     "O jogador usa as linhas antes de se mover no tic",
     "        J.mover(w, p, game, t)            ;; girar, andar, altura da camera\n        J.pisar(w, p, game, t)            ;; dano e segredo do setor\n        J.usar(w, p, game)                ;; linhas\n",
     "        J.usar(w, p, game)                ;; linhas\n        J.mover(w, p, game, t)            ;; girar, andar, altura da camera\n        J.pisar(w, p, game, t)            ;; dano e segredo do setor\n",
     "jogador.atm", "ordem"),
    # --- passo 5: o Zombieman como task (roteiro "monstro": E1M2, -respawn)
    ("zumbi-age-no-spawn",
     "O zumbi da um tic do thinker no proprio spawn (antes da sua vez)",
     "    var vencido = false\n    loop {\n        val st = mo.istate\n",
     "    T.mobj_thinker(game.world, mo, game)\n    var vencido = false\n    loop {\n        val st = mo.istate\n",
     "monstro.atm", "monstro"),
    ("dor-volta-a-procurar",
     "Depois de atacar ou sentir dor, o zumbi volta a procurar (nao a correr)",
     "            (r == :fim) => entrar(mo, game, C.correr@1)",
     "            (r == :fim) => entrar(mo, game, C.procurar@1)",
     "monstro.atm", "monstro"),
    ("salto-sem-vencido",
     "Depois de um salto de fora com os tics ja no fim, o zumbi espera mais um tic",
     "        set vencido = (r == :salto) && (mo.tics <= 0)",
     "        set vencido = false",
     "monstro.atm", "familia"),          # C3: no roteiro monstro, o caso sumiu com a arma nova
    ("corpo-nao-volta",
     "O corpo do zumbi nunca volta no pesadelo (-respawn)",
     "            T.mobj_parado(game.world, mo, game)   ;; corpo: pesadelo (-respawn)\n",
     "",
     "monstro.atm", "monstro"),
    ("zumbi-sem-movimento",
     "O zumbi nao se move por momento (empurrao do tiro, queda)",
     "        until (!T.mobj_mover(game.world, mo, game), :fora)\n",
     "",
     "monstro.atm", "monstro"),
    ("monstros-depois-dos-outros",
     "Os monstros com task pensam depois de todos os outros mobjs (fora de ordem)",
     "    val lista = G.pensantes()\n    var i = G.pensar_ate_task(lista, 1)\n    loop {\n        until (i == 0)\n        val mo = lista@i\n        emit @(mo.task) (:mobj.tic)\n        set i = G.pensar_ate_task(lista, i + 1)\n    }\n",
     "    val lista = G.pensantes()\n    val zumbis = []\n    var i = G.pensar_ate_task(lista, 1)\n    loop {\n        until (i == 0)\n        set zumbis@(#zumbis + 1) = lista@i\n        set i = G.pensar_ate_task(lista, i + 1)\n    }\n    loop _, mo in zumbis {\n        emit @(mo.task) (:mobj.tic)\n    }\n",
     "main.atm", "monstro"),
    # --- passo 6: wipe como fase do relogio e quadro por evento (roteiro "fluxo")
    ("transicao-sem-evento",
     "O quadro nao avisa o relogio do wipe (o tic normal continua durante a transicao)",
     "                emit :tela.transicao      ;; comecou um wipe: o relogio troca de fase\n",
     ""),
    ("wipe-um-tic-depois",
     "Depois do aviso, a transicao so comeca a andar um tic depois",
     "        loop on :tic {                    ;; so a transicao anda\n",
     "        await :tic\n        loop on :tic {                    ;; so a transicao anda\n"),
    ("vista-nao-se-desenha",
     "O Nivel nao desenha a vista (fica a imagem anterior)",
     "    spawn {                               ;; passo 6: a vista desenha a si mesma\n        loop on :game.frame { G.pintar_vista() }\n    }\n",
     ""),
    ("intermissao-nao-se-desenha",
     "A intermissao nao desenha a si mesma",
     "    spawn {\n        loop on :game.frame { G.pintar_intermissao() }\n    }\n",
     ""),
    # --- passo 7: intermissao e finale como tasks (roteiros "telas" e "exits")
    ("pausa-um-tic-a-menos",
     "A pausa entre as linhas da contagem dura um tic a menos",
     "    var n = WI.TICRATE\n",
     "    var n = WI.TICRATE - 1\n",
     "telas.atm", "telas"),
    ("contagem-sem-tempo",
     "A contagem pula o tempo e o par",
     "        val r8 = contar_tempo(w, G, math.floor(s.stime / WI.TICRATE), math.floor(s.partime / WI.TICRATE))\n",
     "        val r8 = :fim\n",
     "telas.atm", "telas"),
    ("intermissao-nao-espera",
     "Depois da contagem, a intermissao segue sem esperar acelerar",
     "    loop {                                ;; espera acelerar\n        tic(w, G)\n        until (w.accelerate != 0)\n    }\n",
     "",
     "telas.atm", "telas"),
    ("proximo-mapa-mais-longo",
     "O mapa com o proximo nivel fica um segundo a mais",
     "        var n = WI.SHOWNEXTLOCDELAY * WI.TICRATE\n",
     "        var n = (WI.SHOWNEXTLOCDELAY + 1) * WI.TICRATE\n",
     "telas.atm", "telas"),
    ("contar-ignora-acelerar",
     "Acelerar no meio de uma linha da contagem e ignorado",
     "        until (w.accelerate != 0, :acelerou)\n        set w@campo = (w@campo) + 2\n",
     "        set w@campo = (w@campo) + 2\n",
     "telas.atm", "telas"),
    ("finale-texto-um-tic-a-menos",
     "O texto do finale termina um tic antes",
     "        val total = (#f.text * F.TEXTSPEED) + F.TEXTWAIT\n",
     "        val total = ((#f.text * F.TEXTSPEED) + F.TEXTWAIT) - 1\n",
     "telas.atm", "telas"),
    ("finale-pula-sem-esperar",
     "A arte do finale pode ser pulada logo no comeco",
     "        val depois = if (f.pfub1 && f.pfub2) => 1130 => 10\n",
     "        val depois = 0\n",
     "telas.atm", "telas"),
    # --- passo 8: menu, barra de status, automapa e a task Mundo
    ("status-antes-do-mundo",
     "A barra de status roda antes do mundo no tic (le a vida do tic anterior)",
     "                    emit @(mundo) (:mundo.tic)         ;; passo 8a: o tic do mundo\n                    if !r.fim {\n                        emit @(rosto) (:barra.tic)     ;; passo 8b: o rosto\n                        G.redesenhar()\n                    }\n",
     "                    emit @(rosto) (:barra.tic)\n                    G.redesenhar()\n                    emit @(mundo) (:mundo.tic)\n",
     "main.atm", "arma"),
    ("menu-caveira-lenta",
     "A caveira do menu pisca a cada 9 tics, nao 8",
     "                    set caveira = 8\n",
     "                    set caveira = 9\n",
     "interface.atm", "fluxo"),
    ("menu-caveira-fechado",
     "A caveira conta os tics tambem com o menu fechado",
     "            if m.active {\n                set caveira = caveira - 1\n",
     "            if true {\n                set caveira = caveira - 1\n",
     "interface.atm", "fluxo"),
    ("menu-depois-da-entrada",
     "O menu recebe a tecla depois do resto da entrada (o jogo ja a usou)",
     "        if G.tecla_para_menu(ev) {\n            emit @(menu) ([tag=\"menu.tecla\", ev=ev])\n        }\n        G.handle_input(ev)\n",
     "        val oferece = G.tecla_para_menu(ev)\n        G.handle_input(ev)\n        if oferece {\n            emit @(menu) ([tag=\"menu.tecla\", ev=ev])\n        }\n",
     "main.atm", "fluxo"),
    ("automapa-depois-do-mundo",
     "O automapa anda depois do mundo no tic (segue a posicao nova do jogador)",
     "                    emit @(automapa) (:automapa.tic)   ;; passo 8d: o automapa\n                    G.tic_comando()                    ;; o comando do jogador\n                                                       ;; (G_BuildTiccmd, fora do\n                                                       ;; P_Ticker no Doom) e a\n                                                       ;; tecla Pause\n                    val parar = G.mundo_parado()       ;; C2: pausa ou menu\n                    if parar != parado {\n                        toggle mundo(!parar)           ;; desligado, nao acorda\n                        set parado = parar             ;; nem com o :mundo.tic\n                    }\n                    emit @(mundo) (:mundo.tic)         ;; passo 8a: o tic do mundo\n",
     "                    G.tic_comando()                    ;; o comando do jogador\n                                                       ;; (G_BuildTiccmd, fora do\n                                                       ;; P_Ticker no Doom) e a\n                                                       ;; tecla Pause\n                    val parar = G.mundo_parado()       ;; C2: pausa ou menu\n                    if parar != parado {\n                        toggle mundo(!parar)           ;; desligado, nao acorda\n                        set parado = parar             ;; nem com o :mundo.tic\n                    }\n                    emit @(mundo) (:mundo.tic)         ;; passo 8a: o tic do mundo\n                    emit @(automapa) (:automapa.tic)\n",
     "main.atm", "semente1"),
    ("automapa-parado",
     "O automapa aberto nao segue o jogador nem aplica zoom",
     "            AM.passo(a, game)\n",
     "",
     "interface.atm", "semente1"),
    ("rosto-sem-furia",
     "O rosto nunca mostra a furia (gatilho preso por 2 s)",
     "                    if furia == 0 {\n",
     "                    if false {\n",
     "barra.atm", "arma"),
    ("rosto-olhar-mais-longo",
     "O olhar parado fica um tic a mais",
     "            set conta = R.STRAIGHTFACECOUNT\n",
     "            set conta = R.STRAIGHTFACECOUNT + 1\n",
     "barra.atm", "arma"),
    ("rosto-esquece-a-vida",
     "O rosto nao guarda a vida do tic anterior (toda dor parece grande)",
     "        set vida_antes = p.health\n",
     "",
     "barra.atm", "fluxo"),
    ("rosto-sem-deus",
     "O rosto ignora o modo deus",
     "        if (prioridade < 5) && S.deus(p) {                       ;; modo deus\n",
     "        if false {\n",
     "barra.atm", "arma"),
    # --- passo 9: a familia de monstros (roteiro "familia": E1M5, -respawn)
    ("tipo-volta-como-zumbi",
     "Depois de atacar ou sentir dor, todo tipo volta a correr como Zombieman (a generalizacao esqueceu um estado)",
     "            (r == :fim) => entrar(mo, game, C.correr@1)",
     "            (r == :fim) => entrar(mo, game, info.S_POSS_RUN1)",
     "monstro.atm", "familia"),
    ("demonio-nao-morde",
     "A sequencia de ataque do Demon termina antes do quadro da mordida",
     "    atacar   = faixa(info.S_SARG_ATK1, info.S_SARG_ATK3),",
     "    atacar   = faixa(info.S_SARG_ATK1, info.S_SARG_ATK2),",
     "monstro.atm", "familia"),
    ("demonio-dor-curta",
     "A dor do Demon tem um quadro so (sem A_Pain)",
     "    dor      = faixa(info.S_SARG_PAIN, info.S_SARG_PAIN2),",
     "    dor      = faixa(info.S_SARG_PAIN, info.S_SARG_PAIN),",
     "monstro.atm", "familia"),
    ("soldado-levanta-morto",
     "A morte do Shotgun Guy termina antes do corpo (ele volta a correr)",
     "    morrer   = faixa(info.S_SPOS_DIE1, info.S_SPOS_DIE5),",
     "    morrer   = faixa(info.S_SPOS_DIE1, info.S_SPOS_DIE4),",
     "monstro.atm", "familia"),
    ("spectre-com-tabela-do-soldado",
     "O Spectre recebe a tabela do Shotgun Guy",
     "set TIPOS@(info.MT_SHADOWS)   = DEMONIO",
     "set TIPOS@(info.MT_SHADOWS)   = SOLDADO",
     "monstro.atm", "familia"),
    # --- C1: correcoes (roteiros "correcoes" e "pisos")
    ("carry-sem-defer",
     "O Jogo nao apaga o carry ao terminar (o jogo novo da intermissao herda as armas)",
     "    defer {\n        set G.game.carry = nil          ;; o carry e do Jogo: nao sobrevive a ele\n    }                                   ;; (nem quando :jogo.novo o aborta)\n",
     "",
     "main.atm", "correcoes"),
    ("esmagar-sem-dano-do-jogo",
     "O esmagamento volta a tirar a vida direto (sem damage_mobj: o jogador nao morre)",
     "          if crush and M.esmagar then\n",
     "          if crush and false then\n",
     "collision.lua", "pisos"),
    # --- C2: o menu e a tecla Pause param o mundo (roteiro "correcoes")
    ("menu-nao-para",
     "O menu aberto nao para o mundo (o comportamento antes do C2)",
     "    return game.paused or (menu.active and (game.leveltime or 0) > 0)\n",
     "    return game.paused\n",
     "game.lua", "correcoes"),
    ("pausa-nao-para",
     "A tecla Pause alterna a pausa, mas o mundo continua",
     "    return game.paused or (menu.active and (game.leveltime or 0) > 0)\n",
     "    return (menu.active and (game.leveltime or 0) > 0)\n",
     "game.lua", "correcoes"),
    ("menu-para-no-primeiro-tic",
     "O menu para o mundo ja no primeiro tic do nivel (no Doom, viewz == 1 deixa rodar)",
     "    return game.paused or (menu.active and (game.leveltime or 0) > 0)\n",
     "    return game.paused or menu.active\n",
     "game.lua", "correcoes"),
    ("pausa-sem-zerar-botoes",
     "O tic da tecla Pause nao zera os botoes (o tiro segurado sai um tic antes)",
     "      game.player.cmd.buttons = 0\n      pausar(not game.paused)\n",
     "      pausar(not game.paused)\n",
     "game.lua", "correcoes"),
    ("menu-usa-pause",
     "O menu aberto engole a tecla Pause",
     "  if key == \"pause\" then\n    -- C2: o M_Responder",
     "  if false then\n    -- C2: o M_Responder",
     "menu.lua", "correcoes"),
    ("pausa-sobrevive-ao-nivel",
     "O Nivel nao desfaz a pausa ao terminar (o idclev na pausa comeca o E1M2 pausado)",
     "    defer {\n        G.pausar(false)                   ;; C2: a pausa e do Nivel: nao\n    }                                     ;; sobrevive a ele (G_InitNew)\n",
     "",
     "main.atm", "correcoes"),
    ("barra-parada-na-pausa",
     "A barra de status para junto com o mundo (no Doom, o ST_Ticker continua)",
     "                    if !r.fim {\n                        emit @(rosto) (:barra.tic)",
     "                    if (!r.fim) && (!parado) {\n                        emit @(rosto) (:barra.tic)",
     "main.atm", "correcoes"),
    # --- C3: a arma com info.STATES e o p_pspr.c (roteiros "arma" e "correcoes")
    ("clarao-antes-da-arma",
     "O clarao anda antes da arma no tic (o clarao ligado no tic nao desconta o primeiro tic)",
     "    par {\n        arma(p, game)                                  ;; ps_weapon\n    } with {\n        clarao(p, game)                                ;; ps_flash, depois da arma\n    }\n",
     "    par {\n        clarao(p, game)\n    } with {\n        arma(p, game)\n    }\n",
     "arma.atm", "arma"),
    ("tiro-volta-ao-comeco",
     "O fim do tiro volta ao primeiro quadro do tiro, em vez da arma pronta",
     "            entrar(p, pos, game, W.pronta@1)           ;; o tiro termina na arma pronta\n",
     "            entrar(p, pos, game, W.atirar@1)\n",
     "arma.atm", "arma"),
    ("salto-vencido-espera",
     "Um salto de fora sem tics (a arma solta na morte) espera um tic a mais",
     "        set venc = vencido(p, pos, r)\n        if r == :fim {\n            entrar(p, pos, game, W.pronta@1)",
     "        set venc = false\n        if r == :fim {\n            entrar(p, pos, game, W.pronta@1)",
     "arma.atm", "arma"),
    ("clarao-nao-apaga",
     "O fim do clarao volta ao primeiro quadro do clarao (nunca apaga)",
     "            entrar(p, pos, game, info.S_LIGHTDONE)     ;; apaga (A_Light0)\n",
     "            entrar(p, pos, game, seq@1)\n",
     "arma.atm", "arma"),
    ("subida-nao-repete",
     "A subida termina depois do primeiro quadro (sem repetir o A_Raise, vai direto para a arma pronta)",
     "            (indice(W.subir, st) > 0)  => sequencia(p, pos, game, W.subir, venc, true)\n",
     "            (indice(W.subir, st) > 0)  => sequencia(p, pos, game, W.subir, venc, false)\n",
     "arma.atm", "arma"),
    ("pronta-nao-repete",
     "A arma pronta para depois do primeiro quadro (o A_WeaponReady so roda uma vez)",
     "            (indice(W.pronta, st) > 0) => sequencia(p, pos, game, W.pronta, venc, true)\n",
     "            (indice(W.pronta, st) > 0) => sequencia(p, pos, game, W.pronta, venc, false)\n",
     "arma.atm", "arma"),
    ("foguete-sem-soltar",
     "Lanca-foguetes e BFG atiram de novo com o gatilho preso (A_WeaponReady)",
     "          or (player.readyweapon ~= WP_MISSILE and player.readyweapon ~= WP_BFG) then\n",
     "          or true then\n",
     "pspr.lua", "arma"),
    ("refire-nao-zera",
     "Soltar o gatilho no fim do tiro nao zera refire (a pistola erra mais)",
     "      player.refire = 0\n      check_ammo(player, game)\n",
     "      check_ammo(player, game)\n",
     "pspr.lua", "arma"),
    ("subida-mais-lenta",
     "A arma sobe 5 por tic, em vez de 6 (RAISESPEED)",
     "    psp.sy = psp.sy - RAISESPEED\n",
     "    psp.sy = psp.sy - 5 * FRACUNIT\n",
     "pspr.lua", "arma"),
    ("sem-balanco",
     "A arma pronta nao balanca com o andar (A_WeaponReady)",
     "    psp.sy = WEAPONTOP + fixed_mul(player.bob or 0, tabela:get_finesine(angle))\n",
     "    psp.sy = WEAPONTOP\n",
     "pspr.lua", "semente1"),
    ("clarao-sem-primeiro-tic",
     "O clarao nao desconta no tic em que acende (P_MovePsprites so na arma)",
     "  if psp.state == 0 or psp.tics == -1 then\n    return false\n  end\n  psp.tics = psp.tics - 1\n",
     "  if psp.state == 0 or psp.tics == -1 or position == PS_FLASH then\n    return false\n  end\n  psp.tics = psp.tics - 1\n",
     "pspr.lua", "arma"),
    ("load-perde-a-arma",
     "Load nao restaura os psprites (a arma volta subindo)",
     '    psp.state = take("psp" .. i .. "_state", psp.state)\n',
     "",
     "saveg.lua", "arma"),
    ("punho-sem-virar",
     "O soco nao vira o jogador para o alvo",
     "      som(game, \"punch\")\n      mo.angle = angulo_para(mo, alvo)\n",
     "      som(game, \"punch\")\n",
     "pspr.lua", "correcoes"),
    ("motosserra-sem-arrancada",
     "A motosserra que acerta nao puxa o jogador para a frente (MF_JUSTATTACKED)",
     "    mo.flags = bor(mo.flags, MF_JUSTATTACKED)\n",
     "",
     "pspr.lua", "correcoes"),
    ("tecla-1-como-antes",
     "A tecla 1 com a motosserra na mao volta ao punho (sem o berserk), como antes do C3",
     "        and not (player.readyweapon == WP_CHAINSAW and (player.powers[PW_STRENGTH] or 0) ~= 0) then\n",
     "        and player.readyweapon ~= WP_CHAINSAW then\n",
     "player.lua", "correcoes"),
    ("sem-municao-ordem-antiga",
     "Sem municao, o plasma nao e a primeira escolha (o BFG sem celula vai para outra arma)",
     "  if own[WP_PLASMA] and am[AM_CELL] > 0 and not shareware then\n",
     "  if false then\n",
     "pspr.lua", "correcoes"),
    ("carry-sem-sx",
     "O nivel seguinte comeca com a arma em sx 0 (a posicao horizontal nao passa de nivel)",
     "    player.psprites[0].sx = prev.psprite_sx or 0\n",
     "    player.psprites[0].sx = 0\n",
     "game.lua", "fluxo"),
    # --- C4: specials do DIFERENCAS (roteiros "correcoes", "pisos",
    # "elevadores", "botoes" e "fluxo")
    ("porta-nao-reabre",
     "A porta que bate em algo fechando fica tentando (antes do C4a)",
     "        until ((dir == -1) && (r == S.RESULT_CRUSHED) && reabre, :esmagou)\n",
     "",
     "setores.atm", "correcoes"),
    ("teto-40-parado",
     "O teto que sobe (linha 40) fica na altura atual (antes do C4b)",
     "        top = highest_ceiling(sec)\n        direction = 1\n",
     "        direction = 1\n",
     "specials.lua", "pisos"),
    ("so-desce-esmaga",
     "O esmagador que so desce (44, 72) esmaga (antes do C4b)",
     "      local crush = ctype == CEIL_CRUSHANDRAISE or ctype == CEIL_SILENTCRUSH\n        or ctype == CEIL_FASTCRUSH\n",
     "      local crush = ctype == CEIL_CRUSHANDRAISE or ctype == CEIL_SILENTCRUSH\n        or ctype == CEIL_FASTCRUSH or ctype == CEIL_LOWERANDCRUSH\n",
     "specials.lua", "pisos"),
    ("teto-sem-desacelerar",
     "O teto que bate em algo descendo nao desacelera",
     "            if desacelera && (dir == -1) && (r == S.RESULT_CRUSHED) {\n",
     "            if false {\n",
     "setores.atm", "pisos"),
    ("teto-parar-sem-toggle",
     "As linhas 57 e 74 marcam o teto parado mas nao desligam a task",
     "      teto.parado = true\n      if teto.task then\n        toggle(teto.task, false)\n      end\n",
     "      teto.parado = true\n",
     "specials.lua", "correcoes"),
    ("teto-sem-reativar",
     "As linhas de esmagador nao reativam os tetos parados",
     "  if ctype == CEIL_FASTCRUSH or ctype == CEIL_SILENTCRUSH or ctype == CEIL_CRUSHANDRAISE then\n    activate_in_stasis_ceiling(self, line)\n  end\n",
     "",
     "specials.lua", "correcoes"),
    ("esmagar-todo-tic",
     "O esmagamento tira vida a cada tic, nao a cada 4 (antes do C4c)",
     "    if (game.leveltime or 0) % 4 == 0 then\n      game.damage_mobj(thing, nil, 10, nil)\n",
     "    if true then\n      game.damage_mobj(thing, nil, 10, nil)\n",
     "game.lua", "pisos"),
    ("esmagar-sem-sangue",
     "O esmagamento nao solta sangue (nem consome P_Random)",
     "      collision.jato_de_sangue(world, thing, game)\n",
     "",
     "game.lua", "pisos"),
    ("corpo-sem-restos",
     "O corpo esmagado nao vira restos (S_GIBS)",
     "            require(\"thinker\").set_mobj_state(thing, require(\"info\").S_GIBS, world, nil)\n",
     "",
     "collision.lua", "pisos"),
    ("elevador-nao-volta",
     "O elevador que bate subindo fica tentando (antes do C4d)",
     "        until ((st == P.UP) && (r == S.RESULT_CRUSHED), :bateu)\n",
     "",
     "setores.atm", "correcoes"),
    ("elevador-parar-sem-toggle",
     "As linhas 54 e 89 marcam o elevador parado mas nao desligam a task",
     "      plat.oldstatus = plat.status\n      plat.status = PLAT_INSTASIS\n      if plat.task then\n        toggle(plat.task, false)\n      end\n",
     "      plat.oldstatus = plat.status\n      plat.status = PLAT_INSTASIS\n",
     "specials.lua", "elevadores"),
    ("elevador-sem-reativar",
     "As linhas de elevador perpetuo nao reativam os parados (antes do C4d)",
     "  activate_in_stasis(self, line.tag)     -- C4d: P_ActivateInStasis\n",
     "",
     "specials.lua", "elevadores"),
    ("load-perde-oldstatus",
     "O load nao restaura o status de antes de parar (a reativacao o perde)",
     "          oldstatus = rec.oldstatus or 0,\n",
     "          oldstatus = 0,\n",
     "saveg.lua", "elevadores"),
    ("piso-nao-troca-special",
     "O donut e o baixar e trocar nao trocam o special (antes do C4e)",
     "            set piso.sector.special = piso.newspecial\n",
     "",
     "setores.atm", "pisos"),
    ("escada-dois-lados",
     "A escada segue linhas pelos dois lados (antes do C4e)",
     "          if has(ln.flags, ML_TWOSIDED) and ln.frontsector == sec and ln.backsector then\n            local tsec = ln.backsector\n",
     "          if has(ln.flags, ML_TWOSIDED) and ln.backsector then\n            local tsec = ln.backsector\n            if ln.frontsector ~= sec then\n              tsec = ln.frontsector\n            end\n",
     "specials.lua", "pisos"),
    ("botao-duplicado",
     "Um segundo botao para a mesma linha (antes do C4f)",
     "        if t.pub.linha == line then\n          return nil\n        end\n",
     "",
     "specials.lua", "botoes"),
    ("save-grava-na-hora",
     "Escolher o slot grava na hora, com a descricao vazia (sem digitar)",
     "    self.save_string_enter = true\n    self.save_slot = choice\n",
     "    self.save_string_enter = true\n    self.save_slot = choice\n    self.save_strings[choice + 1] = \"X\"\n    return M.responder(self, \"return\")\n",
     "menu.lua", "botoes"),
    # --- C5: o save no formato do Doom (roteiros "familia", "luzes" e
    # "correcoes")
    ("load-sem-task-monstro",
     "O load recria o mobj do monstro sem a task Monstro (ele para de pensar)",
     "  collision.set_thing_position(world, mo)\n  criar_task(mo, game)\n  return mo\nend\n\nfunction M.remove_mobj",
     "  collision.set_thing_position(world, mo)\n  return mo\nend\n\nfunction M.remove_mobj",
     "thinker.lua", "familia"),
    ("load-perde-spawnpoint",
     "O load nao restaura o spawnpoint (o pesadelo nao faz o monstro renascer no lugar)",
     "    campos.spawnpoint = { x = sp.x, y = sp.y, angle = sp.angle, type = sp.type, options = sp.options }\n",
     "",
     "saveg.lua", "familia"),
    ("load-luz-sorteia",
     "O load recria a luz que pisca sem a contagem gravada (sorteia de novo)",
     "    return spawn_luz(self, \"Pisca\", sector, rec.maxlight, rec.minlight, rec.count)\n",
     "    return spawn_luz(self, \"Pisca\", sector, rec.maxlight, rec.minlight)\n",
     "specials.lua", "luzes"),
    ("save-grava-luz-morta",
     "O save grava tambem as luzes abortadas no load (que continuam na pool)",
     "      if t.pub and t.pub.kind and not t.pub.dead then\n",
     "      if t.pub and t.pub.kind then\n",
     "saveg.lua", "elevadores"),         # um save depois de um load no mesmo nivel
    ("load-teto-andando",
     "O load recria o teto parado andando (sem desligar a task)",
     "  if teto.parado and teto.task then\n    toggle(teto.task, false)\n  end\n  add_active_ceiling(self, teto)\n",
     "  add_active_ceiling(self, teto)\n",
     "specials.lua", "correcoes"),
    # --- passo 2 (continuacao): fluxo de telas (roteiro "fluxo")
    ("novo-nao-descarta",
     "New Game no meio do jogo e ignorado (o Jogo atual continua)",
     "            await <:jogo.novo || :jogo.carregar>   ;; descarta o jogo atual\n",
     "            await :jogo.carregar\n"),
]


def mkrun(path, mudados):
    """mudados: {arquivo: conteudo mutado}. As pastas do codigo sao
    copiadas com um link por arquivo, e o arquivo mutado troca o seu link
    (o original nao e tocado)."""
    pastas.montar_execucao(ROOT, path, copiar_pastas=True)
    for arquivo, conteudo in mudados.items():
        destino = os.path.join(path, pastas.localizar(ROOT, arquivo))
        os.remove(destino)
        with open(destino, "w") as f:
            f.write(conteudo)


def compare(ref_log, log):
    ref = open(ref_log).read().splitlines()
    got = open(log).read().splitlines() if os.path.exists(log) else []
    first = None
    diff = 0
    for i in range(max(len(ref), len(got))):
        a = ref[i] if i < len(ref) else None
        b = got[i] if i < len(got) else None
        if a != b:
            diff += 1
            if first is None:
                first = i + 1
    return first, diff, len(ref), len(got)


def main():
    so = set(sys.argv[1:])
    mutacoes = [m for m in MUTACOES if not so or m[0] in so]
    usados = sorted({(m[5] if len(m) > 5 else "fluxo") for m in mutacoes})
    for r in usados:
        ref_log = os.path.join(OUT, ROTEIROS[r][1])
        if not os.path.exists(ref_log):
            sys.exit(f"falta {os.path.relpath(ref_log, ROOT)}: rode antes o roteiro {r} "
                     "com tests/test_drivers.sh (ou make test-mutacoes)")
        n = len(open(ref_log).read().splitlines())
        print(f"roteiro {r}: {ROTEIROS[r][0]}  referencia: {n} quadros")
    print()
    print(f"{'mutacao':24} {'resultado':12} {'1o quadro':>9} {'quadros dif.':>12}  descricao")
    survived = 0
    equivalent = 0
    pending = 0
    for m in mutacoes:
        name, desc, old, new = m[:4]
        arquivo = m[4] if len(m) > 4 else "main.atm"
        roteiro = m[5] if len(m) > 5 else "fluxo"
        script, ref_name, game_args = ROTEIROS[roteiro]
        # "old" pode ser uma lista de (arquivo, original, mutado)
        edits = old if isinstance(old, list) else [(arquivo, old, new)]
        mudados = {}
        aplicavel = True
        for arq, o, n in edits:
            src = mudados.get(arq) or open(os.path.join(ROOT, pastas.localizar(ROOT, arq))).read()
            if src.count(o) != 1:
                aplicavel = False
                break
            mudados[arq] = src.replace(o, n)
        if not aplicavel:
            print(f"{name:24} {'NAO APLICADA':12} {'':>9} {'':>12}  trecho nao encontrado")
            survived += 1
            continue
        run = os.path.join(ROOT, "build", "mut", name)
        mkrun(run, mudados)
        log = os.path.join(run, "replay.log")
        env = dict(os.environ, DOOM_REPLAY=os.path.join(OUT, script), DOOM_REPLAY_OUT=log,
                   DOOM_REPLAY_SIDES="1")
        with open(os.path.join(run, "saida.txt"), "w") as out:
            subprocess.run(["atmos", "main.atm", "--", "-nosound", "-nomusic"] + game_args,
                           cwd=run, env=env, stdout=out, stderr=subprocess.STDOUT,
                           timeout=600)
        first, diff, nref, ngot = compare(os.path.join(OUT, ref_name), log)
        # saves sao parte do resultado: compara com os da referencia
        saves_ref = os.path.join(OUT, ref_name.replace("ref_", "saves_").replace(".log", ""))
        saves_dif = []
        if os.path.isdir(saves_ref):
            for nome_dsg in sorted(os.listdir(saves_ref)):
                a_dsg = os.path.join(saves_ref, nome_dsg)
                b_dsg = pastas.save_de(run, nome_dsg)
                if not os.path.exists(b_dsg) or open(a_dsg, "rb").read() != open(b_dsg, "rb").read():
                    saves_dif.append(nome_dsg)
        if first is None and saves_dif:
            result = "detectada"          # so no save
        elif first is None and name in EQUIVALENTES:
            result = "equivalente"
            equivalent += 1
        elif first is None and name in PENDENTES:
            result = "pendente"
            pending += 1
        elif first is None:
            result = "SOBREVIVEU"
            survived += 1
        else:
            result = "detectada"
        extra = "" if ngot == nref else f" ({ngot} quadros)"
        if saves_dif:
            extra += f" [save difere: {', '.join(saves_dif)}]"
        print(f"{name:24} {result:12} {first or '-':>9} {diff:>12}  {desc}{extra}")
        if result == "equivalente":
            print(f"{'':24} {'':12} {'':>9} {'':>12}    -> {EQUIVALENTES[name]}")
        elif result == "pendente":
            print(f"{'':24} {'':12} {'':>9} {'':>12}    -> {PENDENTES[name]}")
        elif name in PENDENTES:
            print(f"{'':24} {'':12} {'':>9} {'':>12}    -> agora detectada: tire de PENDENTES")
    total = len(mutacoes) - equivalent
    print(f"\n{total - survived - pending}/{total} mutacoes nao equivalentes detectadas"
          f" ({equivalent} equivalentes, {pending} pendentes de cobertura, justificadas acima)")
    sys.exit(1 if survived else 0)


if __name__ == "__main__":
    main()
