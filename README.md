# Multithreaded Gaussian blur

This project is a Windows Forms application for applying a configurable two-pass Gaussian blur to images. The blur is implemented as separable horizontal and vertical passes, reducing computational complexity compared to a naive 2D convolution. It supports multiple implementations of the blur algorithm, which can be selected at runtime:

* A C++ implementation (CPU-based)
* An x64 assembly implementation using AVX SIMD instructions.
  
The application dynamically loads the selected library and benchmarks execution time across runs, displaying results in a table. Given the same inputs, both implementations result in exactly the same image.

<img width="1010" height="602" alt="image" src="https://github.com/user-attachments/assets/1d9bb284-97a2-43a3-ab7f-1ae353cb33b8" />

# Assembly implementation

The assembly implementation is written using register aliases and macros. The purpose of each procedure and file is documented in leading comment blocks. AVX (256-bit YMM) registers are used to process multiple pixels in parallel, with both pixel data and kernel values arranged to support efficient vectorized operations.

# Algorithm details

The blur is implemented as two separate passes (horizontal and vertical), reducing the per-pixel computation from N⋅M to N+M for an N×M kernel. The kernel is symmetrical, so only half of it is stored.

To avoid floating-point precision issues and improve performance, kernel values are represented as scaled unsigned integers. Final pixel values are normalized back to the 0–255 range after accumulation.

# Key features

* Runtime switching between implementations
* Configurable blur parameters
* Multithreaded processing (every thread processes an equal number of pixel rows)
* Execution time tracking
* Support for large images (tested up to 10400×10400)
* Kernel radius and blur standard deviation can be tweaked separately

# Architecture

* C# WinForms frontend
* Native DLLs for compute-heavy processing
* Dynamic linking for interchangeable backends
  
# Library comparison

The following graphs show the relation between blur time (ms, y-axis) and thread count (x-axis) for three resolutions: 400×400, 3000×4000, and 10400×10400.

The implementations compared are:

Assembly (AVX) — blue
C++ (no optimization) — red
C++ (/O2) — green

Each column represents the average of 6 runs (excluding the first), with standard deviation indicated.

Benchmarks were performed on an Intel Core i5-12400 (12 threads). Results show:

* Up to 3x speedup from SIMD-based implementation over the optimized C++ version (All resolutions, 1 thread)
* Scaling up to the number of hardware threads
* Diminishing returns beyond 12 threads, likely due to thread management and scheduling overhead

<!-- Graphs of image processing speeds vs thread count for each library-->
<img width="1073" height="648" alt="image" src="https://github.com/user-attachments/assets/94987671-2ca3-4042-bf6d-c1b7b429ea98" />
<img width="1075" height="637" alt="image" src="https://github.com/user-attachments/assets/9fb0e09d-c299-4e3e-857e-2d51facfbbdf" />
<img width="1067" height="640" alt="image" src="https://github.com/user-attachments/assets/a83c3f37-78ac-43da-982f-8c115e893ed8" />

# Building

Open the solution file and run. Post-build scripts copy required DLLs automatically.

# Limitations

* The UI thread is blocked during processing (no async execution)
* Thread creation overhead impacts performance at higher thread counts
* Windows-focused (runs on Linux via WINE)
