;; 03 - Objects with a lifetime: construction, destruction, and the heap.
;;
;; Everything so far lived in storage somebody else had already reserved. Here
;; objects allocate their own memory, own a resource beyond their own bytes,
;; and have to be told when they die. The instrumentation in text.asm lets the
;; program *prove* that every constructor got its destructor.

%include "abi.inc"
%include "libc.inc"
%include "text.inc"

section .rodata
hdr:            db "== 03 | constructors, destructors, and objects that outlive their scope ==", 0
sec_new:        db 10, "new = allocate, then construct:", 10, 0
sec_place:      db 10, "The same constructor, different storage:", 10, 0
sec_leak:       db 10, "Destructors are not optional:", 10, 0
sec_end:        db 10, "delete = destruct, then deallocate:", 10, 0

fmt_show:       db `  %-14s "%s" len=%ld cap=%ld\n`, 0
fmt_count:      db "  %-34s live objects=%ld  heap blocks=%ld", 10, 0
fmt_plain:      db "  %s", 10, 0

lbl_new:        db "Text_new(8)", 0
lbl_hello:      db `+ "hello"`, 0
lbl_world:      db `+ ", world"`, 0
lbl_stack:      db "in-place Text", 0
lbl_leaked:     db "Text_new(4)", 0

s_hello:        db "hello", 0
s_world:        db ", world", 0
s_stack:        db "constructed on the stack", 0
s_leaked:       db "leaked", 0

c_after_new:    db "after Text_new + appends", 0
c_after_place:  db "after in-place construction", 0
c_after_destr:  db "after Text_destroy", 0
c_after_again:  db "after a second Text_destroy", 0
c_forgot:       db "leaked object still alive", 0
c_deleted:      db "after Text_delete(leaked)", 0
c_final:        db "after Text_delete(greeting)", 0

n_place:        db "the object's bytes came from the stack, its buffer from malloc", 0
n_destroy:      db "Text_destroy frees the buffer but never the object itself", 0
n_idem:         db "destroying an already-destroyed object is a no-op, not a crash", 0
n_leak:         db "nothing in the machine noticed; that is what makes leaks expensive", 0

section .text

; void show(const char *label, Text *t)
show:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi

    mov     rdi, r12
    call    Text_capacity
    mov     r8, rax
    mov     rdi, r12
    call    Text_length
    mov     rcx, rax
    mov     rdi, r12
    call    Text_cstr
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_show]
    xor     eax, eax
    ccall   printf

    pop     r12
    pop     rbx
    epilogue

; void report(const char *label)
report:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    call    Text_live_blocks
    mov     r12, rax
    call    Text_live_objects
    mov     rcx, r12
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_count]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; void note(const char *text)
note:
    prologue
    mov     rsi, rdi
    lea     rdi, [fmt_plain]
    xor     eax, eax
    ccall   printf
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue 48
    push    rbx
    push    r12

    ; [rbp-32] holds a Text built in place - no malloc for the object itself.
%define IN_PLACE (rbp - 32)

    lea     rdi, [hdr]
    ccall   puts

    ; -- allocate + construct ------------------------------------------------
    lea     rdi, [sec_new]
    ccall   printf

    mov     rdi, 8
    call    Text_new
    mov     rbx, rax                    ; greeting
    lea     rdi, [lbl_new]
    mov     rsi, rbx
    call    show

    mov     rdi, rbx
    lea     rsi, [s_hello]
    call    Text_append
    lea     rdi, [lbl_hello]
    mov     rsi, rbx
    call    show

    mov     rdi, rbx
    lea     rsi, [s_world]
    call    Text_append                 ; forces the buffer to grow
    lea     rdi, [lbl_world]
    mov     rsi, rbx
    call    show

    lea     rdi, [c_after_new]
    call    report

    ; -- construction is not allocation --------------------------------------
    lea     rdi, [sec_place]
    ccall   printf

    lea     rdi, [IN_PLACE]
    mov     rsi, 8
    call    Text_init                   ; C++ would call this placement new
    lea     rdi, [IN_PLACE]
    lea     rsi, [s_stack]
    call    Text_append
    lea     rdi, [lbl_stack]
    lea     rsi, [IN_PLACE]
    call    show
    lea     rdi, [n_place]
    call    note
    lea     rdi, [c_after_place]
    call    report

    lea     rdi, [IN_PLACE]
    call    Text_destroy
    lea     rdi, [n_destroy]
    call    note
    lea     rdi, [c_after_destr]
    call    report

    lea     rdi, [IN_PLACE]
    call    Text_destroy                ; again, on purpose
    lea     rdi, [n_idem]
    call    note
    lea     rdi, [c_after_again]
    call    report

    ; -- forgetting the destructor -------------------------------------------
    lea     rdi, [sec_leak]
    ccall   printf

    mov     rdi, 4
    call    Text_new
    mov     r12, rax                    ; leaked
    mov     rdi, r12
    lea     rsi, [s_leaked]
    call    Text_append
    lea     rdi, [lbl_leaked]
    mov     rsi, r12
    call    show
    lea     rdi, [n_leak]
    call    note
    lea     rdi, [c_forgot]
    call    report

    mov     rdi, r12
    call    Text_delete
    lea     rdi, [c_deleted]
    call    report

    ; -- destruct + deallocate -----------------------------------------------
    lea     rdi, [sec_end]
    ccall   printf

    mov     rdi, rbx
    call    Text_delete
    lea     rdi, [c_final]
    call    report

    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue
