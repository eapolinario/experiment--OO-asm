# Reference counting and object lifetime

**Technique:** a count in the object header, retain/release, ownership by composition, weak references.
**New machinery:** `rc_alloc`/`rc_retain`/`rc_release`, a virtual destructor slot, an instrumented allocator, `weak_*`.

## The idea

Every earlier exercise freed its objects at a point the programmer chose. This
one hands that decision to the objects. Each carries a count of how many
references point at it; whoever drops the last reference runs the destructor
and reclaims the storage. Lifetime becomes a local, mechanical rule instead of
a whole-program argument.

The machinery is one extra word and two functions:

```asm
struc Rc
    .vptr:  resq 1          ; still offset 0, so exercise 04's dispatch works
    .refs:  resq 1          ; the reference count
endstruc

rc_retain(o):   o->refs += 1
rc_release(o):  if (--o->refs == 0) { o->dtor(); free(o); }
```

`rc_release` reuses the vtable from exercise 04 to call a virtual destructor
(method slot 0), then frees the block - the same destruct-then-deallocate split
as [exercise 03](../03-constructors-and-heap/). Destruction is *immediate and
deterministic*: it happens the instant the count hits zero, on the thread that
released it, in a defined order. That is the property a tracing garbage
collector cannot give you, and it is exactly why reference counting composes
with RAII, `with`-blocks and `defer` - the destructor is a place you can close
a file or unlock a mutex and know when it runs.

## Proving it, not asserting it

`rc.asm` keeps the two counters from exercise 03 - `live_objects` and
`live_blocks` - and the program prints them after every step. Each section
begins and ends at zero, so the output *is* the leak test. It is confirmed by
the real thing:

```console
$ nix develop -c valgrind --leak-check=full ./build/10-reference-counting
... in use at exit: 0 bytes in 0 blocks
```

## What the program shows

1. **retain/release on one object.** The count goes 1, 2, 1, 0, and at 0 the
   destructor runs. Nothing subtle - just the mechanism in isolation.
2. **Ownership through composition.** A `Node` retains each child it is given
   and releases them in its destructor, so a tree is destroyed by releasing its
   root. The destruction order is post-order (`para, section-1, section-2,
   doc`): children die before their parents, because the destructor releases
   children before announcing itself. This is a type whose members are
   `shared_ptr`, written out by hand.
3. **Sharing.** One object handed to two owners reaches refcount 2. Releasing
   the first owner drops it to 1 and destroys nothing; releasing the second
   takes it to 0 and destroys it. The count is printed at each step. No owner
   needs to know whether it is the last - that is the entire point.
4. **The cycle refcounting cannot fix.** Two nodes retain each other. Dropping
   both external references leaves each at refcount 1, held only by the other:
   `live objects = 2`, unreachable yet never freed. This leak is *structural* -
   no order of `release` calls can fix it, because neither count can reach zero
   while the other lives. The program then breaks one edge by hand and the
   counters return to zero, so it does not exit leaking.
5. **Weak references.** A `WeakRef` holds a target pointer but never retains it,
   so it does not keep the target alive; two weak refs leave the target at
   refcount 1. When the target dies it walks its list of weak references and
   nulls each one, so a weak reference is always either valid or *provably
   dead* - `weak_alive` flips from yes to no the moment the target is destroyed,
   and can never dangle.
6. **The cycle, collected.** Rebuilt with the back-edge weak, releasing the one
   strong external reference frees both nodes. A weak edge does not contribute
   to the count, so there is no cycle of ownership to get stuck.

### The weak-reference design, and its cost

The honest, simple design: every target keeps a singly linked list of the weak
references aimed at it, threaded through the cells themselves. Creating a weak
reference is O(1) (push to the front). A target's death is O(number of weak
refs) - it walks the list once, nulling each. Deleting a weak reference while
its target is still alive is O(list length), because the cell must be unlinked
so the target does not later write through freed memory; if the target is
already dead, the cell was nulled and deletion is O(1). A production runtime
(ARC, libc++) keeps weak references in a side table keyed by object address,
trading this per-object list for one global hash - but the invariant is the
same: *the target must be able to find its observers.*

## How other systems make the same trade

| System | Counting | Cycles | Weak |
| --- | --- | --- | --- |
| CPython | `Py_INCREF`/`Py_DECREF`, non-atomic (GIL) | a separate cyclic GC exists *precisely* for this leak | `weakref` |
| Objective-C ARC | compiler-inserted retain/release | programmer breaks them | `__weak`, zeroed on death |
| Swift | ARC, atomic | programmer breaks them | `weak`/`unowned` |
| Rust | `Rc<T>` non-atomic, `Arc<T>` atomic | `Rc` cycles leak by design | `Weak<T>` |
| C++ | `shared_ptr`, atomic control block | `shared_ptr` cycles leak | `weak_ptr` |

Two threads through that table are worth stating outright:

- **Cycles are the universal caveat.** Reference counting cannot collect a
  cycle, so every counted system either adds a tracing collector for cycles
  (CPython) or makes breaking them the programmer's job with weak references
  (everyone else). This exercise shows both the disease and the manual cure.
- **Atomicity is the universal cost.** `rc_retain` here is a plain `inc`. Make
  it a `lock inc` and every retain/release becomes a serialised atomic RMW.
  That single word is why Rust splits `Rc` from `Arc` and why thread-safe
  counting is measurably slower - the counter is shared mutable state, and
  shared mutable state across threads costs a bus lock.

What refcounting buys for that cost is determinism: an object dies the instant
it becomes unreachable through strong references, not "sometime later", which is
why it underpins RAII while tracing GC underpins `finalize()`-style
"eventually" cleanup.

## Try this

- Delete the `Node_release_children` call that breaks the cycle and run under
  valgrind: watch `live objects` stay at 2 and valgrind report the leak. That
  is the bug CPython's `gc` module exists to sweep up.
- Make `rc_retain`/`rc_release` use `lock inc`/`lock dec` and note that the
  program is still correct but every reference operation is now atomic - you
  have turned `Rc` into `Arc`.
- Give `Node` a `parent` pointer. Make it strong and create a leak; make it
  weak (as the last section does) and watch the leak vanish. This is the exact
  decision a doubly linked tree forces on you in C++ and Rust.
- Add a `Node_remove_child` that releases and forgets one child while the parent
  lives, and confirm the counters still balance.

## Next

This is the last rung of the ladder. For where it goes from here, see the
[repository overview](../../README.md) and the open
[stretch issues](https://github.com/eapolinario/experiment--OO-asm/issues): a
mark-and-sweep collector built on top of this exercise (the tracing half of
CPython's design), and porting the whole ladder to AArch64. Back up the ladder,
[exercise 09](../09-prototypes/) is where objects first started pointing at each
other freely, which is what made lifetime a question worth a whole exercise.
