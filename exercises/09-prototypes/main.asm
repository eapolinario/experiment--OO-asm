;; 09 - Prototypes: objects that delegate to other objects.
;;
;; Throw the classes away. There is no vtable in this program and no class
;; descriptor; `object.inc` is not even included. An object is a property bag
;; with a pointer to another object, and *everything* an object system needs -
;; fields, methods, inheritance, overriding, even runtime "monkey patching" -
;; falls out of two rules: read up the delegation chain, write to the receiver.

%include "abi.inc"
%include "libc.inc"
%include "proto.inc"

section .rodata
hdr:            db "== 09 | prototypes: objects that delegate, no classes required ==", 0

sec_intern:     db 10, "Keys are interned, so a chain walk compares pointers, not spellings:", 10, 0
sec_get:        db 10, "get walks proto links; depth is the link the property was found at:", 10, 0
sec_send:       db 10, "A method is a property whose value is a code pointer; send binds this:", 10, 0
sec_set:        db 10, "set always writes to the receiver; the prototype is never touched:", 10, 0
sec_clone:      db 10, "Object.create: a clone starts empty and answers through its prototype:", 10, 0
sec_live:       db 10, "Add a method to the prototype and every existing child gains it at once:", 10, 0
sec_over:       db 10, "Override on one child and only that child sees the new version:", 10, 0
sec_clean:      db 10, "Prototypes are ordinary heap objects; nobody frees them for you:", 10, 0

fmt_get_num:    db "  %-22s = %-6ld found at depth %ld", 10, 0
fmt_get_str:    db "  %-22s = %-6s found at depth %ld", 10, 0
fmt_get_depth:  db "  %-22s found at depth %ld", 10, 0
fmt_get_nf:     db "  %-22s not found", 10, 0
fmt_send:       db "  %-30s = %ld", 10, 0
fmt_yesno:      db "  %-54s %s", 10, 0
fmt_count:      db "  %-30s = %ld", 10, 0
fmt_note:       db "  %s", 10, 0

; interned key spellings (each interned once, canonical pointer cached below)
k_w:            db "w", 0
k_h:            db "h", 0
k_kind:         db "kind", 0
k_name:         db "name", 0
k_area:         db "area", 0
k_perim:        db "perimeter", 0
k_w_dup:        db "w", 0                  ; a *second* address holding "w"

; string-valued properties
s_shape:        db "shape", 0
s_base:         db "base", 0

; labels for the get/send/count lines
lbl_gw:         db `get(child, "w")`, 0
lbl_gh:         db `get(child, "h")`, 0
lbl_gname:      db `get(child, "name")`, 0
lbl_gkind:      db `get(child, "kind")`, 0
lbl_gbkind:     db `get(base,  "kind")`, 0
lbl_gcw0:       db `get(child, "w")`, 0
lbl_gbw0:       db `get(base,  "w")`, 0
lbl_garea_c:    db `get(clone, "area")`, 0

lbl_sca:        db `send(child, "area")`, 0
lbl_sba:        db `send(base,  "area")`, 0
lbl_sca2:       db `send(child, "area")`, 0
lbl_sba2:       db `send(base,  "area")`, 0
lbl_scla:       db `send(clone, "area")`, 0
lbl_scla2:      db `send(clone, "area")`, 0
lbl_scp:        db `send(child, "perimeter")`, 0
lbl_sclp:       db `send(clone, "perimeter")`, 0
lbl_sbp:        db `send(base,  "perimeter")`, 0
lbl_scp2:       db `send(child, "perimeter")`, 0
lbl_sclp2:      db `send(clone, "perimeter")`, 0

lbl_ccount0:    db "clone own-property count", 0
lbl_ccount1:    db "clone own-property count", 0
lbl_live0:      db "live objects before cleanup", 0
lbl_live1:      db "live objects after  cleanup", 0

q_canon:        db `intern() maps two spellings of "w" to one pointer:`, 0
q_addr:         db "the two sources were at different addresses:", 0
q_respb:        db `base responds to "perimeter" before?`, 0
q_respa:        db `base responds to "perimeter" after?`, 0

note_setcw:     db `set(child, "w", 10)`, 0
note_setclw:    db `set(clone, "w", 5)`, 0
note_setbp:     db `set(base, "perimeter", <code>)`, 0
note_setcp:     db `set(child, "perimeter", <own code>)`, 0

s_yes:          db "yes", 0
s_no:           db "no", 0

section .bss
align 8
; Canonical (interned) key pointers, filled in once at startup and then used
; as identities everywhere. This is the assembly-level version of a language
; runtime keeping property names as a table of unique atoms.
iw:             resq 1
ih:             resq 1
ikind:          resq 1
iname:          resq 1
iarea:          resq 1
iperim:         resq 1

g_root:         resq 1
g_base:         resq 1
g_child:        resq 1
g_clone:        resq 1

section .text

; ---------------------------------------------------------------------------
; A method is exactly this: a function taking the receiver in rdi. It reads its
; operands *through the receiver*, so it sees whatever w and h that particular
; object resolves to - its own, or a prototype's. `obj_send` guarantees rdi is
; the object the message was sent to.
; ---------------------------------------------------------------------------

; long m_area(Obj *this, long arg0)     -- this.w * this.h
m_area:
    prologue
    push    rbx
    push    r12
    sub     rsp, 16                     ; two depth scratch slots
    mov     rbx, rdi
    mov     rdi, rbx
    mov     rsi, [iw]
    lea     rdx, [rsp]
    call    obj_lookup
    mov     r12, rax                    ; w
    mov     rdi, rbx
    mov     rsi, [ih]
    lea     rdx, [rsp + 8]
    call    obj_lookup                  ; h
    imul    rax, r12
    add     rsp, 16
    pop     r12
    pop     rbx
    epilogue

; long m_perimeter(Obj *this, long arg0)    -- 2 * (this.w + this.h)
m_perimeter:
    prologue
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    mov     rdi, rbx
    mov     rsi, [iw]
    lea     rdx, [rsp]
    call    obj_lookup
    mov     r12, rax
    mov     rdi, rbx
    mov     rsi, [ih]
    lea     rdx, [rsp + 8]
    call    obj_lookup
    add     rax, r12                    ; w + h
    add     rax, rax                    ; 2*(w + h)
    add     rsp, 16
    pop     r12
    pop     rbx
    epilogue

; long m_half_perimeter(Obj *this, long arg0)   -- this.w + this.h
; A deliberately different implementation, so an override is visible in the
; output rather than merely asserted.
m_half_perimeter:
    prologue
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    mov     rdi, rbx
    mov     rsi, [iw]
    lea     rdx, [rsp]
    call    obj_lookup
    mov     r12, rax
    mov     rdi, rbx
    mov     rsi, [ih]
    lea     rdx, [rsp + 8]
    call    obj_lookup
    add     rax, r12                    ; w + h
    add     rsp, 16
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Presentation helpers. None of them are object-oriented; they keep printf
; boilerplate out of main so the delegation story stays readable.
; ---------------------------------------------------------------------------

; const char *yesno(long cond)
yesno:
    lea     rax, [s_no]
    lea     rcx, [s_yes]
    test    rdi, rdi
    cmovnz  rax, rcx
    ret

; void say_yesno(const char *question, long cond)
say_yesno:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     rdi, rsi
    call    yesno
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_yesno]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; void note(const char *text)
note:
    prologue
    mov     rsi, rdi
    lea     rdi, [fmt_note]
    xor     eax, eax
    ccall   printf
    epilogue

; void get_show(Obj *obj, char *key, const char *label, const char *fmt)
;   Look key up on obj and print "label = value found at depth N", using the
;   caller's format (numeric or string). `fmt` receives (label, value, depth).
get_show:
    prologue
    push    rbx                         ; fmt
    push    r12                         ; label
    push    r13                         ; value
    push    r14                         ; depth
    mov     rbx, rcx
    mov     r12, rdx
    sub     rsp, 16
    lea     rdx, [rsp]
    call    obj_lookup                  ; rdi=obj, rsi=key still in place
    mov     r13, rax
    mov     r14, [rsp]
    add     rsp, 16
    cmp     r14, -1
    je      .nf
    mov     rcx, r14
    mov     rdx, r13
    mov     rsi, r12
    mov     rdi, rbx
    xor     eax, eax
    ccall   printf
    jmp     .done
.nf:
    mov     rsi, r12
    lea     rdi, [fmt_get_nf]
    xor     eax, eax
    ccall   printf
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; void get_depth(Obj *obj, char *key, const char *label)
;   Like get_show, but prints only the depth. Used for method-valued
;   properties, whose value is a code pointer we must never print (ASLR).
get_depth:
    prologue
    push    rbx                         ; label
    push    r12
    mov     rbx, rdx
    sub     rsp, 16
    lea     rdx, [rsp]
    call    obj_lookup
    mov     rcx, [rsp]
    add     rsp, 16
    cmp     rcx, -1
    je      .nf
    mov     rdx, rcx
    mov     rsi, rbx
    lea     rdi, [fmt_get_depth]
    xor     eax, eax
    ccall   printf
    jmp     .done
.nf:
    mov     rsi, rbx
    lea     rdi, [fmt_get_nf]
    xor     eax, eax
    ccall   printf
.done:
    pop     r12
    pop     rbx
    epilogue

; void send_show(Obj *obj, char *key, long arg0, const char *label)
send_show:
    prologue
    push    rbx                         ; label
    push    r12
    mov     rbx, rcx
    call    obj_send                    ; rdi=obj, rsi=key, rdx=arg0 in place
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_send]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; void count_show(Obj *obj, const char *label)
count_show:
    prologue
    push    rbx
    push    r12
    mov     rbx, rsi
    call    obj_own_count               ; rdi=obj in place
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_count]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; long responds_to(Obj *obj, char *key)   -- 1 if the chain answers key, else 0
responds_to:
    prologue
    sub     rsp, 16
    lea     rdx, [rsp]
    call    obj_lookup                  ; rdi=obj, rsi=key in place
    mov     rax, [rsp]
    add     rsp, 16
    cmp     rax, -1
    setne   al
    movzx   rax, al
    epilogue

; ---------------------------------------------------------------------------
global main
main:
    prologue
    push    rbx
    push    r12

    lea     rdi, [hdr]
    ccall   puts

    ; -- intern every key once and cache the canonical pointers --------------
    lea     rdi, [k_w]
    call    intern
    mov     [iw], rax
    lea     rdi, [k_h]
    call    intern
    mov     [ih], rax
    lea     rdi, [k_kind]
    call    intern
    mov     [ikind], rax
    lea     rdi, [k_name]
    call    intern
    mov     [iname], rax
    lea     rdi, [k_area]
    call    intern
    mov     [iarea], rax
    lea     rdi, [k_perim]
    call    intern
    mov     [iperim], rax

    ; -- build the prototype chain: root <- base <- child --------------------
    ; root: the shared ancestor (like Object.prototype).
    xor     edi, edi
    call    obj_new
    mov     [g_root], rax
    mov     rdi, rax
    mov     rsi, [ikind]
    lea     rdx, [s_shape]
    call    obj_set                     ; root.kind = "shape"

    ; base: carries default geometry and one method.
    mov     rdi, [g_root]
    call    obj_new
    mov     [g_base], rax
    mov     rdi, [g_base]
    mov     rsi, [iw]
    mov     rdx, 2
    call    obj_set                     ; base.w = 2
    mov     rdi, [g_base]
    mov     rsi, [ih]
    mov     rdx, 3
    call    obj_set                     ; base.h = 3
    mov     rdi, [g_base]
    mov     rsi, [iname]
    lea     rdx, [s_base]
    call    obj_set                     ; base.name = "base"
    mov     rdi, [g_base]
    mov     rsi, [iarea]
    lea     rdx, [m_area]
    call    obj_set                     ; base.area = code pointer

    ; child: empty, delegates to base.
    mov     rdi, [g_base]
    call    obj_new
    mov     [g_child], rax

    ; -- interning is identity, not spelling ---------------------------------
    lea     rdi, [sec_intern]
    ccall   printf

    lea     rdi, [k_w_dup]
    call    intern                      ; a different address holding "w"
    mov     rcx, [iw]
    cmp     rax, rcx                    ; same canonical pointer?
    sete    al
    movzx   rsi, al
    lea     rdi, [q_canon]
    call    say_yesno

    lea     rax, [k_w_dup]
    mov     rcx, [iw]
    cmp     rax, rcx                    ; but the sources differ in address
    setne   al
    movzx   rsi, al
    lea     rdi, [q_addr]
    call    say_yesno

    ; -- get walks the chain; depth makes delegation visible -----------------
    lea     rdi, [sec_get]
    ccall   printf

    mov     rdi, [g_child]
    mov     rsi, [iw]
    lea     rdx, [lbl_gw]
    lea     rcx, [fmt_get_num]
    call    get_show
    mov     rdi, [g_child]
    mov     rsi, [ih]
    lea     rdx, [lbl_gh]
    lea     rcx, [fmt_get_num]
    call    get_show
    mov     rdi, [g_child]
    mov     rsi, [iname]
    lea     rdx, [lbl_gname]
    lea     rcx, [fmt_get_str]
    call    get_show
    mov     rdi, [g_child]
    mov     rsi, [ikind]
    lea     rdx, [lbl_gkind]
    lea     rcx, [fmt_get_str]
    call    get_show
    mov     rdi, [g_base]
    mov     rsi, [ikind]
    lea     rdx, [lbl_gbkind]
    lea     rcx, [fmt_get_str]
    call    get_show

    ; -- a method on the prototype runs on the child's data ------------------
    lea     rdi, [sec_send]
    ccall   printf

    mov     rdi, [g_child]
    mov     rsi, [iarea]
    xor     edx, edx
    lea     rcx, [lbl_sca]
    call    send_show                   ; 2*3 = 6
    mov     rdi, [g_base]
    mov     rsi, [iarea]
    xor     edx, edx
    lea     rcx, [lbl_sba]
    call    send_show                   ; 2*3 = 6

    ; -- set writes to the receiver, shadowing the prototype -----------------
    lea     rdi, [sec_set]
    ccall   printf

    lea     rdi, [note_setcw]
    call    note
    mov     rdi, [g_child]
    mov     rsi, [iw]
    mov     rdx, 10
    call    obj_set                     ; child.w = 10 (own; shadows base.w)

    mov     rdi, [g_child]
    mov     rsi, [iw]
    lea     rdx, [lbl_gcw0]
    lea     rcx, [fmt_get_num]
    call    get_show                    ; now depth 0, value 10
    mov     rdi, [g_base]
    mov     rsi, [iw]
    lea     rdx, [lbl_gbw0]
    lea     rcx, [fmt_get_num]
    call    get_show                    ; base still 2, at depth 0

    mov     rdi, [g_child]
    mov     rsi, [iarea]
    xor     edx, edx
    lea     rcx, [lbl_sca2]
    call    send_show                   ; child: own w=10, base h=3 -> 30
    mov     rdi, [g_base]
    mov     rsi, [iarea]
    xor     edx, edx
    lea     rcx, [lbl_sba2]
    call    send_show                   ; base untouched -> 6

    ; -- clone = a new empty object that delegates to base -------------------
    lea     rdi, [sec_clone]
    ccall   printf

    mov     rdi, [g_base]
    call    obj_new
    mov     [g_clone], rax

    mov     rdi, [g_clone]
    lea     rsi, [lbl_ccount0]
    call    count_show                  ; 0 own properties
    mov     rdi, [g_clone]
    mov     rsi, [iarea]
    lea     rdx, [lbl_garea_c]
    call    get_depth                   ; answered via base, at depth 1
    mov     rdi, [g_clone]
    mov     rsi, [iarea]
    xor     edx, edx
    lea     rcx, [lbl_scla]
    call    send_show                   ; base defaults -> 6

    lea     rdi, [note_setclw]
    call    note
    mov     rdi, [g_clone]
    mov     rsi, [iw]
    mov     rdx, 5
    call    obj_set                     ; clone.w = 5
    mov     rdi, [g_clone]
    mov     rsi, [iarea]
    xor     edx, edx
    lea     rcx, [lbl_scla2]
    call    send_show                   ; own w=5, base h=3 -> 15
    mov     rdi, [g_clone]
    lea     rsi, [lbl_ccount1]
    call    count_show                  ; 1 own property now

    ; -- live mutation of the prototype reaches every child ------------------
    lea     rdi, [sec_live]
    ccall   printf

    mov     rdi, [g_base]
    mov     rsi, [iperim]
    call    responds_to
    mov     rsi, rax
    lea     rdi, [q_respb]
    call    say_yesno                   ; no

    lea     rdi, [note_setbp]
    call    note
    mov     rdi, [g_base]
    mov     rsi, [iperim]
    lea     rdx, [m_perimeter]
    call    obj_set                     ; add perimeter to the prototype

    mov     rdi, [g_base]
    mov     rsi, [iperim]
    call    responds_to
    mov     rsi, rax
    lea     rdi, [q_respa]
    call    say_yesno                   ; yes

    mov     rdi, [g_child]
    mov     rsi, [iperim]
    xor     edx, edx
    lea     rcx, [lbl_scp]
    call    send_show                   ; child w=10,h=3 -> 26
    mov     rdi, [g_clone]
    mov     rsi, [iperim]
    xor     edx, edx
    lea     rcx, [lbl_sclp]
    call    send_show                   ; clone w=5,h=3 -> 16
    mov     rdi, [g_base]
    mov     rsi, [iperim]
    xor     edx, edx
    lea     rcx, [lbl_sbp]
    call    send_show                   ; base w=2,h=3 -> 10

    ; -- override on one child only ------------------------------------------
    lea     rdi, [sec_over]
    ccall   printf

    lea     rdi, [note_setcp]
    call    note
    mov     rdi, [g_child]
    mov     rsi, [iperim]
    lea     rdx, [m_half_perimeter]
    call    obj_set                     ; child overrides perimeter for itself

    mov     rdi, [g_child]
    mov     rsi, [iperim]
    xor     edx, edx
    lea     rcx, [lbl_scp2]
    call    send_show                   ; child's own version: 10+3 = 13
    mov     rdi, [g_clone]
    mov     rsi, [iperim]
    xor     edx, edx
    lea     rcx, [lbl_sclp2]
    call    send_show                   ; clone still uses base's: 16

    ; -- nobody collects prototypes automatically ----------------------------
    lea     rdi, [sec_clean]
    ccall   printf

    call    obj_live
    mov     rdx, rax
    lea     rsi, [lbl_live0]
    lea     rdi, [fmt_count]
    xor     eax, eax
    ccall   printf                      ; 4 live objects

    mov     rdi, [g_root]
    call    obj_free
    mov     rdi, [g_base]
    call    obj_free
    mov     rdi, [g_child]
    call    obj_free
    mov     rdi, [g_clone]
    call    obj_free

    call    obj_live
    mov     rdx, rax
    lea     rsi, [lbl_live1]
    lea     rdi, [fmt_count]
    xor     eax, eax
    ccall   printf                      ; 0

    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue
