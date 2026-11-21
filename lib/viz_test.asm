;; lib/viz_test.asm - direct smoke tests for the text canvas.

%include "abi.inc"
%include "libc.inc"
%include "viz.inc"

section .text

global main
main:
    prologue

    vopen   5, 2

    ; Negative coordinates and both right/bottom edges must be clipped.
    mov     rdi, -1
    mov     rsi, 0
    mov     rdx, 'X'
    call    viz_putc

    mov     rdi, 0
    mov     rsi, -1
    mov     rdx, 'X'
    call    viz_putc

    mov     rdi, 5
    mov     rsi, 0
    mov     rdx, 'X'
    call    viz_putc

    mov     rdi, 0
    mov     rsi, 2
    mov     rdx, 'X'
    call    viz_putc

    mov     rdi, 2
    mov     rsi, 1
    mov     rdx, 'A'
    call    viz_putc
    call    viz_flush

    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 'B'
    call    viz_putc
    call    viz_flush

    call    viz_close

    xor     eax, eax
    epilogue
