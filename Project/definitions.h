#ifndef definitions_h
#define definitions_h

#include <simd/simd.h>

#define NUMAGENTS 50000

struct Agent {
    vector_float2 position;
    float angle;
    vector_float3 color;
};

struct Size{
    int x;
    int y;
};

#endif /* definitions_h */
