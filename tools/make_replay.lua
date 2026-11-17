-- Gera um roteiro de entrada para o modo replay (DOOM_REPLAY).
--
--   lua5.4 tools/make_replay.lua <saida> [quadros] [semente] [exits]
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

local MOVES = { "up", "up", "up", "down", "left", "right", "comma", "period" }
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
