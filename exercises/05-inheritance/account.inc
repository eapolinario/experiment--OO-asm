;; account.inc - the public header for a small class family:
;;
;;      Account                     (base)
;;        |
;;        +-- SavingsAccount        (adds a periodic interest rate)
;;        +-- CheckingAccount       (adds a flat periodic fee)
;;
;; A C++ compiler needs the *full* definition of a base class to lay out a
;; derived one, because the derived object literally begins with the base's
;; fields. That is what this header publishes: the base field list (as a macro
;; so the offsets cannot drift), every struct in the family, and the vtable
;; slot numbers that are frozen ABI. Money is in integer cents throughout, so
;; every figure printed by the program is exact.

%ifndef ACCOUNT_INC
%define ACCOUNT_INC

; ---------------------------------------------------------------------------
; The base layout, emitted as a macro so the derived classes reuse the *exact*
; same field declarations. This is the assembly equivalent of `class Savings :
; public Account` copying Account's members to the front of Savings.
; ---------------------------------------------------------------------------
%macro ACCOUNT_FIELDS 0
    .vptr:          resq 1          ; +0   MUST be first: the object model says so
    .id:            resq 1          ; +8
    .balance:       resq 1          ; +16  cents
    .periods:       resq 1          ; +24  month-end cycles applied so far
    .kind_at_birth: resq 1          ; +32  what a virtual call saw mid-construction
%endmacro

struc Account
    ACCOUNT_FIELDS
endstruc

; A SavingsAccount is an Account followed by two more fields. Because the base
; fields come first and in the same order, Account.balance and Savings.balance
; name the *same* byte offset - proven below at assembly time.
struc Savings
    ACCOUNT_FIELDS
    .rate_bp:       resq 1          ; periodic interest, in basis points
    .note:          resq 1          ; OWNED heap string; the leak canary
endstruc

struc Checking
    ACCOUNT_FIELDS
    .fee:           resq 1          ; flat periodic fee, in cents
    .note:          resq 1          ; OWNED heap string; the leak canary
endstruc

; The prefix property, enforced by the assembler. If a maintainer reorders a
; base field, these fire instead of silently corrupting every derived object.
%if Savings.balance != Account.balance
    %error "prefix broken: Savings.balance and Account.balance must coincide"
%endif
%if Checking.balance != Account.balance
    %error "prefix broken: Checking.balance and Account.balance must coincide"
%endif
%if Savings.vptr != 0 || Checking.vptr != 0
    %error "vptr must live at offset 0 in every polymorphic object"
%endif

; ---------------------------------------------------------------------------
; Vtable slot numbers. These are ABI: a subclass may OVERWRITE the pointer in
; an inherited slot or APPEND new slots after them, but must never renumber -
; exactly the rule that freezes C++ vtable layout across a shipped library.
;
;   slot 0  destructor      overridden by each derived class (virtual dtor)
;   slot 1  kind            overridden by each derived class
;   slot 2  month_end       overridden by each derived class
;   slot 3  summary         INHERITED unchanged (same pointer in all vtables)
;   slot 4  <derived-only>  appended: Savings->rate, Checking->fee
; ---------------------------------------------------------------------------
%define ACCT_DTOR       0
%define ACCT_KIND       1
%define ACCT_MONTH_END  2
%define ACCT_SUMMARY    3
%define ACCT_BASE_SLOTS 4

%define SAV_RATE        4               ; appended slot, SavingsAccount only
%define SAV_SLOTS       5
%define CHK_FEE         4               ; appended slot, CheckingAccount only
%define CHK_SLOTS       5

; ---------------------------------------------------------------------------
; Exported symbols. The base module owns the instrumented allocator and the
; two generic `delete` helpers; each derived module owns its constructors.
; ---------------------------------------------------------------------------
extern Account_init                     ; void  Account_init(Account*, id, balance)
extern Account_new                      ; Account *Account_new(id, balance)
extern Account_destroy                  ; void  Account_destroy(Account*)   base slice
extern Account_month_end                ; long  Account_month_end(Account*)  base slice
extern Account_summary                  ; void  Account_summary(const Account*)
extern Account_kind                     ; const char *Account_kind(const Account*)

extern account_delete                   ; void account_delete(Account*)            virtual dtor + free
extern account_delete_nonvirtual        ; void account_delete_nonvirtual(Account*) base dtor only + free (the bug)

extern Account_live_objects             ; long: constructed - destructed
extern Account_live_blocks              ; long: malloc'd - freed
extern mem_alloc                        ; void *mem_alloc(long)   counted
extern mem_free                         ; void  mem_free(void*)   counted

extern Account_class
extern Account_vtable

extern Savings_init                     ; void  Savings_init(Savings*, id, balance, rate_bp)
extern Savings_new                      ; Savings *Savings_new(id, balance, rate_bp)
extern Savings_rate                     ; long  Savings_rate(const Savings*)
extern Savings_class
extern Savings_vtable

extern Checking_init                    ; void  Checking_init(Checking*, id, balance, fee)
extern Checking_new                     ; Checking *Checking_new(id, balance, fee)
extern Checking_fee                     ; long  Checking_fee(const Checking*)
extern Checking_class
extern Checking_vtable

%endif ; ACCOUNT_INC
