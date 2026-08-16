# Runtime type information

> Exercise: [07](../exercises/07-rtti/)

## The problem

Polymorphism is about *not* asking what an object is. But sometimes you must:
you have a `Stream*` that might be a `FileStream*`, and the operation you want
exists only on the latter. The question "what is this, really?" has to be
answerable at run time, and answerable safely.

## The technique: metadata reachable from the object

Exercise 04 already put a class descriptor at slot 0 of every vtable, so the
path exists:

```asm
    mov     rax, [rdi]              ; object -> vtable
    mov     rax, [rax + VT_CLASS]   ; vtable -> Class*
    mov     rsi, [rax + Class.name] ; "FileStream"
```

Add `Class.parent` and the descriptors form a chain that mirrors the class
hierarchy. Then:

**`is_a(obj, C)`** walks it: start at the object's class, follow `.parent`
until you find `C` or fall off the end. That is `instanceof`, `isinstance`,
`is`, and the check inside a checked downcast.

**`dynamic_cast(obj, C)`** is `is_a` plus a pointer: return the pointer if the
walk succeeds, NULL if it does not. Returning NULL rather than trapping is what
makes the "test and branch" idiom possible:

```asm
    call    dynamic_cast
    test    rax, rax
    jz      .not_a_file_stream
```

C++ spells the two variants `dynamic_cast<T*>` (null on failure) and
`dynamic_cast<T&>` (throws `std::bad_cast`), for exactly this reason.

## Cost, and the standard fix

The chain walk is O(depth). Depth is usually small, but this runs in hot paths
in some programs, and there is a classic constant-time replacement (Cohen's
algorithm, used in real VMs):

Give each class a **depth** and a **display**: an array of its ancestors,
indexed by depth, with itself last. Then

```
is_a(obj, C)  ==  obj.class.depth >= C.depth
              &&  obj.class.display[C.depth] == C
```

One bounds check, one load, one compare, no loop. It costs `depth * 8` bytes
per class, which is nothing, and it only works for single inheritance - with
multiple inheritance a class has several ancestor paths and you need a real
subtype test (bit vectors, interval numbering of the hierarchy, or a cache).
Exercise 07 implements both and shows them agreeing.

## What C++ actually does

- The vtable holds a pointer to a `std::type_info`-derived object
  (`__class_type_info` and friends), at offset -8 from the address point in the
  Itanium ABI. `typeid(x)` on a polymorphic type loads it from there.
- `dynamic_cast` is **a real function call** into the runtime
  (`__dynamic_cast`), not an inlined compare. For multiple and virtual
  inheritance it has to search a graph of base-class descriptors, deal with
  ambiguous bases, and compute pointer adjustments. It can be surprisingly
  slow - benchmarks routinely find it far more expensive than a virtual call,
  which is why hot code often carries its own type tag or a virtual `kind()`
  method instead. LLVM's `isa<>`/`dyn_cast<>` exist for precisely this reason.
- Type identity across shared libraries is compared by `type_info` *name
  string* in the Itanium ABI when the pointers differ, which is why
  `-fvisibility=hidden` can quietly break `dynamic_cast` across `.so`
  boundaries.
- `-fno-rtti` exists because the metadata is not free: it is emitted for every
  polymorphic class, and some projects (games, embedded, Chromium) would rather
  not pay for it.

## What everyone else does

- **Java**: `instanceof` and checked casts are bytecodes; the JIT compiles them
  to a small number of loads and compares, with fast paths for final classes
  and a per-class secondary-supertype cache for interfaces. Every array store
  into an `Object[]` also carries a hidden type check.
- **Go**: type assertions compare the type descriptor in the interface value
  and are cheap. `switch v := x.(type)` is the idiom.
- **Rust**: no RTTI at all by default. Trait objects have vtables but no type
  identity; `Any` opts into it with a `TypeId`. Downcasting is deliberately
  awkward because the language would rather you used an enum.
- **Python and Ruby**: everything already carries its class; `isinstance` is a
  chain walk (with an MRO to make multiple inheritance deterministic).

## The design question

RTTI is a tell. A `dynamic_cast` in ordinary application code is usually a
missing virtual method: the code is asking "what are you" so it can decide what
to do, which is the job dispatch already does. The legitimate uses are narrower
and recognisable - deserialisation, plugin boundaries, debuggers, visitor
implementations, and interoperating with a hierarchy you do not own.

Worth noticing: everything in this document is *policy*, not mechanism. The
mechanism is one pointer to a descriptor, plus a link to a parent. Once objects
can name their own type, the type system's run-time half is a small library -
which is exactly what the next step turns into an entire dispatch strategy.

Next: [message passing](06-message-passing.md), where the name, not the slot,
becomes the thing you dispatch on.
