/*
 * v_draw.c: desenho 2D no framebuffer (equivalente ao v_video.c do Doom).
 *
 * Metodos do userdata Framebuffer, usados por v_video.lua, am_map.lua,
 * finale.lua e wipe.lua. Cada funcao reproduz exatamente a versao Lua que
 * substituiu (mesmos limites, mesma ordem de escrita); a equivalencia e
 * verificada por tests/test_v_draw.lua.
 */
#include <lauxlib.h>
#include <lua.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

#include "framebuffer.h"

static Framebuffer *check_fb(lua_State *L, int idx)
{
    return (Framebuffer *)luaL_checkudata(L, idx, FB_MT);
}

/* Inteiro Lua ou float (arredondado para baixo, como math.floor). */
static lua_Integer arg_floor(lua_State *L, int idx)
{
    if (lua_isinteger(L, idx))
        return lua_tointeger(L, idx);
    return (lua_Integer)floor(luaL_checknumber(L, idx));
}

static int16_t rd_i16(const uint8_t *p) { return (int16_t)(p[0] | (p[1] << 8)); }
static uint32_t rd_u32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void put(Framebuffer *fb, lua_Integer i, uint8_t c)
{
    if (i >= 0 && i < FB_PIXELS)
        fb->pixels[i] = c;
}

/* fb:draw_patch(x, y, patch, flipped): V_DrawPatch (offsets 0-based). */
static int l_draw_patch(lua_State *L)
{
    Framebuffer *fb = check_fb(L, 1);
    lua_Integer x = arg_floor(L, 2);
    lua_Integer y = arg_floor(L, 3);
    size_t plen;
    const uint8_t *patch = (const uint8_t *)luaL_checklstring(L, 4, &plen);
    int flipped = lua_toboolean(L, 5);
    if (plen < 8)
        return 0;

    lua_Integer w = rd_i16(patch);
    x -= rd_i16(patch + 4);
    y -= rd_i16(patch + 6);
    lua_Integer desttop = y * FB_WIDTH + x;

    for (lua_Integer col = 0; col < w; col++, desttop++) {
        lua_Integer src_col = flipped ? w - 1 - col : col;
        size_t entry = 8 + (size_t)src_col * 4;
        if (src_col < 0 || entry + 4 > plen)
            continue;
        size_t column = rd_u32(patch + entry);
        while (column < plen) {
            uint8_t topdelta = patch[column];
            if (topdelta == 255 || column + 1 >= plen)
                break;
            uint8_t length = patch[column + 1];
            size_t source = column + 3;
            lua_Integer dest = desttop + (lua_Integer)topdelta * FB_WIDTH;
            for (int i = 0; i < length; i++, source++, dest += FB_WIDTH) {
                if (dest >= 0 && dest < FB_PIXELS && source < plen)
                    fb->pixels[dest] = patch[source];
            }
            column += (size_t)length + 4;
        }
    }
    return 0;
}

static uint8_t check_color(lua_State *L, int idx)
{
    lua_Integer c = luaL_checkinteger(L, idx);
    luaL_argcheck(L, c >= 0 && c <= 255, idx, "cor deve estar entre 0 e 255");
    return (uint8_t)c;
}

/* fb:plot(x, y, color): x e y arredondados para baixo. */
static int l_plot(lua_State *L)
{
    Framebuffer *fb = check_fb(L, 1);
    lua_Integer x = arg_floor(L, 2), y = arg_floor(L, 3);
    uint8_t c = check_color(L, 4);
    if (x >= 0 && y >= 0 && x < FB_WIDTH && y < FB_HEIGHT)
        fb->pixels[y * FB_WIDTH + x] = c;
    return 0;
}

static lua_Integer round_half(lua_State *L, int idx)
{
    return (lua_Integer)floor(luaL_checknumber(L, idx) + 0.5);
}

/* fb:draw_line(x0, y0, x1, y1, color): Bresenham do v_video.lua. */
static int l_draw_line(lua_State *L)
{
    Framebuffer *fb = check_fb(L, 1);
    lua_Integer x0 = round_half(L, 2), y0 = round_half(L, 3);
    lua_Integer x1 = round_half(L, 4), y1 = round_half(L, 5);
    uint8_t c = check_color(L, 6);
    lua_Integer dx = x1 > x0 ? x1 - x0 : x0 - x1;
    lua_Integer dy = y1 > y0 ? y1 - y0 : y0 - y1;
    lua_Integer sx = x0 >= x1 ? -1 : 1;
    lua_Integer sy = y0 >= y1 ? -1 : 1;
    lua_Integer err = dx - dy;
    for (lua_Integer guard = dx + dy + 1; guard > 0; guard--) {
        if (x0 >= 0 && y0 >= 0 && x0 < FB_WIDTH && y0 < FB_HEIGHT)
            fb->pixels[y0 * FB_WIDTH + x0] = c;
        if (x0 == x1 && y0 == y1)
            break;
        lua_Integer e2 = err * 2;
        if (e2 > -dy) {
            err -= dy;
            x0 += sx;
        }
        if (e2 < dx) {
            err += dx;
            y0 += sy;
        }
    }
    return 0;
}

/* fb:fill_region(w, h, color): indices y*w + x, como o clear_fb do automapa. */
static int l_fill_region(lua_State *L)
{
    Framebuffer *fb = check_fb(L, 1);
    lua_Integer w = luaL_checkinteger(L, 2), h = luaL_checkinteger(L, 3);
    uint8_t c = check_color(L, 4);
    for (lua_Integer y = 0; y < h; y++)
        for (lua_Integer x = 0; x < w; x++)
            put(fb, y * w + x, c);
    return 0;
}

/* Ponto do automapa: put_dot com largura/altura da area do mapa. */
static void am_dot(Framebuffer *fb, lua_Integer x, lua_Integer y, lua_Integer c,
                   lua_Integer f_w, lua_Integer f_h)
{
    if (x >= 0 && x < f_w && y >= 0 && y < f_h)
        put(fb, y * f_w + x, (uint8_t)(c & 255));
}

/* fb:am_dot(x, y, color, f_w, f_h) */
static int l_am_dot(lua_State *L)
{
    am_dot(check_fb(L, 1), arg_floor(L, 2), arg_floor(L, 3), luaL_checkinteger(L, 4),
           luaL_checkinteger(L, 5), luaL_checkinteger(L, 6));
    return 0;
}

/* fb:am_line(x0, y0, x1, y1, color, f_w, f_h): draw_fline do am_map.lua. */
static int l_am_line(lua_State *L)
{
    Framebuffer *fb = check_fb(L, 1);
    lua_Integer x0 = arg_floor(L, 2), y0 = arg_floor(L, 3);
    lua_Integer x1 = arg_floor(L, 4), y1 = arg_floor(L, 5);
    lua_Integer c = luaL_checkinteger(L, 6);
    lua_Integer f_w = luaL_checkinteger(L, 7), f_h = luaL_checkinteger(L, 8);
    if (!(x0 >= 0 && x0 < f_w && y0 >= 0 && y0 < f_h &&
          x1 >= 0 && x1 < f_w && y1 >= 0 && y1 < f_h))
        return 0;
    lua_Integer dx = x1 - x0, dy = y1 - y0;
    lua_Integer ax = (dx < 0 ? -dx : dx) * 2;
    lua_Integer ay = (dy < 0 ? -dy : dy) * 2;
    lua_Integer sx = dx < 0 ? -1 : 1;
    lua_Integer sy = dy < 0 ? -1 : 1;
    lua_Integer x = x0, y = y0;
    if (ax > ay) {
        lua_Integer d = ay - ax / 2;
        for (;;) {
            am_dot(fb, x, y, c, f_w, f_h);
            if (x == x1)
                return 0;
            if (d >= 0) {
                y += sy;
                d -= ax;
            }
            x += sx;
            d += ay;
        }
    }
    lua_Integer d = ax - ay / 2;
    for (;;) {
        am_dot(fb, x, y, c, f_w, f_h);
        if (y == y1)
            return 0;
        if (d >= 0) {
            x += sx;
            d -= ay;
        }
        y += sy;
        d += ax;
    }
}

/* fb:fill_flat(data): ladrilha um flat 64x64 na tela toda (finale). */
static int l_fill_flat(lua_State *L)
{
    Framebuffer *fb = check_fb(L, 1);
    size_t n;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 2, &n);
    if (n < 4096) {
        memset(fb->pixels, 0, sizeof(fb->pixels));
        return 0;
    }
    for (int y = 0; y < FB_HEIGHT; y++) {
        const uint8_t *row = data + (y % 64) * 64;
        uint8_t *dest = fb->pixels + y * FB_WIDTH;
        for (int x = 0; x < FB_WIDTH; x++)
            dest[x] = row[x % 64];
    }
    return 0;
}

/* fb:draw_patch_column(x, patch, column): coluna sem offsets (scroll do finale). */
static int l_draw_patch_column(lua_State *L)
{
    Framebuffer *fb = check_fb(L, 1);
    lua_Integer x = arg_floor(L, 2);
    size_t plen;
    const uint8_t *patch = (const uint8_t *)luaL_checklstring(L, 3, &plen);
    lua_Integer column = arg_floor(L, 4);
    if (column < 0)
        return 0;
    size_t entry = 8 + (size_t)column * 4;
    if (entry + 4 > plen)
        return 0;
    size_t offset = rd_u32(patch + entry);
    while (offset < plen && patch[offset] != 255) {
        if (offset + 1 >= plen)
            break;
        int top = patch[offset];
        int length = patch[offset + 1];
        size_t source = offset + 3;
        for (int i = 0; i < length; i++) {
            if (top + i >= FB_HEIGHT)
                break;
            if (source + (size_t)i < plen)
                put(fb, (lua_Integer)(top + i) * FB_WIDTH + x, patch[source + i]);
        }
        offset += (size_t)length + 4;
    }
    return 0;
}

/* fb:copy_from(src): copia o quadro inteiro. */
static int l_copy_from(lua_State *L)
{
    Framebuffer *dst = check_fb(L, 1);
    Framebuffer *src = check_fb(L, 2);
    memcpy(dst->pixels, src->pixels, sizeof(dst->pixels));
    return 0;
}

/*
 * fb:copy_span(src, x0, y0, y1, src_y0): copia uma faixa de 2 pixels de
 * largura, linhas y0..y1-1, lendo de src a partir da linha src_y0 (wipe).
 */
static int l_copy_span(lua_State *L)
{
    Framebuffer *dst = check_fb(L, 1);
    Framebuffer *src = check_fb(L, 2);
    lua_Integer x0 = luaL_checkinteger(L, 3);
    lua_Integer y0 = luaL_checkinteger(L, 4);
    lua_Integer y1 = luaL_checkinteger(L, 5);
    lua_Integer sy0 = luaL_checkinteger(L, 6);
    for (lua_Integer row = 0; row < y1 - y0; row++) {
        lua_Integer s = (sy0 + row) * FB_WIDTH + x0;
        lua_Integer d = (y0 + row) * FB_WIDTH + x0;
        for (int k = 0; k < 2; k++) {
            if (d + k >= 0 && d + k < FB_PIXELS && s + k >= 0 && s + k < FB_PIXELS)
                dst->pixels[d + k] = src->pixels[s + k];
        }
    }
    return 0;
}

static const luaL_Reg draw_methods[] = {
    {"draw_patch", l_draw_patch},
    {"plot", l_plot},
    {"draw_line", l_draw_line},
    {"fill_region", l_fill_region},
    {"am_dot", l_am_dot},
    {"am_line", l_am_line},
    {"fill_flat", l_fill_flat},
    {"draw_patch_column", l_draw_patch_column},
    {"copy_from", l_copy_from},
    {"copy_span", l_copy_span},
    {NULL, NULL}
};

/* Registra os metodos na metatable que esta no topo da pilha. */
void v_draw_register(lua_State *L)
{
    luaL_setfuncs(L, draw_methods, 0);
}
