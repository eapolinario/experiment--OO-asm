# Constructors, destructors, and objects that outlive their scope

**Technique:** allocation vs construction, resource ownership, destructor discipline.
**New machinery:** `malloc`/`free`/`realloc`, an instrumented allocator, in-place construction.

## The idea

An object that owns nothing is easy: its lifetime is its storage's lifetime.
`Text` owns a heap buffer, and that single fact forces every question real OO
languages answer with syntax:

| Question | C++ syntax | What actually happens |
| --- | --- | --- |
| Get storage | `operator new` | `malloc(sizeof(T))` |
| Make it a valid object | constructor | `Text_init` establishes the invariant |
| Both at once | `new T(...)` | `Text_new` |
| Release what it owns | destructor | `Text_destroy` frees `.data` |
| Release the storage | `operator delete` | `free(this)` |
| Both at once | `delete p` | `Text_delete` |
| Build in memory you already have | placement `new` | call `Text_init` on any 24 bytes |

Splitting those four operations into two pairs is the entire content of this
exercise:

```
Text_init  / Text_destroy     construct / destruct, wherever the bytes live
Text_new   / Text_delete      allocate + construct, destruct + deallocate
```

Confusing the pairs is how you get double frees. `Text_destroy` deliberately
does **not** free `this`: the object did not allocate itself, so it must not
deallocate itself. The in-place `Text` in `main.asm` proves the point - its 24
bytes are a stack slot, its buffer is `malloc`'d, and only the buffer may be
freed.

## Invariants, again

`Text_init` leaves `.data` pointing at `.cap` writable bytes containing a
NUL-terminated string with `0 <= .len < .cap`. `Text_append` may assume that
and must restore it, which is why the growth path updates `.cap` and `.data`
together and copies the NUL along with the payload. Amortised O(1) appends come
from doubling, the same policy `std::vector` and every dynamic array use.

`Text_destroy` is idempotent: it NULLs `.data` so a second call is a no-op
rather than a double free. That is a defensive choice, not a required one -
C++ instead makes it a hard rule that a destructor runs exactly once, and buys
that guarantee with scope-based automatic invocation.

## Proving it, instead of asserting it

`text.asm` routes every allocation through `mem_alloc`/`mem_free`, which keep
two counters: live objects (constructed minus destructed) and live blocks
(malloc'd minus freed). The program prints them after every step, so the
output *is* the leak test - it ends at `live objects=0  heap blocks=0`, and any
regression shows up as a golden-output diff rather than a mystery.

The leak section is worth reading twice: after "forgetting" to delete an
object, the program continues perfectly happily with `heap blocks=4`. Nothing
in the machine objects. That is precisely why leaks survive code review, and
why later languages moved lifetime out of the programmer's hands - see
[exercise 10](../10-reference-counting/).

You can double-check with the real thing:

```console
$ nix develop -c valgrind --leak-check=full ./build/03-constructors-and-heap
```

## Try this

- Delete the `Text_delete(greeting)` call at the end and watch the final line
  disagree with itself. Then run it under valgrind.
- Make `Text_destroy` free `this`, then run it on the in-place object. This is
  the crash that the init/new split exists to prevent.
- Add `Text_clone(const Text *this) -> Text*`: a copy constructor. What must it
  do about `.data` that a `memcpy` of the 24 bytes would get wrong? (That is
  the rule of three in one question.)
- Change the growth policy from doubling to `+8` and count the `realloc` calls.

## Next

[04 - Vtables and dynamic dispatch](../04-vtables/) is where objects stop being
records with functions attached and start choosing their own behaviour.
