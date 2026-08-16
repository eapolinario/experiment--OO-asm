;; stack.inc - the *public* interface of class Stack.
;;
;; This is the header a client is allowed to see. Notice what is missing: the
;; field offsets. A client can declare storage for a Stack and can call its
;; methods, but cannot reach inside one, because nothing here says where `len`
;; lives - or even that a field called `len` exists.
;;
;; That is encapsulation, and it needs no language support whatsoever. It is a
;; published size, a published vocabulary, and the discipline to publish
;; nothing else.

%ifndef STACK_INC
%define STACK_INC

; Opaque size. The client allocates this many bytes; stack.asm asserts at
; assembly time that the number still matches the real layout. This is exactly
; the trick C uses for `pthread_mutex_t` and C++ for a pimpl'd class.
%define STACK_SIZEOF    80

; Method vocabulary. The `Stack_` prefix is our name mangling: the assembler
; has one flat namespace, so the class name has to be part of the symbol.
; Python does the same thing to any attribute named __x inside class C: it is
; stored as _C__x, for exactly this reason.
extern Stack_init                       ; void  Stack_init(Stack *this)
extern Stack_push                       ; long  Stack_push(Stack *this, long v)
extern Stack_pop                        ; long  Stack_pop(Stack *this, long *out)
extern Stack_depth                      ; long  Stack_depth(const Stack *this)
extern Stack_peek                       ; long  Stack_peek(const Stack *this)
extern Stack_capacity                   ; long  Stack_capacity(const Stack *this)

%endif ; STACK_INC
