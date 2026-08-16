# Prototypes and delegation

> Exercise: [09](../exercises/09-prototypes/)

## The problem

Classes are a compression scheme. They exist because most objects of a kind
share their behaviour, so it is wasteful to store the behaviour in each one.
But the compression is also a constraint: an object cannot have one extra
method, an object cannot change its mind, and creating a new kind of thing
means declaring a new type somewhere a compiler can see it.

What if you skip the class?

## The technique: a bag of properties and a pointer to another object

```
object = { own properties: (key -> value)..., proto: object* }

get(obj, key):
    while obj:
        if key in obj.own: return obj.own[key]
        obj = obj.proto
    return not-found

set(obj, key, value):
    obj.own[key] = value          # ALWAYS on the receiver
```

That asymmetry - **lookup walks the chain, assignment never does** - is the
single most important rule in the design. It gives you inheritance (share via
the prototype) and override (shadow it locally) with no additional machinery,
and it is the source of the classic JavaScript surprise where two objects
sharing a prototype appear to share an array until one of them assigns to it.

Methods are not special. A method is a property whose value happens to be a
code pointer. Sending is lookup plus an indirect call with the receiver bound
to the object you *sent to*, not the object where the method was *found* -
which is what makes an inherited method operate on the child's data. Get that
binding wrong and delegation collapses into "call a function on the prototype".

Cloning is `{ own: {}, proto: existing }`: JavaScript's `Object.create`, Self's
copy-and-tweak. A fresh object with no properties of its own that already
answers everything.

## What it buys

- **Classes become optional sugar.** A "class" is just an object that other
  objects delegate to; `new Foo()` in JavaScript is "make an empty object whose
  proto is `Foo.prototype`, run `Foo` with `this` bound to it". Exercise 09
  shows you can add methods to a prototype after children exist and every child
  gains them, which is the mechanism ES6 `class` syntax sits on top of.
- **Per-object behaviour is free.** Give one object a different method; no new
  type, no new vtable, no declaration.
- **Structure can be discovered rather than declared.** This is why property
  bags with delegation show up whenever a system needs to be extended by its
  users: game entity systems, configuration cascades, CSS's cascade,
  Kubernetes' overlays, LDAP and DNS resolution, and the `__getattr__` layer of
  most Python frameworks. Steve Yegge called this pattern - property bags plus
  a delegation chain, with everything else layered on top - the "universal
  design pattern", precisely because it keeps being rediscovered.

## What it costs

A property read is a search: hash or scan the own properties, then repeat up
the chain. Compared with `[rdi + 16]`, that is orders of magnitude. Worse, the
cost is *unpredictable*, because it depends on where in the chain the property
lives and how many properties each level has.

Modern JavaScript engines recover essentially all of it, and the way they do it
is the punchline of this whole repository:

**Hidden classes (maps, shapes).** V8 gives every object a hidden class
describing its layout: which properties it has, at which fixed offsets.
Objects created the same way share one. Adding a property *transitions* the
object to a new hidden class, following a cached transition edge, so objects
built by the same constructor converge on the same shape.

**Inline caches.** A property access site records the hidden class it saw and
the offset it resolved to. Next time, if the class matches, the access is a
compare and a load at a constant offset.

Put those together and `obj.x` in optimised JavaScript compiles to roughly:

```asm
    cmp     [rdi], cached_map       ; is this the shape I saw last time?
    jne     .deopt
    mov     rax, [rdi + 24]         ; constant offset
```

A type check plus a fixed-offset load. Which is to say: **the engine
reconstructs, at run time, exactly the class-and-vtable arrangement that
exercises 01 and 04 wrote by hand**, deduces the offsets that a static compiler
would have been told, and guards them with a check so it can bail out if the
program does something dynamic after all.

That is the deep symmetry worth taking away. Static object systems fix the
layout up front and give up flexibility; prototype systems keep flexibility and
recover the layout by observation. Both end at a shape check and a constant
offset.

## Practical consequences

- Monomorphic code is fast; heterogeneous code is not. "Always initialise
  fields in the same order, in the constructor, and do not delete properties"
  is folk advice that is really "keep the hidden classes stable".
- Adding a property to a prototype invalidates caches that depended on the old
  shape. Monkey patching at run time is not free; it is a deoptimisation event.
- Delegation depth is a real cost when caches miss: long prototype chains and
  deep `__getattr__` stacks are slow in ways profilers find hard to attribute.

Next: [object lifetime](08-object-lifetime.md), the last question - who decides
when an object dies.
