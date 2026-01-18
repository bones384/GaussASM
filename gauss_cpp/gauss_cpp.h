#pragma once

#include <cstdint>
#ifdef MATHLIBRARY_EXPORTS
#define LIBRARY_API __declspec(dllexport)
#else
#define LIBRARY_API __declspec(dllimport)
#endif
extern "C" {
    LIBRARY_API void gauss_horizontal(uint8_t* input, uint8_t* output, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row);
    LIBRARY_API void gauss_vertical(uint8_t* input, uint8_t* output, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row, int height);
}