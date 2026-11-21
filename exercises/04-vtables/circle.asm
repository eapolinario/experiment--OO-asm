;; circle.asm - class Circle, one implementation of the Shape interface.
;;
;; Circle knows nothing about Rect and vice versa. They are separate
;; translation units that never see each other's symbols. The only thing they
;; share is the slot numbering in shape.inc - and that turns out to be enough
;; for a single call site in main.asm to drive both.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "shape.inc"
%include "report.inc"
%include "shape_layout.inc"

section .rodata
name_circle:    db "Circle", 0
dims_fmt:       db "r=%ld", 0

section .bss
align 8
dims_buf:       resb 32

section .data
align 8

; The class descriptor: one per class, pointed at by the vtable's slot 0.
Circle_class:
    istruc Class
        at Class.name,      dq name_circle
        at Class.size,      dq Circle_size
        at Class.parent,    dq 0
    iend

; The vtable: one per class, shared by every instance. Ten thousand circles
; cost ten thousand vptrs and exactly one of these.
;
; It lives in .data rather than .rodata because these are absolute addresses
; that the dynamic loader must relocate in a PIE. Real toolchains put it in
; .data.rel.ro and re-protect it after relocation.
Circle_vtable:
    dq Circle_class                     ; VT_CLASS
    dq Circle_area                      ; slot SHAPE_AREA
    dq Circle_perimeter                 ; slot SHAPE_PERIMETER
    dq Circle_show                      ; slot SHAPE_SHOW

section .text

; ---------------------------------------------------------------------------
; Circle *Circle_new(long radius)
;
; The constructor is where an object becomes polymorphic: allocating the bytes
; is not enough, something has to write the vtable address into offset 0.
; ---------------------------------------------------------------------------
global Circle_new
Circle_new:
    prologue
    push    rbx
    push    r12
    mov     r12, rdi                    ; radius
    mov     rdi, Circle_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Circle_vtable]
    mov     [rax + Circle.vptr], rcx    ; <- the moment it becomes a Shape
    mov     [rax + Circle.r], r12
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; long Circle_area(const Circle *this)          ; pi*r^2, in hundredths
Circle_area:
    mov     rax, [rdi + Circle.r]
    imul    rax, rax
    imul    rax, 314
    ret

; long Circle_perimeter(const Circle *this)     ; 2*pi*r, in hundredths
Circle_perimeter:
    mov     rax, [rdi + Circle.r]
    imul    rax, 628
    ret

; void Circle_show(const Circle *this)
;
; Inside the class, calling a sibling method directly is normal: we know the
; dynamic type here, so there is nothing to look up. A C++ compiler
; devirtualizes exactly these calls.
Circle_show:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi

    mov     rcx, [rbx + Circle.r]
    lea     rdx, [dims_fmt]
    mov     rsi, 32
    lea     rdi, [dims_buf]
    xor     eax, eax
    ccall   snprintf

    mov     rdi, rbx
    call    Circle_area
    mov     r12, rax
    mov     rdi, rbx
    call    Circle_perimeter

    mov     rcx, rax                    ; perimeter
    mov     rdx, r12                    ; area
    lea     rsi, [dims_buf]
    lea     rdi, [name_circle]
    call    report_shape

    pop     r12
    pop     rbx
    epilogue
