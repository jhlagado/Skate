# Following a local binding

A Scheme name such as `base` is easy to read. In the executable, a load needs
an address or a slot number. Between those two forms lies a useful first route
through Skate: the compiler establishes where a name is visible, emits code to
store its value and emits code to retrieve it when the body uses the name.

This account follows the public compiler and runtime in this checkout. The
assembly excerpts use ordinary Z80 loads, calls and conditional branches.

```scheme
(begin
  (write
    (let ((base 40)
          (delta 2))
      (+ base delta)))
  (newline))
```

The result is `42` followed by a newline. This is the `LET.SK8` case in the
[CP/M compiler proof](../../tools/compiler-checks/scope-cpm-proof.mjs). The
names `base` and `delta` are visible inside the addition. Their scope ends with
that `let` body.

## Two moments in the life of a binding

The Z80 assembly performs two different jobs. The compiler runs
first, reading Scheme and writing instruction bytes. The generated program
runs later, executing those bytes and calling the runtime. Both programs use
registers called `A` and `HL`, but their contents belong to different executions.

During compilation, the compiler associates a symbol identity with a slot
number. During execution, a slot holds the Scheme value. A symbol identity is
the compiler's representation of a source name. A slot is the storage selected
for that name's value. Keeping those two things separate explains much of the
binding code.

The relevant files are [bindings/forms.asm](../../src/compiler/scope/bindings/forms.asm),
[emitter.asm](../../src/compiler/scope/emitter.asm) and
[core/startup.asm](../../src/runtime/core/startup.asm). The excerpts below cover the relevant paths through these files.

## Reserving a place for `base`

In `bindings/forms.asm`, `SCLETF` begins compilation of an ordinary `let`. It calls
`SCLETSET` to save the enclosing scope state and open the binding list. The
loop at `SCLETB` checks that each binding has the required list structure.
After reading a name, it reaches this sequence:

```asm
        CP 5
        JP NZ,SCLETERR
        LD (SCID),HL
        CALL SCNSLOT
        JP C,SCLETERR
        LD (SCSLOT),A
        CALL SCPEND
        JP C,SCLETERR
```

These instructions are copied from the routine with their inline comments
omitted. Token kind five denotes a
symbol. At that point `HL` contains the identity of `base`. The compiler saves
it in `SCID`, then calls `SCNSLOT` to allocate a compiler slot number. On success
the number is returned in `A` and saved in `SCSLOT`.

`SCPEND` records the association in the pending-binding tables. The distinction
between pending and active bindings implements a Scheme rule: the initialisers
of an ordinary `let` are evaluated in the enclosing scope. The new bindings
become visible together in the body.

For this expression, compilation produces the following states. The letters stand for whichever
slot numbers the compiler assigns, rather than fixed addresses.

| Compilation point | Pending names | Newly active names |
| --- | --- | --- |
| Before the binding list | None | None |
| After reserving `base` | `base → b` | None |
| After reserving `delta` | `base → b`, `delta → d` | None |
| At the body | Records ready to leave the pending phase | `base → b`, `delta → d` |

Outer bindings remain available throughout these steps. Reserving a slot does
not by itself make the corresponding name visible to an initialiser.

## Emitting the store

After reserving `base`, the compiler processes its initialiser, `40`. The next
part of `SCLETB` connects that expression with its destination:

```asm
        CALL SCINIT
        JP C,SCLETERR
        CALL SCPREV
        JP C,SCLETERR
        LD A,(SCSLOT)
        LD L,A
        LD A,1
        CALL SCSTORE
        JP C,SCLETERR
```

`SCINIT` compiles the initialiser. It may process a nested expression with
bindings of its own, so the outer binding's slot cannot simply be assumed to
remain in scratch storage. `SCPREV` recovers the pending binding before the
store is emitted.

At entry to `SCSTORE`, `L` contains the slot number and `A` contains one, the
compiler's selector for a local slot. Those registers describe the destination
while the compiler is running. They do not contain the initialiser's Scheme
value. The instructions already emitted for `40` will produce that value when
the generated program runs.

`SCSTORE` has two paths. A local belonging to a procedure uses the active
procedure environment. This `let` is outside a procedure and uses the static
path at `SCSTFIX`. The beginning of that path is:

```asm
        LD A,11H
        CALL SINKBYTE
        LD HL,(SCPC)
        CALL SCFIX
        RET C
        XOR A
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
```

The byte `11H` is the Z80 opcode for `LD DE,nn`. `SINKBYTE` appends it to the
output; `scope/output-sink.asm` also gives that routine the older label
`SCBYTE`, which some comments still use. The next two bytes will hold the
destination address, but the final slot address is not available yet. `SCFIX`
records the location that needs patching and the emitter writes two zero
placeholders. Later publication resolves that address. The rest of the store path emits a call to the runtime
store service.

This is the point where reading assembly as compiler code can be deceptive.
`LD A,11H` runs now. The `LD DE,nn` represented by that byte runs later. In the
later execution, `DE` will contain the slot address while `A:HL` contains the
value to store: a tag in `A` and a sixteen-bit payload in `HL`.

## Making the value available at runtime

The static slot layout used by this path occupies four bytes:

```text
slot + 0    payload low byte
slot + 1    payload high byte
slot + 2    value tag
slot + 3    flags, including bit 0 for initialisation
```

In `core/startup.asm`, `RT_STORE` writes the payload and tag before setting the
initialisation bit. Its final flag update is:

```asm
        LD A,(DE)
        AND 0FEH
        OR 1
        LD (DE),A
        LD A,(SRTTAG)
        RET
```

Here `DE` has already advanced to the flag byte. Clearing and setting bit zero
preserves the other flags. The routine restores the value tag to `A` before
returning, and the payload remains in `HL`. The store therefore leaves the
stored value available to the generated code.

The separate initialisation bit prevents a load from treating an uninitialised
slot as an ordinary value. Zero is a legitimate Scheme number and cannot stand
in for that state. `RT_LOAD` reads the payload and tag, tests bit zero of the
flags and branches to `SRTUNBD` if the slot is not ready. Otherwise it returns
the saved value in `A:HL`.

## Opening the body

The compiler repeats the binding loop for `delta`. When it reaches the closing
parenthesis of the binding list, it enters `SCLETBD`:

```asm
SCLETBD:
        CALL SCBIND
        JP C,SCLETERR
        CALL SCLEBODY
        JP C,SCLETERR
        JP SCLETEND
```

`SCBIND` copies the pending names and slot numbers into the active local scope.
`SCLEBODY` can then compile `(+ base delta)` with both names available. In the
emitter, `SCLOAD` performs the corresponding selection between static slots and
procedure environments. For these static slots it emits an address load with a
fixup, followed by a runtime load call. When those calls run, they retrieve the
values stored by the initialisers.

The addition and printing use their own runtime services. The binding
mechanism supplies the two values they need. `SCLETEND`
restores the compiler's enclosing scope cursors after the body has been
compiled. That restoration changes subsequent name lookup during compilation.
It is not a runtime instruction that clears the two Scheme values.

## Sequential bindings with `let*`

The same proof contains `LETSTAR.SK8`:

```scheme
(begin
  (write
    (let* ((base 40)
           (delta (+ base 2)))
      delta))
  (newline))
```

This also prints `42`, but the second initialiser now uses the first binding.
In `SCLETSB`, the compiler calls `SCADDLOC` after completing each individual
binding. The next initialiser can therefore resolve that name. Ordinary `let`
waits until `SCBIND` at the end of the list. The source-level difference between
`let` and `let*` is visible in the placement of that table update.

Both paths use the store emitter. Their different visibility rules follow
from when the compiler updates its active scope.

The existing proof can be run from the repository root with the sibling
projects described in the main guide available:

```sh
deno run --config deno.runtime.json \
  --allow-read=.,../atom,../z80-tool-services,../triptych \
  --allow-write=build tools/compiler-checks/scope-cpm-proof.mjs
```

It runs a corpus, including these two cases and nested-binding examples. The
proof compiles the programs under CP/M and checks their execution results.
The adjacent `SHADOW.SK8` case covers nested scopes: an inner `value` binding
produces `2` while the outer binding remains a distinct slot. Restoring the
active scope at `SCLETEND` makes the outer binding available again after the
inner body has been compiled.
