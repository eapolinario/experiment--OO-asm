;; stack.asm - the implementation of class Stack.
;;
;; Everything about the representation lives in this file and leaves no trace
;; in the client. The only symbols exported are the six methods; the layout,
;; the capacity constant and the internal helpers stay private simply because
;; they are never declared `global`. The linker enforces that for us: a client
;; that tries to reach `Stack.len` or call an internal helper does not link.

%include "abi.inc"
%include "libc.inc"
%include "stack.inc"

; ---------------------------------------------------------------------------
; Private representation. Nobody outside this file knows these offsets.
; ---------------------------------------------------------------------------
STACK_CAPACITY  equ 8

struc Stack
    .len:       resq 1
    .cap:       resq 1
    .items:     resq STACK_CAPACITY
endstruc

; The published size must match reality, or a client would under-allocate and
; every method would scribble past the end of its buffer. Check it now, at
; assembly time, rather than at 3am.
%if Stack_size != STACK_SIZEOF
    %error "STACK_SIZEOF in stack.inc disagrees with struc Stack"
%endif

;; assert_invariant
;;   0 <= this->len <= this->cap, checked inline. The failure path is a call to
;;   an out-of-line, no-return handler, so the common case costs one compare
;;   and one perfectly-predicted branch.
%macro assert_invariant 0
    mov     rax, [rdi + Stack.len]
    cmp     rax, [rdi + Stack.cap]
    jbe     %%ok
    call    stack_invariant_failed
%%ok:
%endmacro

section .rodata
msg_corrupt:    db "Stack invariant violated: len=%ld cap=%ld", 10, 0

section .text

; ---------------------------------------------------------------------------
; void Stack_init(Stack *this)
;
; The constructor's whole job is to make the invariant true. Every other
; method may then assume it, and must leave it true on the way out.
; ---------------------------------------------------------------------------
global Stack_init
Stack_init:
    mov     qword [rdi + Stack.len], 0
    mov     qword [rdi + Stack.cap], STACK_CAPACITY
    ret

; ---------------------------------------------------------------------------
; long Stack_push(Stack *this, long value)   -> 1 on success, 0 if full
;
; The bounds check lives here, once, instead of at every call site. That is
; the practical argument for encapsulation: an invariant enforced in one place
; cannot be forgotten in another.
; ---------------------------------------------------------------------------
global Stack_push
Stack_push:
    assert_invariant
    mov     rax, [rdi + Stack.len]
    cmp     rax, [rdi + Stack.cap]
    jae     .full
    mov     [rdi + Stack.items + rax*8], rsi
    inc     rax
    mov     [rdi + Stack.len], rax
    mov     eax, 1
    ret
.full:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; long Stack_pop(Stack *this, long *out)     -> 1 on success, 0 if empty
; ---------------------------------------------------------------------------
global Stack_pop
Stack_pop:
    assert_invariant
    mov     rax, [rdi + Stack.len]
    test    rax, rax
    jz      .empty
    dec     rax
    mov     [rdi + Stack.len], rax
    mov     rcx, [rdi + Stack.items + rax*8]
    mov     [rsi], rcx
    mov     eax, 1
    ret
.empty:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; Const methods: they read the receiver and never write through it. In C++
; `const` makes the compiler check that promise; here it is a comment plus the
; discipline to keep it. The machine code is identical either way.
; ---------------------------------------------------------------------------
global Stack_depth
Stack_depth:
    mov     rax, [rdi + Stack.len]
    ret

global Stack_capacity
Stack_capacity:
    mov     rax, [rdi + Stack.cap]
    ret

; long Stack_peek(const Stack *this)  -> top value, or 0 when empty
global Stack_peek
Stack_peek:
    mov     rax, [rdi + Stack.len]
    test    rax, rax
    jz      .empty
    dec     rax
    mov     rax, [rdi + Stack.items + rax*8]
    ret
.empty:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; Private, and never coming back. Not `global`, so main.asm cannot call it -
; try it and read the linker error.
; ---------------------------------------------------------------------------
stack_invariant_failed:
    and     rsp, -16                    ; force alignment; we do not return
    mov     rdx, [rdi + Stack.cap]
    mov     rsi, [rdi + Stack.len]
    lea     rdi, [msg_corrupt]
    xor     eax, eax
    ccall   printf
    ccall   abort
