;; node.asm - class Node: a counted object that owns a list of child Nodes.
;;
;; The destructor is where ownership becomes visible. When a Node's count hits
;; zero, rc_release calls Node_dtor, which:
;;   1. tells its weak observers it is dying (nulls their pointers),
;;   2. releases every child - which may recursively destroy whole subtrees,
;;   3. announces itself, *after* its children are gone (post-order).
;; Storage is freed by rc_release, never here: destruct and deallocate stay
;; separate, exactly as in exercise 03.

%include "abi.inc"
%include "libc.inc"
%include "rc.inc"
%include "node.inc"
%include "weak.inc"

NODE_MAXKIDS    equ 4

struc Node
    .vptr:      resq 1                  ; \ must match struc Rc: the runtime
    .refs:      resq 1                  ; / treats every object as an Rc first
    .name:      resq 1                  ; const char*
    .nkids:     resq 1
    .kids:      resq NODE_MAXKIDS       ; owned: each child is retained
    .weak:      resq 1                  ; head of this node's WeakRef list
endstruc

; The header must line up with the runtime's view of an object, or retain and
; release would be poking the wrong words. Check it at assembly time.
%if Node.vptr != Rc.vptr || Node.refs != Rc.refs
    %error "Node header does not match struc Rc"
%endif

section .rodata
name_node:      db "Node", 0
fmt_destroyed:  db "  destroyed %s", 10, 0
msg_full:       db "Node: too many children (raise NODE_MAXKIDS)", 10, 0

section .data
align 8
Node_class:
    istruc Class
        at Class.name,      dq name_node
        at Class.size,      dq Node_size
        at Class.parent,    dq 0
    iend

; The vtable: slot 0 is the Class*, slot 1 (RC_DTOR) is the destructor. One
; table, shared by every Node, just like exercise 04.
Node_vtable:
    dq Node_class                       ; VT_CLASS
    dq Node_dtor                        ; VT_SLOT(RC_DTOR)

section .text

; ---------------------------------------------------------------------------
; Node *Node_new(const char *name)
; ---------------------------------------------------------------------------
global Node_new
Node_new:
    prologue
    push    rbx
    push    r12
    mov     r12, rdi                    ; name
    mov     rdi, Node_size
    lea     rsi, [Node_vtable]
    call    rc_alloc                    ; sets vptr, refs = 1
    mov     rbx, rax
    mov     [rbx + Node.name], r12
    mov     qword [rbx + Node.nkids], 0
    mov     qword [rbx + Node.weak], 0
    mov     rax, rbx
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void Node_add_child(Node *parent, Node *child)
;
; The parent takes ownership of a *new* reference to the child - it retains.
; The caller keeps whatever reference it already held; a common idiom (used in
; the demo) is to hand a freshly made child to its parent and then release the
; local reference, transferring sole ownership to the parent.
; ---------------------------------------------------------------------------
global Node_add_child
Node_add_child:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; parent
    mov     r12, rsi                    ; child
    mov     rdi, r12
    call    rc_retain                   ; the parent now owns a reference
    mov     rcx, [rbx + Node.nkids]
    cmp     rcx, NODE_MAXKIDS
    jae     .full
    mov     [rbx + Node.kids + rcx*8], r12
    inc     rcx
    mov     [rbx + Node.nkids], rcx
    pop     r12
    pop     rbx
    epilogue
.full:
    and     rsp, -16
    lea     rdi, [msg_full]
    xor     eax, eax
    ccall   printf
    ccall   abort

; ---------------------------------------------------------------------------
; void Node_release_children(Node *this)
;
; Release and forget every child. The count is zeroed *before* the releases, so
; that if a release cascades back into this same node (a cycle), the re-entry
; finds no children and cannot release anything twice. That ordering is the
; whole trick to breaking a cycle by hand without a double free.
; ---------------------------------------------------------------------------
global Node_release_children
Node_release_children:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r13, [rbx + Node.nkids]
    mov     qword [rbx + Node.nkids], 0 ; clear first: re-entry sees no children
    xor     r12, r12
.loop:
    cmp     r12, r13
    jae     .done
    mov     rdi, [rbx + Node.kids + r12*8]
    call    rc_release
    inc     r12
    jmp     .loop
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void Node_dtor(Node *this)   -- the virtual destructor, reached via RC_DTOR.
; Never frees `this`; rc_release does that once this returns.
; ---------------------------------------------------------------------------
Node_dtor:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi
    ; 1. invalidate weak references to this object (they observe death at once)
    mov     rdi, [rbx + Node.weak]
    call    weak_clear_list
    ; 2. release owned children (may recurse and destroy subtrees)
    mov     rdi, rbx
    call    Node_release_children
    ; 3. announce, after the children are gone
    mov     rsi, [rbx + Node.name]
    lea     rdi, [fmt_destroyed]
    xor     eax, eax
    ccall   printf
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; Accessors, including the weak-list hook used by weak.asm.
; ---------------------------------------------------------------------------
global Node_name
Node_name:
    mov     rax, [rdi + Node.name]
    ret

global Node_weak_head
Node_weak_head:
    mov     rax, [rdi + Node.weak]
    ret

global Node_set_weak_head
Node_set_weak_head:
    mov     [rdi + Node.weak], rsi
    ret
