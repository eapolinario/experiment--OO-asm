# Runtime type information

**Technique:** recovering a type from a base pointer, subtype tests, checked downcasts, Cohen's display.
**New machinery:** an exercise-local `RttiClass` that extends `Class` with `depth` and a `display` array; a small RTTI runtime (`rtti.asm`).

## The idea

Exercise 04 put a vptr at offset 0 so a caller could invoke a method without
knowing the type. That same pointer is also an *identity*: it leads to the
class descriptor, and the descriptor knows the class's name, its parent, and -
if we cache a little more - its whole ancestry. RTTI is what you get by reading
that metadata instead of calling through it.

Nothing new is stored in the objects. `type_name`, `is_a` and `dynamic_cast`
all start from `vptr -> Class*` and walk from there, so they work on classes
they were assembled before, exactly like a real RTTI runtime:

```asm
type_name:
    class_of rax, rdi                   ; rax = obj->vptr->class
    mov     rax, [rax + RttiClass.name]
    ret
```

The hierarchy is a three-level chain plus one outsider, defined entirely inside
this directory:

```
Stream  <-  FileStream  <-  CompressedFileStream        Widget
```

`Widget` shares the object model but no ancestry, which is what makes the
negative answers meaningful: a test that only ever says "yes" is not testing
anything.

## Two ways to ask "is it one of these?"

The obvious implementation walks the `.parent` chain from the object's dynamic
class to the root, comparing at each step. It is short, it is obviously
correct, and it costs O(depth):

```asm
is_a_slow:
    class_of rax, rdi
.loop:
    test    rax, rax
    jz      .no
    cmp     rax, rsi                    ; is this class the target?
    je      .yes
    mov     rax, [rax + RttiClass.parent]
    jmp     .loop
```

The fast version is **Cohen's algorithm** (1991), the trick real VMs ship. Give
every class a `depth` and a `display`: the array of its own ancestors indexed
by depth, with `display[depth]` being the class itself. Then a subtype test is
a bounds check and a single compare, with no loop at all:

```asm
is_a_fast:
    class_of rax, rdi                   ; C = class_of(obj)
    mov     rcx, [rsi + RttiClass.depth]        ; d = target.depth
    cmp     rcx, [rax + RttiClass.depth]
    ja      .no                                 ; target deeper than C: impossible
    mov     rax, [rax + RttiClass.display + rcx*8]
    cmp     rax, rsi                            ; C.display[d] == target?
    je      .yes
```

`CompressedFileStream`'s display is `[Stream, FileStream, CompressedFileStream]`.
Asking "is it a `FileStream`?" reads `display[1]` and compares - O(1) whether
the hierarchy is 3 deep or 300. The program runs both functions on every query
and prints them side by side; they never disagree.

The trade-off is space and rigidity. The display is O(depth) words *per class*,
paid once, and it assumes single inheritance and a hierarchy known when the
tables are built. Multiple inheritance breaks the "one integer depth" model -
which is exactly why C++ does **not** use Cohen's display and instead pays for
a general graph search (see below), while Java and the CLR, whose classes have
one superclass, can and do.

## The checked downcast

`dynamic_cast(obj, target)` returns `obj` when the subtype test passes and
`NULL` when it fails. That `NULL` is the whole product: it lets the caller take
a different branch instead of reading a field that is not there.

```asm
    call    dynamic_cast                ; -> pointer, or NULL
    test    rax, rax
    jz      .not_that_type              ; the branch that makes it "checked"
```

Contrast the unchecked cast, C++'s `static_cast<Derived*>(base)`: that compiles
to *nothing* - it reinterprets the pointer and trusts you. When you are right
it is free; when you are wrong the next virtual call reads a garbage vtable
slot. `dynamic_cast` is `static_cast` with the `is_a` test put back in, and the
program shows it succeeding on a real `CompressedFileStream` (so it may read the
derived-only `ratio`) and returning `NULL` for a plain `FileStream`.

## What the program shows

1. **One vtable, two jobs.** Each `describe` line is produced by `vcall`
   (dispatch, slot 1); the type name printed at its head comes from
   `class_of` (identity, slot 0). The same pointer serves both.
2. **`is_a`, two ways, always agreeing.** Eight queries cover a class, its
   parent, its grandparent, an unrelated class, and two that exercise Cohen's
   bounds check (target deeper than the object). `walk` and `cohen` match on
   every line.
3. **A downcast you branch on.** One success, one `NULL`, two different code
   paths - the second never touches `ratio`.
4. **Filtering a mixed array.** The same four objects, held as base pointers,
   filtered first by `is-a Stream` (3 of 4) then by `is-a FileStream` (2 of 4).
   `Widget` is dropped both times.

## What real runtimes do

The model here is deliberately close to the real thing, with a few honest
simplifications worth naming:

- **Python precomputes the answer.** `isinstance(x, C)` does not walk anything
  in the common case: every type carries `tp_mro`, a tuple of its ancestors
  built once at class-creation time, and the check is a scan of that tuple.
  That is the display from the section above, kept on the class. Our
  `.parent` chain is the version you build before you think of caching it.
- **Type metadata sits next to the dispatch table.** Our `vtable[0]` pointing
  at a class descriptor is what compiled languages do too; they usually park it
  just before the first method slot, so a type query is one load at a known
  offset from the vptr.
- **Checked casts can be expensive.** With single inheritance the test is a few
  loads. With multiple inheritance it becomes a graph search with pointer
  adjustments, expensive enough that performance-sensitive codebases ban the
  feature and dispatch another way - a visitor, a hand-rolled tag, a variant.
- **`-fno-rtti` exists** precisely because the metadata is not free: it is
  code size and data size in every translation unit, whether or not you ever
  call `typeid`. Projects that never downcast (LLVM, many game engines) compile
  with `-fno-rtti`, ship their own lightweight `isa`/`classof` instead, and get
  the bytes back. This exercise is, in effect, that hand-rolled scheme.

## Try this

- Add a fourth level, `EncryptedCompressedFileStream <- CompressedFileStream`.
  Fill in its `depth` (3) and `display` by hand, then confirm `is_a_fast`
  answers `is-a Stream` in the same one compare it uses for the shallow types.
- Delete the bounds check (`ja .no`) from `is_a_fast` and ask
  `is_a_fast(a Stream, FileStream_class)`. Watch it read past the object's
  valid display entries and return a wrong answer - the check is correctness,
  not just safety.
- Replace `dynamic_cast` with a raw `mov` in `trycast` (the `static_cast`) and
  run it on the `FileStream`. It now prints a `ratio` that was never stored -
  reading whatever the adjacent bytes happen to hold.
- Add a second, unrelated hierarchy (say `Shape <- Circle`) and confirm every
  cross-family `is_a` is `no` in both directions, from both algorithms.

## Next

[08 - Message passing, selectors and a method cache](../08-message-passing/)
throws out fixed slot numbers entirely and resolves methods by name at run
time, the way Smalltalk, Objective-C, Ruby and Python do.
