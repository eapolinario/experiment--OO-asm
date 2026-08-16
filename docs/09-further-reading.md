# Further reading

Sources worth going to directly, grouped by the technique they explain.

## An object system you can read

- **CPython's `Include/object.h`.** Twenty minutes with this file is the
  shortest path from "objects are a language feature" to "objects are a struct
  with a header". `PyObject` is a refcount and a type pointer - exercises 10
  and 04, in that order. `PyTypeObject` is a table of function-pointer slots:
  `tp_repr`, `tp_call`, `tp_iter`, `tp_getattro`. That is the vtable.
- **`Objects/typeobject.c`**, for the parts that are harder than they look:
  `_PyType_Lookup` and its method cache (exercise 08), MRO computation
  (exercise 05), and the `tp_basicsize` layout rules that produce the
  "multiple bases have instance lay-out conflict" error (exercise 06).
- **`Modules/gcmodule.c` and `Include/refcount.h`**, for reference counting
  plus the cycle collector that has to exist alongside it (exercise 10).
- **The `ctypes` and `struct` modules**, for poking at exercise 01's world from
  Python: explicit layout, explicit padding, explicit alignment.

## The layer underneath

- **System V AMD64 psABI** -
  <https://gitlab.com/x86-psABIs/x86-64-ABI>. Argument registers, stack
  alignment, the red zone, and why the receiver is in `rdi`.
- **Stanley Lippman, *Inside the C++ Object Model* (1996).** If you want the
  fully worked version of exercises 04 to 06 in a compiled language - vptr
  placement, constructor semantics, and the real cost of multiple and virtual
  inheritance - this is still the clearest treatment.

## Doing this in C, seriously

- **Axel-Tobias Schreiner, *Object-Oriented Programming With ANSI-C* (1993).**
  The book-length version of this repository, one level up the abstraction
  ladder. Freely available.
- **GObject** - <https://docs.gtk.org/gobject/>. A complete, production class
  system in C: classes, single inheritance, interfaces, properties, signals,
  and reference counting, all built out of structs and function pointers. When
  you want to see where the techniques go at scale, read GObject.
- **The Linux kernel's `struct file_operations`, `struct device`, and the
  `container_of` macro.** Vtables and downcasting, in a codebase that would
  never describe itself as object-oriented.

## Dispatch, measured

- **Karel Driesen and Urs Hölzle, "The Direct Cost of Virtual Function Calls in
  C++" (OOPSLA 1996).** The paper behind the numbers people quote badly.
- **L. Peter Deutsch and Allan Schiffman, "Efficient Implementation of the
  Smalltalk-80 System" (POPL 1984).** Inline caches, invented.
- **Urs Hölzle, Craig Chambers, David Ungar, "Optimizing Dynamically-Typed
  Object-Oriented Languages With Polymorphic Inline Caches" (ECOOP 1991).**
  The follow-up that makes polymorphic sites fast, and the ancestor of every
  JIT's type feedback.
- **Norman Cohen, "Type-Extension Type Tests Can Be Performed In Constant
  Time" (TOPLAS 1991)** and **Vitek, Horspool, Krall, "Efficient Type Inclusion
  Tests" (OOPSLA 1997).** The depth-and-display trick in exercise 07, and what
  to do when single inheritance is not enough.

## Message passing and prototypes

- **Apple's `objc4` runtime source** -
  <https://github.com/apple-oss-distributions/objc4>. Read `objc-msg-x86_64.s`
  and notice that the hottest function in the system is hand-written assembly
  built around a cache probe. Exercise 08 is a toy version of that file.
- **David Ungar and Randall Smith, "Self: The Power of Simplicity" (OOPSLA
  1987).** Prototypes, argued from first principles.
- **V8's documentation on fast properties and hidden classes** -
  <https://v8.dev/blog/fast-properties>, plus Vyacheslav Egorov's
  "Explaining JavaScript VMs in JavaScript" series at <https://mrale.ph>.
  How a prototype language rebuilds classes and vtables at run time.
- **Russ Cox, "Go Data Structures: Interfaces"** -
  <https://research.swtch.com/interfaces>. The fat-pointer design of exercise
  06, explained by one of its implementers.
- **Alan Kay, "The Early History of Smalltalk" (1993).** For what "object
  oriented" was supposed to mean before it meant class hierarchies.

## Lifetime

- **Richard Jones, Antony Hosking, Eliot Moss, *The Garbage Collection
  Handbook* (2nd ed., 2023).** Comprehensive and readable.
- **CPython's `Include/object.h` and `Modules/gcmodule.c`.** Reference counting
  and the cycle collector that has to exist alongside it, in about as few lines
  as the idea can be expressed.
- **Swift's ownership and ARC documentation**, for what happens when a compiler
  takes over the retain/release calls.

## Theory, if you want the vocabulary to be precise

- **Luca Cardelli and Peter Wegner, "On Understanding Types, Data Abstraction,
  and Polymorphism" (Computing Surveys, 1985).** Where "parametric" versus
  "ad-hoc" versus "subtype" polymorphism come from.
- **Barbara Liskov and Jeannette Wing, "A Behavioral Notion of Subtyping"
  (1994).** The substitution principle, stated properly - and a reminder that
  the machine only guarantees the offsets line up.
- **William Cook, "On Understanding Data Abstraction, Revisited" (OOPSLA
  2009).** Objects versus abstract data types, and why the distinction is not
  pedantry.

## The prompt for this repository

- **Steve Yegge's blog** - <https://steve-yegge.blogspot.com>. The claim that
  object orientation is a discipline rather than a language feature runs
  through several of his posts; "The Universal Design Pattern" is the one that
  argues property bags with delegation (exercise 09) underlie everything else,
  and "Execution in the Kingdom of Nouns" is the one about what happens when a
  language forces the discipline on you.

## Tools that show you the answer directly

Verify flags against your own compiler version; the dump options in particular
move around between releases.

```console
# What does an object actually look like, from Python?
python3 -c "import sys; print(sys.getsizeof(object()), sys.getsizeof(1))"
python3 -c "import ctypes; print(ctypes.sizeof(ctypes.c_void_p))"
python3 -c "import sys; x=[]; print(sys.getrefcount(x))"    # exercise 10
python3 -c "print(int.__mro__)"                             # exercises 05, 07

# What did the assembler emit?
objdump -d -M intel --no-show-raw-insn ./build/04-vtables
nm ./build/04-vtables | grep vtable

# Where did the padding go?
pahole -C Sprite ./program               # struct layout with holes marked

# At run time
gdb -q ./program -ex 'info vtbl obj'
valgrind --leak-check=full ./program
```

Back to [the thesis](00-thesis.md).
