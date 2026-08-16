;; rc.inc - the reference-counting runtime shared by every class here.
;;
;; The whole mechanism is one extra word in the object header and two functions
;; that adjust it:
;;
;;   object header       every counted object begins with these two words
;;   +--------------+
;;   | vptr         |    offset 0, so the vtable machinery from exercise 04
;;   +--------------+    still works unchanged
;;   | refs         |    offset 8, the reference count
;;   +--------------+
;;
;;   retain(o)   o->refs += 1
;;   release(o)  if (--o->refs == 0) { o->dtor(); free(o); }
;;
;; That is CPython's Py_INCREF / Py_DECREF, Objective-C's retain / release,
;; C++'s shared_ptr control block, and Rust's Rc - all of them, reduced to
;; their common core. The interesting content is never the counter; it is the
;; *rules about who adjusts it*, which the classes and the demo make concrete.

%ifndef RC_INC
%define RC_INC

%include "object.inc"                   ; vptr layout, vcall, VT_SLOT, Class

; A counted object exposes exactly one virtual method: its destructor. It lives
; in method slot 0, i.e. vtable[1] (vtable[0] is the Class*, per object.inc).
%define RC_DTOR 0                       ; void dtor(this)

struc Rc
    .vptr:      resq 1
    .refs:      resq 1
endstruc

; -- lifetime ---------------------------------------------------------------
extern rc_alloc         ; void *rc_alloc(long bytes, void *vtable)  ; refs = 1
extern rc_retain        ; void  rc_retain(void *obj)                ; ++refs
extern rc_release       ; void  rc_release(void *obj)               ; --refs, maybe die
extern rc_refs          ; long  rc_refs(const void *obj)

; -- raw block allocation, for satellite objects (e.g. weak cells) that are
;    heap blocks but not reference-counted objects themselves -----------------
extern rc_mem_alloc     ; void *rc_mem_alloc(long bytes)
extern rc_mem_free      ; void  rc_mem_free(void *p)

; -- instrumentation, so the program proves it balances ---------------------
extern rc_live_objects  ; long: rc_alloc'd minus destroyed
extern rc_live_blocks   ; long: every heap block, minus freed

%endif ; RC_INC
