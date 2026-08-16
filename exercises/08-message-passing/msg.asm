;; msg.asm - the message runtime: interning, lookup, dispatch, caches.
;;
;; This is the analogue of Apple's objc runtime or the CPython eval loop's
;; attribute machinery. It knows nothing about Animals or Dogs; it knows how to
;; intern a name, walk a class chain for a selector, call what it finds, cache
;; the result, and - when nothing is found - forward or complain instead of
;; crashing.

%include "abi.inc"
%include "libc.inc"
%include "msg.inc"

; ---------------------------------------------------------------------------
section .rodata
str_forwarding: db "forwardingTarget", 0
fmt_dnu:        db "  [doesNotUnderstand] a %s received '%s'", 10, 0
fmt_counters:   db "    inline-cache hits=%ld misses=%ld | class-cache hits=%ld misses=%ld", 10, 0

; ---------------------------------------------------------------------------
section .bss
align 8
INTERN_MAX      equ 64
intern_strs:    resq INTERN_MAX                 ; canonical spellings, first-come
intern_count:   resq 1
sel_forwarding: resq 1                          ; the SEL the dispatcher forwards through

mcache_hits:    resq 1
mcache_misses:  resq 1
icache_hits:    resq 1
icache_misses:  resq 1

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; Sel intern(const char *s)
;
; Return the one canonical pointer for this spelling. The first time a spelling
; is seen it becomes its own canonical form; later spellings that strcmp-equal
; it collapse to that same pointer. The strcmp cost is paid here, once per new
; name - never again on the dispatch path, which is the whole point of a SEL.
; ---------------------------------------------------------------------------
global intern
intern:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; s
    mov     r12, [intern_count]
    xor     r13, r13                    ; i = 0
.loop:
    cmp     r13, r12
    jae     .add
    lea     rax, [intern_strs]
    mov     r14, [rax + r13*8]          ; existing canonical spelling
    mov     rdi, rbx
    mov     rsi, r14
    ccall   strcmp
    test    eax, eax
    jz      .hit
    inc     r13
    jmp     .loop
.hit:
    mov     rax, r14
    jmp     .done
.add:
    lea     rax, [intern_strs]
    mov     [rax + r12*8], rbx          ; this spelling becomes canonical
    inc     qword [intern_count]
    mov     rax, rbx
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void runtime_init(void)
;
; Intern the one selector the dispatcher itself needs: forwardingTarget, the
; message it sends an object to ask "who should handle what you cannot?".
; ---------------------------------------------------------------------------
global runtime_init
runtime_init:
    prologue
    lea     rdi, [str_forwarding]
    call    intern
    mov     [sel_forwarding], rax
    epilogue

; ---------------------------------------------------------------------------
; void class_init(MpClass *c, const char *name, MpClass *super)
; ---------------------------------------------------------------------------
global class_init
class_init:
    mov     [rdi + MpClass.name], rsi
    mov     [rdi + MpClass.super], rdx
    mov     qword [rdi + MpClass.n_methods], 0
    mov     qword [rdi + MpClass.cache_sel], 0
    mov     qword [rdi + MpClass.cache_impl], 0
    ret

; ---------------------------------------------------------------------------
; void class_add_method(MpClass *c, Sel sel, void *imp)
;
; Append a row to the class's method list and drop its cache, because a new
; row can shadow whatever the cache last resolved. Objective-C flushes method
; caches on exactly this event (class_addMethod / method swizzling).
; ---------------------------------------------------------------------------
global class_add_method
class_add_method:
    mov     rax, [rdi + MpClass.n_methods]
    cmp     rax, MP_MAX_METHODS
    jae     .full                       ; demo never overflows; ignore if it did
    imul    rcx, rax, Method_size
    lea     r8, [rdi + MpClass.methods]
    add     r8, rcx                     ; &methods[n]
    mov     [r8 + Method.sel], rsi
    mov     [r8 + Method.impl], rdx
    inc     qword [rdi + MpClass.n_methods]
    mov     qword [rdi + MpClass.cache_sel], 0      ; invalidate the cache
.full:
    ret

; ---------------------------------------------------------------------------
; void class_flush(MpClass *c)          ; drop the one-entry method cache
; ---------------------------------------------------------------------------
global class_flush
class_flush:
    mov     qword [rdi + MpClass.cache_sel], 0
    ret

; ---------------------------------------------------------------------------
; void *resolve(MpClass *cls0, Sel sel)         -> IMP, or NULL if not found
;
; The heart of it. First consult cls0's one-entry cache. On a miss, walk from
; cls0 up the .super chain, scanning each class's method list, comparing
; selectors by *pointer* (they are interned). The first match wins - which is
; how an override in a subclass shadows the parent - and is written back into
; cls0's cache so the next identical send is a single compare.
;
; A leaf function: it calls nothing, so it needs no frame. rdi (cls0) and rsi
; (sel) survive untouched for the caller.
; ---------------------------------------------------------------------------
resolve:
    mov     rax, [rdi + MpClass.cache_sel]
    cmp     rax, rsi
    jne     .cold
    inc     qword [mcache_hits]
    mov     rax, [rdi + MpClass.cache_impl]
    ret
.cold:
    inc     qword [mcache_misses]
    mov     r8, rdi                     ; cur = cls0
.walk:
    test    r8, r8
    jz      .notfound
    mov     rcx, [r8 + MpClass.n_methods]
    lea     rdx, [r8 + MpClass.methods] ; cursor over this class's rows
.scan:
    test    rcx, rcx
    jz      .up
    mov     rax, [rdx + Method.sel]
    cmp     rax, rsi                    ; pointer compare, never strcmp
    je      .found
    add     rdx, Method_size
    dec     rcx
    jmp     .scan
.up:
    mov     r8, [r8 + MpClass.super]
    jmp     .walk
.found:
    mov     rax, [rdx + Method.impl]
    mov     [rdi + MpClass.cache_sel], rsi      ; cache on the *starting* class
    mov     [rdi + MpClass.cache_impl], rax
    ret
.notfound:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; long msg_send(MpObject *recv, Sel sel, long arg)
;
; Resolve sel against recv's class; if found, tail into the IMP with the
; Objective-C argument shape self=rdi, _cmd=rsi, arg=rdx. If not found, ask the
; receiver for a forwardingTarget and, if it names one, re-send there (the
; proxy pattern, implemented in the dispatcher, not the class). If even that
; fails, hand off to doesNotUnderstand - which prints and returns, so an
; unknown selector is a diagnostic, never a crash.
; ---------------------------------------------------------------------------
global msg_send
msg_send:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; recv
    mov     r12, rsi                    ; sel
    mov     r13, rdx                    ; arg

    mov     rdi, [rbx + MpObject.isa]
    mov     rsi, r12
    call    resolve
    test    rax, rax
    jz      .forward

    mov     r14, rax                    ; IMP
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    r14
    jmp     .done

.forward:
    mov     rdi, [rbx + MpObject.isa]
    mov     rsi, [sel_forwarding]
    call    resolve                     ; does this class name a delegate?
    test    rax, rax
    jz      .dnu

    mov     r14, rax
    mov     rdi, rbx
    mov     rsi, [sel_forwarding]
    xor     edx, edx
    call    r14                         ; delegate = recv.forwardingTarget
    test    rax, rax
    jz      .dnu
    cmp     rax, rbx                    ; a self-referential delegate would loop
    je      .dnu

    mov     rdi, rax                    ; forward the ORIGINAL selector onward
    mov     rsi, r12
    mov     rdx, r13
    call    msg_send
    jmp     .done

.dnu:
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    does_not_understand

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; long does_not_understand(MpObject *recv, Sel sel, long arg)
;
; The safety net. Smalltalk calls it doesNotUnderstand:, Ruby method_missing,
; Python __getattr__/__getattr__. We print the class and the selector (a SEL is
; just its string) and return 0. The send completed; the object simply had
; nothing to say.
; ---------------------------------------------------------------------------
does_not_understand:
    prologue
    mov     rax, [rdi + MpObject.isa]
    mov     rdx, rsi                    ; the selector prints as its own text
    mov     rsi, [rax + MpClass.name]
    lea     rdi, [fmt_dnu]
    xor     eax, eax
    ccall   printf
    xor     eax, eax
    epilogue

; ---------------------------------------------------------------------------
; long send_cached(InlineCache *site, MpObject *recv, Sel sel, long arg)
;
; A send guarded by a per-call-site monomorphic inline cache. If recv's class
; equals the class this site saw last, reuse the cached IMP - one compare, no
; lookup. Otherwise resolve, remember (class -> IMP) for next time, and call.
; Unresolved selectors bypass the cache and fall through to the full msg_send
; so forwarding and doesNotUnderstand still apply.
; ---------------------------------------------------------------------------
global send_cached
send_cached:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; site
    mov     r12, rsi                    ; recv
    mov     r13, rdx                    ; sel
    mov     r14, rcx                    ; arg

    mov     rax, [r12 + MpObject.isa]
    cmp     rax, [rbx + InlineCache.cls]
    jne     .cold
    inc     qword [icache_hits]
    mov     rax, [rbx + InlineCache.impl]
    jmp     .call

.cold:
    inc     qword [icache_misses]
    mov     rdi, [r12 + MpObject.isa]
    mov     rsi, r13
    call    resolve
    test    rax, rax
    jz      .fallback                   ; do not cache a miss
    mov     rcx, [r12 + MpObject.isa]
    mov     [rbx + InlineCache.cls], rcx
    mov     [rbx + InlineCache.impl], rax

.call:
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    call    rax
    jmp     .done

.fallback:
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r14
    call    msg_send

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Instrumentation.
; ---------------------------------------------------------------------------
global counters_reset
counters_reset:
    mov     qword [mcache_hits], 0
    mov     qword [mcache_misses], 0
    mov     qword [icache_hits], 0
    mov     qword [icache_misses], 0
    ret

global report_counters
report_counters:
    prologue
    mov     r8, [mcache_misses]
    mov     rcx, [mcache_hits]
    mov     rdx, [icache_misses]
    mov     rsi, [icache_hits]
    lea     rdi, [fmt_counters]
    xor     eax, eax
    ccall   printf
    epilogue
