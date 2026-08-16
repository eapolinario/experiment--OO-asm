;; account.asm - class Account: the base of the family, plus the shared
;; machinery its subclasses build on.
;;
;; This module owns three things the derived modules borrow:
;;   * the instrumented allocator (mem_alloc/mem_free) and the two live
;;     counters, so the program can PROVE every constructor got a destructor;
;;   * the base slice of construction and destruction (Account_init /
;;     Account_destroy), which a derived constructor/destructor chains into;
;;   * the two generic `delete` helpers, one correct (virtual) and one buggy
;;     (non-virtual), so exercise can show the difference in the counters.
;;
;; live_objects is incremented by the *base* constructor and decremented by the
;; *base* destructor. Every complete object - Account, Savings or Checking -
;; has exactly one Account subobject, so this counter tracks whole objects
;; without any derived class having to touch it.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "account.inc"

section .rodata
name_account:   db "Account", 0
fmt_summary:    db `  summary: a "%s" account, #%ld, holding $%ld.%02ld\n`, 0
msg_oom:        db "out of memory", 10, 0

section .bss
align 8
live_objects:   resq 1                  ; constructed - destructed
live_blocks:    resq 1                  ; malloc'd - freed

section .data
align 8

; One class descriptor per class; the parent link makes the hierarchy walkable
; at run time (exercise 07 turns that into RTTI).
global Account_class
Account_class:
    istruc Class
        at Class.name,      dq name_account
        at Class.size,      dq Account_size
        at Class.parent,    dq 0                    ; the root has no parent
    iend

; The base vtable. Slot numbers come from account.inc and are frozen ABI.
global Account_vtable
Account_vtable:
    dq Account_class                    ; VT_CLASS
    dq Account_destroy                  ; slot ACCT_DTOR
    dq Account_kind                     ; slot ACCT_KIND
    dq Account_month_end                ; slot ACCT_MONTH_END
    dq Account_summary                  ; slot ACCT_SUMMARY

section .text

; ---------------------------------------------------------------------------
; Instrumented allocator, identical in spirit to exercise 03's.
; ---------------------------------------------------------------------------
global mem_alloc
mem_alloc:                              ; void *mem_alloc(long bytes)
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

global mem_free
mem_free:                               ; void mem_free(void *p)   free(NULL) is a no-op
    prologue
    test    rdi, rdi
    jz      .done
    dec     qword [live_blocks]
    ccall   free
.done:
    epilogue

; ---------------------------------------------------------------------------
; void Account_init(Account *this, long id, long balance)
;
; The base constructor. It installs the *base* vtable first, then does its
; work. The vptr write is the important line: from here until a derived
; constructor overwrites it, the object genuinely IS an Account, so any virtual
; call made during base construction resolves to Account's methods. We capture
; that fact in .kind_at_birth to make the classic C++ gotcha observable: a
; virtual call from a base constructor never reaches a derived override,
; because the override's vptr has not been installed yet.
; ---------------------------------------------------------------------------
global Account_init
Account_init:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; this
    lea     rax, [Account_vtable]
    mov     [rbx + Account.vptr], rax   ; <- the object becomes an Account here
    mov     [rbx + Account.id], rsi
    mov     [rbx + Account.balance], rdx
    mov     qword [rbx + Account.periods], 0

    mov     rdi, rbx                    ; a virtual call, mid-construction...
    vcall   ACCT_KIND                   ; ...resolves to Account_kind, never a subclass
    mov     [rbx + Account.kind_at_birth], rax

    inc     qword [live_objects]
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Account *Account_new(long id, long balance)   == operator new + constructor
; ---------------------------------------------------------------------------
global Account_new
Account_new:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14                         ; four pushes keep rsp 16-aligned
    mov     rbx, rdi                    ; id
    mov     r12, rsi                    ; balance
    mov     rdi, Account_size
    call    mem_alloc
    mov     r13, rax                    ; this
    mov     rdi, r13
    mov     rsi, rbx
    mov     rdx, r12
    call    Account_init
    mov     rax, r13
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void Account_destroy(Account *this)
;
; The base slice of destruction: it releases nothing on the heap (a plain
; Account owns only its own bytes) but it closes the object's lifetime by
; decrementing live_objects. A derived destructor runs first and then chains
; here - and a *non-virtual* delete calls this and only this, which is the bug.
; ---------------------------------------------------------------------------
global Account_destroy
Account_destroy:
    test    rdi, rdi
    jz      .done
    dec     qword [live_objects]
.done:
    ret

; ---------------------------------------------------------------------------
; long Account_month_end(Account *this)   -> balance delta in cents (0 here)
;
; The base behaviour a subclass extends by calling this first (Base::method):
; it advances the statement period. A plain Account neither pays interest nor
; charges a fee, so the delta is zero.
; ---------------------------------------------------------------------------
global Account_month_end
Account_month_end:
    inc     qword [rdi + Account.periods]
    xor     eax, eax
    ret

; const char *Account_kind(const Account *this)
global Account_kind
Account_kind:
    lea     rax, [name_account]
    ret

; ---------------------------------------------------------------------------
; void Account_summary(const Account *this)
;
; Defined once here and INHERITED unchanged by both subclasses: the same
; function pointer sits in slot ACCT_SUMMARY of all three vtables. Yet it calls
; kind() virtually, so inherited base code invokes derived behaviour - the
; template-method pattern, falling straight out of the vtable.
; ---------------------------------------------------------------------------
global Account_summary
Account_summary:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rbx
    vcall   ACCT_KIND                   ; virtual: reaches the real class's kind()
    mov     r12, rax
    mov     rax, [rbx + Account.balance]
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                         ; rax = dollars, rdx = cents
    mov     r8, rdx
    mov     rcx, rax
    mov     rdx, [rbx + Account.id]
    mov     rsi, r12
    lea     rdi, [fmt_summary]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void account_delete(Account *this)
;
; `delete` through a base pointer, done correctly. The destructor slot is
; virtual, so this reaches the most-derived destructor, which chains up to the
; base one; only then is the storage released.
; ---------------------------------------------------------------------------
global account_delete
account_delete:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    test    rbx, rbx
    jz      .done
    mov     rdi, rbx
    vcall   ACCT_DTOR                   ; most-derived dtor -> chains to base
    mov     rdi, rbx
    call    mem_free                    ; operator delete
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void account_delete_nonvirtual(Account *this)
;
; The bug this whole exercise exists to make visible. It calls Account_destroy
; statically - as C++ does when the base destructor is NOT declared virtual -
; so the derived destructor never runs and whatever the derived slice owns
; leaks. The object count still balances (the base dtor ran); the block count
; does not.
; ---------------------------------------------------------------------------
global account_delete_nonvirtual
account_delete_nonvirtual:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    test    rbx, rbx
    jz      .done
    mov     rdi, rbx
    call    Account_destroy             ; statically bound: base slice only
    mov     rdi, rbx
    call    mem_free
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Instrumentation accessors.
; ---------------------------------------------------------------------------
global Account_live_objects
Account_live_objects:
    mov     rax, [live_objects]
    ret

global Account_live_blocks
Account_live_blocks:
    mov     rax, [live_blocks]
    ret
