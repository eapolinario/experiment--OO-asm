;; rtti.inc - a tiny runtime type information "runtime", separate from the
;; classes that use it.
;;
;; This split is deliberate. In C++ the machinery below is not in your program
;; at all: `typeid` and `dynamic_cast` are serviced by functions the compiler
;; links in from libstdc++ (`__dynamic_cast`) plus per-class `__class_type_info`
;; records the compiler emits next to each vtable. Your classes only supply the
;; metadata; the runtime does the walking. rtti.asm is that runtime; stream.asm
;; supplies the metadata.

%ifndef RTTI_INC
%define RTTI_INC

%include "object.inc"

; The deepest chain we build is Stream <- FileStream <- CompressedFileStream,
; i.e. depth 2, so a four-slot display leaves headroom. A real VM sizes this
; per class; a fixed maximum keeps the assembly readable.
%define RTTI_MAX_DEPTH 4

;; RttiClass - an extended class descriptor.
;;
;; The first three fields are laid out byte-for-byte like object.inc's `Class`,
;; on purpose: object.inc's `class_of` and every `[c + Class.name]` keep
;; working unchanged, because .name/.size/.parent sit at the same offsets. We
;; only append the two fields Cohen's constant-time subtype test needs:
;;
;;   .depth    length of the parent chain (a root class is depth 0)
;;   .display  display[k] = this class's ancestor at depth k, for k in 0..depth.
;;             By construction display[depth] is the class itself. This is the
;;             "display" of Cohen (1991); Java HotSpot and others ship it so
;;             that `instanceof` against a class is O(1) instead of O(depth).
struc RttiClass
    .name:      resq 1
    .size:      resq 1
    .parent:    resq 1
    .depth:     resq 1
    .display:   resq RTTI_MAX_DEPTH
endstruc

; const char *type_name(Object *obj)
;   The object's most-derived class name, read straight out of its vtable.
extern type_name

; long is_a_slow(Object *obj, RttiClass *target)
;   Subtype test by walking the .parent chain. O(depth).
extern is_a_slow

; long is_a_fast(Object *obj, RttiClass *target)
;   The same answer via Cohen's display. O(1): one bounds check, one compare.
extern is_a_fast

; void *dynamic_cast(Object *obj, RttiClass *target)
;   Checked downcast: obj if obj is-a target, else NULL.
extern dynamic_cast

%endif ; RTTI_INC
