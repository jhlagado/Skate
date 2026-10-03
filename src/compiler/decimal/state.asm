; Decimal parser constants and static workspace.
; Data labels are shared by the decimal modules.
DEC_NAN0:  DB "nan.0"
.CODE_END:
DEC_WORK:
DEC_SRCP:   DW 0                ; Next unconsumed input address.
DEC_LEFT:   DB 0               ; Remaining token bytes.
DEC_NEG:   DB 0                 ; Zero or IEEE sign bit 128.
DEC_LEAD: DB 0               ; Explicit leading sign was present.
DEC_SEEN:  DB 0                ; At least one mantissa digit was consumed.
DEC_DOT:  DB 0                 ; Decimal point already occurred.
DEC_FLT: DB 0                 ; Point or exponent selects inexact output.
DEC_FRAC:  DB 0                ; Number of mantissa digits after the point.
DEC_LEN:   DB 0                ; Mantissa digit count excluding leading zeroes.
DEC_DIG: DB 0                ; Current decimal digit during wide accumulation.
DEC_ENEG:  DB 0                ; Exponent sign, independent of number sign.
DEC_EDIG: DB 0               ; At least one exponent digit was consumed.
DEC_EXP:   DW 0                 ; Exponent magnitude, saturated at 1000.
DEC_TENS: DW 0                ; Signed decimal exponent minus fractional digits.
DEC_EXP2:  DB 0               ; Signed normalized binary exponent, floor -14.
DEC_CNT: DB 0                 ; Phase-local scaling or quotient loop count.
DEC_BITS:   DW 0                ; Eleven extracted significand bits before rounding.
DEC_NUM:   DS 40                ; Exact numerator, then division remainder.
DEC_DEN:   DS 40                ; Exact denominator, then normalized divisor.
.WORK_END:
