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

#endif