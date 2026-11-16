local wad = require("wad")
local r_data_lua = require("r_data")
local sprites = require("sprites")
local r_data_c = require("r_data_c")

local function check(condition, message)
    if not condition then
        error(message, 2)
    end
end

local function equal(a, b, message)
    check(a == b, message)
end

local function compare_posts(a, b, message)
    equal(#a, #b, message .. ": quantidade de posts")

    for i = 1, #a do
        equal(a[i].topdelta, b[i].topdelta,
            message .. ": topdelta do post " .. i)

        equal(a[i].pixels, b[i].pixels,
            message .. ": pixels do post " .. i)
    end
end

local function create_data(module)
    local w = wad.new()
    wad.add_file(w, wad.find_iwad())

    local data = module.new(w)
    data:init()

    return w, data
end

print("Inicializando implementacoes...")

local w, lua_data = create_data(r_data_lua)
local _, c_data = create_data(r_data_c)

print("OK: inicializacao")

-- --------------------------------------------------
-- SKY
-- --------------------------------------------------

print("Testando sky...")

equal(
    lua_data.skyflatnum,
    c_data:skyflatnum(),
    string.format(c_data:skyflatnum())
)

equal(
    lua_data.skytexture,
    c_data:skytexture(),
    "skytexture diferente"
)

print("OK: skyflatnum e skytexture")

-- --------------------------------------------------
-- FLATS
-- --------------------------------------------------

print("Testando flats...")

local flats_first = wad.get_num_for_name(w, "F_START") + 1
local flats_last = wad.get_num_for_name(w, "F_END") - 1

for lump = flats_first, flats_last do
    local name = w.lumps[lump + 1].name

    local lua_num = lua_data:flat_num_for_name(name)
    local c_num = c_data:flat_num_for_name(name)

    equal(lua_num, c_num,
        "flat_num_for_name diferente: " .. name)

    local lua_lump = lua_data:flat_lump(lua_num)
    local c_lump = c_data:flat_lump(c_num)

    equal(lua_lump, c_lump,
        "flat_lump diferente: " .. name)

    local lua_pixels = lua_data:flat_pixels(lua_num)
    local c_pixels = c_data:flat_pixels(c_num)

    equal(#lua_pixels, 4096,
        "Tamanho incorreto no flat Lua: " .. name)

    equal(#c_pixels, 4096,
        "Tamanho incorreto no flat C: " .. name)

    equal(lua_pixels, c_pixels,
        "Pixels diferentes no flat: " .. name)
end

-- Verifica comportamento para índices inválidos.
for _, index in ipairs({-1, 999999}) do
    equal(
        lua_data:flat_lump(index),
        c_data:flat_lump(index),
        "flat_lump diferente para índice inválido"
    )

    equal(
        lua_data:flat_pixels(index),
        c_data:flat_pixels(index),
        "flat_pixels diferente para índice inválido"
    )
end

print("OK: flats")

-- --------------------------------------------------
-- COLORMAPS
-- --------------------------------------------------

print("Testando colormaps...")

for level = -2, 35 do
    local lua_cmap = lua_data:colormap(level)
    local c_cmap = c_data:colormap(level)

    equal(#lua_cmap, 256,
        "Tamanho incorreto do colormap Lua")

    equal(#c_cmap, 256,
        "Tamanho incorreto do colormap C")

    equal(lua_cmap, c_cmap,
        "Colormap diferente no nivel " .. level)
end

print("OK: colormaps")

-- --------------------------------------------------
-- TEXTURES
-- --------------------------------------------------

print("Testando texturas...")

local texture_names = {
    "STARTAN3",
    "BRICK1",
    "SKY1",
    "COMPTILE",
    "DOORTRAK",
    "BIGDOOR2",
    "BROWN1",
}

for _, name in ipairs(texture_names) do
    local lua_num = lua_data:texture_num_for_name(name)
    local c_num = c_data:texture_num_for_name(name)

    equal(lua_num, c_num,
        "texture_num_for_name diferente: " .. name)

    local lua_width = lua_data:texture_width(lua_num)
    local c_width = c_data:texture_width(c_num)

    local lua_height = lua_data:texture_height(lua_num)
    local c_height = c_data:texture_height(c_num)

    equal(lua_width, c_width,
        "Largura diferente: " .. name)

    equal(lua_height, c_height,
        "Altura diferente: " .. name)

    -- Compara todas as colunas da textura.
    for col = 0, lua_width - 1 do
        local lua_column = lua_data:get_column(lua_num, col)
        local c_column = c_data:get_column(c_num, col)

        equal(lua_column, c_column,
            name .. ": coluna " .. col)

        -- Compara também a representação em posts.
        local lua_posts = lua_data:column_posts(lua_num, col)
        local c_posts = c_data:column_posts(c_num, col)

        compare_posts(
            lua_posts,
            c_posts,
            name .. ": coluna " .. col
        )
    end

    print("  OK:", name)
end

-- --------------------------------------------------
-- SPRITES
-- --------------------------------------------------

print("Testando sprites...")
lua_data.sprites = sprites.init_defs(w)
local lua_sprites = lua_data.sprites

-- 1. Compara a quantidade de sprites.
local lua_sprite_count = 0

for _ in pairs(lua_sprites) do
    lua_sprite_count = lua_sprite_count + 1
end

print(lua_sprite_count, c_data:sprite_count())

equal(
    lua_sprite_count,
    c_data:sprite_count(),
    "Quantidade de sprites diferente"
)

-- 2. Confere os nomes dos sprites encontrados em C.
local c_sprite_names = {}

for i = 1, c_data:sprite_count() do
    local name = c_data:sprite_name(i)

    check(name ~= nil, "Nome de sprite C inválido")

    check(
        not c_sprite_names[name],
        "Sprite duplicado em C: " .. name
    )

    c_sprite_names[name] = true
end

-- 3. Compara todos os sprites, frames e rotações.
for name, lua_frames in pairs(lua_sprites) do

    check(
        c_sprite_names[name],
        "Sprite encontrado em Lua, mas não em C: " .. name
    )

    local c_frame_count = c_data:sprite_frame_count(name)

    check(
        c_frame_count ~= nil,
        "Sprite não encontrado em C: " .. name
    )

    equal(
        #lua_frames,
        c_frame_count,
        "Quantidade de frames diferente: " .. name
    )

    for frame_index = 1, #lua_frames do
        local lua_frame = lua_frames[frame_index]
        local c_frame = c_data:sprite_frame(name, frame_index)

        check(
            c_frame ~= nil,
            "Frame não encontrado em C: " .. name
        )

        -- Compara modo de rotação.
        equal(
            lua_frame.rotate,
            c_frame.rotate,
            name .. ": rotate diferente no frame " .. frame_index
        )

        -- Compara as oito direções.
        for rotation = 1, 8 do

            local angle = (rotation - 1) * 536870912
            local moangle = 0
            local frame = frame_index - 1

            local lua_lump, lua_flip =
                sprites.lookup(lua_data, name, angle, moangle, frame)

            local c_lump, c_flip =
                c_data:sprite_lookup(name, angle, moangle, frame)

            equal(
                lua_lump,
                c_lump,
                string.format("%s: lookup lump diferente, frame %d, rotação %d",
                    name, frame_index, rotation)
            )

            equal(
                lua_flip,
                c_flip,
                string.format("%s: lookup flip diferente, frame %d, rotação %d",
                    name, frame_index, rotation)
            )

            equal(
                lua_frame.lump[rotation],
                c_frame.lump[rotation],
                string.format(
                    "%s: lump diferente no frame %d, rotação %d",
                    name, frame_index, rotation
                )
            )

            equal(
                lua_frame.flip[rotation],
                c_frame.flip[rotation],
                string.format(
                    "%s: flip diferente no frame %d, rotação %d",
                    name, frame_index, rotation
                )
            )
        end
    end

    print("  OK:", name)
end

-- 4. Garante que C não tenha sprites extras.
for name in pairs(c_sprite_names) do
    check(
        lua_sprites[name] ~= nil,
        "Sprite encontrado em C, mas não em Lua: " .. name
    )
end

print("OK: sprites, frames, rotações, lumps e flips")

