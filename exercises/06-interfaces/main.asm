;; 06 - Interfaces and multiple inheritance: where one vptr stops being enough.
;;
;; A Duck is a Swimmer and a Quacker at the same time. The single-inheritance
;; trick - one vptr at offset 0 - cannot express that, because both interfaces
;; want offset 0 and only one can have it. So the object carries two vptrs, and
;; a method reached through the second one is handed a pointer 16 bytes into
;; the object that it must correct before it can work. main.asm plays two
;; clients, each of which knows exactly one interface, and watches the pointer
;; move.

%include "abi.inc"
%include "libc.inc"
%include "duck.inc"

; A fat interface value: two words, the way a Go interface or a Rust &dyn Trait
; is passed. The first word is the data pointer, the second the itable.
struc Iface
    .data:  resq 1
    .itab:  resq 1
endstruc

section .rodata
hdr:            db "== 06 | interfaces: two vtables in one object, and the pointer that has to move ==", 0

sec_layout:     db 10, "One object, two interfaces, two vptrs at two offsets:", 10, 0
sec_clients:    db 10, "Two clients, each fluent in exactly one interface:", 10, 0
sec_thunk:      db 10, "The secondary call goes through an adjustor thunk:", 10, 0
sec_totop:      db 10, "offset_to_top recovers the whole object (what dynamic_cast<void*> does):", 10, 0
sec_fat:        db 10, "The alternative: a fat pointer, the way Go and Rust do it:", 10, 0

f_layout:       db "  Swimmer subobject at +0, Quacker subobject at +%ld  (two bases, two offsets)", 10, 0
f_delta:        db "  two interface pointers into the SAME duck differ by %ld bytes", 10, 0
f_field:        db "  offsetof(Duck,volume)=%ld sits past the Quacker subobject at +%ld", 10, 0

f_swim_intro:   db "  the pond holds a Swimmer* (here, the whole duck) and calls swim:", 10, 0
f_quack_intro:  db "  the sound check holds a Quacker* (duck + %ld) and calls quack:", 10, 0

f_thunk_is:     db "  is the secondary quack slot the real Duck_quack?  %s   (it is a thunk)", 10, 0
f_thunk_name:   db "  every object holding two dispatch tables needs one of these", 10, 0
f_thunk_sub:    db "  it runs `sub rdi, %ld` then jumps into Duck_quack, no frame of its own", 10, 0
f_thunk_proof:  db "  so quack, though called on duck+%ld, still read the complete-object volume=%ld", 10, 0

f_totop_ott:    db "  the Quacker vtable's offset_to_top = %ld", 10, 0
f_totop_rec:    db "  complete = Quacker* - offset_to_top;  equals the original Duck*?  %s", 10, 0

f_fat_intro:    db "  a fat Quacker value is two words: (data = whole duck, *itab)", 10, 0
f_fat_note:     db "  no thunk needed - the data word already points at the complete object:", 10, 0
f_fat_delta:    db "  fat data pointer vs complete object: %ld bytes apart", 10, 0
f_fat_trade:    db "  the receiver fix-up moved out of the call path and into a 2-word pointer", 10, 0

s_yes:          db "yes", 0
s_no:           db "no", 0

s_name:         db "Mallard", 0

section .bss
align 8
fat_value:      resb Iface_size

section .text

; const char *yesno(long cond)
yesno:
    lea     rax, [s_no]
    lea     rcx, [s_yes]
    test    rdi, rdi
    cmovnz  rax, rcx
    ret

; ---------------------------------------------------------------------------
; The two single-minded clients. Each is handed a pointer to ITS interface
; subobject and does nothing but dispatch through it. Neither mentions Duck.
; ---------------------------------------------------------------------------

; void pond_visit(Swimmer *s)
pond_visit:
    prologue
    mi_vcall SWIMMER_SWIM               ; s is already the complete object; no fix-up
    epilogue

; void soundcheck(Quacker *q)
soundcheck:
    prologue
    mi_vcall QUACKER_QUACK              ; q is duck+16; the thunk fixes it up
    epilogue

; ---------------------------------------------------------------------------
; void fat_quack(void *data, Itab *itab)
;
; Dispatch for a fat interface pointer. There is no thunk and no receiver
; adjustment: `data` is the complete object by construction, so the method is
; called with it unchanged. This is what Go and Rust emit at an interface call.
; ---------------------------------------------------------------------------
fat_quack:
    mov     rax, [rsi + Itab.quack]
    jmp     rax                         ; tail call; rdi (data) is the receiver

; ---------------------------------------------------------------------------
global main
main:
    prologue
    push    rbx
    push    r12

    lea     rdi, [hdr]
    ccall   puts

    lea     rdi, [s_name]
    mov     rsi, 11                     ; volume
    call    Duck_new
    mov     rbx, rax                    ; the complete duck (also its Swimmer*)
    lea     r12, [rbx + DUCK_K]         ; its Quacker* subobject

    ; -- A. one object, two interface subobjects -----------------------------
    lea     rdi, [sec_layout]
    ccall   printf

    mov     rsi, DUCK_K
    lea     rdi, [f_layout]
    xor     eax, eax
    ccall   printf

    mov     rax, r12                    ; measured, not asserted: q - s
    sub     rax, rbx
    mov     rsi, rax
    lea     rdi, [f_delta]
    xor     eax, eax
    ccall   printf

    mov     rdx, DUCK_K
    mov     rsi, Duck.volume
    lea     rdi, [f_field]
    xor     eax, eax
    ccall   printf

    ; -- B. two clients, one interface each ----------------------------------
    lea     rdi, [sec_clients]
    ccall   printf

    lea     rdi, [f_swim_intro]
    ccall   printf
    mov     rdi, rbx                    ; the Swimmer* is the whole duck
    call    pond_visit

    mov     rsi, DUCK_K
    lea     rdi, [f_quack_intro]
    xor     eax, eax
    ccall   printf
    mov     rdi, r12                    ; the Quacker* is duck + 16
    call    soundcheck

    ; -- C. the adjustor thunk -----------------------------------------------
    lea     rdi, [sec_thunk]
    ccall   printf

    lea     rax, [Duck_quacker_vtable]  ; does the slot hold the real method...
    mov     rax, [rax + MI_VT_SLOT(QUACKER_QUACK)]
    lea     rcx, [Duck_quack]           ; ...or a thunk?
    cmp     rax, rcx
    sete    dil
    movzx   rdi, dil
    call    yesno
    mov     rsi, rax
    lea     rdi, [f_thunk_is]
    xor     eax, eax
    ccall   printf

    lea     rdi, [f_thunk_name]
    ccall   printf

    mov     rsi, DUCK_K
    lea     rdi, [f_thunk_sub]
    xor     eax, eax
    ccall   printf

    mov     rdx, [rbx + Duck.volume]    ; the field quack recovered through the thunk
    mov     rsi, DUCK_K
    lea     rdi, [f_thunk_proof]
    xor     eax, eax
    ccall   printf

    ; -- D. offset_to_top, i.e. dynamic_cast<void*> --------------------------
    lea     rdi, [sec_totop]
    ccall   printf

    mov     rax, [r12 + Object.vptr]    ; the secondary vtable
    mov     rax, [rax + MI_VT_OFFSET_TO_TOP]
    mov     rsi, rax
    lea     rdi, [f_totop_ott]
    xor     eax, eax
    ccall   printf

    mi_to_top rcx, r12                  ; recover the complete object from a Quacker*
    cmp     rcx, rbx
    sete    dil
    movzx   rdi, dil
    call    yesno
    mov     rsi, rax
    lea     rdi, [f_totop_rec]
    xor     eax, eax
    ccall   printf

    ; -- E. the fat-pointer alternative --------------------------------------
    lea     rdi, [sec_fat]
    ccall   printf

    lea     rdi, [f_fat_intro]
    ccall   printf

    lea     rcx, [fat_value]            ; assemble the two-word interface value
    mov     [rcx + Iface.data], rbx     ; data = the WHOLE duck, not the subobject
    lea     rax, [Duck_as_quacker_itab]
    mov     [rcx + Iface.itab], rax

    lea     rdi, [f_fat_note]
    ccall   printf
    lea     rcx, [fat_value]
    mov     rdi, [rcx + Iface.data]
    mov     rsi, [rcx + Iface.itab]
    call    fat_quack                   ; same quack, reached with no adjustment

    lea     rcx, [fat_value]
    mov     rax, [rcx + Iface.data]
    sub     rax, rbx                    ; the fat data word vs the complete object
    mov     rsi, rax
    lea     rdi, [f_fat_delta]
    xor     eax, eax
    ccall   printf

    lea     rdi, [f_fat_trade]
    ccall   printf

    mov     rdi, rbx                    ; the duck was malloc'd; give it back
    ccall   free

    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue
