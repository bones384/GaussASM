#pragma once

#pragma once

#ifdef MATHLIBRARY_EXPORTS
#define IBRARY_API __declspec(dllexport)
#else
#define LIBRARY_API __declspec(dllimport)
#endif

extern "C" LIBRARY_API int sq(int num);
extern "C" LIBRARY_API void gauss(BYTE* data, int depth, int height, int stride);
