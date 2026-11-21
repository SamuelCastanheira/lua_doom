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
-- Uma API de video. LuaJIT usa a FFI. Lua 5.4 usa video_c.dll.

local keys = require("keys")

local M = {}

-- Modo replay (DOOM_REPLAY=roteiro): sem janela nem som, tempo simulado
-- (cada poll() avanca exatamente 1 tic) e teclas lidas de um roteiro.
-- Cada present() grava "quadro hash_framebuffer hash_estado" em
-- DOOM_REPLAY_OUT. Serve para provar que main.lua e main.atm produzem o
-- mesmo jogo. Roteiro: uma linha por evento, "<quadro> <tecla> down|up",
-- "<quadro> quit", "<quadro> exit [secret]" (termina o nivel atual, para
-- testar intermissao e finale) ou "<quadro> die" (o jogador morre).
-- quadro = numero do poll, a partir de 1.
local function replay_backend(path)
  local fbmod = require("framebuffer_c")
  -- wipe.lua e wi_stuff.lua usam math.random (o original usava M_Random);
  -- no replay a semente e fixa para que duas execucoes sejam iguais.
  math.randomseed(1)
  local script = {}
  for line in io.lines(path) do
    local n, key, dir = line:match("^%s*(%d+)%s+(%S+)%s*(%S*)")
    local gx, gy = line:match("^%s*%d+%s+goto%s+(%-?%d+)%s+(%-?%d+)")
    if n then
      n = tonumber(n)
      script[n] = script[n] or {}
      local ev
      if key == "quit" then
        ev = { key = "quit", down = true }
      elseif key == "exit" then
        -- so para testes: termina o nivel como o switch de saida
        ev = { key = "", replay_exit = true, secret = dir == "secret" }
      elseif key == "die" then
        -- so para testes: o jogador morre (renasce ao apertar "use")
        ev = { key = "", replay_die = true }
      elseif key == "use" then
        -- so para testes: aciona a linha N (indice do WAD), como o "use" do
        -- jogador encostado nela; usado para switches repetiveis (passo 3e)
        ev = { key = "", replay_use = tonumber(dir) }
      elseif key == "cross" then
        -- so para testes: cruza a linha N (indice do WAD) pela frente, como o
        -- jogador andando por cima dela; portas de 30 s etc. (passo 3b)
        ev = { key = "", replay_cross = tonumber(dir) }
      elseif key == "goto" then
        -- so para testes: poe o jogador no ponto (x, y) do mapa, em unidades
        -- do mapa; usado para ficar embaixo de um esmagador (passo 3d)
        ev = { key = "", replay_goto = { tonumber(gx), tonumber(gy) } }
      else
        ev = { key = key, down = dir ~= "up" }
      end
      table.insert(script[n], ev)
    end
  end
  local out = assert(io.open(os.getenv("DOOM_REPLAY_OUT") or "replay.log", "w"))
  -- DOOM_REPLAY_DUMP="1450,1500": grava esses quadros (64000 bytes, indices
  -- de paleta) em <DOOM_REPLAY_OUT>.<quadro>.raw, para depurar divergencias.
  local dump = {}
  for n in (os.getenv("DOOM_REPLAY_DUMP") or ""):gmatch("%d+") do
    dump[tonumber(n)] = true
  end
  local polls, frames = 0, 0
  local tick_ms = 1000 / 35
  local b = {}
  function b.init() end
  function b.shutdown()
    out:close()
  end
  function b.set_palette() end
  function b.delay() end
  function b.ticks()
    return polls * tick_ms
  end
  function b.poll()
    polls = polls + 1
    return script[polls] or {}
  end
  function b.present(fb)
    frames = frames + 1
    local state = M.state_hook and M.state_hook() or ""
    out:write(string.format("%d %d %d\n", frames, fbmod.hash(fb), fbmod.hash(state)))
    if dump[frames] then
      local fh = assert(io.open(string.format("%s.%d.raw",
        os.getenv("DOOM_REPLAY_OUT") or "replay.log", frames), "wb"))
      fh:write(fb)
      fh:close()
    end
  end
  return b
end

local replay_path = os.getenv("DOOM_REPLAY")
local raw
if replay_path and replay_path ~= "" then
  raw = replay_backend(replay_path)
  M.replay = true
else
  raw = require("video_c")
end

function M.init(w, h, scale, title)
  print("SCALE", scale)
  raw.init(w, h, scale, title)
end

function M.shutdown()
  raw.shutdown()
end

function M.set_palette(rgb)
  raw.set_palette(rgb)
end

function M.present(fb)
  raw.present(fb)
end

function M.delay(ms)
  raw.delay(ms)
end

function M.ticks()
  return raw.ticks()
end

function M.poll()
  local events = raw.poll()
  for i = 1, #events do
    if events[i].mouse then
      events[i].key = ""
    elseif events[i].key == nil then
      events[i].key = keys.name_of(events[i].sym)
    end
  end
  return events
end

-- Correcao de gama 0..4 (F11), como no Doom original.
function M.set_gamma(level)
  if raw.set_gamma then
    return raw.set_gamma(level)
  end
  return 0
end
function M.set_crt(on)
  if raw.set_crt then
    raw.set_crt(on)
  end
end

function M.mouse_relative(on)
  if raw.mouse_relative then
    raw.mouse_relative(on)
  end
end

function M.toggle_fullscreen()
  if raw.toggle_fullscreen then
    return raw.toggle_fullscreen()
  end
  return false
end

function M.audio_open()
  if not raw.audio_open then
    return nil
  end
  return raw.audio_open()
end

function M.audio_queue(pcm)
  if raw.audio_queue then
    raw.audio_queue(pcm)
  end
end

function M.audio_clear()
  if raw.audio_clear then
    raw.audio_clear()
  end
end

function M.audio_close()
  if raw.audio_close then
    raw.audio_close()
  end
end

function M.music_open(path)
  if not raw.music_open then
    return false
  end
  return raw.music_open(path)
end

function M.music_status()
  if not raw.music_status then
    return ""
  end
  return raw.music_status()
end

function M.music_play()
  if raw.music_play then
    raw.music_play()
  end
end

function M.music_volume(level)
  if raw.music_volume then
    raw.music_volume(level)
  end
end

function M.music_pause(on)
  if raw.music_pause then
    raw.music_pause(on)
  end
end

function M.music_close()
  if raw.music_close then
    raw.music_close()
  end
end

return M
