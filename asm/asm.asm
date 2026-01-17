.data
alpha_mask_data BYTE \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0     

idx LABEL DWORD
dd 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
.code

    ; Parameters
    p_input	 equ rcx ; *data
    p_output	 equ rdx ; *temp
    width_pixels equ r8 ; width in pixels
    stride equ r9 ; stride in bytes
   
    p_kernel equ r10 ; *kernel
    kernel_radius equ r11 ; kernel size (radius)
    start_row equ r12 ; start_row
    end_row equ r13 ; end_row

    ; YMM registers used
    ; Common registers
    orig_bytes equ ymm0 ; original pixel values loaded from p_input

    kernel_value equ ymm5 ; broadcasted kernel value

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
    R_acc equ r15
    R_accb equ r15b
    R_accd equ r15d
    ; Green component accumulator
    G_acc equ r14
    G_accb equ r14b
    G_accd equ r14d
    ; Blue component accumulator
    B_acc equ r9
    B_accb equ r9b
    B_accd equ r9d
    
    kernel_index equ r8 ; same as kernel_delta but for tail processing
    remaining_pixels equ r13 ; total pixels in row left to process in tail
    pixel_idx_tail equ r12 ; current pixel index in tail processing
    dest_pixel_ea equ r8 ; effective address for storing pixel in tail processing

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
; -----------------------------------------
; Function: gauss_horizontal
; Author: ----
; Created: January 9, 2026
; Modified: January 17, 2026 
; Description: Applies a horizontal Gaussian blur to image data.
; Parameters:
;   RCX - Pointer to the image data 
;   RDX - Pointer to temporary buffer
;   R8 - Width of the image in pixels
;   R9 - Stride (number of bytes per row)
;   Additional parameters passed on stack:
;  Kernel - Pointer to the Gaussian kernel
;   Kernel Size - Radius of the Gaussian kernel 
;   Start Row  - Starting row index 
;  End Row  - Ending row index 
; Clobbers: rax, rcx, rdx, r8, r9  
; Saves and restores: rbp, rbx, r12-r15, xmm6-xmm12
;; -----------------------------------------
gauss_horizontal proc

    ; ---- Save callee-saved GPRs ----
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    ; Saved 6 registers - rsp decreases by 48 bytes

    ; Load additional parameters from stack
    mov r10, QWORD PTR [rsp+40+48] ;p_kernel
    mov r11d,  DWORD PTR [rsp+48+48] ; kernel_radius
    mov r12d, DWORD PTR [rsp+56+48] ; start_row
    mov r13d, DWORD PTR [rsp+64+48] ; end_row

    sub rsp, 112		 ; space for XMM6 to XMM12 (7 × 16 bytes)


    ; ---- Save non-volatile XMM registers ----
    movdqu xmmword ptr [rsp + 0], xmm6
    movdqu xmmword ptr [rsp + 16], xmm7
    movdqu xmmword ptr [rsp + 32], xmm8
    movdqu xmmword ptr [rsp + 48], xmm9
    movdqu xmmword ptr [rsp + 64], xmm10
    movdqu xmmword ptr [rsp + 80], xmm11
    movdqu xmmword ptr [rsp + 96], xmm12

    ; Initialize zero register
    vpxor zero, zero, zero ; ymm7 = [0, 0, 0, ... 0]

    ; For each row from start_row to end_row...
rowloop:
    cmp start_row, end_row ; finish procedure if start_row >= end_row
    jge done

    mov rsi, p_input ;*data -> rsi 
    mov rdi, p_output ;*temp -> rdi
    mov rax, start_row ; rax -> start_row
    imul rax, stride ; rax -> start_row * stride (offset of current row from *data)

    ;add offset of current row to *data and *temp - now both store pointer of appropriate first value of first row
    add rsi, rax 
    add rdi, rax

    xor pixel_idx, pixel_idx ; pixel_idx = 0 (start of row)

    ; For each pixel in the row...
pixelloop:
    cmp pixel_idx, width_pixels ; If pixel_idx >= width_pixels, done with row entirely
    jge nextrow 
    ; Not finished row yet, check if enough pixels remain for full 8-pixel processing
    mov rax, width_pixels
    sub rax, pixel_idx
    cmp rax, 8 
    jl tail ; if less than 8 pixels remain, go to tail processing

    ; load center pixel data for 8 pixels
    vmovdqu orig_bytes, YMMWORD PTR [rsi + pixel_idx*4] ;load 256bits from memory (8 pixels * 4 components(bytes) = 32bytes = 256 bits)
    ; ymm0 = [A7, R7, G7, B7, ... A0, R0, G0, B0]
    ; Format32bppArgb 

    ; Zero accumulators
    vpxor low_accum_low, low_accum_low, low_accum_low
    vpxor high_accum_low, high_accum_low, high_accum_low
    vpxor low_accum_high, low_accum_high, low_accum_high
    vpxor high_accum_high, high_accum_high, high_accum_high
    ;ymm3=ymm4= [0,0,0,...0]

    xor kernel_delta, kernel_delta ; kernel_delta = 0 
    
    ; load kernel[0], broadcast
    movzx eax, WORD PTR [p_kernel] ; eax = kernel[0] 
    vmovd xmm5, eax ; move to xmm5
    vpbroadcastd kernel_value, xmm5 ; broadcast to kernel_value as dwords

    ; multiply center pixels by kernel[0] and accumulate
    PROCESS_PIXELS orig_bytes
  
    inc kernel_delta;

    ; For each kernel index from 1 to kernel_radius...
kernelloop:

    ; Check if we've processed the entire kernel
    cmp kernel_delta, kernel_radius
    jge kerneldone

  ; broadcast kernel[i] to kernel_value as dwords
    movzx eax, WORD PTR [p_kernel + kernel_delta*2] 
    vmovd xmm5, eax
    vpbroadcastd kernel_value, xmm5

    ; Load and process left neighbor pixels offset by kernel_delta
leftstart:
    ; Check if we need to clamp (left neighbour of first pixel is past left edge)
    mov rax, pixel_idx
    sub rax, kernel_delta
    js leftclamp ; if pixel_idx - kernel_delta < 0, clamp to 0, shift as needed
    jmp leftok ; if pixel_idx - kernel_delta >= 0, no clamp needed

    ; Need to load first 8 pixels of row and shift as needed
leftclamp:

    ; ymm10 and ymm11 are unused at this point - use for calculations    

    ; load first 8 pixels of row
    vmovdqu temp_bytes, YMMWORD PTR [rsi] ; temp_bytes = [ p8, p7, p6, p5, p4, p3, p2, p1] 8 pixels, 4 bytes each, so a pixel is a dword

    ; calculate shift amount
    ; load idx - every dword is its own index 
    vmovdqa ymm10, YMMWORD PTR idx ; ymm10 = [15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0]

    ; broadcast kernel_delta to all dwords in ymm11
    vmovd xmm11, kernel_delta
    vpbroadcastd ymm11, xmm11 ; ymm11 = [d,d,d,d,d,d,d,d,d,d,d,d,d,d,d,d]

    ; subtract kernel_delta from each index, clamp to 0
    vpsubd ymm10, ymm10, ymm11      
    vpmaxsd ymm10, ymm10, zero ; ymm10 = [max(0, i - d), ...]
    
    ; For example, if kernel_delta=3, ymm10 = [12,11,10,9,8,7,6,5,4,3,2,1,0,0,0,0]
    ; 1st, 2nd, 3rd pixels left neighbour is the 1st pixel, as their true left neighbour is out of bounds

    ; permute temp_bytes to get correct pixels
    ; an entire pixel's worth of data is 4 bytes (a dword), we use ymm10 to rearrange the first 8 pixels' data
    ; copying the first pixels value to those out-of-bounds left neighbours, and the real neighbours for the rest
    vpermd temp_bytes, ymm10, temp_bytes  

    jmp left

    ; No clamping needed, just load 8 pixels starting from  (pixel_idx - kernel_delta)
leftok:
    vmovdqu temp_bytes, YMMWORD PTR [rsi + rax*4]

left:
    ; Process the loaded left neighbor pixels
    PROCESS_PIXELS temp_bytes
  
    ; Load and process right neighbor pixels offset by kernel_delta
  rightstart:  

    ; Check if we need to clamp (right neighbour of last pixel is past right edge)
    mov rax, pixel_idx ; rax = pixel_idx
    add rax, kernel_delta ; rax = pixel_idx + kernel_delta
    add rax, 8 ; rax = pixel_idx + kernel_delta + 8 (8 pixels being processed)
    cmp rax, width_pixels ; if pixel_idx + kernel_delta + 8 >= width_pixels, clamp needed (right neighbour of last pixel is past right edge)
    jle right_ok ; if pixel_idx + kernel_delta + 8 < width_pixels, no clamp needed

    ; Need to load last 8 pixels of row and shift as needed
    mov rax, width_pixels
    sub rax, 8
    vmovdqu temp_bytes, YMMWORD PTR [rsi + rax*4]

rightclamp:

    ; Load idx - every dword is its own index
    vmovdqa ymm10, YMMWORD PTR idx

    ; Calculate shift amount 
    mov rax, kernel_delta
    add rax, pixel_idx
    add rax, 8
    sub rax, width_pixels
    
    ; Broadcast shift amount to ymm11
    vmovd xmm11, rax
    vpbroadcastd ymm11, xmm11

    ; Add shift amount to each index
    vpaddd ymm10, ymm10, ymm11      

    ; Broadcast max index (7) to ymm11
    mov rax, 7
    vmovd xmm11, rax
    vpbroadcastd ymm11, xmm11

    ; Clamp to 7
    vpminsd ymm10, ymm10, ymm11

    ; Permute to get correct pixels
    vpermd temp_bytes, ymm10, temp_bytes  
    
    jmp right

    ; No clamping needed, just load 8 pixels starting from (pixel_idx + kernel_delta)
right_ok:
    sub rax, 8 ; adjust back to pixel_idx + kernel_delta
    vmovdqu temp_bytes, YMMWORD PTR [rsi + rax*4] ; load 8 pixels

    right:
    ; Process the loaded right neighbor pixels
    PROCESS_PIXELS temp_bytes

    inc kernel_delta
    jmp kernelloop

    ; All kernel values processed
kerneldone:
    ; Now normalize accumulators by shifting right by 14
    ; (divide by 16384 - result is summed multiplication result of each byte as a byte if as if kernel_values were 0.0-1.0)
    vpsrad low_accum_low, low_accum_low, 14
    vpsrad low_accum_high, low_accum_high, 14
    vpsrad high_accum_low, high_accum_low, 14
    vpsrad high_accum_high, high_accum_high, 14

    ; Rearrange accumulators to prepare for packing back to bytes in correct order

    ; I could just use vperm2i128 directly into the final positions, but i don't want to change labels and risk mistakes
    vmovaps temp_bytes, low_accum_high
    vmovaps low_accum_high, high_accum_low
    vmovaps high_accum_low, temp_bytes

    vperm2i128 temp_bytes, low_accum_low, low_accum_high, 20h
    vperm2i128 low_accum_high, low_accum_low, low_accum_high, 31h
    vmovaps low_accum_low,temp_bytes

    vperm2i128 temp_bytes, high_accum_low, high_accum_high, 20h
    vperm2i128 high_accum_high, high_accum_low, high_accum_high, 31h
    vmovaps high_accum_low,temp_bytes

    vpackusdw low_bytes, low_accum_low, low_accum_high   ; combines low_accum_lo + low_accum_hi
    vpackusdw high_bytes, high_accum_low, high_accum_high ; combines high_accum_lo + high_accum_hi

    vpackuswb temp_bytes, low_bytes, high_bytes    ; combines low_bytes + high_bytes
    ; temp_bytes now has the blurred pixel data, but alpha is wrong (should be untouched)
    ; blend in original alpha values from orig_bytes

    ymm_alpha_mask equ ymm5 ; ymm5 = [0,255,255,255... , 0,255,255,255] mask to blend alpha from original pixels
    vmovdqa ymm_alpha_mask, YMMWORD PTR [alpha_mask_data]

    ; Select alpha from orig_bytes, RGB from temp_bytes
    vpblendvb temp_bytes,orig_bytes, temp_bytes, ymm_alpha_mask
    ; Store resulting 8 pixels
    vmovdqu YMMWORD PTR [rdi + pixel_idx*4], temp_bytes

    ; Finish processing 8 pixels
    add pixel_idx, 8
    jmp pixelloop

    ; Process remaining pixels in the row one at a time
tail:
    
; Save registers we will use
push rcx
push rdx
push r8
push r9
push r12
push r13
push r14


mov pixel_idx_tail, rbx          ; r12 = pixel_idx (pixel start offset)
mov remaining_pixels, rax          ; r13 = remaining_pixels
add remaining_pixels, pixel_idx_tail ; r13=end byte idx

; For each remaining pixel...
tail_pixel_loop:
    ; pixel_idx_tail = byte offset for current pixel (in pixels, multiply by 4 for bytes)
   
    ; Zero registers that color components will be loaded into
    xor rax, rax
    xor rbx, rbx
    xor rcx, rcx
    xor rdx, rdx

    ; Load pixel components into low 8 bits of rbx,rcx,rdx

    mov bl, byte ptr [rsi + pixel_idx_tail*4 + 2]   ; R

    mov cl, byte ptr [rsi + pixel_idx_tail*4 + 1]   ; G

    mov dl, byte ptr [rsi + pixel_idx_tail*4 + 0]   ; B

    ; Initialize accumulator in r15/r14/r10 (we can reuse these - will be recalculated at the start of next rowloop anyway)

    ;clear accumulators
    xor R_acc, R_acc
    xor G_acc, G_acc
    xor B_acc, B_acc

    ; process center pixel
    ; reset kernel_index
    xor kernel_index, kernel_index

    ; Load kernel[0]
    movzx eax, WORD PTR [p_kernel]  ; kernel fits in 16 bits (2^14 = 16384 max)
             ; multiply R/G/B of center pixel 
        imul ebx, eax
        imul ecx, eax
        imul edx, eax
        ; accumulate
        add R_accd, ebx       ; R_acc
        add G_accd, ecx       ; G_acc
        add B_accd, edx       ; B_acc
        inc kernel_index

        ; process remaining kernel values
    kernel_loop_scalar:
        ; check if done
        cmp kernel_index, kernel_radius
        jge kernel_done_scalar

        ;process left neighbors

        ;zero color component registers
        xor rbx,rbx
        xor rcx,rcx
        xor rdx,rdx

        sub pixel_idx_tail, kernel_index ; move to left neighbor
        jns left_ok_scalar ; if >=0, no clamp needed

            ;clamp to 0 - load first pixel
            mov bl, byte ptr [rsi + 0 + 2]   ; R
            mov cl, byte ptr [rsi + 0 + 1]   ; G
            mov dl, byte ptr [rsi + 0 + 0]   ; B
            jmp left_scalar

            ; no clamp needed - load left neighbor pixel
        left_ok_scalar:
            mov bl, byte ptr [rsi + pixel_idx_tail*4 + 2]   ; R
            mov cl, byte ptr [rsi + pixel_idx_tail*4 + 1]   ; G
            mov dl, byte ptr [rsi + pixel_idx_tail*4 + 0]   ; B

            left_scalar:

        add pixel_idx_tail, kernel_index; ; restore pixel_idx_tail

        movzx eax, WORD PTR [p_kernel + kernel_index*2]  ; load kernel value
         ; multiply R/G/B of left neighbor pixel

        imul ebx, eax
        imul ecx, eax
        imul edx, eax
        ; accumulate
        add R_accd, ebx       ; R_acc
        add G_accd, ecx       ; G_acc
        add B_accd, edx       ; B_acc

        ;process right neighbors
        xor rbx,rbx
        xor rcx,rcx
        xor rdx,rdx

        ; calculate right neighbor index
        add pixel_idx_tail, kernel_index
        cmp pixel_idx_tail, remaining_pixels
        jl right_ok_scalar ; if < remaining_pixels, no clamp needed

            ;clamp to width-1
            mov rax, remaining_pixels
            dec rax ; rax = width-1
            ; load last pixel
            mov bl, byte ptr [rsi + rax*4 + 2]   ; R
            mov cl, byte ptr [rsi + rax*4 + 1]   ; G
            mov dl, byte ptr [rsi + rax*4 + 0]   ; B
            jmp right_scalar

            ; no clamp needed - load right neighbor pixel
            right_ok_scalar:
            mov bl, byte ptr [rsi + pixel_idx_tail*4 + 2]   ; R
            mov cl, byte ptr [rsi + pixel_idx_tail*4 + 1]   ; G
            mov dl, byte ptr [rsi + pixel_idx_tail*4 + 0]   ; B
            right_scalar:

            sub pixel_idx_tail, kernel_index ; restore pixel_idx_tail

            movzx eax, WORD PTR [p_kernel + kernel_index*2]  ; load kernel value again (checking clamp clobbered it)
             ; multiply R/G/B of right neighbor pixel
            imul ebx, eax
            imul ecx, eax
            imul edx, eax
            ; accumulate
            add R_accd, ebx       ; R_acc
            add G_accd, ecx       ; G_acc
            add B_accd, edx       ; B_acc

        inc kernel_index
        jmp kernel_loop_scalar

    kernel_done_scalar:

    ; shift right to normalize (same as AVX2)
    ; arithmetic shift right
    sar R_accd, 14
    sar G_accd, 14
    sar B_accd, 14


      
    mov al, byte ptr [rsi + pixel_idx_tail*4 + 3]
    lea dest_pixel_ea, [rdi + pixel_idx_tail*4]
    ; store pixel (keep alpha)
    mov byte ptr [dest_pixel_ea + 3], al
    mov byte ptr [dest_pixel_ea + 2], R_accb
    mov byte ptr [dest_pixel_ea + 1], G_accb
    mov byte ptr [dest_pixel_ea + 0], B_accb

    ; next pixel
    inc pixel_idx_tail
    cmp pixel_idx_tail, remaining_pixels
    jne tail_pixel_loop

; Restore registers
pop r14
pop r13
pop r12
pop r9
pop r8
pop rdx
pop rcx    

; Row finished - move to next row
nextrow:
    inc start_row
    jmp rowloop

; Blur finished
done:
    vzeroupper ; clear upper parts of YMM registers to avoid AVX-SSE transition penalty

    ; ---- Restore XMM registers ----
    movdqu xmm6, xmmword ptr [rsp + 0]
    movdqu xmm7, xmmword ptr [rsp + 16]
    movdqu xmm8, xmmword ptr [rsp + 32]
    movdqu xmm9, xmmword ptr [rsp + 48]
    movdqu xmm10, xmmword ptr [rsp + 64]
    movdqu xmm11, xmmword ptr [rsp + 80]
    movdqu xmm12, xmmword ptr [rsp + 96]

    add rsp, 112 ; 7 * 16 bytes

    ; ---- Restore callee-saved GPRs ----
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx

    ret

gauss_horizontal endp

end