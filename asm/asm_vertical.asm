.code
gauss_vertical proc
; Parameters
    p_input	 equ rcx ; *data
    p_output	 equ rdx ; *temp
    width_pixels equ r8 ; width in pixels
    height_pixels equ r9
    
    stride equ r10 ; stride in bytes
    p_kernel equ r11 ; *kernel
    kernel_radius equ r12 ; kernel size (radius)
    start_row equ r13 ; start_row
    end_row equ r14 ; end_row

    ret
        ; Load additional parameters from stack
    ;mov r10, QWORD PTR [rsp+40]
    ;mov r11, QWORD PTR [rsp+48] ;p_kernel
    ;mov r12d,  DWORD PTR [rsp+56] ; kernel_radius
    ;mov r13d, DWORD PTR [rsp+64] ; start_row
    ;mov r14d, DWORD PTR [rsp+72] ; end_row
gauss_vertical endp
end