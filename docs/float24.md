# The twenty-four-bit float

Skate's inexact numbers are a twenty-four-bit binary floating-point format,
"float24", carried in a value cell's three payload bytes with tag 9. It
replaces binary16. This note fixes the encoding, the rounding rule, the
special values, the printed form and the runtime interface, and
`tools/compiler-checks/float24-reference.ts` implements all of it bit-exactly
on the host so that the Z80 routines can be checked against golden values.

## Encoding

| Bits | Field |
| --- | --- |
| 23 | sign |
| 22–16 | exponent, seven bits, bias 63 |
| 15–0 | fraction, sixteen bits |

In the value cell the payload bytes hold bits 0–7, 8–15 and 16–23 in that
order, so byte 2 (register `C`) carries the sign and exponent and `HL` the
fraction.

| Exponent field | Meaning |
| --- | --- |
| 0, fraction 0 | signed zero |
| 0, fraction f ≠ 0 | subnormal: f × 2^-78 |
| 1–126 | normal: (1 + f/2^16) × 2^(e-63) |
| 127, fraction 0 | signed infinity |
| 127, fraction ≠ 0 | NaN; the only NaN produced or accepted is 7F8000H |

Consequences: seventeen bits of precision, so every integer of magnitude up
to 2^17 = 131,072 is exact; the largest finite value is (2 − 2^-16) × 2^63 ≈
1.8447 × 10^19; the smallest normal is 2^-62 ≈ 2.17 × 10^-19; the smallest
subnormal is 2^-78 ≈ 3.31 × 10^-24.

## Arithmetic

Every operation computes the exact result and rounds it once to nearest,
ties to even, including overflow to infinity and gradual underflow. The
special cases follow IEEE 754: NaN propagates (always canonical), ∞ − ∞,
0 × ∞, 0/0 and ∞/∞ give NaN, x/0 gives a signed infinity, and the sign of a
zero result is the exclusive-or of the operand signs for × and ÷, the
common sign for a sum of two zeros, and positive for an exact cancellation.
Comparison treats +0 and −0 as equal and NaN as unordered.

Integer to float rounds to nearest even; integers beyond 2^17 may round.
Float to integer truncates toward zero and fails for infinity, NaN and any
magnitude of 2^23 or more.

## Reading and printing

The decimal parser (`src/compiler/decimal/`) keeps its exact-rational path:
the token becomes a fraction, the fraction is scaled to a seventeen-bit
significand, and one rounding step produces the float. A literal whose
decimal order is 20 or more overflows to infinity; one whose order is below
−24 is zero; `+inf.0`, `-inf.0` and `+nan.0` are the only special spellings.

Printing is exact: a finite float prints its full decimal expansion, with
`.0` appended to an integer value, so what `write` produces `read` returns
unchanged. A subnormal needs up to 78 fractional digits. Infinities and
NaN print as `+inf.0`, `-inf.0` and `+nan.0`.

## Runtime interface

The float routines live in `src/runtime/float24/`. Binary operations
(`F24_ADD`, `F24_SUB`, `F24_MUL`, `F24_DIV`, `F24_CMP`) read both operands
from the cells `NUM_X` and `NUM_Y` (payload, byte 2, tag), as the integer
routines do, and return the result in `A:CHL`; `F24_CMP` returns the raw
code −1, 0, 1 or 2 (unordered) in `HL`. Unary routines (`F24_CHK`,
`F24_NEG`, `F24_ITOF`, `F24_FTOI`) take `A:CHL`. A failure returns carry set
with the status in `A`: 1 for a value that is not a number, 2 for an
unrepresentable conversion.

`number?`, the numeric validator, `zero?`, `abs`, `eqv?`, the writer and the
result printer recognise tag 9. The compiler emits a float literal as
`LD HL,fraction / LD A,9 / LD C,sign-exponent`, records it in a replay
record of kind 10 and encodes it in quoted data with code 9, each carrying
the three payload bytes.
