;; zoo.asm - the classes the demo sends messages to.
;;
;;   Animal            speak, legs, describe
;;     +-- Dog         speak (override); fetch added at RUN TIME
;;     +-- Cat         speak (override)
;;   Proxy             forwardingTarget -> a delegate it holds
;;
;; None of this is known to msg.asm. A class here is built at start-up by
;; interning its selectors and appending (selector, function) rows - which is
;; precisely what Objective-C's +load / class-realisation does, and why the
;; same runtime can drive classes it never saw.

%include "abi.inc"
%include "libc.inc"
%include "msg.inc"

; Proxy carries one extra field beyond a plain object: the delegate it forwards
; to. The dispatcher never sees this field; only Proxy_forwardingTarget does.
struc ProxyObject
    .isa:       resq 1
    .name:      resq 1
    .delegate:  resq 1
endstruc

; ---------------------------------------------------------------------------
section .rodata
str_speak:      db "speak", 0
str_legs:       db "legs", 0
str_describe:   db "describe", 0
str_fetch:      db "fetch", 0
str_quack:      db "quack", 0
str_forwarding: db "forwardingTarget", 0

n_Animal:       db "Animal", 0
n_Dog:          db "Dog", 0
n_Cat:          db "Cat", 0
n_Proxy:        db "Proxy", 0

snd_generic:    db "(nothing in particular)", 0
snd_woof:       db "Woof", 0
snd_meow:       db "Meow", 0
str_ball:       db "fetches the ball", 0

fmt_describe:   db "  the %s says %s", 10, 0

; ---------------------------------------------------------------------------
section .bss
align 8
; Classes live in writable memory because they are mutable: methods get added
; at run time, and each carries a cache. A vtable, being immutable, could sit
; in .rodata; a class object cannot.
global Animal_class
global Dog_class
global Cat_class
global Proxy_class
Animal_class:   resb MpClass_size
Dog_class:      resb MpClass_size
Cat_class:      resb MpClass_size
Proxy_class:    resb MpClass_size

; The interned selectors, filled in by setup and shared with main.
global sel_speak
global sel_legs
global sel_describe
global sel_fetch
global sel_quack
sel_speak:      resq 1
sel_legs:       resq 1
sel_describe:   resq 1
sel_fetch:      resq 1
sel_quack:      resq 1

; The one method installed after objects exist (see main's runtime-extension
; section). Kept global so main can install it by name.
global Dog_fetch

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; void setup(void)  - intern selectors, then build the four classes.
; ---------------------------------------------------------------------------
global setup
setup:
    prologue
    push    rbx
    push    r12

    lea     rdi, [str_speak]
    call    intern
    mov     [sel_speak], rax
    lea     rdi, [str_legs]
    call    intern
    mov     [sel_legs], rax
    lea     rdi, [str_describe]
    call    intern
    mov     [sel_describe], rax
    lea     rdi, [str_fetch]
    call    intern
    mov     [sel_fetch], rax
    lea     rdi, [str_quack]
    call    intern
    mov     [sel_quack], rax

    ; Animal: speak, legs, describe
    lea     rdi, [Animal_class]
    lea     rsi, [n_Animal]
    xor     edx, edx
    call    class_init
    lea     rdi, [Animal_class]
    mov     rsi, [sel_speak]
    lea     rdx, [Animal_speak]
    call    class_add_method
    lea     rdi, [Animal_class]
    mov     rsi, [sel_legs]
    lea     rdx, [Animal_legs]
    call    class_add_method
    lea     rdi, [Animal_class]
    mov     rsi, [sel_describe]
    lea     rdx, [Animal_describe]
    call    class_add_method

    ; Dog: overrides speak (fetch is added later, at run time)
    lea     rdi, [Dog_class]
    lea     rsi, [n_Dog]
    lea     rdx, [Animal_class]
    call    class_init
    lea     rdi, [Dog_class]
    mov     rsi, [sel_speak]
    lea     rdx, [Dog_speak]
    call    class_add_method

    ; Cat: overrides speak
    lea     rdi, [Cat_class]
    lea     rsi, [n_Cat]
    lea     rdx, [Animal_class]
    call    class_init
    lea     rdi, [Cat_class]
    mov     rsi, [sel_speak]
    lea     rdx, [Cat_speak]
    call    class_add_method

    ; Proxy: only knows how to name a delegate
    lea     rdi, [Proxy_class]
    lea     rsi, [n_Proxy]
    xor     edx, edx
    call    class_init
    lea     rdi, [str_forwarding]
    call    intern
    mov     r12, rax                    ; canonical forwardingTarget SEL
    lea     rdi, [Proxy_class]
    mov     rsi, r12
    lea     rdx, [Proxy_forwardingTarget]
    call    class_add_method

    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Constructors. Each stamps the object's isa with its class - the moment it
; starts responding to that class's messages.
; ---------------------------------------------------------------------------
; MpObject *Animal_new(const char *name)
global Animal_new
Animal_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, MpObject_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Animal_class]
    mov     [rax + MpObject.isa], rcx
    mov     [rax + MpObject.name], rbx
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; MpObject *Dog_new(const char *name)
global Dog_new
Dog_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, MpObject_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Dog_class]
    mov     [rax + MpObject.isa], rcx
    mov     [rax + MpObject.name], rbx
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; MpObject *Cat_new(const char *name)
global Cat_new
Cat_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, MpObject_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Cat_class]
    mov     [rax + MpObject.isa], rcx
    mov     [rax + MpObject.name], rbx
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; MpObject *Proxy_new(const char *name, MpObject *delegate)
global Proxy_new
Proxy_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; name
    mov     r12, rsi                    ; delegate
    mov     rdi, ProxyObject_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Proxy_class]
    mov     [rax + ProxyObject.isa], rcx
    mov     [rax + ProxyObject.name], rbx
    mov     [rax + ProxyObject.delegate], r12
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; ---------------------------------------------------------------------------
; Method implementations. IMP shape: long f(self=rdi, _cmd=rsi, arg=rdx).
; The ones that just return a value are leaf functions with no frame.
; ---------------------------------------------------------------------------
Animal_speak:
    lea     rax, [snd_generic]
    ret

Dog_speak:
    lea     rax, [snd_woof]
    ret

Cat_speak:
    lea     rax, [snd_meow]
    ret

Animal_legs:
    mov     eax, 4
    ret

; Installed at run time in main; existing Dogs answer it the instant it exists.
Dog_fetch:
    lea     rax, [str_ball]
    ret

; Proxy answers this, and only this; everything else it forwards.
Proxy_forwardingTarget:
    mov     rax, [rdi + ProxyObject.delegate]
    ret

; describe is defined once, on Animal, and inherited. It sends `speak` to self,
; so the sound is chosen by the receiver's dynamic class - a Dog says Woof
; through the very same describe a plain Animal uses. This is the template
; method pattern, and it is name-based virtual dispatch doing the work.
Animal_describe:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; self
    mov     rdi, rbx
    mov     rsi, [sel_speak]
    xor     edx, edx
    call    msg_send                    ; self speak -> sound
    mov     rdx, rax                    ; sound
    mov     rsi, [rbx + MpObject.name]  ; name
    lea     rdi, [fmt_describe]
    xor     eax, eax
    ccall   printf
    xor     eax, eax
    pop     r12
    pop     rbx
    epilogue
