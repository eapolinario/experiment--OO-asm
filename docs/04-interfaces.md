# Interfaces and multiple inheritance

> Exercise: [06](../exercises/06-interfaces/)

## The problem

Single inheritance works because the base's layout can sit at the front of the
derived object. Two bases cannot both sit at the front. Something has to give.

This is where a hand-written object system stops being a pleasant exercise and
starts explaining why real ABIs look the way they do.

## Technique 1: secondary vtables and thunks (the C++ way)

Give the object one vptr per base, at different offsets:

```
Duck                            Duck_vtable_Quacker (primary, offset_to_top 0)
+0    vptr  -> Quacker table    [ 0]  offset_to_top = 0
+8    name                      [ 8]  Class* = Duck
+16   vptr  -> Swimmer table    [16]  quack -> Duck_quack
+24   stamina                   ...
                                Duck_vtable_Swimmer (secondary, offset_to_top -16)
                                [ 0]  offset_to_top = -16
                                [ 8]  Class* = Duck
                                [16]  swim -> thunk -> Duck_swim
```

A client that wants a `Swimmer*` is handed `duck + 16`, not `duck`. The pointer
value *changes* on the cast. Everything else follows from that one fact:

- **Casting is arithmetic, not a no-op.** `(Swimmer*)duck` is `duck + 16`, and
  `(Duck*)swimmer` is `swimmer - 16`. A null check has to be part of it, since
  casting a null pointer must yield null rather than 16.
- **The method body still needs the complete object.** `Duck_swim` wants to
  read `name` at offset 8 from the *start* of the Duck, but it will be called
  with `this` pointing 16 bytes in. So the secondary vtable does not point at
  `Duck_swim` directly; it points at an **adjustor thunk**:

  ```asm
  Duck_swim_thunk:
      sub     rdi, 16         ; this -= offset to the complete object
      jmp     Duck_swim       ; tail call: the thunk leaves no frame
  ```

  g++ emits these with names like `_ZThn16_N4Duck4swimEv` - `Th` for thunk,
  `n16` for "non-virtual, 16". If you have ever seen one in a backtrace, this
  is what it was.
- **`offset_to_top` makes the adjustment discoverable at run time.** Given any
  interface pointer, `this + vtable[offset_to_top]` recovers the complete
  object. That is exactly what `dynamic_cast<void*>` does, and it is why the
  field is in the real Itanium ABI vtable too (just at a negative offset from
  the address point, along with the typeinfo pointer).

The Itanium C++ ABI layout, for comparison with ours:

```
        -16   offset-to-top
         -8   typeinfo pointer
vptr ->   0   first virtual function
          8   second virtual function
```

The vptr points at the *address point*, in the middle of the structure, so that
slot numbering stays positive and the metadata lives behind it. We put
`offset_to_top` and the class pointer in front and start slots at +16, which is
the same idea with easier arithmetic.

### Diamonds

If two bases share a base of their own, the shared base is duplicated - the
object contains two copies with different offsets. Virtual inheritance fixes
that by giving the object a single shared subobject reached through a
**virtual base pointer**, or through offsets stored in the vtable
(`vbase_offset`). The cost is that access to a virtual base member becomes an
extra indirection, and construction gets a rule most people never internalise:
the *most derived* class constructs the virtual base. This is a large part of
why later languages allow multiple *interface* inheritance but only single
*implementation* inheritance: interfaces have no fields, so there is nothing to
duplicate.

## Technique 2: fat pointers (the Go and Rust way)

Do not put anything in the object. Make the *interface value* the composite:

```
interface value = { data pointer, itable pointer }   // two registers
```

An `itable` (Go) or vtable (Rust `dyn Trait`) is a per-(type, interface) pair
table of the methods that type provides for that interface. Calling is:

```asm
    ; rdi = data, rsi = itable
    mov     rax, [rsi + 8*n]
    call    rax                     ; receiver already in rdi, unadjusted
```

Compare with the C++ path: one load instead of two, and **no thunks**, because
`this` never needs adjusting - the data pointer always points at the whole
object.

What you give up:

- An interface value is two words. It does not fit where a pointer fits, cannot
  be atomically swapped as a unit, and doubles the size of slices of
  interfaces.
- Objects carry no dispatch information at all, so you cannot recover an
  interface value from a bare data pointer. Dynamic downcasting needs type
  information from somewhere else (Go stores a type descriptor in the itable;
  Rust needs `Any` and explicit `TypeId`).
- Itables may need to be built lazily at run time (Go does this, with a cache),
  because the set of (type, interface) pairs is only known once the program is
  linked.

The trade is real and neither side is obviously right: C++ pays per object and
per cast so that dispatch is uniform and pointers stay one word; Go and Rust
pay per interface value so that objects stay clean and calls stay flat.

## Technique 3: interface dispatch by search (the JVM way)

The JVM's `invokeinterface` cannot use a fixed slot number, because a class may
implement many interfaces with conflicting numbering. Historically it searched
the class's interface method table; modern JVMs use per-class itables plus
inline caching at the call site. The observable consequence is folklore you may
have heard: `invokeinterface` used to be measurably slower than `invokevirtual`.
Today, with inline caches, the difference is usually noise - which is itself a
lesson about how much of "dispatch cost" is really "prediction and inlining
cost".

## Choosing

| You want | Use |
| --- | --- |
| One-word pointers, uniform dispatch, downcasting | Secondary vtables (C++) |
| Clean objects, no thunks, structural conformance | Fat pointers (Go, Rust) |
| Retrofitting behaviour onto types you do not own | Fat pointers or message passing |
| Many interfaces per type, dynamic loading | Name-based dispatch plus caches (JVM, Objective-C) |

Next: [runtime type information](05-rtti.md), which is what makes downcasting
possible at all.
