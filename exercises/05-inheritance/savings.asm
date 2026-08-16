;; savings.asm - class SavingsAccount : public Account.
;;
;; A separate translation unit that never sees checking.asm. All it shares with
;; the base is account.inc: the field layout (so its own fields land after the
;; base slice at the same offsets a C++ compiler would choose) and the frozen
;; slot numbers. It links against a handful of base symbols - exactly what a
;; C++ derived class needs from its base's header and object file.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "account.inc"

NOTE_SIZE   equ 32

section .rodata
name_savings:   db "SavingsAccount", 0
note_fmt:       db "passbook-for-savings-%ld", 0

section .data
align 8

global Savings_class
Savings_class:
    istruc Class
        at Class.name,      dq name_savings
        at Class.size,      dq Savings_size
        at Class.parent,    dq Account_class        ; the inheritance edge
    iend

; The derived vtable is the base vtable COPIED, with three slots overwritten
; and one appended - never reordered. Slot ACCT_SUMMARY still holds the base's
; Account_summary (an external symbol): that slot is literally inherited, and
; main.asm checks that the pointer is identical to the base's.
global Savings_vtable
Savings_vtable:
    dq Savings_class                    ; VT_CLASS
    dq Savings_destroy                  ; slot ACCT_DTOR       (override)
    dq Savings_kind                     ; slot ACCT_KIND       (override)
    dq Savings_month_end                ; slot ACCT_MONTH_END  (override)
    dq Account_summary                  ; slot ACCT_SUMMARY    (inherited verbatim)
    dq Savings_rate                     ; slot SAV_RATE        (appended)

section .text

; ---------------------------------------------------------------------------
; void Savings_init(Savings *this, long id, long balance, long rate_bp)
;
; Constructor chaining, base-first. Account_init runs to completion - it even
; makes a virtual call, which resolves to the base - and only AFTER it returns
; do we overwrite the vptr with Savings_vtable. That ordering is why a virtual
; call from inside a base constructor cannot reach a derived override: the
; derived vptr is installed here, one instruction after the base is fully
; built.
; ---------------------------------------------------------------------------
global Savings_init
Savings_init:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; this
    mov     r13, rsi                    ; id
    mov     r14, rdx                    ; balance
    mov     r12, rcx                    ; rate_bp

    mov     rdi, rbx                    ; Account::Account(this, id, balance)
    mov     rsi, r13
    mov     rdx, r14
    call    Account_init

    lea     rax, [Savings_vtable]       ; <- now the object becomes a Savings
    mov     [rbx + Savings.vptr], rax
    mov     [rbx + Savings.rate_bp], r12

    mov     rdi, NOTE_SIZE              ; a heap resource this object OWNS
    call    mem_alloc
    mov     [rbx + Savings.note], rax
    mov     rdi, rax
    mov     rsi, NOTE_SIZE
    lea     rdx, [note_fmt]
    mov     rcx, r13
    xor     eax, eax
    ccall   snprintf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Savings *Savings_new(long id, long balance, long rate_bp)
; ---------------------------------------------------------------------------
global Savings_new
Savings_new:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; id
    mov     r12, rsi                    ; balance
    mov     r13, rdx                    ; rate_bp
    mov     rdi, Savings_size
    call    mem_alloc
    mov     r14, rax                    ; this
    mov     rdi, r14
    mov     rsi, rbx
    mov     rdx, r12
    mov     rcx, r13
    call    Savings_init
    mov     rax, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void Savings_destroy(Savings *this)
;
; The derived destructor: free the owned note, then chain to the base
; destructor. Reached through the vtable, this is what makes `delete` on a
; base pointer safe. (Not global: it is only ever reached via slot ACCT_DTOR.)
; ---------------------------------------------------------------------------
Savings_destroy:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    test    rbx, rbx
    jz      .done
    mov     rdi, [rbx + Savings.note]   ; release what the derived slice owns
    call    mem_free
    mov     qword [rbx + Savings.note], 0
    mov     rdi, rbx                    ; ~Account(this): chain to the base
    call    Account_destroy
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; long Savings_month_end(Savings *this)   -> interest credited, in cents
;
; An override that first calls the base implementation directly (the
; equivalent of `Account::month_end(this)`) to advance the period, then adds
; its own behaviour on top.
; ---------------------------------------------------------------------------
Savings_month_end:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rbx
    call    Account_month_end           ; Base::month_end(this): bumps .periods

    mov     rax, [rbx + Savings.balance]
    imul    rax, [rbx + Savings.rate_bp]
    xor     rdx, rdx
    mov     rcx, 10000
    div     rcx                         ; interest = balance * rate_bp / 10000
    add     [rbx + Savings.balance], rax
    pop     r12
    pop     rbx
    epilogue                            ; rax already holds the interest

; const char *Savings_kind(const Savings *this)
Savings_kind:
    lea     rax, [name_savings]
    ret

; long Savings_rate(const Savings *this)   -- the appended slot's method
global Savings_rate
Savings_rate:
    mov     rax, [rdi + Savings.rate_bp]
    ret
