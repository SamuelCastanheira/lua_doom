#include <lua.h>
#include <lauxlib.h>
#include <string.h>

#include <stdint.h>
#include <stddef.h>

#include "framebuffer.h"

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
    lua_rawget(L, table_index);

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

/* ---------------------------------------------------------
 * Registro do módulo
 * --------------------------------------------------------- */

static const luaL_Reg render_functions[] = {
    {"draw_column", l_draw_column},
    {"draw_masked_column", l_draw_masked_column},
    {"draw_flat_plane", l_draw_flat_plane},
    {NULL, NULL}
};

int luaopen_render_c(lua_State *L)
{
    luaL_newlib(L, render_functions);
    return 1;
}