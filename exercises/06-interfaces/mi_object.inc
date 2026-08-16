;; mi_object.inc - the object model, extended for multiple inheritance.
;;
;; The single-inheritance model in include/object.inc puts one vptr at offset 0
;; and is done. It cannot describe an object that IS two unrelated base classes
;; at once, because both bases want to be the thing a `Base*` points at, and
;; only one of them can sit at offset 0. So a class with two interfaces carries
;; two vptrs, at two different offsets, pointing at two different vtables - and
;; the vtable has to grow one field, because a method reached through the
;; second vptr is handed a pointer into the *middle* of the object and has to
;; find its way back to the top.
;;
;;   complete Duck object          primary vtable (Swimmer)
;;   +------------------+          +------------------+
;;   | swimmer_vptr  +0 |--------->| offset_to_top: 0 |
;;   | name          +8 |          | Class*           |
;;   | quacker_vptr +16 |---+      | swim             |
;;   | volume       +24 |   |      +------------------+
;;   +------------------+   |      secondary vtable (Quacker)
;;                          |      +-------------------+
;;                          +----->| offset_to_top: 16 |
;;                                 | Class*            |
;;                                 | quack (a thunk)   |
;;                                 +-------------------+
;;
;; Extended layout, the two-word header a C++ vtable actually carries:
;;
;;   vtable + 0    offset_to_top   bytes to SUBTRACT from a subobject pointer to
;;                                 reach the complete object (0 for the primary)
;;   vtable + 8    Class*          the run-time type (shared by all subobjects)
;;   vtable + 16   slot 0, then 8 bytes per slot
;;
;; (The Itanium C++ ABI stores offset_to_top as a signed number it ADDs, so a
;; secondary base holds -16. We store the non-negative amount to subtract,
;; which reads more directly; the arithmetic is otherwise identical.)

%ifndef MI_OBJECT_INC
%define MI_OBJECT_INC

%include "object.inc"                   ; reuse struc Object and struc Class

%define MI_VT_OFFSET_TO_TOP     0
%define MI_VT_CLASS             8
%define MI_VT_SLOT(n)           (16 + 8*(n))

;; mi_vcall slot
;;   Dispatch on whatever subobject rdi points at. Identical to the single-
;;   inheritance vcall except the slot base is 16, because two header words now
;;   precede the methods. The receiver must already be the right subobject
;;   pointer: an interface pointer, not necessarily the complete object.
%macro mi_vcall 1
    mov     rax, [rdi + Object.vptr]
    call    [rax + MI_VT_SLOT(%1)]
%endmacro

;; mi_class_of dst, obj
;;   dst = obj->vptr->class. Works from any subobject: every vtable of the same
;;   object points at the same Class descriptor.
%macro mi_class_of 2
    mov     %1, [%2 + Object.vptr]
    mov     %1, [%1 + MI_VT_CLASS]
%endmacro

;; mi_to_top dst, iface
;;   dst = the complete-object pointer for the subobject `iface` points at, by
;;   reading offset_to_top out of its vtable and subtracting. This is exactly
;;   what `dynamic_cast<void*>` computes. dst must be a different register from
;;   iface (iface is read after dst is first written).
%macro mi_to_top 2
    mov     %1, [%2 + Object.vptr]
    mov     %1, [%1 + MI_VT_OFFSET_TO_TOP]
    neg     %1
    add     %1, %2
%endmacro

%endif ; MI_OBJECT_INC
