#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>

#include "../src/fixed.h"

static int l_fixed_mul(lua_State *L)
{
int32_t a = (int32_t)luaL_checkinteger(L, 1);
int32_t b = (int32_t)luaL_checkinteger(L, 2);

lua_pushinteger(L, fixed_mul(a, b));
return 1;

}

static int l_fixed_div(lua_State *L)
{
int32_t a = (int32_t)luaL_checkinteger(L, 1);
int32_t b = (int32_t)luaL_checkinteger(L, 2);

lua_pushinteger(L, fixed_div(a, b));
return 1;

}

static int l_abs_fixed(lua_State *L)
{
int32_t n = (int32_t)luaL_checkinteger(L, 1);

lua_pushinteger(L, abs_fixed(n));
return 1;

}

static const luaL_Reg functions[] = {
{"fixed_mul", l_fixed_mul},
{"fixed_div", l_fixed_div},
{"abs_fixed", l_abs_fixed},
{NULL, NULL}
};

int luaopen_test_fixed_c(lua_State *L)
{
luaL_newlib(L, functions);
return 1;
}