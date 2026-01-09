#include "pch.h"
#include "gauss_cpp.h"
#include "math.h" 
#include <cmath> 
#include <thread>
#include <cassert>
#include <cstdint>


void gauss_horizontal(uint8_t* data, uint8_t* temp, int height, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row)
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
			temp[pixel_base + 3] = data[pixel_base + 3];
			// Process RGB channels
			for (int k = 0; k < 3; k++)
			{
				int sum = 0;
				// Center pixel
				sum += kernel[0] * data[pixel_base + k];
				// Apply kernel to left and right neighbors
				for (int l = 1; l < kernel_size; l++)
				{
					// Left neighbor
					int left_j = j - l * 4;
					int left_idx = (left_j < 0) ? (row_base + k) : (row_base + left_j + k);
					sum += kernel[l] * data[left_idx];

					// Right neighbor
					int right_j = j + l * 4;
					int right_idx = (right_j >= rowBytes) ? (row_base + rowBytes - 4 + k) : (row_base + right_j + k);
					sum += kernel[l] * data[right_idx];
				}
				temp[pixel_base + k] = sum >> 14;
			}
		}
	}
}

void gauss_vertical(uint8_t* data, uint8_t* temp, int height, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row)
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
			data[pixel_offset + 3] = 255;
			// Process RGB channels
			for (int k = 0; k < 3; k++)
			{
				int sum = 0;
				// Center pixel
				sum += kernel[0] * temp[pixel_offset + k];
				// Vertical kernel application
				for (int l = 1; l < kernel_size; l++)
				{
					int down = i - l;
					if (down < 0) down = 0;
					int down_offset = down * stride + j + k;
					sum += kernel[l] * temp[down_offset];

					int up = i + l;
					if (up >= height) up = height - 1;
					int up_offset = up * stride + j + k;
					sum += kernel[l] * temp[up_offset];
				}
				data[pixel_offset + k] = sum >> 14;
			}
		}
	}
}

void gauss(uint8_t* data, uint8_t* temp, int height, int width, int stride, uint16_t* kernel, int kernel_size, int start_row, int end_row, int isHorizontal)
{
	uint8_t depth = 4;

	int rowBytes = width * depth;
	//1st pass
	// for rows
	if (isHorizontal)
	{
		for (int i = start_row; i < end_row; i++)
		{
			int row_base = i * stride;
			for (int j = 0; j < rowBytes; j += 4)
			{
				int pixel_base = row_base + j;
				// Copy alpha channel
				temp[pixel_base + 3] = data[pixel_base + 3];
				// Process RGB channels
				for (int k = 0; k < 3; k++)
				{
					int sum = 0;
					// Center pixel
					sum += kernel[0] * data[pixel_base + k];
					// Apply kernel to left and right neighbors
					for (int l = 1; l < kernel_size; l++)
					{
						// Left neighbor
						int left_j = j - l * 4;
						int left_idx = (left_j < 0) ? (row_base + k) : (row_base + left_j + k);
						sum += kernel[l] * data[left_idx];

						// Right neighbor
						int right_j = j + l * 4;
						int right_idx = (right_j >= rowBytes) ? (row_base + rowBytes - 4 + k) : (row_base + right_j + k);
						sum += kernel[l] * data[right_idx];
					}
					temp[pixel_base + k] = sum >> 14;
				}
			}
		}
	}

	//2nd pass
	// for rows
	else
	{
		for (int i = start_row; i < end_row; i++)
		{
			int row_offset = i * stride;
			for (int j = 0; j < rowBytes; j += 4)
			{
				int pixel_offset = row_offset + j;
				// Copy alpha channel
				data[pixel_offset + 3] = temp[pixel_offset + 3];
				// Process RGB channels
				for (int k = 0; k < 3; k++)
				{
					int sum = 0;
					// Center pixel
					sum += kernel[0] * temp[pixel_offset + k];
					// Vertical kernel application
					for (int l = 1; l < kernel_size; l++)
					{
						int down = i - l;
						if (down < 0) down = 0;
						int down_offset = down * stride + j + k;
						sum += kernel[l] * temp[down_offset];

						int up = i + l;
						if (up >= height) up = height - 1;
						int up_offset = up * stride + j + k;
						sum += kernel[l] * temp[up_offset];
					}
					data[pixel_offset + k] = sum >> 14;
				}
			}
		}
	}
	return;
}