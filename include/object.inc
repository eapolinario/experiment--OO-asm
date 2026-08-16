;; object.inc - the object model shared by the exercises.
;;
;;   object                    vtable                   class descriptor
;;   +--------------+          +---------------+        +--------------+
;;   | vptr         |--------->| class         |------->| name         |
;;   +--------------+          +---------------+        | size         |
;;   | field 0      |          | slot 0        |        | parent       |
;;   | field 1      |          | slot 1        |        +--------------+
;;   | ...          |          | ...           |
;;   +--------------+          +---------------+
;;
;; Three rules, and everything else in this repo follows from them:
;;
;;   1. The vptr sits at offset 0 of every polymorphic object. Code that only
;;      needs to *dispatch* can therefore treat every object identically,
;;      without knowing its type.
;;   2. A vtable is per-class and immutable. A thousand instances cost a
;;      thousand 8-byte vptrs, not a thousand copies of the method table.
;;   3. Slot numbers are ABI. A subclass may append slots, or overwrite the
;;      pointer in an inherited slot, but must never reorder them - that is
;;      exactly what makes `call [vtable + 8*n]` work on a value whose real
;;      class the caller has never heard of.
;;
;; Exercise 06 (interfaces / multiple inheritance) extends this layout with an
;; offset-to-top field and defines its own header; see docs/04-interfaces.md
;; for why a second base class forces the change.

%ifndef OBJECT_INC
%define OBJECT_INC

struc Object
    .vptr:      resq 1
endstruc

%define VT_CLASS        0                       ; vtable[0]   = Class*
%define VT_SLOT(n)      (8 + 8*(n))             ; vtable[1+n] = method n

struc Class
    .name:      resq 1                          ; const char*
    .size:      resq 1                          ; sizeof(instance) in bytes
    .parent:    resq 1                          ; Class* of base, or NULL
endstruc

;; vcall slot
;;   Dynamic dispatch on a receiver already in rdi. Two loads and an indirect
;;   call - the entire cost of "virtual" in any language. Clobbers rax.
%macro vcall 1
    mov     rax, [rdi + Object.vptr]
    call    [rax + VT_SLOT(%1)]
%endmacro

;; vcall_on receiver, slot
;;   Same, but loads the receiver into rdi first.
%macro vcall_on 2
    mov     rdi, %1
    mov     rax, [rdi + Object.vptr]
    call    [rax + VT_SLOT(%2)]
%endmacro

;; class_of dst, obj
;;   dst = obj->vptr->class. Safe when dst and obj are the same register.
%macro class_of 2
    mov     %1, [%2 + Object.vptr]
    mov     %1, [%1 + VT_CLASS]
%endmacro

%endif ; OBJECT_INC
