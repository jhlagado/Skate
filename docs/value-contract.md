# Value contract

> **Status: agreed direction, not yet implemented.** This note fixes the target
> value format before code changes begin. The current layouts are recorded in
> the first section so that each migration step can be checked against them.

Skate is moving from sixteen-bit to twenty-four-bit payloads. The wider payload
replaces the sixteen-bit one everywhere: exact integers become twenty-four-bit
integers and binary16 is replaced by a twenty-four-bit float. The two widths
are not intended to coexist. Pointers stay sixteen-bit on the Z80, but the
format keeps room for a later bank number or a native eZ80 address.

The order of work puts correctness before range. The value transport changes
first, with every payload still in sixteen-bit range and the third byte
always zero. Wider arithmetic follows only after that transport has passed
every existing proof unchanged.

## Current layouts

Five containers hold a four-byte value today. They agree on bytes 0 and 1 and
disagree on bytes 2 and 3.

| Container | Byte 2 | Byte 3 |
| --- | --- | --- |
| Inline activation slot (`storage/slots/`) | tag | flags: bit 0 initialized, bit 1 promoted (`SLOT_PTR`) |
| Argument packet (`ARG_PKT`) | tag | always `1` (initialized) |
| Heap binding (`storage/managed.asm`) | zero | bits 0–2 tag 0–7, bit 3 initialized, bit 4 escape, bit 5 allocated, bit 6 mark, bit 7 tag 8 |
| Pair cell (`storage/pairs.asm`) | zero | bits 0–3 tag; CAR cell bit 6 allocated, bit 7 mark |
| Vector element (`vectors/`) | zero | raw tag |

Values in registers use `A:HL`: `A` is the logical tag and `HL` the payload.
Generated code pushes a value as `PUSH AF` then `PUSH HL`, so a value on the
native stack also occupies four bytes, with the flags register as filler.

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

## Registers

On the eZ80 in ADL mode `HL` is twenty-four bits wide, so `A:HL` carries a
whole value unchanged. On the Z80 the third payload byte needs a fixed home
that plays the part of the eZ80's `HLU`:

* `A` is the tag, `HL` is payload bits 0–15 and `C` is payload bits 16–23.
* Routines that load, store, copy or push a value go through a small set of
  helpers or macros. An eZ80 build replaces those helpers rather than the
  routines that call them.

The choice of `C` is provisional. Before it is adopted, a census of runtime
routines must show which ones already clobber `C` between receiving and
returning a value. If that cost is high, the fallback is a pointer convention:
`HL` addresses a four-byte cell, which is slower but needs no extra register.

On the native stack a value stays four bytes on the Z80. The tag word can
carry the tag and the third payload byte together (`B` = tag, `C` = high
payload, pushed as `BC`), so frame sizes do not grow. On the eZ80 in ADL mode
pushes are three bytes each, so a stacked value becomes six bytes; that cost
belongs to the eZ80 port, not to this migration.

## Migration steps

Each step keeps every existing proof passing with unchanged results.

1. **Cell-shaped containers, sixteen-bit values.** Move every container to the
   target byte layout: tag nibble in byte 3, byte 2 zero, flags in the high
   nibble. The argument packet's initialized byte becomes its flag nibble.
   No arithmetic changes.
2. **Three-byte transport.** Carry byte 2 through registers, the native stack,
   packets, slots and the collector, still always zero or a sign extension.
   Add a debug check that fails if a non-zero byte 2 appears where it should
   not.
3. **Twenty-four-bit exact integers.** Literals, arithmetic, division,
   comparison, printing and conversions.
4. **Twenty-four-bit float.** Replace binary16 in one change: classification,
   packing, arithmetic, comparison, conversion, literals and printing. The
   binary16 modules are deleted, not kept alongside.

[`wider-numerics.md`](wider-numerics.md) records the detailed numeric work for
steps 3 and 4. Where it describes sixteen- and twenty-four-bit values side by
side, this note supersedes it.
