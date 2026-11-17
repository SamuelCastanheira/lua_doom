/* r_plane.c: visplanes, chao, teto e ceu. */
#include <stdlib.h>
#include <string.h>

#include "r_local.h"

void r_clear_planes(Renderer *R)
{
    R->numvisplanes = 0;
}

static int new_plane(lua_State *L, Renderer *R, lnum height, lnum picnum,
                     lnum lightlevel, lnum minx, lnum maxx)
{
    R->visplanes = (Visplane *)r_grow(L, R->visplanes, &R->maxvisplanes,
                                      R->numvisplanes + 1, sizeof(Visplane));
    int idx = R->numvisplanes++;
    Visplane *pl = &R->visplanes[idx];
    pl->height = height;
    pl->picnum = picnum;
    pl->lightlevel = lightlevel;
    pl->minx = minx;
    pl->maxx = maxx;
    for (int x = 0; x < SCREENWIDTH; x++) {
        pl->top[x] = 255;
        pl->bottom[x] = 0;
    }
    return idx;
}

int r_find_plane(lua_State *L, Renderer *R, lnum height, lnum picnum, lnum lightlevel)
{
    if (picnum == R->rd->skyflatnum) {
        height = 0;
        lightlevel = 0;
    }
    for (int i = 0; i < R->numvisplanes; i++) {
        const Visplane *pl = &R->visplanes[i];
        if (pl->height == height && pl->picnum == picnum && pl->lightlevel == lightlevel)
            return i;
    }
    return new_plane(L, R, height, picnum, lightlevel, R->viewwidth, -1);
}

int r_check_plane(lua_State *L, Renderer *R, int idx, lnum start, lnum stop)
{
    if (idx < 0)
        return new_plane(L, R, 0, 0, 0, R->viewwidth, -1);

    Visplane *pl = &R->visplanes[idx];
    lnum intrl, unionl, intrh, unionh;
    if (start < pl->minx) {
        intrl = pl->minx;
        unionl = start;
    } else {
        unionl = pl->minx;
        intrl = start;
    }
    if (stop > pl->maxx) {
        intrh = pl->maxx;
        unionh = stop;
    } else {
        unionh = pl->maxx;
        intrh = stop;
    }

    lnum x = intrl;
    while (x <= intrh) {
        if (x >= 0 && x < SCREENWIDTH && pl->top[x] != 255)
            break;
        x++;
    }
    if (x > intrh) {
        pl->minx = unionl;
        pl->maxx = unionh;
        return idx;
    }
    lnum height = pl->height, picnum = pl->picnum, light = pl->lightlevel;
    return new_plane(L, R, height, picnum, light, start, stop);
}

static void put_pixel(Framebuffer *fb, lnum offset, uint8_t value)
{
    if (offset >= 0 && offset < PIXELS) {
        fb->pixels[offset] = value;
        R_TAG(offset);
    }
}

static void draw_sky(Renderer *R, const Visplane *pl)
{
    const RData *rd = R->rd;
    if (rd->skytexture < 0 || rd->skytexture >= rd->texture_count)
        return;
    const Texture *tex = &rd->textures[rd->skytexture];
    if (!tex->wall128)
        return;
    const uint8_t *cm = r_colormap(R, 0);
    r_tag = TAG_SKY;
    const lnum dc_iscale = (9 * FRACUNIT) / 10;
    const lnum dc_texturemid = 100 * FRACUNIT;

    for (lnum x = pl->minx; x <= pl->maxx; x++) {
        if (x < 0 || x >= SCREENWIDTH)
            continue;
        lnum yl = pl->top[x];
        lnum yh = pl->bottom[x];
        if (yl > yh || yl >= 255)
            continue;
        uint32_t angle = (uint32_t)R->viewangle + (uint32_t)R->xtoviewangle[x];
        lnum ang = angle >> ANGLETOSKYSHIFT;
        uint32_t col = (uint32_t)ang & (uint32_t)tex->widthmask;
        r_draw_column_pixels(R->fb, x, yl, yh, dc_iscale, dc_texturemid,
                             tex->wall128 + (size_t)col * RD_COLUMN_SIZE,
                             RD_COLUMN_SIZE, cm, 256,
                             R->centery, R->viewwidth, R->detailshift,
                             R->viewwindowx, R->viewwindowy);
    }
}

static void draw_flat(Renderer *R, const Visplane *pl, const uint8_t *flat,
                      const int *planezlight, lnum planeheight_in)
{
    const int32_t *finesine = R->tables->finesine;
    const uint8_t *colormaps[NUMCOLORMAPS];
    for (int i = 0; i < NUMCOLORMAPS; i++)
        colormaps[i] = r_colormap(R, i);

    lnum planeheight = r_i32(planeheight_in);
    lnum viewx = r_i32(R->viewx);
    lnum viewy = r_i32(R->viewy);
    uint32_t viewangle = (uint32_t)R->viewangle;
    lnum minx = pl->minx, maxx = pl->maxx;
    if (minx < 0) minx = 0;
    if (maxx >= R->viewwidth) maxx = R->viewwidth - 1;

    r_tag = TAG_FLAT;
    lnum cached_y = -1;
    int light_index = -1;
    lnum distance = 0;
    const uint8_t *cm = R->fixedcolormap;
    Framebuffer *fb = R->fb;

    for (lnum x = minx; x <= maxx; x++) {
        lnum t1 = pl->top[x];
        lnum b1 = pl->bottom[x];
        if (t1 > b1 || t1 == 255)
            continue;
        lnum y1 = b1;
        if (y1 >= R->viewheight)
            y1 = R->viewheight - 1;

        lnum distscale = r_i32(R->distscale[x]);
        uint32_t angle = viewangle + (uint32_t)R->xtoviewangle[x];
        int ang = (int)((angle >> 19) & FINEMASK);

        for (lnum y = t1; y <= y1; y++) {
            if (y != cached_y) {
                cached_y = y;
                distance = r_fixed_mul(planeheight, r_i32(R->yslope[y]));
            }
            lnum length = r_fixed_mul(distance, distscale);
            lnum xfrac = r_i32(viewx + r_fixed_mul(finesine[(ang + FINEANGLES / 4) & FINEMASK], length));
            lnum yfrac = r_i32(-viewy - r_fixed_mul(finesine[ang], length));

            uint32_t index = (uint32_t)distance >> LIGHTZSHIFT;
            if (index >= MAXLIGHTZ)
                index = MAXLIGHTZ - 1;
            if (!R->fixedcolormap && (int)index != light_index) {
                light_index = (int)index;
                int level = planezlight[index];
                if (level < 0) level = 0;
                if (level >= NUMCOLORMAPS) level = NUMCOLORMAPS - 1;
                cm = colormaps[level];
            }

            uint32_t spot = ((uint32_t)r_shar(xfrac, 16) & 63)
                          | ((uint32_t)r_shar(yfrac, 10) & 4032);
            uint8_t value = cm[flat[spot]];
            lnum yoffset = R->ylookup[y];
            if (R->detailshift != 0) {
                lnum offset = yoffset + R->columnofs[x << 1];
                put_pixel(fb, offset, value);
                put_pixel(fb, offset + 1, value);
            } else {
                put_pixel(fb, yoffset + R->columnofs[x], value);
            }
        }
    }
}

void r_draw_planes(Renderer *R)
{
    const RData *rd = R->rd;
    for (int p = 0; p < R->numvisplanes; p++) {
        const Visplane *pl = &R->visplanes[p];
        if (pl->minx > pl->maxx)
            continue;
        if (pl->picnum == rd->skyflatnum) {
            draw_sky(R, pl);
            continue;
        }
        lnum light = (lnum)((uint32_t)pl->lightlevel >> 4) + R->extralight;
        if (light < 0) light = 0;
        if (light > LIGHTLEVELS - 1) light = LIGHTLEVELS - 1;

        lnum flatnum = r_flat_translate(rd, pl->picnum);
        if (flatnum < 0 || flatnum >= rd->flat_count)
            flatnum = 0;
        const uint8_t *flat = rd->flatpix + (size_t)flatnum * RD_FLAT_SIZE;

        lnum delta = r_i32(pl->height - r_i32(R->viewz));
        lnum planeheight = delta < 0 ? -delta : delta;
        if (planeheight != 0)
            draw_flat(R, pl, flat, R->zlight[light], planeheight);
    }
}
