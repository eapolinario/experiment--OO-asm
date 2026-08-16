;; 05 - Inheritance: a derived object is a base object with more on the end.
;;
;; main.asm is the client. It constructs Savings and Checking objects and then
;; spends most of its time treating them as plain Account pointers - reading
;; base fields, calling virtual methods, deleting through a base pointer - to
;; show that single inheritance is three concrete tricks and nothing more:
;;
;;   1. the derived object begins with the base's fields (a prefix), so a
;;      Derived* already IS a Base* with no pointer adjustment;
;;   2. the derived vtable is the base's, some slots overwritten and some
;;      appended, never reordered;
;;   3. constructors chain base-first and destructors chain derived-first.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "account.inc"

ACCOUNT_COUNT   equ 5

section .rodata
hdr:            db "== 05 | inheritance: a derived object is a base object with more on the end ==", 0

sec_layout:     db 10, "The base object is a prefix of the derived object:", 10, 0
sec_vtable:     db 10, "The derived vtable is the base's, some slots overwritten, some appended:", 10, 0
sec_ctor:       db 10, "Construction runs base-first, so a mid-build virtual call sees the base:", 10, 0
sec_super:      db 10, "An override can call the base implementation directly:", 10, 0
sec_loop:       db 10, "One array of Account*, three concrete classes, one loop:", 10, 0
sec_dtor:       db 10, "A virtual destructor keeps the books balanced; a non-virtual one leaks:", 10, 0

f_offsets:      db "  offsetof(Account,balance)=%ld  offsetof(Savings,balance)=%ld  (identical)", 10, 0
f_sizes:        db "  sizeof(Account)=%ld  sizeof(Savings)=%ld  (base + %ld new bytes)", 10, 0
f_upcast:       db "  Savings* used as Account* adjusts the address by %ld bytes", 10, 0
f_reader:       db "  a base-only reader, handed that Savings* as-is, sees $%ld.%02ld", 10, 0

f_slots:        db "  Account has %ld method slots, SavingsAccount has %ld  (one appended)", 10, 0
f_inherit:      db "  slot %ld (summary):   same pointer in Account and Savings vtables?  %s", 10, 0
f_override:     db "  slot %ld (month_end): same pointer in Account and Savings vtables?  %s", 10, 0
f_parent:       db `  class walk: SavingsAccount.parent -> "%s"`, 10, 0
f_super_intro:  db "  the inherited Account_summary, dispatched on each object:", 10, 0
f_rate:         db "  appended slot, callable only as a SavingsAccount: rate = %ld.%02ld%%", 10, 0

f_born:         db `  during construction, a virtual kind() returned  "%s"`, 10, 0
f_now:          db `  after construction,  the same call returns      "%s"`, 10, 0
f_ctor_note:    db "  the derived vptr is installed only after Account_init returns", 10, 0

f_super_call:   db "  Checking_month_end advances the period (base) then charges the fee (override):", 10, 0
fmt_state:      db "  %-7s periods=%ld  balance $%ld.%02ld", 10, 0

fmt_me1:        db "  %-15s #%-5ld month-end %-8s $%2ld.%02ld", 0
fmt_me2:        db "  -> balance $%4ld.%02ld", 10, 0
f_loop_note:    db "  one vcall month_end drove all five; each class chose interest or fee", 10, 0

fmt_count:      db "  %-30s live objects=%ld  heap blocks=%ld", 10, 0
f_dtor_correct: db "  correct: account_delete dispatches through the virtual destructor slot", 10, 0
f_dtor_note1:   db "  each derived dtor freed its note, each base dtor closed the object -> 0 / 0", 10, 0
f_dtor_bug:     db "  bug: account_delete_nonvirtual binds ~Account statically, skipping ~Savings", 10, 0
f_orphan:       db `  the block about to leak holds the string "%s"`, 10, 0
f_dtor_note2:   db "  objects balanced, but one block outlives every object: the orphaned note", 10, 0
f_dtor_note3:   db "  a leak detector finds it; we free it by hand so the program ends at zero", 10, 0

verb_credited:  db "credited", 0
verb_charged:   db "charged", 0
s_yes:          db "yes", 0
s_no:           db "no", 0

lbl_before:     db "before:", 0
lbl_after:      db "after:", 0
c_live:         db "sv + ck + array constructed", 0
c_swept:        db "after account_delete on all 7", 0
c_built:        db "one SavingsAccount constructed", 0
c_leaked:       db "after the non-virtual delete", 0
c_reclaimed:    db "after reclaiming the note", 0

section .bss
align 8
accounts:       resq ACCOUNT_COUNT
leaked_note:    resq 1

section .text

; ---------------------------------------------------------------------------
; Small helpers.
; ---------------------------------------------------------------------------

; const char *yesno(long cond)
yesno:
    lea     rax, [s_no]
    lea     rcx, [s_yes]
    test    rdi, rdi
    cmovnz  rax, rcx
    ret

; long read_balance(const Account *a)
;
; A deliberately base-only client: it knows Account and nothing else. Handed a
; Savings* with no adjustment, it still reads the right field, because the
; Account slice is a prefix.
read_balance:
    mov     rax, [rdi + Account.balance]
    ret

; void report(const char *label)   -- prints the two live counters
report:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    call    Account_live_blocks
    mov     r12, rax
    call    Account_live_objects
    mov     rcx, r12                    ; blocks
    mov     rdx, rax                    ; objects
    mov     rsi, rbx
    lea     rdi, [fmt_count]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; void print_state(const char *label, const Account *a)
print_state:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; label
    mov     r12, rsi                    ; a
    mov     rax, [r12 + Account.balance]
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ; rax=dollars, rdx=cents
    mov     r8, rdx
    mov     rcx, rax
    mov     rdx, [r12 + Account.periods]
    mov     rsi, rbx
    lea     rdi, [fmt_state]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; void show_month_end(Account *a, long delta)
;
; The body of the polymorphic loop. It never asks what class `a` is: it reads
; the sign of the returned delta to choose the verb, and reads the balance and
; kind back through the base interface.
show_month_end:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; a
    mov     r12, rsi                    ; delta

    mov     rdi, rbx
    vcall   ACCT_KIND
    mov     r13, rax                    ; kind

    mov     r14, r12                    ; magnitude = |delta|
    mov     rax, r14
    neg     rax
    test    r14, r14
    cmovs   r14, rax

    mov     rax, r14
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ; rax=dollars, rdx=cents
    mov     r8, rax                     ; magnitude dollars
    mov     r9, rdx                     ; magnitude cents

    lea     rcx, [verb_credited]
    lea     rax, [verb_charged]
    test    r12, r12
    cmovs   rcx, rax                    ; delta<0 -> "charged"
    mov     rdx, [rbx + Account.id]
    mov     rsi, r13
    lea     rdi, [fmt_me1]
    xor     eax, eax
    ccall   printf

    mov     rax, [rbx + Account.balance]
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ; rax=dollars, rdx=cents
    mov     rsi, rax
    lea     rdi, [fmt_me2]
    xor     eax, eax
    ccall   printf

    pop     r14
    pop     r13
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

    ; Two "microscope" objects, examined non-destructively in sections 1-4.
    mov     rdi, 1500
    mov     rsi, 100000                 ; $1000.00
    mov     rdx, 250                    ; 2.50% per period
    call    Savings_new
    mov     rbx, rax                    ; sv

    mov     rdi, 2500
    mov     rsi, 30000                  ; $300.00
    mov     rdx, 500                    ; $5.00 fee
    call    Checking_new
    mov     r12, rax                    ; ck

    ; -- 1. layout: the base is a prefix -------------------------------------
    lea     rdi, [sec_layout]
    ccall   printf

    mov     rdx, Savings.balance
    mov     rsi, Account.balance
    lea     rdi, [f_offsets]
    xor     eax, eax
    ccall   printf

    mov     rcx, Savings_size
    sub     rcx, Account_size           ; new bytes
    mov     rdx, Savings_size
    mov     rsi, Account_size
    lea     rdi, [f_sizes]
    xor     eax, eax
    ccall   printf

    lea     rax, [rbx + Savings.balance]
    lea     rcx, [rbx + Account.balance]
    sub     rax, rcx                    ; the upcast adjustment: 0
    mov     rsi, rax
    lea     rdi, [f_upcast]
    xor     eax, eax
    ccall   printf

    mov     rdi, rbx                    ; hand the Savings* straight to a base reader
    call    read_balance
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ; rax=dollars, rdx=cents
    mov     rsi, rax
    lea     rdi, [f_reader]
    xor     eax, eax
    ccall   printf

    ; -- 2. vtable: copy, override, append -----------------------------------
    lea     rdi, [sec_vtable]
    ccall   printf

    mov     rdx, SAV_SLOTS
    mov     rsi, ACCT_BASE_SLOTS
    lea     rdi, [f_slots]
    xor     eax, eax
    ccall   printf

    lea     rax, [Account_vtable]       ; is the summary slot inherited verbatim?
    mov     rax, [rax + VT_SLOT(ACCT_SUMMARY)]
    lea     rcx, [Savings_vtable]
    mov     rcx, [rcx + VT_SLOT(ACCT_SUMMARY)]
    cmp     rax, rcx
    sete    dil
    movzx   rdi, dil
    call    yesno
    mov     rdx, rax
    mov     rsi, ACCT_SUMMARY
    lea     rdi, [f_inherit]
    xor     eax, eax
    ccall   printf

    lea     rax, [Account_vtable]       ; and is the month_end slot overridden?
    mov     rax, [rax + VT_SLOT(ACCT_MONTH_END)]
    lea     rcx, [Savings_vtable]
    mov     rcx, [rcx + VT_SLOT(ACCT_MONTH_END)]
    cmp     rax, rcx
    sete    dil
    movzx   rdi, dil
    call    yesno
    mov     rdx, rax
    mov     rsi, ACCT_MONTH_END
    lea     rdi, [f_override]
    xor     eax, eax
    ccall   printf

    class_of rax, rbx                   ; walk Savings_class.parent -> Account_class
    mov     rax, [rax + Class.parent]
    mov     rsi, [rax + Class.name]
    lea     rdi, [f_parent]
    xor     eax, eax
    ccall   printf

    lea     rdi, [f_super_intro]
    ccall   printf
    mov     rdi, rbx
    vcall   ACCT_SUMMARY                ; base code, reaches Savings_kind
    mov     rdi, r12
    vcall   ACCT_SUMMARY                ; base code, reaches Checking_kind

    mov     rdi, rbx                    ; the appended slot, called as a Savings
    vcall   SAV_RATE                    ; rax = rate in basis points
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ; rax=whole percent, rdx=hundredths
    mov     rsi, rax
    lea     rdi, [f_rate]
    xor     eax, eax
    ccall   printf

    ; -- 3. construction chains base-first -----------------------------------
    lea     rdi, [sec_ctor]
    ccall   printf

    mov     rsi, [rbx + Account.kind_at_birth]
    lea     rdi, [f_born]
    xor     eax, eax
    ccall   printf

    mov     rdi, rbx
    vcall   ACCT_KIND
    mov     rsi, rax
    lea     rdi, [f_now]
    xor     eax, eax
    ccall   printf

    lea     rdi, [f_ctor_note]
    ccall   printf

    ; -- 4. an override calling the base implementation ----------------------
    lea     rdi, [sec_super]
    ccall   printf

    lea     rdi, [lbl_before]
    mov     rsi, r12
    call    print_state

    lea     rdi, [f_super_call]
    ccall   printf

    mov     rdi, r12                    ; ck->month_end(): override calls base, then fee
    vcall   ACCT_MONTH_END

    lea     rdi, [lbl_after]
    mov     rsi, r12
    call    print_state

    ; -- 5. one loop over a heterogeneous array ------------------------------
    lea     rdi, [sec_loop]
    ccall   printf

    mov     rdi, 9001
    mov     rsi, 5000                   ; $50.00 plain account
    call    Account_new
    lea     rcx, [accounts]
    mov     [rcx + 0*8], rax

    mov     rdi, 1001
    mov     rsi, 100000                 ; $1000.00 @ 2.50%
    mov     rdx, 250
    call    Savings_new
    lea     rcx, [accounts]
    mov     [rcx + 1*8], rax

    mov     rdi, 2001
    mov     rsi, 30000                  ; $300.00, $5.00 fee
    mov     rdx, 500
    call    Checking_new
    lea     rcx, [accounts]
    mov     [rcx + 2*8], rax

    mov     rdi, 1002
    mov     rsi, 5000                   ; $50.00 @ 1.00%
    mov     rdx, 100
    call    Savings_new
    lea     rcx, [accounts]
    mov     [rcx + 3*8], rax

    mov     rdi, 2002
    mov     rsi, 1000                   ; $10.00, $5.00 fee
    mov     rdx, 500
    call    Checking_new
    lea     rcx, [accounts]
    mov     [rcx + 4*8], rax

    xor     r13, r13
.me_loop:
    cmp     r13, ACCOUNT_COUNT
    jae     .me_done
    lea     rax, [accounts]
    mov     r14, [rax + r13*8]
    mov     rdi, r14
    vcall   ACCT_MONTH_END              ; the one polymorphic call
    mov     rsi, rax                    ; delta
    mov     rdi, r14
    call    show_month_end
    inc     r13
    jmp     .me_loop
.me_done:
    lea     rdi, [f_loop_note]
    ccall   printf

    ; -- 6. virtual vs non-virtual destruction -------------------------------
    lea     rdi, [sec_dtor]
    ccall   printf

    lea     rdi, [c_live]
    call    report

    lea     rdi, [f_dtor_correct]
    ccall   printf
    mov     rdi, rbx                    ; delete the two microscope objects...
    call    account_delete
    mov     rdi, r12
    call    account_delete
    xor     r13, r13                    ; ...and the whole array, all virtually
.del_loop:
    cmp     r13, ACCOUNT_COUNT
    jae     .del_done
    lea     rax, [accounts]
    mov     rdi, [rax + r13*8]
    call    account_delete
    inc     r13
    jmp     .del_loop
.del_done:
    lea     rdi, [c_swept]
    call    report
    lea     rdi, [f_dtor_note1]
    ccall   printf

    lea     rdi, [f_dtor_bug]
    ccall   printf
    mov     rdi, 3001
    mov     rsi, 100000
    mov     rdx, 250
    call    Savings_new
    mov     r14, rax                    ; leaky
    mov     rax, [r14 + Savings.note]   ; stash the note a leak detector would find
    lea     rcx, [leaked_note]
    mov     [rcx], rax

    lea     rdi, [c_built]
    call    report

    lea     rcx, [leaked_note]          ; show what is about to leak
    mov     rsi, [rcx]
    lea     rdi, [f_orphan]
    xor     eax, eax
    ccall   printf

    mov     rdi, r14                    ; the buggy delete: ~Account only
    call    account_delete_nonvirtual
    lea     rdi, [c_leaked]
    call    report
    lea     rdi, [f_dtor_note2]
    ccall   printf

    lea     rcx, [leaked_note]          ; reclaim the orphan by hand
    mov     rdi, [rcx]
    call    mem_free
    lea     rdi, [c_reclaimed]
    call    report
    lea     rdi, [f_dtor_note3]
    ccall   printf

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue
