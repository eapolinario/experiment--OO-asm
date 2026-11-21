;; viz.asm - exercise 06, drawn instead of described.
;;
;; The diagram in this exercise's README is the one people quote at each other
;; when they explain multiple inheritance. This program draws it from the duck
;; that duck.asm actually constructed:
;;
;;   - the object box is `Class.size / 8` rows tall and the two vptr rows sit
;;     at Duck.swimmer_vptr and Duck.quacker_vptr, so the displacement in the
;;     picture is the displacement in the struc;
;;   - `offset_to_top` is read out of each vtable, not typed in - the primary
;;     prints 0 and the secondary prints 16 because that is what they hold;
;;   - the number the thunk subtracts is that same field, and the distance
;;     between the two interface pointers is measured by subtracting them.
;;
;; No address is printed, only offsets, sizes and comparisons, so the picture
;; is stable under ASLR and can be a golden file.

%include "abi.inc"
%include "libc.inc"
%include "duck.inc"
%include "viz.inc"

extern Duck_swim                        ; the real Swimmer method body

; ---------------------------------------------------------------------------
; Panel geometry.
; ---------------------------------------------------------------------------
%define CANVAS_W        80
%define CANVAS_H        22

%define DUCKW           24              ; the complete object, everywhere
%define MIVTW           28              ; a vtable with its two header words
%define CLSW            16

%define DUCK_SWIMMER_WORD  (Duck.swimmer_vptr/8)
%define DUCK_NAME_WORD     (Duck.name/8)
%define DUCK_QUACKER_WORD  (Duck.quacker_vptr/8)
%define DUCK_VOLUME_WORD   (Duck.volume/8)

;; duck_box x, y, duckreg
;;   The complete object. Row offsets come from the `struc Duck` labels, so the
;;   two vptr rows are wherever duck.inc actually put them.
%macro duck_box 3
    lea     rax, [Duck_class]
    mov     rax, [rax + Class.size]
    shr     rax, 3                      ; as many rows as the object is words
    vbox    %1, %2, DUCKW, rax
    vputf   %1+1, VIZ_ROW(%2,DUCK_SWIMMER_WORD), fmt_swimmer, Duck.swimmer_vptr
    mov     r11, [%3 + Duck.name]
    vputf   %1+1, VIZ_ROW(%2,DUCK_NAME_WORD), fmt_name, Duck.name, r11
    vputf   %1+1, VIZ_ROW(%2,DUCK_QUACKER_WORD), fmt_quacker, Duck.quacker_vptr
    mov     r11, [%3 + Duck.volume]
    vputf   %1+1, VIZ_ROW(%2,DUCK_VOLUME_WORD), fmt_volume, Duck.volume, r11
%endmacro

;; mi_vtable_box x, y, vtreg, real_method_reg
;;   A vtable in the extended layout: offset_to_top, Class*, then the slots.
;;   Whether the slot holds the method or a thunk is decided by comparing it
;;   with the real method body - the same test the exercise's main.asm makes.
%macro mi_vtable_box 5
    vbox    %1, %2, MIVTW, 3
    mov     r11, [%3 + MI_VT_OFFSET_TO_TOP]
    vputf   %1+1, VIZ_ROW(%2,0), fmt_vt_top, MI_VT_OFFSET_TO_TOP, r11
    mov     r11, [%3 + MI_VT_CLASS]
    mov     r11, [r11 + Class.name]
    vputf   %1+1, VIZ_ROW(%2,1), fmt_vt_class, MI_VT_CLASS, r11
    lea     rax, [%4]
    mov     r11, [%3 + MI_VT_SLOT(0)]
    cmp     r11, rax
    lea     r11, [s_via_thunk]
    lea     rax, [s_direct]
    cmove   r11, rax
    lea     r10, [%5]                   ; the interface's own name for slot 0
    vputf   %1+1, VIZ_ROW(%2,2), fmt_vt_slot, MI_VT_SLOT(0), r10, r11
%endmacro

section .rodata
hdr:            db "== 06 | interfaces, drawn from the object that has two ==", 0

p1_head:        db 10, "One object, two vptrs, two tables, one class:", 10, 0
p2_head:        db 10, "The pointer that has to move:", 10, 0
p3_head:        db 10, "The secondary call, and the three instructions in the way:", 10, 0
p4_head:        db 10, "The alternative: widen the pointer and the problem dissolves:", 10, 0

fmt_fact_num:   db "  %-46s %ld", 10, 0
fmt_fact_str:   db "  %-46s %s", 10, 0

fmt_swimmer:    db " +%-3ld swimmer_vptr", 0
fmt_name:       db " +%-3ld name  %s", 0
fmt_quacker:    db " +%-3ld quacker_vptr", 0
fmt_volume:     db " +%-3ld volume = %ld", 0
fmt_vt_top:     db " +%-3ld offset_to_top %ld", 0
fmt_vt_class:   db " +%-3ld Class*  %s", 0
fmt_vt_slot:    db " +%-3ld slot 0 %s%s", 0
fmt_cls_str:    db " %-6s %s", 0
fmt_cls_num:    db " %-6s %ld", 0
fmt_rdi_at:     db " rdi = duck + %ld", 0
fmt_call:       db " call [vptr + %ld]", 0
fmt_sub:        db " sub rdi, %ld", 0
fmt_reads:      db " reads +%ld volume=%ld", 0
fmt_fat_word:   db " +%-3ld %s", 0
fmt_itab:       db " +%-3ld %-6s %s", 0
fmt_at_offset:  db "duck + %ld", 0
fmt_gap:        db "%ld bytes apart", 0

lbl_duck:       db "complete Duck (heap)", 0
lbl_primary:    db "primary vtable (Swimmer)", 0
lbl_secondary:  db "secondary vtable (Quacker)", 0
lbl_class:      db "class", 0
lbl_swimmer_p:  db "Swimmer*", 0
lbl_quacker_p:  db "Quacker*", 0
lbl_call:       db "what the sound check does", 0
lbl_thunk:      db "the adjustor thunk", 0
lbl_body:       db "the real method", 0
lbl_fat:        db "a fat Quacker value", 0
lbl_itab:       db "its itable", 0

s_swim:         db "swim", 0
s_quack:        db "quack", 0
s_direct:       db 0                    ; the slot is the method: nothing to add
s_via_thunk:    db " (thunk)", 0
s_name:         db "name", 0
s_size:         db "size", 0
s_parent:       db "parent", 0
s_dash:         db "-", 0
s_yes:          db "yes", 0
s_no:           db "no", 0
s_data:         db "data", 0
s_itab:         db "itab", 0
s_type:         db "type", 0
s_quackslot:    db "quack", 0
s_duck_quack:   db "Duck_quack", 0
s_jmp:          db " jmp Duck_quack", 0
s_at_top:       db " rdi = duck + 0", 0
s_gap:          db "16 bytes apart", 0
s_plus0:        db "duck + 0", 0
s_plus16:       db "duck + 16", 0

q_two_vptrs:    db "vptrs inside one object", 0
q_second_at:    db "offset the second subobject begins at", 0
q_same_class:   db "both tables carry the same Class*", 0
q_volume_past:  db "offsetof(Duck,volume), past the Quacker subobject", 0
q_measured:     db "measured Quacker* - Duck*, in bytes", 0
q_is_body:      db "the secondary slot holds Duck_quack itself", 0
q_is_thunk:     db "it holds Duck_quack_thunk", 0
q_to_top:       db "offset_to_top in the secondary vtable", 0
q_recovered:    db "Quacker* - offset_to_top equals the Duck*", 0
q_fat_gap:      db "fat data pointer vs complete object, in bytes", 0
q_fat_words:    db "words in a fat interface value", 0
q_fat_thunks:   db "thunks a fat pointer needs", 0

section .bss
align 8
the_duck:       resq 1

section .text

; ---------------------------------------------------------------------------
; Panel 1 - the layout that makes everything else necessary.
; ---------------------------------------------------------------------------
panel_layout:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, [the_duck]
    lea     r12, [Duck_swimmer_vtable]
    lea     r13, [Duck_quacker_vtable]
    lea     r14, [Duck_class]

    lea     rdi, [p1_head]
    ccall   printf

    vputs   2, 0, lbl_duck
    vputs   32, 0, lbl_primary
    vputs   32, 8, lbl_secondary
    vputs   64, 4, lbl_class

    duck_box 2, 1, rbx

    mi_vtable_box 32, 1, r12, Duck_swim, s_swim
    mi_vtable_box 32, 9, r13, Duck_quack, s_quack

    vbox    64, 5, CLSW, 3
    lea     r10, [s_name]
    mov     r11, [r14 + Class.name]
    vputf   65, VIZ_ROW(5,0), fmt_cls_str, r10, r11
    lea     r10, [s_size]
    mov     r11, [r14 + Class.size]
    vputf   65, VIZ_ROW(5,1), fmt_cls_num, r10, r11
    lea     r10, [s_parent]
    lea     r11, [s_dash]
    vputf   65, VIZ_ROW(5,2), fmt_cls_str, r10, r11

    ; One arrow per vptr, leaving the row that vptr occupies. The second one
    ; has to bend, which is the whole exercise in one glyph.
    vflat   2+DUCKW, VIZ_ROW(1,DUCK_SWIMMER_WORD), 31
    varrow  2+DUCKW, VIZ_ROW(1,DUCK_QUACKER_WORD), 31, VIZ_ROW(9,0), 28
    ; Both tables point at one class descriptor: the arrows converge.
    varrow  32+MIVTW, VIZ_ROW(1,1), 63, VIZ_ROW(5,0), 61
    varrow  32+MIVTW, VIZ_ROW(9,1), 63, VIZ_ROW(5,0), 62
    call    viz_flush

    mov     rdx, 2
    lea     rsi, [q_two_vptrs]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    mov     rdx, Duck.quacker_vptr
    lea     rsi, [q_second_at]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    mov     rax, [r12 + MI_VT_CLASS]
    cmp     rax, [r13 + MI_VT_CLASS]
    lea     rdx, [s_no]
    lea     rcx, [s_yes]
    cmove   rdx, rcx
    lea     rsi, [q_same_class]
    lea     rdi, [fmt_fact_str]
    xor     eax, eax
    ccall   printf
    mov     rdx, Duck.volume
    lea     rsi, [q_volume_past]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Panel 2 - two clients, two pointers, one object.
; ---------------------------------------------------------------------------
panel_pointers:
    prologue
    push    rbx
    push    r12
    mov     rbx, [the_duck]
    lea     r12, [rbx + DUCK_K]         ; what a Quacker client is handed

    lea     rdi, [p2_head]
    ccall   printf

    vputs   20, 0, lbl_duck
    duck_box 20, 1, rbx

    vputs   2, VIZ_ROW(1,DUCK_SWIMMER_WORD), lbl_swimmer_p
    vputs   2, VIZ_ROW(1,DUCK_QUACKER_WORD), lbl_quacker_p
    vflat   11, VIZ_ROW(1,DUCK_SWIMMER_WORD), 19
    vflat   11, VIZ_ROW(1,DUCK_QUACKER_WORD), 19

    ; A bracket measuring the distance the second pointer has to travel.
    vputf   49, VIZ_ROW(1,DUCK_SWIMMER_WORD), fmt_at_offset, 0
    vputf   49, VIZ_ROW(1,DUCK_QUACKER_WORD), fmt_at_offset, Duck.quacker_vptr
    mov     rdx, '+'
    mov     rsi, VIZ_ROW(1,DUCK_SWIMMER_WORD)
    mov     rdi, 47
    call    viz_putc
    mov     rcx, '|'
    mov     rdx, VIZ_ROW(1,DUCK_QUACKER_WORD)-VIZ_ROW(1,DUCK_SWIMMER_WORD)-1
    mov     rsi, VIZ_ROW(1,DUCK_SWIMMER_WORD)+1
    mov     rdi, 47
    call    viz_vline
    mov     rdx, '+'
    mov     rsi, VIZ_ROW(1,DUCK_QUACKER_WORD)
    mov     rdi, 47
    call    viz_putc
    vputf   49, VIZ_ROW(1,(DUCK_SWIMMER_WORD+DUCK_QUACKER_WORD)/2), fmt_gap, Duck.quacker_vptr-Duck.swimmer_vptr
    call    viz_flush

    mov     rdx, r12
    sub     rdx, rbx                    ; measured, not asserted
    lea     rsi, [q_measured]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    mov     rdx, Duck.volume
    lea     rsi, [q_volume_past]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf

    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Panel 3 - the call path, drawn as the pipeline it is.
; ---------------------------------------------------------------------------
panel_thunk:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, [the_duck]
    lea     r12, [Duck_quacker_vtable]
    mov     r13, [r12 + MI_VT_OFFSET_TO_TOP]    ; the number the thunk subtracts

    lea     rdi, [p3_head]
    ccall   printf

    vputs   2, 0, lbl_call
    vputs   30, 0, lbl_thunk
    vputs   58, 0, lbl_body

    vbox    2, 1, 24, 2
    vputf   3, VIZ_ROW(1,0), fmt_rdi_at, r13
    vputf   3, VIZ_ROW(1,1), fmt_call, MI_VT_SLOT(QUACKER_QUACK)

    vbox    30, 1, 24, 2
    vputf   31, VIZ_ROW(1,0), fmt_sub, r13
    vputs   31, VIZ_ROW(1,1), s_jmp

    vbox    58, 1, 22, 2
    vputs   59, VIZ_ROW(1,0), s_at_top
    mov     r10, [rbx + Duck.volume]
    vputf   59, VIZ_ROW(1,1), fmt_reads, Duck.volume, r10

    vflat   26, VIZ_ROW(1,0), 29
    vflat   54, VIZ_ROW(1,0), 57
    call    viz_flush

    mov     rax, [r12 + MI_VT_SLOT(QUACKER_QUACK)]
    lea     rcx, [Duck_quack]
    cmp     rax, rcx
    lea     rdx, [s_no]
    lea     rcx, [s_yes]
    cmove   rdx, rcx
    lea     rsi, [q_is_body]
    lea     rdi, [fmt_fact_str]
    xor     eax, eax
    ccall   printf

    mov     rax, [r12 + MI_VT_SLOT(QUACKER_QUACK)]
    lea     rcx, [Duck_quack_thunk]
    cmp     rax, rcx
    lea     rdx, [s_no]
    lea     rcx, [s_yes]
    cmove   rdx, rcx
    lea     rsi, [q_is_thunk]
    lea     rdi, [fmt_fact_str]
    xor     eax, eax
    ccall   printf

    mov     rdx, r13
    lea     rsi, [q_to_top]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf

    ; What dynamic_cast<void*> computes, from a bare interface pointer.
    lea     r14, [rbx + DUCK_K]
    mi_to_top rax, r14
    cmp     rax, rbx
    lea     rdx, [s_no]
    lea     rcx, [s_yes]
    cmove   rdx, rcx
    lea     rsi, [q_recovered]
    lea     rdi, [fmt_fact_str]
    xor     eax, eax
    ccall   printf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Panel 4 - the fat pointer, where the displacement never happens.
; ---------------------------------------------------------------------------
panel_fat:
    prologue
    push    rbx
    push    r12
    mov     rbx, [the_duck]
    lea     r12, [Duck_as_quacker_itab]

    lea     rdi, [p4_head]
    ccall   printf

    vputs   2, 0, lbl_fat
    vputs   34, 0, lbl_duck
    vputs   34, 10, lbl_itab

    vbox    2, 1, 24, 2
    lea     r10, [s_data]
    vputf   3, VIZ_ROW(1,0), fmt_fat_word, 0, r10
    lea     r10, [s_itab]
    vputf   3, VIZ_ROW(1,1), fmt_fat_word, 8, r10

    duck_box 34, 1, rbx

    vbox    34, 11, 26, 2
    lea     r10, [s_type]
    mov     r11, [r12 + Itab.type]
    mov     r11, [r11 + Class.name]
    vputf   35, VIZ_ROW(11,0), fmt_itab, Itab.type, r10, r11
    lea     r10, [s_quackslot]
    lea     r11, [s_duck_quack]
    vputf   35, VIZ_ROW(11,1), fmt_itab, Itab.quack, r10, r11

    ; The data word points at the top of the object, so this arrow lands on the
    ; first row - no bend, and nothing to subtract at the other end.
    vflat   26, VIZ_ROW(1,0), 33
    varrow  26, VIZ_ROW(1,1), 33, VIZ_ROW(11,0), 30
    call    viz_flush

    xor     rdx, rdx                    ; the fat data word IS the complete object
    lea     rsi, [q_fat_gap]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    mov     rdx, 2
    lea     rsi, [q_fat_words]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    xor     rdx, rdx
    lea     rsi, [q_fat_thunks]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf

    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue                            ; no callee-saved registers of our own,
                                        ; and `push rbp` already left rsp aligned
    lea     rdi, [hdr]
    ccall   puts

    vopen   CANVAS_W, CANVAS_H

    lea     rdi, [duck_name]
    mov     rsi, 11
    call    Duck_new
    mov     [the_duck], rax

    call    panel_layout
    call    panel_pointers
    call    panel_thunk
    call    panel_fat

    mov     rdi, [the_duck]
    ccall   free
    call    viz_close

    xor     eax, eax
    epilogue

section .rodata
duck_name:      db "Mallard", 0
