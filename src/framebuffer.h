#ifndef FRAMEBUFFER_H
#define FRAMEBUFFER_H

#include <stdint.h>

#define FB_WIDTH 320
#define FB_HEIGHT 200
#define FB_PIXELS (FB_WIDTH * FB_HEIGHT)

#define FB_MT "framebuffer_c.Framebuffer"

typedef struct {
    uint8_t pixels[FB_PIXELS];
} Framebuffer;

#ifdef LUA_VERSION_NUM
/* v_draw.c: registra draw_patch, draw_line, ... na metatable no topo. */
void v_draw_register(lua_State *L);
#endif

#endif