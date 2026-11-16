#include <lua.h>
#include <lauxlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#include "framebuffer.h"
#include "render_types.h"
#include "tables_c.h"

#define SCREENWIDTH  320
#define SCREENHEIGHT 200
#define PIXELS      (SCREENWIDTH * SCREENHEIGHT)
#define FRACBITS 16
#define FRACUNIT  65536
#define SCREENWIDTH  320
#define SCREENHEIGHT  200
#define SBARHEIGHT  32
#define FINEANGLES  8192
#define FINEMASK  8191
#define ANGLETOFINESHIFT  19
#define ANG90  1073741824
#define ANG180  2147483648
#define FIELDOFVIEW  2048
#define LIGHTLEVELS  16
#define LIGHTZSHIFT  20
#define MAXLIGHTZ  128
#define LIGHTSCALESHIFT  12
#define MAXLIGHTSCALE  48
#define NUMCOLORMAPS  32
#define NF_SUBSECTOR  32768
#define ML_DONTPEGTOP  8
#define ML_DONTPEGBOTTOM  16
#define ML_MAPPED  256
#define SIL_NONE  0
#define SIL_TOP  1
#define SIL_BOTTOM  2
#define SIL_BOTH  3
#define HEIGHTBITS  12
#define HEIGHTUNIT  4096
#define ANGLETOSKYSHIFT  22
#define SHRT_MAX  32767
#define INT_MAX  2147483647
#define INT_MIN  -2147483647
#define PIXELS  SCREENWIDTH * SCREENHEIGHT


/*
 * Converte para int32 preservando o comportamento
 * de overflow da implementação Lua as_i32().
 */
static int32_t as_i32(int64_t value)
{
    uint32_t u = (uint32_t)value;

    if (u <= INT32_MAX)
        return (int32_t)u;

    return (int32_t)((int64_t)u - 4294967296LL);
}

/*
 * Deslocamento aritmético à direita.
 * Equivalente ao shar() utilizado em Lua.
 */
static int64_t arithmetic_shift_right(int64_t value, int bits)
{
    if (value >= 0)
        return value >> bits;

    return -(((-value) + (((int64_t)1 << bits) - 1)) >> bits);
}

static int32_t fixed_shr(int64_t value, int bits)
{
    return (int32_t)arithmetic_shift_right(as_i32(value), bits);
}

#define VISPLANE_MT "render_c.Visplane"
#define VISPLANE_SPAN_MT "render_c.VisplaneSpan"

typedef struct {
    Visplane *plane;
    int bottom;
} VisplaneSpan;

static Visplane *check_visplane(lua_State *L, int index)
{
    return (Visplane *)luaL_checkudata(L, index, VISPLANE_MT);
}

static VisplaneSpan *check_visplane_span(lua_State *L, int index)
{
    return (VisplaneSpan *)luaL_checkudata(
        L, index, VISPLANE_SPAN_MT
    );
}

/* Acesso a pl.top[x] e pl.bottom[x]. */

static int l_visplane_span_index(lua_State *L)
{
    VisplaneSpan *span = check_visplane_span(L, 1);
    lua_Integer x = luaL_checkinteger(L, 2);

    if (x < 0 || x >= RENDER_SCREENWIDTH) {
        lua_pushnil(L);
        return 1;
    }

    int16_t value = span->bottom
        ? span->plane->bottom[x]
        : span->plane->top[x];

    lua_pushinteger(L, value);
    return 1;
}

static int l_visplane_span_newindex(lua_State *L)
{
    VisplaneSpan *span = check_visplane_span(L, 1);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer value = luaL_checkinteger(L, 3);

    if (x < 0 || x >= RENDER_SCREENWIDTH) {
        return luaL_error(L, "visplane span index out of range");
    }

    if (value < INT16_MIN || value > INT16_MAX) {
        return luaL_error(L, "visplane span value out of int16 range");
    }

    if (span->bottom) {
        span->plane->bottom[x] = (int16_t)value;
    } else {
        span->plane->top[x] = (int16_t)value;
    }

    return 0;
}

/* Acesso aos campos do Visplane. */

static int l_visplane_index(lua_State *L)
{
    Visplane *pl = check_visplane(L, 1);
    const char *key = luaL_checkstring(L, 2);

    if (strcmp(key, "height") == 0)
        lua_pushinteger(L, pl->height);
    else if (strcmp(key, "picnum") == 0)
        lua_pushinteger(L, pl->picnum);
    else if (strcmp(key, "lightlevel") == 0)
        lua_pushinteger(L, pl->lightlevel);
    else if (strcmp(key, "minx") == 0)
        lua_pushinteger(L, pl->minx);
    else if (strcmp(key, "maxx") == 0)
        lua_pushinteger(L, pl->maxx);
    else if (strcmp(key, "top") == 0 || strcmp(key, "bottom") == 0) {
        lua_getiuservalue(L, 1, 1);
        lua_getfield(L, -1, key);
        lua_remove(L, -2);
    } else {
        lua_pushnil(L);
    }

    return 1;
}

static int l_visplane_newindex(lua_State *L)
{
    Visplane *pl = check_visplane(L, 1);
    const char *key = luaL_checkstring(L, 2);
    lua_Integer value = luaL_checkinteger(L, 3);

    if (value < INT32_MIN || value > INT32_MAX) {
        return luaL_error(L, "visplane value out of int32 range");
    }

    if (strcmp(key, "height") == 0)
        pl->height = (int32_t)value;
    else if (strcmp(key, "picnum") == 0)
        pl->picnum = (int32_t)value;
    else if (strcmp(key, "lightlevel") == 0)
        pl->lightlevel = (int32_t)value;
    else if (strcmp(key, "minx") == 0)
        pl->minx = (int32_t)value;
    else if (strcmp(key, "maxx") == 0)
        pl->maxx = (int32_t)value;
    else
        return luaL_error(L, "unknown Visplane field: %s", key);

    return 0;
}

static void create_visplane_metatables(lua_State *L)
{
    if (luaL_newmetatable(L, VISPLANE_MT)) {
        lua_pushcfunction(L, l_visplane_index);
        lua_setfield(L, -2, "__index");

        lua_pushcfunction(L, l_visplane_newindex);
        lua_setfield(L, -2, "__newindex");
    }
    lua_pop(L, 1);

    if (luaL_newmetatable(L, VISPLANE_SPAN_MT)) {
        lua_pushcfunction(L, l_visplane_span_index);
        lua_setfield(L, -2, "__index");

        lua_pushcfunction(L, l_visplane_span_newindex);
        lua_setfield(L, -2, "__newindex");
    }
    lua_pop(L, 1);
}

/*
 * Cria um Visplane.
 *
 * Os arrays top e bottom são inicializados com:
 * top    = 255
 * bottom = 0
 */
static Visplane *new_visplane(
    lua_State *L,
    int height,
    int picnum,
    int lightlevel,
    int minx,
    int maxx
)
{
    create_visplane_metatables(L);

    Visplane *pl = (Visplane *)lua_newuserdatauv(
        L, sizeof(Visplane), 1
    );

    pl->height = height;
    pl->picnum = picnum;
    pl->lightlevel = lightlevel;
    pl->minx = minx;
    pl->maxx = maxx;

    for (int x = 0; x < RENDER_SCREENWIDTH; x++) {
        pl->top[x] = 255;
        pl->bottom[x] = 0;
    }

    luaL_getmetatable(L, VISPLANE_MT);
    lua_setmetatable(L, -2);

    /* Uservalue 1 guarda os proxies top e bottom. */
    lua_newtable(L);

    VisplaneSpan *top = (VisplaneSpan *)lua_newuserdatauv(
        L, sizeof(VisplaneSpan), 1
    );

    top->plane = pl;
    top->bottom = 0;

    luaL_getmetatable(L, VISPLANE_SPAN_MT);
    lua_setmetatable(L, -2);

    lua_pushvalue(L, -3);
    lua_setiuservalue(L, -2, 1);

    lua_setfield(L, -2, "top");

    VisplaneSpan *bottom = (VisplaneSpan *)lua_newuserdatauv(
        L, sizeof(VisplaneSpan), 1
    );

    bottom->plane = pl;
    bottom->bottom = 1;

    luaL_getmetatable(L, VISPLANE_SPAN_MT);
    lua_setmetatable(L, -2);

    lua_pushvalue(L, -3);
    lua_setiuservalue(L, -2, 1);

    lua_setfield(L, -2, "bottom");

    lua_setiuservalue(L, -2, 1);

    return pl;
}

/*
 * Adiciona o Visplane recém-criado ao array Lua visplanes.
 *
 * Argumentos:
 * 1 visplanes
 * 2 height
 * 3 picnum
 * 4 lightlevel
 * 5 minx
 * 6 maxx
 */
static void append_visplane(
    lua_State *L,
    int visplanes_index,
    int height,
    int picnum,
    int lightlevel,
    int minx,
    int maxx
)
{
    visplanes_index = lua_absindex(L, visplanes_index);

    new_visplane(
        L, height, picnum, lightlevel, minx, maxx
    );

    lua_Integer count = (lua_Integer)lua_rawlen(
        L, visplanes_index
    );

    /* Duplica para guardar na tabela e preservar o original como retorno. */
    lua_pushvalue(L, -1);
    lua_rawseti(L, visplanes_index, count + 1);
}

/*
 * render_c.find_plane(
 *     visplanes,
 *     viewwidth,
 *     skyflatnum,
 *     height,
 *     picnum,
 *     lightlevel
 * )
 */
static int l_find_plane(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    int viewwidth = (int)luaL_checkinteger(L, 2);
    int skyflatnum = (int)luaL_checkinteger(L, 3);

    int height = (int)luaL_checkinteger(L, 4);
    int picnum = (int)luaL_checkinteger(L, 5);
    int lightlevel = (int)luaL_checkinteger(L, 6);

    if (picnum == skyflatnum) {
        height = 0;
        lightlevel = 0;
    }

    size_t count = lua_rawlen(L, 1);

    for (size_t i = 1; i <= count; i++) {
        lua_rawgeti(L, 1, (lua_Integer)i);

        Visplane *pl = check_visplane(L, -1);

        if (pl->height == height &&
            pl->picnum == picnum &&
            pl->lightlevel == lightlevel) {

            lua_remove(L, -2);
            return 1;
        }

        lua_pop(L, 1);
    }

    append_visplane(
        L, 1,
        height,
        picnum,
        lightlevel,
        viewwidth,
        -1
    );

    return 1;
}

/*
 * render_c.check_plane(
 *     visplanes,
 *     pl,
 *     start,
 *     stop,
 *     viewwidth,
 *     skyflatnum
 * )
 */
static int l_check_plane(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    int start = (int)luaL_checkinteger(L, 3);
    int stop = (int)luaL_checkinteger(L, 4);
    int viewwidth = (int)luaL_checkinteger(L, 5);
    int skyflatnum = (int)luaL_checkinteger(L, 6);

    /* Mesmo comportamento do Lua: plano inexistente. */
    if (lua_isnil(L, 2)) {
        append_visplane(L, 1, 0, 0, 0, viewwidth, -1);

        return 1;
    }

    Visplane *pl = check_visplane(L, 2);

    int intrl, unionl, intrh, unionh;

    if (start < pl->minx) {
        intrl = pl->minx;
        unionl = start;
    } else {
        unionl = pl->minx;
        intrl = start;
    }

    if (stop > pl->maxx) {
        intrh = pl->maxx;
        unionh = stop;
    } else {
        unionh = pl->maxx;
        intrh = stop;
    }

    int x = intrl;

    while (x <= intrh) {
        if (x >= 0 &&
            x < RENDER_SCREENWIDTH &&
            pl->top[x] != 255) {
            break;
        }

        x++;
    }

    /* Não existe interseção: amplia o plano atual. */
    if (x > intrh) {
        pl->minx = unionl;
        pl->maxx = unionh;

        lua_pushvalue(L, 2);
        return 1;
    }

    /* Existe interseção: duplica o plano. */
    append_visplane(
        L, 1,
        pl->height,
        pl->picnum,
        pl->lightlevel,
        start,
        stop
    );

    (void)skyflatnum;

    return 1;
}

static void draw_column_pixels(
    Framebuffer *fb,
    lua_Integer dc_x,
    lua_Integer dc_yl,
    lua_Integer dc_yh,
    lua_Integer dc_iscale,
    lua_Integer dc_texturemid,
    const unsigned char *src,
    size_t slen,
    const unsigned char *cm,
    size_t cmlen,
    lua_Integer centery,
    lua_Integer viewwidth,
    lua_Integer detailshift,
    lua_Integer viewwindowx,
    lua_Integer viewwindowy)
{
    lua_Integer count = dc_yh - dc_yl;

    if (count < 0 || dc_x < 0 || dc_x >= viewwidth || slen == 0)
        return;

    lua_Integer yl = dc_yl;

    if (yl < 0)
        yl = 0;
    if (yl > SCREENHEIGHT - 1)
        yl = SCREENHEIGHT - 1;

    lua_Integer x;
    lua_Integer dest;
    lua_Integer dest2 = -1;

    if (detailshift != 0) {
        x = dc_x * 2;

        if (x < 0 || x + 1 >= SCREENWIDTH)
            return;

        dest = (yl + viewwindowy) * SCREENWIDTH + viewwindowx + x;
        dest2 = dest + 1;
    } else {
        x = dc_x;
        dest = (yl + viewwindowy) * SCREENWIDTH + viewwindowx + x;
    }

    int64_t fracstep = dc_iscale;
    int64_t frac =
        (int64_t)dc_texturemid +
        ((int64_t)dc_yl - centery) * fracstep;

    while (count >= 0 && dest < PIXELS) {
        int64_t shifted = arithmetic_shift_right(frac, FRACBITS);
        int idx = (int)(shifted & 127);

        unsigned char pix = src[(size_t)idx % slen];
        unsigned char val = pix;

        if (pix < cmlen)
            val = cm[pix];

        if (dest >= 0)
            fb->pixels[dest] = val;

        if (dest2 >= 0 && dest2 < PIXELS)
            fb->pixels[dest2] = val;

        dest += SCREENWIDTH;

        if (dest2 >= 0)
            dest2 += SCREENWIDTH;

        frac = as_i32(frac + fracstep);
        count--;
    }
}

/*
 * render_c.draw_masked_column(
 *   fb, posts, sprtopscreen, spryscale, mceil, mfloor,
 *   dc_x, dc_iscale, basemid, colormap,
 *   centery, viewwidth, viewheight,
 *   detailshift, viewwindowx, viewwindowy
 * )
 */
static int l_draw_masked_column(lua_State *L)
{
    Framebuffer *fb = (Framebuffer *)luaL_checkudata(L, 1, FB_MT);

    lua_Integer sprtopscreen = luaL_checkinteger(L, 3);
    lua_Integer spryscale = luaL_checkinteger(L, 4);
    lua_Integer mceil = luaL_checkinteger(L, 5);
    lua_Integer mfloor = luaL_checkinteger(L, 6);

    lua_Integer dc_x = luaL_checkinteger(L, 7);
    lua_Integer dc_iscale = luaL_checkinteger(L, 8);
    lua_Integer basemid = luaL_checkinteger(L, 9);

    size_t cmlen;
    const unsigned char *cm =
        (const unsigned char *)luaL_checklstring(L, 10, &cmlen);

    lua_Integer centery = luaL_checkinteger(L, 11);
    lua_Integer viewwidth = luaL_checkinteger(L, 12);
    lua_Integer viewheight = luaL_checkinteger(L, 13);
    lua_Integer detailshift = luaL_checkinteger(L, 14);
    lua_Integer viewwindowx = luaL_checkinteger(L, 15);
    lua_Integer viewwindowy = luaL_checkinteger(L, 16);

    luaL_checktype(L, 2, LUA_TTABLE);

    size_t post_count = lua_rawlen(L, 2);

    for (size_t p = 1; p <= post_count; p++) {
        lua_rawgeti(L, 2, (lua_Integer)p);
        int post_idx = lua_gettop(L);

        lua_getfield(L, post_idx, "topdelta");
        lua_Integer topdelta = luaL_checkinteger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, post_idx, "pixels");

        size_t pixels_len;
        const unsigned char *pixels =
            (const unsigned char *)luaL_checklstring(L, -1, &pixels_len);

        if (pixels_len == 0) {
            lua_settop(L, post_idx - 1);
            continue;
        }

        /*
         * Usa o cache post.col128, como a implementação Lua.
         * Se não existir, cria uma string de exatamente 128 bytes.
         */
        lua_getfield(L, post_idx, "col128");

        size_t src_len;
        const unsigned char *src;

        if (lua_isnil(L, -1)) {
            unsigned char buffer[128] = {0};

            size_t copy_len = pixels_len < 128 ? pixels_len : 128;
            memcpy(buffer, pixels, copy_len);

            lua_pop(L, 1);

            lua_pushlstring(L, (const char *)buffer, sizeof(buffer));
            lua_pushvalue(L, -1);
            lua_setfield(L, post_idx, "col128");

            src = (const unsigned char *)lua_tolstring(L, -1, &src_len);
        } else {
            src = (const unsigned char *)luaL_checklstring(L, -1, &src_len);
        }

        /*
         * Equivalente aos cálculos da implementação Lua.
         */
        int64_t topscreen =
            (int64_t)sprtopscreen + (int64_t)spryscale * topdelta;

        int64_t bottomscreen =
            topscreen + (int64_t)spryscale * (int64_t)pixels_len;

        lua_Integer yl = fixed_shr(
            topscreen + FRACUNIT - 1,
            FRACBITS
        );

        lua_Integer yh = fixed_shr(
            bottomscreen - 1,
            FRACBITS
        );

        if (yh >= mfloor)
            yh = mfloor - 1;

        if (yl <= mceil)
            yl = mceil + 1;

        if (yl < 0)
            yl = 0;

        if (yh >= viewheight)
            yh = viewheight - 1;

        if (yl <= yh) {
            lua_Integer texturemid =
                basemid - (lua_Integer)as_i32((int64_t)topdelta * FRACUNIT);

            draw_column_pixels(
                fb,
                dc_x,
                yl,
                yh,
                dc_iscale,
                texturemid,
                src,
                src_len,
                cm,
                cmlen,
                centery,
                viewwidth,
                detailshift,
                viewwindowx,
                viewwindowy
            );
        }

        lua_settop(L, post_idx - 1);
    }

    return 0;
}

/*
 * render_c.draw_column(
 *     fb,
 *     dc_x,
 *     dc_yl,
 *     dc_yh,
 *     dc_iscale,
 *     dc_texturemid,
 *     dc_source,
 *     dc_colormap,
 *     centery,
 *     viewwidth,
 *     detailshift,
 *     viewwindowx,
 *     viewwindowy
 * )
 */
static int l_draw_column(lua_State *L)
{
    Framebuffer *fb = (Framebuffer *)luaL_checkudata(
        L, 1, FB_MT
    );

    lua_Integer dc_x          = luaL_checkinteger(L, 2);
    lua_Integer dc_yl         = luaL_checkinteger(L, 3);
    lua_Integer dc_yh         = luaL_checkinteger(L, 4);
    lua_Integer dc_iscale     = luaL_checkinteger(L, 5);
    lua_Integer dc_texturemid = luaL_checkinteger(L, 6);

    size_t slen;
    size_t cmlen;

    const unsigned char *src = (const unsigned char *)
        luaL_checklstring(L, 7, &slen);

    const unsigned char *cm = (const unsigned char *)
        luaL_checklstring(L, 8, &cmlen);

    lua_Integer centery     = luaL_checkinteger(L, 9);
    lua_Integer viewwidth   = luaL_checkinteger(L, 10);
    lua_Integer detailshift = luaL_checkinteger(L, 11);
    lua_Integer viewwindowx = luaL_checkinteger(L, 12);
    lua_Integer viewwindowy = luaL_checkinteger(L, 13);

    draw_column_pixels(
    fb,
    dc_x,
    dc_yl,
    dc_yh,
    dc_iscale,
    dc_texturemid,
    src,
    slen,
    cm,
    cmlen,
    centery,
    viewwidth,
    detailshift,
    viewwindowx,
    viewwindowy);

    return 0;
}

#define FLAT_SIZE 4096
#define RENDER_FINEMASK 8191
#define RENDER_FINEANGLES 8192
#define RENDER_LIGHTZSHIFT 20
#define RENDER_MAXLIGHTZ 128
#define RENDER_NUMCOLORMAPS 32
#define RENDER_FINESINE_SIZE 10240

static lua_Integer render_table_int(
    lua_State *L,
    int table_index,
    lua_Integer key
) {
    table_index = lua_absindex(L, table_index);

    lua_pushinteger(L, key);
    lua_gettable(L, table_index);

    lua_Integer value = luaL_checkinteger(L, -1);
    lua_pop(L, 1);

    return value;
}

static int32_t render_fixed_mul(int32_t a, int32_t b)
{
    int64_t product = (int64_t)a * b;

    int64_t result = product / 65536;

    if (product < 0 && product % 65536 != 0)
        result--;

    return as_i32(result);
}

static int32_t render_shr(int32_t value, unsigned bits)
{
    int64_t divisor = (int64_t)1 << bits;
    int64_t result = value / divisor;

    if (value < 0 && value % divisor != 0)
        result--;

    return (int32_t)result;
}

static void render_put_pixel(
    Framebuffer *fb,
    int64_t offset,
    uint8_t value
) {
    if (offset >= 0 && offset < FB_PIXELS)
        fb->pixels[offset] = value;
}

static int l_draw_flat_plane(lua_State *L)
{
    Framebuffer *fb =
        (Framebuffer *)luaL_checkudata(L, 1, FB_MT);

    size_t flat_len, sine_len;

    const uint8_t *flat = (const uint8_t *)
        luaL_checklstring(L, 2, &flat_len);

    const char *sine_data =
        luaL_checklstring(L, 3, &sine_len);

    luaL_argcheck(L, flat_len >= FLAT_SIZE, 2,
                  "flat must contain 4096 bytes");

    luaL_argcheck(
        L,
        sine_len == RENDER_FINESINE_SIZE * sizeof(int32_t),
        3,
        "invalid finesine data"
    );

    int32_t finesine[RENDER_FINESINE_SIZE];

    memcpy(finesine, sine_data, sizeof(finesine));

    int top_table = lua_absindex(L, 4);
    int bottom_table = lua_absindex(L, 5);
    int xtoviewangle_table = lua_absindex(L, 6);
    int yslope_table = lua_absindex(L, 7);
    int distscale_table = lua_absindex(L, 8);
    int planezlight_table = lua_absindex(L, 9);
    int colormaps_table = lua_absindex(L, 10);
    int ylookup_table = lua_absindex(L, 11);
    int columnofs_table = lua_absindex(L, 12);

    int minx = (int)luaL_checkinteger(L, 13);
    int maxx = (int)luaL_checkinteger(L, 14);

    int32_t planeheight = (int32_t)luaL_checkinteger(L, 15);
    int32_t viewx = (int32_t)luaL_checkinteger(L, 16);
    int32_t viewy = (int32_t)luaL_checkinteger(L, 17);

    uint32_t viewangle =
        (uint32_t)luaL_checkinteger(L, 18);

    int viewwidth = (int)luaL_checkinteger(L, 19);
    int viewheight = (int)luaL_checkinteger(L, 20);
    int detailshift = (int)luaL_checkinteger(L, 21);

    const uint8_t *fixedcolormap = NULL;
    size_t fixedcolormap_len = 0;

    if (!lua_isnil(L, 22)) {
        fixedcolormap = (const uint8_t *)
            luaL_checklstring(L, 22, &fixedcolormap_len);
    }

    if (planeheight == 0)
        return 0;

    /*
     * Mantém as strings de colormap referenciadas
     * pela tabela recebida como argumento.
     */
    const uint8_t *colormaps[RENDER_NUMCOLORMAPS];
    size_t colormap_lengths[RENDER_NUMCOLORMAPS];

    for (int i = 0; i < RENDER_NUMCOLORMAPS; i++) {
        lua_rawgeti(L, colormaps_table, i + 1);

        colormaps[i] = (const uint8_t *)
            luaL_checklstring(L, -1, &colormap_lengths[i]);

        lua_pop(L, 1);
    }

    if (minx < 0)
        minx = 0;

    if (maxx >= viewwidth)
        maxx = viewwidth - 1;

    int cached_y = -1;
    int light_index = -1;

    int32_t distance = 0;

    const uint8_t *cm = NULL;
    size_t cmlen = 0;

    if (fixedcolormap) {
        cm = fixedcolormap;
        cmlen = fixedcolormap_len;
    }

    for (int x = minx; x <= maxx; x++) {
        int t1 = (int)render_table_int(L, top_table, x);
        int b1 = (int)render_table_int(L, bottom_table, x);

        if (t1 > b1 || t1 == 255)
            continue;

        int y1 = b1;

        if (y1 >= viewheight)
            y1 = viewheight - 1;

        int32_t xtoviewangle = (int32_t)
            render_table_int(L, xtoviewangle_table, x);

        int32_t distscale = (int32_t)
            render_table_int(L, distscale_table, x);

        uint32_t angle =
            (viewangle + (uint32_t)xtoviewangle);

        int ang = (angle >> 19) & RENDER_FINEMASK;

        for (int y = t1; y <= y1; y++) {
            if (y != cached_y) {
                cached_y = y;

                int32_t yslope = (int32_t)
                    render_table_int(L, yslope_table, y);

                distance = render_fixed_mul(
                    planeheight,
                    yslope
                );
            }

            int32_t length = render_fixed_mul(
                distance,
                distscale
            );

            int32_t ds_xfrac = as_i32(
                (int64_t)viewx +
                render_fixed_mul(
                    finesine[(ang + RENDER_FINEANGLES / 4)
                             & RENDER_FINEMASK],
                    length
                )
            );

            int32_t ds_yfrac = as_i32(
                -(int64_t)viewy -
                render_fixed_mul(finesine[ang], length)
            );

            uint32_t index =
                ((uint32_t)distance >> RENDER_LIGHTZSHIFT);

            if (index >= RENDER_MAXLIGHTZ)
                index = RENDER_MAXLIGHTZ - 1;

            if (!fixedcolormap && (int)index != light_index) {
                light_index = (int)index;

                int level = (int)render_table_int(
                    L,
                    planezlight_table,
                    index
                );

                if (level < 0)
                    level = 0;

                if (level >= RENDER_NUMCOLORMAPS)
                    level = RENDER_NUMCOLORMAPS - 1;

                cm = colormaps[level];
                cmlen = colormap_lengths[level];
            }

            uint32_t spot =
                ((uint32_t)render_shr(ds_xfrac, 16) & 63)
                |
                ((uint32_t)render_shr(ds_yfrac, 10) & 4032);

            uint8_t pix = flat[spot];

            uint8_t value = pix;

            if (pix < cmlen)
                value = cm[pix];

            int64_t yoffset =
                render_table_int(L, ylookup_table, y);

            if (detailshift != 0) {
                int xx = x << 1;

                int64_t xoffset =
                    render_table_int(L, columnofs_table, xx);

                int64_t offset = yoffset + xoffset;

                render_put_pixel(fb, offset, value);
                render_put_pixel(fb, offset + 1, value);
            } else {
                int64_t xoffset =
                    render_table_int(L, columnofs_table, x);

                render_put_pixel(
                    fb,
                    yoffset + xoffset,
                    value
                );
            }
        }
    }

    return 0;
}

static int l_draw_sky_plane(lua_State *L)
{
    Framebuffer *fb = (Framebuffer *)luaL_checkudata(
        L, 1, FB_MT
    );

    int resource_idx = lua_absindex(L, 2);
    int top_idx = lua_absindex(L, 3);
    int bottom_idx = lua_absindex(L, 4);
    int xtoviewangle_idx = lua_absindex(L, 5);

    uint32_t viewangle =
        (uint32_t)luaL_checkinteger(L, 6);

    int minx = (int)luaL_checkinteger(L, 7);
    int maxx = (int)luaL_checkinteger(L, 8);

    lua_Integer centery = luaL_checkinteger(L, 9);
    lua_Integer viewwidth = luaL_checkinteger(L, 10);
    lua_Integer detailshift = luaL_checkinteger(L, 11);
    lua_Integer viewwindowx = luaL_checkinteger(L, 12);
    lua_Integer viewwindowy = luaL_checkinteger(L, 13);

    /*
     * Obtém o índice da textura SKY1.
     * resource:skytexture()
     */
    lua_getfield(L, resource_idx, "skytexture");
    lua_pushvalue(L, resource_idx);
    lua_call(L, 1, 1);

    lua_Integer skytexture = luaL_checkinteger(L, -1);
    lua_pop(L, 1);

    /*
     * Obtém a colormap do céu.
     * resource:colormap(0)
     */
    lua_getfield(L, resource_idx, "colormap");
    lua_pushvalue(L, resource_idx);
    lua_pushinteger(L, 0);
    lua_call(L, 2, 1);

    size_t cm_len;
    const uint8_t *cm = (const uint8_t *)
        luaL_checklstring(L, -1, &cm_len);

    /*
     * Parâmetros equivalentes à implementação Lua.
     */
    const lua_Integer dc_iscale =
        (9 * FRACUNIT) / 10;

    const lua_Integer dc_texturemid =
        100 * FRACUNIT;

    for (int x = minx; x <= maxx; x++) {
        lua_Integer yl = render_table_int(
            L, top_idx, x
        );

        lua_Integer yh = render_table_int(
            L, bottom_idx, x
        );

        if (yl > yh || yl >= 255)
            continue;

        lua_Integer xtoviewangle = render_table_int(
            L, xtoviewangle_idx, x
        );

        uint32_t angle =
            viewangle + (uint32_t)xtoviewangle;

        lua_Integer ang = angle >> ANGLETOSKYSHIFT;

        /*
         * Obtém a coluna da textura:
         * resource:get_column(skytexture, ang)
         */
        lua_getfield(L, resource_idx, "get_column");
        lua_pushvalue(L, resource_idx);
        lua_pushinteger(L, skytexture);
        lua_pushinteger(L, ang);
        lua_call(L, 3, 1);

        size_t source_len;
        const uint8_t *source = (const uint8_t *)
            luaL_checklstring(L, -1, &source_len);

        draw_column_pixels(
            fb,
            x,
            yl,
            yh,
            dc_iscale,
            dc_texturemid,
            source,
            source_len,
            cm,
            cm_len,
            centery,
            viewwidth,
            detailshift,
            viewwindowx,
            viewwindowy
        );

        lua_pop(L, 1);
    }

    lua_pop(L, 1); /* colormap */

    return 0;
}

static int l_draw_planes(lua_State *L)
{
    int self = lua_absindex(L, 1);
    int finesine = lua_absindex(L, 2);

    lua_getfield(L, self, "visplanes");
    int visplanes = lua_absindex(L, -1);

    lua_getfield(L, self, "res");
    int res = lua_absindex(L, -1);

    lua_getfield(L, self, "fb");
    int fb = lua_absindex(L, -1);

    lua_Integer count = (lua_Integer)lua_rawlen(L, visplanes);

    for (lua_Integer p = 1; p <= count; p++) {
        lua_rawgeti(L, visplanes, p);
        int pl = lua_absindex(L, -1);

        Visplane *plane = check_visplane(L, pl);

        if (plane->minx > plane->maxx) {
            lua_pop(L, 1);
            continue;
        }

        int minx = plane->minx;
        int maxx = plane->maxx;

        /*
         * if pl.picnum == self.res:skyflatnum()
         */
        lua_getfield(L, res, "skyflatnum");
        lua_pushvalue(L, res);
        lua_call(L, 1, 1);

        lua_Integer skyflatnum = luaL_checkinteger(L, -1);
        lua_pop(L, 1);

        if (plane->picnum == skyflatnum) {
            /*
             * render_c.draw_sky_plane(
             *     fb, res, top, bottom, xtoviewangle,
             *     viewangle, minx, maxx, centery,
             *     viewwidth, detailshift, viewwindowx,
             *     viewwindowy
             * )
             */

            lua_pushcfunction(L, l_draw_sky_plane);

            lua_pushvalue(L, fb);
            lua_pushvalue(L, res);

            lua_getfield(L, pl, "top");
            lua_getfield(L, pl, "bottom");

            lua_getfield(L, self, "xtoviewangle");
            lua_getfield(L, self, "viewangle");

            lua_pushinteger(L, minx);
            lua_pushinteger(L, maxx);

            lua_getfield(L, self, "centery");
            lua_getfield(L, self, "viewwidth");
            lua_getfield(L, self, "detailshift");
            lua_getfield(L, self, "viewwindowx");
            lua_getfield(L, self, "viewwindowy");

            lua_call(L, 13, 0);
        } else {
            /*
             * local light = ushr(pl.lightlevel, 4)
             *              + self.extralight
             */

            int64_t light =
                ((uint32_t)plane->lightlevel >> 4);

            lua_getfield(L, self, "extralight");
            light += luaL_checkinteger(L, -1);
            lua_pop(L, 1);

            if (light < 0)
                light = 0;

            if (light > LIGHTLEVELS - 1)
                light = LIGHTLEVELS - 1;

            /*
             * local planezlight = self.zlight[light]
             */
            lua_getfield(L, self, "zlight");
            int zlight_table = lua_absindex(L, -1);

            lua_geti(L, zlight_table, (lua_Integer)light);
            lua_remove(L, zlight_table);

            int planezlight = lua_absindex(L, -1);

            /*
             * local flat = self.res:flat_pixels(pl.picnum)
             */
            lua_getfield(L, res, "flat_pixels");
            lua_pushvalue(L, res);
            lua_pushinteger(L, plane->picnum);
            lua_call(L, 2, 1);

            int flat = lua_absindex(L, -1);

            /*
             * local planeheight =
             *     abs_fixed(pl.height - self.viewz)
             */
            lua_getfield(L, self, "viewz");
            int32_t viewz = (int32_t)luaL_checkinteger(L, -1);
            lua_pop(L, 1);

            int32_t delta = as_i32(
                (int64_t)plane->height - viewz
            );

            int64_t planeheight = delta < 0
                ? -(int64_t)delta
                : delta;

            if (planeheight != 0) {
                /*
                 * local colormaps = {}
                 *
                 * for i = 0, NUMCOLORMAPS - 1 do
                 *     colormaps[i + 1] = self.res:colormap(i)
                 * end
                 */
                lua_newtable(L);
                int colormaps = lua_absindex(L, -1);

                for (int i = 0; i < NUMCOLORMAPS; i++) {
                    lua_getfield(L, res, "colormap");
                    lua_pushvalue(L, res);
                    lua_pushinteger(L, i);
                    lua_call(L, 2, 1);

                    lua_rawseti(L, colormaps, i + 1);
                }

                /*
                 * render_c.draw_flat_plane(
                 *     fb, flat, finesine,
                 *     top, bottom,
                 *     xtoviewangle, yslope, distscale,
                 *     planezlight, colormaps,
                 *     ylookup, columnofs,
                 *     minx, maxx, planeheight,
                 *     viewx, viewy, viewangle,
                 *     viewwidth, viewheight,
                 *     detailshift, fixedcolormap
                 * )
                 */

                lua_pushcfunction(L, l_draw_flat_plane);

                lua_pushvalue(L, fb);
                lua_pushvalue(L, flat);
                lua_pushvalue(L, finesine);

                lua_getfield(L, pl, "top");
                lua_getfield(L, pl, "bottom");

                lua_getfield(L, self, "xtoviewangle");
                lua_getfield(L, self, "yslope");
                lua_getfield(L, self, "distscale");

                lua_pushvalue(L, planezlight);
                lua_pushvalue(L, colormaps);

                lua_getfield(L, self, "ylookup");
                lua_getfield(L, self, "columnofs");

                lua_pushinteger(L, minx);
                lua_pushinteger(L, maxx);
                lua_pushinteger(L, planeheight);

                lua_getfield(L, self, "viewx");
                lua_getfield(L, self, "viewy");
                lua_getfield(L, self, "viewangle");

                lua_getfield(L, self, "viewwidth");
                lua_getfield(L, self, "viewheight");
                lua_getfield(L, self, "detailshift");

                lua_getfield(L, self, "fixedcolormap");

                lua_call(L, 22, 0);

                lua_pop(L, 1); /* colormaps */
            }

            lua_pop(L, 2); /* flat e planezlight */
        }

        lua_pop(L, 1); /* pl */
    }

    return 0;
}


static lua_Integer render_get_int_field(
    lua_State *L,
    int object,
    const char *field
)
{
    object = lua_absindex(L, object);
    lua_getfield(L, object, field);
    lua_Integer value = luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    return value;
}

static int render_get_bool_field(
    lua_State *L,
    int object,
    const char *field
)
{
    object = lua_absindex(L, object);
    lua_getfield(L, object, field);
    int value = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return value;
}

static void render_set_int_field(
    lua_State *L,
    int object,
    const char *field,
    lua_Integer value
)
{
    object = lua_absindex(L, object);
    lua_pushinteger(L, value);
    lua_setfield(L, object, field);
}

static void render_set_table_int(
    lua_State *L,
    int table,
    lua_Integer key,
    lua_Integer value
)
{
    table = lua_absindex(L, table);

    lua_pushinteger(L, key);
    lua_pushinteger(L, value);
    lua_settable(L, table);
}

static void render_set_visplane_span(
    lua_State *L,
    Visplane *plane,
    int bottom,
    int x,
    lua_Integer value
)
{
    if (value < INT16_MIN || value > INT16_MAX) {
        luaL_error(
            L,
            "visplane span value out of int16 range"
        );
        return;
    }

    if (x < 0 || x >= RENDER_SCREENWIDTH) {
    luaL_error(L, "visplane span index out of range");
    return;
}

    if (bottom)
        plane->bottom[x] = (int16_t)value;
    else
        plane->top[x] = (int16_t)value;
}

/*
 * Chama res:get_column(texture, column).
 * Deixa a string retornada no topo da pilha.
 */
static void render_get_column(
    lua_State *L,
    int res,
    lua_Integer texture,
    lua_Integer column
)
{
    res = lua_absindex(L, res);

    lua_getfield(L, res, "get_column");
    lua_pushvalue(L, res);
    lua_pushinteger(L, texture);
    lua_pushinteger(L, column);
    lua_call(L, 3, 1);
}

/*
 * Chama l_draw_column usando os campos atuais do renderer.
 */
static void render_call_draw_column(
    lua_State *L,
    int self,
    int fb
)
{
    self = lua_absindex(L, self);
    fb = lua_absindex(L, fb);

    lua_pushcfunction(L, l_draw_column);

    lua_pushvalue(L, fb);

    lua_getfield(L, self, "dc_x");
    lua_getfield(L, self, "dc_yl");
    lua_getfield(L, self, "dc_yh");
    lua_getfield(L, self, "dc_iscale");
    lua_getfield(L, self, "dc_texturemid");
    lua_getfield(L, self, "dc_source");
    lua_getfield(L, self, "dc_colormap");

    lua_getfield(L, self, "centery");
    lua_getfield(L, self, "viewwidth");
    lua_getfield(L, self, "detailshift");
    lua_getfield(L, self, "viewwindowx");
    lua_getfield(L, self, "viewwindowy");

    lua_call(L, 13, 0);
}

/*
 * render_c.render_seg_loop(self)
 *
 * Migração de render_seg_loop para C.
 */
static int l_render_seg_loop(lua_State *L)
{
    int self = lua_absindex(L, 1);
    int tables_idx = lua_absindex(L, 2);

    luaL_checktype(L, self, LUA_TTABLE);

    Table *tables = (Table *)luaL_checkudata(
        L, tables_idx, TABLE_MT
    );

    luaL_argcheck(
        L, tables->ready, 2, "tables not initialized"
    );

    /* Recursos e framebuffer. */
    lua_getfield(L, self, "res");
    int res = lua_absindex(L, -1);

    lua_getfield(L, self, "fb");
    int fb = lua_absindex(L, -1);

    /* Tabelas utilizadas no loop. */
    lua_getfield(L, self, "ceilingclip");
    int ceilingclip = lua_absindex(L, -1);

    lua_getfield(L, self, "floorclip");
    int floorclip = lua_absindex(L, -1);

    lua_getfield(L, self, "xtoviewangle");
    int xtoviewangle_table = lua_absindex(L, -1);

    lua_getfield(L, self, "walllights");
    int walllights = lua_absindex(L, -1);

    lua_getfield(L, self, "maskedtexturecol");
    int maskedtexturecol = lua_absindex(L, -1);

    /* Planos utilizados para marcar teto e chão. */
    lua_getfield(L, self, "ceilingplane");
    int ceilingplane_idx = lua_absindex(L, -1);

    lua_getfield(L, self, "floorplane");
    int floorplane_idx = lua_absindex(L, -1);

    Visplane *ceilingplane = NULL;
    Visplane *floorplane = NULL;

    if (!lua_isnil(L, ceilingplane_idx))
        ceilingplane = check_visplane(L, ceilingplane_idx);

    if (!lua_isnil(L, floorplane_idx))
        floorplane = check_visplane(L, floorplane_idx);


    /* Estado inicial do loop. */
    lua_Integer rw_x =
        render_get_int_field(L, self, "rw_x");

    lua_Integer rw_stopx =
        render_get_int_field(L, self, "rw_stopx");

    lua_Integer rw_start =
        render_get_int_field(L, self, "rw_start");

    lua_Integer rw_distance =
        render_get_int_field(L, self, "rw_distance");

    lua_Integer rw_scale =
        render_get_int_field(L, self, "rw_scale");

    lua_Integer rw_scalestep =
        render_get_int_field(L, self, "rw_scalestep");

    lua_Integer topfrac =
        render_get_int_field(L, self, "topfrac");

    lua_Integer topstep =
        render_get_int_field(L, self, "topstep");

    lua_Integer bottomfrac =
        render_get_int_field(L, self, "bottomfrac");

    lua_Integer bottomstep =
        render_get_int_field(L, self, "bottomstep");

    lua_Integer viewheight =
        render_get_int_field(L, self, "viewheight");

    int segtextured =
        render_get_bool_field(L, self, "segtextured");

    int markceiling =
        render_get_bool_field(L, self, "markceiling");

    int markfloor =
        render_get_bool_field(L, self, "markfloor");

    lua_Integer midtexture =
        render_get_int_field(L, self, "midtexture");

    lua_Integer toptexture =
        render_get_int_field(L, self, "toptexture");

    lua_Integer bottomtexture =
        render_get_int_field(L, self, "bottomtexture");

    int has_maskedtexture =
    render_get_bool_field(L, self, "maskedtexture");

    int has_maskedtexturecol =
        render_get_bool_field(L, self, "maskedtexturecol");

    lua_Integer detailshift =
        render_get_int_field(L, self, "detailshift");

    lua_Integer viewwidth =
        render_get_int_field(L, self, "viewwidth");

    lua_Integer centery =
        render_get_int_field(L, self, "centery");

    lua_Integer viewwindowx =
        render_get_int_field(L, self, "viewwindowx");

    lua_Integer viewwindowy =
        render_get_int_field(L, self, "viewwindowy");

    lua_Integer extralight =
        render_get_int_field(L, self, "extralight");

    lua_Integer fixedcolormap_idx;

    lua_getfield(L, self, "fixedcolormap");
    fixedcolormap_idx = lua_absindex(L, -1);

    lua_Integer texturecolumn = 0;
    lua_Integer rw_centerangle = 0;
    lua_Integer rw_offset = 0;

    if (segtextured) {
        rw_centerangle =
            render_get_int_field(L, self, "rw_centerangle");

        rw_offset =
            render_get_int_field(L, self, "rw_offset");
    }

    lua_Integer pixhigh = 0;
    lua_Integer pixhighstep = 0;
    lua_Integer pixlow = 0;
    lua_Integer pixlowstep = 0;

    if (toptexture != 0) {
        pixhigh = render_get_int_field(L, self, "pixhigh");
        pixhighstep = render_get_int_field(L, self, "pixhighstep");
    }

    if (bottomtexture != 0) {
        pixlow = render_get_int_field(L, self, "pixlow");
        pixlowstep = render_get_int_field(L, self, "pixlowstep");
    }

    lua_Integer rw_midtexturemid = 0;
    lua_Integer rw_toptexturemid = 0;
    lua_Integer rw_bottomtexturemid = 0;

    if (midtexture != 0) {
        rw_midtexturemid =
            render_get_int_field(L, self, "rw_midtexturemid");
    }

    if (toptexture != 0) {
        rw_toptexturemid =
            render_get_int_field(L, self, "rw_toptexturemid");
    }

    if (bottomtexture != 0) {
        rw_bottomtexturemid =
            render_get_int_field(L, self, "rw_bottomtexturemid");
    }

    int has_fixedcolormap =
        !lua_isnil(L, fixedcolormap_idx) &&
        lua_toboolean(L, fixedcolormap_idx);

    /*
     * Loop principal.
     */
    while (rw_x < rw_stopx) {
        int x = (int)rw_x;

        lua_Integer ceiling =
            render_table_int(L, ceilingclip, rw_x);

        lua_Integer floor =
            render_table_int(L, floorclip, rw_x);

        /*
         * yl = shar(topfrac + HEIGHTUNIT - 1, HEIGHTBITS)
         */
        lua_Integer yl = fixed_shr(
            topfrac + HEIGHTUNIT - 1,
            HEIGHTBITS
        );

        if (yl < ceiling + 1)
            yl = ceiling + 1;

        /*
         * Marca o teto no visplane.
         */
        if (markceiling && ceilingplane) {
            lua_Integer top = ceiling + 1;
            lua_Integer bottom = yl - 1;

            if (bottom >= floor)
                bottom = floor - 1;

            if (top <= bottom) {
                render_set_visplane_span(
                    L, ceilingplane, 0, x, top
                );

                render_set_visplane_span(
                    L, ceilingplane, 1, x, bottom
                );
            }
        }

        /*
         * yh = shar(bottomfrac, HEIGHTBITS)
         */
        lua_Integer yh = fixed_shr(
            bottomfrac,
            HEIGHTBITS
        );

        if (yh >= floor)
            yh = floor - 1;

        /*
         * Marca o chão no visplane.
         */
        if (markfloor && floorplane) {
            lua_Integer top = yh + 1;
            lua_Integer bottom = floor - 1;

            if (top <= ceiling)
                top = ceiling + 1;

            if (top <= bottom) {
                render_set_visplane_span(
                    L, floorplane, 0, x, top
                );

                render_set_visplane_span(
                    L, floorplane, 1, x, bottom
                );
            }
        }

        /*
         * Calcula coluna da textura e iluminação.
         */
        if (segtextured) {

            lua_Integer xtoviewangle =
                render_table_int(
                    L, xtoviewangle_table, rw_x
                );

            uint32_t angle = (uint32_t)as_i32(
                rw_centerangle + xtoviewangle
            );

            angle >>= ANGLETOFINESHIFT;
            angle &= (FINEANGLES / 2) - 1;

            /* Acesso direto ao array C. */
            int32_t tanv = tables->finetangent[angle];

            texturecolumn = fixed_shr(
                rw_offset -
                render_fixed_mul(tanv, (int32_t)rw_distance),
                FRACBITS
            );

            uint32_t light_index =
                (uint32_t)rw_scale >> LIGHTSCALESHIFT;

            if (light_index >= MAXLIGHTSCALE)
                light_index = MAXLIGHTSCALE - 1;

            if (has_fixedcolormap) {
                lua_pushvalue(L, fixedcolormap_idx);
                lua_setfield(L, self, "dc_colormap");
            } else {
                lua_Integer lightlevel = render_table_int(
                    L,
                    walllights,
                    light_index
                );

                lua_getfield(L, res, "colormap");
                lua_pushvalue(L, res);
                lua_pushinteger(L, lightlevel);
                lua_call(L, 2, 1);

                lua_setfield(L, self, "dc_colormap");
            }

            render_set_int_field(
                L, self, "dc_x", rw_x
            );

            lua_Integer iscale = 0;

            if (rw_scale != 0)
                iscale = 4294967295LL / rw_scale;

            render_set_int_field(
                L, self, "dc_iscale", iscale
            );
        }

        /*
         * Parede média: textura ocupa todo o intervalo.
         */
        if (midtexture != 0) {
            render_set_int_field(L, self, "dc_yl", yl);
            render_set_int_field(L, self, "dc_yh", yh);

            render_set_int_field(
                L, self, "dc_texturemid",
                rw_midtexturemid
            );

            render_get_column(
                L, res, midtexture, texturecolumn
            );

            lua_setfield(L, self, "dc_source");

            render_call_draw_column(L, self, fb);

            render_set_table_int(
                L, ceilingclip, rw_x, viewheight
            );

            render_set_table_int(
                L, floorclip, rw_x, -1
            );
        } else {
            /*
             * Textura superior.
             */
            if (toptexture != 0) {
                lua_Integer mid = fixed_shr(
                    pixhigh,
                    HEIGHTBITS
                );

                pixhigh += pixhighstep;

                if (mid >= floor)
                    mid = floor - 1;

                if (mid >= yl) {
                    render_set_int_field(
                        L, self, "dc_yl", yl
                    );

                    render_set_int_field(
                        L, self, "dc_yh", mid
                    );

                    render_set_int_field(
                        L, self, "dc_texturemid",
                        rw_toptexturemid
                    );

                    render_get_column(
                        L, res, toptexture, texturecolumn
                    );

                    lua_setfield(L, self, "dc_source");

                    render_call_draw_column(L, self, fb);

                    render_set_table_int(
                        L, ceilingclip, rw_x, mid
                    );
                } else {
                    render_set_table_int(
                        L, ceilingclip, rw_x, yl - 1
                    );
                }
            } else if (markceiling) {
                render_set_table_int(
                    L, ceilingclip, rw_x, yl - 1
                );
            }

            /*
             * Textura inferior.
             */
            if (bottomtexture != 0) {
                lua_Integer mid = fixed_shr(
                    pixlow + HEIGHTUNIT - 1,
                    HEIGHTBITS
                );

                pixlow += pixlowstep;

                lua_Integer current_ceiling =
                    render_table_int(L, ceilingclip, rw_x);

                if (mid <= current_ceiling)
                    mid = current_ceiling + 1;

                if (mid <= yh) {
                    render_set_int_field(
                        L, self, "dc_yl", mid
                    );

                    render_set_int_field(
                        L, self, "dc_yh", yh
                    );

                    render_set_int_field(
                        L, self, "dc_texturemid",
                        rw_bottomtexturemid
                    );

                    render_get_column(
                        L, res, bottomtexture, texturecolumn
                    );

                    lua_setfield(L, self, "dc_source");

                    render_call_draw_column(L, self, fb);

                    render_set_table_int(
                        L, floorclip, rw_x, mid
                    );
                } else {
                    render_set_table_int(
                        L, floorclip, rw_x, yh + 1
                    );
                }
            } else if (markfloor) {
                render_set_table_int(
                    L, floorclip, rw_x, yh + 1
                );
            }

            /*
             * Armazena a coluna da textura mascarada.
             */
            if (has_maskedtexture && has_maskedtexturecol) {

                render_set_table_int(
                    L,
                    maskedtexturecol,
                    rw_x - rw_start,
                    texturecolumn
                );
            }
        }

        /*
         * Avança para a próxima coluna.
         */
        rw_scale += rw_scalestep;
        topfrac += topstep;
        bottomfrac += bottomstep;
        rw_x++;
    }

    /*
     * Persiste os valores atualizados no renderer.
     */
    render_set_int_field(L, self, "rw_x", rw_x);
    render_set_int_field(L, self, "rw_scale", rw_scale);
    render_set_int_field(L, self, "topfrac", topfrac);
    render_set_int_field(L, self, "bottomfrac", bottomfrac);
    render_set_int_field(L, self, "pixhigh", pixhigh);
    render_set_int_field(L, self, "pixlow", pixlow);

    return 0;
}

/* ---------------------------------------------------------
 * Registro do módulo
 * --------------------------------------------------------- */

static const luaL_Reg render_functions[] = {
    {"draw_column", l_draw_column},
    {"draw_masked_column", l_draw_masked_column},
    {"draw_flat_plane", l_draw_flat_plane},
    {"draw_sky_plane", l_draw_sky_plane},
    {"find_plane", l_find_plane},
    {"check_plane", l_check_plane},
    {"draw_planes", l_draw_planes},
    {"render_seg_loop", l_render_seg_loop},
    {NULL, NULL}
};

int luaopen_render_c(lua_State *L)
{
    luaL_newlib(L, render_functions);
    return 1;
}