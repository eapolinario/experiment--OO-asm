;; 08 - Message passing: dispatch by name, resolved at run time.
;;
;; Exercise 04 chose a method with a slot number fixed at assembly time. Here
;; main.asm names methods with *strings* and the runtime finds them while the
;; program runs. That one change buys everything Smalltalk, Objective-C, Ruby
;; and Python are built on: methods you can add after the fact, a receiver that
;; can refuse a message without crashing, an object that forwards what it does
;; not handle - and, because name lookup is not free, caches to make it cheap.

%include "abi.inc"
%include "libc.inc"
%include "msg.inc"

; -- the zoo (see zoo.asm) ---------------------------------------------------
extern setup
extern Animal_new
extern Dog_new
extern Cat_new
extern Proxy_new
extern Dog_fetch
extern Dog_class
extern Cat_class
extern sel_speak
extern sel_legs
extern sel_describe
extern sel_fetch
extern sel_quack

section .rodata
hdr:            db "== 08 | message passing: dispatch by name, resolved at run time ==", 0

sec_intern:     db 10, "Selectors intern, so selector equality is a pointer compare:", 10, 0
sec_dispatch:   db 10, "Dispatch by name walks the class chain:", 10, 0
sec_runtime:    db 10, "Runtime extension: existing objects gain a method instantly:", 10, 0
sec_dnu:        db 10, "Unknown selectors are handled, not fatal:", 10, 0
sec_forward:    db 10, "Forwarding: a Proxy answers by delegating to the object it holds:", 10, 0
sec_cache:      db 10, "Method caches turn a chain walk into a compare:", 10, 0

fmt_fact:       db "  %-40s %s", 10, 0
q_same:         db `intern("speak") twice -> one selector`, 0
q_diff:         db `intern("speak") vs intern("purr")`, 0
str_speak_a:    db "speak", 0                   ; two independent spellings of the
str_speak_b:    db "speak", 0                   ; same name, at different addresses
str_purr:       db "purr", 0

note_inherit:   db "  describe lives only on Animal; Dog and Cat inherit it up the chain", 10, 0
note_override:  db "  speak is overridden on Dog and Cat, shadowing Animal's version", 10, 0

lbl_before:     db "  before it exists, the message bounces:", 10, 0
lbl_add:        db `  ... class_add_method(Dog, "fetch", Dog_fetch) ...`, 10, 0
lbl_after:      db "  after adding it, the same Rex responds:", 10, 0
fmt_named:      db "  %s %s", 10, 0

fmt_forward:    db "  proxy forwards '%s' -> %s", 10, 0
note_fwd_dnu:   db "  proxy forwarded 'quack' to its Dog, which did not understand it either", 10, 0

lbl_mono:       db "  monomorphic 6x 'legs' (one class, so the class never changes):", 10, 0
lbl_poly:       db "  polymorphic  6x 'legs' (two classes, alternating every send):", 10, 0
note_cache:     db "  the inline cache hits while the class is stable and misses when it alternates;", 10, 0
note_cache2:    db "  the per-class cache still absorbs the alternating case after warm-up", 10, 0

s_yes:          db "yes", 0
s_no:           db "no", 0

section .bss
align 8
obj_critter:    resq 1
obj_dog:        resq 1
obj_cat:        resq 1
obj_proxy:      resq 1
poly:           resq 6
siteM:          resb InlineCache_size
siteP:          resb InlineCache_size

section .text

; const char *yesno(long cond)
yesno:
    lea     rax, [s_no]
    lea     rcx, [s_yes]
    test    rdi, rdi
    cmovnz  rax, rcx
    ret

; void fact(const char *question, long cond)
fact:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rsi
    call    yesno
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_fact]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14

    lea     rdi, [hdr]
    ccall   puts

    call    runtime_init                ; the runtime interns forwardingTarget
    call    setup                       ; the app interns its selectors, builds classes

    ; -- interning: two spellings, one selector ------------------------------
    lea     rdi, [sec_intern]
    ccall   printf

    lea     rdi, [str_speak_a]
    call    intern
    mov     rbx, rax                    ; SEL from spelling A
    lea     rdi, [str_speak_b]
    call    intern
    mov     r12, rax                    ; SEL from spelling B
    lea     rdi, [str_purr]
    call    intern
    mov     r13, rax                    ; SEL for a different name

    cmp     rbx, r12
    sete    sil
    movzx   rsi, sil
    lea     rdi, [q_same]
    call    fact
    cmp     rbx, r13
    sete    sil
    movzx   rsi, sil
    lea     rdi, [q_diff]
    call    fact

    ; -- build the objects ---------------------------------------------------
    lea     rdi, [n_critter]
    call    Animal_new
    mov     [obj_critter], rax
    lea     rdi, [n_rex]
    call    Dog_new
    mov     [obj_dog], rax
    lea     rdi, [n_felix]
    call    Cat_new
    mov     [obj_cat], rax

    ; -- dispatch by name, with inheritance and an override ------------------
    lea     rdi, [sec_dispatch]
    ccall   printf

    mov     rdi, [obj_critter]
    mov     rsi, [sel_describe]
    xor     edx, edx
    call    msg_send                    ; describe: inherited; speak: base
    mov     rdi, [obj_dog]
    mov     rsi, [sel_describe]
    xor     edx, edx
    call    msg_send                    ; describe: inherited; speak: Dog's override
    mov     rdi, [obj_cat]
    mov     rsi, [sel_describe]
    xor     edx, edx
    call    msg_send
    lea     rdi, [note_inherit]
    ccall   printf
    lea     rdi, [note_override]
    ccall   printf

    ; -- add a method after the objects already exist ------------------------
    lea     rdi, [sec_runtime]
    ccall   printf

    lea     rdi, [lbl_before]
    ccall   printf
    mov     rdi, [obj_dog]
    mov     rsi, [sel_fetch]
    xor     edx, edx
    call    msg_send                    ; not defined yet -> doesNotUnderstand

    lea     rdi, [lbl_add]
    ccall   printf
    lea     rdi, [Dog_class]            ; install fetch on the *class* now
    mov     rsi, [sel_fetch]
    lea     rdx, [Dog_fetch]
    call    class_add_method

    lea     rdi, [lbl_after]
    ccall   printf
    mov     rdi, [obj_dog]              ; the very same object, no re-creation
    mov     rsi, [sel_fetch]
    xor     edx, edx
    call    msg_send
    mov     rdx, rax                    ; "fetches the ball"
    lea     rsi, [n_rex]
    lea     rdi, [fmt_named]
    xor     eax, eax
    ccall   printf

    ; -- doesNotUnderstand ---------------------------------------------------
    lea     rdi, [sec_dnu]
    ccall   printf
    mov     rdi, [obj_cat]
    mov     rsi, [sel_quack]
    xor     edx, edx
    call    msg_send                    ; a Cat has no 'quack'; it does not crash

    ; -- forwarding via a proxy ----------------------------------------------
    lea     rdi, [sec_forward]
    ccall   printf

    lea     rdi, [n_proxy]
    mov     rsi, [obj_dog]              ; the proxy delegates to Rex
    call    Proxy_new
    mov     [obj_proxy], rax

    mov     rdi, [obj_proxy]
    mov     rsi, [sel_speak]
    xor     edx, edx
    call    msg_send                    ; Proxy has no speak -> forwarded to Rex
    mov     rdx, rax                    ; "Woof"
    mov     rsi, [sel_speak]            ; a SEL prints as its own text
    lea     rdi, [fmt_forward]
    xor     eax, eax
    ccall   printf

    mov     rdi, [obj_proxy]
    mov     rsi, [sel_fetch]
    xor     edx, edx
    call    msg_send                    ; forwarded, and Rex now has fetch
    mov     rdx, rax
    mov     rsi, [sel_fetch]
    lea     rdi, [fmt_forward]
    xor     eax, eax
    ccall   printf

    mov     rdi, [obj_proxy]
    mov     rsi, [sel_quack]
    xor     edx, edx
    call    msg_send                    ; forwarded to Rex, who also declines
    lea     rdi, [note_fwd_dnu]
    ccall   printf

    ; -- caching: build the polymorphic workload -----------------------------
    lea     rax, [poly]
    mov     rcx, [obj_dog]
    mov     [rax + 0*8], rcx
    mov     rcx, [obj_cat]
    mov     [rax + 1*8], rcx
    mov     rcx, [obj_dog]
    mov     [rax + 2*8], rcx
    mov     rcx, [obj_cat]
    mov     [rax + 3*8], rcx
    mov     rcx, [obj_dog]
    mov     [rax + 4*8], rcx
    mov     rcx, [obj_cat]
    mov     [rax + 5*8], rcx

    lea     rdi, [sec_cache]
    ccall   printf

    ; monomorphic: same class every iteration -> inline cache hits
    call    counters_reset
    lea     rdi, [Dog_class]
    call    class_flush
    lea     rdi, [Cat_class]
    call    class_flush
    xor     rbx, rbx
.mono:
    cmp     rbx, 6
    jae     .mono_done
    lea     rdi, [siteM]
    mov     rsi, [obj_dog]
    mov     rdx, [sel_legs]
    xor     ecx, ecx
    call    send_cached
    inc     rbx
    jmp     .mono
.mono_done:
    lea     rdi, [lbl_mono]
    ccall   printf
    call    report_counters

    ; polymorphic: class alternates -> inline cache thrashes, class cache saves
    call    counters_reset
    lea     rdi, [Dog_class]
    call    class_flush
    lea     rdi, [Cat_class]
    call    class_flush
    xor     rbx, rbx
.poly:
    cmp     rbx, 6
    jae     .poly_done
    lea     rax, [poly]
    mov     rsi, [rax + rbx*8]
    lea     rdi, [siteP]
    mov     rdx, [sel_legs]
    xor     ecx, ecx
    call    send_cached
    inc     rbx
    jmp     .poly
.poly_done:
    lea     rdi, [lbl_poly]
    ccall   printf
    call    report_counters
    lea     rdi, [note_cache]
    ccall   printf
    lea     rdi, [note_cache2]
    ccall   printf

    ; -- release the objects (poly holds no new ones) ------------------------
    mov     rdi, [obj_critter]
    ccall   free
    mov     rdi, [obj_dog]
    ccall   free
    mov     rdi, [obj_cat]
    ccall   free
    mov     rdi, [obj_proxy]
    ccall   free

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue

section .rodata
n_critter:      db "Critter", 0
n_rex:          db "Rex", 0
n_felix:        db "Felix", 0
n_proxy:        db "proxy", 0
