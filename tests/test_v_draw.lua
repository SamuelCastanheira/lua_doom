-- Equivalencia do desenho 2D em C (src/v_draw.c) com as versoes Lua que
-- ele substituiu (v_video.lua, am_map.lua, finale.lua, wipe.lua).
-- As funcoes ref_* abaixo sao copias exatas do codigo Lua original.
local wad = require("wad")
local framebuffer_c = require("framebuffer_c")

local SCREENWIDTH, SCREENHEIGHT, PIXELS = 320, 200, 64000

local function i16(data, off)
  local b1, b2 = data:byte(off + 1, off + 2)
  local v = b1 + b2 * 256
  if v >= 32768 then
    v = v - 65536
  end
  return v
end
local function u32(data, off)
  local b1, b2, b3, b4 = data:byte(off + 1, off + 4)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- v_video.lua
local function ref_draw_patch(fb, x, y, patch, flipped)
  local w, left, top = i16(patch, 0), i16(patch, 4), i16(patch, 6)
  x = x - left
  y = y - top
  local desttop = y * SCREENWIDTH + x
  local plen = #patch
  for col = 0, w - 1 do
    local src_col = col
    if flipped then
      src_col = w - 1 - col
    end
    local column = u32(patch, 8 + src_col * 4)
    while column < plen do
      local topdelta = patch:byte(column + 1)
      if topdelta == 255 then
        break
      end
      local length = patch:byte(column + 2)
      local source = column + 3
      local dest = desttop + topdelta * SCREENWIDTH
      for _ = 1, length do
        if dest >= 0 and dest < PIXELS and source < plen then
          fb[dest + 1] = patch:byte(source + 1)
        end
        source = source + 1
        dest = dest + SCREENWIDTH
      end
      column = column + length + 4
    end
    desttop = desttop + 1
  end
end
local function ref_plot(fb, x, y, color)
  x = math.floor(x)
  y = math.floor(y)
  if x < 0 or y < 0 or x >= SCREENWIDTH or y >= SCREENHEIGHT then
    return
  end
  fb[y * SCREENWIDTH + x + 1] = color
end
local function ref_draw_line(fb, x0, y0, x1, y1, color)
  x0 = math.floor(x0 + 0.5)
  y0 = math.floor(y0 + 0.5)
  x1 = math.floor(x1 + 0.5)
  y1 = math.floor(y1 + 0.5)
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local sx, sy = 1, 1
  if x0 >= x1 then
    sx = -1
  end
  if y0 >= y1 then
    sy = -1
  end
  local err = dx - dy
  local guard = dx + dy + 1
  while guard > 0 do
    ref_plot(fb, x0, y0, color)
    if x0 == x1 and y0 == y1 then
      return
    end
    local e2 = err * 2
    if e2 > -dy then
      err = err - dy
      x0 = x0 + sx
    end
    if e2 < dx then
      err = err + dx
      y0 = y0 + sy
    end
    guard = guard - 1
  end
end

-- am_map.lua
local function ref_clear_fb(fb, f_w, f_h, color)
  for y = 0, f_h - 1 do
    local row = y * f_w
    for x = 0, f_w - 1 do
      fb[row + x + 1] = color
    end
  end
end
local function ref_put_dot(fb, f_w, f_h, xx, yy, cc)
  if xx >= 0 and xx < f_w and yy >= 0 and yy < f_h then
    fb[yy * f_w + xx + 1] = cc & 255
  end
end
local function ref_draw_fline(fb, f_w, f_h, x0, y0, x1, y1, color)
  if not (x0 >= 0 and x0 < f_w and y0 >= 0 and y0 < f_h and x1 >= 0 and x1 < f_w and y1 >= 0 and y1 < f_h) then
    return
  end
  local dx = x1 - x0
  local ax = math.abs(dx) * 2
  local sx = dx < 0 and -1 or 1
  local dy = y1 - y0
  local ay = math.abs(dy) * 2
  local sy = dy < 0 and -1 or 1
  local x, y = x0, y0
  if ax > ay then
    local d = ay - math.floor(ax / 2)
    while true do
      ref_put_dot(fb, f_w, f_h, x, y, color)
      if x == x1 then
        return
      end
      if d >= 0 then
        y = y + sy
        d = d - ax
      end
      x = x + sx
      d = d + ay
    end
  else
    local d = ax - math.floor(ay / 2)
    while true do
      ref_put_dot(fb, f_w, f_h, x, y, color)
      if y == y1 then
        return
      end
      if d >= 0 then
        x = x + sx
        d = d - ay
      end
      y = y + sy
      d = d + ax
    end
  end
end

-- finale.lua
local function ref_fill_flat(fb, data)
  for y = 0, 199 do
    local row = (y % 64) * 64
    local dest = y * SCREENWIDTH
    local x = 0
    while x < SCREENWIDTH do
      local n = math.min(64, SCREENWIDTH - x)
      for i = 0, n - 1 do
        fb[dest + x + i + 1] = data:byte(row + i + 1)
      end
      x = x + 64
    end
  end
end
local function ref_draw_patch_column(fb, x, patch, column)
  if column < 0 then
    return
  end
  local offset_pos = 8 + column * 4
  if offset_pos + 4 > #patch then
    return
  end
  local offset = u32(patch, offset_pos)
  while offset < #patch and patch:byte(offset + 1) ~= 255 do
    local top = patch:byte(offset + 1)
    local length = patch:byte(offset + 2)
    local source = offset + 3
    for i = 0, length - 1 do
      if top + i >= SCREENHEIGHT then
        break
      end
      fb[(top + i) * SCREENWIDTH + x + 1] = patch:byte(source + i + 1)
    end
    offset = offset + length + 4
  end
end

-- wipe.lua
local function ref_copy_span(dst, src, x0, y0, y1, src_y0)
  for row = 0, y1 - y0 - 1 do
    local s = (src_y0 + row) * SCREENWIDTH + x0 + 1
    local d = (y0 + row) * SCREENWIDTH + x0 + 1
    dst[d] = src[s]
    dst[d + 1] = src[s + 1]
  end
end

------------------------------------------------------------------ casos

local w = wad.new()
wad.add_file(w, wad.find_iwad())
math.randomseed(1234)

local function noise_fb()
  local fb = framebuffer_c.new()
  for i = 1, PIXELS, 7 do
    fb[i] = (i * 37) % 256
  end
  return fb
end
local function pair()
  local a = noise_fb()
  local b = framebuffer_c.new()
  b:copy_from(a)
  return a, b
end

local checks = 0
local function same(name, a, b)
  checks = checks + 1
  local sa, sb = a:to_string(), b:to_string()
  if sa ~= sb then
    for i = 1, PIXELS do
      if sa:byte(i) ~= sb:byte(i) then
        error(string.format("%s: pixel %d (x=%d y=%d) lua=%d c=%d", name, i - 1,
          (i - 1) % 320, (i - 1) // 320, sa:byte(i), sb:byte(i)))
      end
    end
  end
end

-- Patches: graficos de interface e todos os sprites.
local patches = {}
for _, name in ipairs({ "STBAR", "STARMS", "TITLEPIC", "M_DOOM", "M_SKULL1", "WIMAP0",
  "INTERPIC", "STFST01", "STTNUM0", "STKEYS0", "HELP1", "CREDIT", "PFUB1", "PFUB2" }) do
  local n = wad.check_num_for_name(w, name)
  if n >= 0 then
    patches[#patches + 1] = wad.cache_lump_num(w, n)
  end
end
local s0 = wad.check_num_for_name(w, "S_START")
local s1 = wad.check_num_for_name(w, "S_END")
for n = s0 + 1, s1 - 1, 3 do
  patches[#patches + 1] = wad.cache_lump_num(w, n)
end

for k, patch in ipairs(patches) do
  for _ = 1, 3 do
    local x = math.random(-200, 400)
    local y = math.random(-150, 300)
    local flip = math.random() < 0.5
    local a, b = pair()
    ref_draw_patch(a, x, y, patch, flip)
    b:draw_patch(x, y, patch, flip)
    same("draw_patch #" .. k, a, b)
  end
end

for k = 1, 300 do
  local a, b = pair()
  local x0, y0 = math.random() * 500 - 90, math.random() * 400 - 100
  local x1, y1 = math.random() * 500 - 90, math.random() * 400 - 100
  local c = math.random(0, 255)
  ref_draw_line(a, x0, y0, x1, y1, c)
  b:draw_line(x0, y0, x1, y1, c)
  ref_plot(a, x1, y0, c)
  b:plot(x1, y0, c)
  same("draw_line #" .. k, a, b)
end

for k = 1, 300 do
  local a, b = pair()
  local f_w, f_h = 320, 168
  local x0, y0 = math.random(-20, 340), math.random(-20, 190)
  local x1, y1 = math.random(-20, 340), math.random(-20, 190)
  local c = math.random(-300, 600)
  if k == 1 then
    ref_clear_fb(a, f_w, f_h, 0)
    b:fill_region(f_w, f_h, 0)
  end
  ref_draw_fline(a, f_w, f_h, x0, y0, x1, y1, c)
  b:am_line(x0, y0, x1, y1, c, f_w, f_h)
  ref_put_dot(a, f_w, f_h, x0, y1, c)
  b:am_dot(x0, y1, c, f_w, f_h)
  same("am_line #" .. k, a, b)
end

local f0 = wad.check_num_for_name(w, "F_START")
local f1 = wad.check_num_for_name(w, "F_END")
for n = f0 + 1, f1 - 1, 5 do
  local data = wad.cache_lump_num(w, n)
  if #data >= 4096 then
    local a, b = pair()
    ref_fill_flat(a, data)
    b:fill_flat(data)
    same("fill_flat " .. wad.lump_name(w, n), a, b)
  end
end

for k, patch in ipairs(patches) do
  local width = i16(patch, 0)
  for _ = 1, 4 do
    local a, b = pair()
    local x = math.random(0, 319)
    local col = math.random(-2, width + 2)
    ref_draw_patch_column(a, x, patch, col)
    b:draw_patch_column(x, patch, col)
    same("draw_patch_column #" .. k, a, b)
  end
end

local src = noise_fb()
for i = 1, PIXELS, 3 do
  src[i] = (i * 11) % 256
end
for k = 1, 200 do
  local a, b = pair()
  local x0 = math.random(0, 159) * 2
  local y0 = math.random(0, 199)
  local y1 = math.random(y0, 200)
  local sy0 = math.random(0, 200 - (y1 - y0))
  ref_copy_span(a, src, x0, y0, y1, sy0)
  b:copy_span(src, x0, y0, y1, sy0)
  same("copy_span #" .. k, a, b)
end

print("v_draw: " .. checks .. " comparacoes, todas identicas")
