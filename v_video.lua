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
-- V_DrawPatch e primitivas 2D. O framebuffer e o userdata do framebuffer_c
-- (indices Lua 1-based); o desenho roda em C (src/v_draw.c).

local M = {}
local framebuffer_c = require("framebuffer_c")

M.SCREENWIDTH = 320
M.SCREENHEIGHT = 200
M.PIXELS = 320 * 200


local function i16(data, off)
  local b1, b2 = data:byte(off + 1, off + 2)
  local v = b1 + b2 * 256
  if v >= 32768 then
    v = v - 65536
  end
  return v
end


function M.patch_size(patch)
  return i16(patch, 0), i16(patch, 2), i16(patch, 4), i16(patch, 6)
end

function M.new_fb()
  return framebuffer_c.new()
end

function M.fill(fb, color)
  fb:clear(color or 0)
end

-- Desenho em C (src/v_draw.c). Mesma semantica da versao Lua anterior.
function M.draw_patch(fb, x, y, patch, flipped)
  fb:draw_patch(x, y, patch, flipped)
end
function M.plot(fb, x, y, color)
  fb:plot(x, y, color)
end
function M.draw_line(fb, x0, y0, x1, y1, color)
  fb:draw_line(x0, y0, x1, y1, color)
end
function M.to_raw(fb)
  return fb:to_string()
end

return M
