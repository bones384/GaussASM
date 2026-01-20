/*
* Author: Mateusz Kowalec
* Created: January 2, 2026
* Modified: January 18, 2026
* File: gauss_cpp.cpp
* Functions: gauss_horizontal, gauss_vertical
* Description: Implements Gaussian blur in C++ for horizontal and vertical passes.
*/

#include "pch.h"
#include "gauss_cpp.h"
#include "math.h" 
#include <cmath> 
#include <thread>
#include <cassert>
#include <cstdint>

/*
* Applies horizontal Gaussian blur to the input image.
* 
* Parameters:
* - input: Pointer to the input image data (Format32bppArgb). Pointer to an array of bytes representing the input image in 32bpp ARGB format.
* - output: Pointer to the output image data (Format32bppArgb). Pointer to an array of bytes where the blurred image will be stored in 32bpp ARGB format.
* - width: Width of the image in pixels. Int.
* - stride: Number of bytes in a row of the image. Int.
* - kernel: Pointer to the Gaussian kernel (1D, normalized to 14 bits). Pointer to an array of 16-bit unsigned integers representing the Gaussian kernel values.
* - kernel_size: Size of the Gaussian kernel (radius). Int.
* - start_row: Starting row index for processing. Int.
* - end_row: Ending row index for processing. Int.
* 
*  output[row,col] = sum_{j=-kernel_size}^{kernel_size} kernel[|j|] * input[row,min(max(col + j, width-1), 0], for row in [start_row, end_row)
*/
void gauss_horizontal(uint8_t* input, uint8_t* output, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row)
{
	uint8_t depth = 4;

	int rowBytes = width * depth;
	for (int i = start_row; i < end_row; i++)
	{
		int row_base = i * stride;
		for (int j = 0; j < rowBytes; j += 4)
		{
			int pixel_base = row_base + j;
			// Copy alpha channel
			output[pixel_base + 3] = input[pixel_base + 3];
			// Process RGB channels
			for (int k = 0; k < 3; k++)
			{
				int sum = 0;
				// Center pixel
				sum += kernel[0] * input[pixel_base + k];
				// Apply kernel to left and right neighbors
				for (int l = 1; l < kernel_size; l++)
				{
					// Left neighbor
					int left_j = j - l * 4;
					int left_idx = (left_j < 0) ? (row_base + k) : (row_base + left_j + k);
					sum += kernel[l] * input[left_idx];

					// Right neighbor
					int right_j = j + l * 4;
					int right_idx = (right_j >= rowBytes) ? (row_base + rowBytes - 4 + k) : (row_base + right_j + k);
					sum += kernel[l] * input[right_idx];
				}
				// Store result, shifted back to byte
				output[pixel_base + k] = sum >> 14;
			}
		}
	}
}
/*
* Applies vertical Gaussian blur to the input image.
* 
* Parameters:
* - input: Pointer to the input image data (Format32bppArgb). Pointer to an array of bytes representing the input image in 32bpp ARGB format.
* - output: Pointer to the output image data (Format32bppArgb). Pointer to an array of bytes where the blurred image will be stored in 32bpp ARGB format.
* - width: Width of the image in pixels. Int.
* - stride: Number of bytes in a row of the image. Int.
* - kernel: Pointer to the Gaussian kernel (1D, normalized to 14 bits). Pointer to an array of 16-bit unsigned integers representing the Gaussian kernel values.
* - kernel_size: Size of the Gaussian kernel (radius). Int.
* - start_row: Starting row index for processing. Int.
* - end_row: Ending row index for processing. Int.
* - height: Height of the image in pixels. Int.
* 
*  output[row,col] = sum_{j=-kernel_size}^{kernel_size} kernel[|j|] * input[min(max(row + j, height-1), 0),col], for row in [start_row, end_row)
*/
void gauss_vertical(uint8_t* input, uint8_t* output, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row, int height)
{
	uint8_t depth = 4;

	int rowBytes = width * depth;
	for (int i = start_row; i < end_row; i++)
	{
		int row_offset = i * stride;
		for (int j = 0; j < rowBytes; j += 4)
		{
			int pixel_offset = row_offset + j;
			// alpha = 1 
			//TODO: change
			output[pixel_offset + 3] = input[pixel_offset+3];
			// Process RGB channels
			for (int k = 0; k < 3; k++)
			{
				int sum = 0;
				// Center pixel
				sum += kernel[0] * input[pixel_offset + k];
				// Vertical kernel application
				for (int l = 1; l < kernel_size; l++)
				{
					int down = i - l;
					if (down < 0) down = 0;
					int down_offset = down * stride + j + k;
					sum += kernel[l] * input[down_offset];

					int up = i + l;
					if (up >= height) up = height - 1;
					int up_offset = up * stride + j + k;
					sum += kernel[l] * input[up_offset];
				}
				output[pixel_offset + k] = sum >> 14;
			}
		}
	}
}
