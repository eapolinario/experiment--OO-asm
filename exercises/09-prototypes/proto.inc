;; proto.inc - the public interface of the prototype object system.
;;
;; There is no class here, and no vtable. An "object" is a bag of (key, value)
;; pairs plus a single pointer to another object it *delegates* to. That is the
;; whole model behind Self, JavaScript, Io and Lua: behaviour is not looked up
;; in a class, it is looked up by walking a chain of ordinary objects.
;;
;; Keys are interned first, so that the chain walk compares 8-byte pointers
;; instead of running strcmp at every link. A JavaScript engine does exactly
;; this: property names become interned "atoms" (V8) or "unique strings", and
;; the shape/hidden-class machinery keys off their identity, not their text.

%ifndef PROTO_INC
%define PROTO_INC

; -- interning --------------------------------------------------------------
extern intern                   ; char *intern(const char *s)

; -- objects ----------------------------------------------------------------
extern obj_new                  ; Obj *obj_new(Obj *proto)   ; proto may be NULL
extern obj_set                  ; void obj_set(Obj *this, char *key, long val)
extern obj_lookup               ; long obj_lookup(Obj *this, char *key, long *depth)
                                ;   returns value; *depth = link found at, or -1
extern obj_send                 ; long obj_send(Obj *recv, char *key, long arg0)
                                ;   get + indirect call, `this` bound to recv
extern obj_own_count            ; long obj_own_count(const Obj *this)

; -- instrumentation, so the program can prove it cleaned up ----------------
extern obj_live                 ; long: objects allocated minus freed
extern obj_free                 ; void obj_free(Obj *this)   ; not automatic!

; A method is just a property whose value is one of these:
;   long method(Obj *this, long arg0)
; `this` is whatever object the message was sent to, never the object the
; method happened to be found on. That is the entire point of `obj_send`.

%endif ; PROTO_INC
