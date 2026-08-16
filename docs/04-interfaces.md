# Interfaces and multiple inheritance

> Exercise: [06](../exercises/06-interfaces/)

## The problem

Single inheritance works because the base's layout can sit at the front of the
derived object. Two bases cannot both sit at the front. Something has to give.

This is where a hand-written object system stops being a pleasant exercise and
starts explaining why real ABIs look the way they do.

## Technique 1: one vptr per interface

Give the object a separate vptr for each interface it implements, at different
offsets:

```
Duck                            Duck_vtable_Quacker (primary, offset_to_top 0)
+0    vptr  -> Quacker table    [ 0]  offset_to_top = 0
+8    name                      [ 8]  Class* = Duck
+16   vptr  -> Swimmer table    [16]  quack -> Duck_quack
+24   stamina                   ...
                                Duck_vtable_Swimmer (secondary, offset_to_top 16)
                                [ 0]  offset_to_top = 16
                                [ 8]  Class* = Duck
                                [16]  swim -> thunk -> Duck_swim
```

A client that wants a `Swimmer` is handed `duck + 16`, not `duck`. The pointer
value *changes* when you view the object as its second interface. Everything
else follows from that one fact:

- **Converting is arithmetic, not a no-op.** Viewing a Duck as a Swimmer is
  `duck + 16`, and going back is `swimmer - 16`. A null check has to be part of
  it, since converting a null pointer must yield null rather than 16.
- **The method body still needs the complete object.** `Duck_swim` wants to
  read `name` at offset 8 from the *start* of the Duck, but it will be called
  with the receiver pointing 16 bytes in. So the secondary vtable does not
  point at `Duck_swim` directly; it points at an **adjustor thunk**:

  ```asm
  Duck_swim_thunk:
      sub     rdi, 16         ; receiver -= offset to the complete object
      jmp     Duck_swim       ; tail call: the thunk leaves no frame
  ```

  Every compiled language that puts more than one dispatch table inside a
  single object ends up emitting these, under one name or another.
- **`offset_to_top` makes the adjustment discoverable at run time.** Given any
  interface pointer, subtracting `vtable[offset_to_top]` recovers the complete
  object, without the caller knowing which interface it was holding.

That last field is the price of admission. Once an object has two dispatch
tables, a pointer to it is ambiguous - "which view is this?" - and the answer
has to be stored somewhere the runtime can find it.

### Where you have already met this problem

Python hits the same wall, and reports it in as many words:

```python
>>> class A(int): pass
>>> class B(str): pass
>>> class C(A, B): pass
TypeError: multiple bases have instance lay-out conflict
```

`int` and `str` each need their own storage at the front of the object, and
CPython cannot put both there. Inheriting from two *ordinary* Python classes is
fine, because they add no C-level layout; inheriting from two classes that do
is exactly the collision this exercise builds by hand. Every language with
multiple bases either solves it (offsets and thunks, below), forbids it
(single inheritance plus field-free interfaces), or moves the tables out of the
object entirely (fat pointers, further down).

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

Compare with technique 1: one load instead of two, and **no thunks**, because
the receiver never needs adjusting - the data pointer always points at the
whole object.

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

The trade is real and neither side is obviously right. Put the tables *in the
object* and pointers stay one word, dispatch is uniform, and any pointer can be
interrogated - but objects grow a vptr per interface and conversions have to
move the pointer. Put the tables *beside the object* and objects stay clean and
calls stay flat - but interface values are two words and a bare pointer no
longer knows anything about itself.

## Technique 3: do not lay anything out, look it up by name

The most flexible option is to give up on slots entirely and resolve the method
by name at the moment of the call. Python is the pure form: an object conforms
to an interface if it happens to have the attributes, nothing is declared, and
`Protocol` classes exist only so that a type checker can say something useful
before run time. There is no layout question because there is no layout - and
no fixed cost either, which is why [exercise 08](../exercises/08-message-passing/)
spends its second half building caches.

The JVM sits in between: `invokeinterface` cannot use a fixed slot number,
since a class may implement many interfaces with conflicting numbering, so it
uses per-class tables plus inline caching at the call site. The folklore that
`invokeinterface` is slower than `invokevirtual` was once true and is now
mostly noise - which is itself a lesson about how much of "dispatch cost" is
really prediction and inlining cost.

## Choosing

| You want | Use |
| --- | --- |
| One-word pointers, uniform dispatch, downcasting | Secondary vtables in the object |
| Clean objects, no thunks, structural conformance | Fat pointers beside the object (Go, Rust) |
| Retrofitting behaviour onto types you do not own | Fat pointers, or name lookup |
| Maximum flexibility, cost recovered by caching | Name lookup (Python, Objective-C, the JVM's interfaces) |

Next: [runtime type information](05-rtti.md), which is what makes downcasting
possible at all.
