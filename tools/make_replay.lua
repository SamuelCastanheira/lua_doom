-- Gera um roteiro de entrada para o modo replay (DOOM_REPLAY).
--
--   lua5.4 tools/make_replay.lua <saida> [quadros] [semente] [exits|fluxo]
--
-- O roteiro passa pelo menu, inicia um jogo novo, anda, atira, usa portas,
-- abre o automapa, muda o tamanho da tela, usa cheats (iddqd, idkfa e idclev,
-- que troca de nivel) e abre/fecha o menu no meio do jogo. A sequencia e
-- pseudoaleatoria mas fixa para uma semente: os dois drivers recebem
-- exatamente as mesmas teclas nos mesmos quadros.
local out_path = assert(arg[1], "uso: make_replay.lua <saida> [quadros] [semente]")
local frames = tonumber(arg[2] or "4000")
local seed = tonumber(arg[3] or "1")
-- "exits": tambem termina niveis (intermissao, finale do E1M8, volta ao titulo)
local exits = arg[4] == "exits"
-- "fluxo": roteiro fixo que passa por todas as transicoes de tela (passo 2)
local fluxo = arg[4] == "fluxo"
-- "luzes": roteiro do passo 3a, rodado com "-warp 4 1". Jogador quase parado
-- (iddqd para nao morrer), olhando em volta: E4M1 (fogo, flash) e, depois de
-- idclev12, E1M2 (glow, flash, strobes rapidos, lentos e sincronizados). Os
-- monstros continuam consumindo P_Random entre as luzes, o que testa a ordem
-- dentro do tic. "quadros" e o tempo em cada mapa.
local luzes = arg[4] == "luzes"
-- "botoes": roteiro do passo 3e, rodado com "-warp 1 1". Usa o comando de
-- teste "use <linha>" (indice do WAD) em switches repetiveis: E1M1 linha 136
-- (porta, tipo 63) e, depois de idclev14, E1M4 linhas 394 e 694
-- (elevadores, tipo 62). Usa de novo com o botao ativo (dois botoes na mesma
-- linha), salva com um botao no meio do timer e carrega esse save (o botao
-- volta com o timer gravado). "quadros" e ignorado.
local botoes = arg[4] == "botoes"
-- "portas": roteiro do passo 3b, rodado com "-warp 1 1". Usa os comandos de
-- teste "use <linha>" e "cross <linha>":
--   E1M1 linha 148 (porta comum): usar de novo abrindo, fechando, esperando
--   e duas vezes no mesmo quadro (o "recado" da porta); save e load em cada
--   fase, em slots diferentes (5: abrindo, 4: esperando, 3: fechando);
--   E1M6 linha 602 (cruzar: fecha e reabre depois de 30 s);
--   E1M2 linhas 497 (abre e fica) e 527 (porta vermelha, com idkfa).
-- "quadros" e ignorado.
local portas = arg[4] == "portas"
-- "elevadores": roteiro do passo 3c, rodado com "-warp 1 3". E1M3: linha 178
-- (desce, espera, sobe; repetivel), com save e load em cada fase (slot 5
-- descendo, 4 esperando, 3 subindo), e linha 360 (sobe e troca a textura).
-- E2M3: linha 114 (elevador perpetuo, cruzar), linha 324 (parar, cruzar),
-- save e load do elevador parado (slot 2) e a linha 114 de novo (nao
-- reativa). "quadros" e ignorado.
local elevadores = arg[4] == "elevadores"
-- "pisos": roteiro do passo 3d, rodado com "-warp 2 2". Usa tambem o comando
-- de teste "goto x y" (poe o jogador num ponto do mapa), para ficar embaixo
-- de um esmagador e ser ferido (a barra de status le a vida no mesmo tic).
--   E2M2: linhas 698 (piso desce, tipo 23), 1038 (19), 713 (sobe 24, 59),
--   638 (escada, 8) e 220 (donut, 9); save e load com eles andando (slot 5);
--   1495 (sobe ate a textura, 30); 728 (esmagador que vai e volta, 73), com
--   o jogador embaixo ate a vida chegar a 0 (desce devagar depois de esmagar);
--   E2M4: 1113 (esmagador rapido, 77) e 65 (escada, 7);
--   E2M1: 243 (baixa e troca a textura do chao, 37);
--   E3M5: 1048 (sobe o teto e baixa o piso, 40) e 1276 (desce o teto e
--   esmaga, 44), com o jogador embaixo por alguns tics.
-- "quadros" e ignorado.
local pisos = arg[4] == "pisos"
-- "arma": roteiro do passo 4a, rodado com "-warp 1 1". Pistola atirando ate
-- acabar a municao (troca sozinha para o punho); depois iddqd e idkfa e cada
-- arma atirando com o gatilho preso (refire); troca de arma no meio do tiro
-- e no meio da subida; a trava do lanca-foguetes (trocar para ele com o
-- gatilho preso nao atira ate soltar); save no meio do tiro do BFG (slot 5)
-- e load; motosserra
-- (balanco com som) e punho; o jogador morre atirando e renasce.
-- "quadros" e ignorado.
local arma = arg[4] == "arma"
-- "monstro": roteiro do passo 5, rodado com "-warp 1 2 -respawn". O E1M2 tem
-- varios Zombieman perto da entrada. iddqd e idkfa; escopeta atirando com o
-- jogador andando (acorda os zumbis: procuram, correm, atiram, sentem dor e
-- morrem); save e load no meio da briga (slot 5); lanca-foguetes (o zumbi
-- despedacado: comportamento "explodir"); espera para os corpos voltarem
-- (-respawn: pesadelo, 12 s). "quadros" e ignorado.
local monstro = arg[4] == "monstro"
-- "familia": roteiro do passo 9, rodado com "-warp 1 5 -respawn". O E1M5 tem
-- os quatro tipos com a task Monstro (Zombieman, Shotgun Guy, Demon,
-- Spectre). iddqd e idkfa; o jogador vai (goto) a sala do Demon com o
-- Shotgun Guy e os zumbis e briga com o lanca-foguetes (despedacados) e
-- com a escopeta (o Demon morde, o Shotgun Guy atira); vai aos Spectres; save
-- e load no meio da briga (slot 5), depois das mortes: o load aplica os
-- registros por indice, e os monstros recebem estados de outros tipos
-- (caso "estranho" da task); espera os corpos voltarem (-respawn).
-- "quadros" e ignorado.
local familia = arg[4] == "familia"
-- "ordem": roteiro do B2 (as mutacoes pendentes), rodado com "-warp 1 3".
-- Dois cenarios em que a ordem dentro do tic decide o resultado:
--  1. "use" no tic em que o movimento poe a linha ao alcance: o jogador e
--     posto (goto) a D unidades da porta da linha 995 (D1, bem em frente ao
--     inicio, olhando para o norte), anda e aperta "use" dois quadros depois.
--     D de 72 a 64: o primeiro D em que a porta abre e o do tic em que o
--     movimento chega ao alcance.
--  2. porta e elevador vizinhos andando no mesmo tic, com o jogador na
--     fronteira: a linha 231 (W1) abre a porta-alcapao do setor 167, a linha
--     116 (WR) baixa o elevador do setor 165, e o jogador e posto na porta,
--     com o corpo sobre o elevador, enquanto os dois andam. change_sector so
--     reajusta quem tem o centro no setor que andou: quem anda primeiro
--     decide a altura que o jogador ve.
-- "quadros" e ignorado.
local ordem = arg[4] == "ordem"
-- "correcoes": roteiro da fase de correcoes (C), rodado com "-warp 1 1".
-- C1: idkfa (todas as armas), saida e New Game na intermissao; no E1M1 do
-- jogo novo, tenta trocar para a escopeta e atira (antes da correcao, o
-- jogo novo comecava com as armas do anterior: o carry vazava).
-- "quadros" e ignorado.
local correcoes = arg[4] == "correcoes"
-- "telas": roteiro do passo 7, rodado com "-warp 1 1". E1M1: visita os 3
-- segredos (goto) e acelera no meio da contagem dos segredos; E1M2: a
-- contagem vai ate o fim, acelera na espera e o mapa seguinte passa pelo
-- tempo; E1M8: sai e, no finale, segura "use" na passagem do texto para a
-- arte.
-- "quadros" e ignorado.
local telas = arg[4] == "telas"

local function rand(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n
end

local lines = {}
local f = 1
local function at(frame, key, dir)
  lines[#lines + 1] = string.format("%d %s %s", frame, key, dir)
end
local function tap(key)
  at(f, key, "down")
  at(f + 1, key, "up")
  f = f + 3
end
local function type_text(text)
  for i = 1, #text do
    tap(text:sub(i, i))
  end
end
local function wait(n)
  f = f + n
end

local MOVES = { "up", "up", "up", "down", "left", "right", "comma", "period" }
local function play(n)
  local stop = f + n
  while f < stop do
    local key = MOVES[rand(#MOVES) + 1]
    local hold = 3 + rand(20)
    at(f, key, "down")
    if rand(3) == 0 then
      at(f + rand(hold), "ctrl", "down")
      at(f + hold, "ctrl", "up")
    end
    at(f + hold, key, "up")
    f = f + hold + 1 + rand(5)
  end
end
local function cmd(text)
  lines[#lines + 1] = string.format("%d %s", f, text)
  f = f + 1
end
local function keys(list)
  for _, k in ipairs(list) do
    tap(k)
  end
end

-- Termina o nivel e passa pela intermissao (o mesmo padrao dos roteiros
-- "exits": a contagem precisa de tempo e de alguns "use").
local function exit_level(kind)
  cmd(kind and ("exit " .. kind) or "exit")
  wait(120)
  for _ = 1, 4 do
    tap("space")
    wait(60)
  end
  wait(60)
end

if elevadores then
  local function use(n)
    lines[#lines + 1] = string.format("%d use %d", f, n)
    f = f + 1
  end
  local function cross(n)
    lines[#lines + 1] = string.format("%d cross %d", f, n)
    f = f + 1
  end
  local function down(n) for _ = 1, n do tap("down") end end
  local function up(n) for _ = 1, n do tap("up") end end
  local E = 178
  wait(40)
  type_text("iddqd")
  wait(20)
  -- Save A (descendo), slot 5: main 0 -> 3 Save -> slot 0 -> 5
  keys({ "escape" }); down(3); keys({ "return" }); wait(10); down(5)
  use(E); wait(8); keys({ "return" })
  wait(10)
  -- Load A: main 3 -> 2 Load -> slot 0 -> 5
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(180)                                            -- chega embaixo; espera
  -- Save B (esperando), slot 4: main 2 -> 3 Save -> slot 5 -> 4
  keys({ "escape" }); down(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(10)
  -- Load B: main 3 -> 2 Load -> slot 5 -> 4
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(130)                                            -- termina a espera; sobe
  -- Save C (subindo), slot 3: main 2 -> 3 Save -> slot 4 -> 3
  keys({ "escape" }); down(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(10)
  -- Load C: main 3 -> 2 Load -> slot 4 -> 3
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(300)
  use(360); wait(300)                                  -- sobe e troca a textura
  -- E2M3: perpetuo, parar, save e load do elevador parado
  type_text("idclev23"); wait(40); type_text("iddqd"); wait(20)
  -- 330 tics: os elevadores estao andando quando a linha de parar e cruzada
  -- (com 400 estavam todos esperando, e o recado nao trocava de fase: as
  -- mutacoes parar-ignorado e parar-um-tic-depois sobreviviam)
  cross(114); wait(330)                                -- perpetuo
  cross(324); wait(60)                                 -- parar
  -- Save D (parado), slot 2: main 2 -> 3 Save -> slot 3 -> 2
  keys({ "escape" }); down(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(30)
  -- Load D: main 3 -> 2 Load -> slot 3 -> 2
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(100)
  cross(114); wait(200)                                -- nao reativa
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if telas then
  local function hold(key, n)
    at(f, key, "down")
    at(f + n, key, "up")
    f = f + n + 1
  end
  local function goto_xy(x, y)
    lines[#lines + 1] = string.format("%d goto %d %d", f, x, y)
    f = f + 1
  end
  wait(40)
  -- E1M1: os 3 segredos (goto em cada setor secreto), para a contagem de
  -- segredos durar 50 tics (100%, de 2 em 2); acelera no meio dela
  goto_xy(2928, -3840); wait(10)
  goto_xy(3264, -3856); wait(10)
  goto_xy(3552, -3872); wait(10)
  goto_xy(1056, -3616); wait(20)
  cmd("exit")
  wait(170)                                            -- no meio dos segredos
  hold("space", 3)
  wait(60)
  hold("space", 3)                                     -- sai da espera
  wait(250)
  -- E1M2: a contagem vai ate o fim; acelera na espera; o mapa seguinte passa
  -- pelo tempo (4 s)
  play(300)
  cmd("exit")
  wait(600)
  hold("space", 3)
  wait(300)
  -- E1M8 e o finale: segura "use" na passagem do texto para a arte (pular
  -- so vale depois de 10 tics de arte)
  type_text("idclev18"); wait(60)
  cmd("exit")
  wait(150)
  hold("space", 3); wait(60); hold("space", 3); wait(300)
  wait(1000)
  hold("space", 1200)
  wait(100)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if correcoes then
  local function hold(key, n)
    at(f, key, "down")
    at(f + n, key, "up")
    f = f + n + 1
  end
  wait(40)
  type_text("idkfa"); wait(20)
  cmd("exit"); wait(150)                               -- intermissao do E1M1
  -- New Game na intermissao: main (item 0) -> episodio 1 -> skill 2
  keys({ "escape", "return", "return", "return" })     -- jogo.novo E1M1
  wait(60)
  hold("3", 3); wait(40)                               -- escopeta (se tiver)
  hold("ctrl", 30); wait(40)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if ordem then
  local function goto_xy(x, y)
    lines[#lines + 1] = string.format("%d goto %d %d", f, x, y)
    f = f + 1
  end
  wait(40)
  type_text("iddqd"); wait(20)
  -- 1. use no alcance: a linha 995 (D1, em y = -3200, de x -1568 a -1440),
  -- a face sul da porta. "use" dois quadros depois de "andar": o terceiro
  -- tic de movimento (ou o segundo/quarto, se o relogio do replay der 0 ou
  -- 2 tics num quadro); a primeira tentativa em que a porta abre e a do
  -- tic em que o movimento poe a linha ao alcance
  for _, d in ipairs({ 72, 71, 70, 69, 68, 67, 66, 65, 64 }) do
    goto_xy(-1504, -3200 - d); wait(10)
    at(f, "up", "down"); at(f + 2, "space", "down")
    at(f + 5, "space", "up"); at(f + 6, "up", "up")
    wait(40)
  end
  wait(100)
  -- 2. porta (setor 167) e elevador (setor 165) vizinhos. A porta e criada
  -- antes do elevador (na pool movers, anda antes dele) e sobe 2 por tic
  -- (128 -> 236); o elevador desce 1 por tic (176 -> 128). O jogador entra
  -- quando cabe entre o chao do elevador (o mais alto dos dois) e o teto da
  -- porta; enquanto os dois andam, o chao que ele ve e o do elevador, lido
  -- quando a porta anda: antes ou depois do elevador andar no mesmo tic.
  cmd("cross 231")                               -- a porta abre (128 -> 236)
  cmd("cross 116"); wait(37)                     -- o elevador desce (176 -> 128)
  goto_xy(-2707, -1317)                          -- centro na porta, corpo no elevador
  wait(120)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if familia then
  local function hold(key, n)
    at(f, key, "down")
    at(f + n, key, "up")
    f = f + n + 1
  end
  local function goto_xy(x, y)
    lines[#lines + 1] = string.format("%d goto %d %d", f, x, y)
    f = f + 1
  end
  local function down(n) for _ = 1, n do tap("down") end end
  local function up(n) for _ = 1, n do tap("up") end end
  wait(40)
  type_text("iddqd"); wait(10); type_text("idkfa"); wait(20)
  hold("5", 3); wait(40)                               -- lanca-foguetes
  goto_xy(432, 784); wait(20)                          -- sala do Demon (576, 832)
  play(700)
  hold("3", 3); wait(40)                               -- escopeta
  play(400)
  goto_xy(144, 1056); wait(20)                         -- Spectres (288, 1104) e (0, 1376)
  play(600)
  -- Save no meio da briga, slot 5: main 0 -> 3 Save -> slot 0 -> 5
  keys({ "escape" }); down(3); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(10)
  -- Load: main 3 -> 2 Load -> slot 0 -> 5
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(20)
  play(300)
  wait(500)                                            -- os corpos voltam (-respawn)
  play(300)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if monstro then
  local function hold(key, n)
    at(f, key, "down")
    at(f + n, key, "up")
    f = f + n + 1
  end
  local function down(n) for _ = 1, n do tap("down") end end
  local function up(n) for _ = 1, n do tap("up") end end
  wait(40)
  type_text("iddqd"); wait(10); type_text("idkfa"); wait(20)
  hold("3", 3); wait(40)                               -- escopeta
  play(700)                                            -- anda e atira
  -- Save no meio da briga, slot 5: main 0 -> 3 Save -> slot 0 -> 5
  keys({ "escape" }); down(3); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(10)
  -- Load: main 3 -> 2 Load -> slot 0 -> 5
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(20)
  play(400)
  hold("5", 3); wait(40)                               -- lanca-foguetes
  play(500)
  wait(500)                                            -- os corpos voltam (-respawn)
  play(300)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if arma then
  local function hold(key, n)
    at(f, key, "down")
    at(f + n, key, "up")
    f = f + n + 1
  end
  local function down(n) for _ = 1, n do tap("down") end end
  local function up(n) for _ = 1, n do tap("up") end end
  -- tecla de arma presa por 3 quadros: com os tics aos pares (relogio do
  -- replay), um toque de um quadro pode ser solto antes de algum tic o ver
  local function arma_n(k) hold(k, 3) end
  wait(40)
  hold("ctrl", 1000)                                   -- pistola ate acabar
  wait(40)
  type_text("iddqd"); wait(10); type_text("idkfa"); wait(20)
  for _, k in ipairs({ "2", "3", "4" }) do             -- pistola, escopeta, metralhadora
    arma_n(k); wait(40); hold("ctrl", 70); wait(30)
  end
  -- troca no meio do tiro: a escopeta termina a sequencia e so entao baixa
  arma_n("3"); wait(40); at(f, "ctrl", "down"); wait(10); arma_n("4"); wait(60)
  at(f, "ctrl", "up"); wait(40)
  -- trava do lanca-foguetes: troca para ele atirando com a metralhadora; com
  -- o gatilho ainda preso desde a arma anterior, ele nao atira ate soltar
  at(f, "ctrl", "down"); wait(10); arma_n("5"); wait(70)
  at(f, "ctrl", "up"); wait(10); hold("ctrl", 10); wait(40)
  -- troca no meio da subida (a pistola baixa em 16 tics e comeca a subir)
  arma_n("2"); wait(22); arma_n("5"); wait(60)
  -- lanca-foguetes com o gatilho preso: atira em sequencia (refire)
  hold("ctrl", 80); wait(40)
  arma_n("6"); wait(40); hold("ctrl", 60); wait(40)       -- plasma
  arma_n("7"); wait(40)                                   -- BFG
  -- Save no meio do tiro do BFG (60 tics), slot 5: main 0 -> 3 Save -> slot 0 -> 5
  hold("ctrl", 3)
  keys({ "escape" }); down(3); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(10)
  -- Load: main 3 -> 2 Load -> slot 0 -> 5
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(80)
  arma_n("1"); wait(60); hold("ctrl", 40); wait(20)       -- motosserra
  arma_n("1"); wait(40); hold("ctrl", 40); wait(20)       -- punho
  -- morre atirando: a arma baixa e fica embaixo; renasce com "use"
  arma_n("2"); wait(40); at(f, "ctrl", "down"); wait(10); cmd("die"); wait(60)
  at(f, "ctrl", "up"); wait(10); hold("space", 3); wait(80)
  hold("ctrl", 40); wait(40)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if pisos then
  local function use(n)
    lines[#lines + 1] = string.format("%d use %d", f, n)
    f = f + 1
  end
  local function cross(n)
    lines[#lines + 1] = string.format("%d cross %d", f, n)
    f = f + 1
  end
  local function goto_xy(x, y)
    lines[#lines + 1] = string.format("%d goto %d %d", f, x, y)
    f = f + 1
  end
  local function down(n) for _ = 1, n do tap("down") end end
  local function up(n) for _ = 1, n do tap("up") end end
  wait(40)
  type_text("iddqd")
  wait(20)
  -- E2M2: pisos, escada e donut andando juntos
  use(698); cross(1038); cross(713); cross(638); use(220)
  wait(30)
  -- Save A (pisos andando), slot 5: main 0 -> 3 Save -> slot 0 -> 5
  keys({ "escape" }); down(3); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(10)
  -- Load A: main 3 -> 2 Load -> slot 0 -> 5
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(300)
  cross(1495); wait(200)                               -- sobe ate a textura
  -- esmagador (73): o teto desce 1 unidade por tic e encosta no jogador
  -- (56 de altura) depois de 40 tics; o jogador, sem o modo deus (o
  -- segundo iddqd o desliga), fica embaixo e morre (C1: o dano passa por
  -- damage_mobj, com cara de dor e morte; antes da correcao ele ficava de
  -- pe com 0 de vida). O idclev do E2M4 comeca o nivel seguinte. A barra de
  -- status reage ao esmagamento, e e isso que detecta a mutacao
  -- specials-no-fim-do-tic. Tem de ser aqui: mais adiante no roteiro os tics
  -- vem aos pares por quadro (arredondamento de 1000/35 no relogio do
  -- replay), toda entrada cai no inicio de um par, e um efeito de um tic no
  -- E3M5 caia sempre no primeiro tic do par, que nao e desenhado
  type_text("iddqd"); wait(10)                         -- desliga o modo deus
  cross(728); goto_xy(672, -352)
  wait(700)                                            -- devagar, sobe, desce
  -- E2M4: esmagador rapido e escada
  type_text("idclev24"); wait(40); type_text("iddqd"); wait(20)
  cross(1113); use(65); wait(300)
  -- E2M1: baixa e troca a textura do chao
  type_text("idclev21"); wait(40); type_text("iddqd"); wait(20)
  cross(243); wait(200)
  -- E3M5: teto sobe e piso desce (40); teto desce e esmaga (44), com o
  -- jogador embaixo por alguns tics (esmagador que nao volta: nao desacelera)
  type_text("idclev35"); wait(40); type_text("iddqd"); wait(20)
  cross(1048); cross(1276); goto_xy(1504, 288); wait(65); goto_xy(-224, -1872)
  wait(300)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if portas then
  local function use(n)
    lines[#lines + 1] = string.format("%d use %d", f, n)
    f = f + 1
  end
  local function cross(n)
    lines[#lines + 1] = string.format("%d cross %d", f, n)
    f = f + 1
  end
  local function down(n) for _ = 1, n do tap("down") end end
  local function up(n) for _ = 1, n do tap("up") end end
  local P = 148
  wait(40)
  type_text("iddqd")
  wait(20)
  -- o recado: usar de novo em cada fase
  use(P); wait(10)                                     -- abrindo
  use(P); wait(6)                                      -- abrindo -> fechando
  use(P); wait(100)                                    -- fechando -> abrindo; espera no topo
  use(P); wait(4)                                      -- esperando -> fechando
  lines[#lines + 1] = string.format("%d use %d", f, P) -- dois "use" no mesmo
  use(P); wait(120)                                    -- quadro: segue fechando
  -- Save A (abrindo), slot 5: main 0 -> 3 Save -> slot 0 -> 5
  keys({ "escape" }); down(3); keys({ "return" }); wait(10); down(5)
  use(P); wait(8); keys({ "return" })
  wait(10)
  -- Load A: main 3 -> 2 Load -> slot 0 -> 5
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); down(5); keys({ "return" })
  wait(120)                                            -- termina de abrir; espera
  -- Save B (esperando), slot 4: main 2 -> 3 Save -> slot 5 -> 4
  keys({ "escape" }); down(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(20)
  -- Load B: main 3 -> 2 Load -> slot 5 -> 4
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(300)                                            -- espera o resto e fecha
  -- Save C (fechando), slot 3: main 2 -> 3 Save -> slot 4 -> 3
  use(P); wait(90)                                     -- abre e espera no topo
  keys({ "escape" }); down(1); keys({ "return" }); wait(10); up(1)
  use(P); wait(5); keys({ "return" })                  -- esperando -> fechando
  wait(10)
  -- Load C: main 3 -> 2 Load -> slot 4 -> 3
  keys({ "escape" }); up(1); keys({ "return" }); wait(10); up(1); keys({ "return" })
  wait(150)
  -- porta de 30 s: E1M6, linha 602 (cruzar)
  type_text("idclev16"); wait(40); type_text("iddqd"); wait(20)
  cross(602); wait(1200)                               -- fecha, 30 s, reabre
  -- E1M2: porta que abre e fica (497) e porta vermelha (527)
  type_text("idclev12"); wait(40); type_text("idkfa"); wait(20)
  use(497); wait(20); use(527); wait(300)
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if botoes then
  local function use(n)
    lines[#lines + 1] = string.format("%d use %d", f, n)
    f = f + 1
  end
  wait(40)
  type_text("iddqd")
  wait(20)
  use(136); wait(60)                                   -- botao: volta em 35 tics
  use(136); wait(10); use(136); wait(80)               -- 2o uso com o botao ativo
  -- Save com um botao ativo: main (item 0) -> 3 Save Game -> slot 5; o
  -- "use" acontece com o menu ja no slot, logo antes de gravar.
  keys({ "escape", "down", "down", "down", "return" })
  wait(10)
  keys({ "down", "down", "down", "down", "down" })
  use(136); wait(5)
  keys({ "return" })                                   -- grava (botao no meio)
  wait(100)
  -- Load: main (item 3) -> 2 Load Game -> slot 0 -> 5
  keys({ "escape", "up", "return" })
  wait(10)
  keys({ "down", "down", "down", "down", "down", "return" }) -- jogo.carregar
  wait(100)
  type_text("idclev14")                                -- nivel.trocar -> E1M4
  wait(40)
  type_text("iddqd")
  wait(20)
  use(394); wait(15); use(694); wait(200)              -- elevadores
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if luzes then
  local function olha_em_volta(n)
    local stop = f + n
    while f < stop do
      wait(150)
      at(f, "left", "down")
      at(f + 25, "left", "up")
      f = f + 26
    end
  end
  wait(40)
  type_text("iddqd")
  olha_em_volta(frames)                                -- E4M1
  type_text("idclev12")                                -- nivel.trocar -> E1M2
  wait(40)
  type_text("iddqd")
  olha_em_volta(frames)                                -- E1M2
  lines[#lines + 1] = string.format("%d quit", f + 20)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 20))
  return
end

if fluxo then
  -- Cada bloco e uma transicao. O menu lembra o ultimo item de cada
  -- submenu (last_on): as setas dependem do caminho feito antes, por isso
  -- os comentarios dizem a posicao esperada. tests/test_drivers.sh confere
  -- se cada transicao aconteceu (cobertura).
  wait(40)
  keys({ "escape", "return", "return", "return" })   -- titulo: jogo.novo E1M1
  wait(40); play(150)
  exit_level(); play(120)                              -- intermissao -> E1M2
  exit_level("secret"); play(120)                      -- saida secreta -> E1M9
  exit_level(); play(120)                              -- E1M9 -> volta ao E1M4
  -- Save: main (item 0) -> 3 Save Game -> slot 0 -> 5
  keys({ "escape", "down", "down", "down", "return" })
  wait(10)
  keys({ "down", "down", "down", "down", "down", "return" })
  wait(40); play(150)
  cmd("die"); wait(80); keys({ "space" })              -- morte -> renasce E1M4
  wait(40); play(100)
  -- Load no meio do jogo: main (item 3) -> 2 Load Game -> slot 0 -> 5
  -- (o menu de load guarda a propria posicao, separada da do save)
  keys({ "escape", "up", "return" })
  wait(10)
  keys({ "down", "down", "down", "down", "down", "return" }) -- jogo.carregar
  wait(40); play(100)
  -- New Game no meio do jogo: main (item 2) -> 0 -> episodio 1 -> skill 2
  keys({ "escape", "up", "up", "return" })
  wait(10)
  keys({ "down", "return", "return" })                 -- jogo.novo E2M1
  wait(40); play(100)
  type_text("idclev28")                                -- nivel.trocar -> E2M8
  wait(60); play(80)
  cmd("exit")                                          -- E2M8: finale (fim do episodio 2)
  for _ = 1, 12 do
    wait(60)
    tap("space")
  end
  wait(300)                                            -- finale -> titulo
  -- Titulo: main (item 0) -> episodio 1 (E2) -> skill 2: jogo.novo
  keys({ "escape", "return", "return", "return" })
  wait(40); play(100)
  -- End Game: main (item 0) -> 1 Options -> 0 End Game -> confirma
  keys({ "escape", "down", "return", "return" })
  wait(10)
  keys({ "y" })                                        -- jogo.fim
  wait(60)
  -- Titulo: main (item 1) -> 2 Load Game -> slot 5 (last_on)
  keys({ "escape", "down", "return" })
  wait(10)
  keys({ "return" })                                   -- jogo.carregar no titulo
  wait(40); play(100)
  -- Quit: main (item 2) -> 5 Quit Game -> confirma
  keys({ "escape", "down", "down", "down", "return" })
  wait(10)
  keys({ "y" })                                        -- jogo.sair
  wait(20)
  lines[#lines + 1] = string.format("%d quit", f + 200)
  local fh = assert(io.open(out_path, "w"))
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  print(string.format("%s: %d eventos, ate o quadro %d", out_path, #lines, f + 200))
  return
end

-- Titulo -> menu -> novo jogo -> episodio 1 -> dificuldade padrao.
wait(40)
tap("escape")
wait(10)
tap("return")
wait(10)
tap("return")
wait(10)
tap("return")
wait(60)
type_text("iddqd")
type_text("idkfa")

local next_cheat = f + 900
-- com exits, o primeiro cheat vai ao E1M8 e a primeira saida cai no finale
local levels = exits and { "18", "12", "15", "21", "31" } or { "12", "18", "15", "21", "31" }
local level_i = 1
while f < frames - 100 do
  local roll = rand(100)
  if roll < 55 then
    local key = MOVES[rand(#MOVES) + 1]
    local hold = 5 + rand(40)
    at(f, key, "down")
    if rand(3) == 0 then
      at(f + rand(hold), "ctrl", "down")
      at(f + hold, "ctrl", "up")
    end
    at(f + hold, key, "up")
    f = f + hold + 1
  elseif roll < 65 then
    tap("space")
  elseif roll < 70 then
    tap(tostring(1 + rand(7)))
  elseif roll < 74 then
    tap("tab")
    wait(20 + rand(30))
    tap("tab")
  elseif roll < 77 then
    tap(rand(2) == 0 and "minus" or "equals")
  elseif roll < 80 then
    tap("escape")
    wait(5 + rand(20))
    tap("down")
    wait(5)
    tap("escape")
  else
    wait(1 + rand(15))
  end
  if f >= next_cheat then
    if exits and level_i % 2 == 0 then
      -- termina o nivel: intermissao (Enter acelera a contagem) e proximo mapa
      lines[#lines + 1] = string.format("%d exit%s", f, rand(4) == 0 and " secret" or "")
      wait(120)
      for _ = 1, 4 do
        tap("space")
        wait(60)
      end
    else
      type_text("idclev" .. levels[level_i])
    end
    level_i = level_i % #levels + 1
    next_cheat = f + 700 + rand(400)
    wait(40)
  end
end
lines[#lines + 1] = string.format("%d quit", frames)

local fh = assert(io.open(out_path, "w"))
fh:write(table.concat(lines, "\n"), "\n")
fh:close()
print(string.format("%s: %d eventos, %d quadros", out_path, #lines, frames))
