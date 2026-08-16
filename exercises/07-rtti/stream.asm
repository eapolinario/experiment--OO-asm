;; stream.asm - four classes: a three-level chain plus one outsider.
;;
;; Each class supplies exactly the metadata the RTTI runtime consumes: a class
;; descriptor (name, size, parent, and the depth/display pair for Cohen's test)
;; and a vtable whose slot 0 points back at that descriptor. The subclass
;; layouts are prefix-compatible - a FileStream begins with a Stream's fields,
;; a CompressedFileStream begins with a FileStream's - which is the same "base
;; first" arrangement a C++ compiler uses so a Derived* can be read as a Base*.
;; Here the classes only build the metadata; rtti.asm does all the reasoning.

%include "abi.inc"
%include "libc.inc"
%include "object.inc"
%include "rtti.inc"
%include "stream.inc"

; ---------------------------------------------------------------------------
; Layouts. The vptr is first in every one, because the object model says so.
; ---------------------------------------------------------------------------
struc Stream
    .vptr:      resq 1
endstruc

struc FileStream
    .vptr:      resq 1
    .fd:        resq 1
endstruc

struc CompressedFileStream
    .vptr:      resq 1
    .fd:        resq 1                  ; same offset as FileStream.fd
    .ratio:     resq 1                  ; the field a downcast exists to reach
endstruc

struc Widget
    .vptr:      resq 1
    .w:         resq 1
    .h:         resq 1
endstruc

section .rodata
name_stream:        db "Stream", 0
name_filestream:    db "FileStream", 0
name_cfs:           db "CompressedFileStream", 0
name_widget:        db "Widget", 0

fmt_stream:         db "  %-20s   buffered byte sink", 10, 0
fmt_filestream:     db "  %-20s   fd=%ld", 10, 0
fmt_cfs:            db "  %-20s   fd=%ld, ratio=%ld%%", 10, 0
fmt_widget:         db "  %-20s   %ldx%ld pixels", 10, 0

; ---------------------------------------------------------------------------
section .data
align 8

; Class descriptors. Ordered base-first so that each display array can name
; the ancestors above it (labels must already be defined). display[k] is this
; class's ancestor at depth k; display[depth] is the class itself; the rest is
; padding. This is the table Cohen's is_a_fast indexes into.
;
; They are `global` because a client names a type by pointing at its
; descriptor - that pointer is the argument to is_a and dynamic_cast.
global Stream_class
global FileStream_class
global CompressedFileStream_class
global Widget_class
Stream_class:
    istruc RttiClass
        at RttiClass.name,      dq name_stream
        at RttiClass.size,      dq Stream_size
        at RttiClass.parent,    dq 0
        at RttiClass.depth,     dq 0
        at RttiClass.display,   dq Stream_class, 0, 0, 0
    iend

FileStream_class:
    istruc RttiClass
        at RttiClass.name,      dq name_filestream
        at RttiClass.size,      dq FileStream_size
        at RttiClass.parent,    dq Stream_class
        at RttiClass.depth,     dq 1
        at RttiClass.display,   dq Stream_class, FileStream_class, 0, 0
    iend

CompressedFileStream_class:
    istruc RttiClass
        at RttiClass.name,      dq name_cfs
        at RttiClass.size,      dq CompressedFileStream_size
        at RttiClass.parent,    dq FileStream_class
        at RttiClass.depth,     dq 2
        at RttiClass.display,   dq Stream_class, FileStream_class, CompressedFileStream_class, 0
    iend

; The outsider. Same object model, no shared ancestry: its parent is NULL and
; its display holds only itself, so every is_a between it and the Stream family
; is a definite no - in both directions.
Widget_class:
    istruc RttiClass
        at RttiClass.name,      dq name_widget
        at RttiClass.size,      dq Widget_size
        at RttiClass.parent,    dq 0
        at RttiClass.depth,     dq 0
        at RttiClass.display,   dq Widget_class, 0, 0, 0
    iend

; Vtables: slot 0 is the class (RTTI), slot 1 is describe (dispatch).
Stream_vtable:
    dq Stream_class
    dq Stream_describe

FileStream_vtable:
    dq FileStream_class
    dq FileStream_describe

CompressedFileStream_vtable:
    dq CompressedFileStream_class
    dq CompressedFileStream_describe

Widget_vtable:
    dq Widget_class
    dq Widget_describe

; ---------------------------------------------------------------------------
section .text

; -- constructors -----------------------------------------------------------
; Stream *Stream_new(void)
global Stream_new
Stream_new:
    prologue
    mov     rdi, Stream_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Stream_vtable]
    mov     [rax + Stream.vptr], rcx    ; the store that makes it a Stream
    epilogue
.oom:
    ccall   abort

; FileStream *FileStream_new(long fd)
global FileStream_new
FileStream_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; fd
    mov     rdi, FileStream_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [FileStream_vtable]
    mov     [rax + FileStream.vptr], rcx
    mov     [rax + FileStream.fd], rbx
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; CompressedFileStream *CompressedFileStream_new(long fd, long ratio)
global CompressedFileStream_new
CompressedFileStream_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; fd
    mov     r12, rsi                    ; ratio
    mov     rdi, CompressedFileStream_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [CompressedFileStream_vtable]
    mov     [rax + CompressedFileStream.vptr], rcx
    mov     [rax + CompressedFileStream.fd], rbx
    mov     [rax + CompressedFileStream.ratio], r12
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; Widget *Widget_new(long w, long h)
global Widget_new
Widget_new:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; w
    mov     r12, rsi                    ; h
    mov     rdi, Widget_size
    ccall   malloc
    test    rax, rax
    jz      .oom
    lea     rcx, [Widget_vtable]
    mov     [rax + Widget.vptr], rcx
    mov     [rax + Widget.w], rbx
    mov     [rax + Widget.h], r12
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; -- the one derived-only accessor ------------------------------------------
; long CompressedFileStream_ratio(CompressedFileStream *this)
global CompressedFileStream_ratio
CompressedFileStream_ratio:
    mov     rax, [rdi + CompressedFileStream.ratio]
    ret

; -- describe (virtual): each reads its own name via the class descriptor ----
; slot 0 of the vtable gives the name (identity); the body formats the fields
; (behaviour). One vtable, two jobs.
Stream_describe:
    prologue
    class_of rax, rdi
    mov     rsi, [rax + RttiClass.name]
    lea     rdi, [fmt_stream]
    xor     eax, eax
    ccall   printf
    epilogue

FileStream_describe:
    prologue
    mov     rdx, [rdi + FileStream.fd]
    class_of rax, rdi
    mov     rsi, [rax + RttiClass.name]
    lea     rdi, [fmt_filestream]
    xor     eax, eax
    ccall   printf
    epilogue

CompressedFileStream_describe:
    prologue
    mov     rcx, [rdi + CompressedFileStream.ratio]
    mov     rdx, [rdi + CompressedFileStream.fd]
    class_of rax, rdi
    mov     rsi, [rax + RttiClass.name]
    lea     rdi, [fmt_cfs]
    xor     eax, eax
    ccall   printf
    epilogue

Widget_describe:
    prologue
    mov     rcx, [rdi + Widget.h]
    mov     rdx, [rdi + Widget.w]
    class_of rax, rdi
    mov     rsi, [rax + RttiClass.name]
    lea     rdi, [fmt_widget]
    xor     eax, eax
    ccall   printf
    epilogue
