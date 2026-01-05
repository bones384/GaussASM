#include "pch.h"
#include "gauss_cpp.h"
#include "math.h" 
#include <cmath>
#include <thread>
#include <cassert>
int sq(int num)
{
	return num * num;
}
//pass: pointer to data, bit depth, height, stride, 
// eventually where each threads data stops
#define M_PI 3.14159265358979323846
float gaussian_distribution(int x, float sigma)
{
	return exp(-(x * x) / (2 * sigma * sigma));
}

void gauss(BYTE* data, int depth, int height, int width, int stride, int kernel_size, float sigma)
{
	int rowBytes = width * depth;
	assert(stride >= rowBytes);
	BYTE* temp = new BYTE[height * stride];
	kernel_size = kernel_size / 2 + 1;
	int *kernel = new int[kernel_size];
	float* temp_kernel = new float[kernel_size];
	float sum = 0;
	temp_kernel[0] = gaussian_distribution(0, sigma);
	sum += temp_kernel[0];
	for (int i = 1; i < kernel_size; i++)
	{ 
		float v = gaussian_distribution(i, sigma);
		temp_kernel[i] = v;
		sum += 2*v;
	}
	int fixedsum = 0;
	temp_kernel[0] /= sum;
	kernel[0] = (int)(temp_kernel[0] * (1 << 14));
	fixedsum += kernel[0];
	for (int i = 1; i < kernel_size; i++)
	{ 
		temp_kernel[i] /= sum;
		kernel[i] = (int)(temp_kernel[i] * (1 << 14));
		fixedsum += 2*kernel[i];
	}
	delete[] temp_kernel;
	kernel[0] += ((1 << 14) - fixedsum);
	
	//1st pass
	// for all rows
	for (int i = 0; i < height; i++)
	{
		// for all pixels in row
		for (int j = 0; j < rowBytes; j+=4)
		{
			temp[i * stride + j + 3] = data[i * stride + j + 3];
			//for all components of pixel except alpha
			for (int k = 0; k < 3; k++)
			{
				int sum = 0;
				//1st pixel
				sum += kernel[0] * data[i * stride + j + k];
				//other pixels
				for (int l = 1; l < kernel_size; l++)
				{
					//left
					if (j - l * 4 + k < 0)
						sum += kernel[l] * data[i * stride + k];
					else
					sum += kernel[l] * data[i * stride + j - l * 4 + k];
					//right
					if (j + l * 4  >= rowBytes)
						sum += kernel[l] * data[i * stride + rowBytes - 4 + k];
					else
						sum += kernel[l] * data[i * stride + j + l * 4 + k];
				}

				temp[i * stride + j + k] = sum >> 14;

			}
		}
	}

	//2nd pass
	// for all rows
	for (int i = 0; i < height; i++)
	{

		// for all pixels in row
		for (int j = 0; j < rowBytes; j += 4)
		{
			data[i * stride + j + 3] = temp[i * stride + j + 3];
			//for all components of pixel
			for (int k = 0; k < 3; k++)
			{
				int sum = 0;
				//1st pixel
				sum += kernel[0] * temp[i * stride + j + k];
				//other pixels
				for (int l = 1; l < kernel_size; l++)
				{
					int srcY = i - l;
					if (srcY < 0) srcY = 0;

					sum += kernel[l] * temp[srcY * stride + j + k];

					srcY = i + l;
					if (srcY >= height) srcY = height - 1;

					sum += kernel[l] * temp[srcY * stride + j + k];
				}

				data[i * stride + j + k] = sum >> 14;
			}
		}
	}
	delete[] temp;
	delete[] kernel;
}