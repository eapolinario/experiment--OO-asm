;; 02 - The client's half of class Stack.
;;
;; This file is the whole argument for encapsulation: it uses a Stack without
;; being able to see one. It knows a size (STACK_SIZEOF) and six symbols. It
;; does not know that a Stack contains a `len`, and could not corrupt one if
;; it wanted to - short of writing raw bytes at an offset it would have to
;; guess.

%include "abi.inc"
%include "libc.inc"
%include "stack.inc"

section .rodata
hdr:            db "== 02 | methods, `this`, and a representation you cannot see ==", 0
sec_alloc:      db 10, "The client allocates bytes, not fields:", 10, 0
sec_two:        db 10, "Two instances, one code path:", 10, 0
sec_inv:        db 10, "The invariant lives in one place:", 10, 0

fmt_sizeof:     db "  STACK_SIZEOF published by stack.inc = %ld bytes", 10, 0
fmt_state:      db "  %-4s depth=%ld top=%ld capacity=%ld", 10, 0
fmt_note:       db "  the only difference between those calls was the value in rdi", 10, 0
fmt_filled:     db "  filled s2 to capacity: depth=%ld", 10, 0
fmt_reject_p:   db "  Stack_push on a full stack returned %ld, depth is still %ld", 10, 0
fmt_popping:    db "  popped:", 0
fmt_popped_v:   db " %ld", 0
fmt_reject_o:   db 10, "  Stack_pop on an empty stack returned %ld", 10, 0

lbl_s1:         db "s1:", 0
lbl_s2:         db "s2:", 0

section .text

; ---------------------------------------------------------------------------
; void show(const char *label, Stack *s)
;
; Every fact printed here comes back through the published vocabulary. There
; is no `[rsi + Stack.len]` in this file, and there cannot be.
; ---------------------------------------------------------------------------
show:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; label
    mov     r12, rsi                    ; receiver

    mov     rdi, r12
    call    Stack_capacity
    mov     r8, rax                     ; 4th vararg

    mov     rdi, r12
    call    Stack_peek
    mov     rcx, rax                    ; 3rd vararg

    mov     rdi, r12
    call    Stack_depth
    mov     rdx, rax                    ; 2nd vararg

    mov     rsi, rbx                    ; 1st vararg
    lea     rdi, [fmt_state]
    xor     eax, eax
    ccall   printf

    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue 192
    push    rbx
    push    r12

    ; Frame map (chosen by us, the "compiler"):
    ;   [rbp-80]  ... s1, one Stack
    ;   [rbp-160] ... s2, another Stack
    ;   [rbp-168] ... a long, for Stack_pop's out-parameter
%define S1  (rbp - 80)
%define S2  (rbp - 160)
%define OUT (rbp - 168)

    lea     rdi, [hdr]
    ccall   puts

    lea     rdi, [sec_alloc]
    ccall   printf
    print   fmt_sizeof, STACK_SIZEOF

    ; -- two independent objects --------------------------------------------
    lea     rdi, [sec_two]
    ccall   printf

    lea     rdi, [S1]
    call    Stack_init
    lea     rdi, [S2]
    call    Stack_init

    lea     rdi, [S1]
    mov     rsi, 10
    call    Stack_push
    lea     rdi, [S1]
    mov     rsi, 20
    call    Stack_push
    lea     rdi, [S1]
    mov     rsi, 30
    call    Stack_push

    lea     rdi, [S2]
    mov     rsi, 7
    call    Stack_push

    lea     rdi, [lbl_s1]
    lea     rsi, [S1]
    call    show
    lea     rdi, [lbl_s2]
    lea     rsi, [S2]
    call    show
    lea     rdi, [fmt_note]
    ccall   printf

    ; -- the invariant holds even when the client misbehaves -----------------
    lea     rdi, [sec_inv]
    ccall   printf

    lea     rdi, [S2]                   ; re-running the constructor gives a
    call    Stack_init                  ; fresh object in the same storage

    mov     rbx, 1
.fill:
    cmp     rbx, 8
    ja      .filled
    lea     rdi, [S2]
    mov     rsi, rbx
    call    Stack_push
    inc     rbx
    jmp     .fill
.filled:
    lea     rdi, [S2]
    call    Stack_depth
    print   fmt_filled, rax

    lea     rdi, [S2]                   ; one push too many
    mov     rsi, 99
    call    Stack_push
    mov     rbx, rax                    ; the rejection
    lea     rdi, [S2]
    call    Stack_depth
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_reject_p]
    xor     eax, eax
    ccall   printf

    lea     rdi, [fmt_popping]
    ccall   printf
.drain:
    lea     rdi, [S2]
    lea     rsi, [OUT]
    call    Stack_pop
    test    rax, rax
    jz      .drained
    print   fmt_popped_v, [OUT]
    jmp     .drain
.drained:
    lea     rdi, [S2]                   ; and one pop too many
    lea     rsi, [OUT]
    call    Stack_pop
    print   fmt_reject_o, rax

    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue
