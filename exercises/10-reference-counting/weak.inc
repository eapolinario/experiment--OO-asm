;; weak.inc - weak references: observe a target without keeping it alive.
;;
;; A weak reference holds a target pointer but does NOT touch its refcount, so
;; it never keeps the target alive. When the target dies it nulls every weak
;; reference aimed at it, so a weak reference is always either valid or provably
;; dead - it can never dangle. This is __weak in Objective-C ARC, std::weak_ptr
;; in C++, and Weak<T> in Rust; all three exist to break the reference cycles
;; that plain counting cannot collect.

%ifndef WEAK_INC
%define WEAK_INC

extern weak_new         ; WeakRef *weak_new(Node *target)     ; does not retain
extern weak_get         ; Node    *weak_get(const WeakRef*)   ; target or NULL
extern weak_alive       ; long     weak_alive(const WeakRef*) ; 1 if target lives
extern weak_delete      ; void     weak_delete(WeakRef*)      ; unlink + free cell

; Called by a dying target (from its destructor) to null every weak reference
; that was observing it. Walks the intrusive list whose head the Node stores.
extern weak_clear_list  ; void weak_clear_list(WeakRef *head)

%endif ; WEAK_INC
