;; 04 - Vtables: one call site, several implementations.
;;
;; Read the externs below first. main.asm knows exactly two class-specific
;; symbols - the two constructors - and after that it never mentions Circle or
;; Rect again. It calls methods on objects whose type it cannot name, in code
;; that was assembled before those classes existed. That is polymorphism, and
;; the entire mechanism is: a pointer at offset 0, a table of function
;; pointers, and an indirect call.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "shape.inc"

extern Circle_new                       ; Circle *Circle_new(long r)
extern Rect_new                         ; Rect   *Rect_new(long w, long h)
extern Rect_enable_debug                ; void    Rect_enable_debug(Rect *)

SHAPE_COUNT     equ 4

section .rodata
hdr:            db "== 04 | vtables: one call site, several implementations ==", 0
sec_loop:       db 10, "Four Shape pointers, one loop, four implementations:", 10, 0
sec_sum:        db 10, "The client never learns what it is talking to:", 10, 0
sec_data:       db 10, "Dispatch is data, not identity:", 10, 0
sec_swap:       db 10, "Swapping the vptr swaps the behaviour:", 10, 0

fmt_total:      db "  total area = %ld.%02ld, summed by `mov rax,[rdi]` + `call [rax+8]`", 10, 0
fmt_notag:      db "  the loop never branches on a type tag - there is no type tag", 10, 0
fmt_fact:       db "  %-46s %s", 10, 0
fmt_num:        db "  %-46s %ld", 10, 0
fmt_before:     db "  before Rect_enable_debug:", 10, 0
fmt_after:      db "  after  Rect_enable_debug (one store to offset 0):", 10, 0
fmt_noteswap:   db "  not one field changed; only the pointer at offset 0 did", 10, 0

q_same_class:   db "two Circles share one vtable", 0
q_diff_class:   db "a Circle and a Rect share a vtable", 0
q_per_obj:      db "bytes of dispatch machinery per instance", 0
q_per_class:    db "bytes of method table per class", 0
s_yes:          db "yes", 0
s_no:           db "no", 0

section .bss
align 8
shapes:         resq SHAPE_COUNT

section .text

; const char *yesno(long condition)
yesno:
    lea     rax, [s_no]
    lea     rcx, [s_yes]
    test    rdi, rdi
    cmovnz  rax, rcx
    ret

; void fact(const char *question, long condition)
fact:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rsi
    call    yesno
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_fact]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14

    lea     rdi, [hdr]
    ccall   puts

    ; -- populate the array --------------------------------------------------
    lea     r13, [shapes]

    mov     rdi, 3
    call    Circle_new
    mov     [r13 + 0*8], rax
    mov     r14, rax                    ; keep this Circle for later

    mov     rdi, 4
    mov     rsi, 5
    call    Rect_new
    mov     [r13 + 1*8], rax

    mov     rdi, 1
    call    Circle_new
    mov     [r13 + 2*8], rax

    mov     rdi, 2
    mov     rsi, 2
    call    Rect_new
    mov     [r13 + 3*8], rax

    ; -- the polymorphic loop ------------------------------------------------
    lea     rdi, [sec_loop]
    ccall   printf

    xor     rbx, rbx
.show_loop:
    cmp     rbx, SHAPE_COUNT
    jae     .show_done
    mov     rdi, [r13 + rbx*8]
    vcall   SHAPE_SHOW                  ; mov rax,[rdi] / call [rax+8*3]
    inc     rbx
    jmp     .show_loop
.show_done:

    ; -- the same trick, accumulating a result -------------------------------
    lea     rdi, [sec_sum]
    ccall   printf

    xor     rbx, rbx
    xor     r12, r12
.sum_loop:
    cmp     rbx, SHAPE_COUNT
    jae     .sum_done
    mov     rdi, [r13 + rbx*8]
    vcall   SHAPE_AREA
    add     r12, rax
    inc     rbx
    jmp     .sum_loop
.sum_done:
    mov     rax, r12
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ; rax = whole part, rdx = hundredths
    mov     rsi, rax
    lea     rdi, [fmt_total]
    xor     eax, eax
    ccall   printf
    lea     rdi, [fmt_notag]
    ccall   printf

    ; -- what the indirection costs ------------------------------------------
    lea     rdi, [sec_data]
    ccall   printf

    mov     rax, [r14 + Object.vptr]    ; first Circle's vptr
    mov     rcx, [r13 + 2*8]
    mov     rcx, [rcx + Object.vptr]    ; second Circle's vptr
    cmp     rax, rcx
    sete    sil
    movzx   rsi, sil
    lea     rdi, [q_same_class]
    call    fact

    mov     rax, [r14 + Object.vptr]
    mov     rcx, [r13 + 1*8]
    mov     rcx, [rcx + Object.vptr]
    cmp     rax, rcx
    sete    sil
    movzx   rsi, sil
    lea     rdi, [q_diff_class]
    call    fact

    mov     rdx, 8
    lea     rsi, [q_per_obj]
    lea     rdi, [fmt_num]
    xor     eax, eax
    ccall   printf

    mov     rdx, (SHAPE_SLOTS + 1) * 8
    lea     rsi, [q_per_class]
    lea     rdi, [fmt_num]
    xor     eax, eax
    ccall   printf

    ; -- isa swizzling -------------------------------------------------------
    lea     rdi, [sec_swap]
    ccall   printf

    lea     rdi, [fmt_before]
    ccall   printf
    mov     rdi, [r13 + 1*8]
    vcall   SHAPE_SHOW

    mov     rdi, [r13 + 1*8]
    call    Rect_enable_debug

    lea     rdi, [fmt_after]
    ccall   printf
    mov     rdi, [r13 + 1*8]
    vcall   SHAPE_SHOW                  ; identical instruction, new behaviour
    lea     rdi, [fmt_noteswap]
    ccall   printf

    ; -- tidy up -------------------------------------------------------------
    xor     rbx, rbx
.free_loop:
    cmp     rbx, SHAPE_COUNT
    jae     .free_done
    mov     rdi, [r13 + rbx*8]
    ccall   free
    inc     rbx
    jmp     .free_loop
.free_done:

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue
