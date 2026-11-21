;; viz.asm - exercise 04, drawn instead of described.
;;
;; This is a second `main` for the same exercise. It links against circle.asm
;; and rect.asm - the very code main.asm uses - constructs the same objects,
;; and then, instead of printing facts about them, prints the picture.
;;
;; Everything positional in that picture is read back out of the object system
;; at run time rather than typed in here:
;;
;;   - a box is `Class.size / 8` rows tall, so the instance box grows a row the
;;     day somebody adds a field;
;;   - the offsets printed in the rows are the `struc` offsets themselves
;;     (Object.vptr, Class.name, VT_SLOT(n)), not literals that agree with them
;;     by coincidence;
;;   - an arrow starts at the row the vptr occupies and ends at the table that
;;     vptr actually holds - two vptrs holding the same address draw two arrows
;;     that merge, which is the whole of "a vtable is per-class".
;;
;; No address is ever printed, only offsets, sizes and comparisons, so the
;; output is stable under ASLR and can be a golden file like every other
;; program here.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "shape.inc"
%include "shape_layout.inc"
%include "viz.inc"

extern Circle_new                       ; Circle *Circle_new(long r)
extern Rect_new                         ; Rect   *Rect_new(long w, long h)
extern Rect_enable_debug                ; void    Rect_enable_debug(Rect *)

; ---------------------------------------------------------------------------
; Panel geometry. Columns, not art: every box lands on one of these.
; ---------------------------------------------------------------------------
%define CANVAS_W        80
%define CANVAS_H        26

%define OBJ_X           2               ; instances, left column
%define OBJW            18
%define VT1_X           26              ; the table, beside the object (panel 1)
%define VTW             28
%define CLS_X           58              ; the class descriptor
%define CLSW            22
%define VT2_X           40              ; the table, with room for elbows
%define MIDA            28              ; columns the elbows turn in
%define MIDB            32

;; vtable_box x, y, vtreg
;;   Draw one Shape vtable: the class word, then one row per interface slot.
;;   `vtreg` must be a callee-saved register, since this makes calls.
;;   The row offsets come from VT_CLASS and VT_SLOT(n) in object.inc, so the
;;   numbers in the picture are the same ones the `vcall` macro indexes with.
%macro vtable_box 3
    mov     r15, %2
    vbox    %1, r15, VTW, 1 + SHAPE_SLOTS
    mov     r11, [%3 + VT_CLASS]
    mov     r10, [r11 + Class.name]
    lea     rsi, [r15 + 1]
    vputf   %1+1, rsi, fmt_vt_class, VT_CLASS, r10
  %assign vt_i 0
  %rep SHAPE_SLOTS
    lea     r10, [slot_names]
    mov     r10, [r10 + 8*vt_i]
    lea     rsi, [r15 + 3 + 2*vt_i]
    vputf   %1+1, rsi, fmt_vt_slot, VT_SLOT(vt_i), vt_i, r10
    %assign vt_i vt_i+1
  %endrep
%endmacro

;; swizzle_panel vt_a, vt_b, second_vt_y, target_y
;;   The Rect, both candidate tables, and one arrow - to whichever table the
;;   object's vptr currently holds. Drawn twice, and only the arrow moves.
%macro swizzle_panel 4
    vputs   OBJ_X, 0, lbl_rect
    vputs   VT2_X, 0, lbl_vt_born
    mov     rax, %3
    dec     rax
    vputs   VT2_X, rax, lbl_vt_debug

    vbox    OBJ_X, 1, OBJW, [rect_words]
    vputf   OBJ_X+1, VIZ_ROW(1,0), fmt_vptr, Object.vptr
    lea     r10, [s_w]
    mov     r11, [rbx + Rect.w]
    vputf   OBJ_X+1, VIZ_ROW(1,Rect.w/8), fmt_field, Rect.w, r10, r11
    lea     r10, [s_h]
    mov     r11, [rbx + Rect.h]
    vputf   OBJ_X+1, VIZ_ROW(1,Rect.h/8), fmt_field, Rect.h, r10, r11

    vtable_box VT2_X, 1, %1
    mov     rax, %3
    vtable_box VT2_X, rax, %2

    ; The one word the two tables disagree on, found by comparing them - the
    ; row is computed, VIZ_ROW(y, i) with a runtime i.
    lea     rdx, [s_differs]
    lea     rsi, [r14*2 + 2]            ; VIZ_ROW(1, r14)
    mov     rdi, VT2_X+VTW+1
    call    viz_puts
    lea     rdx, [s_differs]
    mov     rsi, %3
    add     rsi, 1
    lea     rsi, [rsi + r14*2]          ; VIZ_ROW(rect_vt2_y, r14)
    mov     rdi, VT2_X+VTW+1
    call    viz_puts

    mov     rsi, %4
    add     rsi, 1
    varrow  OBJ_X+OBJW, VIZ_ROW(1,0), VT2_X-1, rsi, MIDA
    call    viz_flush
%endmacro

section .rodata
hdr:            db "== 04 | vtables, drawn from the objects themselves ==", 0

p1_head:        db 10, "One object, one table, one class:", 10, 0
p2_head:        db 10, "One table per class, however many instances:", 10, 0
p3_head:        db 10, "Swapping the vptr swaps the behaviour:", 10, 0
p3_before:      db "  before Rect_enable_debug:", 10, 0
p3_after:       db 10, "  after Rect_enable_debug - one store to offset 0:", 10, 0

fmt_fact_num:   db "  %-46s %ld", 10, 0
fmt_fact_str:   db "  %-46s %s", 10, 0

; Row texts. The leading space keeps them off the box border.
fmt_vptr:       db " +%-3ld vptr", 0
fmt_field:      db " +%-3ld %s = %ld", 0
fmt_vt_class:   db " +%-3ld Class*  %s", 0
fmt_vt_slot:    db " +%-3ld slot %ld  %s", 0
fmt_cls_str:    db " +%-3ld %-6s %s", 0
fmt_cls_num:    db " +%-3ld %-6s %ld", 0

lbl_circle:     db "Circle instance (heap)", 0
lbl_vt_short:   db "Circle vtable (shared)", 0
lbl_vt_circle:  db "Circle vtable (.data, one per class)", 0
lbl_class:      db "class descriptor", 0
lbl_c1:         db "Circle r=3", 0
lbl_c2:         db "Circle r=1", 0
lbl_rect45:     db "Rect 4x5", 0
lbl_vt_rect:    db "Rect vtable", 0
lbl_rect:       db "Rect instance", 0
lbl_vt_born:    db "the table it was born with", 0
lbl_vt_debug:   db "the table Rect_enable_debug stores", 0

s_r:            db "r", 0
s_w:            db "w", 0
s_h:            db "h", 0
s_name:         db "name", 0
s_size:         db "size", 0
s_parent:       db "parent", 0
s_dash:         db "-", 0
s_differs:      db "differs", 0
s_area:         db "area", 0
s_perim:        db "perimeter", 0
s_show:         db "show", 0
s_yes:          db "yes", 0
s_no:           db "no", 0

q_bytes_obj:    db "bytes per instance, from Class.size", 0
q_words_obj:    db "therefore rows in the instance box", 0
q_bytes_vt:     db "bytes of method table, one per class", 0
q_vptr_off:     db "offset the arrow leaves from (Object.vptr)", 0
q_same:         db "the two Circles' vptrs hold the same address", 0
q_diff:         db "the Rect's vptr holds that address too", 0
q_tables:       db "tables drawn above, for three objects", 0
q_identical:    db "words the two Rect tables agree on, of 4", 0
q_differs:      db "the slot number they disagree on", 0
q_fields:       db "fields of the object that changed", 0
q_class_after:  db "class read back through the new table", 0

; Absolute addresses, so this lives in .data and not .rodata: the loader has to
; relocate them, exactly as it does for the vtables themselves.
section .data
align 8
slot_names:     dq s_area, s_perim, s_show

section .bss
align 8
obj_c1:         resq 1
obj_c2:         resq 1
obj_r1:         resq 1
same_words:     resq 1                  ; words the two Rect tables agree on
difference_count: resq 1                ; slots that differ, used as a visual invariant
circle1_words:  resq 1
circle2_words:  resq 1
rect_words:     resq 1
circle1_y:      resq 1
circle2_y:      resq 1
rect_y:         resq 1
rect_vt_y:      resq 1
rect_vt2_y:     resq 1

section .text

; ---------------------------------------------------------------------------
; Panel 1 - the canonical triple: object, vtable, class descriptor.
; ---------------------------------------------------------------------------
panel_layout:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, [obj_c1]
    mov     r12, [rbx + Object.vptr]    ; the table, straight out of the object
    mov     r13, [r12 + VT_CLASS]       ; the class, straight out of the table

    lea     rdi, [p1_head]
    ccall   printf

    vputs   OBJ_X, 0, lbl_circle
    vputs   VT1_X, 0, lbl_vt_short
    vputs   CLS_X, 0, lbl_class

    mov     rax, [r13 + Class.size]
    shr     rax, 3                      ; the box is as tall as the object is big
    vbox    OBJ_X, 1, OBJW, rax
    vputf   OBJ_X+1, VIZ_ROW(1,0), fmt_vptr, Object.vptr
    lea     r10, [s_r]
    mov     r11, [rbx + Circle.r]
    vputf   OBJ_X+1, VIZ_ROW(1,Circle.r/8), fmt_field, Circle.r, r10, r11

    vtable_box VT1_X, 1, r12

    vbox    CLS_X, 1, CLSW, 3
    lea     r10, [s_name]
    mov     r11, [r13 + Class.name]
    vputf   CLS_X+1, VIZ_ROW(1,0), fmt_cls_str, Class.name, r10, r11
    lea     r10, [s_size]
    mov     r11, [r13 + Class.size]
    vputf   CLS_X+1, VIZ_ROW(1,1), fmt_cls_num, Class.size, r10, r11
    lea     r10, [s_parent]
    lea     r11, [s_dash]
    mov     rax, [r13 + Class.parent]
    test    rax, rax
    jz      .no_parent
    mov     r11, [rax + Class.name]
.no_parent:
    vputf   CLS_X+1, VIZ_ROW(1,2), fmt_cls_str, Class.parent, r10, r11

    ; The two loads a virtual call makes, drawn: object to table, table to class.
    vflat   OBJ_X+OBJW, VIZ_ROW(1,0), VT1_X-1
    vflat   VT1_X+VTW, VIZ_ROW(1,0), CLS_X-1
    call    viz_flush

    mov     rdx, [r13 + Class.size]
    lea     rsi, [q_bytes_obj]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    mov     rdx, [r13 + Class.size]
    shr     rdx, 3
    lea     rsi, [q_words_obj]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    mov     rdx, (SHAPE_SLOTS + 1) * 8
    lea     rsi, [q_bytes_vt]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    mov     rdx, Object.vptr
    lea     rsi, [q_vptr_off]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Panel 2 - three objects, two tables. The arrows do the arguing.
; ---------------------------------------------------------------------------
panel_sharing:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rax
    mov     rbx, [obj_c1]
    mov     r12, [obj_c2]
    mov     r13, [obj_r1]

    class_of r14, rbx
    mov     rax, [r14 + Class.size]
    shr     rax, 3
    mov     [circle1_words], rax

    class_of r14, r12
    mov     rax, [r14 + Class.size]
    shr     rax, 3
    mov     [circle2_words], rax

    class_of r14, r13
    mov     rax, [r14 + Class.size]
    shr     rax, 3
    mov     [rect_words], rax

    mov     qword [circle1_y], 1
    mov     rax, [circle1_words]
    shl     rax, 1
    add     rax, 3
    mov     [circle2_y], rax
    mov     rax, [circle2_words]
    shl     rax, 1
    add     rax, 2
    mov     rdx, [circle2_y]
    add     rdx, rax
    mov     [rect_y], rdx

    mov     rax, 3 + 2*(SHAPE_SLOTS + 1)
    mov     [rect_vt_y], rax
    lea     rdi, [p2_head]
    ccall   printf

    mov     r14, [circle1_y]
    dec     r14
    vputs   OBJ_X, r14, lbl_c1
    mov     r14, [circle2_y]
    dec     r14
    vputs   OBJ_X, r14, lbl_c2
    mov     r14, [rect_y]
    dec     r14
    vputs   OBJ_X, r14, lbl_rect45
    vputs   VT2_X, 0, lbl_vt_circle
    mov     r14, [rect_vt_y]
    dec     r14
    vputs   VT2_X, r14, lbl_vt_rect

    mov     r12, [circle1_y]
    vbox    OBJ_X, r12, OBJW, [circle1_words]
    mov     r14, r12
    add     r14, 1
    vputf   OBJ_X+1, r14, fmt_vptr, Object.vptr
    lea     r10, [s_r]
    mov     r11, [rbx + Circle.r]
    mov     r14, r12
    add     r14, 1 + 2*(Circle.r/8)
    vputf   OBJ_X+1, r14, fmt_field, Circle.r, r10, r11

    mov     r12, [circle2_y]
    vbox    OBJ_X, r12, OBJW, [circle2_words]
    mov     r14, r12
    add     r14, 1
    vputf   OBJ_X+1, r14, fmt_vptr, Object.vptr
    lea     r10, [s_r]
    mov     r11, [obj_c2]
    mov     r11, [r11 + Circle.r]
    mov     r14, r12
    add     r14, 1 + 2*(Circle.r/8)
    vputf   OBJ_X+1, r14, fmt_field, Circle.r, r10, r11

    mov     r12, [rect_y]
    vbox    OBJ_X, r12, OBJW, [rect_words]
    mov     r14, r12
    add     r14, 1
    vputf   OBJ_X+1, r14, fmt_vptr, Object.vptr
    lea     r10, [s_w]
    mov     r11, [r13 + Rect.w]
    mov     r14, r12
    add     r14, 1 + 2*(Rect.w/8)
    vputf   OBJ_X+1, r14, fmt_field, Rect.w, r10, r11
    lea     r10, [s_h]
    mov     r11, [r13 + Rect.h]
    mov     r14, r12
    add     r14, 1 + 2*(Rect.h/8)
    vputf   OBJ_X+1, r14, fmt_field, Rect.h, r10, r11

    mov     r14, [rbx + Object.vptr]
    mov     r12, [circle1_y]
    vtable_box VT2_X, r12, r14
    mov     r14, [r13 + Object.vptr]
    mov     r12, [rect_vt_y]
    vtable_box VT2_X, r12, r14

    ; Draw the first Circle's arrow, then the second's into the same row: the
    ; elbow joins the line already there instead of drawing a second one.
    mov     r12, [circle1_y]
    inc     r12
    mov     r15, [circle1_y]
    inc     r15
    vflat   OBJ_X+OBJW, r12, VT2_X-1
    mov     r13, [circle2_y]
    inc     r13
    varrow  OBJ_X+OBJW, r13, VT2_X-1, r15, MIDA
    mov     r14, [rect_y]
    inc     r14
    mov     r15, [rect_vt_y]
    inc     r15
    varrow  OBJ_X+OBJW, r14, VT2_X-1, r15, MIDB
    call    viz_flush

    mov     rax, [rbx + Object.vptr]
    mov     r12, [obj_c2]
    cmp     rax, [r12 + Object.vptr]
    lea     rdx, [s_no]
    lea     rcx, [s_yes]
    cmove   rdx, rcx
    lea     rsi, [q_same]
    lea     rdi, [fmt_fact_str]
    xor     eax, eax
    ccall   printf

    mov     rax, [rbx + Object.vptr]
    mov     r13, [obj_r1]
    cmp     rax, [r13 + Object.vptr]
    lea     rdx, [s_no]
    lea     rcx, [s_yes]
    cmove   rdx, rcx
    lea     rsi, [q_diff]
    lea     rdi, [fmt_fact_str]
    xor     eax, eax
    ccall   printf

    mov     rdx, 2
    lea     rsi, [q_tables]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf

    pop     rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Panel 3 - isa-swizzling. Same object, same fields, different arrow.
; ---------------------------------------------------------------------------
panel_swizzle:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, [obj_r1]

    class_of r14, rbx
    mov     rax, [r14 + Class.size]
    shr     rax, 3
    mov     [rect_words], rax
    shl     rax, 1
    add     rax, 5
    mov     [rect_vt2_y], rax

    mov     r12, [rbx + Object.vptr]    ; the table it was born with

    ; Peek at the debug table's address by installing it and putting the old
    ; one back. Nothing in the object model forbids that: the vptr is a field
    ; like any other, which is the point this panel is about to make.
    mov     rdi, rbx
    call    Rect_enable_debug
    mov     r13, [rbx + Object.vptr]
    mov     [rbx + Object.vptr], r12

    ; How much of the "new behaviour" is actually new: compare the two tables
    ; word by word, count the words that agree, and remember the one that does
    ; not - the panels mark that row, so the reader can see how little changed.
    xor     rax, rax                    ; word index
    xor     rcx, rcx                    ; words the two tables agree on
    xor     r14, r14                    ; the word they do not
    mov     qword [difference_count], 0
.compare:
    cmp     rax, SHAPE_SLOTS            ; word 0 is the class, then one per slot
    ja      .compared
    mov     rdx, [r12 + 8*rax]
    cmp     rdx, [r13 + 8*rax]
    jne     .differs
    inc     rcx
    jmp     .next
.differs:
    mov     r14, rax
    inc     qword [difference_count]
.next:
    inc     rax
    jmp     .compare
.compared:
    cmp     qword [difference_count], 1
    jne     .unexpected
    cmp     r14, 1
    jb      .unexpected
    cmp     r14, SHAPE_SLOTS
    ja      .unexpected
    mov     [same_words], rcx

    lea     rdi, [p3_head]
    ccall   printf
    lea     rdi, [p3_before]
    ccall   printf
    swizzle_panel r12, r13, [rect_vt2_y], 1

    mov     rdi, rbx
    call    Rect_enable_debug           ; for real this time
    lea     rdi, [p3_after]
    ccall   printf
    swizzle_panel r12, r13, [rect_vt2_y], [rect_vt2_y]

    mov     rdx, [same_words]
    lea     rsi, [q_identical]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    lea     rdx, [r14 - 1]              ; word 0 is the class, so slot = word-1
    lea     rsi, [q_differs]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf
    xor     rdx, rdx
    lea     rsi, [q_fields]
    lea     rdi, [fmt_fact_num]
    xor     eax, eax
    ccall   printf

    class_of rax, rbx                   ; the class, read through the new table
    mov     rdx, [rax + Class.name]
    lea     rsi, [q_class_after]
    lea     rdi, [fmt_fact_str]
    xor     eax, eax
    ccall   printf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
.unexpected:
    ccall   abort

; ---------------------------------------------------------------------------
global main
main:
    prologue                            ; no callee-saved registers of our own,
                                        ; and `push rbp` already left rsp aligned
    lea     rdi, [hdr]
    ccall   puts

    vopen   CANVAS_W, CANVAS_H

    mov     rdi, 3
    call    Circle_new
    mov     [obj_c1], rax
    mov     rdi, 1
    call    Circle_new
    mov     [obj_c2], rax
    mov     rdi, 4
    mov     rsi, 5
    call    Rect_new
    mov     [obj_r1], rax

    call    panel_layout
    call    panel_sharing
    call    panel_swizzle

    mov     rdi, [obj_c1]
    ccall   free
    mov     rdi, [obj_c2]
    ccall   free
    mov     rdi, [obj_r1]
    ccall   free
    call    viz_close

    xor     eax, eax
    epilogue
