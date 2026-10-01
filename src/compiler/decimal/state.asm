; Decimal parser constants and static workspace.
; Data labels are shared by the decimal modules.
DNANSTR:  DB "nan.0"
DEND:
DWORK:
DPTRNEXT:   DW 0                ; Next unconsumed input address.
DREMAIN:   DB 0                ; Remaining token bytes.
DNUMSIGN:   DB 0                ; Zero or IEEE sign bit 128.
DSIGNFLG: DB 0               ; Explicit leading sign was present.
DSEENFLG:  DB 0                ; At least one mantissa digit was consumed.
DDOTFLAG:  DB 0                ; Decimal point already occurred.
DFLTFLAG: DB 0                ; Point or exponent selects inexact output.
DFRACNUM:  DB 0                ; Number of mantissa digits after the point.
DSIGCNT:   DB 0                ; Mantissa digit count excluding leading zeroes.
DDIGVAL: DB 0                ; Current decimal digit during wide accumulation.
DEXPSIGN:  DB 0                ; Exponent sign, independent of number sign.
DEXPDIG: DB 0                ; At least one exponent digit was consumed.
DEXPMAGN:   DW 0                ; Exponent magnitude, saturated at 1000.
DEXPSCAL: DW 0                ; Signed decimal exponent minus fractional digits.
DBINEXP:  DB 0                ; Signed normalized binary exponent, floor -14.
DLOOPCNT: DB 0                ; Phase-local scaling or quotient loop count.
DQUOBITS:   DW 0                ; Eleven extracted significand bits before rounding.
DNUMERAT:   DS 40               ; Exact numerator, then division remainder.
DDENOMIN:   DS 40               ; Exact denominator, then normalized divisor.
DWEND:
