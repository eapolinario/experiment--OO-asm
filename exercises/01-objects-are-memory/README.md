# Objects are just memory

**Technique:** structure layout, the receiver pointer, arrays of objects, manual padding.
**New machinery:** none. This is the floor everything else stands on.

## The idea

There is no "object" instruction on any CPU. An object is a base address, and a
type is a promise about what lives at which offset from that address. When you
write `p.y` in C, Java, Rust or Go, the compiler turns it into `[base + 8]`.
That is the whole trick, and it is the reason the rest of this repo is possible:
if a type is only a set of offsets, then anybody - including you, in assembly -
can declare one.

NASM's `struc` emits no bytes at all. It defines absolute symbols:

```asm
struc Point
    .x: resq 1      ; Point.x    = 0
    .y: resq 1      ; Point.y    = 8
endstruc            ; Point_size = 16
```

So `mov rax, [rdi + Point.y]` assembles to exactly `mov rax, [rdi+8]`. The
struct exists in the assembler's symbol table and nowhere else - the same place
a C compiler keeps it.

A "method" at this stage is a plain function whose first argument is the object
it operates on. C++ calls that hidden argument `this`, Python spells it `self`,
Rust spells it `&self`, and all three put it in `rdi` on System V x86-64:

```asm
; void point_translate(Point *this, long dx, long dy)
point_translate:
    add     [rdi + Point.x], rsi
    add     [rdi + Point.y], rdx
    ret
```

Note what this function does *not* need: a stack frame, a heap, a runtime, or a
type tag. Non-virtual methods really are this cheap.

## What the program shows

1. **A type is a set of offsets** - `sizeof` and `offsetof` printed straight
   out of the assembler's symbol table.
2. **One type, three storage classes** - the same 16 bytes interpreted as a
   `Point` whether they live in `.data` (static), on the stack (automatic), or
   in `.bss` (zero-initialised). Storage duration and type are independent.
3. **Methods take a receiver** - `point_show` / `point_translate` operate on
   whatever `rdi` points at.
4. **Arrays of objects are contiguous** - iteration is `add rdi, Point_size`.
   Objects have no per-instance header here, which is exactly why an array of
   them is cache-friendly.
5. **Padding is your job** - `SpriteNaive` and `Sprite` hold the same fields.
   Declared badly, the struct is 26 bytes with qwords at offsets 1 and 10;
   declared well, it is 32 bytes with everything naturally aligned. x86 will
   execute the misaligned loads anyway, more slowly, which is why the bug is
   easy to ship. A C compiler inserts that padding silently; here you are the
   compiler.

## Run it

```console
$ make run          # build and execute
$ make test         # diff against expected.txt
$ make disas        # see what was actually emitted
```

## Try this

- Add `point_equals(Point *a, Point *b) -> long` and use it from `main`.
- Reorder `Sprite`'s fields and watch `Sprite_size` change. Can you get it
  below 32 bytes without misaligning a qword? (Hint: `.alive` and `.kind` are
  one byte each.)
- Change `point_sum_x` to stride by `Point_size * 2` and predict the output
  before running it.
- Run `make disas` and find the `[rdi+8]` that used to be `Point.y`.

## Next

[02 - Methods, encapsulation and the `this` pointer](../02-methods-and-this/) turns
these free functions into a disciplined interface with a private
representation.
