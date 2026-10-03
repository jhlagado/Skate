# Value contract

> **Status:** step 1 is done: every container uses the target cell, with
> byte 2 written as zero. Step 2, the three-byte transport, is specified in
> [Transport](#transport) and is next.

Skate is moving from sixteen-bit to twenty-four-bit payloads. The wider payload
replaces the sixteen-bit one everywhere: exact integers become twenty-four-bit
integers and binary16 is replaced by a twenty-four-bit float. The two widths
are not intended to coexist. Pointers stay sixteen-bit on the Z80, but the
format keeps room for a later bank number or a native eZ80 address.

The order of work puts correctness before range. The value transport changes
first, with every payload still in sixteen-bit range and the third byte
always zero. Wider arithmetic follows only after that transport has passed
every existing proof unchanged.

## Before step 1

Until step 1 the five four-byte containers agreed only on bytes 0 and 1:
inline slots and argument packets kept the tag in byte 2, heap bindings
packed a tag, flags and a ninth tag bit into byte 3, and the native stack
carried the flags register as filler beside the tag. They now all use the
target cell below.

## Target cell

Every container uses one layout:

| Byte | Meaning |
| --- | --- |
| 0 | payload bits 0–7 |
| 1 | payload bits 8–15 |
| 2 | payload bits 16–23 |
| 3 | bits 0–3 logical tag; bits 4–7 flags owned by the container |

The tag nibble is in the low half because pairs already use that position,
with allocation and mark in bits 6 and 7, and every container can then extract
the tag with `AND 0FH`. The flag nibble
belongs to whichever structure owns the cell:

| Container | Bit 4 | Bit 5 | Bit 6 | Bit 7 |
| --- | --- | --- | --- | --- |
| Inline slot | initialized | promoted | reserved | reserved |
| Argument packet | initialized | reserved | reserved | reserved |
| Heap binding | initialized | escape | allocated | mark |
| Pair, CAR cell | reserved | reserved | allocated | mark |
| Pair, CDR cell | reserved | reserved | reserved | reserved |
| Vector element | reserved | reserved | reserved | reserved |

The exact bit assignments may move during the migration, but the rule does
not: copying a value copies bytes 0–2 and the tag nibble, and never copies a
flag nibble from one container into another.

The heap binding's separate tag-8 bit disappears once the tag has four bits.

## Tags

Four tag bits allow sixteen tags. The current nine stay as they are, and
floats move out of the tag-0 scalar family into a tag of their own:

| Tag | Meaning |
| ---: | --- |
| 0 | Immediates: booleans, characters, sentinels, primitive procedures |
| 1 | Pair |
| 2 | Closure |
| 3 | Exact integer |
| 4 | Interned symbol |
| 5 | Compiler-owned literal string |
| 6 | Managed string |
| 7 | Vector |
| 8 | Escape token and port |
| 9 | Float |
| 10–15 | Unassigned |

With floats in their own tag, tag 0 no longer has to reserve part of its
payload space to keep immediates apart from float encodings.

## Payload rules

* **Exact integers** use the full twenty-four bits as a two's-complement value.
  Until the integer step, every integer is in sixteen-bit range and byte 2
  is its sign extension.
* **Floats** use 1 sign bit, 7 exponent bits and 16 fraction bits. The
  sixteen-bit fraction keeps the multiplication and division loops
  byte-aligned and gives seventeen bits of precision. The encodings of zero,
  subnormals, infinities and NaN are fixed by golden values before any float
  code is written.
* **Pointer tags** (1, 2, 4, 5, 6, 7 and the port form of 8) carry a
  sixteen-bit address in bytes 0 and 1. Byte 2 is zero on the Z80. It is
  reserved as a bank number for CP/M 3 banked memory, and on the eZ80 it
  becomes the high address byte.
* **Immediates** (tag 0) keep their current sixteen-bit encodings with byte 2
  zero.

Until the integer step, every routine may assume byte 2 is zero or the sign
extension of an exact integer, and must preserve it when it copies a value.

## Transport

This is the contract for step 2. It was fixed after a census of the runtime
(below), and it is what every routine that moves a value must follow.

### Registers

A value in registers is **`A:CHL`**:

| Register | Holds |
| --- | --- |
| `A` | the logical tag (0–15); the high nibble is zero |
| `C` | payload bits 16–23, the cell's byte 2 |
| `HL` | payload bits 0–15 |

`C:H:L` is the twenty-four-bit payload, in the order a Z80 24-bit routine
expects (`CHL` with a second operand in `BDE`). On the eZ80 in ADL mode `C`
becomes `HLU`, so `A:HL` carries the whole value and `C` is freed. Carry
keeps its meaning: clear for success, set for an error with the code in `A`
where a routine documents one.

`B`, `DE`, `IX` and `IY` are not part of a value. A routine may use them
freely unless its own header says it keeps them.

### Rules

1. **Every producer sets `C`.** Any routine or generated sequence that leaves
   a value in `A:HL` also leaves its byte 2 in `C`: a load copies it from the
   cell, a constant loads it, an arithmetic result computes it. There is no
   "don't care" value of `C`.
2. **Every pass-through keeps `C`.** A routine documented as keeping `A:HL`
   (pushing, rooting, storing and returning the value) keeps `C` too.
3. **Every consumer copies `C`.** Storing a value writes `C` to byte 2;
   pushing one pushes it. Nothing writes a constant zero to byte 2 of a value
   it was given.
4. **What `C` holds:** for an exact integer, the sign extension of `H` until
   the integer step and the top payload byte after it; for every other tag,
   zero (the reserved bank byte for pointers). The debug check below enforces
   exactly this during step 2.

### Native stack

A pushed value stays four bytes and becomes a cell image:

```asm
        LD B,A          ; B = tag beside C = byte 2
        PUSH BC         ; [byte 2][tag] at the higher address
        PUSH HL         ; [lo][hi] below it
```

From the stack pointer up, the bytes are `lo, hi, byte 2, tag`, the same as a
cell, so packing arguments and scanning roots copy four bytes with no
reshuffle. Popping is `POP HL / POP BC / LD A,B`. Generated code does not push
values inline; it calls `ARG_PUSH` and `ARG_POP` (by `RST`), so the change
lives in those helpers. On the eZ80 in ADL mode each push is three bytes, so
a stacked value becomes six; that cost belongs to the eZ80 port.

### Memory temporaries

A routine that parks a value in memory (`ROOT_VAL`/`ROOT_TAG`,
`ARG_VAL`/`ARG_TAG`, `QT_ACC`/`QT_ATAG` and the like) parks `C` with it. The
cleanest form is a four-byte cell-shaped temporary written and read as a
whole.

### Generated code

| Sequence | Now | Step 2 |
| --- | --- | --- |
| integer constant | `LD HL,n / LD A,3` | `LD HL,n / LD C,x / LD A,3` (+2 bytes) |
| tag-0 constant | `LD HL,n / XOR A` | `LD HL,n / XOR A / LD C,A` (+1 byte) |
| push, pop | `CALL ARG_PUSH`, `ARG_POP` | unchanged |
| load, store | slot and global helpers | unchanged; the helpers move `C` |

Measured on the six workloads, the constants add about 40 to 170 bytes per
program before any optimisation. In the runtime, a clear-byte-2 store
(`XOR A / LD (HL),A`) becomes `LD (HL),C`, one byte smaller, and a skipped
byte 2 (`INC HL`) becomes `LD C,(HL) / INC HL`.

### Census

`tools/compiler-checks/register-census.ts` follows the runtime call graph and
reports, for each named routine, whether it can write `C`, directly or through
a callee. It treats error exits as not returning and a `POP BC` that restores
a `PUSH BC` as harmless. At the time of the decision (October 2026):

* 236 of 798 runtime routines can write `C`.
* Every routine that passes a value through already keeps `C`: `ARG_PUSH`,
  `ARG_POP`, `G_LOAD`, `G_STORE`, `G_SET`, `G_OPSH`, `L_LOAD`, `L_STORE`,
  `L_SET`, `ROOT_ADD`, `ROOT_POP`, `OPS_PUSH`, `OPS_POP`, `QT_PUSH`,
  `QT_POP`, `QT_CACHE`, `RT_LOAD`, `RT_STORE`, `RT_SET`, `HEAP_GET`,
  `HEAP_PUT`, `HEAP_SET`, `SLOT_GET`, `SLOT_PUT`, `SLOT_SET`, `CAR`, `CDR`.
* The boundary routines that write `C` all produce a new value and must set
  `C` on exit anyway: `CONS`, `RT_ADD`, `RT_SUB`, `RT_MUL`, the call
  dispatchers (`INV_*`, `PRIM_OP`, `PRIM_TL`, `EC_CALL`, through the packet
  builders), `PAIR_NEW`, `HEAP_LAM`, `QT_BUILD`, `QT_FOLD`, `STD_CASE` and
  `OUT_SHOW`.

So `C` costs no saves at the generated-code boundary. The fallback considered
earlier, passing a pointer to a four-byte cell, is not needed.

```bash
deno task census:registers ARG_PUSH RT_STORE CONS
```

### Debug check

Step 2 adds a transport probe to the CP/M proofs. At the entry of every
consumer (`ARG_PUSH`, `RT_STORE`, `RT_SET`, `HEAP_PUT`, `HEAP_SET`,
`SLOT_PUT`, `SLOT_SET`, `OPS_PUSH`, `QT_PUSH`, `ROOT_ADD` and the packet
builder's reads of the stack), the emulator checks that `C` matches rule 4
for the tag in `A` and the payload in `HL`, and fails the proof with the
routine name and the caller's address if it does not. It runs over the whole
CP/M suite, so a producer that forgets `C` is found by the first program that
uses it. The probe stays in place for step 3, with rule 4 widened to accept
any byte 2 for an integer.

### Order of work in step 2

1. Add the probe, initially reporting rather than failing, and the census
   task.
2. Convert the consumers: `ARG_PUSH`/`ARG_POP`, the stores, the side stacks,
   the root records, the packet builders and the memory temporaries.
3. Convert the producers: loads, constants in the emitter, primitive and
   arithmetic results, the reader and quoted data, until the probe is silent.
4. Make the probe fail, run the full suite, and record code-size changes.

## Migration steps

Each step keeps every existing proof passing with unchanged results.

1. **Done. Cell-shaped containers, sixteen-bit values.** Move every container to the
   target byte layout: tag nibble in byte 3, byte 2 zero, flags in the high
   nibble. The argument packet's initialized byte becomes its flag nibble.
   No arithmetic changes.
2. **Three-byte transport.** Carry byte 2 through registers, the native stack,
   packets, slots and the collector, still always zero or a sign extension,
   as set out in [Transport](#transport), with the debug check.
3. **Twenty-four-bit exact integers.** Literals, arithmetic, division,
   comparison, printing and conversions.
4. **Twenty-four-bit float.** Replace binary16 in one change: classification,
   packing, arithmetic, comparison, conversion, literals and printing. The
   binary16 modules are deleted, not kept alongside.

[`wider-numerics.md`](wider-numerics.md) records the detailed numeric work for
steps 3 and 4. Where it describes sixteen- and twenty-four-bit values side by
side, this note supersedes it.
