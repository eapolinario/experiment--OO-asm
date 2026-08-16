# The thesis

Steve Yegge has a line, in one of his rants about languages and the people who
love them, to the effect that object orientation is not a language feature but
a *discipline*: you can write object-oriented code in C, or in assembly, if you
are willing to do by hand what a compiler would otherwise do for you. That
claim is easy to nod along with and surprisingly hard to picture. What exactly
would you be doing by hand?

This repository answers that question the only way it can be answered honestly:
by doing it. Ten programs, in x86-64 assembly, each adding one technique that
an object-oriented language would have given you for free.

## What "object oriented" decomposes into

Strip the vocabulary away and a language's object system is a small set of
implementation techniques, each of which is independently understandable:

| Feature you are sold | Technique you are actually buying | Exercise |
| --- | --- | --- |
| Objects, fields | A base address and agreed offsets | [01](../exercises/01-objects-are-memory/) |
| Methods, `this`/`self` | A calling convention: the receiver is argument 0 | [01](../exercises/01-objects-are-memory/), [02](../exercises/02-methods-and-this/) |
| Encapsulation, `private` | Symbol visibility; publish a size, not a layout | [02](../exercises/02-methods-and-this/) |
| Constructors, destructors | Separating "get storage" from "establish the invariant" | [03](../exercises/03-constructors-and-heap/) |
| `virtual`, polymorphism | A pointer at offset 0 to a per-class table of code pointers | [04](../exercises/04-vtables/) |
| Inheritance, `super` | Base layout as a prefix; copy the table, overwrite some slots | [05](../exercises/05-inheritance/) |
| Interfaces, multiple bases | Secondary vtables and thunks that fix up `this` | [06](../exercises/06-interfaces/) |
| `instanceof`, `dynamic_cast` | A class descriptor chain, walked at run time | [07](../exercises/07-rtti/) |
| Duck typing, `method_missing` | Dispatch on an interned name, with a cache | [08](../exercises/08-message-passing/) |
| Prototypes, monkey patching | A property bag plus a delegation pointer | [09](../exercises/09-prototypes/) |
| Automatic lifetime, ARC | A counter in a header, and rules about who adjusts it | [10](../exercises/10-reference-counting/) |

Nothing on the right-hand side requires language support. All of it requires
*discipline*, because when you build it yourself there is nobody to stop you
from breaking your own rules. That is the real content of the claim: the
compiler is not doing anything you could not do, it is doing it *consistently*.

## Why bother knowing this

Three practical reasons, beyond the pleasure of it.

**You stop guessing about cost.** "Virtual calls are slow" turns into a
concrete claim you can evaluate: two dependent loads and an indirect branch,
which is nothing if the call site is monomorphic and the predictor is warm, and
which is a pipeline stall if it is megamorphic. "Interfaces are slower than
inheritance" turns into: one extra pointer adjustment, or a second word in
every interface value. Once you have written the dispatch sequence, the
performance discussion becomes arithmetic instead of vibes.

**You can answer the questions your own language dodges.** Why does
`__slots__` make instances smaller and faster? Why can you add a method to a
class at run time in Python but not in Java? Why does CPython ship a `gc`
module when it already reference counts every object? Why is `isinstance`
cheap but `__getattr__` a performance cliff? Each of those is a design choice
in this repository, made visible - and once you have written both sides, the
answers stop being trivia and become the same three or four mechanisms
recombined.

**You can build objects where there are none.** Every large C program grows an
object system eventually: CPython's own `PyObject` header and `PyTypeObject`
slot table are exactly exercises 01 and 04, the Linux kernel's
`struct file_operations` is a vtable, and Postgres, libcurl and SQLite all
ship dispatch tables. Knowing the techniques means recognising the shape and
choosing deliberately, instead of reinventing a worse version.

## The language on the right-hand side

Assembly says how; something has to say why anyone would want it. Where these
documents need a language to point at, they mostly point at **Python**, for one
reason: CPython is an object system implemented in C, so the mapping is
concrete rather than analogical. `PyObject` really does begin with a refcount
and a type pointer. `PyTypeObject` really is a table of slots. `Py_INCREF` is
exercise 10, `_PyType_Lookup` and its cache are exercise 08, and
`__getattr__` is exercise 09. When you read `ob_type`, you are reading the vptr
from exercise 04.

Other languages appear where they made a genuinely different choice - Go and
Rust on interface layout, Smalltalk and Objective-C on message sends,
JavaScript on prototypes, C++ where a symbol name or an ABI rule is the
artifact worth showing. The point is never the language. It is that the same
handful of mechanisms keeps reappearing under different syntax.

## Ground rules for the experiment

- **x86-64 System V, NASM syntax, ELF.** The techniques are architecture
  independent; the encodings are not. See the AArch64 note in
  [09-further-reading.md](09-further-reading.md).
- **libc is borrowed for `printf` and `malloc` and nothing else.** The
  experiment is about the object system, not about re-implementing an
  allocator. Everything above the allocator is written here.
- **Every claim is demonstrated by a running program.** Each exercise prints
  evidence, and the printed output is checked against a golden file, so a
  regression is a failing test rather than a misleading paragraph.
- **Nothing is printed that is not deterministic.** No raw pointers, no
  addresses, no timings in the golden output. Facts about pointers (are these
  two equal? how many bytes apart are they?) are printed instead.

## How to read this

Start with [01-object-layout.md](01-object-layout.md) and walk up, or start
with the exercise that answers a question you already have. Each document
covers one technique: what problem it solves, how it is laid out in memory,
what it costs, and what real toolchains do differently.

1. [Object layout and the receiver](01-object-layout.md)
2. [Dispatch: static, virtual, and what a vtable costs](02-dispatch.md)
3. [Inheritance](03-inheritance.md)
4. [Interfaces and multiple inheritance](04-interfaces.md)
5. [Runtime type information](05-rtti.md)
6. [Message passing](06-message-passing.md)
7. [Prototypes and delegation](07-prototypes.md)
8. [Object lifetime](08-object-lifetime.md)
9. [Further reading](09-further-reading.md)
