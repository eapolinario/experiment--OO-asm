# Prototypes and delegation

**Technique:** property bags, a delegation pointer, interned keys, live method addition.
**New machinery:** `intern`, `obj_lookup` (the chain walk), `obj_send` (get + indirect call). No vtable, no class - `object.inc` is not even included.

## The idea

Every exercise so far has a class somewhere: a `struc` that fixes the fields, a
vtable that fixes the methods, a slot numbering frozen as ABI. Prototypes throw
all of that out and keep something smaller.

An object is:

```asm
struc Obj
    .proto:  resq 1              ; another object, or NULL
    .count:  resq 1
    .keys:   resq PROTO_CAP      ; interned strings
    .vals:   resq PROTO_CAP      ; data, or code pointers
endstruc
```

a bag of key/value pairs plus one pointer to another object. There is no type.
There is no method table. There is a rule for reading and a rule for writing,
and they are not symmetric:

- **get walks the chain.** Look in the object's own keys; on a miss, follow
  `.proto` and look again, until the key is found or the chain ends. Lookup
  *is* inheritance, performed one link at a time at run time.
- **set writes to the receiver.** Always. It never follows `.proto`. Assigning
  a key that currently resolves to a prototype creates a new *own* property
  that shadows it, and leaves the prototype untouched.

That asymmetry - read up, write local - is the single most important rule of
every prototype system, and the source of a classic JavaScript surprise:
`child.x += 1` reads `x` from the prototype and writes a fresh own `x` onto
`child`, so siblings that shared the inherited value silently stop sharing it.
The program prints exactly this: after `set(child, "w", 10)`, `child.w` is an
own property at depth 0 while `base.w` is still 2.

## Keys are interned

Before anything is stored, every key string is passed through `intern`, which
returns one canonical pointer per distinct spelling. The chain walk then
compares keys with `cmp reg, reg` instead of calling `strcmp` at every link.
The program proves the mechanism: two different addresses both holding `"w"`
intern to the same pointer.

This is not a toy shortcut. V8 interns property names into *atoms*, Ruby into
*symbols*, the JVM into the string constant pool; identity comparison on
interned names is what makes property lookup and inline caching affordable.

## What a chain walk costs, and how engines get the speed back

A get is O(depth): a linear scan of each object's own keys, then a pointer
chase to the next. `get(child, "kind")` in this program crosses two links to
reach the root. Naively, dynamic delegation is slower than a vtable's two loads
because the depth and the per-object scan are both unbounded.

Real engines recover the speed by, in effect, *reinventing the class and the
vtable at run time*:

- **Hidden classes / shapes (V8, SpiderMonkey).** Objects created the same way
  and given the same keys in the same order are assigned a shared descriptor
  that records "key `w` lives at offset 0, key `h` at offset 1". Instances then
  carry only the values, and a lookup becomes a shape check plus a fixed-offset
  load - which is a vtable and a struct, materialised lazily from observed
  behaviour.
- **Inline caches.** Each call site remembers the shape it saw last time and
  the offset it resolved to, so a monomorphic site skips the walk entirely.
  This is exactly the "monomorphic vs megamorphic" story from
  [exercise 04](../04-vtables/), one level up.

So prototypes are the *more primitive* mechanism: classes and vtables can be
built on top of them (a "class" is just a prototype everyone shares), but not
the other way round. A property bag with a delegation pointer is the
"universal design pattern" that reappears whenever a system needs open-ended,
user-extensible objects - JavaScript and Lua objects, DOM nodes, `GObject`
property bags, Python's `__dict__`, Cocoa's key-value coding.

## What the program shows

1. **Interning is identity.** Two spellings of `"w"`, one canonical pointer.
2. **Delegation has a visible depth.** Each get prints the link it resolved at,
   so a three-object chain (`child -> base -> root`) is laid bare.
3. **send binds `this` to the receiver.** `area` is defined once, on `base`, yet
   `send(child, "area")` computes with the child's own `w`. The method runs on
   the object the message was sent to, never the object it was found on.
4. **Shadowing.** Writing `child.w` leaves `base.w` alone; `send(base, "area")`
   still returns 6 while the child now returns 30.
5. **Clone = `Object.create`.** A brand-new object with zero own properties
   already answers `area` (through `base`), then diverges the moment you set an
   own key.
6. **Live mutation.** `perimeter` is added to `base` *after* `child` and `clone`
   exist, and both immediately gain it - then `child` overrides it for itself
   alone. This is the capability the class/vtable world cannot offer: exercise
   04's tables are per-class and fixed at assembly time; here behaviour is
   editable data, which is what "monkey patching" and Ruby's open classes are.

Nothing collects these objects - the last section frees them by hand and the
live-object counter returns to zero, a deliberate hand-off to the next exercise.

## Try this

- Send a message no object in the chain answers (for example
  `obj_send(child, intern("volume"), 0)`) and watch `obj_send` hit its
  `doesNotUnderstand` path. That branch is Smalltalk's `doesNotUnderstand:`,
  Ruby's `method_missing`, and a JavaScript `Proxy` trap.
- Point `base.proto` at `child`, making a cycle, then get a missing key and
  watch the walk never terminate. Real engines forbid prototype cycles for
  exactly this reason; add a visited-depth cap to `obj_lookup` and see the cost.
- Add a second child of `base`, override `area` on the prototype, and confirm
  both children change at once - then measure how the answer depends on chain
  depth by inserting another object between `base` and `root`.
- Replace the linear key scan with the beginnings of a shape: give `Obj` a
  pointer to a shared descriptor and store only values. You will have started
  writing V8.

## Next

[10 - Reference counting and object lifetime](../10-reference-counting/) answers
the question this exercise dodged: once objects point at each other freely, who
decides when one dies?
