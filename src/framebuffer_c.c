/*
 * framebuffer_c.c
 *
 * Framebuffer nativo para lua_doom.
 * Lua 5.4 / C99.
 *
 * Armazena 320x200 indices de paleta (8 bits por pixel) em memoria C.
 * Mantem compatibilidade com acessos Lua:
 *
 *   local fb = framebuffer_c.new()
 *   fb[1] = 12
 *   local pixel = fb[1]
 *   print(#fb)              -- 64000
 *   fb:clear(0)
 *   local bytes = fb:to_string()
 *
 * Os indices Lua sao 1-based. Leituras fora da faixa retornam nil;
 * escritas fora da faixa geram erro.
 */
#include <lua.h>
#include <lauxlib.h>
#include "framebuffer.h"

#include <stdint.h>
#include <string.h>

/* ---------------------------------------------------------
 * Validacao e acesso
 * --------------------------------------------------------- */

static Framebuffer *check_framebuffer(lua_State *L, int index)
{
    return (Framebuffer *)luaL_checkudata(L, index, FB_MT);
}

static int check_pixel_index(lua_State *L, int index)
{
    lua_Integer i = luaL_checkinteger(L, index);

    if (i < 1 || i > FB_PIXELS) {
        luaL_argerror(L, index, "indice do framebuffer fora da faixa (1..64000)");
    }

    return (int)i - 1;
}

static uint8_t check_color(lua_State *L, int index)
{
    lua_Integer color = luaL_checkinteger(L, index);

    if (color < 0 || color > 255) {
        luaL_argerror(L, index, "cor deve estar entre 0 e 255");
    }

    return (uint8_t)color;
}


/* ---------------------------------------------------------
 * Metamethods
 * --------------------------------------------------------- */

static int l_fb_index(lua_State *L)
{
    Framebuffer *fb = check_framebuffer(L, 1);

    if (lua_isinteger(L, 2)) {
        lua_Integer i = lua_tointeger(L, 2);

        if (i < 1 || i > FB_PIXELS) {
            lua_pushnil(L);
        } else {
            lua_pushinteger(L, fb->pixels[(int)i - 1]);
        }

        return 1;
    }

    /*
     * Para chaves string, procura os metodos registrados
     * na metatable (fb.clear, fb.get etc.).
     */
    if (lua_type(L, 2) == LUA_TSTRING) {
        luaL_getmetatable(L, FB_MT);
        lua_pushvalue(L, 2);
        lua_rawget(L, -2);
        return 1;
    }

    lua_pushnil(L);
    return 1;
}

static int l_fb_newindex(lua_State *L)
{
    Framebuffer *fb = check_framebuffer(L, 1);

    if (!lua_isinteger(L, 2)) {
        return luaL_error(L, "indice do framebuffer deve ser um inteiro");
    }

    int i = check_pixel_index(L, 2);
    fb->pixels[i] = check_color(L, 3);

    return 0;
}

static int l_fb_len(lua_State *L)
{
    (void)check_framebuffer(L, 1);
    lua_pushinteger(L, FB_PIXELS);
    return 1;
}


/* ---------------------------------------------------------
 * Metodos
 * --------------------------------------------------------- */

static int l_fb_clear(lua_State *L)
{
    Framebuffer *fb = check_framebuffer(L, 1);
    uint8_t color = 0;

    if (!lua_isnoneornil(L, 2)) {
        color = check_color(L, 2);
    }

    memset(fb->pixels, color, sizeof(fb->pixels));
    return 0;
}

static int l_fb_get(lua_State *L)
{
    Framebuffer *fb = check_framebuffer(L, 1);
    int i = check_pixel_index(L, 2);

    lua_pushinteger(L, fb->pixels[i]);
    return 1;
}

static int l_fb_set(lua_State *L)
{
    Framebuffer *fb = check_framebuffer(L, 1);
    int i = check_pixel_index(L, 2);
    uint8_t color = check_color(L, 3);

    fb->pixels[i] = color;
    return 0;
}

static int l_fb_to_string(lua_State *L)
{
    Framebuffer *fb = check_framebuffer(L, 1);

    /*
     * Compatibilidade temporaria com video_c.c, que atualmente
     * recebe uma string. Esta operacao copia 64000 bytes.
     * A integracao direta por ponteiro pode ser feita depois.
     */
    lua_pushlstring(L, (const char *)fb->pixels, sizeof(fb->pixels));
    return 1;
}


/* ---------------------------------------------------------
 * Construtor
 * --------------------------------------------------------- */
static int l_new(lua_State *L)
{
    uint8_t color = 0;

    /* Valida o argumento antes de adicionar o userdata à pilha. */
    if (!lua_isnoneornil(L, 1)) {
        color = check_color(L, 1);
    }

    Framebuffer *fb = (Framebuffer *)lua_newuserdatauv(
        L, sizeof(Framebuffer), 0
    );

    memset(fb->pixels, color, sizeof(fb->pixels));

    luaL_getmetatable(L, FB_MT);
    lua_setmetatable(L, -2);

    return 1;
}

/* ---------------------------------------------------------
 * Registro do modulo
 * --------------------------------------------------------- */

static const luaL_Reg framebuffer_methods[] = {
    {"clear",     l_fb_clear},
    {"get",       l_fb_get},
    {"set",       l_fb_set},
    {"to_string", l_fb_to_string},
    {NULL, NULL}
};

/* framebuffer_c.hash(s): FNV-1a de 32 bits de uma string (testes de replay). */
static int l_hash(lua_State *L)
{
    size_t n;
    const unsigned char *p = (const unsigned char *)luaL_checklstring(L, 1, &n);
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) {
        h ^= p[i];
        h *= 16777619u;
    }
    lua_pushinteger(L, (lua_Integer)h);
    return 1;
}

static const luaL_Reg framebuffer_module[] = {
    {"new", l_new},
    {"hash", l_hash},
    {NULL, NULL}
};

int luaopen_framebuffer_c(lua_State *L)
{
    /* Metatable do userdata. */
    luaL_newmetatable(L, FB_MT);

    lua_pushcfunction(L, l_fb_index);
    lua_setfield(L, -2, "__index");

    lua_pushcfunction(L, l_fb_newindex);
    lua_setfield(L, -2, "__newindex");

    lua_pushcfunction(L, l_fb_len);
    lua_setfield(L, -2, "__len");

    lua_pushliteral(L, "Framebuffer");
    lua_setfield(L, -2, "__name");

    lua_pushliteral(L, "metatable protegida");
    lua_setfield(L, -2, "__metatable");

    /* Os metodos ficam na propria metatable. */
    luaL_setfuncs(L, framebuffer_methods, 0);
    v_draw_register(L);
    lua_pop(L, 1);

    /* Tabela publica do modulo. */
    luaL_newlib(L, framebuffer_module);

    lua_pushinteger(L, FB_WIDTH);
    lua_setfield(L, -2, "WIDTH");

    lua_pushinteger(L, FB_HEIGHT);
    lua_setfield(L, -2, "HEIGHT");

    lua_pushinteger(L, FB_PIXELS);
    lua_setfield(L, -2, "PIXELS");

    return 1;
}
