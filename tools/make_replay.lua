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
