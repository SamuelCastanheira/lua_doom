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
-- Sprites da vista, a partir de sprites.py. O frame e o de spawn.

local compat = require("compat")
local wad = require("wad")
local v = require("v_video")
local render = require("render")
local rdata = require("r_data_c")

local M = {}

local band = compat.band
local ushr, shar = compat.ushr, compat.shar
local as_i32, as_u32 = compat.as_i32, compat.as_u32
local fixed_mul, fixed_div = compat.fixed_mul, compat.fixed_div

local FRACBITS = 16
local FRACUNIT = 65536
local SCREENWIDTH = 320
local FINEANGLES = 8192
local ANG45 = 536870912
local MAX_SPRITE_FRAMES = 29


local function u32(data, off)
  local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function install(frames, lump, frame, rotation, flipped)
  if frame < 0 or frame >= MAX_SPRITE_FRAMES or rotation < 0 or rotation > 8 then
    return false
  end
  local sf = frames[frame + 1]
  local flip = 0
  if flipped then
    flip = 1
  end
  if rotation == 0 then
    if sf.rotate == 1 then
      return true
    end
    sf.rotate = 0
    for r = 1, 8 do
      sf.lump[r] = lump
      sf.flip[r] = flip
    end
    return true
  end
  if sf.rotate == 0 then
    return true
  end
  sf.rotate = 1
  local idx = rotation
  if sf.lump[idx] < 0 then
    sf.lump[idx] = lump
    sf.flip[idx] = flip
  end
  return true
end

function M.init_defs(wadfile)
  local start = wad.check_num_for_name(wadfile, "S_START")
  local endn = wad.check_num_for_name(wadfile, "S_END")
  if start < 0 then
    start = wad.check_num_for_name(wadfile, "SS_START")
  end
  if endn < 0 then
    endn = wad.check_num_for_name(wadfile, "SS_END")
  end
  local first, last
  if start >= 0 and endn > start then
    first, last = start + 1, endn - 1
  else
    first, last = 0, wad.num_lumps(wadfile) - 1
  end
  local buckets = {}
  local order = {}
  for lump = first, last do
    local name = wad.lump_name(wadfile, lump)
    if #name >= 6 then
      local key = name:sub(1, 4)
      if not buckets[key] then
        buckets[key] = {}
        order[#order + 1] = key
      end
      local list = buckets[key]
      list[#list + 1] = lump
    end
  end
  local result = {}
  for _, sprname in ipairs(order) do
    local frames = {}
    for i = 1, MAX_SPRITE_FRAMES do
      frames[i] = { rotate = -1, lump = { -1, -1, -1, -1, -1, -1, -1, -1 }, flip = { 0, 0, 0, 0, 0, 0, 0, 0 } }
    end
    local maxframe = -1
    for _, lump in ipairs(buckets[sprname]) do
      local name = wad.lump_name(wadfile, lump)
      local frame = name:byte(5) - string.byte("A")
      local rotation = name:byte(6) - string.byte("0")
      if install(frames, lump, frame, rotation, false) and frame > maxframe then
        maxframe = frame
      end
      if #name >= 8 then
        local ch = name:sub(7, 7)
        if ch >= "A" and ch <= "]" then
          local frame2 = name:byte(7) - string.byte("A")
          local rotation2 = name:byte(8) - string.byte("0")
          if install(frames, lump, frame2, rotation2, true) and frame2 > maxframe then
            maxframe = frame2
          end
        end
      end
    end
    if maxframe >= 0 then
      for frame_i = 0, maxframe do
        local slot = frames[frame_i + 1]
        if slot.rotate == -1 then
          slot.rotate = 0
        end
      end
      local kept = {}
      for i = 1, maxframe + 1 do
        kept[i] = frames[i]
      end
      result[sprname] = kept
    end
  end
  return result
end

function M.lookup(res, name, ang_to_thing, moangle, frame)
  local base = (name or ""):sub(1, 4):upper()
  local sprframes = res:sprite_frame(base)
  if not sprframes then
    return nil
  end
  local fi = band(frame, 32767)
  local sf = sprframes[fi + 1]
  if not sf then
    return nil
  end
  local lump, flip
  if sf.rotate ~= 0 then
    local rot = band(ushr(as_u32(ang_to_thing - moangle + 2415919104), 29), 7)
    lump = sf.lump[rot + 1]
    flip = sf.flip[rot + 1]
  else
    lump = sf.lump[1]
    flip = sf.flip[1]
  end
  if lump < 0 then
    return nil
  end
  return lump, flip
end

function M.spawn_things(world, skill)
  local thinker = require("thinker")
  thinker.spawn_map(world, skill, nil)
end

-- Projecao, ordenacao, clipping contra paredes e desenho ficam em C
-- (src/render/r_things.c). Sprites usam brilho maximo, como antes.
function M.draw(renderer, world, fb)
  renderer.c:draw_sprites(world.mobjs)
end

local BASEYCENTER = 100
local WEAPONTOP = 32 * FRACUNIT
local FINESINE_LEN = 10240

-- Patches (ex.: "PISFA0") cujos estados em info.STATES tem FF_FULLBRIGHT.
-- Os flashes das armas sao acesos; o corpo da arma usa a luz do setor.
local FF_FULLBRIGHT = 32768
local fullbright_patches
local function is_fullbright(name)
  if not fullbright_patches then
    fullbright_patches = {}
    local info = require("info")
    for _, st in pairs(info.STATES) do
      local spr = info.SPRNAMES[st[0]]
      if spr and st[1] >= FF_FULLBRIGHT then
        fullbright_patches[spr .. string.char(65 + st[1] % FF_FULLBRIGHT) .. "0"] = true
      end
    end
  end
  return fullbright_patches[name] == true
end
M.is_fullbright = is_fullbright

-- Desenha um patch da arma pelo numero do lump.
-- fullbright: ignora a luz do setor; shadow: fuzz (invisibilidade).
function M.draw_psprite(renderer, fb, lump, sx, sy, fullbright, shadow)
  if lump and lump >= 0 then
    renderer.c:draw_psprite(lump, sx, sy, fb, fullbright, shadow)
  end
end

local PW_INVISIBILITY = 2
-- R_DrawPSprite: arma translucida com invisibilidade, piscando no fim.
local function player_shadow(player)
  local inv = player.powers and player.powers[PW_INVISIBILITY] or 0
  return inv > 4 * 32 or band(inv, 8) ~= 0
end

-- R_DrawPlayerSprites: a arma e o clarao, os psprites acesos, cada um no
-- seu estado de info.STATES e na sua posicao (C3; antes, o desenho calculava
-- o balanco da arma e escrevia psprite_sy no jogador).
function M.draw_weapon(renderer, fb, player)
  local pspr = require("pspr")
  local shadow = player_shadow(player)
  for position = pspr.PS_WEAPON, pspr.PS_FLASH do
    local psp = player.psprites[position]
    if psp.state ~= 0 then
      local name, aceso = pspr.patch(psp.state)
      local n = renderer.res:check_num_for_name(name)
      M.draw_psprite(renderer, fb, n, psp.sx, psp.sy, aceso, shadow)
    end
  end
end

M.ANG45 = ANG45
M.FINEANGLES = FINEANGLES

return M
