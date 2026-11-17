-- DOOM generic portado do python_doom para Lua com SDL2.
--
-- Por Wagner Nunes da Silva
--
-- vagucs@bol.com.br
-- vagucs@vagucs.com.br
-- vagucs@gmail.com
--
-- www.vagucs.com.br
--
-- Driver imperativo: o laco original a 35 Hz, sem Atmos.
--
-- Todo o estado e as regras ficam em game.lua. Este arquivo so faz o laco:
-- ler eventos, recuperar ate 4 tics de atraso e apresentar o quadro.
-- E a referencia para o driver com concorrencia estruturada (main.atm):
-- os dois precisam produzir o mesmo jogo, tic a tic (tests/test_drivers.sh).
--
--   lua5.4 main.lua -fps -scale 4
io.stdout:setvbuf("no")
io.stderr:setvbuf("no")

local video = require("video")
local game_mod = require("game")

local TICK_MS = game_mod.TICK_MS
local G = game_mod.new(arg)

local accum = 0
local last = video.ticks()
while G.running() do
  local events = video.poll()
  for i = 1, #events do
    G.handle_input(events[i])
  end
  local now = video.ticks()
  accum = accum + (now - last)
  last = now
  local guard = 0
  while accum >= TICK_MS and guard < 4 do
    if G.tic() then
      break -- fim de nivel: nao recupera mais tics neste quadro
    end
    accum = accum - TICK_MS
    guard = guard + 1
  end
  if accum > TICK_MS * 4 then
    accum = 0
  end
  G.frame()
end

G.shutdown()
