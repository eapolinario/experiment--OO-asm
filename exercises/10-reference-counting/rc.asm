;; rc.asm - the reference-counting runtime and its instrumented allocator.
;;
;; Two counters make lifetime auditable instead of assumed, exactly as in
;; exercise 03:
;;
;;   live_objects   counted objects constructed minus destroyed
;;   live_blocks    heap blocks malloc'd minus freed (objects AND weak cells)
;;
;; A correct program ends with both at zero. A leak - including the cycle in
;; the demo - shows up as a non-zero count rather than as a claim in prose.

%include "abi.inc"
%include "libc.inc"
%include "rc.inc"

section .rodata
msg_oom:        db "rc: out of memory", 10, 0
msg_overrel:    db "rc: release() on an object whose refcount is already 0", 10, 0

section .bss
align 8
live_objects:   resq 1
live_blocks:    resq 1

section .text

; ---------------------------------------------------------------------------
; void *rc_mem_alloc(long bytes)   -- one counted heap block.
; ---------------------------------------------------------------------------
global rc_mem_alloc
rc_mem_alloc:
    prologue
    ccall   malloc
    test    rax, rax
    jz      .oom
    inc     qword [live_blocks]
    epilogue
.oom:
    lea     rdi, [msg_oom]
    xor     eax, eax
    ccall   printf
    ccall   abort

; ---------------------------------------------------------------------------
; void rc_mem_free(void *p)        -- free(NULL) is a no-op.
; ---------------------------------------------------------------------------
global rc_mem_free
rc_mem_free:
    prologue
    test    rdi, rdi
    jz      .done
    dec     qword [live_blocks]
    ccall   free
.done:
    epilogue

; ---------------------------------------------------------------------------
; void *rc_alloc(long bytes, void *vtable)
;
; Allocate a block, install its vtable, and hand it back with refcount 1: the
; single reference now owned by whoever called rc_alloc. "Born owning one
; reference" is the convention CPython (tp_alloc), ARC (+1 from alloc/init) and
; shared_ptr's make_shared all share.
; ---------------------------------------------------------------------------
global rc_alloc
rc_alloc:
    prologue
    push    rbx
    push    r12
    mov     r12, rsi                    ; vtable (rdi = bytes stays put)
    call    rc_mem_alloc
    mov     rbx, rax
    mov     [rbx + Rc.vptr], r12
    mov     qword [rbx + Rc.refs], 1
    inc     qword [live_objects]
    mov     rax, rbx
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void rc_retain(void *obj)        -- one more owner. Non-atomic on purpose.
;
; A plain `inc`. That is the whole reason a non-atomic refcount is cheap and a
; thread-safe one is not: make this a `lock inc` (an atomic RMW with a memory
; barrier) and every retain/release becomes an uncontended-but-still-serialised
; bus operation. This single distinction is why Rust splits `Rc` (this) from
; `Arc` (the `lock`-prefixed version), and why Swift's ARC pays for atomics.
; ---------------------------------------------------------------------------
global rc_retain
rc_retain:
    test    rdi, rdi
    jz      .done
    inc     qword [rdi + Rc.refs]
.done:
    ret

; ---------------------------------------------------------------------------
; void rc_release(void *obj)
;
; Drop one reference. If it was the last, run the destructor (which releases
; whatever this object owns, possibly cascading) and then reclaim the storage.
; Note the split, identical to exercise 03's destruct-then-deallocate: the
; virtual dtor tears down the object's *contents*; rc_release frees the object
; *itself*. Destruction here is immediate and deterministic - the instant the
; count reaches zero - which is exactly what lets refcounting drive RAII and
; `with`-blocks, where a tracing GC could only promise "eventually".
; ---------------------------------------------------------------------------
global rc_release
rc_release:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    test    rbx, rbx
    jz      .done                       ; release(NULL) is a no-op
    mov     rax, [rbx + Rc.refs]
    test    rax, rax
    jz      .overrelease                ; refcount already 0: a double free
    dec     rax
    mov     [rbx + Rc.refs], rax
    jnz     .done                       ; still referenced by someone
    ; last reference gone: destruct, then deallocate
    mov     rdi, rbx
    vcall   RC_DTOR                     ; virtual: run the object's destructor
    dec     qword [live_objects]
    mov     rdi, rbx
    call    rc_mem_free
.done:
    pop     r12
    pop     rbx
    epilogue
.overrelease:
    lea     rdi, [msg_overrel]
    xor     eax, eax
    ccall   printf
    ccall   abort

; ---------------------------------------------------------------------------
; Accessors.
; ---------------------------------------------------------------------------
global rc_refs
rc_refs:
    mov     rax, [rdi + Rc.refs]
    ret

global rc_live_objects
rc_live_objects:
    mov     rax, [live_objects]
    ret

global rc_live_blocks
rc_live_blocks:
    mov     rax, [live_blocks]
    ret
