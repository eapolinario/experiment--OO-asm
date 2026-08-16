;; rtti.asm - the RTTI runtime: name lookup, subtype tests, checked downcast.
;;
;; None of these functions know a single class by name. They operate purely on
;; the metadata reachable from an object: vptr -> Class* -> {name, parent,
;; depth, display}. That is the whole point of RTTI - one runtime that answers
;; "what are you?" for classes it was assembled before, exactly as libstdc++'s
;; __dynamic_cast handles types the standard library never heard of.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "rtti.inc"

section .text

; ---------------------------------------------------------------------------
; const char *type_name(Object *obj)
;
; Follow the vptr to the class descriptor and read its name. The caller may
; hold nothing but a base pointer; the object still reports its most-derived
; type, because its constructor stamped the derived vtable into offset 0. This
; is precisely what `typeid(x).name()` lowers to: a load of the type_info the
; vtable points at, then a field read.
; ---------------------------------------------------------------------------
global type_name
type_name:
    class_of rax, rdi                   ; rax = obj->vptr->class
    mov     rax, [rax + RttiClass.name]
    ret

; ---------------------------------------------------------------------------
; long is_a_slow(Object *obj, RttiClass *target)  -> 1 if obj is-a target
;
; The textbook implementation: begin at the object's dynamic class and walk
; the .parent chain toward the root, comparing against target at every step.
; The cost is O(depth of the hierarchy). This is what a naive dynamic_cast
; does, and what the JVM's `instanceof` does before it caches the result at the
; call site.
; ---------------------------------------------------------------------------
global is_a_slow
is_a_slow:
    class_of rax, rdi                   ; rax = current = class_of(obj)
.loop:
    test    rax, rax
    jz      .no                         ; ran off the root: not a subtype
    cmp     rax, rsi
    je      .yes
    mov     rax, [rax + RttiClass.parent]
    jmp     .loop
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; long is_a_fast(Object *obj, RttiClass *target)  -> 1 if obj is-a target
;
; Cohen's algorithm. Because each class caches its depth and the array of its
; own ancestors indexed by depth, the entire question collapses to:
;
;     target.depth <= class_of(obj).depth   AND
;     class_of(obj).display[target.depth] == target
;
; No loop, no matter how deep the hierarchy: one bounds check, one indexed
; load, one compare. The bounds check is not just for memory safety - if the
; target sits deeper than the object's class, the object cannot possibly be a
; subtype of it, so the answer is a definite no.
; ---------------------------------------------------------------------------
global is_a_fast
is_a_fast:
    class_of rax, rdi                   ; rax = C = class_of(obj)
    mov     rcx, [rsi + RttiClass.depth]        ; d = target.depth
    cmp     rcx, [rax + RttiClass.depth]        ; d > C.depth ?
    ja      .no                                 ; target is deeper: cannot be an ancestor
    mov     rax, [rax + RttiClass.display + rcx*8]   ; C.display[d]
    cmp     rax, rsi
    je      .yes
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; ---------------------------------------------------------------------------
; void *dynamic_cast(Object *obj, RttiClass *target)
;
; The checked downcast. Returns obj when obj is-a target, otherwise NULL. The
; caller is expected to test that NULL - it is the entire difference between a
; checked cast and a hopeful one.
;
; Contrast the unchecked cast, C++'s static_cast<Derived*>(base): that is just
; a `mov`, a reinterpretation with the test deleted. When you are right it is
; free; when you are wrong you now hold a pointer of the wrong type and the
; next virtual call reads a garbage vtable slot. dynamic_cast is this function
; (it bottoms out in libstdc++'s __dynamic_cast); static_cast is the same
; `mov` with is_a assumed rather than verified.
;
; We route the check through is_a_fast; the program also runs is_a_slow beside
; it and proves the two never disagree.
; ---------------------------------------------------------------------------
global dynamic_cast
dynamic_cast:
    prologue
    push    rbx
    push    r12                         ; pushed in a pair to keep rsp aligned
    mov     rbx, rdi                    ; remember obj across the call
    call    is_a_fast                   ; (obj still in rdi, target still in rsi)
    test    rax, rax
    jz      .fail
    mov     rax, rbx                    ; hit: the pointer is safe to narrow
    jmp     .done
.fail:
    xor     eax, eax                    ; miss: NULL, and the caller must notice
.done:
    pop     r12
    pop     rbx
    epilogue
