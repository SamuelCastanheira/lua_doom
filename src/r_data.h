/*
 * Estruturas de recursos graficos (texturas, flats, colormaps, sprites).
 *
 * Compartilhado entre r_data_c (que carrega os dados do WAD) e render_c
 * (que le os dados direto da memoria, sem passar pela API Lua).
 * Os dois modulos precisam ser compilados com este mesmo header.
 */
#ifndef R_DATA_H
#define R_DATA_H

#include <lua.h>
#include <stddef.h>
#include <stdint.h>

#define RD_MT "r_data_c.RData"
#define RD_FLAT_SIZE 4096
#define RD_COLUMN_SIZE 128
#define MAX_SPRITE_FRAMES 29
#define SPRITE_ROTATIONS 8

typedef struct {
    int16_t originx;
    int16_t originy;
    int32_t patch;
} PatchDef;

/* Um post de coluna mascarada: pixels em Texture.mpix[pixofs..]. */
typedef struct {
    int topdelta;
    int length;
    uint32_t pixofs;
} MaskedPost;

typedef struct {
    char name[9];
    int width;
    int height;
    int widthmask;
    int patch_count;
    PatchDef *patches;
    int32_t *col_lump;
    uint32_t *col_ofs;
    uint8_t *composite;

    /* Preenchidos por prepare_render(). */
    uint8_t *wall128;        /* width * 128: mesma saida de get_column */
    int32_t *mpost_first;    /* width + 1 indices em mposts */
    MaskedPost *mposts;      /* posts de column_posts, por coluna */
    uint8_t *mpix;           /* pixels dos posts */
} Texture;

typedef struct {
    char name[9];
    int texture_num;
} TextureIndex;

typedef struct {
    int rotate;
    int lump[SPRITE_ROTATIONS];
    int flip[SPRITE_ROTATIONS];
} SpriteFrame;

typedef struct {
    int frame_count;
    SpriteFrame *frames;
} SpriteDef;

typedef struct {
    char name[5];
    SpriteDef def;
} SpriteEntry;

typedef struct {
    int count;
    SpriteEntry *entries;
} SpriteDefs;

typedef struct {
    int lump_num;
    uint8_t *pixels;
    size_t size;
} Flat;

typedef struct {
    lua_State *L;
    int wad_ref;
    int wad_module_ref;

    Texture *textures;
    int texture_count;
    TextureIndex *tex_index;
    int tex_index_count;

    int flats_first;
    int flats_last;
    Flat *flats;
    int flat_count;

    int *flattranslation;
    int flattranslation_count;
    int *texturetranslation;
    int texturetranslation_count;

    uint8_t *colormaps;
    size_t colormaps_size;

    int skytexture;
    int skyflatnum;

    SpriteDefs sprites;
    int sprite_count;

    int initialized;

    /* Preenchidos por prepare_render(). */
    uint8_t *flatpix;        /* flat_count * 4096: mesma saida de flat_pixels */
    int render_ready;
} RData;

#endif
