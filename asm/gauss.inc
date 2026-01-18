    ; Parameters
    p_input	 equ rcx ; *data
    p_output	 equ rdx ; *temp
    width_pixels equ r8 ; width in pixels
    stride equ r9 ; stride in bytes
   
    p_kernel equ r10 ; *kernel
    kernel_radius equ r11 ; kernel size (radius)
    start_row equ r12 ; start_row
    end_row equ r13 ; end_row
    height_pixels equ r14 ; height in pixels, vertical blur only

    ; YMM registers used
    ; Common registers
    orig_bytes equ ymm0 ; original pixel values loaded from p_input

    kernel_value equ ymm5 ; broadcasted kernel value

    ymm_alpha_mask equ ymm5 ;    [0,255,255,255... , 0,255,255,255] mask to blend alpha from original pixels


    temp_bytes equ ymm6 ; temporary storage - often loaded neighboring pixel data or intermediate results
    x_temp_bytes equ xmm6 ; lower 128 bits of temp_bytes

    zero equ ymm7 ; [0, 0, 0, ... 0]
    x_zero equ xmm7 ; lower 128 bits of zero

    ; Widened pixel components (from bytes to words)
    low_bytes equ ymm1
    x_low_bytes equ xmm1
    high_bytes equ ymm2
    x_high_bytes equ xmm2

    ; Accumulators
    low_accum_low equ ymm3
    high_accum_low equ ymm4
    low_accum_high equ ymm8
    high_accum_high equ ymm9

    ; Further widened pixel components (from words to dwords)
    low_bytes_low equ ymm10
    x_low_bytes_low equ xmm10
    low_bytes_high equ ymm1
    x_low_bytes_high equ xmm1
    high_bytes_low equ ymm11
    x_high_bytes_low equ xmm11
    high_bytes_high equ ymm2
    x_high_bytes_high equ xmm2

    ; Procedure variables
   
    pixel_idx equ rbx ; current pixel index in row (in pixels)
    kernel_delta equ r15 ; current kernel index delta from center

    ; Tail processing variables

    ; Accumulators for tail processing

    ; Red component accumulator
    R_acc equ r8
    R_accb equ r8b
    R_accd equ r8d
    ; Green component accumulator
    G_acc equ rdx
    G_accb equ dl
    G_accd equ edx
    ; Blue component accumulator
    B_acc equ r9
    B_accb equ r9b
    B_accd equ r9d
    
    remaining_pixels equ r13 ; total pixels in row left to process in tail
    dest_pixel_ea equ r15 ; effective address for storing pixel in tail processing

.data
alpha_mask_data BYTE \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0     

idx LABEL DWORD
dd 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

.code
    ; -----------------------------------------
    ; Macro to process 8 pixels - expand, multiply by kernel, accumulate
    ; src_reg - source register containing 8 pixels (32 bytes)
    ; INTERNAL USE ONLY
    ; -----------------------------------------


PROCESS_PIXELS MACRO src_reg

    vextracti128 x_low_bytes, src_reg, 0       ; pixels 0–3 -> x_low_bytes
    vextracti128 x_high_bytes, src_reg, 1       ; pixels 4–7 -> x_high_bytes

    vpmovzxbw low_bytes, x_low_bytes             ; widen bytes to words
    vpmovzxbw high_bytes, x_high_bytes

    vextracti128 x_low_bytes_low, low_bytes, 0 ; pixels 0,1 -> x_low_bytes_low
    vextracti128 x_low_bytes_high, low_bytes, 1 ; pixels 2,3 -> x_low_bytes_high
    vextracti128 x_high_bytes_low, high_bytes, 0 ; pixels 4,5 -> x_high_bytes_low
    vextracti128 x_high_bytes_high, high_bytes, 1 ; pixels 6,7 -> x_high_bytes_high

    vpmovzxwd low_bytes_low, x_low_bytes_low ; widen words to dwords
    vpmovzxwd low_bytes_high, x_low_bytes_high

    vpmovzxwd high_bytes_low, x_high_bytes_low
    vpmovzxwd high_bytes_high, x_high_bytes_high

    vpmulld low_bytes_low, low_bytes_low, kernel_value ; multiply by kernel value
    vpmulld low_bytes_high, low_bytes_high, kernel_value

    vpmulld high_bytes_low, high_bytes_low, kernel_value
    vpmulld high_bytes_high, high_bytes_high, kernel_value

    vpaddd low_accum_low, low_accum_low, low_bytes_low ; accumulate
    vpaddd low_accum_high, low_accum_high, low_bytes_high

    vpaddd high_accum_low, high_accum_low, high_bytes_low
    vpaddd high_accum_high, high_accum_high, high_bytes_high
ENDM