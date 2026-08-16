;; report.asm - printing helper shared by the shape classes.

%include "abi.inc"
%include "libc.inc"

section .rodata
fmt_line:       db "  %-11s %-8s area=%3ld.%02ld  perimeter=%3ld.%02ld", 10, 0

section .text

; ---------------------------------------------------------------------------
; void report_shape(const char *name, const char *dims,
;                   long area_centi, long perimeter_centi)
;
; Values arrive in hundredths so that the exercises can stay in integers.
; Incidentally this is the first call in the repo with more than six
; arguments: printf gets seven here, so the last one travels on the stack -
; pushed in a 16-byte chunk to keep rsp aligned at the call.
; ---------------------------------------------------------------------------
global report_shape
report_shape:
    prologue 32
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; name
    mov     r12, rsi                    ; dims
    mov     r13, rdx                    ; area
    mov     r14, rcx                    ; perimeter

    mov     rax, r13
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     [rbp - 8], rax              ; area, whole part
    mov     [rbp - 16], rdx             ; area, hundredths

    mov     rax, r14
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx
    mov     [rbp - 24], rax             ; perimeter, whole part
    mov     [rbp - 32], rdx             ; perimeter, hundredths

    sub     rsp, 16                     ; 16, not 8, to preserve alignment
    mov     rax, [rbp - 32]
    mov     [rsp], rax                  ; 7th argument lives on the stack
    mov     r9, [rbp - 24]
    mov     r8, [rbp - 16]
    mov     rcx, [rbp - 8]
    mov     rdx, r12
    mov     rsi, rbx
    lea     rdi, [fmt_line]
    xor     eax, eax
    ccall   printf
    add     rsp, 16

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
