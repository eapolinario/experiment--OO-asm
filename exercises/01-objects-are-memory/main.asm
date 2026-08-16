;; 01 - An object is just a block of memory.
;;
;; No vtables here, no polymorphism, nothing dynamic. Just the observation
;; that every "object" you have ever used is a base address plus a set of
;; agreed-upon byte offsets, and that a struct declaration is a naming
;; discipline layered on top of pointer arithmetic.

%include "abi.inc"
%include "libc.inc"

; ---------------------------------------------------------------------------
; The types.
;
; NASM's `struc` emits no code and no data. It defines absolute symbols:
;   Point.x = 0, Point.y = 8, Point_size = 16
; That is *all* a C struct declaration is as well. The compiler never stores a
; "Point"; it stores the knowledge that x lives 0 bytes into the object.
; ---------------------------------------------------------------------------
struc Point
    .x:         resq 1
    .y:         resq 1
endstruc

; Field order is a layout decision with a cost. `struc` never inserts padding,
; so declaring small fields first leaves the qwords straddling 8-byte
; boundaries. x86 tolerates unaligned loads (with a penalty); other machines
; fault. A C compiler silently pads for you - in assembly, you are the one
; doing the padding.
struc SpriteNaive
    .alive:     resb 1
    .hp:        resq 1
    .kind:      resb 1
    .pos:       resq 2
endstruc

struc Sprite
    .hp:        resq 1
    .pos:       resq 2
    .alive:     resb 1
    .kind:      resb 1
    .pad:       resb 6              ; round up so arrays stay aligned too
endstruc

; ---------------------------------------------------------------------------
section .rodata

hdr:            db "== 01 | an object is just a block of memory ==", 0
sec_layout:     db 10, "A type is a set of offsets:", 10, 0
sec_storage:    db 10, "One type, three storage classes:", 10, 0
sec_methods:    db 10, "A method is a function with an explicit `this` in rdi:", 10, 0
sec_array:      db 10, "An array of objects is contiguous; the loop just adds the size:", 10, 0
sec_padding:    db 10, "You pad by hand, or you pay for it:", 10, 0

fmt_size:       db "  sizeof(Point)      = %ld", 10, 0
fmt_off_x:      db "  offsetof(Point, x) = %ld", 10, 0
fmt_off_y:      db "  offsetof(Point, y) = %ld", 10, 0
fmt_point:      db "  %-9s (%ld, %ld)", 10, 0
fmt_elem:       db "  particles[%ld] at byte offset %-3ld -> (%ld, %ld)", 10, 0
fmt_sum:        db "  sum of x = %ld", 10, 0
fmt_layout:     db "  %-12s size=%-3ld hp at +%-2ld pos at +%-2ld  %s", 10, 0
verdict_ok:     db "every field naturally aligned", 0
verdict_bad:    db "misaligned fields: the CPU pays on every access", 0

lbl_static:     db "static", 0
lbl_stack:      db "stack", 0
lbl_bss:        db "bss", 0
lbl_before:     db "before", 0
lbl_after:      db "after", 0
lbl_naive:      db "SpriteNaive", 0
lbl_sprite:     db "Sprite", 0

; ---------------------------------------------------------------------------
section .data
align 8

; A statically allocated instance. `istruc`/`at`/`iend` fill in the fields by
; name; the linker sees nothing but 16 bytes of initialised data.
origin:
    istruc Point
        at Point.x, dq 5
        at Point.y, dq 7
    iend

; ---------------------------------------------------------------------------
section .bss
align 16

; Three objects, back to back. No headers, no per-object bookkeeping: the
; array *is* the objects.
PARTICLE_COUNT  equ 3
particles:      resb PARTICLE_COUNT * Point_size

; ---------------------------------------------------------------------------
section .text

; void point_init(Point *this, long x, long y)
;
; A leaf function that calls nothing needs no frame at all: the entire body is
; two stores through the receiver.
global point_init
point_init:
    mov     [rdi + Point.x], rsi
    mov     [rdi + Point.y], rdx
    ret

; void point_translate(Point *this, long dx, long dy)
global point_translate
point_translate:
    add     [rdi + Point.x], rsi
    add     [rdi + Point.y], rdx
    ret

; void point_show(const Point *this, const char *label)
;
; Spelled out the long way once, so the `print` macro used from exercise 02
; onward holds no mysteries. Note the ordering: everything is read out of rdi
; before rdi is reloaded with the format string.
global point_show
point_show:
    prologue
    mov     rcx, [rdi + Point.y]        ; 4th printf arg
    mov     rdx, [rdi + Point.x]        ; 3rd printf arg
                                        ; 2nd arg (label) already in rsi
    lea     rdi, [fmt_point]            ; 1st arg
    xor     eax, eax                    ; 0 vector registers used
    ccall   printf
    epilogue

; long point_sum_x(const Point *array, long count)
;
; The only thing that makes this an "array of objects" is that the stride
; equals the object size.
global point_sum_x
point_sum_x:
    xor     eax, eax
.loop:
    test    rsi, rsi
    jz      .done
    add     rax, [rdi + Point.x]
    add     rdi, Point_size
    dec     rsi
    jmp     .loop
.done:
    ret

; void show_layout(const char *name, long size, long hp_off, long pos_off)
;
; Reports a struct's layout and whether its qword fields land on 8-byte
; boundaries. Written as a real function mostly to keep printf's argument
; shuffling in one place.
global show_layout
show_layout:
    prologue
    xor     rax, rax
    test    rdx, 7                      ; hp_off % 8
    jz      .hp_ok
    inc     rax
.hp_ok:
    test    rcx, 7                      ; pos_off % 8
    jz      .pos_ok
    inc     rax
.pos_ok:
    lea     r9, [verdict_ok]
    test    rax, rax
    jz      .verdict_ready
    lea     r9, [verdict_bad]
.verdict_ready:
    mov     r8, rcx                     ; pos_off
    mov     rcx, rdx                    ; hp_off
    mov     rdx, rsi                    ; size
    mov     rsi, rdi                    ; name
    lea     rdi, [fmt_layout]
    xor     eax, eax
    ccall   printf
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue 32                         ; 32 bytes of locals; [rbp-16] is a Point
    push    rbx                         ; callee-saved: we must restore these
    push    r12                         ; two pushes keep rsp 16-byte aligned

    lea     rdi, [hdr]
    ccall   puts

    ; -- a type is a set of offsets ------------------------------------------
    lea     rdi, [sec_layout]
    ccall   printf
    print   fmt_size, Point_size
    print   fmt_off_x, Point.x
    print   fmt_off_y, Point.y

    ; -- the same 16 bytes, wherever they live -------------------------------
    lea     rdi, [sec_storage]
    ccall   printf

    lea     rdi, [origin]               ; static storage
    lea     rsi, [lbl_static]
    call    point_show

    lea     rdi, [rbp - 16]             ; automatic storage
    mov     rsi, 2
    mov     rdx, 3
    call    point_init
    lea     rdi, [rbp - 16]
    lea     rsi, [lbl_stack]
    call    point_show

    lea     rdi, [particles]            ; static, zero-initialised storage
    lea     rsi, [lbl_bss]
    call    point_show

    ; -- methods are functions with a receiver -------------------------------
    lea     rdi, [sec_methods]
    ccall   printf

    lea     rdi, [rbp - 16]
    lea     rsi, [lbl_before]
    call    point_show

    lea     rdi, [rbp - 16]
    mov     rsi, 10
    mov     rdx, -10
    call    point_translate

    lea     rdi, [rbp - 16]
    lea     rsi, [lbl_after]
    call    point_show

    ; -- an array of objects -------------------------------------------------
    lea     rdi, [sec_array]
    ccall   printf

    xor     rbx, rbx                    ; index
    lea     r12, [particles]            ; cursor
.fill:
    cmp     rbx, PARTICLE_COUNT
    jae     .report
    mov     rdi, r12
    mov     rsi, rbx
    imul    rsi, 10                     ; x = 10*i
    mov     rdx, rsi
    add     rdx, rdx                    ; y = 2x
    call    point_init
    add     r12, Point_size             ; <- the whole trick
    inc     rbx
    jmp     .fill

.report:
    xor     rbx, rbx
    lea     r12, [particles]
.report_loop:
    cmp     rbx, PARTICLE_COUNT
    jae     .sum
    mov     rdx, r12
    lea     rax, [particles]
    sub     rdx, rax                    ; byte offset within the array
    mov     rcx, [r12 + Point.x]
    mov     r8,  [r12 + Point.y]
    mov     rsi, rbx
    lea     rdi, [fmt_elem]
    xor     eax, eax
    ccall   printf
    add     r12, Point_size
    inc     rbx
    jmp     .report_loop

.sum:
    lea     rdi, [particles]
    mov     rsi, PARTICLE_COUNT
    call    point_sum_x
    print   fmt_sum, rax

    ; -- layout has a price --------------------------------------------------
    lea     rdi, [sec_padding]
    ccall   printf

    lea     rdi, [lbl_naive]
    mov     rsi, SpriteNaive_size
    mov     rdx, SpriteNaive.hp
    mov     rcx, SpriteNaive.pos
    call    show_layout

    lea     rdi, [lbl_sprite]
    mov     rsi, Sprite_size
    mov     rdx, Sprite.hp
    mov     rcx, Sprite.pos
    call    show_layout

    pop     r12
    pop     rbx
    xor     eax, eax                    ; return 0 from main
    epilogue
