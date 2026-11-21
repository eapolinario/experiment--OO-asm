;; lib/viz.asm - the text canvas behind `make viz`.
;;
;; A canvas is `h` rows of `stride = w + 1` bytes: `w` drawable columns and a
;; permanent NUL, so every row is already a C string and `viz_flush` can hand
;; it straight to `puts`. Addressing a cell is
;;
;;      mov     rax, y
;;      imul    rax, [viz_stride]
;;      add     rax, [viz_buf]
;;      mov     [rax + x], ch
;;
;; which is the same base-plus-offset arithmetic the exercises use to reach a
;; field: the canvas is an array of row structs, and `stride` is its `sizeof`.
;; That it is one byte larger than the visible row is the same padding decision
;; a compiler makes in exercise 01, taken for the same reason - a layout that
;; makes the common access cheap.
;;
;; There is exactly one canvas. A viz program draws a panel, flushes it, and
;; draws the next one on the cleared canvas; the pictures are printed in the
;; order they are drawn, so the output reads top to bottom like the prose does.
;;
;; Everything clips. A write outside the canvas is dropped, not trapped and not
;; wrapped, so a box that outgrows its panel loses ink at the edge rather than
;; scribbling over the next row's bytes - the one place in this repository
;; where running off the end of an array is handled instead of demonstrated.

%include "abi.inc"
%include "libc.inc"
%include "viz.inc"

section .bss
align 8
viz_buf:        resq 1                  ; char *: h rows of `stride` bytes
viz_w:          resq 1                  ; drawable columns
viz_h:          resq 1                  ; rows
viz_stride:     resq 1                  ; w + 1, the extra byte being the NUL
viz_scratch:    resb VIZ_SCRATCH        ; viz_putf formats here first

section .text

; ---------------------------------------------------------------------------
; void viz_open(long w, long h)
; ---------------------------------------------------------------------------
global viz_open
viz_open:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; w
    mov     r12, rsi                    ; h
    mov     [viz_w], rbx
    mov     [viz_h], r12
    lea     rax, [rbx + 1]              ; stride: one spare byte for the NUL
    mov     [viz_stride], rax
    imul    rax, r12
    mov     rdi, rax
    ccall   malloc
    test    rax, rax
    jz      .oom
    mov     [viz_buf], rax
    call    viz_clear
    pop     r12
    pop     rbx
    epilogue
.oom:
    ccall   abort

; ---------------------------------------------------------------------------
; void viz_close(void)
; ---------------------------------------------------------------------------
global viz_close
viz_close:
    prologue
    mov     rdi, [viz_buf]
    ccall   free
    mov     qword [viz_buf], 0
    epilogue

; ---------------------------------------------------------------------------
; void viz_clear(void)
;
; Blank the canvas and restore the terminator at the end of every row.
; ---------------------------------------------------------------------------
global viz_clear
viz_clear:
    prologue
    push    rbx
    push    r12
    mov     rax, [viz_stride]
    imul    rax, [viz_h]
    mov     rdx, rax                    ; total bytes
    mov     rsi, ' '
    mov     rdi, [viz_buf]
    ccall   memset

    xor     rbx, rbx                    ; y
.row:
    cmp     rbx, [viz_h]
    jae     .done
    mov     rax, rbx
    imul    rax, [viz_stride]
    add     rax, [viz_buf]
    add     rax, [viz_w]                ; one past the last drawable column
    mov     byte [rax], 0
    inc     rbx
    jmp     .row
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; char *viz_rowptr(long y)
; ---------------------------------------------------------------------------
viz_rowptr:
    mov     rax, rdi
    imul    rax, [viz_stride]
    add     rax, [viz_buf]
    ret

; ---------------------------------------------------------------------------
; long viz_rowlen(long y)
;
; The row's length with trailing spaces ignored - zero for a blank row.
; ---------------------------------------------------------------------------
viz_rowlen:
    prologue
    push    rbx
    push    r12
    call    viz_rowptr
    mov     rbx, rax
    mov     rax, [viz_w]
.trim:
    test    rax, rax
    jz      .done
    cmp     byte [rbx + rax - 1], ' '
    jne     .done
    dec     rax
    jmp     .trim
.done:
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void viz_flush(void)
;
; Print the canvas, then clear it for the next panel.
;
; Blank rows below the last one with ink are dropped, and trailing spaces are
; trimmed, so one canvas can be opened at the largest panel's size and every
; smaller panel still prints tight. The output is a golden file, and invisible
; whitespace is exactly what makes a golden file fail for no reason.
; ---------------------------------------------------------------------------
global viz_flush
viz_flush:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, [viz_h]                ; scan up for the last row with ink
.scan:
    test    rbx, rbx
    jz      .done                       ; nothing drawn at all
    dec     rbx
    mov     rdi, rbx
    call    viz_rowlen
    test    rax, rax
    jz      .scan

    xor     r12, r12                    ; y
.row:
    cmp     r12, rbx
    ja      .done
    mov     rdi, r12
    call    viz_rowlen
    mov     r13, rax                    ; trimmed length
    mov     rdi, r12
    call    viz_rowptr
    ; r13 <= w, so at worst this rewrites the NUL that is already there.
    mov     byte [rax + r13], 0
    mov     rdi, rax
    ccall   puts
    inc     r12
    jmp     .row
.done:
    call    viz_clear
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void viz_putc(long x, long y, long ch)
;
; A leaf, and the one function every other drawing primitive goes through, so
; the bounds check lives here and nowhere else. The comparisons are unsigned:
; a negative coordinate is a very large one, and fails the same test.
; ---------------------------------------------------------------------------
global viz_putc
viz_putc:
    cmp     rdi, [viz_w]
    jae     .off_canvas
    cmp     rsi, [viz_h]
    jae     .off_canvas
    mov     rax, rsi
    imul    rax, [viz_stride]
    add     rax, [viz_buf]
    mov     [rax + rdi], dl
.off_canvas:
    ret

; ---------------------------------------------------------------------------
; void viz_puts(long x, long y, const char *s)
;
; Opaque: the spaces inside `s` erase what they land on, so a label drawn over
; a border cuts a hole in it. Panels are laid out not to overlap.
; ---------------------------------------------------------------------------
global viz_puts
viz_puts:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; x, walking right
    mov     r12, rsi                    ; y
    mov     r13, rdx                    ; s
.next:
    movzx   edx, byte [r13]
    test    dl, dl
    jz      .done
    mov     rdi, rbx
    mov     rsi, r12
    call    viz_putc
    inc     rbx
    inc     r13
    jmp     .next
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void viz_putf(long x, long y, const char *fmt, long a, long b)
;
; printf, into the canvas. fmt/a/b already sit in rdx/rcx/r8, which is where
; snprintf wants its third, fourth and fifth arguments - only the destination
; and the size have to be moved into place.
; ---------------------------------------------------------------------------
global viz_putf
viz_putf:
    prologue
    push    rbx
    push    r12
    mov     rbx, rdi                    ; x
    mov     r12, rsi                    ; y
    lea     rdi, [viz_scratch]
    mov     rsi, VIZ_SCRATCH
    xor     eax, eax                    ; no vector registers in this call
    ccall   snprintf
    mov     rdi, rbx
    mov     rsi, r12
    lea     rdx, [viz_scratch]
    call    viz_puts
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void viz_hline(long x, long y, long n, long ch)
; ---------------------------------------------------------------------------
global viz_hline
viz_hline:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; x
    mov     r12, rsi                    ; y
    mov     r13, rdx                    ; cells left
    mov     r14, rcx                    ; ch
.next:
    test    r13, r13
    jle     .done                       ; a non-positive run draws nothing
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r14
    call    viz_putc
    inc     rbx
    dec     r13
    jmp     .next
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void viz_vline(long x, long y, long n, long ch)
; ---------------------------------------------------------------------------
global viz_vline
viz_vline:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; x
    mov     r12, rsi                    ; y, walking down
    mov     r13, rdx
    mov     r14, rcx
.next:
    test    r13, r13
    jle     .done
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r14
    call    viz_putc
    inc     r12
    dec     r13
    jmp     .next
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void viz_wordbox(long x, long y, long w, long words)
;
; A column of `words` machine words, `w` columns wide: a border line, a text
; line, a border line, and so on, closing with a border. The caller writes the
; contents with viz_putf at VIZ_ROW(y, i) - see viz.inc for the geometry.
;
; The word count is the only thing a diagram needs to know about a type's size,
; which is why the viz programs pass `[class + Class.size] / 8` and never a
; literal: the box is as tall as the object is big.
; ---------------------------------------------------------------------------
global viz_wordbox
viz_wordbox:
    prologue
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                    ; x
    mov     r12, rsi                    ; y of the line being drawn
    mov     r13, rdx                    ; w
    mov     r14, rcx                    ; words left below this border
.row:
    mov     rdi, rbx                    ; ---- the border line ----
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, '-'
    call    viz_hline
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, '+'
    call    viz_putc
    lea     rdi, [rbx + r13 - 1]
    mov     rsi, r12
    mov     rdx, '+'
    call    viz_putc

    test    r14, r14
    jz      .done                       ; the closing border, and out

    mov     rdi, rbx                    ; ---- the text line ----
    lea     rsi, [r12 + 1]
    mov     rdx, '|'
    call    viz_putc
    lea     rdi, [rbx + r13 - 1]
    lea     rsi, [r12 + 1]
    mov     rdx, '|'
    call    viz_putc

    add     r12, 2
    dec     r14
    jmp     .row
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    epilogue

; ---------------------------------------------------------------------------
; void viz_arrow(long x0, long y0, long x1, long y1, long xmid)
;
; A pointer. Straight when the two rows line up:
;
;       ------->
;
; and an elbow through column `xmid` when they do not, which is what a vptr
; stored partway down an object needs in order to reach a table drawn beside
; it:
;
;       ---+
;          |
;          +--->
;
; Five arguments is more than the four the exercises ever need, so this one
; keeps them in stack slots rather than fighting over callee-saved registers.
; ---------------------------------------------------------------------------
global viz_arrow
viz_arrow:
    prologue 40
    mov     [rbp - 8], rdi              ; x0
    mov     [rbp - 16], rsi             ; y0
    mov     [rbp - 24], rdx             ; x1
    mov     [rbp - 32], rcx             ; y1
    mov     [rbp - 40], r8              ; xmid

    mov     rax, [rbp - 16]
    cmp     rax, [rbp - 32]
    jne     .elbow

    ; ---- same row: one run and a head -------------------------------------
    mov     rdi, [rbp - 8]
    mov     rsi, [rbp - 16]
    mov     rdx, [rbp - 24]
    sub     rdx, rdi                    ; x0 .. x1-1
    mov     rcx, '-'
    call    viz_hline
    jmp     .head

.elbow:
    ; ---- out to xmid, down or up, then in to x1 ---------------------------
    mov     rdi, [rbp - 8]
    mov     rsi, [rbp - 16]
    mov     rdx, [rbp - 40]
    sub     rdx, rdi                    ; x0 .. xmid-1
    mov     rcx, '-'
    call    viz_hline
    mov     rdi, [rbp - 40]
    mov     rsi, [rbp - 16]
    mov     rdx, '+'
    call    viz_putc

    mov     rax, [rbp - 16]             ; the run between the two rows,
    mov     rcx, [rbp - 32]             ; whichever way it goes
    cmp     rax, rcx
    jle     .ordered
    xchg    rax, rcx
.ordered:
    mov     rdx, rcx
    sub     rdx, rax
    dec     rdx                         ; the rows strictly between
    mov     rdi, [rbp - 40]
    lea     rsi, [rax + 1]
    mov     rcx, '|'
    call    viz_vline

    mov     rdi, [rbp - 40]
    mov     rsi, [rbp - 32]
    mov     rdx, '+'
    call    viz_putc
    mov     rdi, [rbp - 40]
    inc     rdi
    mov     rsi, [rbp - 32]
    mov     rdx, [rbp - 24]
    sub     rdx, rdi                    ; xmid+1 .. x1-1
    mov     rcx, '-'
    call    viz_hline

.head:
    mov     rdi, [rbp - 24]
    mov     rsi, [rbp - 32]
    mov     rdx, '>'
    call    viz_putc
    epilogue
