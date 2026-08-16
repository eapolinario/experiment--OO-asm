# Object layout and the receiver

> Exercises: [01](../exercises/01-objects-are-memory/), [02](../exercises/02-methods-and-this/)

## The problem

Machines have memory and registers. They have no notion of an object. So the
first question any object system has to answer is: given a value of some type,
where is its data, and how does code find a particular field of it?

## The technique

An object is a **base address**. A type is a **map from field names to byte
offsets**. That is the entire representation.

```asm
struc Point
    .x: resq 1          ; Point.x = 0
    .y: resq 1          ; Point.y = 8
endstruc                ; Point_size = 16
```

`struc` emits nothing. It defines three absolute symbols in the assembler's
symbol table, so that `mov rax, [rdi + Point.y]` assembles to `mov rax,
[rdi+8]`. A C compiler keeps its struct declarations in exactly the same place
and emits exactly the same instruction. The type exists at compile time; at run
time there are only bytes.

Two consequences follow immediately, and both matter:

- **Field access costs nothing.** It is an addressing mode, not an operation.
  `[rdi + 8]` is free relative to `[rdi]` on any machine built since 1980.
- **There is no type information in an object** unless you put some there.
  Sixteen bytes that you believe are a `Point` are indistinguishable from
  sixteen bytes that are two `long`s. Everything in exercises 04 through 08 is
  about deliberately adding that information back, and paying for it.

## The receiver

A method is a function whose first argument is the object. C++ writes that
argument invisibly and calls it `this`; Python writes it explicitly and calls
it `self`; Rust writes `&self`; Go writes an explicit receiver before the
function name. On System V x86-64 all of them put it in `rdi`.

```asm
; void point_translate(Point *this, long dx, long dy)
point_translate:
    add     [rdi + Point.x], rsi
    add     [rdi + Point.y], rdx
    ret
```

So "calling a method on an object" is: put the object's address in the first
argument register, put the real arguments in the rest, call. The only thing
that distinguishes this from a free function taking a struct pointer is
vocabulary. **A non-virtual method call is exactly as expensive as a C function
call**, because it is one.

The receiver convention has consequences you can feel in language design:

- Extension methods, UFCS proposals, and Rust's `impl` blocks all exploit the
  fact that `a.f(b)` and `f(a, b)` are the same call.
- A "static" or "class" method is just a function in the class's namespace that
  does not take a receiver, which is why it cannot touch instance state - there
  is no `rdi` to touch.

## Layout decisions

Since a type is a set of offsets, choosing the offsets is a design act with
real costs.

**Alignment.** A qword load from an address that is not a multiple of 8 works
on x86 and costs extra when it straddles a cache line; on some architectures it
faults. `struc` never pads, so exercise 01 shows the same fields laid out two
ways: 26 bytes with two misaligned qwords, or 32 bytes with everything aligned.
A C compiler inserts that padding silently and rounds the total size up to the
largest member's alignment, so that arrays stay aligned too.

**Ordering.** Because padding is inserted *between* fields, declaration order
changes `sizeof`. Sorting fields large-to-small is the standard trick, and the
reason tools like `pahole` exist. Rust reorders struct fields for you by
default, which is why `#[repr(C)]` exists for when you need C's rules.

**Arrays.** An array of objects is objects back to back; iteration is `add rdi,
Point_size`. Nothing per-object is stored except the fields themselves, which
is why an array of 10,000 points is 160,000 bytes and streams through the cache
perfectly. Compare with a language where every element is a separately
allocated, headered object reached through a pointer: same code, an order of
magnitude more memory traffic. This single layout difference is most of what
"data-oriented design" is arguing about, and most of the gap between a Java
`Point[]` and a C++ `std::vector<Point>`.

## Encapsulation is a linkage property

Exercise 02 splits a class across two files. The implementation file defines
the layout and marks six functions `global`; the header publishes a size and
those six names. A client physically cannot reach `Stack.len`, because that
symbol does not exist outside the file that defines it.

```asm
%define STACK_SIZEOF    80          ; allocate this much, ask no questions
extern Stack_push
```

This is the same technique as C's opaque pointers (`FILE*`, `pthread_mutex_t`)
and C++'s pimpl idiom. Note what it costs: because the client hard-codes the
size, changing the layout is an **ABI break**. The class must be recompiled
along with every client. Real libraries deal with this by allocating through a
factory function (so only the library knows the size), or by reserving padding,
or by putting everything behind a pointer. `private` in C++ deliberately does
*not* do this: private members are part of the class layout, visible in the
header, and changing them breaks the ABI - `private` controls access, not
knowledge.

The invariant is the reason to bother. `0 <= len <= cap` is checked inside
`Stack_push` and nowhere else, and because no outside code can modify `len`,
the set of places that could break it is one file instead of one program.

## Name mangling

The assembler has one flat namespace, so `push` cannot belong to two classes.
Prefixing the class name (`Stack_push`) is the whole technique; C++ does the
same thing and adds parameter types so that overloads get distinct symbols:

```
Stack::push(long)   ->  _ZN5Stack4pushEl
                         | |    |    |
                         | |    |    +-- parameter list: long
                         | |    +------- method name, length-prefixed
                         | +------------ class name, length-prefixed
                         +-------------- nested-name encoding
```

`c++filt` reverses it. Every "undefined symbol: _ZN..." you have ever seen is
this, and the reason C++ has no stable cross-compiler ABI on Windows is that
Microsoft mangles differently.

## What it costs

| Operation | Cost |
| --- | --- |
| Field access | An addressing mode; free |
| Non-virtual method call | One `call`; identical to a C function call |
| Per-object overhead | Zero, until you add a vptr in exercise 04 |
| Passing an object | One register, if you pass a pointer |

Next: [dispatch](02-dispatch.md), where objects start choosing their own
behaviour and the first real cost appears.
