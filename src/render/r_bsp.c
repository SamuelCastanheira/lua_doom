/* r_bsp.c: travessia da BSP, clipping de segmentos solidos e subsetores. */
#include "r_local.h"

static void crunch_solid(Renderer *R, int start, int nexti)
{
    if (nexti == start)
        return;
    int dest = start + 1;
    for (int i = nexti + 1; i < R->newend; i++)
        R->solidsegs[dest++] = R->solidsegs[i];
    R->newend = dest;
}

static void clip_solid(lua_State *L, Renderer *R, lnum first, lnum last)
{
    if (first > last)
        return;
    ClipRange *s = R->solidsegs;
    int start = 0;
    while (start < R->newend && s[start].last < first - 1)
        start++;
    if (start >= R->newend) {
        r_store_wall_range(L, R, first, last);
        return;
    }
    if (first < s[start].first) {
        if (last < s[start].first - 1) {
            r_store_wall_range(L, R, first, last);
            if (R->newend + 1 > MAXSOLIDSEGS)
                luaL_error(L, "render_c: solidsegs overflow");
            for (int i = R->newend - 1; i >= start; i--)
                s[i + 1] = s[i];
            s[start].first = first;
            s[start].last = last;
            R->newend++;
            return;
        }
        r_store_wall_range(L, R, first, s[start].first - 1);
        s[start].first = first;
    }
    if (last <= s[start].last)
        return;
    int nexti = start;
    while (nexti + 1 < R->newend && last >= s[nexti + 1].first - 1) {
        r_store_wall_range(L, R, s[nexti].last + 1, s[nexti + 1].first - 1);
        nexti++;
        if (last <= s[nexti].last) {
            s[start].last = s[nexti].last;
            crunch_solid(R, start, nexti);
            return;
        }
    }
    r_store_wall_range(L, R, s[nexti].last + 1, last);
    s[start].last = last;
    crunch_solid(R, start, nexti);
}

static void clip_pass(lua_State *L, Renderer *R, lnum first, lnum last)
{
    if (first > last)
        return;
    const ClipRange *s = R->solidsegs;
    int start = 0;
    while (start < R->newend && s[start].last < first - 1)
        start++;
    if (start >= R->newend) {
        r_store_wall_range(L, R, first, last);
        return;
    }
    if (first < s[start].first) {
        if (last < s[start].first - 1) {
            r_store_wall_range(L, R, first, last);
            return;
        }
        r_store_wall_range(L, R, first, s[start].first - 1);
    }
    if (last <= s[start].last)
        return;
    int nexti = start;
    while (nexti + 1 < R->newend && last >= s[nexti + 1].first - 1) {
        r_store_wall_range(L, R, s[nexti].last + 1, s[nexti + 1].first - 1);
        nexti++;
        if (last <= s[nexti].last)
            return;
    }
    r_store_wall_range(L, R, s[nexti].last + 1, last);
}

static void add_line(lua_State *L, Renderer *R, int segnum)
{
    const RLevel *lv = &R->level;
    const RSeg *line = &lv->segs[segnum];
    R->curline = segnum;
    if (line->sidedef < 0 || line->linedef < 0)
        return;

    lnum angle1 = r_point_to_angle(R, lv->vertexes[line->v1].x, lv->vertexes[line->v1].y);
    lnum angle2 = r_point_to_angle(R, lv->vertexes[line->v2].x, lv->vertexes[line->v2].y);
    lnum span = r_u32(angle1 - angle2);
    if (span >= ANG180)
        return;
    R->rw_angle1 = angle1;
    angle1 = r_u32(angle1 - R->viewangle);
    angle2 = r_u32(angle2 - R->viewangle);

    lnum clip2 = r_u32(2 * R->clipangle);
    lnum tspan = r_u32(angle1 + R->clipangle);
    if (tspan > clip2) {
        tspan = r_u32(tspan - 2 * R->clipangle);
        if (tspan >= span)
            return;
        angle1 = R->clipangle;
    }
    tspan = r_u32(R->clipangle - angle2);
    if (tspan > clip2) {
        tspan = r_u32(tspan - 2 * R->clipangle);
        if (tspan >= span)
            return;
        angle2 = r_u32(-R->clipangle);
    }

    const lnum mask = FINEANGLES / 2 - 1;
    lnum x1 = R->viewangletox[r_band(r_ushr(r_u32(angle1 + ANG90), ANGLETOFINESHIFT), mask)];
    lnum x2 = R->viewangletox[r_band(r_ushr(r_u32(angle2 + ANG90), ANGLETOFINESHIFT), mask)];
    if (x1 == x2)
        return;

    R->backsector = line->backsector;
    if (R->backsector < 0) {
        clip_solid(L, R, x1, x2 - 1);
        return;
    }
    const RSector *front = &lv->sectors[R->frontsector];
    const RSector *back = &lv->sectors[R->backsector];
    if (back->ceilingheight <= front->floorheight
        || back->floorheight >= front->ceilingheight) {
        clip_solid(L, R, x1, x2 - 1);
        return;
    }
    clip_pass(L, R, x1, x2 - 1);
}

static void subsector(lua_State *L, Renderer *R, lnum num)
{
    const RLevel *lv = &R->level;
    if (num < 0 || num >= lv->num_subsectors)
        return;
    const RSubsector *sub = &lv->subsectors[num];
    if (sub->sector < 0)
        return;
    R->frontsector = sub->sector;
    const RSector *front = &lv->sectors[sub->sector];

    lnum light = r_ushr(front->lightlevel, 4) + R->extralight;
    if (light < 0) light = 0;
    if (light > LIGHTLEVELS - 1) light = LIGHTLEVELS - 1;
    R->walllights = R->scalelight[light];

    R->floorplane = r_find_plane(L, R, front->floorheight, front->floorpic, front->lightlevel);
    R->ceilingplane = r_find_plane(L, R, front->ceilingheight, front->ceilingpic, front->lightlevel);

    int line = sub->firstline;
    for (int i = 0; i < sub->numlines; i++, line++) {
        if (line >= 0 && line < lv->num_segs)
            add_line(L, R, line);
    }
}

static int point_on_side(lnum x, lnum y, const RNode *node)
{
    lnum dx = r_i32(x - node->x);
    lnum dy = r_i32(y - node->y);
    lnum left = r_i32(r_shar(node->dy, 16)) * dx;
    lnum right = dy * r_i32(r_shar(node->dx, 16));
    return right >= left ? 1 : 0;
}

static void render_bsp_node(lua_State *L, Renderer *R, lnum bspnum)
{
    if (r_band(bspnum, NF_SUBSECTOR) != 0 || bspnum < 0) {
        lnum num = 0;
        if (bspnum != -1)
            num = r_band(bspnum, 32767);
        subsector(L, R, num);
        return;
    }
    if (bspnum >= R->level.num_nodes)
        return;
    const RNode *node = &R->level.nodes[bspnum];
    int side = point_on_side(R->viewx, R->viewy, node);
    render_bsp_node(L, R, node->children[side]);
    render_bsp_node(L, R, node->children[side ^ 1]);
}

static void clear_clip(Renderer *R)
{
    R->solidsegs[0].first = -2147483647LL;
    R->solidsegs[0].last = -1;
    R->solidsegs[1].first = R->viewwidth;
    R->solidsegs[1].last = 2147483647LL;
    R->newend = 2;
    for (lnum i = 0; i < R->viewwidth; i++) {
        R->floorclip[i] = (int)R->viewheight;
        R->ceilingclip[i] = -1;
    }
}

void r_render_bsp(lua_State *L, Renderer *R)
{
    r_clear_planes(R);
    R->numdrawsegs = 0;
    R->numopenings = 0;
    R->floorplane = -1;
    R->ceilingplane = -1;
    clear_clip(R);
    if (R->level.num_nodes > 0)
        render_bsp_node(L, R, R->level.numnodes - 1);
    else
        subsector(L, R, 0);
    r_draw_planes(R);
}
