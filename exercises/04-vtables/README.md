# Vtables and dynamic dispatch

**Technique:** the vptr, per-class method tables, slot numbering as ABI, isa-swizzling.
**New machinery:** `include/object.inc` - `vcall`, `VT_SLOT`, `Class`.

## The idea

Everything so far has been bookkeeping. This is the trick that makes "object
oriented" a distinct thing.

Put a pointer at offset 0 of every object. Point it at a per-class array of
function pointers. Agree, once and forever, on what each index in that array
means. Now a caller that has never heard of your class can invoke your code:

```asm
    mov     rax, [rdi]                  ; rax = this->vptr
    call    [rax + 8*3]                 ; slot 2 of the table (slot 0 is the class)
```

Two loads and an indirect call. That is the entire cost of `virtual` in C++,
of every method call in Java before the JIT gets clever, and of every method
call in Python before you count the dictionary lookups. There is no type tag,
no switch, no runtime "if it's a Circle then". The object carries a pointer to
its own behaviour, and the call site follows it.

`shape.inc` is the whole interface:

```asm
%define SHAPE_AREA      0
%define SHAPE_PERIMETER 1
%define SHAPE_SHOW      2
```

There is no Shape class, no Shape struct, and no field in any object saying
"I am a Shape". `Circle` and `Rect` are separate translation units that never
see each other's symbols. All they share is an agreement about slot numbers -
and that is exactly what an interface is.

## Why slot numbers are ABI

Insert a method in the middle of `shape.inc` and recompile only `circle.asm`,
and `main` will call `Circle_perimeter` when it means to call `Circle_area`.
Nothing crashes; the answers are just wrong. This is why:

- C++ vtable layout is frozen by the platform ABI, and adding a virtual
  function to a class in a shipped library breaks binary compatibility;
- COM interfaces are immutable by rule - you publish `IFoo2` instead;
- Java, which resolves methods by name and signature at class-load time, can
  add methods to a base class without recompiling the world, and pays for that
  flexibility with a much heavier runtime.

Exercise 08 builds the other side of that trade-off: dispatch by name.

## What the program shows

- **One loop, four implementations.** `main.asm` externs exactly two symbols,
  `Circle_new` and `Rect_new`, and after that never mentions either class. The
  `vcall` in the loop is a single instruction pair driving four bodies of code.
- **The cost.** 8 bytes per instance (the vptr) and 32 bytes per class (the
  table), no matter how many objects exist. Ten thousand circles share one
  vtable.
- **Dispatch is data, not identity.** Two circles compare equal on their vptrs;
  a circle and a rect do not. The vptr is just a field.
- **Therefore you can swap it.** `Rect_enable_debug` stores a different table
  pointer into offset 0 and the object starts behaving differently while every
  field stays put. Objective-C calls this isa-swizzling and implements
  key-value observing with it; Smalltalk exposes it as `become:`; the JVM
  forbids it, which is one reason the JIT can trust a call site's type
  feedback.

## Look at the picture

```console
$ make viz
```

Three panels, drawn from the objects this exercise builds rather than typed
out: the canonical object/vtable/class triple, then three instances sharing
two tables - the two Circles' arrows *merge*, because their vptrs hold the same
word - and then the swizzle, before and after:

**Generated output**

```
  Rect instance                         the table it was born with
  +----------------+                    +--------------------------+
  | +0   vptr      |--------+           | +0   Class*  Rect        |
  +----------------+        |           +--------------------------+
  | +8   w = 4     |        |           | +8   slot 0  area        |
  +----------------+        |           +--------------------------+
  | +16  h = 5     |        |           | +16  slot 1  perimeter   |
  +----------------+        |           +--------------------------+
                            |           | +24  slot 2  show        | differs
                            |           +--------------------------+
                            |           the table Rect_enable_debug stores
                            |           +--------------------------+
                            +---------->| +0   Class*  Rect        |
                                        +--------------------------+
```

Only the arrow moved. `viz.asm` compares the two tables word by word to find
which slot they disagree on - three of the four words are identical - and marks
that row itself.

## Look at the machine code

```console
$ make disas | sed -n '/<main>:/,/^$/p' | grep -A2 'mov.*(%rdi)'
```

A direct call is `call <label>` - five bytes, and the branch predictor knows
the target before the instruction issues. The virtual call is a load, a load,
and an indirect call whose target the predictor has to *guess* from history.
For a monomorphic call site it guesses right essentially always. For a
megamorphic one it does not, and that is where the "virtual calls are slow"
folklore comes from - not from the two extra loads.

## Try this

- Add a third class (`Triangle`) in a new file. Note what you must change in
  `main.asm`: only the construction, never the loop.
- Give `Circle` a second vtable whose `SHAPE_AREA` slot returns 0, and swizzle
  a live circle mid-loop.
- Swap the order of `SHAPE_AREA` and `SHAPE_PERIMETER` in `shape.inc`, then
  rebuild *only* `circle.asm` (`touch circle.asm && make`). Watch the wrong
  method get called with no error anywhere. This is a binary compatibility
  break, reproduced in four keystrokes.
- Replace `vcall SHAPE_AREA` with a direct `call Circle_area` and measure the
  difference on a million iterations. Then make the call site polymorphic and
  measure again.

## Next

[05 - Inheritance and overriding](../05-inheritance/) makes one class *be* another
by putting the base object's layout at the front of the derived one.
