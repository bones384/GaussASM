
; -----------------------------------------
; File: asm.asm
; Author: Mateusz Kowalec
; Created: January 2, 2026
; Modified: January 18, 2026 
; Description: Holds horizontal Gaussian blur function.
;; -----------------------------------------
    
INCLUDE gauss.inc

.code
   
; -----------------------------------------
; Function: gauss_horizontal
; Author: Mateusz Kowalec
; Created: January 9, 2026
; Modified: January 18, 2026 
; Description: Applies a horizontal Gaussian blur to image data.
; Parameters:
;   RCX - Pointer to the input data (32bpp ARGB format)
;   RDX - Pointer to the output data 
;   R8 - Width of the image in pixels, dword
;   R9 - Stride (number of bytes per row), dword
;   Additional parameters passed on stack:
;  Kernel - Pointer to the Gaussian kernel, word*
;   Kernel Size - Radius of the Gaussian kernel, dword
;   Start Row  - Starting row index , dword
;  End Row  - Ending row index , dword
; Clobbers: rax, rcx, rdx, r8, r9  
; Saves and restores: rbp, rbx, r12-r15, xmm6-xmm12
;
;  output[row,col] = sum_{j=-kernel_size}^{kernel_size} kernel[|j|] * input[row,min(max(col + j, width-1), 0], for row in [start_row, end_row)
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

    sub rsp, 96		 ; space for XMM6 to XMM12 (6 × 16 bytes)


    ; ---- Save non-volatile XMM registers ----
    movdqu xmmword ptr [rsp + 0], xmm6
    movdqu xmmword ptr [rsp + 16], xmm7
    movdqu xmmword ptr [rsp + 32], xmm8
    movdqu xmmword ptr [rsp + 48], xmm9
    movdqu xmmword ptr [rsp + 64], xmm10
    movdqu xmmword ptr [rsp + 80], xmm11

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

    ; For a pixel in the row...
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
    mov rax, kernel_delta
    sub rax, pixel_idx
    vmovd xmm11, rax
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

rightclamp:
    ; Need to load last 8 pixels of row and shift as needed
    mov rax, width_pixels
    sub rax, 8
    vmovdqu temp_bytes, YMMWORD PTR [rsi + rax*4]

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

    vmovdqu temp_bytes, low_accum_high
    vmovdqu low_accum_high, high_accum_low
    vmovdqu high_accum_low, temp_bytes

    vperm2i128 temp_bytes, low_accum_low, low_accum_high, 20h
    vperm2i128 low_accum_high, low_accum_low, low_accum_high, 31h
    vmovdqu low_accum_low,temp_bytes

    vperm2i128 temp_bytes, high_accum_low, high_accum_high, 20h
    vperm2i128 high_accum_high, high_accum_low, high_accum_high, 31h
    vmovdqu high_accum_low,temp_bytes

    vpackusdw low_bytes, low_accum_low, low_accum_high   ; combines low_accum_lo + low_accum_hi
    vpackusdw high_bytes, high_accum_low, high_accum_high ; combines high_accum_lo + high_accum_hi

    vpackuswb temp_bytes, low_bytes, high_bytes    ; combines low_bytes + high_bytes
    ; temp_bytes now has the blurred pixel data, but alpha is wrong (should be untouched)
    ; blend in original alpha values from orig_bytes

    vmovdqa ymm_alpha_mask, YMMWORD PTR [alpha_mask_data] ;  ymm5 = [0,255,255,255... , 0,255,255,255] mask to blend alpha from original pixels

    ; Select alpha from orig_bytes, RGB from temp_bytes
    ; vpblendvb dest, src1, src2, mask
    ; For each byte in mask, if high bit set, select byte from src2, else from src1
    ; mask has 0 for alpha bytes, 255 for R,G,B bytes - select alpha from orig_bytes, R,G,B from temp_bytes
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
push r13



mov remaining_pixels, width_pixels          ; r13 = remaining_pixels
;add remaining_pixels, pixel_idx ; remaining_pixels=end byte idx

; For each remaining pixel...
tail_pixel_loop:
   
    ; Zero register that color components will be loaded into
    xor rcx, rcx
      
   ; Initialize accumulators in r15/rdx/r10 (we can reuse these - will be recalculated at the start of next rowloop or restored prior anyway)
   ;clear accumulators
    xor R_acc, R_acc
    xor G_acc, G_acc
    xor B_acc, B_acc

    ; reset kernel_delta
    xor kernel_delta, kernel_delta

    ; Load kernel[0]
    movzx eax, WORD PTR [p_kernel]  ; kernel fits in 16 bits (2^14 = 16384 max)

    ; process center pixel:
    ; Load pixel component into low 8 bits of rcx
    ; multiply R/G/B of center pixel 
    ; accumulate
    ; repeat for all 3 color components

    movzx ecx, byte ptr [rsi + pixel_idx*4 + 2]   ; R
    imul ecx, eax
    add R_accd, ecx       
    movzx ecx, byte ptr [rsi + pixel_idx*4 + 1]   ; G
    imul ecx, eax
    add G_accd, ecx
    movzx ecx, byte ptr [rsi + pixel_idx*4 + 0]   ; B
    imul ecx, eax
    add B_accd, ecx

        inc kernel_delta

        ; process remaining kernel values
    kernel_loop_scalar:
        ; check if done
        cmp kernel_delta, kernel_radius
        jge kernel_done_scalar

        ;process left neighbors

        movzx eax, WORD PTR [p_kernel + kernel_delta*2]  ; load kernel value

        ;zero color component register

        sub pixel_idx, kernel_delta ; move to left neighbor
        jns left_ok_scalar ; if >=0, no clamp needed

            ;clamp to 0 - load first pixel
            movzx ecx, byte ptr [rsi + 0 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx  
            movzx ecx, byte ptr [rsi + 0 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx  
            movzx ecx, byte ptr [rsi + 0 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx  
            jmp left_done

            ; no clamp needed - load left neighbor pixel
        left_ok_scalar:

            movzx ecx, byte ptr [rsi + pixel_idx*4 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx  
            movzx ecx, byte ptr [rsi + pixel_idx*4 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx  
            movzx ecx, byte ptr [rsi + pixel_idx*4 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx  

        left_done:

        add pixel_idx, kernel_delta; restore pixel_idx

       
         

        ;process right neighbors


        ; calculate right neighbor index
        add pixel_idx, kernel_delta
        cmp pixel_idx, remaining_pixels
        jl right_ok_scalar ; if < remaining_pixels, no clamp needed

            ;clamp to width-1
            dec remaining_pixels ; remaining_pixels = width-1
            ; load last pixel
            movzx ecx, byte ptr [rsi + remaining_pixels*4 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx  
            movzx ecx, byte ptr [rsi + remaining_pixels*4 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx
            movzx ecx, byte ptr [rsi + remaining_pixels*4 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx
            inc remaining_pixels ; restore remaining_pixels
            jmp right_done

            ; no clamp needed - load right neighbor pixel
            right_ok_scalar:
            movzx ecx, byte ptr [rsi + pixel_idx*4 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx
            movzx ecx, byte ptr [rsi + pixel_idx*4 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx
            movzx ecx, byte ptr [rsi + pixel_idx*4 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx
            right_done:

            sub pixel_idx, kernel_delta ; restore pixel_idx

        inc kernel_delta
        jmp kernel_loop_scalar

    kernel_done_scalar:

    ; shift right to normalize (same as AVX2)
    ; arithmetic shift right
    sar R_accd, 14
    sar G_accd, 14
    sar B_accd, 14


      
    mov al, byte ptr [rsi + pixel_idx*4 + 3]
    lea dest_pixel_ea, [rdi + pixel_idx*4]
    ; store pixel (keep alpha)
    mov byte ptr [dest_pixel_ea + 3], al
    mov byte ptr [dest_pixel_ea + 2], R_accb
    mov byte ptr [dest_pixel_ea + 1], G_accb
    mov byte ptr [dest_pixel_ea + 0], B_accb

    ; next pixel
    inc pixel_idx
    cmp pixel_idx, remaining_pixels
    jne tail_pixel_loop

; Restore registers

pop r13
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

    add rsp, 96 ; 7 * 16 bytes

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