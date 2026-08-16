;; stream.inc - the public face of the demo hierarchy.
;;
;;   Stream
;;     +-- FileStream
;;           +-- CompressedFileStream
;;   Widget            (unrelated: shares the object model, not the family)
;;
;; A client needs three things from a class here: how to build one, the class
;; descriptor to name it in an is_a / dynamic_cast query, and - for the one
;; field that only exists on the most-derived class - an accessor it may call
;; only after a downcast has proved the object really is that type.

%ifndef STREAM_INC
%define STREAM_INC

%include "rtti.inc"

; Virtual method slots for the hierarchy (see object.inc's VT_SLOT). Only the
; class pointer at slot 0 is needed for RTTI; `describe` exists so the family
; is genuinely polymorphic and so the program can show one vtable doing both
; jobs - dispatch through slot 1, identity through slot 0.
%define STREAM_DESCRIBE 0
%define STREAM_SLOTS    1

; -- constructors -----------------------------------------------------------
extern Stream_new                       ; Stream *Stream_new(void)
extern FileStream_new                   ; FileStream *FileStream_new(long fd)
extern CompressedFileStream_new         ; CompressedFileStream *_new(long fd, long ratio)
extern Widget_new                       ; Widget *Widget_new(long w, long h)

; -- class descriptors (the "type_info" a query names) ----------------------
extern Stream_class
extern FileStream_class
extern CompressedFileStream_class
extern Widget_class

; -- derived-only behaviour, legal only after a checked downcast -------------
extern CompressedFileStream_ratio       ; long ratio(CompressedFileStream *this)

%endif ; STREAM_INC
