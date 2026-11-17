-- Renderiza quadros de teste sem abrir janela e grava o framebuffer cru.
--
-- Uso (a partir da raiz de uma copia do projeto):
--   lua5.4 tools/dump_frames.lua <saida_dir> [episodio] [mapa] [sprites|full]
--                                [blocks] [detail]
--
-- "full" = sprites + arma + variacao de extralight e fixedcolormap.
-- blocks: 3..11 (11 = tela cheia, padrao); detail: 0 alto, 1 baixo.
--
-- Gera <saida_dir>/frame_NN.raw (64000 bytes, indices de paleta) e
-- <saida_dir>/palette.raw. Funciona tanto com o renderer Lua antigo
-- (commit 522b06f) quanto com o renderer em C, para comparar pixel a pixel.
-- As cameras ficam nas posicoes dos things do mapa, com angulos variados.
local outdir = assert(arg[1], "uso: dump_frames.lua <saida_dir> [ep] [mapa] [sprites]")
local episode = tonumber(arg[2] or "1")
local mapn = tonumber(arg[3] or "1")
local mode = arg[4] or ""
local with_sprites = mode == "sprites" or mode == "full"
local full = mode == "full"
local blocks = tonumber(arg[5] or "11")
local detail = tonumber(arg[6] or "0")

local wad = require("wad")
local v = require("v_video")
local world_mod = require("world")
local render = require("render")
local sprites = require("sprites")

local w = wad.new()
wad.add_file(w, wad.find_iwad())

local res
local ok_c, rdata_c = pcall(require, "r_data_c")
if ok_c and not package.loaded["r_data"] then
  res = rdata_c.new(w)
  res:init()
else
  local rdata = require("r_data")
  res = rdata.new(w)
  rdata.init(res)
  res.sprites = sprites.init_defs(w)
end

local world = world_mod.new()
world_mod.setup_level(world, w, res, episode, mapn)
if with_sprites then
  sprites.spawn_things(world, 2)
end

local renderer = render.new(res)
render.set_view_size(renderer, blocks, detail)

local function save(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function fb_bytes(fb)
  if type(fb) == "table" then
    local parts = {}
    for i = 1, 64000, 4000 do
      parts[#parts + 1] = string.char(table.unpack(fb, i, i + 3999))
    end
    return table.concat(parts)
  end
  return fb:to_string()
end

save(outdir .. "/palette.raw", wad.cache_lump_name(w, "PLAYPAL"):sub(1, 768))

local ANG45 = 536870912
local frame = 0
local things = world.things
local step = math.max(1, math.floor(#things / 24))
for t = 1, #things, step do
  local th = things[t]
  local x, y = th.x * 65536, th.y * 65536
  local sub = world_mod.point_in_subsector(world, x, y)
  local z = sub.sector.floorheight + 41 * 65536
  for _, rot in ipairs({ 0, 3 }) do
    local ang = (math.floor(th.angle * ANG45 / 45) + rot * ANG45) % 4294967296
    local fb = v.new_fb()
    local extra, cmap = 0, 0
    if full then
      extra = frame % 3
      if frame % 5 == 4 then
        cmap = (frame % 2 == 0) and 32 or 1
      end
    end
    render.setup_frame(renderer, x, y, z, ang, extra, cmap)
    render.render(renderer, world, fb)
    if with_sprites then
      sprites.draw(renderer, world, fb)
      render.draw_masked(renderer)
    end
    if full then
      local lump = wad.check_num_for_name(w, frame % 2 == 0 and "PISGA0" or "SHTGA0")
      local sx = 65536 + (frame % 7 - 3) * 65536 * 4
      local sy = 32 * 65536 + (frame % 4) * 65536 * 3
      if renderer.c then
        sprites.draw_psprite(renderer, fb, lump, sx, sy)
      else
        sprites.draw_psprite(renderer, fb, wad.cache_lump_num(w, lump), sx, sy)
      end
    end
    save(string.format("%s/frame_%02d.raw", outdir, frame), fb_bytes(fb))
    frame = frame + 1
  end
end
print("frames", frame)
