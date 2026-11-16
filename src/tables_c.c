#include <stdbool.h>
#include <stdint.h>
#include <limits.h>
#include <math.h>
#include <string.h>

#include <lua.h>
#include <lauxlib.h>

#define TABLE_MT "tables_c.Table"

#define FINEANGLES 8192
#define FINEMASK 8191
#define ANGLETOFINESHIFT 19
#define FRACUNIT 65536
#define SLOPERANGE 2048
#define ANG90 1073741824
#define DBITS 5

#define FINESINE_SIZE (FINEANGLES * 5 / 4)

typedef struct {
    int32_t finesine[FINESINE_SIZE];
    int32_t finetangent[FINEANGLES / 2];
    uint32_t tantoangle[SLOPERANGE + 1];

    bool ready;
} Table;


/* =========================================================
   Estrutura e validação
   ========================================================= */

static Table *check_table(lua_State *L, int index)
{
    return (Table *)luaL_checkudata(L, index, TABLE_MT);
}

static Table *check_ready_table(lua_State *L, int index)
{
    Table *tb = check_table(L, index);

    luaL_argcheck(L, tb->ready, index, "tables not initialized");

    return tb;
}


/* =========================================================
   Funções auxiliares
   ========================================================= */

static int32_t trunc_i32(double n)
{
    return (int32_t)n;
}

static uint32_t trunc_u32(double n)
{
    return (uint32_t)n;
}

static int64_t idiv(int64_t n, int64_t d)
{
    if (d == 0)
        return 0;

    int64_t q = n / d;
    int64_t r = n % d;

    if (r != 0 && ((n < 0) != (d < 0)))
        q--;

    return q;
}


/* =========================================================
   Inicialização das tabelas
   ========================================================= */

static void init_tables(Table *tb)
{
    if (tb->ready)
        return;

    const double pi = acos(-1.0);

    int32_t nsin = (FINEANGLES / 4) * 5;

    for (int i = 0; i < nsin; i++) {
        double a = (i + 0.5) * pi * 2.0 / FINEANGLES;

        tb->finesine[i] =
            trunc_i32(FRACUNIT * sin(a));
    }

    int32_t half = FINEANGLES / 2;
    int32_t quarter = FINEANGLES / 4;

    for (int i = 0; i < half; i++) {
        double a = (i - quarter + 0.5) * pi * 2.0 / FINEANGLES;

        double v = FRACUNIT * tan(a);

        if (!isfinite(v)) {
            v = a > 0 ? INT32_MAX : -INT32_MAX;
        } else if (v > INT32_MAX) {
            v = INT32_MAX;
        } else if (v < -INT32_MAX) {
            v = -INT32_MAX;
        }

        tb->finetangent[i] = trunc_i32(v);
    }

    for (int i = 0; i <= SLOPERANGE; i++) {
        double ang =
            atan((double)i / SLOPERANGE)
            / (pi * 2.0)
            * 4294967295.0;

        tb->tantoangle[i] = trunc_u32(ang);
    }

    tb->ready = true;
}


/* =========================================================
   Operações sobre as tabelas
   ========================================================= */

static int32_t fine_sin(const Table *tb, int32_t angle)
{
    uint32_t i =
        ((uint32_t)angle >> ANGLETOFINESHIFT) & FINEMASK;

    return tb->finesine[i];
}

static int32_t fine_cos(const Table *tb, int32_t angle)
{
    uint32_t i =
        (((uint32_t)angle >> ANGLETOFINESHIFT)
        + (FINEANGLES / 4)) & FINEMASK;

    return tb->finesine[i];
}

static int64_t slope_div(int32_t num, int32_t den)
{
    if (den < 512)
        return SLOPERANGE;

    uint32_t shifted_den = ((uint32_t)den) >> 8;

    int64_t ans = idiv((int64_t)num * 8, shifted_den);

    if (ans > SLOPERANGE)
        return SLOPERANGE;

    return (int64_t)ans;
}


/* =========================================================
   API Lua
   ========================================================= */

static int l_new(lua_State *L)
{
    Table *tb = (Table *)lua_newuserdatauv(L, sizeof(Table), 0);

    memset(tb, 0, sizeof(Table));

    luaL_getmetatable(L, TABLE_MT);
    lua_setmetatable(L, -2);

    return 1;
}

static int l_init(lua_State *L)
{
    Table *tb = check_table(L, 1);

    init_tables(tb);

    return 0;
}

static int l_fine_sin(lua_State *L)
{
    Table *tb = check_ready_table(L, 1);
    int32_t angle = (int32_t)luaL_checkinteger(L, 2);

    lua_pushinteger(L, fine_sin(tb, angle));

    return 1;
}

static int l_fine_cos(lua_State *L)
{
    Table *tb = check_ready_table(L, 1);
    int32_t angle = (int32_t)luaL_checkinteger(L, 2);

    lua_pushinteger(L, fine_cos(tb, angle));

    return 1;
}

static int l_slope_div(lua_State *L)
{
    check_ready_table(L, 1);

    int32_t num = (int32_t)luaL_checkinteger(L, 2);
    int32_t den = (int32_t)luaL_checkinteger(L, 3);

    lua_pushinteger(L, (lua_Integer)slope_div(num, den));

    return 1;
}


/* =========================================================
   Acesso aos arrays
   Índices Lua começam em zero nesta API.
   ========================================================= */

static int l_get_finesine(lua_State *L)
{
    Table *tb = check_ready_table(L, 1);
    lua_Integer i = luaL_checkinteger(L, 2);

    luaL_argcheck(L, i >= 0 && i < FINESINE_SIZE, 2,
                  "finesine index out of range");

    lua_pushinteger(L, tb->finesine[i]);

    return 1;
}

static int l_get_finetangent(lua_State *L)
{
    Table *tb = check_ready_table(L, 1);
    lua_Integer i = luaL_checkinteger(L, 2);

    luaL_argcheck(L, i >= 0 && i < FINEANGLES / 2, 2,
                  "finetangent index out of range");

    lua_pushinteger(L, tb->finetangent[i]);

    return 1;
}

static int l_get_tantoangle(lua_State *L)
{
    Table *tb = check_ready_table(L, 1);
    lua_Integer i = luaL_checkinteger(L, 2);

    luaL_argcheck(L, i >= 0 && i <= SLOPERANGE, 2,
                  "tantoangle index out of range");

    lua_pushinteger(L, tb->tantoangle[i]);

    return 1;
}

static int l_finesine_data(lua_State *L)
{
    Table *tb = check_ready_table(L, 1);

    lua_pushlstring(
        L,
        (const char *)tb->finesine,
        sizeof(tb->finesine)
    );

    return 1;
}


/* =========================================================
   Registro dos métodos
   ========================================================= */

static const luaL_Reg table_methods[] = {
    {"init", l_init},

    {"fine_sin", l_fine_sin},
    {"fine_cos", l_fine_cos},
    {"slope_div", l_slope_div},

    {"get_finesine", l_get_finesine},
    {"get_finetangent", l_get_finetangent},
    {"get_tantoangle", l_get_tantoangle},
    {"finesine_data", l_finesine_data},
    {NULL, NULL}
};


/* =========================================================
   Abertura do módulo
   ========================================================= */

int luaopen_tables_c(lua_State *L)
{
    /* Metatable do userdata */
    luaL_newmetatable(L, TABLE_MT);

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    luaL_setfuncs(L, table_methods, 0);

    /* Constantes acessíveis pelo objeto */
    lua_pushinteger(L, ANG90);
    lua_setfield(L, -2, "ANG90");

    lua_pushinteger(L, DBITS);
    lua_setfield(L, -2, "DBITS");

    lua_pushinteger(L, FINEANGLES);
    lua_setfield(L, -2, "FINEANGLES");

    lua_pushinteger(L, FINEMASK);
    lua_setfield(L, -2, "FINEMASK");

    lua_pop(L, 1);

    /* Tabela do módulo */
    lua_newtable(L);

    lua_pushcfunction(L, l_new);
    lua_setfield(L, -2, "new");

    return 1;
}