;; checking.asm - class CheckingAccount : public Account.
;;
;; The second subclass, structurally a mirror of SavingsAccount but with
;; different behaviour: instead of paying periodic interest it charges a flat
;; periodic fee. It, too, is a standalone module sharing only account.inc with
;; the rest of the family, and it overrides the same three slots while
;; appending a different one of its own (CHK_FEE).

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "account.inc"

NOTE_SIZE   equ 32

section .rodata
name_checking:  db "CheckingAccount", 0
note_fmt:       db "chequebook-for-checking-%ld", 0

section .data
align 8

global Checking_class
Checking_class:
    istruc Class
        at Class.name,      dq name_checking
        at Class.size,      dq Checking_size
        at Class.parent,    dq Account_class
    iend

; Same shape as Savings_vtable: three overrides, the inherited Account_summary
; in slot ACCT_SUMMARY, and one appended slot - but here the appended slot is a
; different method (Checking_fee), which is why an appended slot is only safe
; to call once you know the concrete class.
global Checking_vtable
Checking_vtable:
    dq Checking_class                   ; VT_CLASS
    dq Checking_destroy                 ; slot ACCT_DTOR       (override)
    dq Checking_kind                    ; slot ACCT_KIND       (override)
    dq Checking_month_end               ; slot ACCT_MONTH_END  (override)
    dq Account_summary                  ; slot ACCT_SUMMARY    (inherited verbatim)
    dq Checking_fee                     ; slot CHK_FEE         (appended)

section .text

; ---------------------------------------------------------------------------
; void Checking_init(Checking *this, long id, long balance, long fee)
; ---------------------------------------------------------------------------
global Checking_init
Checking_init:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; this
    mov     r13, rsi                    ; id
    mov     r14, rdx                    ; balance
    mov     r12, rcx                    ; fee

    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, r14
    call    Account_init                ; base slice first

    lea     rax, [Checking_vtable]
    mov     [rbx + Checking.vptr], rax
    mov     [rbx + Checking.fee], r12

    mov     rdi, NOTE_SIZE
    call    mem_alloc
    mov     [rbx + Checking.note], rax
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
; Checking *Checking_new(long id, long balance, long fee)
; ---------------------------------------------------------------------------
global Checking_new
Checking_new:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     rdi, Checking_size
    call    mem_alloc
    mov     r14, rax
    mov     rdi, r14
    mov     rsi, rbx
    mov     rdx, r12
    mov     rcx, r13
    call    Checking_init
    mov     rax, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void Checking_destroy(Checking *this)   -- derived dtor, chains to base
; ---------------------------------------------------------------------------
Checking_destroy:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    test    rbx, rbx
    jz      .done
    mov     rdi, [rbx + Checking.note]
    call    mem_free
    mov     qword [rbx + Checking.note], 0
    mov     rdi, rbx
    call    Account_destroy
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; long Checking_month_end(Checking *this)   -> balance delta (negative: a fee)
;
; Also calls the base implementation first, then subtracts the flat fee. The
; delta it returns is negative, and the one polymorphic loop in main.asm reads
; that sign to say "charged" instead of "credited" - without ever asking what
; class the object is.
; ---------------------------------------------------------------------------
Checking_month_end:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rbx
    call    Account_month_end           ; Base::month_end(this)

    mov     rax, [rbx + Checking.fee]
    sub     [rbx + Checking.balance], rax
    neg     rax                         ; delta = -fee
    pop     r12
    pop     rbx
    epilogue

; const char *Checking_kind(const Checking *this)
Checking_kind:
    lea     rax, [name_checking]
    ret

; long Checking_fee(const Checking *this)   -- the appended slot's method
global Checking_fee
Checking_fee:
    mov     rax, [rdi + Checking.fee]
    ret
