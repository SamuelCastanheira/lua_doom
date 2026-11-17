/*
 * r_things.c: sprites dos mobjs e da arma (psprite).
 *
 * Luz como no Doom original (R_ProjectSprite / R_DrawPSprite):
 *   MF_SHADOW -> fuzz; fixedcolormap; FF_FULLBRIGHT -> colormap 0;
 *   senao a luz do setor do sprite, diminuindo com a distancia.
 */
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "r_local.h"

static const int FUZZ_DIR[] = {
    1, -1, 1, -1, 1, 1, -1, 1, 1, -1, 1, 1, 1, -1, 1, 1, 1, -1, -1, -1, -1, 1, -1, -1, 1,
    1, 1, 1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, -1, -1, -1, 1, 1, 1, 1, -1, 1, 1, -1, 1,
};
#define FUZZ_COUNT ((int)(sizeof(FUZZ_DIR) / sizeof(FUZZ_DIR[0])))
static int fuzzpos = 0; /* global como no sprites.lua: persiste entre quadros */

static lnum rd_i16(const uint8_t *p) { return (int16_t)(p[0] | (p[1] << 8)); }
static lnum rd_u32(const uint8_t *p)
{
    return (lnum)((uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
}

/* Patch de um lump, via res:cache_lump_num; fica ancorado no cache. */
static const uint8_t *get_lump(lua_State *L, Renderer *R, int ud, lnum lump, size_t *len)
{
    if (lump < 0)
        return NULL;
    if (lump >= R->nlumps) {
        int n = (int)lump + 256;
        const uint8_t **p = (const uint8_t **)realloc(R->lump_ptr, (size_t)n * sizeof(*p));
        size_t *l = (size_t *)realloc(R->lump_len, (size_t)n * sizeof(*l));
        if (!p || !l)
            luaL_error(L, "render_c: sem memoria no cache de lumps");
        for (int i = R->nlumps; i < n; i++) {
            p[i] = NULL;
            l[i] = 0;
        }
        R->lump_ptr = p;
        R->lump_len = l;
        R->nlumps = n;
    }
    if (!R->lump_ptr[lump]) {
        int top = lua_gettop(L);
        lua_getiuservalue(L, ud, UV_LUMPS);
        int cache = lua_gettop(L);
        lua_getiuservalue(L, ud, UV_RES);
        lua_getfield(L, -1, "cache_lump_num");
        lua_pushvalue(L, -2);
        lua_pushinteger(L, lump);
        lua_call(L, 2, 1);
        if (lua_type(L, -1) != LUA_TSTRING) {
            lua_settop(L, top);
            return NULL;
        }
        lua_pushvalue(L, -1);
        lua_rawseti(L, cache, lump);
        R->lump_ptr[lump] = (const uint8_t *)lua_tolstring(L, -1, &R->lump_len[lump]);
        lua_settop(L, top);
    }
    *len = R->lump_len[lump];
    return R->lump_ptr[lump];
}

static const SpriteEntry *find_sprite(const RData *rd, const char *name, size_t len)
{
    if (len < 4)
        return NULL;
    char base[5];
    for (int i = 0; i < 4; i++)
        base[i] = (char)toupper((unsigned char)name[i]);
    base[4] = '\0';
    for (int i = 0; i < rd->sprites.count; i++) {
        if (strcmp(rd->sprites.entries[i].name, base) == 0)
            return &rd->sprites.entries[i];
    }
    return NULL;
}

static int point_on_seg_side(lnum x, lnum y, const Renderer *R, const RSeg *line)
{
    const RVertex *v1 = &R->level.vertexes[line->v1];
    const RVertex *v2 = &R->level.vertexes[line->v2];
    lnum lx = v1->x, ly = v1->y;
    lnum ldx = v2->x - lx;
    lnum ldy = v2->y - ly;
    if (ldx == 0) {
        if (x <= lx)
            return ldy > 0 ? 1 : 0;
        return ldy < 0 ? 1 : 0;
    }
    if (ldy == 0) {
        if (y <= ly)
            return ldx < 0 ? 1 : 0;
        return ldx > 0 ? 1 : 0;
    }
    lnum dx = x - lx;
    lnum dy = y - ly;
    lnum left = r_fixed_mul(r_shar(ldy, FRACBITS), dx);
    lnum right = r_fixed_mul(dy, r_shar(ldx, FRACBITS));
    return right < left ? 0 : 1;
}

static int project(lua_State *L, Renderer *R, int ud, int mo, int index, VisSprite *vis)
{
    lnum mx = 0, my = 0, mz = 0, mangle = 0, mframe = 0, mflags = 0;
    mx = r_field_num(L, mo, "x");
    my = r_field_num(L, mo, "y");
    mz = r_field_num(L, mo, "z");
    mangle = r_field_num(L, mo, "angle");
    mframe = r_field_num(L, mo, "frame");
    mflags = r_field_num(L, mo, "flags");
    size_t namelen = 0;
    lua_getfield(L, mo, "sprite");
    const char *name = lua_tolstring(L, -1, &namelen);
    char namebuf[8] = {0};
    if (name && namelen >= 4)
        memcpy(namebuf, name, 4);
    lua_pop(L, 1);

    lnum tr_x = r_i32(mx - R->viewx);
    lnum tr_y = r_i32(my - R->viewy);
    lnum gxt = r_fixed_mul(tr_x, R->viewcos);
    lnum gyt = -r_fixed_mul(tr_y, R->viewsin);
    lnum tz = gxt - gyt;
    if (tz < MINZ)
        return 0;
    lnum xscale = r_fixed_div(R->projection, tz);
    gxt = -r_fixed_mul(tr_x, R->viewsin);
    gyt = r_fixed_mul(tr_y, R->viewcos);
    lnum tx = -(gyt + gxt);
    if ((tx < 0 ? -tx : tx) > tz * 4)
        return 0;

    const SpriteEntry *entry = find_sprite(R->rd, namebuf, name ? namelen : 0);
    if (!entry)
        return 0;
    lnum fi = r_band(mframe, 32767);
    if (fi >= entry->def.frame_count)
        return 0;
    const SpriteFrame *sf = &entry->def.frames[fi];
    int rot = 0;
    if (sf->rotate != 0) {
        lnum ang = r_point_to_angle(R, mx, my);
        rot = (int)r_band(r_ushr(r_u32(ang - mangle + 2415919104LL), 29), 7);
    }
    lnum lump = sf->lump[rot];
    int flip = sf->flip[rot];
    if (lump < 0)
        return 0;

    size_t plen = 0;
    const uint8_t *patch = get_lump(L, R, ud, lump, &plen);
    if (!patch || plen < 8)
        return 0;
    lnum pw = rd_i16(patch), left = rd_i16(patch + 4), top = rd_i16(patch + 6);

    tx = tx - left * FRACUNIT;
    lnum x1 = r_shar(R->centerxfrac + r_fixed_mul(tx, xscale), FRACBITS);
    if (x1 > R->viewwidth)
        return 0;
    tx = tx + pw * FRACUNIT;
    lnum x2 = r_shar(R->centerxfrac + r_fixed_mul(tx, xscale), FRACBITS) - 1;
    if (x2 < 0)
        return 0;

    lnum iscale = xscale != 0 ? r_fixed_div(FRACUNIT, xscale) : FRACUNIT;
    lnum xiscale = iscale;
    lnum startfrac = 0;
    if (flip != 0) {
        xiscale = -iscale;
        startfrac = pw * FRACUNIT - 1;
    }
    lnum vis_x1 = x1 < 0 ? 0 : x1;
    lnum vis_x2 = x2 > R->viewwidth - 1 ? R->viewwidth - 1 : x2;
    if (vis_x1 > x1)
        startfrac += xiscale * (vis_x1 - x1);

    vis->mobj_index = index;
    vis->has_mo = 1;
    vis->fuzz = r_band(mflags, MF_SHADOW) != 0;
    if (vis->fuzz) {
        vis->colormap = NULL;
    } else if (R->fixedcolormap) {
        vis->colormap = R->fixedcolormap;
    } else if (r_band(mframe, FF_FULLBRIGHT) != 0) {
        vis->colormap = r_colormap(R, 0);
    } else {
        const int *spritelights = r_sector_lights(R, r_point_in_sector(R, mx, my));
        lnum lindex = r_shar(xscale, LIGHTSCALESHIFT - (int)R->detailshift);
        if (lindex >= MAXLIGHTSCALE)
            lindex = MAXLIGHTSCALE - 1;
        if (lindex < 0)
            lindex = 0;
        vis->colormap = r_colormap(R, spritelights[lindex]);
    }
    vis->mo_flags = mflags;
    vis->patch = patch;
    vis->patch_len = plen;
    vis->w = pw;
    vis->scale = xscale * ((lnum)1 << R->detailshift);
    vis->gx = mx;
    vis->gy = my;
    vis->gz = mz;
    vis->gzt = mz + top * FRACUNIT;
    vis->texturemid = mz + top * FRACUNIT - R->viewz;
    vis->x1 = vis_x1;
    vis->x2 = vis_x2;
    vis->xiscale = xiscale;
    vis->startfrac = startfrac;
    return 1;
}

static void clip_against_walls(Renderer *R, const VisSprite *spr, lnum *cliptop, lnum *clipbot)
{
    lnum x1 = spr->x1, x2 = spr->x2;
    for (int i = 0; i < SCREENWIDTH; i++) {
        clipbot[i] = -2;
        cliptop[i] = -2;
    }
    for (int n = R->numdrawsegs - 1; n >= 0; n--) {
        const DrawSeg *ds = &R->drawsegs[n];
        if (ds->x1 > x2 || ds->x2 < x1)
            continue;
        if (ds->silhouette == 0 && ds->maskedtexturecol < 0)
            continue;
        lnum r1 = ds->x1 < x1 ? x1 : ds->x1;
        lnum r2 = ds->x2 > x2 ? x2 : ds->x2;
        lnum scale = ds->scale2 > ds->scale1 ? ds->scale2 : ds->scale1;
        lnum lowscale = ds->scale2 < ds->scale1 ? ds->scale2 : ds->scale1;
        int in_front = scale < spr->scale
            || (lowscale < spr->scale && ds->curline >= 0
                && point_on_seg_side(spr->gx, spr->gy, R, &R->level.segs[ds->curline]) == 0);
        if (in_front) {
            if (ds->maskedtexturecol >= 0)
                r_render_masked_seg_range(R, n, r1, r2);
            continue;
        }
        int silhouette = ds->silhouette;
        if (spr->gz >= ds->bsilheight)
            silhouette &= ~SIL_BOTTOM;
        if (spr->gzt <= ds->tsilheight)
            silhouette &= ~SIL_TOP;
        for (lnum x = r1; x <= r2; x++) {
            lnum i = x - ds->x1;
            if (i >= 0 && ds->sprtopclip >= 0 && i < ds->clip_count) {
                if ((silhouette & SIL_BOTTOM) && clipbot[x] == -2)
                    clipbot[x] = R->openings[ds->sprbottomclip + i];
                if ((silhouette & SIL_TOP) && cliptop[x] == -2)
                    cliptop[x] = R->openings[ds->sprtopclip + i];
            }
        }
    }
    for (lnum x = x1; x <= x2; x++) {
        if (clipbot[x] == -2)
            clipbot[x] = R->viewheight;
        if (cliptop[x] == -2)
            cliptop[x] = -1;
    }
}

static void draw_fuzz_pixel(Renderer *R, lnum x, lnum y, const uint8_t *cm)
{
    uint8_t *fb = R->fb->pixels;
    lnum colx = R->detailshift != 0 ? x * 2 : x;
    lnum dest = R->ylookup[y] + R->columnofs[colx];
    lnum src = dest + FUZZ_DIR[fuzzpos] * SCREENWIDTH;
    fuzzpos++;
    if (fuzzpos >= FUZZ_COUNT)
        fuzzpos = 0;
    if (src < 0 || src >= PIXELS)
        src = dest;
    uint8_t pix = (src >= 0 && src < PIXELS) ? fb[src] : 0;
    uint8_t val = cm[pix];
    if (dest >= 0 && dest < PIXELS) {
        fb[dest] = val;
        R_TAG(dest);
    }
    if (R->detailshift != 0 && dest + 1 < PIXELS && dest + 1 >= 0) {
        fb[dest + 1] = val;
        R_TAG(dest + 1);
    }
}

static void draw_one(Renderer *R, const VisSprite *spr, int clip_walls)
{
    const uint8_t *patch = spr->patch;
    size_t plen = spr->patch_len;
    lnum patch_w = spr->w;
    lnum iscale = spr->xiscale;
    lnum spryscale = spr->scale;
    lnum y_iscale = iscale < 0 ? -iscale : iscale;
    if (R->detailshift > 0)
        y_iscale = r_floordiv(y_iscale, (lnum)1 << R->detailshift);
    if (y_iscale < 1)
        y_iscale = 1;
    lnum sprtopscreen = R->centeryfrac - r_fixed_mul(spr->texturemid, spryscale);

    lnum cliptop[SCREENWIDTH], clipbot[SCREENWIDTH];
    if (clip_walls) {
        clip_against_walls(R, spr, cliptop, clipbot);
    } else {
        for (int i = 0; i < SCREENWIDTH; i++) {
            cliptop[i] = -1;
            clipbot[i] = R->viewheight;
        }
    }

    int fuzz = spr->fuzz;
    const uint8_t *cm = fuzz ? r_colormap(R, 6) : spr->colormap;

    uint8_t *fb = R->fb->pixels;
    uint8_t sprite_tag = clip_walls ? TAG_SPRITE : TAG_PSPRITE;
    lnum frac = spr->startfrac;
    for (lnum x = spr->x1; x <= spr->x2; x++, frac += iscale) {
        lnum col = r_shar(frac, FRACBITS);
        if (col < 0 || col >= patch_w)
            continue;
        size_t entry = 8 + (size_t)col * 4;
        if (entry + 4 > plen)
            continue;
        lnum column = rd_u32(patch + entry);
        r_tag = sprite_tag; /* clip_against_walls pode ter mudado r_tag */
        while (column >= 0 && (size_t)column < plen) {
            lnum topdelta = patch[column];
            if (topdelta == 255)
                break;
            if ((size_t)column + 1 >= plen)
                break;
            lnum length = patch[column + 1];
            lnum source = column + 3;
            lnum topscreen = sprtopscreen + spryscale * topdelta;
            lnum bottomscreen = topscreen + spryscale * length;
            lnum yl = r_shar(topscreen + FRACUNIT - 1, FRACBITS);
            lnum yh = r_shar(bottomscreen - 1, FRACBITS);
            if (yl <= cliptop[x]) yl = cliptop[x] + 1;
            if (yh >= clipbot[x]) yh = clipbot[x] - 1;
            if (yl < 0) yl = 0;
            if (yh >= R->viewheight) yh = R->viewheight - 1;
            if (fuzz) {
                if (yl <= 0) yl = 1;
                if (yh >= R->viewheight - 1) yh = R->viewheight - 2;
            }
            if (yl <= yh) {
                lnum texfrac = r_fixed_mul(yl * FRACUNIT - topscreen, y_iscale);
                if (texfrac < 0)
                    texfrac = 0;
                for (lnum y = yl; y <= yh; y++, texfrac += y_iscale) {
                    if (fuzz) {
                        draw_fuzz_pixel(R, x, y, cm);
                        continue;
                    }
                    lnum idx = r_shar(texfrac, FRACBITS);
                    if (idx < 0 || idx >= length)
                        continue;
                    if ((size_t)(source + idx) >= plen)
                        continue;
                    uint8_t val = cm[patch[source + idx]];
                    if (R->detailshift != 0) {
                        lnum off = R->ylookup[y] + R->columnofs[x * 2];
                        if (off >= 0 && off < PIXELS) {
                            fb[off] = val;
                            R_TAG(off);
                            if (off + 1 < PIXELS) {
                                fb[off + 1] = val;
                                R_TAG(off + 1);
                            }
                        }
                    } else {
                        lnum off = R->ylookup[y] + R->columnofs[x];
                        if (off >= 0 && off < PIXELS) {
                            fb[off] = val;
                            R_TAG(off);
                        }
                    }
                }
            }
            column += length + 4;
        }
    }
}

static int cmp_vis(const void *a, const void *b)
{
    const VisSprite *va = (const VisSprite *)a;
    const VisSprite *vb = (const VisSprite *)b;
    if (va->scale != vb->scale)
        return va->scale < vb->scale ? -1 : 1;
    return va->mobj_index < vb->mobj_index ? -1 : (va->mobj_index > vb->mobj_index);
}

void r_draw_sprites(lua_State *L, Renderer *R, int ud, int mobjs)
{
    mobjs = lua_absindex(L, mobjs);
    R->numvis = 0;
    int n = (int)lua_rawlen(L, mobjs);
    for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, mobjs, i);
        int mo = lua_gettop(L);
        if (!lua_istable(L, mo)) {
            lua_pop(L, 1);
            continue;
        }
        lua_getfield(L, mo, "sprite");
        size_t slen = 0;
        const char *s = lua_tolstring(L, -1, &slen);
        int has_sprite = s != NULL && slen > 0;
        lua_getfield(L, mo, "player");
        int is_player = lua_toboolean(L, -1);
        lua_pop(L, 2);
        lnum flags = r_field_num(L, mo, "flags");
        if (has_sprite && !is_player && r_band(flags, MF_NOSECTOR) == 0) {
            R->vissprites = (VisSprite *)r_grow(L, R->vissprites, &R->maxvis,
                                                R->numvis + 1, sizeof(VisSprite));
            if (project(L, R, ud, mo, R->numvis, &R->vissprites[R->numvis]))
                R->numvis++;
        }
        lua_pop(L, 1);
    }
    qsort(R->vissprites, (size_t)R->numvis, sizeof(VisSprite), cmp_vis);
    for (int i = 0; i < R->numvis; i++)
        draw_one(R, &R->vissprites[i], 1);
}

void r_draw_psprite(lua_State *L, Renderer *R, int ud, lnum lump, lnum sx, lnum sy,
                    int fullbright, int shadow)
{
    size_t plen = 0;
    const uint8_t *patch = get_lump(L, R, ud, lump, &plen);
    if (!patch || plen < 8)
        return;
    lnum w = rd_i16(patch), left = rd_i16(patch + 4), top = rd_i16(patch + 6);
    lnum tx = sx - 160 * FRACUNIT;
    tx = tx - left * FRACUNIT;
    lnum x1 = r_shar(R->centerxfrac + r_fixed_mul(tx, R->pspritescale), FRACBITS);
    if (x1 > R->viewwidth)
        return;
    tx = tx + w * FRACUNIT;
    lnum x2 = r_shar(R->centerxfrac + r_fixed_mul(tx, R->pspritescale), FRACBITS) - 1;
    if (x2 < 0)
        return;
    lnum vis_x1 = x1 < 0 ? 0 : x1;
    lnum vis_x2 = x2 > R->viewwidth - 1 ? R->viewwidth - 1 : x2;
    lnum startfrac = 0;
    if (vis_x1 > x1)
        startfrac += R->pspriteiscale * (vis_x1 - x1);

    VisSprite vis;
    memset(&vis, 0, sizeof(vis));
    vis.has_mo = 0;
    vis.fuzz = shadow;
    if (shadow)
        vis.colormap = NULL;
    else if (R->fixedcolormap)
        vis.colormap = R->fixedcolormap;
    else if (fullbright)
        vis.colormap = r_colormap(R, 0);
    else
        vis.colormap = r_colormap(R, r_sector_lights(R, r_point_in_sector(R, R->viewx, R->viewy))[MAXLIGHTSCALE - 1]);
    vis.patch = patch;
    vis.patch_len = plen;
    vis.w = w;
    vis.scale = R->pspritescale * ((lnum)1 << R->detailshift);
    vis.texturemid = 100 * FRACUNIT + FRACUNIT / 2 - (sy - top * FRACUNIT);
    vis.x1 = vis_x1;
    vis.x2 = vis_x2;
    vis.xiscale = R->pspriteiscale;
    vis.startfrac = startfrac;
    draw_one(R, &vis, 0);
}
