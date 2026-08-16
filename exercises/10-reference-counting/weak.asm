;; weak.asm - the weak-reference implementation.
;;
;; Design (deliberately the simplest honest one): every target keeps a singly
;; linked list of the weak references pointing at it, threaded through the cells
;; themselves. Creating a weak reference pushes a cell onto that list; the
;; target's destructor walks the list and nulls each cell's target pointer.
;;
;; Costs of this choice, stated plainly:
;;   - weak_new is O(1): push onto the front of the list.
;;   - a target's death is O(number of weak refs to it): it walks the list once.
;;   - weak_delete of a *live* target is O(list length): it must find and unlink
;;     the cell so the target does not later write through freed memory. If the
;;     target is already dead the cell was nulled, its list is gone, and delete
;;     is O(1).
;; A production runtime (ARC, libc++) instead stores weak references in a
;; side table keyed by object address, trading this per-object list for a
;; global hash. The idea - "the target must be able to find its observers" - is
;; identical.

%include "abi.inc"
%include "libc.inc"
%include "rc.inc"
%include "node.inc"
%include "weak.inc"

struc WeakRef
    .target:    resq 1                  ; Node*, or NULL once the target dies
    .next:      resq 1                  ; next cell in the target's weak list
endstruc

section .text

; ---------------------------------------------------------------------------
; WeakRef *weak_new(Node *target)
;
; Allocate a cell and push it onto the target's weak list. Crucially it does
; NOT call rc_retain: a weak reference must not keep its target alive. The cell
; is a heap block (so live_blocks counts it) but not a counted object.
; ---------------------------------------------------------------------------
global weak_new
weak_new:
    prologue
    push    rbx
    push    r12
    mov     r12, rdi                    ; target
    mov     rdi, WeakRef_size
    call    rc_mem_alloc
    mov     rbx, rax
    mov     [rbx + WeakRef.target], r12
    ; push onto target's list: cell.next = target.head; target.head = cell
    mov     rdi, r12
    call    Node_weak_head
    mov     [rbx + WeakRef.next], rax
    mov     rdi, r12
    mov     rsi, rbx
    call    Node_set_weak_head
    mov     rax, rbx
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Node *weak_get(const WeakRef *wr)     -- target, or NULL if it has died.
; ---------------------------------------------------------------------------
global weak_get
weak_get:
    mov     rax, [rdi + WeakRef.target]
    ret

; ---------------------------------------------------------------------------
; long weak_alive(const WeakRef *wr)    -- 1 while the target lives, else 0.
; ---------------------------------------------------------------------------
global weak_alive
weak_alive:
    xor     eax, eax
    cmp     qword [rdi + WeakRef.target], 0
    setne   al
    ret

; ---------------------------------------------------------------------------
; void weak_clear_list(WeakRef *head)
;
; Called from a dying target. Walk its list and null every cell's target, so
; each observer now reports dead. The cells are not freed here - they are owned
; by whoever created them and outlive the target.
; ---------------------------------------------------------------------------
global weak_clear_list
weak_clear_list:
.loop:
    test    rdi, rdi
    jz      .done
    mov     rax, [rdi + WeakRef.next]
    mov     qword [rdi + WeakRef.target], 0
    mov     rdi, rax
    jmp     .loop
.done:
    ret

; ---------------------------------------------------------------------------
; void weak_delete(WeakRef *wr)
;
; Free a weak-reference cell. If its target is still alive we must first unlink
; the cell from the target's list; if the target already died the cell's target
; is NULL and the list no longer exists, so we just free it.
; ---------------------------------------------------------------------------
global weak_delete
weak_delete:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; wr
    mov     r12, [rbx + WeakRef.target] ; target, or NULL
    test    r12, r12
    jz      .free                       ; target dead: nothing to unlink

    mov     rdi, r12
    call    Node_weak_head              ; rax = list head
    cmp     rax, rbx
    jne     .search
    ; wr is the head: head = wr.next
    mov     rsi, [rbx + WeakRef.next]
    mov     rdi, r12
    call    Node_set_weak_head
    jmp     .free
.search:
    mov     rcx, rax                    ; prev = head
.scan:
    mov     rdx, [rcx + WeakRef.next]   ; cur = prev.next
    test    rdx, rdx
    jz      .free                       ; not found (should not happen)
    cmp     rdx, rbx
    je      .unlink
    mov     rcx, rdx
    jmp     .scan
.unlink:
    mov     rax, [rbx + WeakRef.next]
    mov     [rcx + WeakRef.next], rax   ; prev.next = wr.next
.free:
    mov     rdi, rbx
    call    rc_mem_free
    pop     r12
    pop     rbx
    epilogue
