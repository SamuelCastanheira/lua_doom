/*
 * render_c: renderer do Doom em C.
 *
 * Estado interno compartilhado entre os arquivos do renderer. A organizacao
 * segue o Doom original:
 *   r_main.c   API Lua, tamanho da vista, mapeamento de angulos e luzes
 *   r_level.c  copia do mapa (Lua -> C) e sincronizacao por quadro
 *   r_bsp.c    travessia da BSP e clipping de segmentos solidos
 *   r_segs.c   paredes (store_wall_range / render_seg_loop) e masked
 *   r_plane.c  visplanes, chao, teto e ceu
 *   r_things.c sprites e arma
 *   r_draw.c   desenho de colunas
 *
 * Regra de equivalencia: o renderer Lua usava inteiros de 64 bits sem wrap e
 * aplicava wrap de 32 bits so em pontos especificos (as_i32, fixed_mul, shar,
 * ...). Para produzir os mesmos pixels, o estado aqui usa `lnum` (int64_t) e
 * as mesmas funcoes de wrap nos mesmos pontos. Nao troque por int32_t sem
 * rodar `make compare`.
 */
#ifndef R_LOCAL_H
#define R_LOCAL_H

#include <stddef.h>
#include <stdint.h>

#include <lauxlib.h>
#include <lua.h>

#include "framebuffer.h"
#include "r_data.h"
#include "tables_c.h"

#define RENDERER_MT "render_c.Renderer"

/* Indices dos uservalues do userdata Renderer. */
#define UV_RES 1
#define UV_TABLES 2
#define UV_FB 3
#define UV_LUMPS 4
#define UV_WORLD 5
#define UV_COUNT 5

#define SCREENWIDTH 320
#define SCREENHEIGHT 200
#define SBARHEIGHT 32
#define PIXELS (SCREENWIDTH * SCREENHEIGHT)
#define FRACBITS 16
#define FRACUNIT 65536
#define FINEANGLES 8192
#define FINEMASK 8191
#define ANGLETOFINESHIFT 19
#define ANG45 536870912LL
#define ANG90 1073741824LL
#define ANG180 2147483648LL
#define FIELDOFVIEW 2048
#define LIGHTLEVELS 16
#define LIGHTZSHIFT 20
#define MAXLIGHTZ 128
#define LIGHTSCALESHIFT 12
#define MAXLIGHTSCALE 48
#define NUMCOLORMAPS 32
#define NF_SUBSECTOR 32768
#define ML_DONTPEGTOP 8
#define ML_DONTPEGBOTTOM 16
#define ML_MAPPED 256
#define SIL_NONE 0
#define SIL_TOP 1
#define SIL_BOTTOM 2
#define SIL_BOTH 3
#define HEIGHTBITS 12
#define HEIGHTUNIT 4096
#define ANGLETOSKYSHIFT 22
#define R_SHRT_MAX 32767
#define R_INT_MAX 2147483647LL
#define R_INT_MIN (-2147483647LL) /* igual ao render.lua (nao e INT32_MIN) */
#define MF_SHADOW 262144
#define MF_NOSECTOR 8
#define MINZ (4 * FRACUNIT)
#define MAXSOLIDSEGS 512
#define SLOPERANGE 2048
#define DBITS 5

typedef int64_t lnum; /* espelha um inteiro do Lua: 64 bits, sem wrap */

/* ------------------------------------------------ aritmetica (compat.lua) */

static inline lnum r_u32(lnum n) { return (lnum)(uint32_t)n; }
static inline lnum r_i32(lnum n) { return (lnum)(int32_t)(uint32_t)n; }

/* compat.ushr: deslocamento logico do valor em 32 bits sem sinal. */
static inline lnum r_ushr(lnum n, int bits) {
    if (bits <= 0) return r_u32(n);
    if (bits >= 32) return 0;
    return r_u32(n) >> bits;
}

/* compat.shar: deslocamento aritmetico do valor em 32 bits com sinal. */
static inline lnum r_shar(lnum n, int bits) {
    if (bits <= 0) return r_i32(n);
    if (bits >= 31) return r_i32(n) < 0 ? -1 : 0;
    return r_i32(n) >> bits; /* gcc/clang/msvc: shift aritmetico */
}

/* compat.shl: resultado em 32 bits sem sinal. */
static inline lnum r_shl(lnum n, int bits) {
    if (bits <= 0) return r_u32(n);
    if (bits >= 32) return 0;
    return r_u32((lnum)((uint64_t)r_u32(n) << bits));
}

static inline lnum r_band(lnum a, lnum b) { return r_u32(a) & r_u32(b); }

/* Divisao com arredondamento para baixo (math.floor(n / d)). */
static inline lnum r_floordiv(lnum n, lnum d) {
    lnum q = n / d;
    if ((n % d != 0) && ((n < 0) != (d < 0))) q--;
    return q;
}

/* render.lua idiv: d == 0 -> 0. */
static inline lnum r_idiv(lnum n, lnum d) {
    if (d == 0) return 0;
    return r_floordiv(n, d);
}

static inline lnum r_fixed_mul(lnum a, lnum b) {
    int64_t p = (int64_t)(int32_t)r_i32(a) * (int64_t)(int32_t)r_i32(b);
    return r_i32(p >> 16);
}

static inline lnum r_fixed_div(lnum a, lnum b) {
    a = r_i32(a);
    b = r_i32(b);
    if (b == 0) return a >= 0 ? 2147483647LL : -2147483648LL;
    lnum abs_a = a < 0 ? -a : a;
    lnum abs_b = b < 0 ? -b : b;
    if (r_ushr(abs_a, 14) >= abs_b)
        return ((a < 0) == (b < 0)) ? 2147483647LL : -2147483648LL;
    return r_i32(r_floordiv(a * 65536, b));
}

static inline lnum r_abs_fixed(lnum n) {
    n = r_i32(n);
    return n < 0 ? -n : n;
}

/* ------------------------------------------------------------ mapa */

typedef struct { lnum x, y; } RVertex;

typedef struct {
    lnum floorheight, ceilingheight;
    lnum floorpic, ceilingpic, lightlevel;
} RSector;

typedef struct {
    lnum textureoffset, rowoffset;
    lnum toptexture, midtexture, bottomtexture;
    int sector;
} RSide;

typedef struct {
    int v1, v2;
    lnum flags;
    uint32_t mapped_frame; /* ultimo quadro em que foi marcada */
} RLine;

typedef struct {
    int v1, v2;
    lnum angle, offset;
    int linedef, sidedef, frontsector, backsector; /* -1 = nenhum */
} RSeg;

typedef struct { int sector, firstline, numlines; } RSubsector;

typedef struct {
    lnum x, y, dx, dy;
    lnum children[2];
} RNode;

typedef struct {
    RVertex *vertexes; int num_vertexes;
    RSector *sectors; int num_sectors;
    RSide *sides; int num_sides;
    RLine *lines; int num_lines;
    RSeg *segs; int num_segs;
    RSubsector *subsectors; int num_subsectors;
    RNode *nodes; int num_nodes;
    lnum numnodes; /* world.numnodes */
    int loaded;
} RLevel;

/* ------------------------------------------------------ renderer */

typedef struct {
    lnum height;
    lnum picnum, lightlevel;
    lnum minx, maxx;
    int16_t top[SCREENWIDTH];
    int16_t bottom[SCREENWIDTH];
} Visplane;

typedef struct {
    lnum x1, x2;
    lnum scale1, scale2, scalestep;
    int curline;
    int silhouette;
    lnum bsilheight, tsilheight;
    int sprtopclip;       /* offset em openings, -1 = nenhum */
    int sprbottomclip;
    int clip_count;
    int maskedtexturecol; /* offset em openings, -1 = nenhum */
    int masked_count;
} DrawSeg;

typedef struct {
    int mobj_index;
    int has_mo;
    lnum mo_flags;
    const uint8_t *patch;
    size_t patch_len;
    lnum w;
    lnum scale;
    lnum gx, gy, gz, gzt;
    lnum texturemid;
    lnum x1, x2;
    lnum xiscale;
    lnum startfrac;
} VisSprite;

typedef struct { lnum first, last; } ClipRange;

typedef struct {
    RData *rd;
    const Table *tables;
    Framebuffer *fb;

    /* tamanho da vista */
    int screenblocks, sized_blocks, sized_detail;
    lnum viewwidth, viewheight, scaledviewwidth, detailshift;
    lnum centerx, centery, centerxfrac, centeryfrac, projection;
    lnum viewwindowx, viewwindowy;
    lnum pspritescale, pspriteiscale;
    lnum viewangletox[FINEANGLES / 2];
    lnum xtoviewangle[SCREENWIDTH + 1];
    lnum yslope[SCREENHEIGHT];
    lnum distscale[SCREENWIDTH];
    int scalelight[LIGHTLEVELS][MAXLIGHTSCALE];
    int zlight[LIGHTLEVELS][MAXLIGHTZ];
    lnum ylookup[SCREENHEIGHT];
    lnum columnofs[SCREENWIDTH];
    lnum clipangle;

    /* quadro */
    lnum viewx, viewy, viewz, viewangle, viewsin, viewcos;
    lnum extralight;
    const uint8_t *fixedcolormap;
    uint32_t framecount;

    int ceilingclip[SCREENWIDTH];
    int floorclip[SCREENWIDTH];
    ClipRange solidsegs[MAXSOLIDSEGS];
    int newend;

    Visplane *visplanes; int numvisplanes, maxvisplanes;
    DrawSeg *drawsegs; int numdrawsegs, maxdrawsegs;
    int *openings; size_t numopenings, maxopenings;

    /* estado da BSP e do segmento atual (campos self.* do render.lua) */
    int frontsector, backsector, curline;
    const int *walllights;
    int floorplane, ceilingplane;
    lnum rw_angle1, rw_normalangle, rw_distance;
    lnum rw_x, rw_start, rw_stopx, rw_scale, rw_scalestep;
    lnum worldtop, worldbottom, worldhigh, worldlow;
    lnum midtexture, toptexture, bottomtexture;
    int maskedtexture, segtextured, markfloor, markceiling;
    int maskedtexturecol;
    lnum rw_midtexturemid, rw_toptexturemid, rw_bottomtexturemid;
    lnum rw_offset, rw_centerangle;
    lnum topfrac, topstep, bottomfrac, bottomstep;
    lnum pixhigh, pixhighstep, pixlow, pixlowstep;

    /* estado das colunas (dc_*) */
    lnum dc_x, dc_iscale;
    const uint8_t *dc_colormap;

    RLevel level;
    int *mapped_list; int nmapped, maxmapped;

    VisSprite *vissprites; int numvis, maxvis;

    const uint8_t **lump_ptr; size_t *lump_len; int nlumps;
} Renderer;

/* r_main.c */
void r_init_view(Renderer *R);
void r_set_view_size(Renderer *R, lnum blocks, lnum detail);
void r_setup_frame(Renderer *R, lnum x, lnum y, lnum z, lnum angle,
                   lnum extralight, lnum fixedcolormap);
lnum r_point_to_angle(const Renderer *R, lnum x, lnum y);
const uint8_t *r_colormap(const Renderer *R, lnum level);
void *r_grow(lua_State *L, void *ptr, int *cap, int need, size_t elem);

/* r_level.c */
lnum r_field_num(lua_State *L, int obj, const char *name); /* nil -> 0 */
void r_sync_level(lua_State *L, Renderer *R, int ud, int world_idx);
void r_free_level(RLevel *lv);
void r_mark_line(lua_State *L, Renderer *R, int line);
void r_flush_mapped(lua_State *L, Renderer *R, int ud);

/* r_bsp.c */
void r_render_bsp(lua_State *L, Renderer *R);

/* r_segs.c */
void r_store_wall_range(lua_State *L, Renderer *R, lnum start, lnum stop);
void r_render_masked_seg_range(Renderer *R, int dsi, lnum x1, lnum x2);
void r_draw_masked(Renderer *R);
int r_alloc_openings(lua_State *L, Renderer *R, size_t count);

/* r_plane.c */
void r_clear_planes(Renderer *R);
int r_find_plane(lua_State *L, Renderer *R, lnum height, lnum picnum, lnum lightlevel);
int r_check_plane(lua_State *L, Renderer *R, int pl, lnum start, lnum stop);
void r_draw_planes(Renderer *R);

/* r_things.c */
void r_draw_sprites(lua_State *L, Renderer *R, int ud, int mobjs_idx);
void r_draw_psprite(lua_State *L, Renderer *R, int ud, lnum lump, lnum sx, lnum sy);

/* r_draw.c */
void r_draw_column_pixels(Framebuffer *fb, lnum dc_x, lnum dc_yl, lnum dc_yh,
                          lnum dc_iscale, lnum dc_texturemid,
                          const uint8_t *src, size_t slen,
                          const uint8_t *cm, size_t cmlen,
                          lnum centery, lnum viewwidth, lnum detailshift,
                          lnum viewwindowx, lnum viewwindowy);
void r_draw_masked_post(Framebuffer *fb, int topdelta, const uint8_t *pixels,
                        size_t pixels_len, lnum sprtopscreen, lnum spryscale,
                        lnum mceil, lnum mfloor, lnum dc_x, lnum dc_iscale,
                        lnum basemid, const uint8_t *cm, size_t cmlen,
                        lnum centery, lnum viewwidth, lnum viewheight,
                        lnum detailshift, lnum viewwindowx, lnum viewwindowy);
int r_draw_lua_register(lua_State *L); /* draw_column/draw_masked_column */

#endif
