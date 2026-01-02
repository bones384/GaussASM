#include "pch.h"
#include "gauss_cpp.h"

int sq(int num)
{
	return num * num;
}
//pass: pointer to data, bit depth, height, stride, 
// eventually where each threads data stops

void gauss(BYTE* data, int depth, int height, int stride)
{
	// for all rows
	for (int i = 0; i < height; i++)
	{
		// for all pixels in row
		for (int j = 0; j < stride; j++)
		{
			data[i * stride + j] = (int)((((1.*j)/(1.*stride)))*255);
		}
	}
}