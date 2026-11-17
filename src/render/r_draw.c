/* r_draw.c: desenho de colunas de parede, ceu e texturas mascaradas. */
#include <string.h>

#include "r_local.h"

void r_draw_column_pixels(Framebuffer *fb, lnum dc_x, lnum dc_yl, lnum dc_yh,
                          lnum dc_iscale, lnum dc_texturemid,
                          const uint8_t *src, size_t slen,
                          const uint8_t *cm, size_t cmlen,
                          lnum centery, lnum viewwidth, lnum detailshift,
                          lnum viewwindowx, lnum viewwindowy)
{
    lnum count = dc_yh - dc_yl;
    if (count < 0 || dc_x < 0 || dc_x >= viewwidth || slen == 0)
        return;

    lnum yl = dc_yl;
    if (yl < 0) yl = 0;
    if (yl > SCREENHEIGHT - 1) yl = SCREENHEIGHT - 1;

    lnum dest, dest2 = -1;
    if (detailshift != 0) {
        lnum x = dc_x * 2;
        if (x < 0 || x + 1 >= SCREENWIDTH)
            return;
        dest = (yl + viewwindowy) * SCREENWIDTH + viewwindowx + x;
        dest2 = dest + 1;
    } else {
        dest = (yl + viewwindowy) * SCREENWIDTH + viewwindowx + dc_x;
    }

    lnum fracstep = dc_iscale;
    lnum frac = dc_texturemid + (dc_yl - centery) * fracstep;
    uint8_t *pixels = fb->pixels;

    while (count >= 0 && dest < PIXELS) {
        int idx = (int)((frac >> FRACBITS) & 127);
        uint8_t pix = src[(size_t)idx % slen];
        uint8_t val = pix < cmlen ? cm[pix] : pix;
        if (dest >= 0)
            pixels[dest] = val;
        if (dest2 >= 0 && dest2 < PIXELS)
            pixels[dest2] = val;
        dest += SCREENWIDTH;
        if (dest2 >= 0)
            dest2 += SCREENWIDTH;
        frac = r_i32(frac + fracstep);
        count--;
    }
}

void r_draw_masked_post(Framebuffer *fb, int topdelta, const uint8_t *pixels,
                        size_t pixels_len, lnum sprtopscreen, lnum spryscale,
                        lnum mceil, lnum mfloor, lnum dc_x, lnum dc_iscale,
                        lnum basemid, const uint8_t *cm, size_t cmlen,
                        lnum centery, lnum viewwidth, lnum viewheight,
                        lnum detailshift, lnum viewwindowx, lnum viewwindowy)
{
    if (pixels_len == 0)
        return;

    lnum topscreen = sprtopscreen + spryscale * topdelta;
    lnum bottomscreen = topscreen + spryscale * (lnum)pixels_len;
    lnum yl = r_shar(topscreen + FRACUNIT - 1, FRACBITS);
    lnum yh = r_shar(bottomscreen - 1, FRACBITS);

    if (yh >= mfloor) yh = mfloor - 1;
    if (yl <= mceil) yl = mceil + 1;
    if (yl < 0) yl = 0;
    if (yh >= viewheight) yh = viewheight - 1;
    if (yl > yh)
        return;

    /* A coluna e lida com indice & 127: pixels alem do post valem 0. */
    uint8_t col128[128];
    size_t n = pixels_len < 128 ? pixels_len : 128;
    memcpy(col128, pixels, n);
    if (n < 128)
        memset(col128 + n, 0, 128 - n);

    lnum texturemid = basemid - r_i32((lnum)topdelta * FRACUNIT);
    r_draw_column_pixels(fb, dc_x, yl, yh, dc_iscale, texturemid,
                         col128, sizeof(col128), cm, cmlen,
                         centery, viewwidth, detailshift,
                         viewwindowx, viewwindowy);
}

/* ------------------------------------------------- bindings de baixo nivel */

/*
 * render_c.draw_column(fb, dc_x, dc_yl, dc_yh, dc_iscale, dc_texturemid,
 *                      source, colormap, centery, viewwidth, detailshift,
 *                      viewwindowx, viewwindowy)
 */
static int l_draw_column(lua_State *L)
{
    Framebuffer *fb = (Framebuffer *)luaL_checkudata(L, 1, FB_MT);
    size_t slen, cmlen;
    const uint8_t *src = (const uint8_t *)luaL_checklstring(L, 7, &slen);
    const uint8_t *cm = (const uint8_t *)luaL_checklstring(L, 8, &cmlen);
    r_draw_column_pixels(fb,
        luaL_checkinteger(L, 2), luaL_checkinteger(L, 3),
        luaL_checkinteger(L, 4), luaL_checkinteger(L, 5),
        luaL_checkinteger(L, 6), src, slen, cm, cmlen,
        luaL_checkinteger(L, 9), luaL_checkinteger(L, 10),
        luaL_checkinteger(L, 11), luaL_checkinteger(L, 12),
        luaL_checkinteger(L, 13));
    return 0;
}

/*
 * render_c.draw_masked_column(fb, posts, sprtopscreen, spryscale, mceil,
 *   mfloor, dc_x, dc_iscale, basemid, colormap, centery, viewwidth,
 *   viewheight, detailshift, viewwindowx, viewwindowy)
 * posts = { {topdelta=, pixels=}, ... }
 */
static int l_draw_masked_column(lua_State *L)
{
    Framebuffer *fb = (Framebuffer *)luaL_checkudata(L, 1, FB_MT);
    luaL_checktype(L, 2, LUA_TTABLE);
    size_t cmlen;
    const uint8_t *cm = (const uint8_t *)luaL_checklstring(L, 10, &cmlen);
    lnum sprtopscreen = luaL_checkinteger(L, 3);
    lnum spryscale = luaL_checkinteger(L, 4);
    lnum mceil = luaL_checkinteger(L, 5);
    lnum mfloor = luaL_checkinteger(L, 6);
    lnum dc_x = luaL_checkinteger(L, 7);
    lnum dc_iscale = luaL_checkinteger(L, 8);
    lnum basemid = luaL_checkinteger(L, 9);
    lnum centery = luaL_checkinteger(L, 11);
    lnum viewwidth = luaL_checkinteger(L, 12);
    lnum viewheight = luaL_checkinteger(L, 13);
    lnum detailshift = luaL_checkinteger(L, 14);
    lnum viewwindowx = luaL_checkinteger(L, 15);
    lnum viewwindowy = luaL_checkinteger(L, 16);

    size_t count = lua_rawlen(L, 2);
    for (size_t p = 1; p <= count; p++) {
        lua_rawgeti(L, 2, (lua_Integer)p);
        lua_getfield(L, -1, "topdelta");
        int topdelta = (int)luaL_checkinteger(L, -1);
        lua_getfield(L, -2, "pixels");
        size_t len;
        const uint8_t *pix = (const uint8_t *)luaL_checklstring(L, -1, &len);
        r_draw_masked_post(fb, topdelta, pix, len, sprtopscreen, spryscale,
                           mceil, mfloor, dc_x, dc_iscale, basemid, cm, cmlen,
                           centery, viewwidth, viewheight, detailshift,
                           viewwindowx, viewwindowy);
        lua_pop(L, 3);
    }
    return 0;
}

int r_draw_lua_register(lua_State *L)
{
    lua_pushcfunction(L, l_draw_column);
    lua_setfield(L, -2, "draw_column");
    lua_pushcfunction(L, l_draw_masked_column);
    lua_setfield(L, -2, "draw_masked_column");
    return 0;
}
