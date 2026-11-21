local render_c = require("render_c")
local framebuffer_c = require("framebuffer_c")

local FRACBITS = 16
local FRACUNIT = 65536
local SCREENWIDTH = 320
local SCREENHEIGHT = 200
local PIXELS = SCREENWIDTH * SCREENHEIGHT

local function as_i32(n)
    n = n & 0xffffffff
    if n >= 0x80000000 then
        n = n - 0x100000000
    end
    return n
end

-- Deslocamento aritmético à direita.
local function shar(n, bits)
    return math.floor(as_i32(n) / (2 ^ bits))
end

local function shl(n, bits)
    return as_i32(n << bits)
end

-- =========================================================
-- Referência Lua: draw_column
-- =========================================================

local function draw_lua(fb, a)
    local count = a.yh - a.yl

    if count < 0 or a.x < 0 or a.x >= a.viewwidth then
        return
    end

    local yl = math.max(0, math.min(199, a.yl))

    local x = a.x
    local dest, dest2

    if a.detailshift ~= 0 then
        x = as_i32(x << 1)
        if x < 0 or x + 1 >= 320 then return end
        dest = (yl + a.viewwindowy) * 320 + a.viewwindowx + x
        dest2 = dest + 1
    else
        dest = (yl + a.viewwindowy) * 320 + a.viewwindowx + x
    end

    local fracstep = a.iscale
    local frac = a.texturemid + (a.yl - a.centery) * fracstep

    while count >= 0 and dest < PIXELS do
        local idx = shar(frac, 16) & 127
        local pix = a.source:byte((idx % #a.source) + 1)
        local val = pix

        if pix < #a.colormap then
            val = a.colormap:byte(pix + 1)
        end

        if dest >= 0 then fb[dest + 1] = val end
        if dest2 and dest2 < PIXELS then fb[dest2 + 1] = val end

        dest = dest + 320
        if dest2 then dest2 = dest2 + 320 end

        frac = as_i32(frac + fracstep)
        count = count - 1
    end
end

-- =========================================================
-- Referência Lua: draw_masked_column
-- =========================================================

local function draw_masked_lua(fb, a)
    local basemid = a.texturemid

    for _, post in ipairs(a.posts) do
        local topdelta = post.topdelta
        local pixels = post.pixels

        if #pixels > 0 then
            local topscreen = a.sprtopscreen + a.spryscale * topdelta
            local bottomscreen = topscreen + a.spryscale * #pixels

            local yl = shar(topscreen + FRACUNIT - 1, FRACBITS)
            local yh = shar(bottomscreen - 1, FRACBITS)

            if yh >= a.mfloor then
                yh = a.mfloor - 1
            end

            if yl <= a.mceil then
                yl = a.mceil + 1
            end

            if yl < 0 then
                yl = 0
            end

            if yh >= a.viewheight then
                yh = a.viewheight - 1
            end

            if yl <= yh then
                local src = post.col128 or pixels

                if #src < 128 then
                    src = src .. string.rep("\0", 128 - #src)
                elseif #src > 128 then
                    src = src:sub(1, 128)
                end

                post.col128 = src

                draw_lua(fb, {
                    x = a.x,
                    yl = yl,
                    yh = yh,
                    iscale = a.iscale,
                    texturemid = basemid - shl(topdelta, FRACBITS),
                    source = src,
                    colormap = a.colormap,
                    centery = a.centery,
                    viewwidth = a.viewwidth,
                    detailshift = a.detailshift,
                    viewwindowx = a.viewwindowx,
                    viewwindowy = a.viewwindowy,
                })
            end
        end
    end
end

-- =========================================================
-- Utilitários
-- =========================================================

local function compare(a, b)
    for i = 1, PIXELS do
        if a[i] ~= b[i] then
            return false, i, a[i], b[i]
        end
    end

    return true
end

local function make_string(n, seed)
    local t = {}

    for i = 1, n do
        t[i] = string.char((i * 37 + seed * 13) % 256)
    end

    return table.concat(t)
end

local function clone_posts(posts)
    local result = {}

    for i, post in ipairs(posts) do
        result[i] = {
            topdelta = post.topdelta,
            pixels = post.pixels,
        }
    end

    return result
end

local function new_framebuffers()
    local lua_fb = framebuffer_c.new()
    local c_fb = framebuffer_c.new()

    -- Valor diferente de zero para detectar escritas indevidas.
    lua_fb:clear(165)
    c_fb:clear(165)

    return lua_fb, c_fb
end

local function report_result(name, lua_fb, c_fb)
    local ok, pos, expected, actual = compare(lua_fb, c_fb)

    if ok then
        print("OK: " .. name)
        return true
    end

    print(string.format(
        "FALHOU: %s | pixel %d | Lua=%d | C=%d | x=%d y=%d",
        name,
        pos,
        expected,
        actual,
        (pos - 1) % SCREENWIDTH,
        math.floor((pos - 1) / SCREENWIDTH)
    ))

    return false
end

-- =========================================================
-- Dados de teste
-- =========================================================

local source = make_string(128, 1)
local cmap = make_string(256, 3)

-- =========================================================
-- Testes draw_column
-- =========================================================

local column_cases = {
    {
        yl = 0, yh = 39, x = 100,
        iscale = FRACUNIT, texturemid = 0,
    },
    {
        yl = 20, yh = 80, x = 120,
        iscale = FRACUNIT // 2, texturemid = FRACUNIT,
    },
    {
        yl = 170, yh = 199, x = 160,
        iscale = FRACUNIT * 2, texturemid = -FRACUNIT,
    },
    {
        yl = 0, yh = 100, x = 100,
        iscale = FRACUNIT, texturemid = -20 * FRACUNIT,
    },
}

local passed = 0
local total = 0

for i, c in ipairs(column_cases) do
    total = total + 1

    local a, b = new_framebuffers()

    c.centery = 100
    c.viewwidth = 320
    c.detailshift = 0
    c.viewwindowx = 0
    c.viewwindowy = 0
    c.source = source
    c.colormap = cmap

    draw_lua(a, c)

    render_c.draw_column(
        b,
        c.x, c.yl, c.yh,
        c.iscale, c.texturemid,
        c.source, c.colormap,
        c.centery, c.viewwidth,
        c.detailshift, c.viewwindowx, c.viewwindowy
    )

    if report_result("draw_column " .. i, a, b) then
        passed = passed + 1
    end
end

-- =========================================================
-- Testes draw_masked_column
-- =========================================================

local function masked_case(overrides)
    local a = {
        sprtopscreen = 50 * FRACUNIT,
        spryscale = FRACUNIT,

        mceil = -1,
        mfloor = 200,

        x = 100,
        iscale = FRACUNIT,
        texturemid = 0,

        centery = 100,
        viewwidth = 320,
        viewheight = 200,

        detailshift = 0,
        viewwindowx = 0,
        viewwindowy = 0,

        colormap = cmap,

        posts = {
            { topdelta = 0, pixels = make_string(40, 1) },
        },
    }

    for k, v in pairs(overrides or {}) do
        a[k] = v
    end

    return a
end

local masked_cases = {
    {
        name = "post central",
        args = masked_case(),
    },

    {
        name = "post parcialmente cortado em cima",
        args = masked_case({
            sprtopscreen = -20 * FRACUNIT,
            posts = {
                { topdelta = 0, pixels = make_string(60, 2) },
            },
        }),
    },

    {
        name = "post parcialmente cortado embaixo",
        args = masked_case({
            sprtopscreen = 170 * FRACUNIT,
            posts = {
                { topdelta = 0, pixels = make_string(60, 3) },
            },
        }),
    },

    {
        name = "post cortado por mceil",
        args = masked_case({
            sprtopscreen = 20 * FRACUNIT,
            mceil = 35,
            posts = {
                { topdelta = 0, pixels = make_string(80, 4) },
            },
        }),
    },

    {
        name = "post cortado por mfloor",
        args = masked_case({
            sprtopscreen = 80 * FRACUNIT,
            mfloor = 120,
            posts = {
                { topdelta = 0, pixels = make_string(80, 5) },
            },
        }),
    },

    {
        name = "múltiplos posts",
        args = masked_case({
            sprtopscreen = 20 * FRACUNIT,
            mceil = 30,
            mfloor = 160,
            posts = {
                { topdelta = 0, pixels = make_string(20, 6) },
                { topdelta = 30, pixels = make_string(30, 7) },
                { topdelta = 70, pixels = make_string(40, 8) },
            },
        }),
    },

    {
        name = "post vazio entre posts válidos",
        args = masked_case({
            posts = {
                { topdelta = 0, pixels = make_string(20, 9) },
                { topdelta = 20, pixels = "" },
                { topdelta = 40, pixels = make_string(30, 10) },
            },
        }),
    },

    {
        name = "post menor que 128 bytes",
        args = masked_case({
            posts = {
                { topdelta = 0, pixels = make_string(17, 11) },
            },
        }),
    },

    {
        name = "post exatamente 128 bytes",
        args = masked_case({
            posts = {
                { topdelta = 0, pixels = make_string(128, 12) },
            },
        }),
    },

    {
        name = "post maior que 128 bytes",
        args = masked_case({
            posts = {
                { topdelta = 0, pixels = make_string(180, 13) },
            },
        }),
    },

    {
        name = "escala vertical fracionária",
        args = masked_case({
            sprtopscreen = 30 * FRACUNIT,
            spryscale = FRACUNIT // 2,
            posts = {
                { topdelta = 0, pixels = make_string(100, 14) },
            },
        }),
    },

    {
        name = "detailshift",
        args = masked_case({
            x = 100,
            viewwidth = 160,
            detailshift = 1,
            posts = {
                { topdelta = 0, pixels = make_string(80, 15) },
            },
        }),
    },

    {
        name = "viewport deslocado",
        args = masked_case({
            sprtopscreen = 20 * FRACUNIT,
            viewwindowx = 20,
            viewwindowy = 10,
            posts = {
                { topdelta = 0, pixels = make_string(80, 16) },
            },
        }),
    },

    {
        name = "coluna próxima à borda direita",
        args = masked_case({
            x = 319,
            posts = {
                { topdelta = 0, pixels = make_string(60, 17) },
            },
        }),
    },

    {
        name = "post totalmente fora da área visível",
        args = masked_case({
            sprtopscreen = -150 * FRACUNIT,
            posts = {
                { topdelta = 0, pixels = make_string(20, 18) },
            },
        }),
    },
}

for _, test in ipairs(masked_cases) do
    total = total + 1

    local a, b = new_framebuffers()
    local args = test.args

    -- Cada implementação recebe seus próprios posts.
    local lua_posts = clone_posts(args.posts)
    local c_posts = clone_posts(args.posts)

    local lua_args = {}
    for k, v in pairs(args) do
        lua_args[k] = v
    end
    lua_args.posts = lua_posts

    local c_args = {}
    for k, v in pairs(args) do
        c_args[k] = v
    end
    c_args.posts = c_posts

    draw_masked_lua(a, lua_args)

    render_c.draw_masked_column(
        b,
        c_args.posts,
        c_args.sprtopscreen,
        c_args.spryscale,
        c_args.mceil,
        c_args.mfloor,
        c_args.x,
        c_args.iscale,
        c_args.texturemid,
        c_args.colormap,
        c_args.centery,
        c_args.viewwidth,
        c_args.viewheight,
        c_args.detailshift,
        c_args.viewwindowx,
        c_args.viewwindowy
    )

    if report_result(test.name, a, b) then
        passed = passed + 1
    end
end

print(string.format("\nResultado: %d/%d testes passaram.", passed, total))

assert(passed == total, "Há divergências entre Lua e C!")