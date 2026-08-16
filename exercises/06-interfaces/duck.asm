;; duck.asm - class Duck : public Swimmer, public Quacker.
;;
;; One object, two interfaces, two vptrs. The interesting code is tiny: a
;; three-instruction adjustor thunk. Everything else is the same vtable machine
;; from exercise 04, instantiated twice per object.

%include "abi.inc"
%include "libc.inc"
%include "duck.inc"

section .rodata
name_duck:      db "Duck", 0
fmt_swim:       db "  [Swimmer] %s paddles across the pond", 10, 0
fmt_quack:      db "  [Quacker] %s quacks, volume %ld", 10, 0

section .data
align 8

Duck_class:
    istruc Class
        at Class.name,      dq name_duck
        at Class.size,      dq Duck_size
        at Class.parent,    dq 0
    iend
global Duck_class

; Primary vtable, for the Swimmer subobject at offset 0. Its offset_to_top is 0
; because that subobject already is the complete object.
Duck_swimmer_vtable:
    dq 0                                ; MI_VT_OFFSET_TO_TOP
    dq Duck_class                       ; MI_VT_CLASS
    dq Duck_swim                        ; slot SWIMMER_SWIM (no adjustment needed)
global Duck_swimmer_vtable

; Secondary vtable, for the Quacker subobject at offset DUCK_K. Its
; offset_to_top is DUCK_K, and its one method slot holds the ADJUSTOR THUNK,
; not Duck_quack directly - the whole point of this exercise.
Duck_quacker_vtable:
    dq DUCK_K                           ; MI_VT_OFFSET_TO_TOP = 16
    dq Duck_class                       ; MI_VT_CLASS
    dq Duck_quack_thunk                 ; slot QUACKER_QUACK -> thunk -> Duck_quack
global Duck_quacker_vtable

; The fat-pointer alternative: a Go-style itable. The data half of a fat
; pointer will be the complete object, so this stores Duck_quack itself - no
; thunk, because there is nothing to adjust.
Duck_as_quacker_itab:
    istruc Itab
        at Itab.type,       dq Duck_class
        at Itab.quack,      dq Duck_quack
    iend
global Duck_as_quacker_itab

section .text

; ---------------------------------------------------------------------------
; Duck *Duck_new(const char *name, long volume)
;
; Construction installs BOTH vptrs. A C++ constructor for a multiply-inheriting
; class does the same: it writes each base's vtable pointer into that base's
; slot within the object.
; ---------------------------------------------------------------------------
global Duck_new
Duck_new:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; name
    mov     r12, rsi                    ; volume
    mov     rdi, Duck_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    mov     r13, rax                    ; this
    lea     rax, [Duck_swimmer_vtable]
    mov     [r13 + Duck.swimmer_vptr], rax
    lea     rax, [Duck_quacker_vtable]
    mov     [r13 + Duck.quacker_vptr], rax
    mov     [r13 + Duck.name], rbx
    mov     [r13 + Duck.volume], r12
    mov     rax, r13
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; ---------------------------------------------------------------------------
; void Duck_swim(Duck *this)   -- a Swimmer method
;
; Reached through the primary vptr, so `this` is already the complete object;
; no adjustment.
; ---------------------------------------------------------------------------
global Duck_swim
Duck_swim:
    prologue
    mov     rsi, [rdi + Duck.name]
    lea     rdi, [fmt_swim]
    xor     eax, eax
    ccall   printf
    epilogue

; ---------------------------------------------------------------------------
; void Duck_quack(Duck *this)   -- a Quacker method
;
; The real body. It expects `this` to be the COMPLETE object and reads
; .volume, a field that lives past the Quacker subobject. If it were called
; with the raw Quacker pointer (this + DUCK_K), .name and .volume would read
; the wrong bytes - which is exactly why the secondary vtable slot is a thunk.
; ---------------------------------------------------------------------------
global Duck_quack
Duck_quack:
    prologue
    mov     rdx, [rdi + Duck.volume]
    mov     rsi, [rdi + Duck.name]
    lea     rdi, [fmt_quack]
    xor     eax, eax
    ccall   printf
    epilogue

; ---------------------------------------------------------------------------
; Duck_quack_thunk - the adjustor thunk.
;
; Called with rdi = Quacker subobject pointer (complete + DUCK_K). It subtracts
; DUCK_K to recover the complete object and tail-jumps into the real method, so
; Duck_quack never learns it was reached through a secondary interface. Three
; instructions, no stack frame: this is the entire cost of a second base class
; on the call path.
; ---------------------------------------------------------------------------
global Duck_quack_thunk
Duck_quack_thunk:
    sub     rdi, DUCK_K
    jmp     Duck_quack
