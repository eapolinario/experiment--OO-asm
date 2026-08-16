# Object orientation, implemented from scratch in x86-64 assembly

The claim under test:

> "Object oriented" is not a language feature. It is a set of implementation
> techniques - a discipline you can practise in any language, including
> assembly, if you are willing to do by hand what a compiler would otherwise
> do for you.

That idea is easy to nod along with and surprisingly hard to picture. What
*exactly* would you be doing by hand? This repository answers by doing it: ten
runnable programs in NASM, each adding one technique that an object-oriented
language would have handed you for free, in increasing order of difficulty.

By exercise 10 there are objects, encapsulation, constructors and destructors,
virtual dispatch, inheritance, interfaces with multiple bases, runtime type
information, message passing with method caches, prototype delegation, and
reference counting - all of it built out of nothing but memory layout,
function pointers, and rules that nobody enforces except you.

## Quick start

```console
$ nix develop                 # nasm, gcc, gdb, valgrind, make
$ make                        # assemble and link every exercise
$ make test                   # run them all, diff against the golden output
$ make list                   # the ladder, with one-line summaries

$ make -C exercises/04-vtables run       # one exercise
$ make -C exercises/04-vtables disas     # what the assembler really emitted
```

Or without entering the shell at all:

```console
$ nix flake check             # builds and runs everything in a sandbox
```

Targets x86-64 Linux (System V ABI, ELF, PIE). libc is borrowed for `printf`
and `malloc` and nothing else - everything above the allocator is written here.

## What you need to know

Less assembly than you would expect, and more pointers.

**You need to be comfortable with pointers.** That is the actual prerequisite.
Everything here is "a register holds an address, and the field is at a constant
offset from it". If `p->field` compiling to `[base + 8]` sounds reasonable, you
can read this. If you have never worked with a pointer, start with C or Go for
a week and come back - the exercises will fight you otherwise.

**You do not need to know assembly.** You need to *read* about twenty
instructions, five of which are most of the text: `mov` (copy), `lea` (compute
an address without dereferencing it), `call`/`ret`, `push`/`pop`, plus
`cmp`/`test` and the conditional jumps. There is no SIMD, no floating point
(everything is fixed-point integers), no syscalls, and no string instructions.
You are never asked to write assembly to follow along, only to modify it if you
want to try the exercises at the end of each README.

**The conventions are documented where they are used.**
[`include/abi.inc`](include/abi.inc) is a crib sheet for the calling
convention: which registers pass arguments, which are yours to clobber, and the
stack alignment rule. Read it once before exercise 01 and refer back. Two
things are assumed rather than taught, and both only matter if you start
editing: how the linker resolves symbols across files, and why addresses are
rip-relative in a position-independent executable.

**The ramp is not even.** Exercises 01 to 05 build steadily and each one is
short. Exercise 06 is the first genuine step up - it is about pointer
adjustment, and the difficulty is conceptual rather than instructional.
Exercise 08 is the densest code in the repository, because a cache is
bookkeeping. If you stall, the exercise READMEs and [`docs/`](docs/) explain
the same idea in prose, and every program prints its own evidence, so running
it is often faster than reading it.

**If you are here from a high-level language**, the payoff is in `docs/`. The
running comparison is Python, because CPython is an object system written in C
and the mapping is exact rather than metaphorical: `ob_type` is the vptr,
`PyTypeObject`'s slots are the vtable, `Py_INCREF` is exercise 10.

## The ladder

| # | Exercise | Technique | The point |
| --- | --- | --- | --- |
| 01 | [objects are memory](exercises/01-objects-are-memory/) | struct layout, the receiver | A type is a set of offsets; a method is a function taking `this` in `rdi` |
| 02 | [methods and `this`](exercises/02-methods-and-this/) | name mangling, opaque types | `private` is not a keyword, it is a symbol you did not export |
| 03 | [constructors and the heap](exercises/03-constructors-and-heap/) | lifetime, ownership | Allocation and construction are different operations, and so are their inverses |
| 04 | [vtables](exercises/04-vtables/) | dynamic dispatch | Two loads and an indirect call. This is the whole of `virtual` |
| 05 | [inheritance](exercises/05-inheritance/) | prefix layout, overriding | A derived object *is* a base object, because the base is its first field |
| 06 | [interfaces](exercises/06-interfaces/) | secondary vtables, thunks | Two bases cannot both live at offset 0, and everything follows from that |
| 07 | [RTTI](exercises/07-rtti/) | class descriptors, downcasts | `instanceof` is a walk up a chain of pointers |
| 08 | [message passing](exercises/08-message-passing/) | selectors, method caches | Dispatch by name instead of by slot, and then make it fast again |
| 09 | [prototypes](exercises/09-prototypes/) | property bags, delegation | Classes are optional; V8 reinvents them at run time anyway |
| 10 | [reference counting](exercises/10-reference-counting/) | automatic lifetime | The one question layout cannot answer: *when* does an object die |

Each exercise is self-contained: sources, a `README.md` explaining the
technique and what to look for, and an `expected.txt` that the test suite
diffs against, so every claim in the prose is backed by a program that still
runs.

## The deep dive

The exercise READMEs explain *this program*. The documents in
[`docs/`](docs/) explain *the technique*: what problem it solves, how it is
laid out in memory, what it costs, and what real toolchains do differently.

- [00 - The thesis](docs/00-thesis.md): what "object oriented" decomposes into,
  and why knowing that is useful
- [01 - Object layout and the receiver](docs/01-object-layout.md): offsets,
  alignment, `this`, name mangling, encapsulation as a linkage property
- [02 - Dispatch](docs/02-dispatch.md): static vs virtual, why slot numbers are
  ABI, and what a virtual call actually costs (hint: it is branch prediction
  and lost inlining, not the two loads)
- [03 - Inheritance](docs/03-inheritance.md): the prefix property, vtable
  copy-and-override, constructor order, virtual destructors, fragile base
  classes
- [04 - Interfaces and multiple inheritance](docs/04-interfaces.md): secondary
  vtables, adjustor thunks, `offset_to_top`, and the fat-pointer alternative
  that Go and Rust chose
- [05 - Runtime type information](docs/05-rtti.md): chain walks, constant-time
  subtype tests, and what `dynamic_cast` really costs
- [06 - Message passing](docs/06-message-passing.md): selectors,
  `doesNotUnderstand`, inline caches, and why `objc_msgSend` is hand-written
  assembly
- [07 - Prototypes and delegation](docs/07-prototypes.md): property bags,
  shadowing, and how hidden classes rebuild exercises 01 and 04 at run time
- [08 - Object lifetime](docs/08-object-lifetime.md): manual, RAII, reference
  counting, cycles, weak references, tracing collection
- [09 - Further reading](docs/09-further-reading.md): the ABI documents, the
  papers, the runtime sources, and the tools that show you the answer directly

## The object model

Everything from exercise 04 onward obeys three rules, defined in
[`include/object.inc`](include/object.inc):

```
  object                    vtable                   class descriptor
  +--------------+          +---------------+        +--------------+
  | vptr         |--------->| class         |------->| name         |
  +--------------+          +---------------+        | size         |
  | field 0      |          | slot 0        |        | parent       |
  | field 1      |          | slot 1        |        +--------------+
  | ...          |          | ...           |
  +--------------+          +---------------+
```

1. The vptr sits at offset 0 of every polymorphic object, so code that only
   needs to dispatch can treat every object identically.
2. A vtable is per-class and immutable. A thousand instances cost a thousand
   8-byte pointers, not a thousand method tables.
3. Slot numbers are ABI. Append or overwrite, never reorder.

Exercise 06 has to extend that layout, and the fact that it *has* to is one of
the more interesting things in the repository.

## Repository layout

```
flake.nix                 pinned toolchain; `nix flake check` runs everything
Makefile                  drives every exercise
mk/common.mk              per-exercise rules: all, run, test, record, disas
include/
  abi.inc                 System V calling convention, prologue/epilogue, print
  object.inc              the object model: vptr, vtable, Class, vcall
  libc.inc                the few libc symbols we borrow
docs/                     the technique deep dives
exercises/NN-name/        sources, README.md, expected.txt, Makefile
```

Tests are golden-output diffs, which has a useful side effect: an exercise may
never print a raw pointer, so nothing depends on ASLR and every printed fact
has to be a derived one (are these two vptrs equal? how many bytes apart are
these subobjects?).

## Conventions

- Every `.asm` includes `abi.inc`, which sets `default rel`, defines the
  calling-convention helpers, and emits the non-executable-stack marker.
- The receiver is always `rdi`. Methods are named `Class_method`.
- Comments explain *why*, and connect the code to what real toolchains do.
  Nothing comments `mov rax, 5`.
- New exercises get a directory, a `Makefile` containing one `include` line,
  a README with the same section structure, and a recorded `expected.txt`.

## Status

The ten exercises and the docs are done. Open
[issues](https://github.com/eapolinario/experiment--OO-asm/issues) track the
stretch goals: an AArch64 port, a dispatch benchmark, a diff against what g++
actually emits, exceptions and stack unwinding, and a mark-and-sweep collector
built on exercise 10.
