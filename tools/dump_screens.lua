-- Gera telas 2D (menu, automapa, finale, wipe, mapa simples) sem janela,
-- para comparar o desenho 2D entre versoes com tools/compare_frames.py.
--   lua5.4 tools/dump_screens.lua <saida_dir>
local outdir = assert(arg[1], "uso: dump_screens.lua <saida_dir>")
local wad = require("wad")
local v = require("v_video")
local menu_mod = require("menu")
local am_map = require("am_map")
local finale_mod = require("finale")
local wipe_mod = require("wipe")
local world_mod = require("world")
local sprites = require("sprites")

local w = wad.new()
wad.add_file(w, wad.find_iwad())
local res = require("r_data_c").new(w)
res:init()

local n = 0
local function save(fb)
  local f = assert(io.open(string.format("%s/frame_%02d.raw", outdir, n), "wb"))
  f:write(fb:to_string())
  f:close()
  n = n + 1
end
do
  local f = assert(io.open(outdir .. "/palette.raw", "wb"))
  f:write(wad.cache_lump_name(w, "PLAYPAL"):sub(1, 768))
  f:close()
end

local fb = v.new_fb()

-- Menu: tela principal e submenus navegando com as setas.
local sound = { sfx_volume = 8, music_volume = 8, play = function() end }
local game = {
  running = true, show_messages = true, detail_level = 0, screen_size = 7,
  mouse_sensitivity = 5, sound = sound, skill = 2, episode = 1, mapn = 1, wad = w,
  start_sound = function() end, held = {},
}
local menu = menu_mod.new(w, sound, game)
menu_mod.responder(menu, "return")
for _, key in ipairs({ "", "down", "return", "escape", "down", "down", "return", "down", "escape" }) do
  if key ~= "" then
    menu_mod.responder(menu, key)
  end
  v.fill(fb, 0)
  v.draw_patch(fb, 0, 0, wad.cache_lump_name(w, "TITLEPIC"))
  menu_mod.draw(menu, fb)
  save(fb)
end

-- Mapa simples do world (draw_line com coordenadas float).
local world = world_mod.new()
world_mod.setup_level(world, w, res, 1, 1)
v.fill(fb, 0)
world.res = nil -- draw_overhead usa res.swatch, que nao existe no userdata r_data_c
world_mod.draw_overhead(world, fb, wad.cache_lump_name(w, "PLAYPAL"))
world.res = res
save(fb)

-- Automapa: varias posicoes, zoom e grade.
sprites.spawn_things(world, 2)
local ps = world_mod.player_start(world)
local mo = { x = ps.x * 65536, y = ps.y * 65536, angle = 0 }
game.world = world
game.player = { mo = mo, cheats = 0, powers = { [0] = 0, 0, 0, 0, 0, 0 } }
local am = am_map.new()
am_map.start(am, game)
for k = 1, 6 do
  mo.angle = (k * 700000000) % 4294967296
  mo.x = mo.x + k * 64 * 65536
  if k == 3 then
    am.grid = 1
  end
  if k == 5 then
    am.cheating = 2
  end
  am_map.ticker(am, game)
  am_map.drawer(am, fb, game)
  save(fb)
end

-- Finale: texto, arte e rolagem do coelho.
for _, ep in ipairs({ 1, 3 }) do
  game.episode = ep
  local fin = finale_mod.new(game)
  for t = 1, 400 do
    finale_mod.ticker(fin)
    if t % 80 == 0 then
      finale_mod.draw(fin, fb)
      save(fb)
    end
  end
  for _, stage in ipairs({ 1, 2 }) do
    fin.stage = stage
    for t = 1, 3 do
      fin.count = t * 300
      finale_mod.draw(fin, fb)
      save(fb)
    end
  end
end

-- Wipe com sequencia aleatoria fixa.
local wipe = wipe_mod.new()
v.fill(fb, 0)
v.draw_patch(fb, 0, 0, wad.cache_lump_name(w, "TITLEPIC"))
wipe_mod.capture_start(wipe, fb)
v.fill(fb, 0)
v.draw_patch(fb, 0, 0, wad.cache_lump_name(w, "INTERPIC"))
wipe_mod.capture_end(wipe, fb)
local seed = 7
wipe_mod.begin(wipe, fb, function(m)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % m
end)
for t = 1, 40 do
  local done = wipe_mod.tick(wipe, 1, fb)
  if t % 4 == 0 or done then
    save(fb)
  end
  if done then
    break
  end
end
print("telas", n)
