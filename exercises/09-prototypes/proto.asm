;; proto.asm - a prototype object system: property bags plus delegation.
;;
;; The two operations that carry the whole lesson are get and set, and their
;; asymmetry is the point:
;;
;;   get(obj, key)   walks obj, then obj->proto, then its proto, ... until the
;;                   key is found or the chain ends. Lookup is delegation.
;;   set(obj, key)   *always* writes to obj itself. It never follows a proto
;;                   link. Writing through a value inherited from a prototype
;;                   creates a new own property that shadows it, and leaves the
;;                   prototype untouched.
;;
;; That single rule ("read up the chain, write to the receiver") is why, in
;; JavaScript, `child.x = child.x + 1` can silently turn an inherited property
;; into an own one, and why mutating an object that lives on a shared prototype
;; is a classic source of aliasing bugs.

%include "abi.inc"
%include "libc.inc"
%include "proto.inc"

; An object is a fixed-capacity property bag. A real engine would grow this,
; hash the keys, and (in V8) hoist a fixed set of keys into a shared "hidden
; class" so that instances with the same shape carry only the values. We stay
; with a linear array because the delegation story, not the container, is the
; subject here.
PROTO_CAP       equ 8

struc Obj
    .proto:     resq 1                  ; delegate, or NULL at the root
    .count:     resq 1                  ; number of own properties
    .keys:      resq PROTO_CAP          ; interned key pointers
    .vals:      resq PROTO_CAP          ; matching values (data or code ptrs)
endstruc

INTERN_CAP      equ 32

section .rodata
msg_full:       db "proto: object is full (raise PROTO_CAP)", 10, 0
msg_missing:    db `proto: object does not understand "%s"\n`, 0
msg_oom:        db "proto: out of memory", 10, 0

section .bss
align 8
intern_tab:     resq INTERN_CAP         ; canonical char* for each spelling
intern_n:       resq 1
live_objs:      resq 1                  ; obj_new minus obj_free

section .text

; ---------------------------------------------------------------------------
; char *intern(const char *s)
;
; Returns a single canonical pointer for every distinct spelling. Two strings
; that compare equal by strcmp map to the same pointer, so every later
; comparison is a pointer compare. The strings we intern are static, so we can
; keep the first pointer we saw as the canonical one instead of copying.
; ---------------------------------------------------------------------------
global intern
intern:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; s
    mov     r13, [intern_n]             ; how many canonicals so far
    xor     r12, r12                    ; i = 0
.scan:
    cmp     r12, r13
    jae     .add
    lea     rax, [intern_tab]           ; PIE: base the index off a register
    mov     rsi, [rax + r12*8]          ; canonical candidate
    mov     rdi, rbx
    ccall   strcmp
    test    eax, eax
    jz      .found
    inc     r12
    jmp     .scan
.found:
    lea     rax, [intern_tab]
    mov     rax, [rax + r12*8]          ; return the canonical we already have
    jmp     .done
.add:
    lea     rax, [intern_tab]
    mov     [rax + r12*8], rbx          ; adopt this spelling as canonical
    inc     r13
    mov     [intern_n], r13
    mov     rax, rbx
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void *mem_alloc(long bytes)   -- counted, so cleanup can be proven at exit.
; ---------------------------------------------------------------------------
mem_alloc:
    prologue
    ccall   malloc
    test    rax, rax
    jz      .oom
    inc     qword [live_objs]
    epilogue
.oom:
    lea     rdi, [msg_oom]
    xor     eax, eax
    ccall   printf
    ccall   abort

; ---------------------------------------------------------------------------
; Obj *obj_new(Obj *proto)
;
; A fresh object has zero own properties. Everything it "has" at birth, it has
; by delegation - which is why a clone (obj_new on an existing object) already
; answers every message the prototype answers, while owning nothing.
; ---------------------------------------------------------------------------
global obj_new
obj_new:
    prologue
    push    rbx
    push    r12
    mov     r12, rdi                    ; proto
    mov     rdi, Obj_size
    call    mem_alloc
    mov     rbx, rax
    mov     [rbx + Obj.proto], r12
    mov     qword [rbx + Obj.count], 0
    mov     rax, rbx
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void obj_free(Obj *this)
;
; Deliberately manual. Prototypes are just heap objects; nothing here reclaims
; them for you. Exercise 10 is where that job stops being the programmer's.
; ---------------------------------------------------------------------------
global obj_free
obj_free:
    prologue
    test    rdi, rdi
    jz      .done
    dec     qword [live_objs]
    ccall   free
.done:
    epilogue

; ---------------------------------------------------------------------------
; long obj_lookup(Obj *this, char *key, long *depth_out)
;
; The delegation walk. Scan this object's own keys; on a miss, follow .proto
; and try again, counting how many links we crossed. `depth_out` receives the
; link the property was found at (0 = own, 1 = the prototype, ...), or -1 when
; the chain runs out. Keys are interned, so the inner compare is `cmp reg,reg`.
;
; This is a leaf function: it calls nothing, so it needs no frame at all.
; ---------------------------------------------------------------------------
global obj_lookup
obj_lookup:
    xor     r8, r8                      ; depth = 0
.walk:
    test    rdi, rdi
    jz      .notfound
    mov     rcx, [rdi + Obj.count]
    xor     r10, r10                    ; slot index
.scan:
    cmp     r10, rcx
    jae     .next
    mov     rax, [rdi + Obj.keys + r10*8]
    cmp     rax, rsi                    ; interned: identity, not strcmp
    je      .hit
    inc     r10
    jmp     .scan
.next:
    mov     rdi, [rdi + Obj.proto]      ; delegate one link up
    inc     r8
    jmp     .walk
.hit:
    mov     rax, [rdi + Obj.vals + r10*8]
    mov     [rdx], r8                   ; report the depth we found it at
    ret
.notfound:
    mov     qword [rdx], -1
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; void obj_set(Obj *this, char *key, long val)
;
; Writes to the receiver, full stop. If `key` is already an own property it is
; overwritten; otherwise it is appended. The proto chain is never consulted and
; never modified - so setting a key that exists only on a prototype creates a
; shadowing own property and leaves the prototype exactly as it was.
; ---------------------------------------------------------------------------
global obj_set
obj_set:
    mov     rcx, [rdi + Obj.count]
    xor     r10, r10
.scan:
    cmp     r10, rcx
    jae     .append
    mov     rax, [rdi + Obj.keys + r10*8]
    cmp     rax, rsi
    je      .overwrite
    inc     r10
    jmp     .scan
.overwrite:
    mov     [rdi + Obj.vals + r10*8], rdx
    ret
.append:
    cmp     rcx, PROTO_CAP
    jae     .full
    mov     [rdi + Obj.keys + rcx*8], rsi
    mov     [rdi + Obj.vals + rcx*8], rdx
    inc     rcx
    mov     [rdi + Obj.count], rcx
    ret
.full:
    and     rsp, -16                    ; no return; just make the call legal
    lea     rdi, [msg_full]
    xor     eax, eax
    ccall   printf
    ccall   abort

; ---------------------------------------------------------------------------
; long obj_own_count(const Obj *this)   -- own properties only, no delegation.
; ---------------------------------------------------------------------------
global obj_own_count
obj_own_count:
    mov     rax, [rdi + Obj.count]
    ret

; ---------------------------------------------------------------------------
; long obj_send(Obj *recv, char *key, long arg0)
;
; A method call is nothing but "look the property up, then call it". The one
; subtlety - and it is the reason `this` exists - is that the receiver bound
; for the call is the object the message was *sent to*, not the object the
; method was *found on*. A method defined on a prototype therefore operates on
; the child's own data. Smalltalk, Ruby (self), Python and JS all obey this.
; ---------------------------------------------------------------------------
global obj_send
obj_send:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; receiver  (becomes `this`)
    mov     r13, rsi                    ; key
    mov     r12, rdx                    ; arg0
    sub     rsp, 16                     ; scratch for the depth out-param
    mov     rdi, rbx
    mov     rsi, r13
    lea     rdx, [rsp]
    call    obj_lookup                  ; rax = value (a code pointer)
    mov     rcx, [rsp]
    add     rsp, 16
    cmp     rcx, -1
    je      .missing
    mov     rdi, rbx                    ; bind this = receiver, not where found
    mov     rsi, r12                    ; forward arg0
    call    rax                         ; get + indirect call
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue
.missing:
    ; The prototype analogue of Smalltalk's doesNotUnderstand: / Ruby's
    ; method_missing / a JS Proxy trap. We just report and stop.
    mov     rsi, r13
    lea     rdi, [msg_missing]
    xor     eax, eax
    ccall   printf
    ccall   abort

; ---------------------------------------------------------------------------
; long obj_live(void)   -- objects still allocated.
; ---------------------------------------------------------------------------
global obj_live
obj_live:
    mov     rax, [live_objs]
    ret
