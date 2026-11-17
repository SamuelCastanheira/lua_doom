-- atmos.env.doom: ambiente Atmos do lua_doom.
--
-- Um ambiente liga o mundo externo a uma aplicacao Atmos: a cada step() ele
-- emite eventos que acordam as tasks (ver atmos.env.clock e atmos.env.pico).
-- Este usa o modulo video (video_c ou o modo replay), e nao o lua-sdl2/pico,
-- porque o jogo ja tem a propria camada de video e audio em C.
--
-- Eventos emitidos a cada step(), nesta ordem:
--
--   {tag="input.key.down", key=..., ...}   tecla pressionada
--   {tag="input.key.up",   key=..., ...}   tecla solta
--   {tag="input.mouse",    dx=, dy=, button=, down=}
--   {tag="input.quit"}                     janela fechada
--   <numero>                               microssegundos de relogio real
--                                          (habilita "await 1s" etc.)
--   {tag="tic", n=...}                     tic de jogo a 35 Hz; ate 4 por
--                                          step para recuperar atraso
--   "frame"                                hora de desenhar/apresentar
--
-- Como o casamento de tags e hierarquico, "await :input" acorda com qualquer
-- entrada e "await :input.key.down" so com teclas pressionadas.
--
-- O jogo nao deve contar tempo em segundos: tudo no Doom e medido em tics
-- (35 por segundo). Use "await :tic" (ou um helper wait_tics(n)).
--
-- A temporizacao e a mesma do laco original (main.lua): acumulador em ms e no
-- maximo 4 tics por step. cancel_catchup() interrompe a recuperacao de tics do
-- step atual (o laco original fazia "break" quando o nivel terminava).
local atmos = require("atmos")
local video = require("video")

local M = {
  ticrate = 35,
  max_catchup = 4,
  tic = 0, -- tics emitidos desde o inicio
  now = 0, -- ms do relogio do video
}

local TICK_MS = 1000 / M.ticrate
local accum = 0
local last = nil
local cancel = false

function M.cancel_catchup()
  cancel = true
end

local function input_tag(ev)
  if ev.mouse then
    return "input.mouse"
  elseif ev.key == "quit" then
    return "input.quit"
  elseif ev.down then
    return "input.key.down"
  end
  return "input.key.up"
end

function M.step()
  if last == nil then
    last = video.ticks()
  end
  local events = video.poll()
  for i = 1, #events do
    local ev = events[i]
    ev.tag = input_tag(ev)
    emit(ev)
  end

  local now = video.ticks()
  local dt = now - last
  accum = accum + dt
  last = now
  M.now = now
  if dt > 0 then
    emit(math.floor(dt * 1000))
  end

  local guard = 0
  cancel = false
  while accum >= TICK_MS and guard < M.max_catchup do
    M.tic = M.tic + 1
    emit({ tag = "tic", n = M.tic })
    if cancel then
      break
    end
    accum = accum - TICK_MS
    guard = guard + 1
  end
  if accum > TICK_MS * 4 then
    accum = 0
  end

  emit("frame")
end

atmos.env(M)

return M
