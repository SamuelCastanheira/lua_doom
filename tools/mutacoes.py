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
    "arma-no-meio-do-jogador":
        "a arma no meio do tic do jogador, como no P_PlayerThink do Doom "
        "(depois da troca pelo teclado, antes dos poderes). O que vem depois "
        "dela nao interage com ela: a forca so cresce e o soco so pergunta se "
        "e diferente de zero; tirar MF_SHADOW nao afeta o tiro; a arma nao le "
        "damagecount, bonuscount, mensagem nem fixedcolormap; e nenhuma dessas "
        "partes consome P_Random. Por isso o passo 4c poe a arma depois de "
        "todas as partes, sem corte (registro do passo 4, secao 4c)",
    "tiro-sem-gatilho-preso":
        "durante o tiro, attackdown ja e verdadeiro: e ligado ao comecar o tiro "
        "(fase pronta) e por do_shot, e so e desligado na saida para a fase "
        "pronta (enter_atk_step, sem o gatilho); o save grava attackdown "
        "verdadeiro no meio do tiro. A linha da task e redundante, como era "
        "no weapon_think (passo 4a)",
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
    "spectre-com-tabela-do-soldado":
        "a task Monstro com uma tabela que nao cobre os estados do mobj cai "
        "no caso estranho, que segue o ponteiro proximo de info.STATES, como "
        "o thinker Lua: o Spectre com a tabela do Shotgun Guy anda pela "
        "tabela quadro a quadro, sem os comportamentos com nome, e faz o "
        "mesmo. O caso estranho, criado para o load por indice, torna "
        "silencioso um erro de cobertura da tabela do tipo (registro do "
        "passo 9)"
}

# Mutantes NAO equivalentes que o roteiro ainda nao cobre. Sobreviver e
# esperado por enquanto (nao falha o teste), mas fica impresso com o motivo e
# com o roteiro que deve passar a detecta-lo. Quando esse roteiro existir,
# tire a mutacao daqui: ela tem de passar a "detectada".
PENDENTES = {
    # Vazio desde o B2: as tres mutacoes que estavam aqui (usar-antes-de-mover,
    # portas-fora-de-movers e a mesma no roteiro fluxo) ganharam o roteiro
    # "ordem" (docs/registro/12-mutacoes-pendentes.md).
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
     "val task Pisca (setor, maxl, minl) {\n    espera(band(rng.p_random(), 64) + 1)\n",
     "val task Pisca (setor, maxl, minl) {\n    rng.p_random()\n",
     "setores.atm", "luzes"),
    ("fogo-intervalo-3",
     "Fogo tremula a cada 3 tics em vez de 4",
     "        espera(4)\n",
     "        espera(3)\n",
     "setores.atm", "luzes"),
    ("strobe-sincronizado-sorteia",
     "Strobe sincronizado sorteia a primeira espera (consome P_Random a mais)",
     "    val primeira = if sincronizado => 1 => (band(rng.p_random(), 7) + 1)\n",
     "    val primeira = band(rng.p_random(), 7) + 1\n",
     "setores.atm", "luzes"),
    ("brilho-nao-volta",
     "Glow inverte a direcao sem desfazer o ultimo passo (passa do minimo)",
     "        set setor.lightlevel = setor.lightlevel + GLOWSPEED\n        loop {                                ;; clareia ate o maximo\n",
     "        loop {                                ;; clareia ate o maximo\n",
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
     "      if btn and btn.timer > 0 then\n",
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
     "val func mover_plat (sp, plat, st, direto) {\n    var espera = !direto\n",
     "val func mover_plat (sp, plat, st, direto) {\n    var espera = false\n",
     "setores.atm", "elevadores"),
    ("parar-ignorado",
     "Elevador em movimento ignora o recado de parar",
     "        until (plat.status != st, :troca)\n",
     "",
     "setores.atm", "elevadores"),
    ("parar-um-tic-depois",
     "Depois do recado de parar, o elevador so passa a esperar no tic seguinte",
     "        set direto = (r == :troca)\n        ifs {\n            (r == :troca) => {}           ;; recado: segue no status novo",
     "        set direto = false\n        ifs {\n            (r == :troca) => {}           ;; recado: segue no status novo",
     "setores.atm", "elevadores"),
    ("parar-com-toggle",
     "Parar com toggle(task, false) alem do recado: o elevador congela sem "
     "descontar o count (o original desconta o count enorme a cada tic)",
     "      th.status = PLAT_WAITING\n      th.count = 2147483647\n",
     "      th.status = PLAT_WAITING\n      th.count = 2147483647\n      toggle(t, false)\n",
     "specials.lua", "elevadores"),
    ("perpetuo-para-no-topo",
     "Elevador perpetuo termina ao chegar em cima (tratado como desce-sobe)",
     "                until ((st != P.DOWN) && (plat.type != P.PERPETUAL))   ;; subiu: acabou\n",
     "                until (st != P.DOWN)\n",
     "setores.atm", "elevadores"),
    ("espera-um-tic-a-menos",
     "Elevador espera um tic a menos embaixo (count = wait - 1)",
     "                set plat.count = plat.wait\n",
     "                set plat.count = plat.wait - 1\n",
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
     "    loop {\n        await :game.specials\n        val r = S.move_plane(sp.world, piso.sector, piso.speed, piso.dest, 0, piso.direction, piso.crush)\n        until (r == S.RESULT_PASTDEST)\n    }\n",
     "    loop {\n        val r = S.move_plane(sp.world, piso.sector, piso.speed, piso.dest, 0, piso.direction, piso.crush)\n        until (r == S.RESULT_PASTDEST)\n        await :game.specials\n    }\n",
     "setores.atm", "pisos"),
    ("piso-nao-troca-textura",
     "Piso que chega ao destino nao troca a textura do chao (donut, baixar e trocar)",
     "    if piso.floorpic {\n        set piso.sector.floorpic = piso.floorpic\n    }\n",
     "",
     "setores.atm", "pisos"),
    ("piso-troca-textura-no-inicio",
     "Piso troca a textura do chao ao nascer, nao ao chegar",
     "val task Piso (sp, piso) {\n    set pub = piso\n",
     "val task Piso (sp, piso) {\n    set pub = piso\n    if piso.floorpic {\n        set piso.sector.floorpic = piso.floorpic\n    }\n",
     "setores.atm", "pisos"),
    ("esmagador-nao-desacelera",
     "Esmagador que vai e volta nao desce devagar depois de esmagar",
     "                set vel = devagar\n",
     "",
     "setores.atm", "pisos"),
    ("esmagador-sobe-devagar",
     "Esmagador nao volta a velocidade normal ao chegar embaixo",
     "        if dir == -1 {                    ;; chegou embaixo: sobe na normal\n            set vel = normal\n        }\n",
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
    ("teto-vai-ate-o-mais-alto",
     "Teto que sobe (linha 40) vai ate o teto vizinho mais alto (como o Doom), "
     "nao para na altura atual (o tick antigo usava topheight)",
     "            (t == C.LOWERTOFLOOR) => teto.dest\n",
     "            (t == C.LOWERTOFLOOR) || (t == C.RAISETOHIGHEST) => teto.dest\n",
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
    ("clarao-depois-da-fase",
     "O clarao conta depois da fase: o clarao ligado no tic perde um tic",
     "    par {\n        clarao(p)\n    } with {\n        loop {\n            val st = p.psprite_state\n            ifs {\n                (st == :up) => subir(p, game)\n                (st == :down) => baixar(p, game)\n                (st == :atk) || (st == :fire) => atirar(p, game)\n                else => pronta(p, game)\n            }\n        }\n    }\n",
     "    par {\n        loop {\n            val st = p.psprite_state\n            ifs {\n                (st == :up) => subir(p, game)\n                (st == :down) => baixar(p, game)\n                (st == :atk) || (st == :fire) => atirar(p, game)\n                else => pronta(p, game)\n            }\n        }\n    } with {\n        clarao(p)\n    }\n",
     "arma.atm", "arma"),
    ("clarao-conta-morto",
     "O clarao continua contando com o jogador morto",
     "        if vivo && (p.flash_tics > 0) {\n",
     "        if p.flash_tics > 0 {\n",
     "arma.atm", "arma"),
    ("troca-ignorada-na-subida",
     "Pedir outra arma durante a subida nao baixa a arma (sobe ate o fim)",
     "            if p.pendingweapon != A.WP_NOCHANGE {\n                A.arma_baixar(p, game)\n            } else {\n                A.arma_subir(p, game)\n            }\n",
     "            A.arma_subir(p, game)\n",
     "arma.atm", "arma"),
    ("tiro-sem-gatilho-preso",
     "Durante o tiro, segurar o gatilho nao marca attackdown",
     "            if c.firing {\n                set p.attackdown = true\n            }\n",
     "",
     "arma.atm", "arma"),
    ("pronta-nao-zera-refire",
     "Soltar o gatilho com a arma pronta nao zera refire (a pistola erra mais)",
     "                        set p.refire = 0\n",
     "",
     "arma.atm", "arma"),
    ("foguete-sem-soltar",
     "Lanca-foguetes e BFG atiram de novo com o gatilho preso",
     "                c.firing && c.can_fire && A.arma_pode_atirar(p) => {\n",
     "                c.firing && c.can_fire => {\n",
     "arma.atm", "arma"),
    ("load-perde-fase-da-arma",
     "Load nao restaura a fase da arma (volta subindo)",
     '  player.psprite_state = take("psprite_state", player.psprite_state)\n',
     '  player.psprite_state = "up"\n',
     "saveg.lua", "arma"),
    # --- passo 4c: o jogador como task (roteiros "arma" e "fluxo")
    ("arma-no-meio-do-jogador",
     "A arma no meio do tic do jogador, como no Doom (antes dos poderes)",
     "        J.escolher_arma(p)                ;; pedido pelo teclado\n        J.contar_poderes(p)               ;; e o efeito de tela\n        J.contar_avisos(p)                ;; claroes e mensagem\n        emit :jogador.arma\n",
     "        J.escolher_arma(p)                ;; pedido pelo teclado\n        emit :jogador.arma\n        J.contar_poderes(p)               ;; e o efeito de tela\n        J.contar_avisos(p)                ;; claroes e mensagem\n",
     "jogador.atm", "arma"),
    ("morto-perde-o-tic-da-morte",
     "No tic em que percebe a morte, o Jogador espera o proximo tic para agir",
     "    loop {                                ;; morto (o tic corrente ja chegou)\n        J.cair(",
     "    loop {                                ;; morto (o tic corrente ja chegou)\n        await :game.jogador\n        J.cair(",
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
     "monstro.atm", "monstro"),
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
    ("estranho-congela",
     "Zumbi com o estado de outro tipo (load por indice) para de pensar",
     "        T.seguir_tabela(mo, game.world, game) => :aplicado\n",
     "        true => :fora\n",
     "monstro.atm", "arma"),
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
     "          if crush and M.dano_esmagar then\n",
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
    # --- passo 2 (continuacao): fluxo de telas (roteiro "fluxo")
    ("novo-nao-descarta",
     "New Game no meio do jogo e ignorado (o Jogo atual continua)",
     "            await <:jogo.novo || :jogo.carregar>   ;; descarta o jogo atual\n",
     "            await :jogo.carregar\n"),
]


def mkrun(path, mudados):
    """mudados: {arquivo: conteudo mutado}."""
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    for name in os.listdir(ROOT):
        if name.endswith((".lua", ".so", ".dll", ".atm", ".wad")) or name == "atmos":
            os.symlink(os.path.join(ROOT, name), os.path.join(path, name))
    for arquivo, conteudo in mudados.items():
        os.remove(os.path.join(path, arquivo))
        with open(os.path.join(path, arquivo), "w") as f:
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
            src = mudados.get(arq) or open(os.path.join(ROOT, arq)).read()
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
                b_dsg = os.path.join(run, nome_dsg)
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
