;; text.inc - public interface of class Text, a heap-owning string buffer.
;;
;; Text owns a resource (a malloc'd character buffer), which is what makes its
;; lifetime interesting: creating one is two steps (allocate, then construct)
;; and destroying one is two steps in the other order (destruct, then free).

%ifndef TEXT_INC
%define TEXT_INC

%define TEXT_SIZEOF     24              ; for in-place construction by a client

; -- lifetime ---------------------------------------------------------------
extern Text_new                         ; Text *Text_new(long capacity)
extern Text_delete                      ; void  Text_delete(Text *this)
extern Text_init                        ; void  Text_init(Text *this, long cap)
extern Text_destroy                     ; void  Text_destroy(Text *this)

; -- behaviour --------------------------------------------------------------
extern Text_append                      ; Text *Text_append(Text*, const char*)
extern Text_cstr                        ; const char *Text_cstr(const Text*)
extern Text_length                      ; long  Text_length(const Text *this)
extern Text_capacity                    ; long  Text_capacity(const Text *this)

; -- instrumentation, so the tests can prove balance ------------------------
extern Text_live_objects                ; long: constructed minus destroyed
extern Text_live_blocks                 ; long: malloc'd minus free'd

%endif ; TEXT_INC
