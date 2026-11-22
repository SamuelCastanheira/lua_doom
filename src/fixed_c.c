#include "fixed.h"
#include <limits.h>


/* =========================================================

Conversões de 32 bits

========================================================= */

uint32_t as_u32(int64_t n)
{
    return (uint32_t)n;
}

int32_t as_i32(int64_t n)
{
    uint32_t u = (uint32_t)n;

    if (u <= INT32_MAX)
        return (int32_t)u;

    /* Conversão explícita sem depender de overflow assinado. */
    return (int32_t)((int64_t)u - 4294967296LL);

}

/* =========================================================

Ponto fixo 16.16

========================================================= */

int32_t fixed_mul(int32_t a, int32_t b)
{
    int64_t product = (int64_t)a * (int64_t)b;

    /* Divisão por 65536 arredondada para baixo. */
    int64_t result = product / FRACUNIT;

    if (product < 0 && product % FRACUNIT != 0)
        result--;

    return as_i32(result);
}

int32_t fixed_div(int32_t a, int32_t b)
{
    if (b == 0)
    return a >= 0 ? FIXED_MAXINT : FIXED_MININT;

    int64_t abs_a = a < 0 ? -(int64_t)a : a;
    int64_t abs_b = b < 0 ? -(int64_t)b : b;

    if ((abs_a >> 14) >= abs_b)
        return ((a < 0) == (b < 0))
            ? FIXED_MAXINT
            : FIXED_MININT;

    /*
    * Lua floor_div implementa floor(n / d).
    * C faz divisão truncando em direção a zero.
    * Corrigimos o resultado quando há resto e sinal negativo.
    */
    int64_t numerator = (int64_t)a * FRACUNIT;
    int64_t quotient = numerator / b;
    int64_t remainder = numerator % b;

    if (remainder != 0 && ((numerator < 0) != (b < 0)))
        quotient--;

    return as_i32(quotient);

}

int64_t abs_fixed(int32_t n)
{
    return n < 0 ? -(int64_t)n : n;
}
