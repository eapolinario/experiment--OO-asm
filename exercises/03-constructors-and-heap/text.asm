;; text.asm - class Text: an object that owns heap memory.
;;
;; Two pairs of operations, and the difference between them is the whole
;; lesson of this exercise:
;;
;;   Text_init / Text_destroy      construct and destruct, wherever the object
;;                                 happens to live (stack, static, inside
;;                                 another object)
;;   Text_new  / Text_delete       allocate + construct, destruct + free
;;
;; C++ spells the second pair `new`/`delete` and the first pair "placement new"
;; and "explicit destructor call". They are not the same operation, and code
;; that confuses them either leaks or frees the wrong pointer.

%include "abi.inc"
%include "libc.inc"
%include "text.inc"

struc Text
    .len:       resq 1                  ; bytes used, excluding the NUL
    .cap:       resq 1                  ; bytes available in .data
    .data:      resq 1                  ; OWNED. The invariant that matters.
endstruc

%if Text_size != TEXT_SIZEOF
    %error "TEXT_SIZEOF in text.inc disagrees with struc Text"
%endif

TEXT_MIN_CAPACITY equ 8

section .rodata
msg_oom:        db "out of memory", 10, 0

section .bss
align 8
live_objects:   resq 1                  ; constructed - destructed
live_blocks:    resq 1                  ; malloc'd - free'd

section .text

; ---------------------------------------------------------------------------
; Counted allocator. Real runtimes instrument the heap for exactly this
; reason: "did every constructor get a matching destructor?" is not a question
; you can answer by staring at the code.
; ---------------------------------------------------------------------------

; void *mem_alloc(long bytes)
mem_alloc:
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

; void mem_free(void *p)                ; free(NULL) is a no-op, as in C
mem_free:
    prologue
    test    rdi, rdi
    jz      .done
    dec     qword [live_blocks]
    ccall   free
.done:
    epilogue

; ---------------------------------------------------------------------------
; void Text_init(Text *this, long capacity)
;
; The constructor. On entry `this` is raw bytes; on exit it satisfies:
;   .data points at .cap writable bytes, .data[0..len] is a NUL-terminated
;   string, and 0 <= .len < .cap.
; Note that it does not care where those raw bytes came from.
; ---------------------------------------------------------------------------
global Text_init
Text_init:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; this
    mov     r12, rsi                    ; requested capacity
    cmp     r12, TEXT_MIN_CAPACITY
    jae     .have_cap
    mov     r12, TEXT_MIN_CAPACITY
.have_cap:
    mov     rdi, r12
    call    mem_alloc

    mov     [rbx + Text.data], rax
    mov     [rbx + Text.cap], r12
    mov     qword [rbx + Text.len], 0
    mov     byte [rax], 0               ; a valid, empty C string
    inc     qword [live_objects]

    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void Text_destroy(Text *this)
;
; The destructor. It releases what the object owns and leaves the husk in a
; state where destroying it again is harmless - defensive, but it makes the
; "who destroys this?" question survivable. Note it does NOT free `this`:
; the object did not allocate itself, so it must not deallocate itself.
; ---------------------------------------------------------------------------
global Text_destroy
Text_destroy:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    test    rbx, rbx
    jz      .done
    mov     rdi, [rbx + Text.data]
    test    rdi, rdi
    jz      .done                       ; already destroyed
    call    mem_free
    mov     qword [rbx + Text.data], 0
    mov     qword [rbx + Text.len], 0
    mov     qword [rbx + Text.cap], 0
    dec     qword [live_objects]
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Text *Text_new(long capacity)         == operator new + constructor
; ---------------------------------------------------------------------------
global Text_new
Text_new:
    prologue
    push    rbx
    push    r12
    mov     r12, rdi                    ; capacity
    mov     rdi, Text_size
    call    mem_alloc
    mov     rbx, rax
    mov     rdi, rbx
    mov     rsi, r12
    call    Text_init
    mov     rax, rbx
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void Text_delete(Text *this)          == destructor + operator delete
; ---------------------------------------------------------------------------
global Text_delete
Text_delete:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    test    rbx, rbx
    jz      .done
    mov     rdi, rbx
    call    Text_destroy
    mov     rdi, rbx
    call    mem_free
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Text *Text_append(Text *this, const char *s)   -> this, for chaining
;
; The object grows its own buffer. Ownership is not a language feature here
; either: it is the rule "whatever .data points at belongs to this object, and
; nobody else may free it".
; ---------------------------------------------------------------------------
global Text_append
Text_append:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; this
    mov     r12, rsi                    ; s

    mov     rdi, r12
    ccall   strlen
    mov     r13, rax                    ; n = strlen(s)
    mov     r14, [rbx + Text.len]       ; old length

    lea     rax, [r13 + r14 + 1]        ; bytes needed, including NUL
    cmp     rax, [rbx + Text.cap]
    jbe     .copy

    mov     rsi, [rbx + Text.cap]
    add     rsi, rsi                    ; doubling keeps appends amortised O(1)
    cmp     rsi, rax
    jae     .resize
    mov     rsi, rax
.resize:
    mov     [rbx + Text.cap], rsi
    mov     rdi, [rbx + Text.data]
    ccall   realloc                     ; block count is unchanged by realloc
    test    rax, rax
    jz      .oom
    mov     [rbx + Text.data], rax

.copy:
    mov     rdi, [rbx + Text.data]
    add     rdi, r14                    ; write at the old end
    mov     rsi, r12
    lea     rdx, [r13 + 1]              ; copy the NUL too
    ccall   memcpy
    add     [rbx + Text.len], r13

    mov     rax, rbx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
.oom:
    lea     rdi, [msg_oom]
    xor     eax, eax
    ccall   printf
    ccall   abort

; ---------------------------------------------------------------------------
; Accessors.
; ---------------------------------------------------------------------------
global Text_cstr
Text_cstr:
    mov     rax, [rdi + Text.data]
    ret

global Text_length
Text_length:
    mov     rax, [rdi + Text.len]
    ret

global Text_capacity
Text_capacity:
    mov     rax, [rdi + Text.cap]
    ret

global Text_live_objects
Text_live_objects:
    mov     rax, [live_objects]
    ret

global Text_live_blocks
Text_live_blocks:
    mov     rax, [live_blocks]
    ret
