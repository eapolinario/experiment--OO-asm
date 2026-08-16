;; libc.inc - the handful of C library symbols the exercises lean on.
;;
;; We deliberately borrow libc for I/O and the heap: the experiment is about
;; building an *object system*, not about re-implementing printf or malloc.
;; Everything above the allocator - layout, dispatch, inheritance, interfaces,
;; RTTI, message sends, reference counting - is written from scratch here.

%ifndef LIBC_INC
%define LIBC_INC

extern printf
extern snprintf
extern puts
extern putchar
extern malloc
extern calloc
extern realloc
extern free
extern strcmp
extern strlen
extern memcpy
extern memset
extern abort

%endif ; LIBC_INC
