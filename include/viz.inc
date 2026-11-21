;; viz.inc - a text canvas, so a program can draw the memory it just built.
;;
;; Every technique in this repository is the same picture: 8-byte words in a
;; box, and arrows between boxes. The exercises print *facts* about that
;; picture ("two Circles share one vtable: yes"); a `viz` program prints the
;; picture itself, drawn from the same live data.
;;
;; The rule that makes this worth doing: nothing here is hand-drawn art. A box
;; is as many rows tall as the class descriptor says the instance is bytes
;; wide, divided by eight. An arrow leaves the row a vptr actually occupies.
;; If you add a field, the diagram grows a row without anybody editing it - so
;; it cannot drift from the code the way ASCII art in a README does.
;;
;; The canvas is deliberately built the same way the exercises build objects:
;;
;;      cell(x, y) = buf + y*stride + x
;;
;; a base, a scale, and an offset - `[base + index*scale + disp]`, the address
;; mode this whole tutorial runs on. A row is a struct; the canvas is an array
;; of them. Rows carry a permanent NUL terminator at column `w`, which is why
;; the stride is one byte wider than the canvas: it makes every row a C string
;; that `puts` can print directly.
;;
;; ASCII only, `+ - | >`, matching the diagrams already in object.inc and the
;; exercise READMEs - and keeping the output diffable as a golden file.
;;
;; Geometry. A "word box" is a column of 8-byte words. Word `i` of a box drawn
;; at `y` has its border line at VIZ_BORDER(y,i) and its text at VIZ_ROW(y,i);
;; a box of `n` words is VIZ_HEIGHT(n) lines tall, closing border included:
;;
;;      y+0   +----------------+     VIZ_BORDER(y,0)
;;      y+1   | +0  vptr       |     VIZ_ROW(y,0)
;;      y+2   +----------------+     VIZ_BORDER(y,1)
;;      y+3   | +8  r = 3      |     VIZ_ROW(y,1)
;;      y+4   +----------------+     VIZ_BORDER(y,2), and VIZ_HEIGHT(2) = 5
;;
;; Writes outside the canvas are dropped rather than trapped, so a diagram that
;; outgrows its canvas loses ink instead of corrupting the heap.

%ifndef VIZ_INC
%define VIZ_INC

%define VIZ_SCRATCH     256                     ; max length of one viz_putf

;; Line of word `i` in a box whose top border is at `y`.
%define VIZ_BORDER(y, i)    ((y) + 2*(i))       ; the `+---+` above word i
%define VIZ_ROW(y, i)       ((y) + 1 + 2*(i))   ; the `|   |` holding word i
%define VIZ_HEIGHT(n)       (1 + 2*(n))         ; total lines of an n-word box

extern viz_open                 ; void viz_open(long w, long h)
extern viz_close                ; void viz_close(void)
extern viz_clear                ; void viz_clear(void)
extern viz_flush                ; void viz_flush(void)   - print, then clear
extern viz_putc                 ; void viz_putc(long x, long y, long ch)
extern viz_puts                 ; void viz_puts(long x, long y, const char *s)
extern viz_putf                 ; void viz_putf(long x, long y, const char *f, ...)
extern viz_hline                ; void viz_hline(long x, long y, long n, long ch)
extern viz_vline                ; void viz_vline(long x, long y, long n, long ch)
extern viz_wordbox              ; void viz_wordbox(long x, long y, long w, long words)
extern viz_arrow                ; void viz_arrow(long x0, long y0, long x1, long y1, long xmid)

;; The macros below are sugar for those calls, in the house style of abi.inc's
;; `print`: later arguments are loaded first, so an expression mentioning rdi
;; or rsi still reads the right thing.

;; vopen w, h
%macro vopen 2
    mov     rsi, %2
    mov     rdi, %1
    call    viz_open
%endmacro

;; vputs x, y, label            - a static string
%macro vputs 3
    lea     rdx, [%3]
    mov     rsi, %2
    mov     rdi, %1
    call    viz_puts
%endmacro

;; vputsr x, y, src             - a string whose address is already a value
%macro vputsr 3
    mov     rdx, %3
    mov     rsi, %2
    mov     rdi, %1
    call    viz_puts
%endmacro

;; vputf x, y, fmt [, a [, b [, c]]]  - printf into the canvas.
;; Values only: a string argument must arrive in a register the caller loaded
;; with `lea`, because a bare label would assemble to an absolute address and
;; this is a position-independent executable.
%macro vputf 3-6
  %if %0 >= 6
    mov     r9, %6
  %endif
  %if %0 >= 5
    mov     r8, %5
  %endif
  %if %0 >= 4
    mov     rcx, %4
  %endif
    lea     rdx, [%3]
    mov     rsi, %2
    mov     rdi, %1
    call    viz_putf
%endmacro

;; vbox x, y, w, words          - a box of `words` 8-byte rows
%macro vbox 4
    mov     rcx, %4
    mov     rdx, %3
    mov     rsi, %2
    mov     rdi, %1
    call    viz_wordbox
%endmacro

;; varrow x0, y0, x1, y1, xmid  - `--->`, or an elbow through column xmid
%macro varrow 5
    mov     r8, %5
    mov     rcx, %4
    mov     rdx, %3
    mov     rsi, %2
    mov     rdi, %1
    call    viz_arrow
%endmacro

;; vflat x0, y0, x1             - the common case: a straight arrow
%macro vflat 3
    varrow  %1, %2, %3, %2, %1
%endmacro

%endif ; VIZ_INC
