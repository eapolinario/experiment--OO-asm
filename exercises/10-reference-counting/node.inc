;; node.inc - a reference-counted tree node, the demo's one concrete class.
;;
;; A Node owns its children (it retains each on the way in and releases each in
;; its destructor), so a whole tree is torn down by releasing its root. That is
;; ownership expressed through composition, the same shape as a C++ type whose
;; members are shared_ptr, or a Python object whose attributes hold references.

%ifndef NODE_INC
%define NODE_INC

extern Node_new                 ; Node *Node_new(const char *name)     ; refs = 1
extern Node_add_child           ; void  Node_add_child(Node *parent, Node *child)
extern Node_release_children    ; void  Node_release_children(Node *this)
extern Node_name                ; const char *Node_name(const Node *this)

; Weak-list hook. The weak-reference module owns the WeakRef cells and their
; layout; the Node only stores the head of the intrusive list, reached through
; these two accessors so the two files need not share a struct definition.
extern Node_weak_head           ; void *Node_weak_head(const Node *this)
extern Node_set_weak_head       ; void  Node_set_weak_head(Node *this, void *head)

%endif ; NODE_INC
