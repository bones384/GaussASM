#pragma once

#include <cstdint>
#ifdef MATHLIBRARY_EXPORTS
#define LIBRARY_API __declspec(dllexport)
#else
#define LIBRARY_API __declspec(dllimport)
#endif
extern "C" {
    LIBRARY_API void gauss_horizontal(uint8_t* data, uint8_t* temp, int height, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row);
    LIBRARY_API void gauss_vertical(uint8_t* data, uint8_t* temp,int height, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row);
    LIBRARY_API void gauss(uint8_t* data, uint8_t* temp,  int height, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row, int isHorizontal);
}