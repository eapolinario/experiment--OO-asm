;; abi.inc - System V AMD64 calling convention helpers.
;;
;; Quick reference (the contract every "method" in this repo obeys):
;;
;;   integer/pointer args : rdi, rsi, rdx, rcx, r8, r9, then the stack
;;   return value         : rax           (rdx:rax for 128-bit)
;;   callee-saved         : rbx, rbp, r12, r13, r14, r15, rsp
;;   caller-saved         : rax, rcx, rdx, rsi, rdi, r8-r11
;;   stack alignment      : rsp % 16 == 0 *immediately before* a `call`,
;;                          therefore rsp % 16 == 8 on entry to a function
;;   variadic calls       : al = number of vector registers used (0 here)
;;
;; Our object convention: the receiver (`this`) travels in rdi, so a method
;; with two arguments uses rdi=this, rsi=arg0, rdx=arg1. That is exactly what
;; a C++ compiler emits for a non-static member function.

%ifndef ABI_INC
%define ABI_INC

; Position-independent addressing by default: `lea rdi, [msg]` becomes
; rip-relative, which is what modern PIE binaries require.
default rel

;; prologue [bytes]
;;   Standard frame. The optional argument reserves `bytes` of locals, rounded
;;   up so that rsp stays 16-byte aligned for the calls we make.
%macro prologue 0-1 0
    push    rbp
    mov     rbp, rsp
  %if (%1) > 0
    sub     rsp, ((%1) + 15) & ~15
  %endif
%endmacro

;; epilogue
;;   `leave` is `mov rsp, rbp` + `pop rbp`, so it also undoes any `sub rsp`.
%macro epilogue 0
    leave
    ret
%endmacro

;; ccall name
;;   Call a libc (or any C ABI) function. `wrt ..plt` emits an R_X86_64_PLT32
;;   relocation, the form the linker wants when producing a PIE executable.
%macro ccall 1
    call    %1 wrt ..plt
%endmacro

;; print fmt [, a [, b [, c]]]
;;   Sugar for the printf sequence that exercise 01 spells out by hand:
;;       lea rdi, [fmt] / mov rsi, a / ... / xor eax, eax / call printf
;;   Arguments pass through verbatim, so both `print fmt, rax` and
;;   `print fmt, qword [rdi + Point.x]` work.
%macro print 1-4
  %if %0 >= 4
    mov     rcx, %4
  %endif
  %if %0 >= 3
    mov     rdx, %3
  %endif
  %if %0 >= 2
    mov     rsi, %2
  %endif
    lea     rdi, [%1]
    xor     eax, eax            ; no vector registers used by this call
    ccall   printf
%endmacro

; Every object file must declare that it does not need an executable stack,
; otherwise the linker conservatively marks the whole program's stack RWX.
; Ending in .text also gives every file a sensible default section.
section .note.GNU-stack noalloc noexec nowrite progbits
section .text

%endif ; ABI_INC
