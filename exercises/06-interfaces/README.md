# Interfaces and multiple inheritance

**Technique:** secondary vtables, adjustor thunks, `offset_to_top`, and the fat-pointer alternative.
**New machinery:** an exercise-local `mi_object.inc` - the vtable grows an `offset_to_top` header word ahead of the class pointer; `mi_vcall`, `mi_class_of`, `mi_to_top`.

## The idea

Exercise 04 put one vptr at offset 0 and called it the object model. That works
because a `Shape*` and the object it points at begin at the same address: to
dispatch, you follow offset 0. Single inheritance (exercise 05) keeps the
promise by making the base the *prefix* of the derived object, so the one vptr
still sits at offset 0 for everybody.

Now make one class be two unrelated things at once. A `Duck` is a `Swimmer` and
a `Quacker`. A `Swimmer*` must point at something whose offset 0 is a Swimmer
vtable; a `Quacker*` must point at something whose offset 0 is a Quacker
vtable. One object cannot have two different things at offset 0. So it stops
trying:

```
  complete Duck            primary vtable (Swimmer)
  +---------------+        +------------------+
  | swimmer_vptr 0|------->| offset_to_top: 0 |
  | name        8 |        | Class*           |
  | quacker_vptr16|---+    | swim             |
  | volume     24 |   |    +------------------+
  +---------------+   |    secondary vtable (Quacker)
                      |    +-------------------+
                      +--->| offset_to_top: 16 |
                           | Class*            |
                           | quack  (a thunk)  |
                           +-------------------+
```

Two vptrs, at offsets 0 and 16. The Swimmer subobject is the whole object; the
Quacker subobject starts 16 bytes in. Handing a client a `Quacker*` means
handing it `duck + 16` - a pointer into the *middle* of the object. Everything
hard about multiple inheritance is the consequence of that one displacement.

## The field the vtable grows

A method body written for `Quacker::quack` wants `this` to be the complete
object, because that is where `name` and `volume` live. But the Quacker client
only ever holds `duck + 16`. Two mechanisms bridge the gap, and both need to
know the distance, so the distance is stored in the vtable:

```
  vtable + 0    offset_to_top   bytes to get from this subobject to the top
  vtable + 8    Class*          the run-time type (same for every subobject)
  vtable + 16   slot 0, slot 1, ...
```

The primary vtable's `offset_to_top` is 0; the secondary's is 16. Real compiled
ABIs store this as a signed number they *add*, so a secondary base holds `-16`;
`mi_object.inc` stores the non-negative amount to subtract, which reads more
directly. The arithmetic is the same either way.

## The adjustor thunk

The static, compile-time fix-up. The Quacker vtable's `quack` slot does **not**
point at `Duck_quack`. It points at a three-instruction stub:

```asm
Duck_quack_thunk:
    sub     rdi, 16                     ; Quacker* -> complete Duck*
    jmp     Duck_quack                  ; tail-call the real body, no frame
```

The client loads slot 0 of the secondary vtable and calls it with
`rdi = duck + 16`. The thunk subtracts 16 and jumps into the real method, which
now sees the complete object and reads `volume` correctly. `Duck_quack` never
learns it was reached through a second interface. Any compiler that lets one
object hold two dispatch tables emits one of these per method per secondary
interface, under some generated name. The program proves the thunk is really
there - the slot's address is not `Duck_quack` - and
that it works, by reading a complete-object field through it.

## offset_to_top, which is what `dynamic_cast<void*>` does

The runtime fix-up. Given only a `Quacker*` and no idea what it belongs to, you
can still recover the complete object: read its vtable, read `offset_to_top`,
subtract. `mi_to_top` does exactly that, and the program confirms the result
equals the original `Duck*`. `dynamic_cast<void*>(quacker)` in C++ compiles to
this and nothing more - the "address of the most-derived object" is one vtable
load away from any subobject pointer.

## The alternative: fat pointers (Go, Rust)

None of the above is inevitable. The displacement exists because the interface
pointer was made *thin* - a single word that has to double as both "the object"
and "which interface" by pointing at an embedded vptr. Widen it and the problem
dissolves.

A fat interface value is two words: a data pointer and an itable pointer.

```
  (data = complete Duck, itab = { Class*, quack, ... })
```

Dispatch loads the method from the itable and calls it with the data pointer
unchanged - and the data pointer is *already* the complete object, so there is
no adjustment and no thunk:

```asm
    mov     rax, [rsi + 8]              ; itab.quack
    jmp     rax                         ; rdi still holds the whole object
```

This is what Go interface values and Rust `&dyn Trait` are: `(data, vtable)`
pairs passed in two registers. The object itself carries no vptr at all; the
itable is external and built per (type, interface) pair.

**The trade-off, which the program shows both halves of:**

- *Embedded secondary vtables* (C++): an interface pointer is one word and is
  layout-compatible with a plain pointer, so it can be stored in a field, an
  array, or a `union` wherever a pointer fits. The cost is a second vptr inside
  every object and an adjustor thunk on every cross-interface call.
- *Fat pointers* (Go, Rust): objects stay clean - no vptr, no thunks, and a
  type can satisfy an interface it was written before. The cost is that an
  interface value is two words, so it is *not* a plain pointer: you cannot
  store it where one word is expected, and copying it moves 16 bytes.

Same call, same object, two designs; the adjustment moved out of the call path
and into the pointer's width.

## What the program shows

- **Two subobjects, one object.** The Swimmer subobject sits at +0 and the
  Quacker subobject at +16; the two interface pointers into the *same* duck are
  measured 16 bytes apart.
- **Two single-minded clients.** `pond_visit` knows only `Swimmer`,
  `soundcheck` knows only `Quacker`; neither mentions `Duck`. Each is handed
  its own subobject pointer and dispatches through it.
- **The thunk.** The secondary `quack` slot holds a thunk, not `Duck_quack`;
  called on `duck + 16` it still reads the complete-object `volume`.
- **offset_to_top.** A bare `Quacker*` is walked back to the complete object,
  and the recovered pointer equals the original `Duck*`.
- **Fat pointers.** The same `quack` reached through a two-word `(data, itab)`
  value, with the data pointer sitting zero bytes from the complete object -
  the thunk's job done by the pointer's shape instead.

## Look at the picture

```console
$ make viz
```

The diagram at the top of this file, drawn from the duck the program actually
constructed - four panels: the layout with its two arrows converging on one
class descriptor, the two interface pointers measured 16 bytes apart, the fat
pointer that needs neither, and the call path:

**Generated output**

```
  what the sound check does   the adjustor thunk          the real method
  +----------------------+    +----------------------+    +--------------------+
  | rdi = duck + 16      |--->| sub rdi, 16          |--->| rdi = duck + 0     |
  +----------------------+    +----------------------+    +--------------------+
  | call [vptr + 16]     |    | jmp Duck_quack       |    | reads +24 volume=11|
  +----------------------+    +----------------------+    +--------------------+
```

Every number there is read back out of the object system: the 16 the thunk
subtracts is the secondary vtable's `offset_to_top` field, the `+16` the client
calls through is `MI_VT_SLOT(0)`, the distance between the two interface
pointers is measured by subtracting them, and the word `(thunk)` appears beside
that slot in panel 1 only because the slot compared unequal to `Duck_quack`.

## Try this

- Delete the `sub rdi, DUCK_K` from `Duck_quack_thunk` and rerun. `volume`
  reads garbage (and `name` dereferences a wild pointer): the exact bug the
  thunk exists to prevent.
- Add a third interface `Nameable` with a `name()` method, at a third offset.
  Watch a second `offset_to_top` and a second thunk appear, and the fat-pointer
  path need only one more itable - no new object field.
- Reorder the struct so `Quacker` is the primary base and `Swimmer` the
  secondary. The thunk moves to `swim` and `offset_to_top` swaps over.
- Store a `Quacker*` and a fat Quacker value into arrays of the same element
  size. Only the thin pointer fits in one word; the fat value needs two - the
  trade-off made physical.

## Next

[07 - Runtime type information](../07-rtti/) reads the `Class*` these vtables
carry and walks the `parent` chain, which is all `instanceof` and a checked
`dynamic_cast` ever were.
