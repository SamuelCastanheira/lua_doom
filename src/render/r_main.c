/*
 * r_main.c: API Lua do render_c, tamanho da vista, mapeamento e luzes.
 *
 * Uso a partir do Lua (ver render.lua):
 *   local R = render_c.new(res, tables)
 *   R:set_view_size(blocks, detail)          -> screenblocks
 *   R:setup_frame(x, y, z, angle, extralight, fixedcolormap)
 *   R:render(world, fb)                       paredes, chao, teto, ceu
 *   R:draw_sprites(world.mobjs)               sprites + masked atras deles
 *   R:draw_masked()                           masked restantes
 *   R:draw_psprite(lump, sx, sy, fb, fullbright, shadow)   arma
 *   R:point_to_angle(x, y)
 *   R:get(campo)                              leitura de estado (debug/HUD)
 */
#include <stdlib.h>
#include <string.h>

#include "r_local.h"

#if defined(_WIN32)
#define R_EXPORT __declspec(dllexport)
#else
#define R_EXPORT __attribute__((visibility("default")))
#endif

void *r_grow(lua_State *L, void *ptr, int *cap, int need, size_t elem)
{
    if (need <= *cap)
        return ptr;
    int n = *cap ? *cap : 64;
    while (n < need)
        n *= 2;
    void *p = realloc(ptr, (size_t)n * elem);
    if (!p)
        luaL_error(L, "render_c: sem memoria");
    *cap = n;
    return p;
}

const uint8_t *r_colormap(const Renderer *R, lnum level)
{
    if (level < 0) level = 0;
    if (level > 32) level = 32;
    size_t ofs = (size_t)level * 256u;
    if (!R->rd->colormaps || ofs + 256 > R->rd->colormaps_size)
        return R->rd->colormaps;
    return R->rd->colormaps + ofs;
}

/* tables.slope_div */
static lnum slope_div(lnum num, lnum den)
{
    if (den < 512)
        return SLOPERANGE;
    lnum ans = r_idiv(num * 8, r_ushr(den, 8));
    return ans > SLOPERANGE ? SLOPERANGE : ans;
}

lnum r_point_to_angle(const Renderer *R, lnum x, lnum y)
{
    const uint32_t *tantoangle = R->tables->tantoangle;
    x = r_i32(x - R->viewx);
    y = r_i32(y - R->viewy);
    if (x == 0 && y == 0)
        return 0;
    if (x >= 0) {
        if (y >= 0) {
            if (x > y)
                return tantoangle[slope_div(y, x)];
            return r_u32(ANG90 - 1 - tantoangle[slope_div(x, y)]);
        }
        y = -y;
        if (x > y)
            return r_u32(-(lnum)tantoangle[slope_div(y, x)]);
        return r_u32(3221225472LL + tantoangle[slope_div(x, y)]);
    }
    x = -x;
    if (y >= 0) {
        if (x > y)
            return r_u32(ANG180 - 1 - tantoangle[slope_div(y, x)]);
        return r_u32(ANG90 + tantoangle[slope_div(x, y)]);
    }
    y = -y;
    if (x > y)
        return r_u32(ANG180 + tantoangle[slope_div(y, x)]);
    return r_u32(3221225472LL - 1 - tantoangle[slope_div(x, y)]);
}

static lnum fine_sin(const Renderer *R, lnum angle)
{
    return R->tables->finesine[r_band(r_ushr(r_u32(angle), ANGLETOFINESHIFT), FINEMASK)];
}

static lnum fine_cos(const Renderer *R, lnum angle)
{
    return R->tables->finesine[r_band(r_ushr(r_u32(angle), ANGLETOFINESHIFT) + FINEANGLES / 4, FINEMASK)];
}

static void init_mapping(Renderer *R)
{
    const int32_t *finetangent = R->tables->finetangent;
    lnum focallength = r_fixed_div(R->centerxfrac, finetangent[FINEANGLES / 4 + FIELDOFVIEW / 2]);
    const int half = FINEANGLES / 2;
    for (int i = 0; i < half; i++) {
        lnum ft = finetangent[i];
        lnum t;
        if (ft > FRACUNIT * 2) {
            t = -1;
        } else if (ft < -FRACUNIT * 2) {
            t = R->viewwidth + 1;
        } else {
            t = r_shar(r_i32(R->centerxfrac - r_fixed_mul(ft, focallength) + FRACUNIT - 1), FRACBITS);
            if (t < -1) t = -1;
            if (t > R->viewwidth + 1) t = R->viewwidth + 1;
        }
        R->viewangletox[i] = t;
    }
    for (lnum x = 0; x <= R->viewwidth; x++) {
        int i = 0;
        while (i < half && R->viewangletox[i] > x)
            i++;
        R->xtoviewangle[x] = r_u32(r_shl(i, ANGLETOFINESHIFT) - ANG90);
    }
    for (int i = 0; i < half; i++) {
        if (R->viewangletox[i] == -1)
            R->viewangletox[i] = 0;
        else if (R->viewangletox[i] == R->viewwidth + 1)
            R->viewangletox[i] = R->viewwidth;
    }
    R->clipangle = R->xtoviewangle[0];
}

static void init_lights(Renderer *R)
{
    for (int i = 0; i < LIGHTLEVELS; i++) {
        lnum startmap = r_idiv(((LIGHTLEVELS - 1 - i) * 2) * NUMCOLORMAPS, LIGHTLEVELS);
        for (int j = 0; j < MAXLIGHTZ; j++) {
            lnum scale = r_ushr(r_fixed_div((SCREENWIDTH / 2) * FRACUNIT, r_shl(j + 1, LIGHTZSHIFT)), LIGHTSCALESHIFT);
            lnum level = startmap - r_idiv(scale, 2);
            if (level < 0) level = 0;
            if (level > NUMCOLORMAPS - 1) level = NUMCOLORMAPS - 1;
            R->zlight[i][j] = (int)level;
        }
        lnum vw = R->viewwidth << R->detailshift;
        if (vw < 1)
            vw = 1;
        for (int j = 0; j < MAXLIGHTSCALE; j++) {
            /* math.floor(j * SCREENWIDTH / vw / 2): exato para estes valores */
            lnum level = startmap - ((lnum)j * SCREENWIDTH) / (vw * 2);
            if (level < 0) level = 0;
            if (level > NUMCOLORMAPS - 1) level = NUMCOLORMAPS - 1;
            R->scalelight[i][j] = (int)level;
        }
    }
}

static void init_slopes(Renderer *R)
{
    for (lnum i = 0; i < R->viewheight && i < SCREENHEIGHT; i++) {
        lnum dy = (i - R->centery) * FRACUNIT + FRACUNIT / 2;
        if (dy < 0) dy = -dy;
        if (dy < 1) dy = 1;
        R->yslope[i] = r_fixed_div(r_idiv(R->viewwidth << R->detailshift, 2) * FRACUNIT, dy);
    }
    for (lnum i = 0; i < R->viewwidth; i++) {
        lnum cosadj = r_abs_fixed(fine_cos(R, R->xtoviewangle[i]));
        if (cosadj < 1)
            cosadj = 1;
        R->distscale[i] = r_fixed_div(FRACUNIT, cosadj);
    }
}

static void set_centers(Renderer *R)
{
    R->centerx = r_idiv(R->viewwidth, 2);
    R->centery = r_idiv(R->viewheight, 2);
    R->centerxfrac = r_shl(R->centerx, FRACBITS);
    R->centeryfrac = r_shl(R->centery, FRACBITS);
    R->projection = R->centerxfrac;
}

/* Estado inicial igual ao render.new() do Lua. */
void r_init_view(Renderer *R)
{
    R->viewwidth = SCREENWIDTH;
    R->viewheight = SCREENHEIGHT - SBARHEIGHT;
    R->detailshift = 0;
    R->screenblocks = 10;
    R->sized_blocks = -1;
    R->sized_detail = -1;
    R->pspritescale = FRACUNIT;
    R->pspriteiscale = FRACUNIT;
    set_centers(R);
    for (int i = 0; i < SCREENHEIGHT; i++)
        R->ylookup[i] = (lnum)i * SCREENWIDTH;
    for (int i = 0; i < SCREENWIDTH; i++) {
        R->columnofs[i] = i;
        R->ceilingclip[i] = 0;
        R->floorclip[i] = 0;
    }
    init_mapping(R);
    init_lights(R);
    init_slopes(R);
}

void r_set_view_size(Renderer *R, lnum blocks, lnum detail)
{
    if (blocks < 3) blocks = 3;
    if (blocks > 11) blocks = 11;
    detail = detail != 0 ? 1 : 0;
    if (R->sized_blocks == blocks && R->sized_detail == detail)
        return;
    R->sized_blocks = (int)blocks;
    R->sized_detail = (int)detail;
    R->screenblocks = (int)blocks;
    R->detailshift = detail;

    lnum scaled, viewheight;
    if (blocks == 11) {
        scaled = SCREENWIDTH;
        viewheight = SCREENHEIGHT;
    } else {
        scaled = blocks * 32;
        viewheight = r_band(r_idiv(blocks * 168, 10), r_u32(~(lnum)7));
    }
    R->scaledviewwidth = scaled;
    R->viewwidth = r_ushr(scaled, (int)detail);
    R->viewheight = viewheight;
    set_centers(R);
    R->viewwindowx = r_ushr(SCREENWIDTH - scaled, 1);
    R->viewwindowy = scaled == SCREENWIDTH ? 0 : r_ushr(SCREENHEIGHT - SBARHEIGHT - viewheight, 1);
    for (int i = 0; i < SCREENHEIGHT; i++)
        R->ylookup[i] = (i + R->viewwindowy) * SCREENWIDTH;
    for (int i = 0; i < SCREENWIDTH; i++)
        R->columnofs[i] = R->viewwindowx + i;
    for (int i = 0; i < SCREENWIDTH; i++) {
        R->ceilingclip[i] = 0;
        R->floorclip[i] = 0;
    }
    R->pspritescale = r_idiv(FRACUNIT * R->viewwidth, SCREENWIDTH);
    R->pspriteiscale = r_idiv(FRACUNIT * SCREENWIDTH, R->viewwidth > 1 ? R->viewwidth : 1);
    init_mapping(R);
    init_slopes(R);
    init_lights(R);
}

void r_setup_frame(Renderer *R, lnum x, lnum y, lnum z, lnum angle,
                   lnum extralight, lnum fixedcolormap)
{
    R->viewx = x;
    R->viewy = y;
    R->viewz = z;
    R->viewangle = r_u32(angle);
    R->viewsin = fine_sin(R, R->viewangle);
    R->viewcos = fine_cos(R, R->viewangle);
    R->extralight = extralight;
    R->fixedcolormap = fixedcolormap != 0 ? r_colormap(R, fixedcolormap) : NULL;
}

/* ------------------------------------------------------------- Lua API */

static Renderer *check_renderer(lua_State *L, int idx)
{
    return (Renderer *)luaL_checkudata(L, idx, RENDERER_MT);
}

static lnum arg_num(lua_State *L, int idx, lnum def)
{
    if (lua_isnoneornil(L, idx))
        return def;
    if (lua_isinteger(L, idx))
        return lua_tointeger(L, idx);
    return (lnum)luaL_checknumber(L, idx);
}

static int l_new(lua_State *L)
{
    RData *rd = (RData *)luaL_checkudata(L, 1, RD_MT);
    Table *tables = (Table *)luaL_checkudata(L, 2, TABLE_MT);
    luaL_argcheck(L, tables->ready, 2, "tables_c nao inicializado (chame :init())");
    luaL_argcheck(L, rd->initialized, 1, "r_data_c nao inicializado (chame :init())");

    /* Texturas, flats e colormaps prontos em memoria C. */
    lua_getfield(L, 1, "prepare_render");
    lua_pushvalue(L, 1);
    lua_call(L, 1, 0);

    Renderer *R = (Renderer *)lua_newuserdatauv(L, sizeof(Renderer), UV_COUNT);
    memset(R, 0, sizeof(*R));
    R->rd = rd;
    R->tables = tables;
    R->floorplane = -1;
    R->ceilingplane = -1;
    R->maskedtexturecol = -1;
    R->use_bbox = 1;
    luaL_setmetatable(L, RENDERER_MT);

    lua_pushvalue(L, 1);
    lua_setiuservalue(L, -2, UV_RES);
    lua_pushvalue(L, 2);
    lua_setiuservalue(L, -2, UV_TABLES);
    lua_newtable(L);
    lua_setiuservalue(L, -2, UV_LUMPS);

    r_init_view(R);
    return 1;
}

static int l_gc(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    r_free_level(&R->level);
    free(R->visplanes);
    free(R->drawsegs);
    free(R->openings);
    free(R->mapped_list);
    free(R->vissprites);
    free(R->lump_ptr);
    free(R->lump_len);
    free(R->tagbuf);
    R->tagbuf = NULL;
    R->visplanes = NULL;
    R->drawsegs = NULL;
    R->openings = NULL;
    R->mapped_list = NULL;
    R->vissprites = NULL;
    R->lump_ptr = NULL;
    R->lump_len = NULL;
    R->nlumps = 0;
    return 0;
}

static int l_set_view_size(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    r_set_view_size(R, arg_num(L, 2, 10), arg_num(L, 3, 0));
    lua_pushinteger(L, R->screenblocks);
    return 1;
}

static int l_setup_frame(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    r_setup_frame(R, arg_num(L, 2, 0), arg_num(L, 3, 0), arg_num(L, 4, 0),
                  arg_num(L, 5, 0), arg_num(L, 6, 0), arg_num(L, 7, 0));
    return 0;
}

static int l_render(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    R->fb = (Framebuffer *)luaL_checkudata(L, 3, FB_MT);
    lua_pushvalue(L, 3);
    lua_setiuservalue(L, 1, UV_FB);

    R->rd->L = L;
    R->framecount++;
    if (R->framecount == 0)
        R->framecount = 1;
    if (R->tagbuf)
        memset(R->tagbuf, 0, PIXELS);
    r_tagbuf = R->tagbuf;
    r_sync_level(L, R, 1, 2);
    r_render_bsp(L, R);
    r_flush_mapped(L, R, 1);
    r_tagbuf = NULL;
    return 0;
}

static void require_frame(lua_State *L, Renderer *R)
{
    if (!R->fb || !R->level.loaded)
        luaL_error(L, "render_c: chame render() antes de desenhar sprites/masked");
}

static int l_draw_sprites(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    require_frame(L, R);
    r_tagbuf = R->tagbuf;
    r_draw_sprites(L, R, 1, 2);
    r_tagbuf = NULL;
    return 0;
}

static int l_draw_masked(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    require_frame(L, R);
    r_tagbuf = R->tagbuf;
    r_draw_masked(R);
    r_tagbuf = NULL;
    return 0;
}

static int l_draw_psprite(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    if (!R->fb)
        return luaL_error(L, "render_c: chame render() antes de draw_psprite");
    if (!lua_isnoneornil(L, 5)) {
        R->fb = (Framebuffer *)luaL_checkudata(L, 5, FB_MT);
        lua_pushvalue(L, 5);
        lua_setiuservalue(L, 1, UV_FB);
    }
    r_tagbuf = R->tagbuf;
    r_draw_psprite(L, R, 1, arg_num(L, 2, -1), arg_num(L, 3, 0), arg_num(L, 4, 0),
                   lua_toboolean(L, 6), lua_toboolean(L, 7));
    r_tagbuf = NULL;
    return 0;
}

static int l_point_to_angle(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    lua_pushinteger(L, r_point_to_angle(R, arg_num(L, 2, 0), arg_num(L, 3, 0)));
    return 1;
}

/* R:set_option(nome, valor): opcoes de diagnostico ("use_bbox"). */
static int l_set_option(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    const char *k = luaL_checkstring(L, 2);
    if (strcmp(k, "use_bbox") == 0) {
        R->use_bbox = lua_toboolean(L, 3);
    } else if (strcmp(k, "tags") == 0) {
        if (lua_toboolean(L, 3)) {
            if (!R->tagbuf)
                R->tagbuf = (uint8_t *)calloc(PIXELS, 1);
        } else {
            free(R->tagbuf);
            R->tagbuf = NULL;
        }
    }
    else
        return luaL_error(L, "render_c: opcao desconhecida '%s'", k);
    return 0;
}

/* R:get_tags(): string de 64000 bytes com o TAG_* de cada pixel. */
static int l_get_tags(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    if (!R->tagbuf)
        return luaL_error(L, "render_c: ative com set_option('tags', true)");
    lua_pushlstring(L, (const char *)R->tagbuf, PIXELS);
    return 1;
}

static int l_get(lua_State *L)
{
    Renderer *R = check_renderer(L, 1);
    const char *k = luaL_checkstring(L, 2);
    struct { const char *name; lnum value; } fields[] = {
        {"screenblocks", R->screenblocks}, {"viewwidth", R->viewwidth},
        {"viewheight", R->viewheight}, {"detailshift", R->detailshift},
        {"centerx", R->centerx}, {"centery", R->centery},
        {"centerxfrac", R->centerxfrac}, {"centeryfrac", R->centeryfrac},
        {"projection", R->projection}, {"viewwindowx", R->viewwindowx},
        {"viewwindowy", R->viewwindowy}, {"viewx", R->viewx},
        {"viewy", R->viewy}, {"viewz", R->viewz}, {"viewangle", R->viewangle},
        {"viewsin", R->viewsin}, {"viewcos", R->viewcos},
        {"pspritescale", R->pspritescale}, {"pspriteiscale", R->pspriteiscale},
        {"numvisplanes", R->numvisplanes}, {"numdrawsegs", R->numdrawsegs},
        {"numvissprites", R->numvis},
        {"visited_subsectors", R->visited_subsectors},
        {"use_bbox", R->use_bbox},
    };
    for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++) {
        if (strcmp(fields[i].name, k) == 0) {
            lua_pushinteger(L, fields[i].value);
            return 1;
        }
    }
    lua_pushnil(L);
    return 1;
}

static const luaL_Reg renderer_methods[] = {
    {"set_view_size", l_set_view_size},
    {"setup_frame", l_setup_frame},
    {"render", l_render},
    {"draw_sprites", l_draw_sprites},
    {"draw_masked", l_draw_masked},
    {"draw_psprite", l_draw_psprite},
    {"point_to_angle", l_point_to_angle},
    {"get", l_get},
    {"set_option", l_set_option},
    {"get_tags", l_get_tags},
    {NULL, NULL}
};

static const luaL_Reg module_functions[] = {
    {"new", l_new},
    {NULL, NULL}
};

R_EXPORT int luaopen_render_c(lua_State *L)
{
    if (luaL_newmetatable(L, RENDERER_MT)) {
        lua_pushcfunction(L, l_gc);
        lua_setfield(L, -2, "__gc");
        luaL_newlib(L, renderer_methods);
        lua_setfield(L, -2, "__index");
    }
    lua_pop(L, 1);

    luaL_newlib(L, module_functions);
    r_draw_lua_register(L);
    return 1;
}
