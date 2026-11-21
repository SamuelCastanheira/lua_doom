#ifndef FIXED_H
#define FIXED_H

#include <stdint.h>

#define FRACBITS 16
#define FRACUNIT 65536

#define FIXED_MAXINT INT32_MAX
#define FIXED_MININT INT32_MIN

/* Conversões e wrap de 32 bits */
uint32_t as_u32(int64_t n);
int32_t as_i32(int64_t n);

/* Ponto fixo 16.16 */
int32_t fixed_mul(int32_t a, int32_t b);
int32_t fixed_div(int32_t a, int32_t b);
int64_t abs_fixed(int32_t n);

#endif