# Wider numeric payloads

> **Status:** the integer half is implemented. Exact integers are
> twenty-four-bit and travel as `A:CHL` (see
> [value-contract.md](value-contract.md)); binary16 remains the float format
> until the twenty-four-bit float replaces it. The sections below on
> integers describe work that is now done; the float sections are the plan.

The four-byte cell leaves a byte beside the current sixteen-bit payload. That
byte can hold the high part of a future numeric value, but storage alone does
not make the language twenty-four-bit. Values still travel through the current
`A:HL` runtime convention, where `A` is the tag and `HL` is the sixteen-bit
payload. A wider numeric value therefore needs a transport decision as well as
wider arithmetic.

This note records the work implied by that change. The current sixteen-bit
integer and binary16 implementations remain the reference until a complete
replacement has passed the existing numeric, reader, writer and CP/M proofs.

## Exact integers

An exact twenty-four-bit signed integer would have the range -8,388,608 to
8,388,607. The decimal reader already accumulates a forty-byte numerator, so
its wide multiplication and comparison machinery can remain. The range check
in `src/compiler/decimal/integer.asm` would accept three magnitude bytes
instead of two, and the scope emitter would have to publish the third payload
byte.

The runtime work is broader:

* `src/runtime/numeric/ops.asm` needs three-byte checked addition, subtraction
  and multiplication. Multiplication must either keep a six-byte intermediate
  or reject a partial product before it can exceed the signed twenty-four-bit
  range.
* `src/runtime/numeric/divide.asm` needs three-byte dividend, divisor,
  remainder and quotient state and twenty-four restoring-division steps.
* `src/runtime/numeric/convert.asm` needs three-byte negation and bounds checks.
  The negative endpoint is exactly -8,388,608, so it needs the same asymmetric
  handling as the current -32,768 case.
* `src/runtime/numeric/compare.asm` must compare three-byte signed values and
  preserve exact ordering when an integer is compared with a floating value.
* `src/runtime/data/writer.asm` must print three-byte integers. The current
  decimal writer repeatedly subtracts sixteen-bit divisors.
* `src/runtime/primitives/numeric.asm` and the numeric state block must carry
  the extra byte through folds, predicates, quotient/remainder and error exits.

The mixed integer and binary16 paths need particular care. Binary16 represents
every integer exactly only through 2,048. Converting a twenty-four-bit integer
to binary16 may produce a rounded finite value or infinity, while comparing an
integer with a binary16 value must continue to compare the mathematical values
without first rounding the integer. The existing mixed comparison path in
`src/runtime/numeric/compare.asm` is therefore not a simple width substitution.

## A twenty-four-bit float

A twenty-four-bit float needs a format before arithmetic can be changed. Two
reasonable layouts are:

* one sign bit, six exponent bits and seventeen fraction bits, giving eighteen
  bits of precision including the implicit leading one and an exponent range
  similar to a small scientific format;
* one sign bit, seven exponent bits and sixteen fraction bits, giving seventeen
  bits of precision and a wider exponent range.

Either layout improves on binary16's eleven-bit significand. The choice fixes
the encodings for zero, subnormals, infinity and NaN, so it should be made with
a set of golden values before assembly changes begin.

The format must also preserve the existing tag-zero scalar namespace. Payloads
in that namespace encode booleans, sentinels, primitive values and byte
characters. A zero-extended sixteen-bit immediate cannot simply be interpreted
as an arbitrary twenty-four-bit float because one of those reserved values
could become a finite subnormal. The format work must either assign a reserved
twenty-four-bit prefix for these immediates or introduce a separate numeric
tag. The current nine-tag ABI favours an explicit reserved namespace, but the
choice belongs in the format specification and its golden-value tests.

The arithmetic modules under `src/runtime/binary16/` would then need parallel
changes:

* classification and unpacking would read the new exponent and fraction
  fields;
* addition and subtraction would align a wider significand and retain enough
  guard, round and sticky bits;
* multiplication would need the product of the wider significands;
* division would generate the new quotient width;
* packing and rounding would apply the new exponent limits and special values;
* comparison and integer conversion would use the new format; and
* the decimal parser and literal emitter would publish the new payload while
  retaining the existing exact-rational conversion path.

The current binary16 modules already separate those concerns, which limits the
places that need redesign. It does not make the change a constant-only update:
the significand products, quotient loops, rounding boundaries and conversion
tests all change together.

## The transport decision

The cell layout can carry three payload bytes, but the current calling
convention cannot. A value passed through a generated call has a four-byte
argument packet with two payload bytes, a tag byte and a publication byte. The
stack slots and the `A:HL` register convention have the same sixteen-bit
assumption.

There are two practical migration choices:

1. Extend value packets to five bytes: three payload bytes, a tag and the
   publication byte. This preserves the separate tag and root-publication
   fields but changes argument traversal, stack frames and every packet-backed
   adapter.
2. Use four-byte cell-shaped packets with the tag and publication state packed
   into the metadata byte. This saves a byte per packet but changes the calling
   convention and requires a new rule for collector state during ordinary
   copies.

Both choices also require a register contract. The wide prototype must state
where unary and binary operands live, where the third payload byte is read and
written, how a result is returned and which value remains available on an
error. A low-risk internal prototype is memory-record based: `HL` points to
the left four-byte cell, `DE` points to the right cell for a binary operation,
and the result is written to a non-allocating `NUM_WIDE` cell whose address is
returned in `HL`; carry clear reports success and carry set reports an error in
`A`, with the original left record unchanged. That is a proposal for the
prototype, not a change to the current ABI. A final contract must also define
whether heap cells may be passed directly and how a caller copies the result
back into a stack slot or packet.

Neither choice belongs in the storage-only experiment. Until one is selected,
the high payload byte must remain zero at every public ABI boundary. A partial
implementation that writes a third byte only in heap cells would lose values
when they enter a call, a vector operation or a collector root.

## A safe order of work

The least disruptive sequence is:

1. Specify and test the wide packet or cell adapter in host code while the
   native runtime still uses sixteen-bit values.
2. Implement twenty-four-bit exact integers first. Their representation is
   straightforward and gives useful evidence about packet size, stack depth,
   code size and cycle cost.
3. Extend decimal literals, integer printing, mixed integer and float
   comparison and integer-to-float conversion.
4. Select a twenty-four-bit float encoding from golden values, then implement
   classification, packing, addition, subtraction, multiplication, division,
   comparison and conversion as one format change.
5. Requalify datum input, output, vectors, pairs, closures, ports, `apply`,
   `call/ec`, malformed values and all numeric boundary cases on CP/M.

The acceptance comparison must report generated COM and ASO sizes, runtime
bytes, writable numeric workspace, stack low-water mark, instruction counts
and collection behaviour. It must include values at both integer endpoints,
rounding ties, signed zero, the smallest and largest finite floats, infinities,
NaN, mixed comparisons around the exactness boundary and failed conversions.

The immediate four-byte-cell work can therefore finish without choosing a
twenty-four-bit numeric ABI. The spare payload byte is a measured extension
point, not yet a promise that every numeric primitive accepts a wider value.
