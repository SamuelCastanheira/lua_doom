local wad = require("wad")
local r_data_lua = require("r_data")
local r_data_c = require("r_data_c")

local w = wad.new()
wad.add_file(w, wad.find_iwad())

local lua_data = r_data_lua.new(w)
r_data_lua.init(lua_data)

local c_data = r_data_c.new(w)
c_data:init()

local tex_name = "STARTAN3"

local lua_tex = r_data_lua.texture_num_for_name(lua_data, tex_name)
local c_tex = c_data:texture_num_for_name(tex_name)

assert(
    r_data_lua.texture_width(lua_data, lua_tex) == c_data:texture_width(c_tex),
    "Larguras diferentes"
)

assert(
    r_data_lua.texture_height(lua_data, lua_tex) == c_data:texture_height(c_tex),
    "Alturas diferentes"
)

for x = 0, 127 do
    local lua_column = r_data_lua.get_column(lua_data,lua_tex, x)
    local c_column = c_data:get_column(c_tex, x)

    if lua_column ~= c_column then
        error("Coluna diferente: " .. x)
    end
end

print("STARTAN3: todas as colunas são idênticas!")