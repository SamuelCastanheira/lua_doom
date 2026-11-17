/*
 * r_level.c: copia do mapa das tabelas Lua para arrays C.
 *
 * A geometria (vertices, segs, subsetores, nos) e copiada uma vez por mapa.
 * A cada quadro so os campos que a logica do jogo altera sao relidos:
 *   setores: floorheight, ceilingheight, floorpic, ceilingpic, lightlevel
 *   lados:   textureoffset, rowoffset, toptexture, midtexture, bottomtexture
 * O flag ML_MAPPED das linhas vistas e devolvido ao Lua (automapa).
 */
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "r_local.h"

/* Le um numero Lua (inteiro ou float) no topo da pilha e o remove. */
static lnum pop_num(lua_State *L)
{
    int isint = 0;
    lua_Integer v = lua_tointegerx(L, -1, &isint);
    lnum out = 0;
    if (isint)
        out = v;
    else if (lua_type(L, -1) == LUA_TNUMBER)
        out = (lnum)floor(lua_tonumber(L, -1));
    lua_pop(L, 1);
    return out;
}

lnum r_field_num(lua_State *L, int obj, const char *name)
{
    lua_getfield(L, obj, name);
    return pop_num(L);
}
#define field_num r_field_num

/* Indice (0-based) do objeto no campo `name` de obj, pelo mapa; -1 se nil. */
static int field_ref(lua_State *L, int obj, const char *name, int map)
{
    lua_getfield(L, obj, name);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return -1;
    }
    lua_rawget(L, map);
    int isint = 0;
    lua_Integer v = lua_tointegerx(L, -1, &isint);
    lua_pop(L, 1);
    return isint ? (int)v : -1;
}

/* Registra array[i] -> i-1 no mapa. Retorna o tamanho do array. */
static int index_array(lua_State *L, int arr, int map)
{
    int n = (int)lua_rawlen(L, arr);
    for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, arr, i);
        lua_pushinteger(L, i - 1);
        lua_rawset(L, map);
    }
    return n;
}

static void *alloc_items(lua_State *L, int n, size_t size)
{
    void *p = calloc((size_t)(n > 0 ? n : 1), size);
    if (!p)
        luaL_error(L, "render_c: sem memoria carregando o mapa");
    return p;
}

void r_free_level(RLevel *lv)
{
    free(lv->vertexes);
    free(lv->sectors);
    free(lv->sides);
    free(lv->lines);
    free(lv->segs);
    free(lv->subsectors);
    free(lv->nodes);
    memset(lv, 0, sizeof(*lv));
}

static void sync_sector(lua_State *L, RSector *s, int obj)
{
    s->floorheight = field_num(L, obj, "floorheight");
    s->ceilingheight = field_num(L, obj, "ceilingheight");
    s->floorpic = field_num(L, obj, "floorpic");
    s->ceilingpic = field_num(L, obj, "ceilingpic");
    s->lightlevel = field_num(L, obj, "lightlevel");
}

static void sync_side(lua_State *L, RSide *s, int obj)
{
    s->textureoffset = field_num(L, obj, "textureoffset");
    s->rowoffset = field_num(L, obj, "rowoffset");
    s->toptexture = field_num(L, obj, "toptexture");
    s->midtexture = field_num(L, obj, "midtexture");
    s->bottomtexture = field_num(L, obj, "bottomtexture");
}

static void load_level(lua_State *L, Renderer *R, int ud, int world)
{
    RLevel *lv = &R->level;
    r_free_level(lv);
    int top = lua_gettop(L);

    lua_newtable(L);
    int map = lua_gettop(L);

    lua_getfield(L, world, "vertexes");
    int vertexes = lua_gettop(L);
    lua_getfield(L, world, "sectors");
    int sectors = lua_gettop(L);
    lua_getfield(L, world, "sides");
    int sides = lua_gettop(L);
    lua_getfield(L, world, "lines");
    int lines = lua_gettop(L);
    lua_getfield(L, world, "segs");
    int segs = lua_gettop(L);
    lua_getfield(L, world, "subsectors");
    int subsectors = lua_gettop(L);
    lua_getfield(L, world, "nodes");
    int nodes = lua_gettop(L);
    for (int i = vertexes; i <= nodes; i++)
        luaL_checktype(L, i, LUA_TTABLE);

    lv->num_vertexes = index_array(L, vertexes, map);
    lv->num_sectors = index_array(L, sectors, map);
    lv->num_sides = index_array(L, sides, map);
    lv->num_lines = index_array(L, lines, map);
    lv->num_segs = (int)lua_rawlen(L, segs);
    lv->num_subsectors = (int)lua_rawlen(L, subsectors);
    lv->num_nodes = (int)lua_rawlen(L, nodes);
    lv->numnodes = field_num(L, world, "numnodes");

    lv->vertexes = (RVertex *)alloc_items(L, lv->num_vertexes, sizeof(RVertex));
    lv->sectors = (RSector *)alloc_items(L, lv->num_sectors, sizeof(RSector));
    lv->sides = (RSide *)alloc_items(L, lv->num_sides, sizeof(RSide));
    lv->lines = (RLine *)alloc_items(L, lv->num_lines, sizeof(RLine));
    lv->segs = (RSeg *)alloc_items(L, lv->num_segs, sizeof(RSeg));
    lv->subsectors = (RSubsector *)alloc_items(L, lv->num_subsectors, sizeof(RSubsector));
    lv->nodes = (RNode *)alloc_items(L, lv->num_nodes, sizeof(RNode));

    for (int i = 0; i < lv->num_vertexes; i++) {
        lua_rawgeti(L, vertexes, i + 1);
        lv->vertexes[i].x = field_num(L, -1, "x");
        lv->vertexes[i].y = field_num(L, -1, "y");
        lua_pop(L, 1);
    }
    for (int i = 0; i < lv->num_sectors; i++) {
        lua_rawgeti(L, sectors, i + 1);
        sync_sector(L, &lv->sectors[i], lua_gettop(L));
        lua_pop(L, 1);
    }
    for (int i = 0; i < lv->num_sides; i++) {
        lua_rawgeti(L, sides, i + 1);
        int o = lua_gettop(L);
        sync_side(L, &lv->sides[i], o);
        lv->sides[i].sector = field_ref(L, o, "sector", map);
        lua_pop(L, 1);
    }
    for (int i = 0; i < lv->num_lines; i++) {
        lua_rawgeti(L, lines, i + 1);
        int o = lua_gettop(L);
        lv->lines[i].v1 = field_ref(L, o, "v1", map);
        lv->lines[i].v2 = field_ref(L, o, "v2", map);
        lv->lines[i].flags = field_num(L, o, "flags");
        lv->lines[i].mapped_frame = 0;
        lua_pop(L, 1);
    }
    for (int i = 0; i < lv->num_segs; i++) {
        lua_rawgeti(L, segs, i + 1);
        int o = lua_gettop(L);
        RSeg *sg = &lv->segs[i];
        sg->v1 = field_ref(L, o, "v1", map);
        sg->v2 = field_ref(L, o, "v2", map);
        sg->angle = field_num(L, o, "angle");
        sg->offset = field_num(L, o, "offset");
        sg->linedef = field_ref(L, o, "linedef", map);
        sg->sidedef = field_ref(L, o, "sidedef", map);
        sg->frontsector = field_ref(L, o, "frontsector", map);
        sg->backsector = field_ref(L, o, "backsector", map);
        if (sg->v1 < 0 || sg->v2 < 0)
            luaL_error(L, "render_c: seg %d sem vertices", i);
        lua_pop(L, 1);
    }
    for (int i = 0; i < lv->num_subsectors; i++) {
        lua_rawgeti(L, subsectors, i + 1);
        int o = lua_gettop(L);
        lv->subsectors[i].sector = field_ref(L, o, "sector", map);
        lv->subsectors[i].firstline = (int)field_num(L, o, "firstline");
        lv->subsectors[i].numlines = (int)field_num(L, o, "numlines");
        lua_pop(L, 1);
    }
    for (int i = 0; i < lv->num_nodes; i++) {
        lua_rawgeti(L, nodes, i + 1);
        int o = lua_gettop(L);
        RNode *nd = &lv->nodes[i];
        nd->x = field_num(L, o, "x");
        nd->y = field_num(L, o, "y");
        nd->dx = field_num(L, o, "dx");
        nd->dy = field_num(L, o, "dy");
        lua_getfield(L, o, "children");
        lua_rawgeti(L, -1, 1);
        nd->children[0] = pop_num(L);
        lua_rawgeti(L, -1, 2);
        nd->children[1] = pop_num(L);
        lua_pop(L, 2);
    }

    /* Guarda as tabelas para sincronizar e detectar troca de mapa. */
    lua_createtable(L, 0, 5);
    lua_pushvalue(L, world);
    lua_setfield(L, -2, "world");
    lua_pushvalue(L, sectors);
    lua_setfield(L, -2, "sectors");
    lua_pushvalue(L, sides);
    lua_setfield(L, -2, "sides");
    lua_pushvalue(L, lines);
    lua_setfield(L, -2, "lines");
    lua_pushvalue(L, segs);
    lua_setfield(L, -2, "segs");
    lua_setiuservalue(L, ud, UV_WORLD);

    lv->loaded = 1;
    R->nmapped = 0;
    lua_settop(L, top);
}

/* 1 se o campo `name` de world e o mesmo objeto guardado em refs. */
static int same_field(lua_State *L, int world, int refs, const char *name)
{
    lua_getfield(L, world, name);
    lua_getfield(L, refs, name);
    int same = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    return same;
}

void r_sync_level(lua_State *L, Renderer *R, int ud, int world)
{
    world = lua_absindex(L, world);
    luaL_checktype(L, world, LUA_TTABLE);
    int top = lua_gettop(L);

    lua_getiuservalue(L, ud, UV_WORLD);
    int refs = lua_gettop(L);
    int same = 0;
    if (lua_istable(L, refs)) {
        lua_getfield(L, refs, "world");
        same = lua_rawequal(L, -1, world);
        lua_pop(L, 1);
        same = same && same_field(L, world, refs, "sectors")
                    && same_field(L, world, refs, "sides")
                    && same_field(L, world, refs, "lines")
                    && same_field(L, world, refs, "segs");
    }
    if (!same || !R->level.loaded) {
        lua_settop(L, top);
        load_level(L, R, ud, world);
        lua_settop(L, top);
        return; /* load_level ja leu os valores atuais */
    }

    RLevel *lv = &R->level;
    lua_getfield(L, refs, "sectors");
    int sectors = lua_gettop(L);
    for (int i = 0; i < lv->num_sectors; i++) {
        lua_rawgeti(L, sectors, i + 1);
        sync_sector(L, &lv->sectors[i], lua_gettop(L));
        lua_pop(L, 1);
    }
    lua_getfield(L, refs, "sides");
    int sides = lua_gettop(L);
    for (int i = 0; i < lv->num_sides; i++) {
        lua_rawgeti(L, sides, i + 1);
        sync_side(L, &lv->sides[i], lua_gettop(L));
        lua_pop(L, 1);
    }
    lua_settop(L, top);
}

void r_mark_line(lua_State *L, Renderer *R, int line)
{
    RLine *ln = &R->level.lines[line];
    if (ln->mapped_frame == R->framecount)
        return;
    ln->mapped_frame = R->framecount;
    R->mapped_list = (int *)r_grow(L, R->mapped_list, &R->maxmapped,
                                   R->nmapped + 1, sizeof(int));
    R->mapped_list[R->nmapped++] = line;
}

/* linedef.flags = bor(linedef.flags, ML_MAPPED), como no render.lua. */
void r_flush_mapped(lua_State *L, Renderer *R, int ud)
{
    if (R->nmapped == 0)
        return;
    int top = lua_gettop(L);
    lua_getiuservalue(L, ud, UV_WORLD);
    lua_getfield(L, -1, "lines");
    int lines = lua_gettop(L);
    for (int i = 0; i < R->nmapped; i++) {
        int idx = R->mapped_list[i];
        lua_rawgeti(L, lines, idx + 1);
        lnum flags = field_num(L, -1, "flags");
        lnum nf = r_u32(r_u32(flags) | ML_MAPPED);
        if (nf != flags) {
            lua_pushinteger(L, nf);
            lua_setfield(L, -2, "flags");
        }
        R->level.lines[idx].flags = nf;
        lua_pop(L, 1);
    }
    R->nmapped = 0;
    lua_settop(L, top);
}
