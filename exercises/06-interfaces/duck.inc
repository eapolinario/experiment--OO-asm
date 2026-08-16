;; duck.inc - the layout and published symbols of class Duck.
;;
;; Duck implements two independent interfaces, Swimmer and Quacker. Neither
;; knows about the other; a Swimmer client and a Quacker client are written
;; and (here) assembled without ever seeing Duck. What they share with Duck is
;; only the slot numbering of their own interface - and, for the second
;; interface, the fact that the object model will hand back a pointer that has
;; been shifted by DUCK_K bytes.

%ifndef DUCK_INC
%define DUCK_INC

%include "mi_object.inc"

; ---------------------------------------------------------------------------
; The complete object. The two vptrs cannot share offset 0, so the primary
; interface (Swimmer) takes offset 0 and the secondary (Quacker) takes offset
; DUCK_K. A field sits between and after them precisely so that a method which
; only receives the Quacker subobject pointer must adjust to reach them.
; ---------------------------------------------------------------------------
struc Duck
    .swimmer_vptr:  resq 1          ; +0   primary interface subobject
    .name:          resq 1          ; +8   complete-object field
    .quacker_vptr:  resq 1          ; +16  secondary interface subobject
    .volume:        resq 1          ; +24  complete-object field
endstruc

%define DUCK_K          Duck.quacker_vptr       ; 16: where the Quacker subobject begins

; Each interface numbers its own slots from 0; the vptr disambiguates them.
%define SWIMMER_SWIM    0
%define QUACKER_QUACK   0

; ---------------------------------------------------------------------------
; A Go-style interface value's itable: the concrete type followed by the method
; pointers. A fat interface pointer is (data, *itab); this is the *itab half.
; ---------------------------------------------------------------------------
struc Itab
    .type:          resq 1          ; *concrete type (Class*), as Go's itab.itype
    .quack:         resq 1          ; method 0
endstruc

extern Duck_new                     ; Duck *Duck_new(const char *name, long volume)

extern Duck_swimmer_vtable          ; primary vtable
extern Duck_quacker_vtable          ; secondary vtable (its quack slot is a thunk)
extern Duck_as_quacker_itab         ; the fat-pointer itable for Duck-as-Quacker

extern Duck_quack                   ; the real method body (rdi = complete Duck*)
extern Duck_quack_thunk             ; the adjustor thunk (rdi = Quacker subobject)
extern Duck_class

%endif ; DUCK_INC
