#include <lua.h>
#include <lauxlib.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <string.h>
#include <ctype.h>

#include "r_data.h"

#define FRACUNIT 65536

static uint16_t rd_u16(const uint8_t *p) {
    return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}

static int16_t rd_i16(const uint8_t *p) {
    return (int16_t)rd_u16(p);
}

static uint32_t rd_u32(const uint8_t *p) {
    return (uint32_t)p[0]
        | ((uint32_t)p[1] << 8)
        | ((uint32_t)p[2] << 16)
        | ((uint32_t)p[3] << 24);
}

static int32_t rd_i32(const uint8_t *p) {
    return (int32_t)rd_u32(p);
}

static int has_bytes(size_t size, size_t offset, size_t count) {
    return offset <= size && count <= size - offset;
}

static void free_texture(Texture *t) {
    if (!t) return;
    free(t->patches);
    free(t->col_lump);
    free(t->col_ofs);
    free(t->composite);
    free(t->wall128);
    free(t->mpost_first);
    free(t->mposts);
    free(t->mpix);
    memset(t, 0, sizeof(*t));
}

static void free_rdata(RData *rd) {
    if (!rd) return;

    if (rd->textures) {
        for (int i = 0; i < rd->texture_count; ++i)
            free_texture(&rd->textures[i]);
        free(rd->textures);
    }

    free(rd->colormaps);
    free(rd->flatpix);
    rd->flatpix = NULL;
    rd->render_ready = 0;
    rd->textures = NULL;
    rd->texture_count = 0;
    rd->colormaps = NULL;
    rd->colormaps_size = 0;
    rd->initialized = 0;
    rd->skyflatnum = 0;
    rd->skytexture = 0;
}

static void push_wad(RData *rd) {
    lua_rawgeti(rd->L, LUA_REGISTRYINDEX, rd->wad_ref);
}

static void push_wad_module(RData *rd) {
    lua_rawgeti(rd->L, LUA_REGISTRYINDEX, rd->wad_module_ref);
}

static int call_wad_num(RData *rd, const char *method, const char *name) {
    lua_State *L = rd->L;
    push_wad_module(rd);
    lua_getfield(L, -1, method);
    push_wad(rd);
    lua_pushstring(L, name);
    lua_remove(L, -4); /* remove module, keep function + wad + name */
    if (lua_pcall(L, 2, 1, 0) != LUA_OK)
        lua_error(L);
    int result = (int)luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    return result;
}

/* Calls wad.cache_lump_num(wad, lump_number), leaves returned string on stack. */
static int push_lump_num(RData *rd, int lump_num) {
    lua_State *L = rd->L;
    push_wad_module(rd);
    lua_getfield(L, -1, "cache_lump_num");
    push_wad(rd);
    lua_pushinteger(L, lump_num);
    lua_remove(L, -4);
    if (lua_pcall(L, 2, 1, 0) != LUA_OK)
        lua_error(L);
    luaL_checktype(L, -1, LUA_TSTRING);
    return lua_gettop(L);
}

/* Calls wad.cache_lump_name(wad, name), leaves returned string on stack. */
static int push_lump_name(RData *rd, const char *name) {
    lua_State *L = rd->L;
    push_wad_module(rd);
    lua_getfield(L, -1, "cache_lump_name");
    push_wad(rd);
    lua_pushstring(L, name);
    lua_remove(L, -4);
    if (lua_pcall(L, 2, 1, 0) != LUA_OK)
        lua_error(L);
    luaL_checktype(L, -1, LUA_TSTRING);
    return lua_gettop(L);
}

static void copy_name8(char dst[9], const uint8_t *src) {
    int n = 0;
    while (n < 8 && src[n] != 0) {
        dst[n] = (char)src[n];
        ++n;
    }
    while (n > 0 && dst[n - 1] == ' ')
        --n;
    dst[n] = '\0';
    for (int i = 0; i < n; ++i) {
        if (dst[i] >= 'a' && dst[i] <= 'z')
            dst[i] = (char)(dst[i] - 'a' + 'A');
    }
}

static int texture_index_by_name(RData *rd, const char *name) {
    char key[9] = {0};
    size_t n = strlen(name);
    if (n > 8) n = 8;
    for (size_t i = 0; i < n; ++i) {
        char c = name[i];
        key[i] = (c >= 'a' && c <= 'z') ? (char)(c - 'a' + 'A') : c;
    }
    while (n > 0 && key[n - 1] == ' ')
        key[--n] = '\0';

    for (int i = 0; i < rd->texture_count; ++i) {
        if (strcmp(rd->textures[i].name, key) == 0)
            return i;
    }
    return -1;
}

static int patch_width_from_data(const uint8_t *data, size_t size) {
    if (!has_bytes(size, 0, 8))
        return -1;
    int width = rd_i16(data);
    if (width < 0 || width > 32767)
        return -1;
    if (!has_bytes(size, 8, (size_t)width * 4))
        return -1;
    return width;
}

static void generate_lookup(RData *rd, Texture *tex) {
    int *counts = (int *)calloc((size_t)tex->width, sizeof(int));
    if (!counts) return;

    for (int p = 0; p < tex->patch_count; ++p) {
        PatchDef *mp = &tex->patches[p];
        if (mp->patch < 0) continue;

        int lump_idx = push_lump_num(rd, mp->patch);
        size_t size = 0;
        const uint8_t *data = (const uint8_t *)lua_tolstring(rd->L, lump_idx, &size);
        int pw = patch_width_from_data(data, size);

        if (pw > 0) {
            int x1 = mp->originx;
            int x2 = x1 + pw;
            int x = x1 < 0 ? 0 : x1;
            if (x2 > tex->width) x2 = tex->width;

            while (x < x2) {
                size_t col_entry = 8u + (size_t)(x - mp->originx) * 4u;
                if (has_bytes(size, col_entry, 4)) {
                    counts[x]++;
                    tex->col_lump[x] = mp->patch;
                    tex->col_ofs[x] = rd_u32(data + col_entry);
                }
                ++x;
            }
        }
        lua_pop(rd->L, 1);
    }

    for (int x = 0; x < tex->width; ++x) {
        if (counts[x] > 1)
            tex->col_lump[x] = -1;
    }
    free(counts);
}

static void draw_patch_column(
    const uint8_t *patch, size_t patch_size, uint32_t column,
    uint8_t *composite, const Texture *tex, int x, int originy
) {
    size_t pos = (size_t)column;

    while (pos < patch_size) {
        uint8_t topdelta = patch[pos];
        if (topdelta == 255) break;
        if (!has_bytes(patch_size, pos, 3)) break;

        uint8_t length = patch[pos + 1];
        size_t source = pos + 3;
        if (!has_bytes(patch_size, source, length)) break;

        int y = originy + (int)topdelta;
        int count = (int)length;
        if (y < 0) {
            count += y;
            source += (size_t)(-y);
            y = 0;
        }
        if (y + count > tex->height)
            count = tex->height - y;

        if (count > 0 && y >= 0 && y < tex->height) {
            size_t dest = (size_t)x * (size_t)tex->height + (size_t)y;
            memcpy(composite + dest, patch + source, (size_t)count);
        }

        pos += (size_t)length + 4u;
    }
}

static int generate_composite(RData *rd, Texture *tex) {
    if (tex->composite) return 1;

    size_t total = (size_t)tex->width * (size_t)tex->height;
    tex->composite = (uint8_t *)calloc(total ? total : 1, 1);
    if (!tex->composite) return 0;

    for (int p = 0; p < tex->patch_count; ++p) {
        PatchDef *mp = &tex->patches[p];
        if (mp->patch < 0) continue;

        int lump_idx = push_lump_num(rd, mp->patch);
        size_t size = 0;
        const uint8_t *data = (const uint8_t *)lua_tolstring(rd->L, lump_idx, &size);
        int pw = patch_width_from_data(data, size);

        if (pw > 0) {
            int x1 = mp->originx;
            int x2 = x1 + pw;
            if (x2 > tex->width) x2 = tex->width;
            int x = x1 < 0 ? 0 : x1;

            while (x < x2) {
                size_t col_entry = 8u + (size_t)(x - mp->originx) * 4u;
                if (has_bytes(size, col_entry, 4)) {
                    uint32_t column = rd_u32(data + col_entry);
                    if (column < size)
                        draw_patch_column(data, size, column,
                                          tex->composite, tex, x, mp->originy);
                }
                ++x;
            }
        }
        lua_pop(rd->L, 1);
    }

    for (int x = 0; x < tex->width; ++x) {
        if (tex->col_lump[x] < 0)
            tex->col_ofs[x] = (uint32_t)((size_t)x * (size_t)tex->height);
    }
    return 1;
}

static int init_textures(RData *rd) {
    lua_State *L = rd->L;

    int pnames_idx = push_lump_name(rd, "PNAMES");
    size_t pnames_size = 0;
    const uint8_t *pnames = (const uint8_t *)lua_tolstring(L, pnames_idx, &pnames_size);
    if (pnames_size < 4) {
        lua_pop(L, 1);
        return 0;
    }

    int32_t patch_count = rd_i32(pnames);
    if (patch_count < 0 || patch_count > 65535 ||
        !has_bytes(pnames_size, 4, (size_t)patch_count * 8u)) {
        lua_pop(L, 1);
        return 0;
    }

    int32_t *patch_lookup = (int32_t *)malloc((size_t)(patch_count ? patch_count : 1) * sizeof(int32_t));
    if (!patch_lookup) {
        lua_pop(L, 1);
        return 0;
    }

    for (int i = 0; i < patch_count; ++i) {
        char pname[9];
        copy_name8(pname, pnames + 4 + (size_t)i * 8u);
        patch_lookup[i] = call_wad_num(rd, "check_num_for_name", pname);
    }
    lua_pop(L, 1);

    int tex1_idx = push_lump_name(rd, "TEXTURE1");
    size_t tex1_size = 0;
    const uint8_t *tex1 = (const uint8_t *)lua_tolstring(L, tex1_idx, &tex1_size);
    if (tex1_size < 4) {
        free(patch_lookup);
        lua_pop(L, 1);
        return 0;
    }
    int32_t num1 = rd_i32(tex1);
    if (num1 < 0 || num1 > 65535 ||
        !has_bytes(tex1_size, 4, (size_t)num1 * 4u)) {
        free(patch_lookup);
        lua_pop(L, 1);
        return 0;
    }

    int tex2_idx = 0;
    const uint8_t *tex2 = NULL;
    size_t tex2_size = 0;
    int32_t num2 = 0;
    if (call_wad_num(rd, "check_num_for_name", "TEXTURE2") >= 0) {
        tex2_idx = push_lump_name(rd, "TEXTURE2");
        tex2 = (const uint8_t *)lua_tolstring(L, tex2_idx, &tex2_size);
        if (tex2_size >= 4) {
            num2 = rd_i32(tex2);
            if (num2 < 0 || num2 > 65535 ||
                !has_bytes(tex2_size, 4, (size_t)num2 * 4u)) {
                lua_pop(L, 1);
                tex2_idx = 0;
                tex2 = NULL;
                num2 = 0;
            }
        } else {
            lua_pop(L, 1);
            tex2_idx = 0;
            tex2 = NULL;
        }
    }

    int total = num1 + num2;
    rd->textures = (Texture *)calloc((size_t)(total ? total : 1), sizeof(Texture));
    if (!rd->textures) {
        if (tex2_idx) lua_pop(L, 1);
        lua_pop(L, 1);
        free(patch_lookup);
        return 0;
    }

    for (int i = 0; i < total; ++i) {
        const uint8_t *src = (i < num1) ? tex1 : tex2;
        size_t src_size = (i < num1) ? tex1_size : tex2_size;
        int32_t offset = (i < num1)
            ? rd_i32(tex1 + 4 + (size_t)i * 4u)
            : rd_i32(tex2 + 4 + (size_t)(i - num1) * 4u);

        if (offset < 0 || !has_bytes(src_size, (size_t)offset, 22))
            continue;

        Texture *tex = &rd->textures[i];
        copy_name8(tex->name, src + offset);
        tex->width = rd_i16(src + offset + 12);
        tex->height = rd_i16(src + offset + 14);
        int patch_n = rd_i16(src + offset + 20);

        if (tex->width <= 0 || tex->height <= 0 ||
            tex->width > 4096 || tex->height > 4096 ||
            patch_n < 0 || patch_n > 4096 ||
            !has_bytes(src_size, (size_t)offset + 22, (size_t)patch_n * 10u)) {
            tex->width = tex->height = 0;
            continue;
        }

        tex->patch_count = patch_n;
        tex->patches = (PatchDef *)calloc((size_t)(patch_n ? patch_n : 1), sizeof(PatchDef));
        tex->col_lump = (int32_t *)malloc((size_t)tex->width * sizeof(int32_t));
        tex->col_ofs = (uint32_t *)calloc((size_t)tex->width, sizeof(uint32_t));
        if (!tex->patches || !tex->col_lump || !tex->col_ofs) {
            tex->width = tex->height = 0;
            continue;
        }

        const uint8_t *p = src + offset + 22;
        for (int j = 0; j < patch_n; ++j, p += 10) {
            int16_t pidx = rd_i16(p + 4);
            tex->patches[j].originx = rd_i16(p);
            tex->patches[j].originy = rd_i16(p + 2);
            tex->patches[j].patch =
                (pidx >= 0 && pidx < patch_count) ? patch_lookup[pidx] : -1;
        }

        int power = 1;
        while (power * 2 <= tex->width)
            power *= 2;
        tex->widthmask = power - 1;

        for (int x = 0; x < tex->width; ++x)
            tex->col_lump[x] = -1;

        generate_lookup(rd, tex);
        rd->texture_count++;
    }

    /* Compact valid textures while preserving their original order. */
    if (rd->texture_count != total) {
        int dst = 0;
        for (int src_i = 0; src_i < total; ++src_i) {
            Texture *src_t = &rd->textures[src_i];
            if (src_t->width <= 0 || src_t->height <= 0) {
                free_texture(src_t);
                continue;
            }
            if (dst != src_i) {
                rd->textures[dst] = *src_t;
                memset(src_t, 0, sizeof(*src_t));
            }
            ++dst;
        }
        rd->texture_count = dst;
    }

    if (tex2_idx) lua_pop(L, 1);
    lua_pop(L, 1); /* TEXTURE1 */
    free(patch_lookup);
    return 1;
}

static RData *check_rdata(lua_State *L, int idx) {
    RData *rd = (RData *)luaL_checkudata(L, idx, RD_MT);
    /* Chamadas Lua internas usam rd->L; precisa ser a thread atual, porque
     * o Atmos roda codigo dentro de corrotinas. */
    rd->L = L;
    return rd;
}

static int l_new(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    RData *rd = (RData *)lua_newuserdatauv(L, sizeof(RData), 0);
    memset(rd, 0, sizeof(*rd));
    rd->wad_ref = LUA_NOREF;
    rd->wad_module_ref = LUA_NOREF;
    rd->L = L;

    lua_pushvalue(L, 1);
    rd->wad_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    lua_getglobal(L, "require");
    lua_pushliteral(L, "wad");
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        luaL_unref(L, LUA_REGISTRYINDEX, rd->wad_ref);
        rd->wad_ref = LUA_NOREF;
        return lua_error(L);
    }
    rd->wad_module_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    luaL_getmetatable(L, RD_MT);
    lua_setmetatable(L, -2);
    return 1;
}

static int l_gc(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    free_rdata(rd);
    if (rd->wad_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, rd->wad_ref);
        rd->wad_ref = LUA_NOREF;
    }
    if (rd->wad_module_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, rd->wad_module_ref);
        rd->wad_module_ref = LUA_NOREF;
    }
    return 0;
}

/* Libera toda a memoria alocada para as definicoes de sprites. */
static void free_sprites(SpriteDefs *sprites)
{
    if (!sprites) return;

    for (int i = 0; i < sprites->count; ++i) {
        free(sprites->entries[i].def.frames);
        sprites->entries[i].def.frames = NULL;
        sprites->entries[i].def.frame_count = 0;
    }

    free(sprites->entries);
    sprites->entries = NULL;
    sprites->count = 0;
}


/*
 * Equivalente a install() em sprites.lua.
 *
 * frame e rotation sao valores logicos do nome do lump:
 *   TROOA1 -> frame 0 (A), rotation 1
 *   TROOA0 -> frame 0 (A), rotation 0 (imagem usada nas oito direcoes)
 *
 * lump permanece como indice global zero-based do WAD.
 */
static int install_sprite_frame(
    SpriteFrame *frames,
    int lump,
    int frame,
    int rotation,
    int flipped
)
{
    if (frame < 0 || frame >= MAX_SPRITE_FRAMES ||
        rotation < 0 || rotation > 8) {
        return 0;
    }

    SpriteFrame *sf = &frames[frame];
    const int flip = flipped ? 1 : 0;

    if (rotation == 0) {
        /* Se ja usa oito rotacoes especificas, a entrada A0 nao as substitui. */
        if (sf->rotate == 1)
            return 1;

        sf->rotate = 0;
        for (int r = 0; r < SPRITE_ROTATIONS; ++r) {
            sf->lump[r] = lump;
            sf->flip[r] = flip;
        }
        return 1;
    }

    /* Uma entrada A1..A8 nao substitui uma imagem A0 ja instalada. */
    if (sf->rotate == 0)
        return 1;

    sf->rotate = 1;

    /* Rotacao 1 do WAD ocupa indice 0 no array C. */
    const int idx = rotation - 1;
    if (sf->lump[idx] < 0) {
        sf->lump[idx] = lump;
        sf->flip[idx] = flip;
    }

    return 1;
}


/* Chama wad.lump_name(wadfile, lump_index) e devolve o nome em buffer C. */
static int call_wad_lump_name(RData *rd, int lump_index, char out[9])
{
    lua_State *L = rd->L;

    push_wad_module(rd);
    lua_getfield(L, -1, "lump_name");
    push_wad(rd);
    lua_pushinteger(L, lump_index);
    lua_remove(L, -4); /* remove o modulo; ficam funcao, wad e indice */

    if (lua_pcall(L, 2, 1, 0) != LUA_OK)
        lua_error(L);

    size_t len = 0;
    const char *name = luaL_checklstring(L, -1, &len);

    if (len > 8) len = 8;
    memcpy(out, name, len);
    out[len] = '\0';
    lua_pop(L, 1);

    /* Os nomes do WAD sao comparados sem diferenciar maiusculas/minusculas. */
    for (size_t i = 0; i < len; ++i) {
        if (out[i] >= 'a' && out[i] <= 'z')
            out[i] = (char)(out[i] - 'a' + 'A');
    }

    return (int)len;
}


/* Chama wad.num_lumps(wadfile). */
static int call_wad_num_lumps(RData *rd)
{
    lua_State *L = rd->L;

    push_wad_module(rd);
    lua_getfield(L, -1, "num_lumps");
    push_wad(rd);
    lua_remove(L, -2); /* remove o modulo; ficam funcao e wad */

    if (lua_pcall(L, 1, 1, 0) != LUA_OK)
        lua_error(L);

    int count = (int)luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    return count;
}


/* Procura sprite pelo prefixo de quatro caracteres. */
static SpriteEntry *find_sprite_entry(SpriteDefs *sprites, const char name[5])
{
    for (int i = 0; i < sprites->count; ++i) {
        if (memcmp(sprites->entries[i].name, name, 4) == 0)
            return &sprites->entries[i];
    }
    return NULL;
}


/* Cria a entrada e os 29 frames inicialmente vazios. */
static SpriteEntry *create_sprite_entry(SpriteDefs *sprites, const char name[5])
{
    if (sprites->count == 0) {
        sprites->entries = (SpriteEntry *)calloc(1, sizeof(SpriteEntry));
    } else {
        SpriteEntry *new_entries = (SpriteEntry *)realloc(
            sprites->entries,
            (size_t)(sprites->count + 1) * sizeof(SpriteEntry)
        );
        if (!new_entries)
            return NULL;
        sprites->entries = new_entries;
    }

    if (!sprites->entries)
        return NULL;

    SpriteEntry *entry = &sprites->entries[sprites->count];
    memset(entry, 0, sizeof(*entry));
    memcpy(entry->name, name, 5);

    entry->def.frames = (SpriteFrame *)malloc(
        MAX_SPRITE_FRAMES * sizeof(SpriteFrame)
    );
    if (!entry->def.frames)
        return NULL;

    entry->def.frame_count = 0;

    for (int f = 0; f < MAX_SPRITE_FRAMES; ++f) {
        SpriteFrame *sf = &entry->def.frames[f];
        sf->rotate = -1;
        for (int r = 0; r < SPRITE_ROTATIONS; ++r) {
            sf->lump[r] = -1;
            sf->flip[r] = 0;
        }
    }

    sprites->count++;
    return entry;
}


/*
 * Equivalente a sprites.init_defs(wadfile).
 *
 * Usa os helpers existentes em r_data_c.c:
 *   call_wad_num(rd, method, name)
 *   push_wad_module(rd)
 *   push_wad(rd)
 *
 * Retorna 1 em sucesso e 0 em falha de alocacao.
 */
static int init_sprites(RData *rd)
{
    free_sprites(&rd->sprites);

    int start = call_wad_num(rd, "check_num_for_name", "S_START");
    int endn  = call_wad_num(rd, "check_num_for_name", "S_END");

    if (start < 0)
        start = call_wad_num(rd, "check_num_for_name", "SS_START");
    if (endn < 0)
        endn = call_wad_num(rd, "check_num_for_name", "SS_END");

    int first, last;
    if (start >= 0 && endn > start) {
        first = start + 1;
        last = endn - 1;
    } else {
        first = 0;
        last = call_wad_num_lumps(rd) - 1;
    }

    if (last < first)
        return 1;

    /*
     * Primeira passagem: agrupa por prefixo e instala cada lump.
     * A ordem das entradas acompanha a primeira ocorrencia no WAD,
     * como a tabela "order" da implementacao Lua.
     */
    for (int lump = first; lump <= last; ++lump) {
        char name[9] = {0};
        int name_len = call_wad_lump_name(rd, lump, name);

        if (name_len < 6)
            continue;

        char sprite_name[5] = {
            name[0], name[1], name[2], name[3], '\0'
        };

        SpriteEntry *entry = find_sprite_entry(&rd->sprites, sprite_name);
        if (!entry) {
            entry = create_sprite_entry(&rd->sprites, sprite_name);
            if (!entry) {
                free_sprites(&rd->sprites);
                return 0;
            }
        }

        /* O nome precisa ter pelo menos os caracteres frame e rotacao. */
        int frame = (unsigned char)name[4] - (unsigned char)'A';
        int rotation = (unsigned char)name[5] - (unsigned char)'0';

        install_sprite_frame(entry->def.frames, lump, frame, rotation, 0);

        /*
         * Nomes como TROOA2B8 representam dois frames no mesmo lump:
         * frame A / rotacao 2 normal e frame B / rotacao 8 espelhado.
         *
         * Preserva-se exatamente a condicao do codigo Lua: 'A' <= ch <= ']'.
         */
        if (name_len >= 8) {
            char ch = name[6];
            if (ch >= 'A' && ch <= ']') {
                int frame2 = (unsigned char)name[6] - (unsigned char)'A';
                int rotation2 = (unsigned char)name[7] - (unsigned char)'0';
                install_sprite_frame(entry->def.frames, lump,
                                      frame2, rotation2, 1);
            }
        }
    }

    /*
     * Segunda passagem: calcula o maior frame instalado e normaliza
     * frames intermediarios ausentes para rotate=0, igual ao Lua.
     * Depois reduz a alocacao para maxframe + 1.
     */
    for (int i = 0; i < rd->sprites.count; ++i) {
        SpriteDef *def = &rd->sprites.entries[i].def;
        int maxframe = -1;

        for (int f = 0; f < MAX_SPRITE_FRAMES; ++f) {
            if (def->frames[f].rotate != -1)
                maxframe = f;
        }

        if (maxframe < 0) {
            free(def->frames);
            def->frames = NULL;
            def->frame_count = 0;
            continue;
        }

        for (int f = 0; f <= maxframe; ++f) {
            if (def->frames[f].rotate == -1)
                def->frames[f].rotate = 0;
        }

        def->frame_count = maxframe + 1;

        SpriteFrame *trimmed = (SpriteFrame *)realloc(
            def->frames,
            (size_t)def->frame_count * sizeof(SpriteFrame)
        );
        if (trimmed)
            def->frames = trimmed;
    }

    /* Remove entradas que nao produziram nenhum frame valido. */
    int dst = 0;
    for (int src = 0; src < rd->sprites.count; ++src) {
        SpriteEntry *entry = &rd->sprites.entries[src];

        if (entry->def.frame_count == 0) {
            free(entry->def.frames);
            continue;
        }

        if (dst != src)
            rd->sprites.entries[dst] = *entry;

        ++dst;
    }
    rd->sprites.count = dst;

    if (dst == 0) {
        free(rd->sprites.entries);
        rd->sprites.entries = NULL;
    } else {
        SpriteEntry *trimmed = (SpriteEntry *)realloc(
            rd->sprites.entries, (size_t)dst * sizeof(SpriteEntry)
        );
        if (trimmed)
            rd->sprites.entries = trimmed;
    }

    return 1;
}

static int l_skyflatnum(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_pushinteger(L, rd->skyflatnum);
    return 1;
}

static int l_skytexture(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_pushinteger(L, rd->skytexture);
    return 1;
}
static int l_colormap(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer level = luaL_checkinteger(L, 2);
    if (level < 0) level = 0;
    if (level > 32) level = 32;

    size_t offset = (size_t)level * 256u;
    if (!rd->colormaps || !has_bytes(rd->colormaps_size, offset, 256))
        return luaL_error(L, "r_data_c: COLORMAP does not contain level %lld",
                          (long long)level);

    lua_pushlstring(L, (const char *)rd->colormaps + offset, 256);
    return 1;
}

static int l_flat_num_for_name(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    const char *name = luaL_checkstring(L, 2);
    int lump = call_wad_num(rd, "check_num_for_name", name);
    lua_pushinteger(L, lump < 0 ? 0 : lump - rd->flats_first);
    return 1;
}

static int l_flat_lump(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer flatnum = luaL_checkinteger(L, 2);
    if (rd->flat_count <= 0) {
        lua_pushinteger(L, rd->flats_first);
        return 1;
    }
    if (flatnum < 0 || flatnum >= rd->flat_count)
        flatnum = 0;
    lua_pushinteger(L, rd->flats_first + (int)flatnum);
    return 1;
}

static int l_flat_pixels(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer flatnum = luaL_checkinteger(L, 2);
    if (rd->flat_count <= 0)
        return luaL_error(L, "r_data_c: no flats found between F_START and F_END");
    if (flatnum < 0 || flatnum >= rd->flat_count)
        flatnum = 0;

    int lump = rd->flats_first + (int)flatnum;
    int data_idx = push_lump_num(rd, lump);
    size_t size = 0;
    const char *data = lua_tolstring(L, data_idx, &size);

    char buffer[4096];
    size_t n = size < sizeof(buffer) ? size : sizeof(buffer);
    if (n) memcpy(buffer, data, n);
    if (n < sizeof(buffer)) memset(buffer + n, 0, sizeof(buffer) - n);

    lua_pushlstring(L, buffer, sizeof(buffer));
    lua_remove(L, data_idx);
    return 1;
}

static int l_texture_num_for_name(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    const char *name = luaL_checkstring(L, 2);
    int idx = texture_index_by_name(rd, name);
    lua_pushinteger(L, idx < 0 ? 0 : idx);
    return 1;
}

static Texture *get_texture(RData *rd, lua_Integer texnum) {
    if (texnum < 0 || texnum >= rd->texture_count)
        return NULL;
    return &rd->textures[texnum];
}

static int l_texture_height(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer n = luaL_checkinteger(L, 2);
    Texture *tex = get_texture(rd, n);
    if (!tex) return luaL_error(L, "r_data_c: invalid texture number");
    lua_pushinteger(L, (lua_Integer)tex->height * FRACUNIT);
    return 1;
}

static int l_texture_width(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer n = luaL_checkinteger(L, 2);
    Texture *tex = get_texture(rd, n);
    if (!tex) return luaL_error(L, "r_data_c: invalid texture number");
    lua_pushinteger(L, tex->width);
    return 1;
}

static void column_to_source(
    const uint8_t *patch, size_t patch_size, uint32_t column,
    uint8_t out[128]
) {
    memset(out, 0, 128);
    size_t pos = column;

    while (pos < patch_size) {
        uint8_t topdelta = patch[pos];
        if (topdelta == 255) break;
        if (!has_bytes(patch_size, pos, 3)) break;
        uint8_t length = patch[pos + 1];
        size_t source = pos + 3;
        if (!has_bytes(patch_size, source, length)) break;

        for (int i = 0; i < length; ++i) {
            int y = (int)topdelta + i;
            if (y >= 0 && y < 128)
                out[y] = patch[source + (size_t)i];
        }
        pos += (size_t)length + 4u;
    }
}

static int l_column_posts(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer texnum = luaL_checkinteger(L, 2);
    lua_Integer col = luaL_checkinteger(L, 3);

    Texture *tex = get_texture(rd, texnum);
    if (!tex || texnum <= 0) {
        lua_newtable(L);
        return 1;
    }

    col = (lua_Integer)((uint32_t)col & (uint32_t)tex->widthmask);
    int lump = tex->col_lump[col];

    lua_newtable(L);
    int result = lua_gettop(L);

    if (lump >= 0) {
        int patch_idx = push_lump_num(rd, lump);
        size_t size = 0;
        const uint8_t *patch = (const uint8_t *)lua_tolstring(L, patch_idx, &size);
        size_t pos = tex->col_ofs[col];
        int post = 1;

        while (pos < size) {
            uint8_t topdelta = patch[pos];
            if (topdelta == 255) break;
            if (!has_bytes(size, pos, 3)) break;
            uint8_t length = patch[pos + 1];
            size_t source = pos + 3;
            if (!has_bytes(size, source, length)) break;

            lua_createtable(L, 0, 2);
            lua_pushinteger(L, topdelta);
            lua_setfield(L, -2, "topdelta");
            lua_pushlstring(L, (const char *)patch + source, length);
            lua_setfield(L, -2, "pixels");
            lua_rawseti(L, result, post++);

            pos += (size_t)length + 4u;
        }
        lua_remove(L, patch_idx);
        return 1;
    }

    if (!generate_composite(rd, tex))
        return luaL_error(L, "r_data_c: out of memory generating composite texture");

    size_t offset = (size_t)tex->col_ofs[col];
    if (has_bytes((size_t)tex->width * tex->height, offset, (size_t)tex->height)) {
        lua_createtable(L, 0, 2);
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "topdelta");
        lua_pushlstring(L, (const char *)tex->composite + offset, (size_t)tex->height);
        lua_setfield(L, -2, "pixels");
        lua_rawseti(L, result, 1);
    }
    return 1;
}

static int l_get_column(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer texnum = luaL_checkinteger(L, 2);
    lua_Integer col = luaL_checkinteger(L, 3);

    Texture *tex = get_texture(rd, texnum);
    if (!tex)
        return luaL_error(L, "r_data_c: invalid texture number");

    col = (lua_Integer)((uint32_t)col & (uint32_t)tex->widthmask);
    uint8_t output[128];
    int lump = tex->col_lump[col];

    if (lump >= 0) {
        int patch_idx = push_lump_num(rd, lump);
        size_t size = 0;
        const uint8_t *patch = (const uint8_t *)lua_tolstring(L, patch_idx, &size);
        column_to_source(patch, size, tex->col_ofs[col], output);
        lua_pop(L, 1);
    } else {
        if (!generate_composite(rd, tex))
            return luaL_error(L, "r_data_c: out of memory generating composite texture");

        size_t offset = (size_t)tex->col_ofs[col];
        size_t total = (size_t)tex->width * (size_t)tex->height;
        size_t n = (size_t)tex->height;
        if (offset > total || n > total - offset)
            return luaL_error(L, "r_data_c: invalid composite column offset");

        const uint8_t *source = tex->composite + offset;
        if (n > 0) {
            for (int i = 0; i < 128; ++i)
                output[i] = source[(size_t)i % n];
        } else {
            memset(output, 0, sizeof(output));
        }
    }

    lua_pushlstring(L, (const char *)output, sizeof(output));
    return 1;
}

static int l_init(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    free_rdata(rd);

    /* 1. init_textures(self) */
    if (!init_textures(rd))
        return luaL_error(L,
            "r_data_c: failed to parse PNAMES/TEXTURE1/TEXTURE2");

    /* 2. init_flats(self) */
    rd->flats_first =
        call_wad_num(rd, "get_num_for_name", "F_START") + 1;

    rd->flats_last =
        call_wad_num(rd, "get_num_for_name", "F_END") - 1;

    rd->flat_count = rd->flats_last >= rd->flats_first
        ? rd->flats_last - rd->flats_first + 1
        : 0;

    /* flattranslation é identidade: não precisamos armazená-la. */

    /* 3. self.colormaps = wad.cache_lump_name(...) */
    int cmap_idx = push_lump_name(rd, "COLORMAP");

    size_t cmap_size = 0;
    const char *cmap = lua_tolstring(L, cmap_idx, &cmap_size);

    rd->colormaps = (uint8_t *)malloc(cmap_size ? cmap_size : 1);

    if (!rd->colormaps) {
        lua_pop(L, 1);
        return luaL_error(L,
            "r_data_c: out of memory allocating COLORMAP");
    }

    if (cmap_size)
        memcpy(rd->colormaps, cmap, cmap_size);

    rd->colormaps_size = cmap_size;
    lua_pop(L, 1);

    /* 4. self.skyflatnum = flat_num_for_name(self, "F_SKY1") */
    int skyflat_lump =
        call_wad_num(rd, "check_num_for_name", "F_SKY1");

    rd->skyflatnum = skyflat_lump < 0
        ? 0
        : skyflat_lump - rd->flats_first;

    /* 5. self.skytexture = texture_num_for_name(self, "SKY1") */
    int skytexture = texture_index_by_name(rd, "SKY1");

    rd->skytexture = skytexture < 0 ? 0 : skytexture;

    /* 6. self.sprites = sprites.init_defs(wadfile) */
    if (!init_sprites(rd))
        return luaL_error(L,
            "r_data_c: failed to initialize sprites");

    rd->initialized = 1;

    lua_pushvalue(L, 1);
    return 1;

    lua_pushvalue(L, 1);
    return 1;
}

static int l_sprite_count(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_pushinteger(L, rd->sprites.count);
    return 1;
}

static int l_sprite_name(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    int index = (int)luaL_checkinteger(L, 2);

    /* Índice recebido pelo Lua: começa em 1. */
    if (index < 1 || index > rd->sprites.count) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushstring(L, rd->sprites.entries[index - 1].name);
    return 1;
}

static int l_sprite_frame_count(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    const char *name = luaL_checkstring(L, 2);

    for (int i = 0; i < rd->sprites.count; i++) {
        SpriteEntry *entry = &rd->sprites.entries[i];

        if (strcmp(entry->name, name) == 0) {
            lua_pushinteger(L, entry->def.frame_count);
            return 1;
        }
    }

    lua_pushnil(L);
    return 1;
}

static int l_sprite_frame(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    const char *name = luaL_checkstring(L, 2);

    /* Frame específico é opcional. */
    int frame_index = 0;

    if (!lua_isnoneornil(L, 3)) {
        frame_index = (int)luaL_checkinteger(L, 3);
    }

    for (int i = 0; i < rd->sprites.count; i++) {
        SpriteEntry *entry = &rd->sprites.entries[i];

        if (strcmp(entry->name, name) != 0)
            continue;

        /* Retorna um frame específico. */
        if (frame_index != 0) {
            if (frame_index < 1 ||
                frame_index > entry->def.frame_count) {
                lua_pushnil(L);
                return 1;
            }

            SpriteFrame *frame =
                &entry->def.frames[frame_index - 1];

            lua_createtable(L, 0, 3);

            lua_pushinteger(L, frame->rotate);
            lua_setfield(L, -2, "rotate");

            lua_createtable(L, SPRITE_ROTATIONS, 0);

            for (int r = 0; r < SPRITE_ROTATIONS; r++) {
                lua_pushinteger(L, frame->lump[r]);
                lua_rawseti(L, -2, r + 1);
            }

            lua_setfield(L, -2, "lump");

            lua_createtable(L, SPRITE_ROTATIONS, 0);

            for (int r = 0; r < SPRITE_ROTATIONS; r++) {
                lua_pushinteger(L, frame->flip[r]);
                lua_rawseti(L, -2, r + 1);
            }

            lua_setfield(L, -2, "flip");

            return 1;
        }

        /* Retorna todos os frames. */
        int count = entry->def.frame_count;

        lua_createtable(L, count, 0);

        for (int i = 0; i < count; i++) {
            SpriteFrame *frame = &entry->def.frames[i];

            lua_createtable(L, 0, 3);

            lua_pushinteger(L, frame->rotate);
            lua_setfield(L, -2, "rotate");

            lua_createtable(L, SPRITE_ROTATIONS, 0);

            for (int r = 0; r < SPRITE_ROTATIONS; r++) {
                lua_pushinteger(L, frame->lump[r]);
                lua_rawseti(L, -2, r + 1);
            }

            lua_setfield(L, -2, "lump");

            lua_createtable(L, SPRITE_ROTATIONS, 0);

            for (int r = 0; r < SPRITE_ROTATIONS; r++) {
                lua_pushinteger(L, frame->flip[r]);
                lua_rawseti(L, -2, r + 1);
            }

            lua_setfield(L, -2, "flip");

            lua_rawseti(L, -2, i + 1);
        }

        return 1;
    }

    lua_pushnil(L);
    return 1;
}

static int l_sprite_lookup(lua_State *L)
{
    RData *rd = check_rdata(L, 1);

    size_t name_len;
    const char *name = luaL_checklstring(L, 2, &name_len);

    lua_Integer ang_to_thing = luaL_checkinteger(L, 3);
    lua_Integer moangle = luaL_checkinteger(L, 4);
    lua_Integer frame = luaL_checkinteger(L, 5);

    /* Normaliza os quatro primeiros caracteres do nome. */
    char base[5] = {0};

    for (int i = 0; i < 4 && (size_t)i < name_len; i++) {
        base[i] = (char)toupper((unsigned char)name[i]);
    }

    /* Localiza a definição do sprite. */
    SpriteEntry *entry = NULL;

    for (int i = 0; i < rd->sprites.count; i++) {
        if (memcmp(rd->sprites.entries[i].name, base, 4) == 0) {
            entry = &rd->sprites.entries[i];
            break;
        }
    }

    if (!entry) {
        lua_pushnil(L);
        return 1;
    }

    /* Equivalente a band(frame, 32767). */
    int fi = (uint32_t)frame & 32767;

    SpriteDef *def = &entry->def;

    if (fi >= def->frame_count) {
        lua_pushnil(L);
        return 1;
    }

    SpriteFrame *sf = &def->frames[fi];

    int rotation_index = 0;

    if (sf->rotate != 0) {
        /*
         * Equivalente a:
         * band(ushr(as_u32(ang_to_thing - moangle
         *     + 2415919104), 29), 7)
         */
        uint32_t angle =
            (uint32_t)ang_to_thing -
            (uint32_t)moangle +
            UINT32_C(0x90000000);

        rotation_index = (angle >> 29) & 7;
    }

    int lump = sf->lump[rotation_index];
    int flip = sf->flip[rotation_index];

    if (lump < 0) {
        lua_pushnil(L);
        return 1;
    }

    lua_pushinteger(L, lump);
    lua_pushinteger(L, flip);

    return 2;
}

static int l_texture_count(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_pushinteger(L, rd->texture_count);
    return 1;
}

static int l_flat_count(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_pushinteger(L, rd->flat_count);
    return 1;
}

static int l_texture_name(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer index = luaL_checkinteger(L, 2);

    /* Lua usa índice baseado em 1; C usa índice baseado em 0. */
    Texture *tex = get_texture(rd, index - 1);

    if (!tex)
        return luaL_error(L, "r_data_c: invalid texture index");

    lua_pushstring(L, tex->name);
    return 1;
}

static int l_texture_info(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer index = luaL_checkinteger(L, 2);

    Texture *tex = get_texture(rd, index - 1);

    if (!tex)
        return luaL_error(L, "r_data_c: invalid texture index");

    lua_createtable(L, 0, 7);

    lua_pushstring(L, tex->name);
    lua_setfield(L, -2, "name");

    lua_pushinteger(L, tex->width);
    lua_setfield(L, -2, "width");

    lua_pushinteger(L, tex->height);
    lua_setfield(L, -2, "height");

    lua_pushinteger(L, tex->widthmask);
    lua_setfield(L, -2, "widthmask");

    lua_createtable(L, tex->patch_count, 0);

    for (int i = 0; i < tex->patch_count; i++) {
        lua_createtable(L, 0, 3);

        lua_pushinteger(L, tex->patches[i].originx);
        lua_setfield(L, -2, "originx");

        lua_pushinteger(L, tex->patches[i].originy);
        lua_setfield(L, -2, "originy");

        lua_pushinteger(L, tex->patches[i].patch);
        lua_setfield(L, -2, "patch");

        lua_rawseti(L, -2, i + 1);
    }

    lua_setfield(L, -2, "patches");

    lua_createtable(L, tex->width, 0);

    for (int i = 0; i < tex->width; i++) {
        lua_pushinteger(L, tex->col_lump[i]);
        lua_rawseti(L, -2, i + 1);
    }

    lua_setfield(L, -2, "col_lump");

    lua_createtable(L, tex->width, 0);

    for (int i = 0; i < tex->width; i++) {
        lua_pushinteger(L, tex->col_ofs[i]);
        lua_rawseti(L, -2, i + 1);
    }

    lua_setfield(L, -2, "col_ofs");

    return 1;
}

static int l_cache_lump_num(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    lua_Integer lump_num = luaL_checkinteger(L, 2);

    /* Empilha o módulo wad. */
    push_wad_module(rd);

    /* Empilha wad.cache_lump_num. */
    lua_getfield(L, -1, "cache_lump_num");

    /* Empilha a instância do WAD. */
    push_wad(rd);

    /* Empilha o número do lump. */
    lua_pushinteger(L, lump_num);

    /* Remove o módulo wad da pilha. */
    lua_remove(L, -4);

    /* Executa cache_lump_num(wad, lump_num). */
    lua_call(L, 2, 1);

    return 1;
}

static int l_check_num_for_name(lua_State *L) {
    RData *rd = check_rdata(L, 1);

    /* Empilha o módulo wad. */
    push_wad_module(rd);

    /* Empilha wad.check_num_for_name. */
    lua_getfield(L, -1, "check_num_for_name");

    /* Empilha a instância do WAD. */
    push_wad(rd);

    /* Empilha o nome do lump. */
    lua_pushvalue(L, 2);

    /* Remove o módulo wad da pilha. */
    lua_remove(L, -4);

    /* Executa check_num_for_name(wad, nome). */
    lua_call(L, 2, 1);

    return 1;
}

/*
 * Prepara os dados que o render_c le direto da memoria:
 *   - Texture.wall128: cada coluna exatamente como get_column devolve;
 *   - Texture.mposts/mpix: os posts exatamente como column_posts devolve;
 *   - RData.flatpix: cada flat exatamente como flat_pixels devolve.
 * Idempotente. Chamado uma vez por render_c.new().
 */
static int prepare_texture(RData *rd, Texture *tex) {
    lua_State *L = rd->L;
    if (tex->width <= 0 || tex->height <= 0)
        return 1;
    if (!generate_composite(rd, tex))
        return 0;

    tex->wall128 = (uint8_t *)calloc((size_t)tex->width, RD_COLUMN_SIZE);
    tex->mpost_first = (int32_t *)calloc((size_t)tex->width + 1, sizeof(int32_t));
    if (!tex->wall128 || !tex->mpost_first)
        return 0;

    size_t npost = 0, cap_post = (size_t)tex->width + 8;
    size_t npix = 0, cap_pix = (size_t)tex->width * (size_t)tex->height + 64;
    tex->mposts = (MaskedPost *)malloc(cap_post * sizeof(MaskedPost));
    tex->mpix = (uint8_t *)malloc(cap_pix);
    if (!tex->mposts || !tex->mpix)
        return 0;

    size_t total = (size_t)tex->width * (size_t)tex->height;

    for (int x = 0; x < tex->width; ++x) {
        uint8_t *out = tex->wall128 + (size_t)x * RD_COLUMN_SIZE;
        tex->mpost_first[x] = (int32_t)npost;
        int lump = tex->col_lump[x];

        /* Fontes: (topdelta, length, ponteiro) de cada post desta coluna. */
        const uint8_t *patch = NULL;
        size_t size = 0;
        int patch_idx = 0;

        if (lump >= 0) {
            patch_idx = push_lump_num(rd, lump);
            patch = (const uint8_t *)lua_tolstring(L, patch_idx, &size);
            column_to_source(patch, size, tex->col_ofs[x], out);
        } else {
            size_t offset = (size_t)tex->col_ofs[x];
            size_t n = (size_t)tex->height;
            if (offset <= total && n <= total - offset) {
                const uint8_t *src = tex->composite + offset;
                for (int i = 0; i < RD_COLUMN_SIZE; ++i)
                    out[i] = src[(size_t)i % n];
            }
        }

        /* Posts mascarados (mesma logica de l_column_posts). */
        if (lump >= 0) {
            size_t pos = tex->col_ofs[x];
            while (pos < size) {
                uint8_t topdelta = patch[pos];
                if (topdelta == 255) break;
                if (!has_bytes(size, pos, 3)) break;
                uint8_t length = patch[pos + 1];
                size_t source = pos + 3;
                if (!has_bytes(size, source, length)) break;
                if (npost == cap_post) {
                    cap_post *= 2;
                    MaskedPost *np = (MaskedPost *)realloc(tex->mposts, cap_post * sizeof(MaskedPost));
                    if (!np) { lua_pop(L, 1); return 0; }
                    tex->mposts = np;
                }
                if (npix + length > cap_pix) {
                    cap_pix = (cap_pix + length) * 2;
                    uint8_t *np = (uint8_t *)realloc(tex->mpix, cap_pix);
                    if (!np) { lua_pop(L, 1); return 0; }
                    tex->mpix = np;
                }
                memcpy(tex->mpix + npix, patch + source, length);
                tex->mposts[npost].topdelta = topdelta;
                tex->mposts[npost].length = length;
                tex->mposts[npost].pixofs = (uint32_t)npix;
                npost++;
                npix += length;
                pos += (size_t)length + 4u;
            }
            lua_remove(L, patch_idx);
        } else {
            size_t offset = (size_t)tex->col_ofs[x];
            size_t n = (size_t)tex->height;
            if (has_bytes(total, offset, n)) {
                if (npost == cap_post) {
                    cap_post *= 2;
                    MaskedPost *np = (MaskedPost *)realloc(tex->mposts, cap_post * sizeof(MaskedPost));
                    if (!np) return 0;
                    tex->mposts = np;
                }
                if (npix + n > cap_pix) {
                    cap_pix = (cap_pix + n) * 2;
                    uint8_t *np = (uint8_t *)realloc(tex->mpix, cap_pix);
                    if (!np) return 0;
                    tex->mpix = np;
                }
                memcpy(tex->mpix + npix, tex->composite + offset, n);
                tex->mposts[npost].topdelta = 0;
                tex->mposts[npost].length = (int)n;
                tex->mposts[npost].pixofs = (uint32_t)npix;
                npost++;
                npix += n;
            }
        }
    }
    tex->mpost_first[tex->width] = (int32_t)npost;
    return 1;
}

static int l_prepare_render(lua_State *L) {
    RData *rd = check_rdata(L, 1);
    if (!rd->initialized)
        return luaL_error(L, "r_data_c: prepare_render antes de init");
    if (rd->render_ready) {
        lua_pushvalue(L, 1);
        return 1;
    }
    for (int i = 0; i < rd->texture_count; ++i) {
        if (!prepare_texture(rd, &rd->textures[i]))
            return luaL_error(L, "r_data_c: sem memoria preparando textura %d", i);
    }
    size_t nflats = rd->flat_count > 0 ? (size_t)rd->flat_count : 1;
    rd->flatpix = (uint8_t *)calloc(nflats, RD_FLAT_SIZE);
    if (!rd->flatpix)
        return luaL_error(L, "r_data_c: sem memoria para flats");
    for (int f = 0; f < rd->flat_count; ++f) {
        int idx = push_lump_num(rd, rd->flats_first + f);
        size_t size = 0;
        const char *data = lua_tolstring(L, idx, &size);
        size_t n = size < RD_FLAT_SIZE ? size : RD_FLAT_SIZE;
        if (n) memcpy(rd->flatpix + (size_t)f * RD_FLAT_SIZE, data, n);
        lua_remove(L, idx);
    }
    rd->render_ready = 1;
    lua_pushvalue(L, 1);
    return 1;
}

static const luaL_Reg rdata_methods[] = {
    {"init", l_init},
    {"prepare_render", l_prepare_render},
    {"colormap", l_colormap},
    {"flat_num_for_name", l_flat_num_for_name},
    {"flat_lump", l_flat_lump},
    {"flat_pixels", l_flat_pixels},
    {"texture_num_for_name", l_texture_num_for_name},
    {"texture_height", l_texture_height},
    {"texture_width", l_texture_width},
    {"column_posts", l_column_posts},
    {"get_column", l_get_column},
    {"skyflatnum", l_skyflatnum},
    {"skytexture", l_skytexture},
    {"sprite_count", l_sprite_count},
    {"sprite_name", l_sprite_name},
    {"sprite_frame_count", l_sprite_frame_count},
    {"sprite_frame", l_sprite_frame},
    {"sprite_lookup", l_sprite_lookup},
    {"texture_count", l_texture_count},
    {"flat_count", l_flat_count},
    {"texture_name", l_texture_name},
    {"texture_info", l_texture_info},
    {"cache_lump_num", l_cache_lump_num},
    {"check_num_for_name", l_check_num_for_name},
    {NULL, NULL}
};

static const luaL_Reg module_functions[] = {
    {"new", l_new},
    {NULL, NULL}
};

int luaopen_r_data_c(lua_State *L) {
    luaL_newmetatable(L, RD_MT);
    lua_pushcfunction(L, l_gc);
    lua_setfield(L, -2, "__gc");

    lua_newtable(L);
    luaL_setfuncs(L, rdata_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newlib(L, module_functions);
    return 1;
}




