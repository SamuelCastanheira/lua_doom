#ifndef RENDER_TYPES_H
#define RENDER_TYPES_H

#include <stdint.h>
#include <stddef.h>

#define RENDER_SCREENWIDTH 320
#define RENDER_SCREENHEIGHT 200

typedef struct {
    int32_t x, y;
} Vertex;

typedef struct {
    int32_t floorheight;
    int32_t ceilingheight;
    int32_t floorpic;
    int32_t ceilingpic;
    int32_t lightlevel;
} Sector;

typedef struct {
    int32_t textureoffset;
    int32_t rowoffset;
    int32_t toptexture;
    int32_t bottomtexture;
    int32_t midtexture;
    int32_t sector;
} SideDef;

typedef struct {
    int32_t v1, v2;
    int32_t flags;
    int32_t frontsector;
    int32_t backsector;
    int32_t frontsidedef;
    int32_t backsidedef;
} LineDef;

typedef struct {
    int32_t v1, v2;
    uint32_t angle;
    int32_t linedef;
    int32_t sidedef;
    int32_t frontsector;
    int32_t backsector;
    int32_t offset;
} Seg;

typedef struct {
    int32_t numlines;
    int32_t firstline;
    int32_t sector;
} Subsector;

typedef struct {
    int32_t x, y;
    int32_t dx, dy;
    uint16_t children[2];
} Node;

typedef struct {
    Vertex *vertexes;
    size_t num_vertexes;

    Sector *sectors;
    size_t num_sectors;

    SideDef *sidedefs;
    size_t num_sidedefs;

    LineDef *linedefs;
    size_t num_linedefs;

    Seg *segs;
    size_t num_segs;

    Subsector *subsectors;
    size_t num_subsectors;

    Node *nodes;
    size_t num_nodes;
} World;

typedef struct {
    int32_t height;
    int32_t picnum;
    int32_t lightlevel;
    int32_t minx;
    int32_t maxx;

    int16_t top[RENDER_SCREENWIDTH];
    int16_t bottom[RENDER_SCREENWIDTH];
} Visplane;

typedef struct {
    int32_t x1, x2;
    int32_t scale1, scale2;
    int32_t scalestep;

    int32_t silhouette;
    int32_t bsilheight;
    int32_t tsilheight;

    int16_t *sprtopclip;
    int16_t *sprbottomclip;
    int32_t clip_count;

    int32_t *maskedtexturecol;
    int32_t masked_count;
} DrawSeg;

#endif