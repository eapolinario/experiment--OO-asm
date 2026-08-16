# Single inheritance and overriding

**Technique:** prefix layout, vtable copy-and-override, constructor/destructor chaining, the virtual destructor.
**New machinery:** none new in `include/`; a class family (`Account`, `SavingsAccount`, `CheckingAccount`) split across translation units that share only `account.inc`.

## The idea

Inheritance sounds like a language feature. It is three mechanical facts:

1. **The derived object begins with the base object.** `SavingsAccount`'s
   fields are laid down after a complete `Account`, in the same order, so
   `offsetof(Account, balance)` and `offsetof(Savings, balance)` are the *same
   number*. A `Savings*` is therefore already an `Account*`: the "upcast"
   adjusts the pointer by zero bytes. `account.inc` makes this literal by
   emitting the base fields from one `ACCOUNT_FIELDS` macro into every struct,
   and then asserting the offsets coincide at assembly time.

2. **The derived vtable is the base vtable, copied.** Some slots are
   overwritten with the derived function pointers; new slots are appended after
   them; nothing is ever renumbered. In this exercise slots 0-2 (destructor,
   `kind`, `month_end`) are overridden, slot 3 (`summary`) is inherited
   *verbatim* - the identical function pointer sits in all three vtables - and
   slot 4 is appended, differently, by each subclass. A base-only caller doing
   `vcall month_end` lands in derived code without knowing the class exists.

3. **Constructors chain base-first, destructors derived-first.** `Savings_init`
   calls `Account_init` and only then overwrites the vptr with
   `Savings_vtable`. `Savings_destroy` frees what it owns and then calls
   `Account_destroy`. Both orders fall out of "the base slice must be a valid
   object before the derived slice exists, and must outlive it".

That is single inheritance. Everything C++ adds on top - access control,
multiple bases, virtual bases - is refinement.

## The gotcha construction makes observable

Because the base constructor installs the *base* vptr and runs to completion
before the derived vptr is written, a virtual call made during base
construction resolves to the base. `Account_init` makes exactly that call and
stashes the answer in `.kind_at_birth`; the program prints it next to the
finished object's `kind()`:

```
  during construction, a virtual kind() returned  "Account"
  after construction,  the same call returns      "SavingsAccount"
```

This is why a virtual call in a C++ base-class constructor never reaches a
derived override - not a special case, just the vptr not being installed yet.

## Calling the base implementation

An override often wants to do the base thing *and* something extra.
`Checking_month_end` calls `Account_month_end` directly - a static,
non-virtual `call`, the equivalent of `Account::month_end(this)` - to advance
the statement period, then subtracts its fee. The program shows the period
counter moving (base ran) and the balance dropping (override ran) from a
single `vcall`.

## The virtual destructor, and the bug it exists to prevent

`account_delete` deletes through an `Account*` by dispatching the destructor
*through the vtable*: the most-derived destructor runs, frees the resource the
derived slice owns (a heap-allocated note), and chains to the base destructor,
which closes the object. `account_delete_nonvirtual` instead calls
`Account_destroy` statically - exactly what C++ emits when the base destructor
is **not** declared `virtual`. The derived destructor never runs.

The instrumented allocator from exercise 03 makes the difference impossible to
miss. After the correct sweep both counters are zero. After the buggy delete:

```
  after the non-virtual delete   live objects=0  heap blocks=1
```

The object count balances - the base destructor did run - but a block outlives
every object. That orphan is the derived note, leaked because `~SavingsAccount`
was skipped. The program then reclaims it by hand (as a leak detector would)
so it ends at `0 / 0`; `valgrind` agrees.

## What the program shows

- **Layout** - identical field offsets in base and derived, a zero-byte
  upcast, and a deliberately base-only reader pulling the right balance out of
  a `Savings*` it was handed unchanged.
- **Vtable** - 4 base slots vs 5 derived, the `summary` slot inherited as the
  same pointer, the `month_end` slot overridden, the `parent` link walked from
  `SavingsAccount` to `Account`, and the inherited `Account_summary` printing a
  derived `kind` because it dispatches virtually.
- **Construction** - the base-vptr gotcha, printed.
- **Base call from an override** - period advanced by the base, fee taken by
  the override.
- **One loop, three classes** - an array of `Account*` holding a plain account,
  two savings and two checking, driven by a single `vcall month_end`; the sign
  of the returned delta, not a type tag, chooses "credited" vs "charged".
- **Destruction** - virtual vs non-virtual, proven in the counters, balanced to
  zero at the end.

## Try this

- Delete the `mem_free` that reclaims the orphaned note and rerun under
  `valgrind`: the `heap blocks=1` line is now a real, reported leak.
- Add a `PremiumSavings : SavingsAccount` two levels deep. Its `init` chains
  through `Savings_init` through `Account_init`; confirm `live_objects` still
  moves by exactly one per object.
- Give `CheckingAccount` an overdraft limit field and have `Checking_month_end`
  refuse to go below it. Note you changed one file and no vtable slot numbers.
- Swap slots 2 and 3 in `account.inc` and rebuild only `savings.asm`
  (`touch savings.asm && make`). Watch `summary` and `month_end` trade places
  with no error anywhere - the binary-compatibility break from exercise 04,
  now across an inheritance edge.

## Next

[06 - Interfaces and multiple inheritance](../06-interfaces/) is where a single
vptr at offset 0 stops being enough, because two base classes cannot both live
there.
