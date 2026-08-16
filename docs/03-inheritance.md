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

Now a `SavingsAccount*` **is** an `Account*`. Not "can be converted to" - it is
the same address, and every `Account` field is at the offset the base's code
already expects. Upcasting is free; it is a no-op that exists only in the type
system. That is the entire structural content of single inheritance, and it is
why C++ can say a derived object "contains" a base subobject and mean it
literally.

Two things fall out:

- **Array covariance is a memory-safety hazard.** An `Account[]` and a
  `SavingsAccount[]` have different strides. Writing an `Account` into a
  `SavingsAccount[]` would produce an object with no `rate`. Java allows this
  and pays with a run-time `ArrayStoreException` check on every array write;
  C++ makes it undefined behaviour; most later languages made arrays invariant.
- **Slicing.** Copying a derived object into base-sized storage silently drops
  the tail and leaves you with a base whose vptr is a base vptr. C++ programmers
  learn this as "don't pass polymorphic objects by value".

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

The ordering is not arbitrary, and it explains a famous C++ surprise:

> A virtual call in a base constructor does not reach the derived override.

Of course it does not. At that instant the derived constructor has not yet
overwritten the vptr, so the object *is* a base - the vtable in it says so. C++
specifies this behaviour precisely because it is what the implementation does;
Java made the opposite choice (the derived override runs, on an object whose
fields are not yet initialised), which trades one kind of bug for another.

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
dynamic dispatch off. In C++ you write the base name explicitly
(`Account::describe()`), which also lets you say *which* base - a question that
only has an answer once [multiple inheritance](04-interfaces.md) exists.

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
and protocols; C++ keeps everything and asks you to be careful.

Next: [interfaces and multiple inheritance](04-interfaces.md), where the prefix
trick runs out of room.
