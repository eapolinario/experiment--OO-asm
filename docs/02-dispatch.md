# Dispatch: static, virtual, and what a vtable costs

> Exercise: [04](../exercises/04-vtables/)

## The problem

A call site in already-compiled code has to invoke a method whose
implementation depends on the run-time type of the receiver - a type that may
not have existed when the call site was assembled.

Everything else in object orientation is bookkeeping. This is the part that
required an idea.

## The obvious solutions, and why they lose

**Tag and switch.** Give every object a small integer type tag and branch on it.
This works, and it is what a C program usually does first. It fails on
extensibility: every new type requires editing every switch, and the switches
live in code the type author does not own. It also grows a mispredicted
indirect branch anyway once the switch gets large enough to become a jump
table.

**One function per type, chosen by the caller.** Requires the caller to know
the type, which is the thing we are trying to avoid.

**Look the method up by name at run time.** Perfectly viable - it is
[message passing](06-message-passing.md), and Smalltalk, Objective-C, Ruby and
Python all do it. It is flexible and it is slow enough that everyone who does
it also builds a cache.

## The technique: a table of code pointers, per class

Put a pointer at offset 0 of every object. Point it at a per-class array of
function pointers. Fix the meaning of each index. Then:

```asm
    mov     rax, [rdi]              ; rax = this->vptr
    call    [rax + 8*n]             ; slot n
```

Two loads and an indirect call, in that order and with that dependency chain.
This is what `virtual` compiles to in C++, what every non-final method call in
Java compiles to before the JIT devirtualizes it, and what a `dyn Trait` call
compiles to in Rust.

The properties that make it the default choice everywhere:

- **The call site is constant size and constant time**, independent of how many
  implementations exist. Ten classes or ten thousand, it is the same two loads.
- **It is open to extension.** A class compiled next year works with a call
  site compiled today, because the call site only knows a slot number.
- **Per-object cost is one pointer**; per-class cost is one table. Instances
  share behaviour by construction.

## Slot numbers are ABI

The agreement about what index means what is the interface. In this repository
it is literally three `%define`s:

```asm
%define SHAPE_AREA      0
%define SHAPE_PERIMETER 1
%define SHAPE_SHOW      2
```

Insert a method in the middle and recompile only some of the classes, and the
program calls the wrong function with no diagnostic anywhere. Nothing crashes;
the answers are just wrong. Consequences in the real world:

- **Adding a virtual function to a published C++ base class breaks binary
  compatibility.** Not source compatibility - the recompiled world is fine -
  but every DLL/`.so` compiled against the old header now indexes a different
  table. This is why Qt has `d_ptr`, why COM interfaces are immutable by rule
  (you publish `IFoo2`), and why library authors sometimes reserve unused
  vtable slots.
- **Java does not have this problem**, because it resolves methods by name and
  descriptor at class-load time and builds the tables at run time. That
  flexibility is a large part of why the JVM is a large program.

## What it actually costs

The three costs are not equal, and only one of them usually matters.

**Two dependent loads.** `[rdi]` then `[rax + k]`. Both are almost always L1
hits: the vptr is in the same cache line as the object header you just touched,
and a hot vtable stays resident. Call it a few cycles of latency that the
out-of-order engine usually hides.

**An indirect branch.** This is the one that matters. The branch target
predictor has to guess the target from history:

- A **monomorphic** call site (one class ever seen) predicts perfectly. The
  indirect call costs about what a direct call costs.
- A **polymorphic** site (two or three classes, in a stable pattern) is usually
  predicted well by modern indirect predictors.
- A **megamorphic** site (many classes, unpredictable order) mispredicts, and a
  misprediction is a full pipeline flush: tens of cycles.

So "virtual calls are slow" is a claim about *branch prediction*, not about
memory indirection. The loop in exercise 04 alternates Circle, Rect, Circle,
Rect - a pattern real predictors learn.

**Lost inlining.** Frequently the largest cost, and the least visible. A direct
call can be inlined, and inlining is what enables constant folding, dead code
elimination and vectorisation downstream. A virtual call is an optimisation
barrier unless the compiler can prove the target. This is why `final` (Java,
Kotlin, C++11) is a performance annotation, why devirtualization is a real pass
in every serious compiler, and why JITs go to enormous lengths to speculate on
types and then guard the speculation.

## Where the vtable lives

In this repository, vtables sit in `section .data` because their entries are
absolute addresses that the dynamic loader must relocate in a
position-independent executable. Real toolchains put them in `.data.rel.ro`:
writable during relocation, then re-protected read-only by `RELRO`. That
detail exists because a writable vtable is a control-flow hijacking primitive -
overwrite a vtable entry, own the process. It is also why `vptr` corruption is
such a popular exploitation target, and why hardening features (CFI,
vtable verification, PAC on ARM) exist.

## The vptr is just a field

Nothing prevents an object from changing its own vptr. Exercise 04 does exactly
that: `Rect_enable_debug` stores a different table address into offset 0, and
the object starts behaving differently without a single field changing.

- **Objective-C** exposes this as isa-swizzling and implements key-value
  observing with it: observing an object silently reclasses it into a generated
  subclass whose setters post notifications.
- **Smalltalk** exposes it as `become:`.
- **C++ does it to you** during construction and destruction: a base
  constructor installs the base vtable, and the derived constructor overwrites
  it afterwards. That is exactly why a virtual call inside a base constructor
  does not reach the derived override - see [inheritance](03-inheritance.md).
- **The JVM forbids it**, which is precisely what lets the JIT install a type
  guard and trust it.

## Alternatives worth knowing

| Strategy | Call cost | Extensible? | Used by |
| --- | --- | --- | --- |
| Direct call | 1 branch, inlinable | No | non-virtual methods, `final` |
| Vtable slot | 2 loads + indirect branch | Yes | C++, Java, C# |
| Fat pointer (data + itable) | 1 load + indirect branch | Yes | Go interfaces, Rust `dyn Trait` |
| Name lookup + cache | Hash/compare + indirect branch | Very | Objective-C, Ruby, Python |
| Inline cache (monomorphic) | Compare + direct branch | Very | JS engines, JVM JIT |
| Tag + switch | Compare chain or jump table | No | C, and hot paths in VMs |

Notice that the fat pointer saves a load - the itable pointer is already in a
register - at the cost of making every interface value two words. That is the
trade-off Go and Rust chose, and [interfaces](04-interfaces.md) covers it.

Next: [inheritance](03-inheritance.md).
