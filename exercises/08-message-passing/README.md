# Message passing, selectors and a method cache

**Technique:** dispatch by name, interned selectors, class-chain lookup, forwarding, doesNotUnderstand, method caches.
**New machinery:** an exercise-local message runtime (`msg.asm`): `intern`, `msg_send`, `send_cached`, per-class and inline caches.

## The idea

A vtable dispatches by *slot number*, and that number is frozen when the file
is assembled (exercise 04). This exercise dispatches by *name*, resolved while
the program runs. The receiver carries an `isa` pointer to a mutable class
object; the runtime looks the selector up in that class, then its superclass,
and so on. It is slower than `call [rax + 8*n]`, and in exchange the method set
stops being fixed:

```asm
msg_send:                      ; long msg_send(recv, sel, arg)
    mov  rdi, [rbx + MpObject.isa]
    mov  rsi, r12              ; the selector
    call resolve               ; walk isa -> super -> super ... by name
    ... call the IMP, or forward, or complain ...
```

This is the model under Smalltalk, Objective-C, Ruby and Python. Everything
below falls out of it.

## Selectors are interned strings

A selector is a name, but comparing names with `strcmp` on every send would be
absurd. So names are **interned**: the first time a spelling is seen it becomes
the one canonical pointer for that spelling, and every later spelling that
compares equal collapses to it. After interning, selector equality is a single
`cmp` of two pointers - which is exactly what a `SEL` is in Objective-C and a
symbol is in Lisp/Ruby. The program interns `"speak"` from two different
addresses and shows they yield one selector; the `strcmp` cost is paid once, at
intern time, never on the dispatch path.

## Lookup walks the chain; overrides shadow

`resolve` scans the receiver's class, then its superclass, comparing selectors
by pointer. The first match wins, so a subclass method placed earlier in the
walk shadows the parent's. The program's `describe` is defined only on `Animal`
yet a `Dog` uses it (found two hops up), while `speak` is overridden on `Dog`
and `Cat` (found immediately, shadowing `Animal`). Because `describe` itself
sends `speak` to `self`, the sound is chosen by the receiver's dynamic class -
name-based virtual dispatch, i.e. the template-method pattern.

## The thing a vtable cannot do: grow at run time

A vtable is fixed at assembly time; you cannot add a slot to a class that other
translation units already compiled against. A class object here is just a
mutable list, so `class_add_method` appends a row - and because existing objects
hold only an `isa` pointer, **every instance that already exists answers the new
message immediately**. The program sends `fetch` to a `Dog`, gets
`doesNotUnderstand`, installs `fetch` on the class, and sends it again to the
*same* object, which now responds. This is Ruby reopening a class, Objective-C's
`class_addMethod`, Python assigning to `Cls.method`. It is impossible with the
frozen table of exercise 04, and that impossibility is the whole trade.

## Unknown selectors, and forwarding

A send that resolves to nothing must not jump through a null pointer. It is
routed to `does_not_understand`, which prints the class and selector and
returns - Smalltalk's `doesNotUnderstand:`, Ruby's `method_missing`, Python's
`__getattr__`. On top of that hook sits **forwarding**: when a `Proxy` cannot
handle a message, the dispatcher asks it for a `forwardingTarget` and re-sends
to whatever it names. The `Proxy` implements exactly one method yet answers
`speak`, `fetch`, and more by delegating to the `Dog` it holds - the proxy
pattern, implemented in the dispatcher rather than in any class. When even the
delegate does not understand (`quack`), the failure surfaces there, still
without a crash.

## Caching: making the lookup cheap

A chain walk per send is a lot of work for what is usually the same answer as
last time, so the runtime caches at two levels:

- **Per-class method cache.** Each class remembers the last `(selector -> IMP)`
  it resolved, inherited or not. A repeat send of that selector to that class is
  one compare. Objective-C keeps a bigger hashed version of exactly this on
  every class.
- **Per-call-site monomorphic inline cache.** Each call site remembers the last
  *class* it saw and the IMP that class resolved to. If the next receiver has
  the same class, the site skips the lookup on a single compare. This is the
  optimisation every method-dispatch JIT is built around.

The program runs two workloads through `send_cached` and prints the counters:

```
  monomorphic 6x 'legs' (one class ...):
    inline-cache hits=5 misses=1 | class-cache hits=0 misses=1
  polymorphic  6x 'legs' (two classes, alternating ...):
    inline-cache hits=0 misses=6 | class-cache hits=4 misses=2
```

Monomorphic: after the first send the class never changes, so the inline cache
carries every remaining send and the class cache is never even consulted.
Polymorphic: the class alternates, so the inline cache misses every time (it
holds one entry), yet the per-class caches still turn most of those misses into
compares once both classes are warm. Real call sites are overwhelmingly
monomorphic, which is why the one-entry inline cache is such a good bet - and
why a site that goes megamorphic is where dispatch cost shows up.

## What C++ (and Objective-C, and JITs) actually do

Compare the cost with exercise 04. A C++ virtual call is two loads and an
indirect call - no strings, no search, because the compiler assigned slot
numbers and the set of methods can never change. That is why it is fast and why
adding a virtual to a shipped base class breaks the ABI.

Objective-C pays for the flexibility this exercise demonstrates, so it spends
enormous effort making the payment small. `objc_msgSend` is hand-written
assembly: it exists precisely to make the cache-hit path a handful of
instructions - load `isa`, hash the selector, probe the per-class cache, jump -
with no prologue, no spills, and a tail call into the method so the send frame
disappears. The slow path (a cache miss that walks the method lists) is written
in C; the hot path is assembly because every cycle is multiplied by every
message the whole system sends.

JITs take the same idea further with **inline caching**: they rewrite the call
site itself to remember the last class (monomorphic) or a few classes
(polymorphic), exactly as `send_cached` does, and then speculatively inline the
cached method - turning a dynamic send into a predicted direct call the branch
predictor loves. Our two counters are the toy version of the numbers a JIT
watches to decide when a site has gone megamorphic and should fall back.

## What the program shows

1. **Interning** - two spellings of `speak`, one selector; a different name, a
   different selector.
2. **Name dispatch with inheritance and override** - `describe` inherited,
   `speak` overridden, both reached by walking the chain.
3. **Runtime extension** - a `Dog` gains `fetch` after it already exists.
4. **doesNotUnderstand** - `quack` to a `Cat` is a printed diagnostic, not a
   crash.
5. **Forwarding** - a `Proxy` answers by delegating to its `Dog`, in the
   dispatcher.
6. **Caches** - inline-cache and class-cache hit/miss counters for a
   monomorphic and a polymorphic workload.

## Try this

- Add `Cat`-specific behaviour at run time (`class_add_method(Cat, "purr", ...)`)
  and watch an existing `Felix` respond, while `Rex` still does not understand
  `purr`.
- Make the polymorphic loop monomorphic by pointing every slot at a `Dog`, and
  watch the inline-cache misses collapse to one.
- Give the inline cache a second entry (a two-way polymorphic cache) and see
  the alternating workload start hitting it. That is the step from monomorphic
  to polymorphic inline caching that real JITs make.
- Remove the `class_flush` calls before the caching loops and predict the new
  counters before running: the per-class caches are already warm from earlier
  sections, so some misses become hits.

## Next

[09 - Prototypes and delegation](../09-prototypes/) removes the class/instance
distinction entirely: objects delegate straight to other objects, the way
JavaScript and Self do.
