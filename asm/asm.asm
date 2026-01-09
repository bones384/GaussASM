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

    



    xor r10, r10 ; will be used for stride
    xor r11, r11 ; will be used for kernel pointer
    xor r12, r12 ; will be used for kernel size
    xor r13, r13 ; will be used for start_row
    xor r14, r14 ; will be used for end_row


    mov r10d, DWORD PTR [rsp+40+64] ; stride
    mov r11,  QWORD PTR [rsp+48+64] ; kernel (uint16_t*)
    mov r12d, DWORD PTR [rsp+56+64] ; kernel_size
    mov r13d, DWORD PTR [rsp+64+64] ; start_row
    mov r14d, DWORD PTR [rsp+72+64] ; end_row

     sub rsp, 64          ; space for YMM6 + YMM7 (2 × 32 bytes)

    ; ---- Save YMM registers ----
    vmovdqu ymmword ptr [rsp +  0], ymm6
    vmovdqu ymmword ptr [rsp + 32], ymm7

rowloop:
    cmp r13d, r14d
    jge done

    mov rsi, rcx ;*data -> rsi 
    mov rdi, rdx ;*temp -> rsi
    mov rax, r13 ; rax -> start_row
    imul rax, r10 ; rax -> start_row * stride (offset of current row from *data)
    ; these values were loaded into lower 32bits of 64bit registers, but the other bits get set to 0 so we can use 64bit math safely
    ;add offset of current row to *data and *temp - now both store pointer of appropriate first value of first row

    add rsi, rax 
    add rdi, rax

    xor ebx, ebx ; x = 0,  x: current byte index

pixelloop:
    cmp ebx, r9d ;jmp to nextrow if x > width
    jge nextrow

    ; load center pixels for 8 pixels
    vmovdqu ymm0, YMMWORD PTR [rsi + rbx*4] ;load 256bits from memory (8 pixels * 4 components(bytes) = 32bytes = 256 bits)
    ; ymm0 = [A7, R7, G7, B7, ... A0, R0, G0, B0]
    ; Format32bppArgb 


    ;extend each component value from 1 byte to 2 bytes (FF - > 00FF)
    vpxor ymm7, ymm7, ymm7 ; ymm7 = [0, 0, 0, ... 0]

    vpunpcklbw ymm1, ymm0, ymm7   ; interweave low 16 bytes of each 32 byte half of both registers (pixels 0,1 and 4,5)
    vpunpckhbw ymm2, ymm0, ymm7   ; same but high bytes - pixels 2,3 and 6,7

    vpxor ymm3, ymm3, ymm3
    vpxor ymm4, ymm4, ymm4
    ;ymm3=ymm4= [0,0,0,...0]
    xor r15d, r15d ; r15d = 0 ; kernel index (delta)
    
    vpbroadcastw ymm5, WORD PTR [r11 + r15*2]

    vpmullw ymm1, ymm1, ymm5
    vpmullw ymm2, ymm2, ymm5
    ;dont need to add, could move?
    vpaddd ymm3, ymm3, ymm1
    vpaddd ymm4, ymm4, ymm2
    inc r15;
kernelloop:
    cmp r15d, r12d
    jge kerneldone
  ; broadcast kernel[l]
    vpbroadcastw ymm5, WORD PTR [r11 + r15*2]

    mov eax, ebx
    sub eax, r15d
    js leftclamp
    jmp leftok
leftclamp:
    xor eax, eax
leftok:
    vmovdqu ymm0, YMMWORD PTR [rsi + rax*4]

    vpunpcklbw ymm1, ymm0, ymm7
    vpunpckhbw ymm2, ymm0, ymm7

    vpmullw ymm1, ymm1, ymm5
    vpmullw ymm2, ymm2, ymm5

    vpaddd ymm3, ymm3, ymm1
    vpaddd ymm4, ymm4, ymm2

    mov eax, ebx
    add eax, r15d
    cmp eax, r9d
    jl right_ok
    mov eax, r9d
    dec eax
right_ok:

    vmovdqu ymm0, YMMWORD PTR [rsi + rax*4]
    vpunpcklbw ymm1, ymm0, ymm7
    vpunpckhbw ymm2, ymm0, ymm7

    vpmullw ymm1, ymm1, ymm5
    vpmullw ymm2, ymm2, ymm5

    vpaddd ymm3, ymm3, ymm1
    vpaddd ymm4, ymm4, ymm2

    inc r15d
    jmp kernelloop

kerneldone:
    ; normalize Q14 fixed point
    vpsrad ymm3, ymm3, 14
    vpsrad ymm4, ymm4, 14

    ; pack back to bytes
    vpackusdw ymm3, ymm3, ymm4
    vpackuswb ymm3, ymm3, ymm7

    ; store 8 pixels
    vmovdqu YMMWORD PTR [rdi + rbx*4], ymm3

    add ebx, 8
    jmp pixelloop

nextrow:
    inc r13d
    jmp rowloop
done:
    vzeroupper

     ; ---- Restore YMM registers ----
   vmovdqu ymm6, ymmword ptr [rsp + 0]
    vmovdqu ymm7, ymmword ptr [rsp + 32]

    add rsp, 64

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