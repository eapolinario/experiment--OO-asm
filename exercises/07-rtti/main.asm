;; 07 - Runtime type information: an object that can name its own type.
;;
;; Exercise 04 gave every object a vptr so a caller could *dispatch* without
;; knowing the type. This exercise mines that same pointer for *identity*:
;; vptr -> Class* -> name/parent/depth. From a base pointer alone we recover
;; the most-derived class, test subtype relationships, and narrow a pointer
;; safely. main.asm holds every object through a base type and never branches
;; on a hand-written type tag - there is no type tag, only the class the vptr
;; already points at.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "rtti.inc"
%include "stream.inc"

OBJ_COUNT       equ 4

section .rodata
hdr:            db "== 07 | runtime type information: objects that know their own type ==", 0

sec_dispatch:   db 10, "One vtable, two jobs - dispatch (slot 1) and identity (slot 0):", 10, 0
sec_isa:        db 10, "is_a two ways: a parent-chain walk and Cohen's O(1) display:", 10, 0
sec_cast:       db 10, "A checked downcast is a maybe you must branch on:", 10, 0
sec_filter:     db 10, "Filtering a heterogeneous array by type:", 10, 0

fmt_ask:        db "  %-20s is-a %-20s   walk=%-3s cohen=%-3s  %s", 10, 0
note_isa:       db "  walk is O(depth), cohen is O(1), and they never disagree", 10, 0

fmt_cast_ok:    db "  a %-20s -> CompressedFileStream*: ok, ratio=%ld%%", 10, 0
fmt_cast_no:    db "  a %-20s -> CompressedFileStream*: NULL, took the safe branch", 10, 0

fmt_filter_hdr: db "  keep is-a %s:", 10, 0
fmt_filter_row: db "    [%ld] %-20s %s", 10, 0
fmt_filter_sum: db "    -> %ld of %d matched", 10, 0

s_yes:          db "yes", 0
s_no:           db "no", 0
s_agree:        db "(agree)", 0
s_mismatch:     db "MISMATCH", 0
s_kept:         db "kept", 0
s_dropped:      db "dropped", 0

section .bss
align 8
objs:           resq OBJ_COUNT          ; four base pointers, types forgotten

section .text

; ---------------------------------------------------------------------------
; void ask(Object *obj, RttiClass *target)
;
; Runs both subtype tests and prints them side by side, plus whether they
; agree. The whole point of the section: the O(1) display never contradicts
; the O(depth) walk.
; ---------------------------------------------------------------------------
ask:
    prologue 16
    push    rbx                         ; obj
    push    r12                         ; target
    push    r13                         ; obj's type name
    push    r14                         ; walk result (0/1)
    mov     rbx, rdi
    mov     r12, rsi

    mov     rdi, rbx
    call    type_name
    mov     r13, rax                    ; obj name

    mov     rdi, rbx
    mov     rsi, r12
    call    is_a_slow
    mov     r14, rax                    ; walk answer

    mov     rdi, rbx
    mov     rsi, r12
    call    is_a_fast
    mov     [rbp - 8], rax              ; cohen answer

    lea     rcx, [s_no]                 ; walk string
    lea     rax, [s_yes]
    test    r14, r14
    cmovnz  rcx, rax

    mov     rax, [rbp - 8]              ; cohen numeric
    lea     r8, [s_no]                  ; cohen string
    lea     rdx, [s_yes]
    test    rax, rax
    cmovnz  r8, rdx

    lea     r9, [s_mismatch]            ; agreement string
    lea     rdx, [s_agree]
    cmp     rax, r14
    cmove   r9, rdx

    mov     rdx, [r12 + RttiClass.name] ; target name
    mov     rsi, r13                    ; obj name
    lea     rdi, [fmt_ask]
    xor     eax, eax
    ccall   printf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void trycast(Object *obj)
;
; Attempt the checked downcast to CompressedFileStream* and let the NULL pick
; the branch. On success we may touch a field that exists only on the derived
; class (the ratio); on failure we must not, and dynamic_cast is what tells us
; which world we are in. An unchecked static_cast would take the ok branch
; unconditionally and read a bogus ratio out of a FileStream.
; ---------------------------------------------------------------------------
trycast:
    prologue
    push    rbx                         ; obj
    push    r12                         ; obj's type name
    mov     rbx, rdi

    mov     rdi, rbx
    call    type_name
    mov     r12, rax

    mov     rdi, rbx
    lea     rsi, [CompressedFileStream_class]
    call    dynamic_cast
    test    rax, rax
    jz      .miss

    mov     rdi, rax                    ; safe: rax really is a CompressedFileStream
    call    CompressedFileStream_ratio
    mov     rdx, rax                    ; ratio
    mov     rsi, r12                    ; source type name
    lea     rdi, [fmt_cast_ok]
    xor     eax, eax
    ccall   printf
    jmp     .done
.miss:
    mov     rsi, r12
    lea     rdi, [fmt_cast_no]
    xor     eax, eax
    ccall   printf
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void filter(RttiClass *target)
;
; Walk the mixed array and keep the elements that are-a target. A heterogeneous
; container plus a type predicate is how every "collect all the Ts" loop works,
; from LINQ's OfType<T>() to a Smalltalk `select:`.
; ---------------------------------------------------------------------------
filter:
    prologue 16
    push    rbx                         ; index
    push    r12                         ; target
    push    r13                         ; kept count
    push    r14                         ; current element
    mov     r12, rdi

    mov     rsi, [r12 + RttiClass.name]
    lea     rdi, [fmt_filter_hdr]
    xor     eax, eax
    ccall   printf

    xor     rbx, rbx
    xor     r13, r13
.loop:
    cmp     rbx, OBJ_COUNT
    jae     .summary
    lea     rax, [objs]
    mov     r14, [rax + rbx*8]

    mov     rdi, r14
    mov     rsi, r12
    call    is_a_fast
    add     r13, rax                    ; tally the matches

    lea     rdx, [s_dropped]
    lea     rcx, [s_kept]
    test    rax, rax
    cmovnz  rdx, rcx
    mov     [rbp - 8], rdx              ; stash the verdict across the next call

    mov     rdi, r14
    call    type_name                   ; element's own type name

    mov     rcx, [rbp - 8]              ; verdict
    mov     rdx, rax                    ; name
    mov     rsi, rbx                    ; index
    lea     rdi, [fmt_filter_row]
    xor     eax, eax
    ccall   printf

    inc     rbx
    jmp     .loop
.summary:
    mov     rdx, OBJ_COUNT
    mov     rsi, r13
    lea     rdi, [fmt_filter_sum]
    xor     eax, eax
    ccall   printf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue
    push    rbx
    push    r12

    lea     rdi, [hdr]
    ccall   puts

    ; -- build four objects, then forget their static types ------------------
    lea     r12, [objs]

    call    Stream_new
    mov     [r12 + 0*8], rax

    mov     rdi, 3
    call    FileStream_new
    mov     [r12 + 1*8], rax

    mov     rdi, 4
    mov     rsi, 75
    call    CompressedFileStream_new
    mov     [r12 + 2*8], rax

    mov     rdi, 8
    mov     rsi, 6
    call    Widget_new
    mov     [r12 + 3*8], rax

    ; -- one vtable does dispatch and identity -------------------------------
    lea     rdi, [sec_dispatch]
    ccall   printf
    xor     rbx, rbx
.describe:
    cmp     rbx, OBJ_COUNT
    jae     .described
    lea     rax, [objs]
    mov     rdi, [rax + rbx*8]
    vcall   STREAM_DESCRIBE             ; slot 1: behaviour; the leading name is slot 0
    inc     rbx
    jmp     .describe
.described:

    ; -- is_a, both ways, must always agree ----------------------------------
    lea     rdi, [sec_isa]
    ccall   printf

    lea     rax, [objs]
    mov     rdi, [rax + 2*8]            ; a CompressedFileStream, asked about itself and up
    lea     rsi, [CompressedFileStream_class]
    call    ask
    lea     rax, [objs]
    mov     rdi, [rax + 2*8]
    lea     rsi, [FileStream_class]
    call    ask
    lea     rax, [objs]
    mov     rdi, [rax + 2*8]
    lea     rsi, [Stream_class]
    call    ask
    lea     rax, [objs]
    mov     rdi, [rax + 2*8]
    lea     rsi, [Widget_class]         ; unrelated: a definite no
    call    ask

    lea     rax, [objs]
    mov     rdi, [rax + 1*8]            ; a FileStream asked about a deeper type
    lea     rsi, [CompressedFileStream_class]
    call    ask                         ; exercises Cohen's bounds check
    lea     rax, [objs]
    mov     rdi, [rax + 1*8]
    lea     rsi, [Stream_class]
    call    ask

    lea     rax, [objs]
    mov     rdi, [rax + 0*8]            ; a base Stream is not a FileStream
    lea     rsi, [FileStream_class]
    call    ask
    lea     rax, [objs]
    mov     rdi, [rax + 3*8]            ; and a Widget is nobody's subtype here
    lea     rsi, [Stream_class]
    call    ask

    lea     rdi, [note_isa]
    ccall   printf

    ; -- the downcast and its NULL -------------------------------------------
    lea     rdi, [sec_cast]
    ccall   printf
    lea     rax, [objs]
    mov     rdi, [rax + 2*8]            ; really a CompressedFileStream: succeeds
    call    trycast
    lea     rax, [objs]
    mov     rdi, [rax + 1*8]            ; only a FileStream: NULL, other branch
    call    trycast

    ; -- filter the mixed bag ------------------------------------------------
    lea     rdi, [sec_filter]
    ccall   printf
    lea     rdi, [Stream_class]
    call    filter
    lea     rdi, [FileStream_class]
    call    filter

    ; -- release everything --------------------------------------------------
    xor     rbx, rbx
.free:
    cmp     rbx, OBJ_COUNT
    jae     .freed
    lea     rax, [objs]
    mov     rdi, [rax + rbx*8]
    ccall   free
    inc     rbx
    jmp     .free
.freed:

    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue
