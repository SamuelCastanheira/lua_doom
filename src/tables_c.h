#ifndef TABLES_C_H
#define TABLES_C_H

#include <stdbool.h>
#include <stdint.h>

#define TABLE_MT "tables_c.Table"

#define TABLE_FINEANGLES 8192
#define TABLE_SLOPERANGE 2048
#define TABLE_FINEMASK 8191
#define TABLE_ANGLETOFINESHIFT 19

#define TABLE_FINESINE_SIZE (TABLE_FINEANGLES * 5 / 4)

typedef struct {
    int32_t finesine[TABLE_FINESINE_SIZE];
    int32_t finetangent[TABLE_FINEANGLES / 2];
    uint32_t tantoangle[TABLE_SLOPERANGE + 1];

    bool ready;
} Table;

#endif