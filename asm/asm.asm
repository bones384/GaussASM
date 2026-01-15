.data
alpha_mask_data BYTE \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0, \
  255,255,255,0,  255,255,255,0  ; 32 bytes total

  byte_expand_lo LABEL BYTE
db 0,0,0,0, 4,4,4,4, 8,8,8,8, 12,12,12,12
  byte_expand_hi LABEL BYTE
  db 4,4,4,4, 5,5,5,5, 6,6,6,6, 7,7,7,7

byte_offsets LABEL BYTE
db 0,1,2,3, 0,1,2,3, 0,1,2,3, 0,1,2,3

lane_index_4 LABEL BYTE
dd 0,1,2,3
lane_base_hi LABEL BYTE
dd 4,4,4,4
lane_max_4 LABEL BYTE
dd 3,3,3,3
idx LABEL BYTE
dd 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
.code
gauss_horizontal proc

    ; RCX = data (uint8_t*)
    ; RDX = temp (uint8_t*)
    ; R8D = height
    ; R9D = width

      push rbx
    push rbp
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    p_data	 equ rcx 

    p_temp	 equ rdx
    ;height	 equ r8d
    ;width_bytes equ r9
    width_bytes equ r8
    stride equ r9

    ;xor r10, r10 ; will be used for stride
    ;xor r11, r11 ; will be used for kernel pointer
    ;xor r12, r12 ; will be used for kernel size
    ;xor r13, r13 ; will be used for start_row
    ;xor r14, r14 ; will be used for end_row


    mov r10, QWORD PTR [rsp+40+64] ; stride/// ;r10d ,kernel dqddd
    mov r11d,  DWORD PTR [rsp+48+64] ; kernel (uint16_t*) // k size
    mov r12d, DWORD PTR [rsp+56+64] ; kernel_size// srow
    mov r13d, DWORD PTR [rsp+64+64] ; start_row //endrow
    ;mov r14d, DWORD PTR [rsp+72+64] ; end_row //nothing

    ;stride equ r10
    p_kernel equ r10 ;r11
    kernel_size equ r11
    start_row equ r12
    end_row equ r13

    orig_bytes equ ymm0
    zero equ ymm7
    x_zero equ xmm7
    low_bytes equ ymm1
    x_low_bytes equ xmm1
    low_bytes_high equ ymm1
    x_low_bytes_high equ xmm1
    high_bytes equ ymm2
    x_high_bytes equ xmm2
    high_bytes_high equ ymm2
    x_high_bytes_high equ xmm2
    low_accum_low equ ymm3
    high_accum_low equ ymm4
    kernel_value equ ymm5
    temp_bytes equ ymm6
    x_temp_bytes equ xmm6
    low_accum_high equ ymm8
    high_accum_high equ ymm9

    low_bytes_low equ ymm10
    x_low_bytes_low equ xmm10
    high_bytes_low equ ymm11
    x_high_bytes_low equ xmm11
    temp equ ymm12
    x_temp equ xmm12
    kernel_delta equ r15

     sub rsp, 64          ; space for YMM6 + YMM7 (2 × 32 bytes)
     sub rsp, 64          ; space for YMM8 + YMM9 (2 × 32 bytes)
     sub rsp, 64          ; space for YMM10 + YMM11 (2 × 32 bytes)
     sub rsp, 32

    ; ---- Save YMM registers ----
    vmovdqu ymmword ptr [rsp +  0], ymm6
    vmovdqu ymmword ptr [rsp + 32], ymm7
    vmovdqu ymmword ptr [rsp + 32], ymm8
    vmovdqu ymmword ptr [rsp + 32], ymm9
        vmovdqu ymmword ptr [rsp + 32], ymm10
    vmovdqu ymmword ptr [rsp + 32], ymm11
    vmovdqu ymmword ptr [rsp + 32], ymm12


    vpxor zero, zero, zero ; ymm7 = [0, 0, 0, ... 0]
rowloop:
    cmp start_row, end_row
    jge done

    mov rsi, p_data ;*data -> rsi 
    mov rdi, p_temp ;*temp -> rdi
    mov rax, start_row ; rax -> start_row
    imul rax, stride ; rax -> start_row * stride (offset of current row from *data)

    ;add offset of current row to *data and *temp - now both store pointer of appropriate first value of first row
    add rsi, rax 
    add rdi, rax

    byte_idx equ rbx

    xor byte_idx, byte_idx ; x = 0,  x: current byte index

pixelloop:
    cmp byte_idx, width_bytes ;jmp to nextrow if x > width
    jge nextrow
    ;not past row, check if we can process 8 pixels at once
    mov rax, width_bytes
    sub rax, byte_idx
    cmp rax, 8 
    jl tail



    ; load center pixels for 8 pixels
    vmovdqu orig_bytes, YMMWORD PTR [rsi + byte_idx*4] ;load 256bits from memory (8 pixels * 4 components(bytes) = 32bytes = 256 bits)
    ; ymm0 = [A7, R7, G7, B7, ... A0, R0, G0, B0]
    ; Format32bppArgb 

    ;; TEST
    ;;    vmovdqu YMMWORD PTR [rdi + rbx*4], ymm0
    ;;    inc ebx
    ;;    jmp pixelloop
    ;;

    ;extend each component value from 1 byte to 2 bytes (FF - > 00FF)

    

   ; vpunpcklbw low_bytes, orig_bytes, zero   ; interweave low 16 bytes of each 32 byte half of both registers (pixels 0,1 and 4,5)
    ;vpunpckhbw high_bytes, orig_bytes, zero   ; same but high bytes - pixels 2,3 and 6,7

    vextracti128 x_low_bytes, orig_bytes, 0       ; pixels 0–3
    vextracti128 x_high_bytes, orig_bytes, 1       ; pixels 4–7

    vpmovzxbw low_bytes, x_low_bytes             ; widen
    vpmovzxbw high_bytes, x_high_bytes

    vpxor low_accum_low, low_accum_low, low_accum_low
    vpxor high_accum_low, high_accum_low, high_accum_low
    vpxor low_accum_high, low_accum_high, low_accum_high
    vpxor high_accum_high, high_accum_high, high_accum_high
    ;ymm3=ymm4= [0,0,0,...0]
    xor kernel_delta, kernel_delta ; kernel_delta = 0 
    
    movzx eax, WORD PTR [p_kernel + kernel_delta*2] 
    vmovd xmm5, eax
    vpbroadcastd kernel_value, xmm5


    vextracti128 x_low_bytes_low, low_bytes, 0
    vextracti128 x_low_bytes_high, low_bytes, 1

    vextracti128 x_high_bytes_low, high_bytes, 0
    vextracti128 x_high_bytes_high, high_bytes, 1

    vpmovzxwd low_bytes_low, x_low_bytes_low
    vpmovzxwd low_bytes_high, x_low_bytes_high

    vpmovzxwd high_bytes_low, x_high_bytes_low
    vpmovzxwd high_bytes_high, x_high_bytes_high

    vpmulld low_bytes_low, low_bytes_low, kernel_value
    vpmulld low_bytes_high, low_bytes_high, kernel_value

    vpmulld high_bytes_low, high_bytes_low, kernel_value
    vpmulld high_bytes_high, high_bytes_high, kernel_value

    vpaddd low_accum_low, low_accum_low, low_bytes_low
    vpaddd low_accum_high, low_accum_high, low_bytes_high

    vpaddd high_accum_low, high_accum_low, high_bytes_low
    vpaddd high_accum_high, high_accum_high, high_bytes_high

    inc kernel_delta;
kernelloop:
    cmp kernel_delta, kernel_size
    jge kerneldone
  ; broadcast kernel[i]
    movzx eax, WORD PTR [p_kernel + kernel_delta*2] 
    vmovd xmm5, eax
    vpbroadcastd kernel_value, xmm5

    mov rax, byte_idx
    sub rax, kernel_delta
    js leftclamp
    jmp leftok
leftclamp:
    vmovdqu temp_bytes, YMMWORD PTR [rsi]

    vmovdqa ymm10, YMMWORD PTR idx
    vmovd xmm11, kernel_delta
    vpbroadcastd ymm11, xmm11

    vpsubd ymm10, ymm10, ymm11      ; i - d
    vpmaxsd ymm10, ymm10, zero 
    vpermd temp_bytes, ymm10, temp_bytes  ; clamp to 0
    jmp left
leftok:

    vmovdqu temp_bytes, YMMWORD PTR [rsi + rax*4]

left:

    vextracti128 x_low_bytes, temp_bytes, 0       ; pixels 0–3
    vextracti128 x_high_bytes, temp_bytes, 1       ; pixels 4–7

    vpmovzxbw low_bytes, x_low_bytes             ; widen
    vpmovzxbw high_bytes, x_high_bytes

    vextracti128 x_low_bytes_low, low_bytes, 0
    vextracti128 x_low_bytes_high, low_bytes, 1

    vextracti128 x_high_bytes_low, high_bytes, 0
    vextracti128 x_high_bytes_high, high_bytes, 1


    vpmovzxwd low_bytes_low, x_low_bytes_low
    vpmovzxwd low_bytes_high, x_low_bytes_high

    vpmovzxwd high_bytes_low, x_high_bytes_low
    vpmovzxwd high_bytes_high, x_high_bytes_high

    vpmulld low_bytes_low, low_bytes_low, kernel_value
    vpmulld low_bytes_high, low_bytes_high, kernel_value

    vpmulld high_bytes_low, high_bytes_low, kernel_value
    vpmulld high_bytes_high, high_bytes_high, kernel_value

    vpaddd low_accum_low, low_accum_low, low_bytes_low
    vpaddd low_accum_high, low_accum_high, low_bytes_high

    vpaddd high_accum_low, high_accum_low, high_bytes_low
    vpaddd high_accum_high, high_accum_high, high_bytes_high
  right_start:  
    mov rax, byte_idx
    add rax, kernel_delta
    add rax, 8
    cmp rax, width_bytes
    jle right_ok
    mov rax, width_bytes
    sub rax, 8
    vmovdqu temp_bytes, YMMWORD PTR [rsi + rax*4]

    vmovdqa ymm10, YMMWORD PTR idx
    mov rax, kernel_delta
    add rax, byte_idx
    add rax, 8
    sub rax, width_bytes
    vmovd xmm11, rax
    vpbroadcastd ymm11, xmm11

    vpaddd ymm10, ymm10, ymm11      ; i + d

    ;xor rax,rax
    ;add rax, width_bytes
    ;dec rax
    mov rax, 7
    vmovd xmm11, rax
    vpbroadcastd ymm11, xmm11

    vpminsd ymm10, ymm10, ymm11 
    vpermd temp_bytes, ymm10, temp_bytes  ; clamp to 0
    ;
    jmp right
right_ok:
    sub rax, 8
    vmovdqu temp_bytes, YMMWORD PTR [rsi + rax*4]
    right:
    ;vpunpcklbw low_bytes, temp_bytes, zero
    ;vpunpckhbw high_bytes, temp_bytes, zero

   vextracti128 x_low_bytes, temp_bytes, 0       ; pixels 0–3
    vextracti128 x_high_bytes, temp_bytes, 1       ; pixels 4–7

    vpmovzxbw low_bytes, x_low_bytes             ; widen
    vpmovzxbw high_bytes, x_high_bytes

    vextracti128 x_low_bytes_low, low_bytes, 0
    vextracti128 x_low_bytes_high, low_bytes, 1

    vextracti128 x_high_bytes_low, high_bytes, 0
    vextracti128 x_high_bytes_high, high_bytes, 1

    vpmovzxwd low_bytes_low, x_low_bytes_low
    vpmovzxwd low_bytes_high, x_low_bytes_high

    vpmovzxwd high_bytes_low, x_high_bytes_low
    vpmovzxwd high_bytes_high, x_high_bytes_high

    vpmulld low_bytes_low, low_bytes_low, kernel_value
    vpmulld low_bytes_high, low_bytes_high, kernel_value

    vpmulld high_bytes_low, high_bytes_low, kernel_value
    vpmulld high_bytes_high, high_bytes_high, kernel_value

    vpaddd low_accum_low, low_accum_low, low_bytes_low
    vpaddd low_accum_high, low_accum_high, low_bytes_high

    vpaddd high_accum_low, high_accum_low, high_bytes_low
    vpaddd high_accum_high, high_accum_high, high_bytes_high

    inc kernel_delta
    jmp kernelloop

kerneldone:
    ; normalize Q14 fixed point
    vpsrad low_accum_low, low_accum_low, 14
    vpsrad low_accum_high, low_accum_high, 14
    vpsrad high_accum_low, high_accum_low, 14
    vpsrad high_accum_high, high_accum_high, 14

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

    vpackuswb temp_bytes, low_bytes, high_bytes    
;    vpermd temp_bytes, temp_bytes, 00111001b
    ymm_alpha_mask equ ymm5
    vmovdqa ymm_alpha_mask, YMMWORD PTR [alpha_mask_data]

    ; store 8 pixels
    vpblendvb temp_bytes,orig_bytes, temp_bytes, ymm_alpha_mask
    vmovdqu YMMWORD PTR [rdi + byte_idx*4], temp_bytes

    add byte_idx, 8
    jmp pixelloop

tail:
    
; Save registers we will use
push rcx
push rdx
push r8
push r9
push r12
push r13
push r14

byte_idx_tail equ r12
mov r12, rbx          ; r12 = byte_idx (pixel start offset)
remaining_pixels equ r13
mov r13, rax          ; r13 = remaining_pixels
add r13, byte_idx_tail ; r13=end byte idx
tail_pixel_loop:
    ; byte_idx_tail = byte offset for current pixel (in pixels, multiply by 4 for bytes)
   
    xor rax, rax
    xor rbx, rbx
    xor rcx, rcx
    xor rdx, rdx
    ; Load pixel components ;NOTE: These could be in the wrong order
    mov al, byte ptr [rsi + byte_idx_tail*4 + 3]   ; A

    mov bl, byte ptr [rsi + byte_idx_tail*4 + 2]   ; R

    mov cl, byte ptr [rsi + byte_idx_tail*4 + 1]   ; G

    mov dl, byte ptr [rsi + byte_idx_tail*4 + 0]   ; B

        ; dest_pixel_ea = &dest_pixel

    ; Initialize accumulator in r15/r14/r10 (we can reuse these)

    R_acc equ r15
    R_accb equ r15b
    R_accd equ r15d
    G_acc equ r14
    G_accb equ r14b
    G_accd equ r14d
    B_acc equ r9
    B_accb equ r9b
    B_accd equ r9d

    xor R_acc, R_acc;r                   clear upper bits (for 32-bit multiplies) 
    xor G_acc, G_acc;g
    xor B_acc, B_acc;b
    ; r8 = kernel index
    kernel_index equ r8
    xor kernel_index, kernel_index

            ; Load kernel value
            movzx eax, WORD PTR [p_kernel + kernel_index*2]  ; 16-bit kernel
             ; multiply R/G/B of center pixel
        imul ebx, eax
        imul ecx, eax
        imul edx, eax
        ; accumulate
        add R_accd, ebx       ; R_acc
        add G_accd, ecx       ; G_acc
        add B_accd, edx       ; B_acc
        inc kernel_index
    kernel_loop_scalar:
        cmp kernel_index, kernel_size
        jge kernel_done_scalar

        ;process left neighbors

        xor rax,rax
        xor rbx,rbx
        xor rcx,rcx
        xor rdx,rdx


        sub byte_idx_tail, kernel_index
        jns left_ok_scalar
            ;clamp to 0
            mov al, byte ptr [rsi + 0 + 3]   ; A
            mov bl, byte ptr [rsi + 0 + 2]   ; R
            mov cl, byte ptr [rsi + 0 + 1]   ; G
            mov dl, byte ptr [rsi + 0 + 0]   ; B
            jmp left_scalar
        left_ok_scalar:
            mov al, byte ptr [rsi + byte_idx_tail*4 + 3]   ; A
            mov bl, byte ptr [rsi + byte_idx_tail*4 + 2]   ; R
            mov cl, byte ptr [rsi + byte_idx_tail*4 + 1]   ; G
            mov dl, byte ptr [rsi + byte_idx_tail*4 + 0]   ; B
            left_scalar:

        add byte_idx_tail, kernel_index
        movzx eax, WORD PTR [p_kernel + kernel_index*2]  ; 16-bit kernel

        imul ebx, eax
        imul ecx, eax
        imul edx, eax
        ; accumulate
        add R_accd, ebx       ; R_acc
        add G_accd, ecx       ; G_acc
        add B_accd, edx       ; B_acc

        ;process right neighbors
         xor rax,rax
        xor rbx,rbx
        xor rcx,rcx
        xor rdx,rdx

        add byte_idx_tail, kernel_index
        cmp byte_idx_tail, remaining_pixels
        jl right_ok_scalar
            ;clamp to width-1
            mov rax, remaining_pixels
            dec rax
            mov bl, byte ptr [rsi + rax*4 + 2]   ; R
            mov cl, byte ptr [rsi + rax*4 + 1]   ; G
            mov dl, byte ptr [rsi + rax*4 + 0]   ; B
            jmp right_scalar
            right_ok_scalar:
            mov al, byte ptr [rsi + byte_idx_tail*4 + 3]   ; A
            mov bl, byte ptr [rsi + byte_idx_tail*4 + 2]   ; R
            mov cl, byte ptr [rsi + byte_idx_tail*4 + 1]   ; G
            mov dl, byte ptr [rsi + byte_idx_tail*4 + 0]   ; B
            right_scalar:
            sub byte_idx_tail, kernel_index
            movzx eax, WORD PTR [p_kernel + kernel_index*2]  ; 16-bit kernel
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

    ; shift right to normalize Q14 (same as AVX2)
    ; arithmetic shift right
    sar R_accd, 14
    sar G_accd, 14
    sar B_accd, 14

set_b0:
      dest_pixel_ea equ r8

    lea dest_pixel_ea, [rdi + byte_idx_tail*4]
    ; store pixel (keep alpha)
    mov byte ptr [dest_pixel_ea + 3], 255 ;assuming this is alpha
    mov byte ptr [dest_pixel_ea + 2], R_accb
    mov byte ptr [dest_pixel_ea + 1], G_accb
    mov byte ptr [dest_pixel_ea + 0], B_accb

    ; next pixel
    inc byte_idx_tail
    cmp byte_idx_tail, remaining_pixels
    jne tail_pixel_loop

; Restore registers
pop r14
pop r13
pop r12
pop r9
pop r8
pop rdx
pop rcx    

nextrow:
    inc start_row
    jmp rowloop
done:
    vzeroupper

     ; ---- Restore YMM registers ----
   vmovdqu ymm6, ymmword ptr [rsp + 0]
    vmovdqu ymm7, ymmword ptr [rsp + 32]
    vmovdqu ymm8, ymmword ptr [rsp + 64]
    vmovdqu ymm9, ymmword ptr [rsp + 96]
    vmovdqu ymm10, ymmword ptr [rsp + 128]
    vmovdqu ymm11, ymmword ptr [rsp + 160]
    vmovdqu ymm12, ymmword ptr [rsp + 196]
     add rsp, 64
         add rsp, 64

    add rsp, 64
    add rsp,32
    ; ---- Restore GPRs ----
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbp
    pop rbx


    ret

gauss_horizontal endp

end