# Value contract

> **Status:** all four steps are done. Every container uses the target cell,
> every value travels as `A:CHL` with byte 2 in `C`, as set out in
> [Transport](#transport), exact integers are twenty-four-bit and floats are
> the twenty-four-bit format in [float24.md](float24.md), with tag 9.

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

* **Exact integers** use the full twenty-four bits as a two's-complement
  value, -8,388,608 to 8,388,607. Overflow is a runtime error, as it was at
  sixteen bits.
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

Every routine that copies a value copies byte 2 with it.

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
4. **What `C` holds:** for an exact integer, payload bits 16–23; for every
   other tag, zero (the reserved bank byte for pointers). The debug check
   below enforces the zero.

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
| integer constant | `LD HL,n / LD A,3` | `LD HL,n / LD A,3 / LD C,x` (+2 bytes) |
| tag-0 constant | `LD HL,n / XOR A` | `LD HL,n / XOR A / LD C,A` (+1 byte) |
| symbol or string | `LD HL,lit / LD A,k` | `LD HL,lit / LD A,k / LD C,0` (+2 bytes) |
| push, pop | `CALL ARG_PUSH`, `ARG_POP` | unchanged |
| load, store | slot and global helpers | unchanged; the helpers move `C` |

Counting constants in the six compiled workloads gives about 40 to 170
bytes per program. In the runtime, a clear-byte-2 store (`XOR A /
LD (HL),A`) becomes `LD (HL),C`, one byte smaller, and a skipped byte 2
(`INC HL`) becomes `LD C,(HL) / INC HL`.

Measured after step 2, the runtime grew from 23,860 to 24,040 bytes (+180),
and the core alone from 18,379 to 18,509 (+130). The projection of no
growth was wrong: most of the cost is the byte-2 fields added beside memory
temporaries (`QT_CEXT`, `QT_DEXT`, `QT_AEXT`, `DR_AEXT`, `VEC_EXT`,
`EC_EXT`, `REST_EXT`) and the loads and stores around them, plus
`RT_WIDEN`. The larger core moves the first heap page, so a core-only program
keeps 2,688 live pairs instead of 2,720.

Measured after step 3, the runtime is 24,206 bytes (+166) and the core 18,639
(+130). Twenty-four-bit arithmetic, division and the shared decimal routine
`NUM_TEXT` cost about that much, after `RT_WIDEN`, the second integer printer
and `number->string`'s own division were removed. The heap's first page did
not move again, so the ceiling stays at 2,688.

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

`src/runtime/core/probe.asm` is assembled into the runtime only when
`build/PROBE` exists:

```bash
deno task probe:on
```

```bash
deno task probe:off
```

Each switch regenerates the runtime tables. With the probe on, every value
consumer calls `PROBE` on entry: `ARG_PUSH`, `ROOT_ADD`, `RT_STORE` (and so
`G_STORE` and `RT_SET`), `HEAP_PUT`, `HEAP_SET`, `SLOT_PUT`, `SLOT_SET`,
`OPS_PUSH`, `QT_PUSH`, and `PAIR_NEW` for both constructor inputs. It checks
`C` against rule 4 for the tag in `A` (an integer's `C` is never wrong). A
mismatch prints
`PROBE site caller` (the consumer's entry and its return address, in hex) on
the console, which fails the proof's output check, then continues with the
corrected byte so one missing producer reports once per site.

Run the CP/M groups with the probe on after any change to how values move.
In the probe build the runtime is larger, so the pinned pair ceiling and the
full-image proof fail by design; every other group must pass with no
`PROBE` line. At the end of step 2 the probe found two producers that did
not set `C` (the primitive operator push in `PRIM_OP`/`PRIM_TL` and the rest
list store in `REST_ARG`), and the whole CP/M suite was then silent.

### Numeric ABI

The binary numeric routines (`NUM_ADD`, `NUM_SUB`, `NUM_MUL`, `NUM_DIV`,
`NUM_CMP`, `NUM_QUOT`, `NUM_REM`) take the left value in `A:CHL` and the
right value as a four-byte cell at `NUM_Y` (payload, byte 2, tag; the tag
byte may carry a packet's flag nibble, which `NUM_LOAD` masks). A packet
record is copied there with one `LDIR`. Results return in `A:CHL`; on
failure carry is set, `A` is the error code and `CHL` the original left
value. `equal?` (`STD_DEEP`) takes its right value the same way, in `STD_R`.

Where a value is produced by a routine that does not know its tag, the
boundary normalises `C`: the primitive dispatcher's retire point and the
datum reader's `DR_PUSH` and `DR_DONE` clear `C` for every tag but 3.

Where the compiler handles an integer literal, byte 2 travels in `C` from
`DEC_INT` through `RD_NEXT` (`RD_EXT`) and the emitter (`ST_IMMED+2`), and a
replay record for an exact integer is kind 9 with the three payload bytes
and the tag implied. Quoted data encodes an integer outside 0–255 as code 8
with three payload bytes.

## Migration steps

Each step keeps every existing proof passing with unchanged results.

1. **Done. Cell-shaped containers, sixteen-bit values.** Move every container to the
   target byte layout: tag nibble in byte 3, byte 2 zero, flags in the high
   nibble. The argument packet's initialized byte becomes its flag nibble.
   No arithmetic changes.
2. **Done. Three-byte transport.** Carry byte 2 through registers, the native stack,
   packets, slots and the collector, still always zero or a sign extension,
   as set out in [Transport](#transport), with the debug check.
3. **Done. Twenty-four-bit exact integers.** Literals, arithmetic, division,
   comparison, printing and conversions.
4. **Done. Twenty-four-bit float.** Binary16 was replaced in one change:
   classification, packing, arithmetic, comparison, conversion, literals and
   printing, with the binary16 modules deleted. [float24.md](float24.md)
   fixes the format; `tools/compiler-checks/float24-reference.ts` is its
   bit-exact host reference, and `tests/compiler-checks/float24_test.ts`
   checks the runtime against it. The runtime came out 41 bytes smaller
   than with binary16 (24,165 bytes).
