;; rect.asm - class Rect, a second implementation of the same interface.
;;
;; Rect also ships a *second* vtable. Nothing says a class may only have one:
;; the vptr is a per-object field, so two objects of the same class can behave
;; differently while sharing every field and every line of code. Objective-C
;; calls this isa-swizzling and implements key-value observing with it;
;; Smalltalk calls it `become:`.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "shape.inc"
%include "report.inc"

struc Rect
    .vptr:      resq 1
    .w:         resq 1
    .h:         resq 1
endstruc

section .rodata
name_rect:      db "Rect", 0
name_rect_dbg:  db "Rect[debug]", 0
dims_fmt:       db "%ldx%ld", 0
fmt_debug:      db "                (dispatched through %s's vtable: class=%s, instance size=%ld)", 10, 0

section .bss
align 8
dims_buf:       resb 32

section .data
align 8

Rect_class:
    istruc Class
        at Class.name,      dq name_rect
        at Class.size,      dq Rect_size
        at Class.parent,    dq 0
    iend

Rect_vtable:
    dq Rect_class
    dq Rect_area
    dq Rect_perimeter
    dq Rect_show

; Same class, same fields, one different function pointer.
Rect_vtable_debug:
    dq Rect_class
    dq Rect_area
    dq Rect_perimeter
    dq Rect_show_debug

section .text

; ---------------------------------------------------------------------------
; Rect *Rect_new(long w, long h)
; ---------------------------------------------------------------------------
global Rect_new
Rect_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; w
    mov     r12, rsi                    ; h
    mov     rdi, Rect_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Rect_vtable]
    mov     [rax + Rect.vptr], rcx
    mov     [rax + Rect.w], rbx
    mov     [rax + Rect.h], r12
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; ---------------------------------------------------------------------------
; void Rect_enable_debug(Rect *this)
;
; One store. No fields move, no code is patched, no table is edited - the
; object simply starts answering to a different table.
; ---------------------------------------------------------------------------
global Rect_enable_debug
Rect_enable_debug:
    lea     rax, [Rect_vtable_debug]
    mov     [rdi + Rect.vptr], rax
    ret

; long Rect_area(const Rect *this)
Rect_area:
    mov     rax, [rdi + Rect.w]
    imul    rax, [rdi + Rect.h]
    imul    rax, 100
    ret

; long Rect_perimeter(const Rect *this)
Rect_perimeter:
    mov     rax, [rdi + Rect.w]
    add     rax, [rdi + Rect.h]
    imul    rax, 200
    ret

; void Rect_show(const Rect *this)
Rect_show:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    call    rect_format_dims

    mov     rdi, rbx
    call    Rect_area
    mov     r12, rax
    mov     rdi, rbx
    call    Rect_perimeter

    mov     rcx, rax
    mov     rdx, r12
    lea     rsi, [dims_buf]
    lea     rdi, [name_rect]
    call    report_shape

    pop     r12
    pop     rbx
    epilogue

; void Rect_show_debug(const Rect *this)
;
; Reads its own class descriptor back out of the vtable it was reached
; through - a preview of the RTTI in exercise 07.
Rect_show_debug:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    call    rect_format_dims

    mov     rdi, rbx
    call    Rect_area
    mov     r12, rax
    mov     rdi, rbx
    call    Rect_perimeter

    mov     rcx, rax
    mov     rdx, r12
    lea     rsi, [dims_buf]
    lea     rdi, [name_rect_dbg]
    call    report_shape

    class_of rax, rbx                   ; rax = this->vptr->class
    mov     rcx, [rax + Class.size]
    mov     rdx, [rax + Class.name]
    lea     rsi, [name_rect_dbg]
    lea     rdi, [fmt_debug]
    xor     eax, eax
    ccall   printf

    pop     r12
    pop     rbx
    epilogue

; Private: format "WxH" into dims_buf. Receiver in rbx, preserved.
rect_format_dims:
    prologue
    mov     r8, [rbx + Rect.h]
    mov     rcx, [rbx + Rect.w]
    lea     rdx, [dims_fmt]
    mov     rsi, 32
    lea     rdi, [dims_buf]
    xor     eax, eax
    ccall   snprintf
    epilogue
