;; 10 - Reference counting: who decides when an object dies.
;;
;; This is the last rung of the ladder, and it is about lifetime. Every earlier
;; object was freed by hand at a point the programmer picked. Here the objects
;; decide: each carries a count of how many references point at it, and the one
;; that drops the last reference is the one that runs the destructor. The whole
;; program is an audit - the instrumented allocator prints live counts so that
;; balance is demonstrated, and the one case refcounting cannot handle (a cycle)
;; is shown leaking, then broken by hand.

%include "abi.inc"
%include "libc.inc"
%include "rc.inc"
%include "node.inc"
%include "weak.inc"

section .rodata
hdr:            db "== 10 | reference counting: who decides when an object dies ==", 0

sec_basic:      db 10, "retain and release adjust a counter in the object header:", 10, 0
sec_compose:    db 10, "Ownership through composition: releasing the root frees the tree:", 10, 0
sec_share:      db 10, "Sharing: one object, two owners, released one at a time:", 10, 0
sec_cycle:      db 10, "A cycle is the leak that reference counting cannot fix:", 10, 0
sec_weak:       db 10, "Weak references observe a target without keeping it alive:", 10, 0
sec_weakcyc:    db 10, "A cycle with one weak edge is reclaimed correctly:", 10, 0

fmt_refs:       db "  %-22s refcount = %ld", 10, 0
fmt_alive:      db "  %-22s = %s", 10, 0
fmt_counts:     db "  live objects = %ld   live blocks = %ld", 10, 0
fmt_plain:      db "  %s", 10, 0
fmt_cyc_refs:   db "  %s.refs = %ld    %s.refs = %ld", 10, 0

; names for the tree in the composition section
n_doc:          db "doc", 0
n_sec1:         db "section-1", 0
n_sec2:         db "section-2", 0
n_para:         db "para", 0

; names for the sharing section
n_shared:       db "shared", 0
n_owner1:       db "owner-1", 0
n_owner2:       db "owner-2", 0

; names for the two cycle sections
n_cycA:         db "cycle-A", 0
n_cycB:         db "cycle-B", 0
n_nodeA:        db "node-A", 0
n_nodeB:        db "node-B", 0
n_target:       db "target", 0
solo_name:      db "solo", 0

lbl_cycA:       db "cycle-A", 0
lbl_cycB:       db "cycle-B", 0

; note / label strings
t_new_solo:     db `Node_new("solo")`, 0
t_retain_solo:  db "rc_retain(solo)", 0
t_release_solo: db "rc_release(solo)", 0
t_last_release: db "rc_release(solo): last reference, destructor runs", 0
t_built:        db "built  doc -> { section-1 -> { para }, section-2 }", 0
t_rel_doc:      db "rc_release(doc):", 0
t_two_owners:   db "owner-1 and owner-2 both retain shared", 0
t_rel_o1:       db "rc_release(owner-1):", 0
t_rel_o2:       db "rc_release(owner-2):", 0
t_shared2:      db "shared", 0
t_shared_after: db "shared (1 owner left)", 0
t_each_retains: db "cycle-A and cycle-B each retain the other", 0
t_drop_ext:     db "drop both external references:", 0
t_break:        db "break one edge by hand:", 0
t_w_made:       db "created w1, w2 as weak references to target", 0
t_target:       db "target", 0
t_w1:           db "weak_alive(w1)", 0
t_w2:           db "weak_alive(w2)", 0
t_del_w1:       db "weak_delete(w1) while target alive: unlinks from the list", 0
t_rel_target:   db "rc_release(target):", 0
t_weakcyc:      db "node-A owns node-B strongly; node-B refers to node-A weakly", 0
t_rel_only:     db "release the only strong external reference:", 0
t_wback:        db "weak back-reference", 0

s_yes:          db "yes", 0
s_no:           db "no", 0

section .bss
align 8
; The demo keeps raw (non-owning) handles to the cycle nodes so it can reach in
; and break the cycle after all owning references are gone.
r_a:            resq 1
r_b:            resq 1

section .text

; ---------------------------------------------------------------------------
; Presentation helpers.
; ---------------------------------------------------------------------------

; const char *yesno(long cond)
yesno:
    lea     rax, [s_no]
    lea     rcx, [s_yes]
    test    rdi, rdi
    cmovnz  rax, rcx
    ret

; void note(const char *text)
note:
    prologue
    mov     rsi, rdi
    lea     rdi, [fmt_plain]
    xor     eax, eax
    ccall   printf
    epilogue

; void counts(void) -- print live objects and blocks
counts:
    prologue
    push    rbx
    push    r12
    call    rc_live_blocks
    mov     r12, rax
    call    rc_live_objects
    mov     rdx, r12
    mov     rsi, rax
    lea     rdi, [fmt_counts]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; void show_refs(const char *label, void *obj)
;   Reads the refcount of a *live* object. Never call it after the object may
;   have been freed - that would be exactly the use-after-free this exercise is
;   about avoiding.
show_refs:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; label
    mov     r12, rsi                    ; obj
    mov     rdi, r12
    call    rc_refs
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_refs]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; void show_alive(const char *label, WeakRef *wr)
show_alive:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; label
    mov     r12, rsi                    ; wr
    mov     rdi, r12
    call    weak_alive
    mov     rdi, rax
    call    yesno
    mov     rdx, rax
    mov     rsi, rbx
    lea     rdi, [fmt_alive]
    xor     eax, eax
    ccall   printf
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

    ; == retain / release on a single object =================================
    lea     rdi, [sec_basic]
    ccall   printf

    lea     rdi, [solo_name]
    call    Node_new
    mov     rbx, rax                    ; solo
    lea     rdi, [t_new_solo]
    mov     rsi, rbx
    call    show_refs                   ; refcount = 1

    lea     rdi, [t_retain_solo]
    mov     rsi, rbx
    call    retain_then_show            ; retain, then show refcount = 2

    lea     rdi, [t_release_solo]
    mov     rsi, rbx
    call    release_then_show           ; release, then show refcount = 1

    lea     rdi, [t_last_release]
    call    note
    mov     rdi, rbx
    call    rc_release                  ; refcount 0 -> destroyed solo
    call    counts

    ; == composition: releasing the root destroys the whole tree ============
    lea     rdi, [sec_compose]
    ccall   printf

    lea     rdi, [n_doc]
    call    Node_new
    mov     rbx, rax                    ; doc (the root; we keep this owning ref)

    lea     rdi, [n_sec1]
    call    Node_new
    mov     r12, rax                    ; section-1
    mov     rdi, rbx
    mov     rsi, r12
    call    Node_add_child              ; doc owns section-1 (refs 2)

    lea     rdi, [n_para]
    call    Node_new
    mov     r13, rax                    ; para
    mov     rdi, r12
    mov     rsi, r13
    call    Node_add_child              ; section-1 owns para (refs 2)

    lea     rdi, [n_sec2]
    call    Node_new
    mov     r14, rax                    ; section-2
    mov     rdi, rbx
    mov     rsi, r14
    call    Node_add_child              ; doc owns section-2 (refs 2)

    ; transfer sole ownership to the tree: drop our local creating references
    mov     rdi, r13
    call    rc_release                  ; para now owned only by section-1
    mov     rdi, r14
    call    rc_release                  ; section-2 owned only by doc
    mov     rdi, r12
    call    rc_release                  ; section-1 owned only by doc

    lea     rdi, [t_built]
    call    note
    call    counts                      ; 4 objects, 4 blocks

    lea     rdi, [t_rel_doc]
    call    note
    mov     rdi, rbx
    call    rc_release                  ; releasing the root frees everything
    call    counts                      ; back to 0

    ; == sharing: one object, two owners ====================================
    lea     rdi, [sec_share]
    ccall   printf

    lea     rdi, [n_shared]
    call    Node_new
    mov     rbx, rax                    ; shared

    lea     rdi, [n_owner1]
    call    Node_new
    mov     r12, rax                    ; owner-1
    lea     rdi, [n_owner2]
    call    Node_new
    mov     r13, rax                    ; owner-2

    mov     rdi, r12
    mov     rsi, rbx
    call    Node_add_child              ; shared refs -> 2
    mov     rdi, r13
    mov     rsi, rbx
    call    Node_add_child              ; shared refs -> 3
    mov     rdi, rbx
    call    rc_release                  ; drop our creating ref: shared refs 2

    lea     rdi, [t_two_owners]
    call    note
    lea     rdi, [t_shared2]
    mov     rsi, rbx
    call    show_refs                   ; shared refcount = 2
    call    counts                      ; 3 objects live

    lea     rdi, [t_rel_o1]
    call    note
    mov     rdi, r12
    call    rc_release                  ; owner-1 dies; shared survives at refs 1
    lea     rdi, [t_shared_after]
    mov     rsi, rbx
    call    show_refs                   ; shared refcount = 1

    lea     rdi, [t_rel_o2]
    call    note
    mov     rdi, r13
    call    rc_release                  ; owner-2 dies; shared reaches 0, dies too
    call    counts                      ; back to 0

    ; == the cycle refcounting cannot collect ================================
    lea     rdi, [sec_cycle]
    ccall   printf

    lea     rdi, [n_cycA]
    call    Node_new
    mov     rbx, rax
    mov     [r_a], rax                  ; keep a raw handle for the manual break
    lea     rdi, [n_cycB]
    call    Node_new
    mov     r12, rax
    mov     [r_b], rax

    mov     rdi, rbx
    mov     rsi, r12
    call    Node_add_child              ; A retains B: B.refs -> 2
    mov     rdi, r12
    mov     rsi, rbx
    call    Node_add_child              ; B retains A: A.refs -> 2

    lea     rdi, [t_each_retains]
    call    note
    call    cyc_refs                    ; cycle-A.refs = 2   cycle-B.refs = 2

    lea     rdi, [t_drop_ext]
    call    note
    mov     rdi, rbx
    call    rc_release                  ; A.refs -> 1 (still held by B)
    mov     rdi, r12
    call    rc_release                  ; B.refs -> 1 (still held by A)
    call    cyc_refs                    ; both still 1
    call    counts                      ; live objects = 2, and unreachable

    lea     rdi, [t_break]
    call    note
    mov     rdi, [r_a]
    call    Node_release_children       ; sever A's edge; the cascade frees both
    call    counts                      ; back to 0

    ; == weak references =====================================================
    lea     rdi, [sec_weak]
    ccall   printf

    lea     rdi, [n_target]
    call    Node_new
    mov     rbx, rax                    ; target

    mov     rdi, rbx
    call    weak_new
    mov     r12, rax                    ; w1
    mov     rdi, rbx
    call    weak_new
    mov     r13, rax                    ; w2

    lea     rdi, [t_w_made]
    call    note
    lea     rdi, [t_target]
    mov     rsi, rbx
    call    show_refs                   ; refcount still 1: weak refs do not count
    lea     rdi, [t_w1]
    mov     rsi, r12
    call    show_alive                  ; yes
    lea     rdi, [t_w2]
    mov     rsi, r13
    call    show_alive                  ; yes

    lea     rdi, [t_del_w1]
    call    note
    mov     rdi, r12
    call    weak_delete                 ; unlink from a live target's list
    lea     rdi, [t_target]
    mov     rsi, rbx
    call    show_refs                   ; still 1
    lea     rdi, [t_w2]
    mov     rsi, r13
    call    show_alive                  ; still yes

    lea     rdi, [t_rel_target]
    call    note
    mov     rdi, rbx
    call    rc_release                  ; target dies; w2 is nulled as it dies
    lea     rdi, [t_w2]
    mov     rsi, r13
    call    show_alive                  ; no
    mov     rdi, r13
    call    weak_delete                 ; target dead: just free the cell
    call    counts                      ; back to 0

    ; == the same cycle, but one edge is weak ===============================
    lea     rdi, [sec_weakcyc]
    ccall   printf

    lea     rdi, [n_nodeA]
    call    Node_new
    mov     rbx, rax                    ; node-A (the external owner)
    lea     rdi, [n_nodeB]
    call    Node_new
    mov     r12, rax                    ; node-B

    mov     rdi, rbx
    mov     rsi, r12
    call    Node_add_child              ; A strongly owns B: B.refs -> 2
    mov     rdi, r12
    call    rc_release                  ; drop creating ref: B owned only by A

    mov     rdi, rbx
    call    weak_new                    ; B's back-pointer to A, but weak
    mov     r13, rax                    ; wa (does not raise A.refs)

    lea     rdi, [t_weakcyc]
    call    note
    lea     rdi, [t_rel_only]
    call    note
    mov     rdi, rbx
    call    rc_release                  ; A.refs -> 0: no strong cycle, all freed

    lea     rdi, [t_wback]
    mov     rsi, r13
    call    show_alive                  ; no: A is gone, the weak edge knows it
    mov     rdi, r13
    call    weak_delete                 ; free the (dead) weak cell
    call    counts                      ; back to 0

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    xor     eax, eax
    epilogue

; ---------------------------------------------------------------------------
; Small local helpers kept out of line so main reads as a script.
; ---------------------------------------------------------------------------

; void retain_then_show(const char *label, void *obj) -- retain, then show.
retain_then_show:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; label
    mov     r12, rsi                    ; obj
    mov     rdi, r12
    call    rc_retain
    mov     rdi, rbx
    mov     rsi, r12
    call    show_refs
    pop     r12
    pop     rbx
    epilogue

; void release_then_show(const char *label, void *obj) -- release, then show.
; Safe only because the demo guarantees this is never the *last* reference.
release_then_show:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, r12
    call    rc_release
    mov     rdi, rbx
    mov     rsi, r12
    call    show_refs
    pop     r12
    pop     rbx
    epilogue

; void cyc_refs(void) -- print both cycle nodes' refcounts on one line.
cyc_refs:
    prologue
    push    rbx
    push    r12
    mov     rdi, [r_a]
    call    rc_refs
    mov     rbx, rax                    ; A.refs
    mov     rdi, [r_b]
    call    rc_refs
    mov     r12, rax                    ; B.refs
    mov     r8, r12                     ; 5th arg: B.refs
    lea     rcx, [lbl_cycB]             ; 4th arg: "cycle-B"
    mov     rdx, rbx                    ; 3rd arg: A.refs
    lea     rsi, [lbl_cycA]             ; 2nd arg: "cycle-A"
    lea     rdi, [fmt_cyc_refs]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue
