/* r_segs.c: paredes, drawsegs e texturas mascaradas. */
#include <stdlib.h>
#include <string.h>

#include "r_local.h"

int r_alloc_openings(lua_State *L, Renderer *R, size_t count)
{
    size_t need = R->numopenings + count;
    if (need > R->maxopenings) {
        size_t cap = R->maxopenings ? R->maxopenings : 16384;
        while (cap < need)
            cap *= 2;
        int *p = (int *)realloc(R->openings, cap * sizeof(int));
        if (!p)
            luaL_error(L, "render_c: sem memoria para openings");
        R->openings = p;
        R->maxopenings = cap;
    }
    int ofs = (int)R->numopenings;
    R->numopenings = need;
    return ofs;
}

static lnum texture_height(lua_State *L, const Renderer *R, lnum texnum)
{
    if (texnum < 0 || texnum >= R->rd->texture_count)
        luaL_error(L, "r_data_c: invalid texture number");
    return (lnum)R->rd->textures[texnum].height * FRACUNIT;
}

static const uint8_t *wall_column(lua_State *L, const Renderer *R, lnum texnum, lnum col)
{
    if (texnum < 0 || texnum >= R->rd->texture_count)
        luaL_error(L, "r_data_c: invalid texture number");
    const Texture *tex = &R->rd->textures[texnum];
    uint32_t c = (uint32_t)col & (uint32_t)tex->widthmask;
    return tex->wall128 + (size_t)c * RD_COLUMN_SIZE;
}

static lnum scale_from_global_angle(const Renderer *R, lnum visangle)
{
    const int32_t *finesine = R->tables->finesine;
    lnum anglea = r_u32(ANG90 + r_u32(visangle - R->viewangle));
    lnum angleb = r_u32(ANG90 + r_u32(visangle - R->rw_normalangle));
    lnum sinea = finesine[r_band(r_ushr(anglea, ANGLETOFINESHIFT), FINEMASK)];
    lnum sineb = finesine[r_band(r_ushr(angleb, ANGLETOFINESHIFT), FINEMASK)];
    lnum num = r_fixed_mul(R->projection, sineb) * ((lnum)1 << R->detailshift);
    lnum den = r_fixed_mul(R->rw_distance, sinea);
    lnum scale;
    if (den > r_ushr(num, 16) && den != 0) {
        scale = r_fixed_div(num, den);
        if (scale > 64 * FRACUNIT)
            scale = 64 * FRACUNIT;
        else if (scale < 256)
            scale = 256;
    } else {
        scale = 64 * FRACUNIT;
    }
    return scale;
}

static lnum point_to_dist(const Renderer *R, lnum x, lnum y)
{
    lnum dx = r_abs_fixed(x - R->viewx);
    lnum dy = r_abs_fixed(y - R->viewy);
    if (dy > dx) {
        lnum t = dx;
        dx = dy;
        dy = t;
    }
    if (dx == 0)
        return 0;
    lnum frac = r_fixed_div(dy, dx);
    lnum idx = r_shar(frac, DBITS);
    if (idx > SLOPERANGE) idx = SLOPERANGE;
    if (idx < 0) idx = 0;
    lnum ang = r_ushr((lnum)R->tables->tantoangle[idx] + ANG90, ANGLETOFINESHIFT);
    return r_fixed_div(dx, R->tables->finesine[r_band(ang, FINEMASK)]);
}

/* render_seg_loop: igual a l_render_seg_loop da versao hibrida. */
static void render_seg_loop(lua_State *L, Renderer *R)
{
    lnum rw_x = R->rw_x;
    lnum rw_stopx = R->rw_stopx;
    lnum rw_start = R->rw_start;
    lnum rw_distance = R->rw_distance;
    lnum rw_scale = R->rw_scale;
    lnum rw_scalestep = R->rw_scalestep;
    lnum topfrac = R->topfrac, topstep = R->topstep;
    lnum bottomfrac = R->bottomfrac, bottomstep = R->bottomstep;
    lnum viewheight = R->viewheight;
    int segtextured = R->segtextured;
    int markceiling = R->markceiling;
    int markfloor = R->markfloor;
    lnum midtexture = R->midtexture;
    lnum toptexture = R->toptexture;
    lnum bottomtexture = R->bottomtexture;
    int masked = R->maskedtexture && R->maskedtexturecol >= 0;
    Visplane *ceilingplane = R->ceilingplane >= 0 ? &R->visplanes[R->ceilingplane] : NULL;
    Visplane *floorplane = R->floorplane >= 0 ? &R->visplanes[R->floorplane] : NULL;

    lnum texturecolumn = 0;
    lnum rw_centerangle = segtextured ? R->rw_centerangle : 0;
    lnum rw_offset = segtextured ? R->rw_offset : 0;
    lnum pixhigh = 0, pixhighstep = 0, pixlow = 0, pixlowstep = 0;
    if (toptexture != 0) {
        pixhigh = R->pixhigh;
        pixhighstep = R->pixhighstep;
    }
    if (bottomtexture != 0) {
        pixlow = R->pixlow;
        pixlowstep = R->pixlowstep;
    }
    lnum rw_midtexturemid = midtexture != 0 ? R->rw_midtexturemid : 0;
    lnum rw_toptexturemid = toptexture != 0 ? R->rw_toptexturemid : 0;
    lnum rw_bottomtexturemid = bottomtexture != 0 ? R->rw_bottomtexturemid : 0;

    int *ceilingclip = R->ceilingclip;
    int *floorclip = R->floorclip;

#define DRAW_COL(yl_, yh_, mid_, tex_) \
    r_draw_column_pixels(R->fb, R->dc_x, (yl_), (yh_), R->dc_iscale, (mid_), \
        wall_column(L, R, (tex_), texturecolumn), RD_COLUMN_SIZE, \
        R->dc_colormap, 256, R->centery, R->viewwidth, R->detailshift, \
        R->viewwindowx, R->viewwindowy)

    while (rw_x < rw_stopx) {
        int x = (int)rw_x;
        lnum ceiling = ceilingclip[x];
        lnum floor = floorclip[x];

        lnum yl = r_shar(topfrac + HEIGHTUNIT - 1, HEIGHTBITS);
        if (yl < ceiling + 1)
            yl = ceiling + 1;

        if (markceiling && ceilingplane) {
            lnum top = ceiling + 1;
            lnum bottom = yl - 1;
            if (bottom >= floor)
                bottom = floor - 1;
            if (top <= bottom) {
                ceilingplane->top[x] = (int16_t)top;
                ceilingplane->bottom[x] = (int16_t)bottom;
            }
        }

        lnum yh = r_shar(bottomfrac, HEIGHTBITS);
        if (yh >= floor)
            yh = floor - 1;

        if (markfloor && floorplane) {
            lnum top = yh + 1;
            lnum bottom = floor - 1;
            if (top <= ceiling)
                top = ceiling + 1;
            if (top <= bottom) {
                floorplane->top[x] = (int16_t)top;
                floorplane->bottom[x] = (int16_t)bottom;
            }
        }

        if (segtextured) {
            uint32_t angle = (uint32_t)r_i32(rw_centerangle + R->xtoviewangle[x]);
            angle >>= ANGLETOFINESHIFT;
            angle &= (FINEANGLES / 2) - 1;
            lnum tanv = R->tables->finetangent[angle];
            texturecolumn = r_shar(rw_offset - r_fixed_mul(tanv, r_i32(rw_distance)), FRACBITS);

            uint32_t light_index = (uint32_t)rw_scale >> LIGHTSCALESHIFT;
            if (light_index >= MAXLIGHTSCALE)
                light_index = MAXLIGHTSCALE - 1;
            if (R->fixedcolormap)
                R->dc_colormap = R->fixedcolormap;
            else
                R->dc_colormap = r_colormap(R, R->walllights[light_index]);
            R->dc_x = rw_x;
            R->dc_iscale = rw_scale != 0 ? 4294967295LL / rw_scale : 0;
        }

        if (midtexture != 0) {
            DRAW_COL(yl, yh, rw_midtexturemid, midtexture);
            ceilingclip[x] = (int)viewheight;
            floorclip[x] = -1;
        } else {
            if (toptexture != 0) {
                lnum mid = r_shar(pixhigh, HEIGHTBITS);
                pixhigh += pixhighstep;
                if (mid >= floor)
                    mid = floor - 1;
                if (mid >= yl) {
                    DRAW_COL(yl, mid, rw_toptexturemid, toptexture);
                    ceilingclip[x] = (int)mid;
                } else {
                    ceilingclip[x] = (int)(yl - 1);
                }
            } else if (markceiling) {
                ceilingclip[x] = (int)(yl - 1);
            }

            if (bottomtexture != 0) {
                lnum mid = r_shar(pixlow + HEIGHTUNIT - 1, HEIGHTBITS);
                pixlow += pixlowstep;
                lnum current_ceiling = ceilingclip[x];
                if (mid <= current_ceiling)
                    mid = current_ceiling + 1;
                if (mid <= yh) {
                    DRAW_COL(mid, yh, rw_bottomtexturemid, bottomtexture);
                    floorclip[x] = (int)mid;
                } else {
                    floorclip[x] = (int)(yh + 1);
                }
            } else if (markfloor) {
                floorclip[x] = (int)(yh + 1);
            }

            if (masked)
                R->openings[R->maskedtexturecol + (rw_x - rw_start)] = (int)texturecolumn;
        }

        rw_scale += rw_scalestep;
        topfrac += topstep;
        bottomfrac += bottomstep;
        rw_x++;
    }
#undef DRAW_COL

    R->rw_x = rw_x;
    R->rw_scale = rw_scale;
    R->topfrac = topfrac;
    R->bottomfrac = bottomfrac;
    R->pixhigh = pixhigh;
    R->pixlow = pixlow;
}

static void push_drawseg(lua_State *L, Renderer *R, lnum start, lnum stop, lnum scale1)
{
    R->drawsegs = (DrawSeg *)r_grow(L, R->drawsegs, &R->maxdrawsegs,
                                    R->numdrawsegs + 1, sizeof(DrawSeg));
    DrawSeg *ds = &R->drawsegs[R->numdrawsegs++];
    const RSector *front = &R->level.sectors[R->frontsector];
    lnum width = stop - start + 1;

    ds->x1 = start;
    ds->x2 = stop;
    ds->scale1 = scale1;
    ds->scale2 = scale1 + R->rw_scalestep * (stop - start > 0 ? stop - start : 0);
    ds->curline = R->curline;
    ds->scalestep = R->rw_scalestep;
    ds->maskedtexturecol = R->maskedtexturecol;
    ds->masked_count = R->maskedtexturecol >= 0 ? (int)width : 0;
    ds->silhouette = SIL_NONE;
    ds->bsilheight = 0;
    ds->tsilheight = 0;
    ds->sprtopclip = -1;
    ds->sprbottomclip = -1;
    ds->clip_count = 0;

    if (R->backsector < 0) {
        ds->silhouette = SIL_BOTH;
        ds->bsilheight = R_INT_MAX;
        ds->tsilheight = R_INT_MIN;
        int top = r_alloc_openings(L, R, (size_t)width);
        int bot = r_alloc_openings(L, R, (size_t)width);
        for (lnum i = 0; i < width; i++) {
            R->openings[top + i] = (int)R->viewheight;
            R->openings[bot + i] = -1;
        }
        ds = &R->drawsegs[R->numdrawsegs - 1];
        ds->sprtopclip = top;
        ds->sprbottomclip = bot;
        ds->clip_count = (int)width;
        return;
    }

    const RSector *back = &R->level.sectors[R->backsector];
    if (front->floorheight > back->floorheight) {
        ds->silhouette = SIL_BOTTOM;
        ds->bsilheight = front->floorheight;
    } else if (back->floorheight > R->viewz) {
        ds->silhouette = SIL_BOTTOM;
        ds->bsilheight = R_INT_MAX;
    }
    if (front->ceilingheight < back->ceilingheight) {
        ds->silhouette |= SIL_TOP;
        ds->tsilheight = front->ceilingheight;
    } else if (back->ceilingheight < R->viewz) {
        ds->silhouette |= SIL_TOP;
        ds->tsilheight = R_INT_MIN;
    }
    if (back->ceilingheight <= front->floorheight) {
        ds->silhouette |= SIL_BOTTOM;
        ds->bsilheight = R_INT_MAX;
    }
    if (back->floorheight >= front->ceilingheight) {
        ds->silhouette |= SIL_TOP;
        ds->tsilheight = R_INT_MIN;
    }

    lnum n = width > 0 ? width : 0;
    int top = r_alloc_openings(L, R, (size_t)n);
    int bot = r_alloc_openings(L, R, (size_t)n);
    for (lnum i = 0; i < n; i++) {
        R->openings[top + i] = R->ceilingclip[start + i];
        R->openings[bot + i] = R->floorclip[start + i];
    }
    ds = &R->drawsegs[R->numdrawsegs - 1];
    ds->sprtopclip = top;
    ds->sprbottomclip = bot;
    ds->clip_count = (int)n;

    if (R->maskedtexture) {
        if ((ds->silhouette & SIL_TOP) == 0) {
            ds->silhouette |= SIL_TOP;
            ds->tsilheight = R_INT_MIN;
        }
        if ((ds->silhouette & SIL_BOTTOM) == 0) {
            ds->silhouette |= SIL_BOTTOM;
            ds->bsilheight = R_INT_MAX;
        }
    }
}

void r_store_wall_range(lua_State *L, Renderer *R, lnum start, lnum stop)
{
    if (start > stop)
        return;

    const RLevel *lv = &R->level;
    const RSeg *line = &lv->segs[R->curline];
    const RLine *linedef = &lv->lines[line->linedef];
    const RSide *sidedef = &lv->sides[line->sidedef];
    const RSector *front = &lv->sectors[R->frontsector];
    const RSector *back = R->backsector >= 0 ? &lv->sectors[R->backsector] : NULL;
    const int32_t *finesine = R->tables->finesine;
    lnum skyflatnum = R->rd->skyflatnum;

    r_mark_line(L, R, line->linedef);

    R->rw_normalangle = r_u32(line->angle + ANG90);
    lnum offsetangle = r_u32(R->rw_normalangle - R->rw_angle1);
    if (offsetangle > ANG180)
        offsetangle = r_u32(-offsetangle);
    if (offsetangle > ANG90)
        offsetangle = ANG90;
    lnum distangle = r_u32(ANG90 - offsetangle);
    const RVertex *v1 = &lv->vertexes[line->v1];
    lnum hyp = point_to_dist(R, v1->x, v1->y);
    R->rw_distance = r_fixed_mul(hyp, finesine[r_band(r_ushr(distangle, ANGLETOFINESHIFT), FINEMASK)]);
    R->rw_x = start;
    R->rw_start = start;
    R->rw_stopx = stop + 1;
    R->rw_scale = scale_from_global_angle(R, r_u32(R->viewangle + R->xtoviewangle[start]));
    if (stop > start) {
        lnum scale2 = scale_from_global_angle(R, r_u32(R->viewangle + R->xtoviewangle[stop]));
        R->rw_scalestep = r_idiv(scale2 - R->rw_scale, stop - start);
    } else {
        R->rw_scalestep = 0;
    }

    R->worldtop = front->ceilingheight - R->viewz;
    R->worldbottom = front->floorheight - R->viewz;
    R->midtexture = 0;
    R->toptexture = 0;
    R->bottomtexture = 0;
    R->maskedtexture = 0;
    R->maskedtexturecol = -1;
    R->segtextured = 0;

    if (!back) {
        R->midtexture = sidedef->midtexture;
        R->markfloor = 1;
        R->markceiling = 1;
        if (r_band(linedef->flags, ML_DONTPEGBOTTOM) != 0) {
            lnum vtop = front->floorheight + texture_height(L, R, R->midtexture);
            R->rw_midtexturemid = vtop - R->viewz;
        } else {
            R->rw_midtexturemid = R->worldtop;
        }
        R->rw_midtexturemid += sidedef->rowoffset;
    } else {
        R->worldhigh = back->ceilingheight - R->viewz;
        R->worldlow = back->floorheight - R->viewz;
        if (front->ceilingpic == skyflatnum && back->ceilingpic == skyflatnum)
            R->worldtop = R->worldhigh;
        R->markfloor = R->worldlow != R->worldbottom
            || back->floorpic != front->floorpic
            || back->lightlevel != front->lightlevel;
        R->markceiling = R->worldhigh != R->worldtop
            || back->ceilingpic != front->ceilingpic
            || back->lightlevel != front->lightlevel;
        if (back->ceilingheight <= front->floorheight
            || back->floorheight >= front->ceilingheight) {
            R->markceiling = 1;
            R->markfloor = 1;
        }
        if (R->worldhigh < R->worldtop) {
            R->toptexture = sidedef->toptexture;
            if (r_band(linedef->flags, ML_DONTPEGTOP) != 0) {
                R->rw_toptexturemid = R->worldtop;
            } else {
                lnum vtop = back->ceilingheight + texture_height(L, R, R->toptexture);
                R->rw_toptexturemid = vtop - R->viewz;
            }
        }
        if (R->worldlow > R->worldbottom) {
            R->bottomtexture = sidedef->bottomtexture;
            if (r_band(linedef->flags, ML_DONTPEGBOTTOM) != 0)
                R->rw_bottomtexturemid = R->worldtop;
            else
                R->rw_bottomtexturemid = R->worldlow;
        }
        R->rw_toptexturemid += sidedef->rowoffset;
        R->rw_bottomtexturemid += sidedef->rowoffset;
        if (sidedef->midtexture != 0) {
            R->maskedtexture = 1;
            lnum n = stop - start + 1;
            R->maskedtexturecol = r_alloc_openings(L, R, (size_t)n);
            for (lnum i = 0; i < n; i++)
                R->openings[R->maskedtexturecol + i] = R_SHRT_MAX;
        }
    }

    R->segtextured = R->midtexture != 0 || R->toptexture != 0
        || R->bottomtexture != 0 || R->maskedtexture;
    if (R->segtextured) {
        offsetangle = r_u32(R->rw_normalangle - R->rw_angle1);
        if (offsetangle > ANG180)
            offsetangle = r_u32(-offsetangle);
        R->rw_offset = r_fixed_mul(hyp, finesine[r_band(r_ushr(offsetangle, ANGLETOFINESHIFT), FINEMASK)]);
        if (r_u32(R->rw_normalangle - R->rw_angle1) < ANG180)
            R->rw_offset = -R->rw_offset;
        R->rw_offset = R->rw_offset + sidedef->textureoffset + line->offset;
        R->rw_centerangle = r_u32(ANG90 + R->viewangle - R->rw_normalangle);
    }

    if (front->floorheight >= R->viewz)
        R->markfloor = 0;
    if (front->ceilingheight <= R->viewz && front->ceilingpic != skyflatnum)
        R->markceiling = 0;
    if (R->markceiling)
        R->ceilingplane = r_check_plane(L, R, R->ceilingplane, start, stop);
    if (R->markfloor)
        R->floorplane = r_check_plane(L, R, R->floorplane, start, stop);

    lnum cy4 = r_shar(R->centeryfrac, 4);
    R->worldtop = r_shar(R->worldtop, 4);
    R->worldbottom = r_shar(R->worldbottom, 4);
    R->topstep = -r_fixed_mul(R->rw_scalestep, R->worldtop);
    R->topfrac = cy4 - r_fixed_mul(R->worldtop, R->rw_scale);
    R->bottomstep = -r_fixed_mul(R->rw_scalestep, R->worldbottom);
    R->bottomfrac = cy4 - r_fixed_mul(R->worldbottom, R->rw_scale);
    if (back) {
        R->worldhigh = r_shar(R->worldhigh, 4);
        R->worldlow = r_shar(R->worldlow, 4);
        if (R->worldhigh < R->worldtop) {
            R->pixhigh = cy4 - r_fixed_mul(R->worldhigh, R->rw_scale);
            R->pixhighstep = -r_fixed_mul(R->rw_scalestep, R->worldhigh);
        }
        if (R->worldlow > R->worldbottom) {
            R->pixlow = cy4 - r_fixed_mul(R->worldlow, R->rw_scale);
            R->pixlowstep = -r_fixed_mul(R->rw_scalestep, R->worldlow);
        }
    }

    lnum scale1 = R->rw_scale;
    render_seg_loop(L, R);
    push_drawseg(L, R, start, stop, scale1);
}

void r_render_masked_seg_range(Renderer *R, int dsi, lnum x1, lnum x2)
{
    DrawSeg *ds = &R->drawsegs[dsi];
    if (ds->maskedtexturecol < 0 || ds->curline < 0)
        return;
    const RLevel *lv = &R->level;
    const RSeg *line = &lv->segs[ds->curline];
    if (line->frontsector < 0 || line->backsector < 0 || line->sidedef < 0)
        return;
    const RSector *front = &lv->sectors[line->frontsector];
    const RSector *back = &lv->sectors[line->backsector];
    const RSide *sidedef = &lv->sides[line->sidedef];
    lnum texnum = sidedef->midtexture;
    if (texnum == 0)
        return;

    lnum lightnum = r_ushr(front->lightlevel, 4) + R->extralight;
    const RVertex *v1 = &lv->vertexes[line->v1];
    const RVertex *v2 = &lv->vertexes[line->v2];
    if (v1->y == v2->y)
        lightnum--;
    else if (v1->x == v2->x)
        lightnum++;
    if (lightnum < 0) lightnum = 0;
    if (lightnum > LIGHTLEVELS - 1) lightnum = LIGHTLEVELS - 1;
    const int *walllights = R->scalelight[lightnum];

    const Texture *tex = (texnum > 0 && texnum < R->rd->texture_count)
        ? &R->rd->textures[texnum] : NULL;

    lnum mid;
    if (r_band(lv->lines[line->linedef].flags, ML_DONTPEGBOTTOM) != 0) {
        mid = front->floorheight;
        if (back->floorheight > mid)
            mid = back->floorheight;
        mid = mid + (tex ? (lnum)tex->height * FRACUNIT : 0) - R->viewz;
    } else {
        mid = front->ceilingheight;
        if (back->ceilingheight < mid)
            mid = back->ceilingheight;
        mid = mid - R->viewz;
    }
    mid += sidedef->rowoffset;

    lnum spryscale = ds->scale1 + (x1 - ds->x1) * ds->scalestep;
    for (lnum dc_x = x1; dc_x <= x2; dc_x++) {
        lnum i = dc_x - ds->x1;
        if (i < 0 || i >= ds->masked_count) {
            spryscale += ds->scalestep;
            continue;
        }
        int *tcolp = &R->openings[ds->maskedtexturecol + i];
        if (*tcolp != R_SHRT_MAX) {
            lnum index = spryscale > 0 ? r_ushr(spryscale, LIGHTSCALESHIFT) : 0;
            if (index >= MAXLIGHTSCALE)
                index = MAXLIGHTSCALE - 1;
            const uint8_t *cm = R->fixedcolormap ? R->fixedcolormap
                                                 : r_colormap(R, walllights[index]);
            lnum iscale = spryscale != 0 ? r_floordiv(4294967295LL, spryscale) : 0;
            lnum sprtopscreen = R->centeryfrac - r_fixed_mul(mid, spryscale);
            lnum mceil = (ds->sprtopclip >= 0 && i < ds->clip_count)
                ? R->openings[ds->sprtopclip + i] : -1;
            lnum mfloor = (ds->sprbottomclip >= 0 && i < ds->clip_count)
                ? R->openings[ds->sprbottomclip + i] : R->viewheight;

            if (tex && tex->mposts) {
                uint32_t col = (uint32_t)(lnum)*tcolp & (uint32_t)tex->widthmask;
                for (int p = tex->mpost_first[col]; p < tex->mpost_first[col + 1]; p++) {
                    const MaskedPost *post = &tex->mposts[p];
                    r_draw_masked_post(R->fb, post->topdelta, tex->mpix + post->pixofs,
                                       (size_t)post->length, sprtopscreen, spryscale,
                                       mceil, mfloor, dc_x, iscale, mid, cm, 256,
                                       R->centery, R->viewwidth, R->viewheight,
                                       R->detailshift, R->viewwindowx, R->viewwindowy);
                }
            }
            *tcolp = R_SHRT_MAX;
        }
        spryscale += ds->scalestep;
    }
}

void r_draw_masked(Renderer *R)
{
    for (int n = R->numdrawsegs - 1; n >= 0; n--) {
        if (R->drawsegs[n].maskedtexturecol >= 0)
            r_render_masked_seg_range(R, n, R->drawsegs[n].x1, R->drawsegs[n].x2);
    }
}
