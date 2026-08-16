# Object lifetime

> Exercises: [03](../exercises/03-constructors-and-heap/), [10](../exercises/10-reference-counting/)

## The problem

Objects that own resources have to be destroyed, exactly once, after the last
use and not before. In exercise 03 that decision is made by hand and nothing in
the machine checks it: a forgotten `Text_delete` leaks and the program runs on
perfectly happily. That is the whole difficulty. A leak is not an error
condition; it is the absence of an action.

Everything below is an answer to "who decides, and how do they know".

## Manual: the programmer decides

Ownership becomes a documented convention. `Text` owns its buffer, so
`Text_destroy` frees it; `Text_new` allocates the object, so `Text_delete`
frees it; a client that receives a pointer had better know whether it is
borrowing or owning. This is C, and it works, given discipline and a naming
convention (`_create`/`_destroy`, "the caller frees the returned buffer").

Scope-bound cleanup makes it *structurally* reliable: bind the lifetime to a
scope and let the compiler emit the release on every exit path, including the
exceptional ones. C++ calls this RAII; Python's `with` and Go's `defer` are the
explicit, opt-in version of the same idea. In every case it is exercise 03 with
the calls inserted for you.

Rust makes it *statically checked*: ownership is a type property, moves are
tracked, borrows are checked, and `Drop` runs at the end of the owner's scope.
Same mechanism, but the compiler now refuses to build the programs that would
have leaked or double-freed.

## Reference counting: the objects decide, together

Put a counter in the object header. `retain` increments, `release` decrements
and destroys at zero.

```
retain(o):   o.rc += 1
release(o):  o.rc -= 1
             if o.rc == 0: destructor(o); free(o)
```

Properties that make it popular:

- **Destruction is immediate and deterministic.** The object dies at the
  instruction that dropped its last reference, so it composes with RAII and
  with scarce resources - file descriptors and locks get released on time.
- **No pauses**, no scanning, no separate heap traversal. Memory use tracks the
  program's actual working set.
- **It needs no runtime support**, so it can live in a library or be written
  by hand - which is exactly why this exercise is possible at all.

And the costs, which are equally real:

- **Every copy of a pointer is a write.** Counts must be updated even for
  short-lived references, and each update dirties a cache line - a serious
  penalty when objects are shared across cores.
- **Thread safety demands atomics.** An atomic increment is far more expensive
  than a plain one, and contended counts serialise. Rust's split between `Rc`
  (fast, single-threaded, not `Send`) and `Arc` (atomic) exposes exactly this
  choice in the type system. Swift and Objective-C ARC pay it constantly, and
  the compiler works hard to elide pairs.
- **Cycles leak, structurally.** Two objects that reference each other keep
  each other alive forever, and no amount of care at the call sites fixes it,
  because each individual count is correct. Exercise 10 builds the cycle and
  shows the counters proving nobody is ever freed.

### Weak references

The standard escape from cycles: a reference that does not contribute to the
count and is detectable (or nulled) when the target dies. Parent-to-child
strong, child-to-parent weak; observers weak; caches weak. Python spells it
`weakref.ref` (and `WeakValueDictionary` for caches, which is the common case);
Rust spells it `Weak`, ARC spells it `__weak`, C++ spells it `weak_ptr`.

Implementations differ in cost and honesty. A "side table" (the target keeps a
list of weak slots to clear, or a shared control block holds both counts) makes
dangling detection reliable at the price of an extra allocation or indirection.
`shared_ptr`/`weak_ptr` use a control block holding a strong count and a weak
count; the object's storage survives until the weak count also hits zero, which
is why `make_shared` can keep a large buffer alive longer than expected.

The catch is that weak references are a *manual* fix: somebody has to notice
the cycle. That is exactly the thing programmers are bad at.

## Tracing garbage collection: the runtime decides

Stop asking objects and ask the graph: start from the roots (stack slots,
registers, globals), mark everything reachable, sweep the rest. Cycles are not
a special case - unreachable is unreachable.

What it needs, and what makes it a runtime feature rather than a library:

- **Precise root and field information.** The collector must know which words
  are pointers. That means stack maps, and per-class layout metadata - and the
  natural place to hang that metadata is the class descriptor from exercise 04.
  Our `Class` already carries name, size and parent; adding a field map turns
  it into a GC map. (Conservative collectors like Boehm's guess instead, which
  works surprisingly well and occasionally retains garbage.)
- **Control over mutator threads**, for safepoints and read/write barriers.
- **A moving collector, if you want compaction** - which then requires that
  nobody holds a raw address across a collection, which is why JNI has handles
  and why interior pointers are a research topic.

The payoffs are cycles collected automatically, allocation reduced to a pointer
bump, and no per-reference bookkeeping at all. The costs are pauses (or the
complexity of avoiding them), memory headroom, and non-deterministic
finalisation - which is why every GC'd language *also* has explicit disposal
(`try-with-resources`, `using`, `defer`, context managers) for the resources
that cannot wait.

## Hybrids, which is what most systems actually are

- **CPython**: reference counting for immediacy plus a generational cycle
  collector for exactly the case refcounting cannot handle. The GIL is what
  makes the non-atomic counts safe, which is a large part of why removing it is
  so hard.
- **Objective-C / Swift ARC**: the compiler inserts the retain/release calls
  that a programmer used to write, elides what it can prove redundant, and
  leaves cycles to `weak`/`unowned` annotations.
- **C++**: manual by default, scope-bound cleanup by convention, shared
  ownership only when it is genuinely shared - the advice being to reach for
  the counted pointer last, because unique ownership is cheaper and clearer.
- **Java, Go, C#**: tracing GC, plus explicit lifetime constructs for
  non-memory resources.

## The through-line

Notice that this last technique is not about layout at all. Exercises 01
through 09 are about where things are and how you find them; exercise 10 is
about *when*, and it turns out to be the one that resisted a mechanical answer
the longest. Layout questions were settled by the mid-1980s. Lifetime
questions produced reference counting, tracing collectors, RAII, ARC and
borrow checking, and are still producing language designs today.

Back to [the thesis](00-thesis.md), or on to
[further reading](09-further-reading.md).
