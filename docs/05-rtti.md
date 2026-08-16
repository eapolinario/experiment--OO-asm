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

Languages differ only in how they report the failure: a null pointer you must
test, or an exception you must catch. The check underneath is the same walk.

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

## What Python does

`isinstance` is this exercise, in the interpreter. Every object begins with a
pointer to its type (`ob_type`, our vptr), every type has a `tp_base` (our
`Class.parent`) and a precomputed `tp_mro` tuple, and `isinstance(x, C)` checks
whether `C` appears in that tuple. The MRO *is* the display from the section
above: a precomputed, ordered array of ancestors, cached on the class so the
check does not have to walk anything.

Two Python details worth noticing, because both are this mechanism leaking
through:

- **`__class__` is writable.** Assigning to it re-points the object at another
  type, and `isinstance` immediately agrees. That is the vptr swap from
  exercise 04, exposed as an attribute.
- **`isinstance` is overridable.** A metaclass can define `__instancecheck__`,
  which is how `abc.ABC` lets an unrelated class register as a subclass and how
  `Protocol` does structural checks. Once the type test is a function rather
  than a layout fact, it can be *anything* - the cost being that it is now a
  call, not a compare.

## What everyone else does

- **Java**: `instanceof` compiles to a few loads and compares, with fast paths
  for final classes and a per-class cache for interfaces. Every array store
  into an `Object[]` carries a hidden type check as well.
- **Go**: type assertions compare the type descriptor already sitting in the
  interface value, so they are cheap. `switch v := x.(type)` is the idiom.
- **Rust**: no type information at all by default. Trait objects have vtables
  but no identity; `Any` opts in with a `TypeId`. Downcasting is deliberately
  awkward because the language would rather you used an enum.
- **Compiled languages with multiple inheritance** have the hardest job: a
  class has several ancestor paths, so the test becomes a graph search with
  pointer adjustments, expensive enough that performance-sensitive codebases
  routinely ban it and carry their own type tag instead. The metadata is also
  not free - it has to be emitted for every polymorphic class, which is why
  toolchains offer a switch to turn the whole feature off.

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
