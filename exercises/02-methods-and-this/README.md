# Methods, `this`, and a representation you cannot see

**Technique:** name mangling, the receiver convention, opaque types, invariants.
**New machinery:** multi-file linkage; `global` as the access specifier.

## The idea

Exercise 01 showed a method is a function that takes the object as its first
argument. This one adds the two things that turn a pile of functions into a
*class*: a namespace and a boundary.

**The namespace is name mangling.** The assembler has one flat symbol table, so
`push` cannot mean two things. Prefixing the class name - `Stack_push` - is the
whole technique. C++ does exactly this, just less legibly:
`Stack::push(long)` becomes `_ZN5Stack4pushEl`, encoding the class, the method
and the parameter types so that overloads get distinct symbols.

**The boundary is what you choose to export.** `stack.asm` declares only six
symbols `global`. The layout, the capacity constant and the failure handler are
invisible to anyone else; the client cannot reach `Stack.len` because that
symbol does not exist outside the file where it is defined. `private` is not a
keyword here, it is the default, and the linker is the enforcement mechanism.

The client is handed one number and one vocabulary:

```asm
%define STACK_SIZEOF    80          ; allocate this much, ask no questions
extern Stack_push                   ; long Stack_push(Stack *this, long v)
```

which is precisely how C ships `pthread_mutex_t` and how C++ ships a pimpl'd
class. The implementation keeps the two halves honest with an assembly-time
assertion:

```asm
%if Stack_size != STACK_SIZEOF
    %error "STACK_SIZEOF in stack.inc disagrees with struc Stack"
%endif
```

**The invariant is the point of the boundary.** `0 <= len <= cap` is checked
inside `Stack_push` and `Stack_pop` and nowhere else. Because no outside code
can touch `len`, a violation can only come from a bug in this one file. That
is the entire practical value of encapsulation: it shrinks the set of places a
class invariant can be broken from "the program" to "this file".

## What the program shows

- **Two instances, one code path.** `s1` and `s2` run the same `Stack_push`
  instructions; the only difference is the pointer in `rdi`. Objects are data,
  methods are code, and code is shared.
- **Re-running the constructor** on `s2` yields a fresh object in the same
  storage. Construction is not allocation - a distinction exercise 03 leans on.
- **Bad input is rejected, not absorbed.** Pushing onto a full stack returns 0
  and leaves the depth alone; popping an empty one returns 0.
- **Const methods** (`Stack_depth`, `Stack_peek`, `Stack_capacity`) read the
  receiver and never write through it. `const` in C++ makes the compiler check
  that promise; the emitted code is identical either way.

## Try this

- In `main.asm`, add `mov rax, [rdi + 0]` after a `Stack_init` and try to
  assemble it. `Stack.len` is not just private, it is *unknown*.
- Add `call stack_invariant_failed` to `main.asm` and read the linker error.
  That error message is the access control.
- Break the boundary on purpose: change `STACK_CAPACITY` to 16 in `stack.asm`
  without touching `stack.inc`, and watch `%error` fire. Then imagine shipping
  that as two separately compiled binaries - this is the ABI break that makes
  C++ library authors add reserved padding to their classes.
- Add `Stack_clear` and note that you did not have to touch the client's
  storage or the header's size.

## Next

[03 - Constructors, destructors and the heap](../03-constructors-and-heap/)
gives objects a lifetime that outlives the frame that created them.
