# Inheritance

> Exercise: [05](../exercises/05-inheritance/)

## The problem

We want a `SavingsAccount` to be usable anywhere an `Account` is expected -
passed to functions compiled against `Account`, stored in arrays of `Account*`,
and yet able to answer some messages differently.

## The technique: the base is a prefix

Lay the derived object out as *the base object, followed by the new fields*.

```
Account                     SavingsAccount
+0   vptr                   +0   vptr
+8   id                     +8   id           \
+16  balance                +16  balance      / exactly the Account layout
                            +24  rate         <- added by the derived class
```

Now a `SavingsAccount` **is** an `Account`. Not "can be converted to" - it is
the same address, and every `Account` field is at the offset the base's code
already expects. Widening the type is free; it is a no-op that exists only in
the type system. That is the entire structural content of single inheritance.

CPython does this literally. A type's `tp_basicsize` is the size of its C
struct, and a subtype's struct begins with its base's struct: `PyLongObject`
starts with the same header every `PyObject` starts with, which is why any C
function taking a `PyObject *` can be handed an int without conversion. It is
also why exercise 06's layout conflict exists - two bases cannot both be that
prefix.

Two things fall out:

- **Arrays of objects are not covariant.** A block of `Account`s and a block of
  `SavingsAccount`s have different strides, so writing one into the other's
  storage produces an object missing its tail. Languages that allow it check at
  run time on every write; most later languages made arrays invariant instead.
  (Python sidesteps the question entirely: its lists hold pointers, so every
  element is one word regardless of type.)
- **Copying by value truncates.** Copying a derived object into base-sized
  storage silently drops the extra fields and leaves a vptr that says "base".
  Languages that pass objects by value have to warn about this; languages that
  only ever pass references, Python included, never meet it.

## The derived vtable

The base's vtable is copied and some entries are replaced. New methods are
appended after the base's slots, never inserted among them:

```
Account_vtable          SavingsAccount_vtable
[0] Account_class       [0] SavingsAccount_class
[1] Account_destroy     [1] SavingsAccount_destroy     <- overridden
[2] Account_describe    [2] SavingsAccount_describe    <- overridden
[3] Account_monthly     [3] SavingsAccount_monthly     <- overridden
                        [4] SavingsAccount_set_rate    <- appended
```

Because the first N slots keep their meaning, base-only code indexing slot 2
reaches the derived override without knowing the derived class exists. This
prefix property applied twice - to fields and to slots - is single inheritance.

Also note the class descriptor: `Class.parent` points at the base's descriptor,
which is the chain that [RTTI](05-rtti.md) walks.

## Constructing and destroying

Construction runs base-first: `SavingsAccount_init` calls `Account_init`, then
installs the derived vptr, then initialises its own fields. Destruction runs in
exactly the reverse order.

The ordering is not arbitrary, and it is the source of a bug that every
language expresses differently while having the same cause: **during
construction, an object is not yet the type it is going to be.**

In our implementation, a dispatched call made before the derived vptr is
installed reaches the *base* version, because at that instant the vtable in the
object still says "base". Some compiled languages specify exactly that
behaviour, since it is what the machine does.

Python takes the other option, and gets the mirror-image bug:

```python
class Base:
    def __init__(self):
        self.setup()            # dispatches on the real class...

class Derived(Base):
    def __init__(self):
        super().__init__()
        self.cache = {}
    def setup(self):
        self.cache['ready'] = True   # AttributeError: no attribute 'cache'
```

Here the override *does* run, because a Python object's `__class__` is correct
from the moment it is allocated - there is no half-installed vptr. What is not
ready is the object's *state*, so the override runs against fields that do not
exist yet. Same hazard, opposite symptom: one language gives you the wrong
method, the other gives you the right method at the wrong time. Both are the
consequence of construction being a process rather than an instant.

## Virtual destructors

Put the destructor in a vtable slot and `delete` through a base pointer works:
the object's own table names its own destructor, which cleans up the derived
part and then calls the base destructor directly.

Leave it out of the table and the base destructor runs alone. The derived
fields are never cleaned up, whatever they own leaks, and nothing complains.
Exercise 05 demonstrates both paths and proves the difference with allocation
counters, which is more convincing than the warning in the textbook.

This is why the rule is "if a class has any virtual function, give it a virtual
destructor", and why `std::shared_ptr` is unusual in *not* needing one - it
captures the deleter for the concrete type at construction time.

## `super`

Calling the base implementation from an override is a **non-virtual, direct**
call to a known symbol:

```asm
    call    Account_describe        ; i.e. Account::describe(this)
```

It has to be non-virtual. If `super.describe()` dispatched through the vtable,
an override calling its base implementation would call itself, forever. So
`super` is the one place where an object-oriented language deliberately turns
dynamic dispatch off. Languages that allow more than one base have to let you
say *which* base you mean, either by naming it explicitly or - as Python does
with `super()` and the MRO - by defining a total order over the ancestors and
walking it. That question only has an answer once
[multiple inheritance](04-interfaces.md) exists.

## What inheritance costs

Structurally, nothing: no extra indirection, no extra memory, no extra
instructions. A derived object is a base object with more fields, and the call
sequence is identical.

The costs are in software engineering, and they are real enough that a
generation of language design moved away from implementation inheritance:

- **The fragile base class problem.** A base class's public methods are its
  contract; its *internal calls between those methods* are also a contract,
  because a subclass may have overridden any of them. Changing which internal
  method the base calls can break subclasses that compile fine. There is no
  layout trick that fixes this; it is a coupling problem.
- **Layout coupling.** Adding a field to a base class shifts every derived
  field. Adding a virtual function shifts every derived slot. Both are ABI
  breaks for separately compiled subclasses.
- **The hierarchy is a taxonomy you have to get right early**, and taxonomies
  are hard. Every "Square is not a Rectangle" argument is really about
  behavioural subtyping (the Liskov substitution principle) not being enforced
  by the mechanism: the machine only guarantees that the offsets line up.

Which is why modern practice prefers composition plus interfaces: keep the
prefix trick for *interface* conformance (exercise 06), and hold collaborators
in fields instead of inheriting them. Go and Rust omit implementation
inheritance entirely; Java, C# and Swift have it but push you toward interfaces
and protocols. Python keeps implementation inheritance but leans on duck
typing and protocols in practice, so the hierarchy usually stays shallow.

Next: [interfaces and multiple inheritance](04-interfaces.md), where the prefix
trick runs out of room.
