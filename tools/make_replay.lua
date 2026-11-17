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
