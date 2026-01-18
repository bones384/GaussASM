INCLUDE gauss.inc
.code
gauss_vertical proc

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
    mov r14d, DWORD PTR [rsp+72+48] ; height_pixels

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

    ; Load and process top neighbor pixels offset by kernel_delta
topstart:
    ; Check if we need to clamp (target row past top edge)
    mov rax, start_row
    sub rax, kernel_delta
    js topclamp ; if row number - kernel_delta < 0, clamp desired row to 0
    jmp topok ; if >= 0, no clamp needed
    
    ; Need to load from first row 
topclamp:

    ; load matching 8 pixels of row 0
    vmovdqu temp_bytes, YMMWORD PTR [p_input + pixel_idx*4] ; temp_bytes = [ p8, p7, p6, p5, p4, p3, p2, p1]
    jmp top

    ; No clamping needed, just load 8 pixels starting from the same index, but row kernel_delta above
topok:
; need to load [rsi - kernel_delta*stride + pixel_idx*4]
    mov rax, kernel_delta
    imul rax, stride
    neg rax
    lea rax, [rsi + rax]
    vmovdqu temp_bytes, YMMWORD PTR [ rax + pixel_idx*4]

top:
    ; Process the loaded top neighbor pixels
    PROCESS_PIXELS temp_bytes
    
    ; Load and process bottom neighbor pixels from row offset by kernel_delta
  bottomstart:  

    ; Check if we need to clamp (bottom neighbouring row is past bottom edge)

     mov rax, start_row  
     add rax, kernel_delta 
     cmp rax, height_pixels ; if current row + kernel_delta > height_pixels, clamp needed 
     jl bottomok ; < no clamp needed

   

bottomclamp:
 ; Need to load from last row 

    mov rax, height_pixels
    dec rax
    imul rax, stride
    lea rax, [p_input + rax]
    vmovdqu temp_bytes, YMMWORD PTR [rax + pixel_idx*4]
    jmp bottom

    ; No clamping needed, just load 8 pixels from row kernel_delta below
bottomok:
    
    mov rax, kernel_delta
    imul rax, stride
    lea rax, [rsi + rax]
    vmovdqu temp_bytes, YMMWORD PTR [ rax + pixel_idx*4]

    bottom:
    ; Process the loaded bottom neighbor pixels
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

    vpackusdw low_bytes, low_accum_low, low_accum_high   ; combines low_accum_lo + low_accum_hi but messes with order (first lane 0's from both, then lane 1's)
    vpackusdw high_bytes, high_accum_low, high_accum_high ; combines high_accum_lo + high_accum_hi, same as above

    vpackuswb temp_bytes, low_bytes, high_bytes    ; combines low_bytes + high_bytes, still changes order
    ; temp_bytes now has the blurred pixel data, but alpha is wrong (should be untouched)
    ; blend in original alpha values from orig_bytes

    ; ymm5 = [0,255,255,255... , 0,255,255,255] mask to blend alpha from original pixels
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
push rdx
push r8
push r13
push rcx; - p_input pointer (rsp + 16)
push r9; - stride (rsp + 8)
push rdi; - p_output pointer (rsp)


mov remaining_pixels, r8          ; r13 = remaining_pixels
;add remaining_pixels, pixel_idx ; remaining_pixels=end byte idx

; For each remaining pixel...
tail_pixel_loop:
    ; Zero register that color components will be loaded into
    xor rcx, rcx
      
   ; Initialize accumulators in r15/rdx/r10 (we can reuse these - will be recalculated at the start of next rowloop anyway)
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

        ;process top neighbors

        movzx eax, WORD PTR [p_kernel + kernel_delta*2]  ; load kernel value

        ;zero color component register
        ;xor rcx,rcx

        sub start_row, kernel_delta ; move to top neighbor
        jns top_ok_scalar ; if >=0, no clamp needed

            ; load p_input from stack
            mov rdi, [rsp + 16]

            ;clamp to 0 - load first row pixel with same idx
            movzx ecx, byte ptr [rdi + pixel_idx*4 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx  
            movzx ecx, byte ptr [rdi + pixel_idx*4 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx  
            movzx ecx, byte ptr [rdi + pixel_idx*4 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx  
            jmp top_done

            ; no clamp needed - load pixel from row above
        top_ok_scalar:

            ; load stride from stack
            mov rdi, [rsp + 8]
            ; multiply by desired row
            imul rdi, start_row
            add rdi, [rsp + 16] ; p_input + offset to desired row

            movzx ecx, byte ptr [rdi + pixel_idx*4 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx  
            movzx ecx, byte ptr [rdi + pixel_idx*4 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx  
            movzx ecx, byte ptr [rdi + pixel_idx*4 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx  

        top_done:

        add start_row, kernel_delta; restore height_pixels 

       
         

        ;process bottom neighbors

        xor rcx,rcx


        ; calculate bottom neighbor row
        add start_row, kernel_delta
        cmp start_row, height_pixels
        jl bottom_ok_scalar ; if < height_pixels, no clamp needed

            ;clamp to height-1
            dec height_pixels
            dec height_pixels
             ; load stride from stack
            mov rdi, [rsp + 8]
            ; multiply by desired row
            imul rdi, height_pixels
            add rdi, [rsp + 16] ; p_input + offset to desired row
            inc height_pixels
            inc height_pixels
            movzx ecx, byte ptr [rdi + remaining_pixels*4 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx  
            movzx ecx, byte ptr [rdi + remaining_pixels*4 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx
            movzx ecx, byte ptr [rdi + remaining_pixels*4 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx
            jmp bottom_done

            ; no clamp needed - load pixel from rows below
            bottom_ok_scalar:

             ; load stride from stack
            mov rdi, [rsp + 8]
            ; multiply by desired row
            imul rdi, start_row
            add rdi, [rsp + 16] ; p_input + offset to desired row

                movzx ecx, byte ptr [rdi + pixel_idx*4 + 2]   ; R
            imul ecx, eax
            add R_accd, ecx
            movzx ecx, byte ptr [rdi + pixel_idx*4 + 1]   ; G
            imul ecx, eax
            add G_accd, ecx
            movzx ecx, byte ptr [rdi + pixel_idx*4 + 0]   ; B
            imul ecx, eax
            add B_accd, ecx
            bottom_done:

            sub start_row, kernel_delta ; restore start_row

        inc kernel_delta
        jmp kernel_loop_scalar

    kernel_done_scalar:

    ; shift right to normalize (same as AVX2)
    ; arithmetic shift right
    sar R_accd, 14
    sar G_accd, 14
    sar B_accd, 14


      
    mov al, byte ptr [rsi + pixel_idx*4 + 3]
    pop rdi
    lea dest_pixel_ea, [rdi + pixel_idx*4]
    push rdi
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

pop rdi
pop r9
pop rcx
pop r13
pop r8
pop rdx

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
gauss_vertical endp
end