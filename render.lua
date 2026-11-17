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
-- Vista: interface Lua do renderer em C (src/render/, modulo render_c).
-- BSP, paredes, chao, teto, ceu, sprites e masked rodam em C. Este modulo
-- so repassa chamadas e guarda o estado que o resto do jogo consulta.
local render_c = require("render_c")
local native_tables = require("tables_c").new()
native_tables:init()

local M = {}

function M.new(res)
  return {
    res = res,
    c = render_c.new(res, native_tables),
    screenblocks = 10,
  }
end

function M.set_view_size(self, blocks, detail)
  self.screenblocks = self.c:set_view_size(blocks, detail)
end

function M.setup_frame(self, x, y, z, angle, extra_light, fixedcolormap)
  self.c:setup_frame(x, y, z, angle, extra_light or 0, fixedcolormap or 0)
end

-- Paredes, chao, teto e ceu. Sincroniza setores e lados do world a cada quadro.
function M.render(self, world, fb)
  self.fb = fb
  self.c:render(world, fb)
end

-- Texturas mascaradas que nao foram desenhadas junto com os sprites.
function M.draw_masked(self)
  self.c:draw_masked()
end

-- Ceu do nivel, como G_InitNew do Doom original:
--   Doom 2: mapas 1-11 SKY1, 12-20 SKY2, 21+ SKY3
--   Doom 1: episodio 1..4 -> SKY1..SKY4
-- O original so escolhia o ceu ao comecar um jogo novo (no Doom 2 o ceu nao
-- mudava ao passar do mapa 11 para o 12); aqui vale para todo inicio de nivel.
function M.sky_name(wadfile, episode, mapn)
  local wad = require("wad")
  if wad.check_num_for_name(wadfile, "MAP01") >= 0 then
    if mapn < 12 then
      return "SKY1"
    elseif mapn < 21 then
      return "SKY2"
    end
    return "SKY3"
  end
  return "SKY" .. tostring(math.max(1, math.min(4, episode)))
end

function M.set_level_sky(res, wadfile, episode, mapn)
  res:set_sky(M.sky_name(wadfile, episode, mapn))
end

function M.point_to_angle(self, x, y)
  return self.c:point_to_angle(x, y)
end

-- Leitura de estado do renderer C (viewwidth, viewheight, centerxfrac, ...).
function M.get(self, field)
  return self.c:get(field)
end

return M
