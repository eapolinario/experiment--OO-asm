# Message passing

> Exercise: [08](../exercises/08-message-passing/)

## The problem

A vtable slot is decided when the caller is assembled. That is fast and it is
rigid: you cannot add a method at run time, cannot ask an object whether it
responds to something, cannot forward an unknown call somewhere else, and
cannot let an object decide, per call, what a name means.

Alan Kay's formulation of objects was not about tables at all. It was about
*messages*: you do not call a function on an object, you send it a name and
some arguments, and the object decides what to do. Smalltalk, Objective-C,
Ruby and Python all implement that literally.

## The technique: dispatch on an interned name

```
send(receiver, selector, args...)
    class = receiver->isa
    while class:
        for (sel, imp) in class->methods:
            if sel == selector: return imp(receiver, args...)
        class = class->superclass
    return doesNotUnderstand(receiver, selector, args...)
```

Three pieces make it practical.

**Selectors are interned.** A selector is not a string, it is the unique
address assigned to that string the first time anyone mentions it. Comparison
becomes a pointer compare, and the string is only touched when interning and
when printing. Objective-C's `SEL` and Ruby's and Lisp's symbols are exactly
this. `@selector(quack)` is a compile-time constant that the runtime fixes up
to the interned pointer at load time.

**Method lists live on the class, which links to its superclass.** Inheritance
becomes a search order rather than a layout property. Multiple inheritance
becomes a *linearisation* problem, which is why Python has an MRO and C3
linearisation, and why Ruby flattens modules into the ancestor chain.

**Unknown selectors are a normal event, not an error.** A miss has somewhere to
go: `doesNotUnderstand:` in Smalltalk, `forwardInvocation:` in Objective-C,
`method_missing` in Ruby, `__getattr__` in Python. This turns out to be an
enormously productive hook - it is how proxies, remote objects, mocks, ORMs
that materialise columns as accessors, and Rails' dynamic finders all work,
without any of them being a language feature.

## What it buys

Things exercise 04's vtables simply cannot do:

- **Add a method to a class after instances exist.** Every existing object
  responds immediately, because nothing was baked into any call site. This is
  monkey patching, Objective-C categories, and Ruby's `class_eval`.
- **Ask before you send.** `respondsToSelector:`, `respond_to?`, `hasattr`.
- **Answer for methods you do not have.** Forwarding, proxying, decorating.
- **Change the dispatch rules themselves.** Metaclasses, `method_added`, aspect
  weaving. In a message-passing runtime, dispatch is a function you can
  intercept.

That set of capabilities is the whole argument for dynamic languages. It is not
that they are terser; it is that the meaning of a call is decided at run time,
by the receiver.

## What it costs, and how everyone claws it back

A naive send walks a chain and scans lists: not a few cycles, but potentially
hundreds. Every real implementation therefore caches.

**Per-class method cache.** A hash table on the class mapping selector to
implementation, populated on first lookup. Objective-C has had one since NeXT.
Invalidated whenever methods are added or the hierarchy changes - which is
exactly why runtime method addition has a global cost.

**Inline caches.** The idea that made dynamic languages fast, from Deutsch and
Schiffman's Smalltalk work in 1984. Remember, *at the call site*, the last
class seen and the implementation it resolved to:

```asm
    cmp     rax, [rip + cached_class]   ; is the receiver the same class as last time?
    jne     .slow_path
    call    [rip + cached_imp]          ; direct call, perfectly predicted
```

A monomorphic call site - the overwhelming majority in real programs - becomes
a compare and a direct call, which is *cheaper than a vtable dispatch*, because
the target is a constant the predictor loves and the compiler can even inline
behind a guard.

Extensions: **polymorphic inline caches** (a small inline chain of guards for
two to four classes), and **megamorphic** call sites that give up and go to the
global cache. Every modern JavaScript engine, JVM and Smalltalk VM is built on
this hierarchy, and it is why `objc_msgSend` is hand-written assembly with a
tightly tuned cache probe: it is the single hottest function in the system.

Exercise 08 implements both caches and prints hit and miss counters, so you can
watch a monomorphic loop hit every time and a polymorphic one thrash.

## The comparison

| | Vtable (exercise 04) | Message send (exercise 08) |
| --- | --- | --- |
| Resolved at | assembly time (slot number) | run time (name) |
| Cost, cold | 2 loads + indirect call | chain walk, hundreds of cycles |
| Cost, cached | same | compare + direct call |
| Add a method later | impossible | routine |
| Unknown method | link error, or wrong function | a hook you can implement |
| Typical error | ABI break | typo found at run time |

The interesting row is "cost, cached": with an inline cache, name-based
dispatch is not slower than slot-based dispatch. What you actually pay for is
the *possibility of change* - because a method could be added at any moment,
every cache needs invalidation, and the compiler cannot assume anything about
a call site without a guard. Speed is recoverable; static reasoning is not.

Next: [prototypes and delegation](07-prototypes.md), which removes the last
fixed structure - the class itself.
