;; msg.inc - the shared vocabulary of a name-based message runtime.
;;
;; Exercise 04 dispatched by *slot number*, chosen at assembly time: two loads
;; and an indirect call, and the set of methods was frozen in the vtable. This
;; runtime dispatches by *name*, resolved at run time, the way Smalltalk,
;; Objective-C, Ruby and Python do. The price is a lookup; the reward is that
;; the method set is no longer fixed - you can add to it while the program
;; runs, and objects that already exist answer the new message at once.
;;
;; A "selector" here is exactly Objective-C's SEL: an interned string, so that
;; two spellings of the same name become one pointer and every dispatch
;; compares selectors with `cmp`, never `strcmp`.

%ifndef MSG_INC
%define MSG_INC

%include "object.inc"

; A (selector, implementation) pair - one row of a method list.
struc Method
    .sel:       resq 1                  ; Sel (interned char*)
    .impl:      resq 1                  ; IMP: long f(self, Sel, arg)
endstruc

; Small fixed method capacity per class, so a class can be extended at run time
; without a realloc. Real runtimes grow the list; the cap keeps this readable.
%define MP_MAX_METHODS 8

;; A class object. Unlike a vtable this is mutable: methods can be appended
;; after objects exist. .cache_sel/.cache_impl are a one-entry per-class method
;; cache - the last selector resolved *starting from this class* and the IMP it
;; resolved to, inherited or not. Objective-C keeps exactly such a cache on
;; each class (a bigger, hashed one).
struc MpClass
    .name:      resq 1                  ; const char*
    .super:     resq 1                  ; MpClass* or NULL
    .n_methods: resq 1
    .cache_sel: resq 1                  ; last selector looked up here
    .cache_impl:resq 1                  ; ... and the IMP it found
    .methods:   resb MP_MAX_METHODS * Method_size
endstruc

;; Every object begins with an "isa": a pointer to its class. This is not a
;; vtable pointer - there are no slots - it is the class object the dispatcher
;; searches. The name is Objective-C's.
struc MpObject
    .isa:       resq 1
    .name:      resq 1
endstruc

;; A monomorphic inline cache: one call site's memory of the last class it saw
;; and the IMP that class resolved to. The next send at that site is a single
;; compare - if the class matches, skip the lookup entirely. This is the trick
;; every method-JIT leans on.
struc InlineCache
    .cls:       resq 1
    .impl:      resq 1
endstruc

; -- runtime -----------------------------------------------------------------
extern intern                           ; Sel  intern(const char *spelling)
extern runtime_init                     ; void runtime_init(void)  (interns SEL forwardingTarget)
extern class_init                       ; void class_init(MpClass*, const char *name, MpClass *super)
extern class_add_method                 ; void class_add_method(MpClass*, Sel, void *imp)
extern class_flush                      ; void class_flush(MpClass*)  (drops the per-class cache)
extern msg_send                         ; long msg_send(MpObject *recv, Sel, long arg)
extern send_cached                      ; long send_cached(InlineCache*, MpObject*, Sel, long arg)

; -- instrumentation ---------------------------------------------------------
extern counters_reset                   ; void counters_reset(void)
extern report_counters                  ; void report_counters(void)  (prints one indented line)

%endif ; MSG_INC
