;=============================================================================
;  Exact decimal-token conversion
;=============================================================================

;  PURPOSE
;  -------
;  Convert an ASCII decimal token to a binary16 or exact-integer value.

;  PUBLIC INTERFACE
;  ----------------
;

;+---------------------------------------------------------------------------+
;|  DPARSE - Convert one ASCII decimal token.                                |
;|                                                                           |
;|  CALL                                                                     |
;|    HL -> token bytes; BC = length (1..64).                                |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    A = representation tag; HL = payload; carry clear.                     |
;|                                                                           |
;|  FAILURE                                                                  |
;|    A = error code; carry set.                                             |
;+---------------------------------------------------------------------------+

;  RESULT TAGS
;  -----------
;
;  0  binary16 scalar
;  3  exact signed 16-bit integer

;  ERROR CODES
;  -----------
;
;  128  malformed token
;  129  capacity or address extent
;  130  integer range

;  REGISTERS AND WORKSPACE
;  -----------------------
;
;  PRESERVES  IX, IY.
;  SCRATCH    AF, BC, DE, HL and DWORK..DWEND.
;  ALLOCATION No heap or host conversion.
;  MEMORY     Keep input, workspace and stack disjoint.
;  REENTRY    Static workspace makes DPARSE non-reentrant.

;  CONVERSION METHOD
;  -----------------
;
;  Validate the complete grammar before applying magnitude shortcuts.
;  A huge exponent cannot hide malformed token text.
;
;  Two 320-bit unsigned integers represent the exact decimal rational.
;  Normalize their ratio and extract eleven quotient bits.
;  Use the exact remainder for nearest-even rounding without double rounding.
;=============================================================================

DPARSE: LD A,B              ; A byte count above 255 exceeds the token bound.
        OR A
        JP NZ,DCAPERR
        LD A,C
        OR A
        JP Z,DSYNTAX           ; This grammar condition rejects the complete token.
        CP 65
        JP NC,DCAPERR
        PUSH HL             ; Save the input while clearing private state.
        ADD HL,BC           ; Reject an extent that wraps beyond address 65536.
        JR NC,DADDRCHK
        LD A,H
        OR L                ; A carry with zero sum is the exact legal end.
        JR Z,DADDRCHK
        POP HL
        JP DCAPERR
; The whole input extent is valid. Clear all per-call state before parsing.
DADDRCHK:  POP HL
        PUSH HL
        PUSH BC
        LD HL,DWORK
        LD DE,DWORK+1
        LD BC,100           ; 101 workspace bytes; census test guards this size.
        LD (HL),0
        LDIR                ; Every call starts with zero limbs and flags.
        POP BC
        POP HL
        LD (DPTRNEXT),HL         ; Save the next input address.
        LD A,C
        LD (DREMAIN),A          ; Save the remaining token-byte count.
        LD A,(HL)
        CP '+'
        JR Z,DSIGNSET
        CP '-'
        JR NZ,DSPECIAL
        LD A,128
        LD (DNUMSIGN),A         ; Final IEEE sign bit, or integer negation request.
; Consume either leading sign; the negative path already saved its sign bit.
DSIGNSET:  LD A,1
        LD (DSIGNFLG),A      ; Special spellings require an explicit sign.
        CALL DGETBYTE            ; Consume one byte; the caller has checked that one remains.
; Recognize only the three signed, five-byte special tails before mantissa parsing.
DSPECIAL:  LD A,(DREMAIN)          ; Recover the remaining token-byte count.
        CP 5
        JR NZ,DMANTIS
        LD A,(DSIGNFLG)       ; Recover the explicit-sign flag.
        OR A
        JR Z,DMANTIS
        LD HL,(DPTRNEXT)         ; Recover the next input address.
        LD A,(HL)
        CP 'i'
        JR Z,DINFCHK
        CP 'n'
        JR NZ,DMANTIS
        LD A,(DNUMSIGN)          ; Recover the saved number sign bit.
        OR A
        JP NZ,DSYNTAX         ; Only +nan.0 is a valid canonical NaN spelling.
        LD DE,DNANSTR
        CALL DMATCH          ; Compare the remaining spelling with the selected constant.
        JP NZ,DSYNTAX          ; This grammar condition rejects the complete token.
        LD HL,7E00H
        XOR A
        RET
; Validate the entire infinity tail before returning its signed encoding.
DINFCHK:   LD DE,DINFSTR
        CALL DMATCH          ; Compare the remaining spelling with the selected constant.
        JP NZ,DSYNTAX          ; This grammar condition rejects the complete token.
        JP DINFRES
; Read the mantissa, retaining every digit exactly, including those beyond
; binary16 precision. DFRACNUM counts digits after the point; DSIGCNT ignores only
; leading zeroes and later gives the decimal order without wide arithmetic.
DMANTIS:  LD A,(DREMAIN)          ; Recover the remaining token-byte count.
        OR A
        JP Z,DFINISH
        CALL DGETBYTE            ; Consume one byte; the caller has checked that one remains.
        CP '.'
        JR Z,DDOTSEEN
        CP 'e'
        JR Z,DEXPSET
        CP 'E'
        JR Z,DEXPSET
        SUB '0'              ; Convert an ASCII digit candidate to its unsigned numeric value.
        CP 10                ; Only values zero through nine are decimal digits.
        JP NC,DSYNTAX          ; This grammar condition rejects the complete token.
        LD (DDIGVAL),A        ; Save the current decimal digit.
        LD A,1
        LD (DSEENFLG),A         ; Save the mantissa-digit-present flag.
        LD A,(DDIGVAL)        ; Recover the current decimal digit.
        OR A
        JR NZ,DSIGADD
        LD A,(DSIGCNT)          ; Recover the significant digit count.
        OR A
        JR Z,DFRACCT
; Once a nonzero digit occurs, every later digit contributes to decimal order.
DSIGADD: LD HL,DSIGCNT
        INC (HL)
; Count fractional positions even when their digits are leading zeroes.
DFRACCT:   LD A,(DDOTFLAG)         ; Recover the decimal-point-present flag.
        OR A
        JR Z,DACCUM
        LD HL,DFRACNUM
        INC (HL)
; Accumulate this digit without losing low bits needed at a rounding midpoint.
DACCUM:   LD HL,DNUMERAT           ; Select the numerator limbs for the wide operation.
        CALL DMULTEN           ; Numerator = previous digits times ten.
        LD A,(DDIGVAL)        ; Recover the current decimal digit.
        LD HL,DNUMERAT           ; Select the numerator limbs for the wide operation.
        ADD A,(HL)
        LD (HL),A
        JR NC,DMANTIS
        LD B,39
; A low-limb digit addition overflowed; increment successive higher limbs.
DADDPROP: INC HL
        INC (HL)            ; Propagate decimal digit addition through limbs.
        JR NZ,DMANTIS
        DJNZ DADDPROP
        JR DMANTIS
; Permit one decimal point, and remember that this is an inexact literal.
DDOTSEEN:   LD A,(DDOTFLAG)         ; Recover the decimal-point-present flag.
        OR A
        JP NZ,DSYNTAX          ; This grammar condition rejects the complete token.
        INC A
        LD (DDOTFLAG),A         ; Save the decimal-point-present flag.
        LD (DFLTFLAG),A        ; Save the inexact-literal flag.
        JR DMANTIS
; Exponents are bounded at 1000, beyond every decision boundary for 64-byte
; tokens. Saturation affects magnitude only; every remaining byte is checked.
DEXPSET: LD A,(DSEENFLG)         ; Recover the mantissa-digit-present flag.
        OR A
        JP Z,DSYNTAX           ; This grammar condition rejects the complete token.
        LD A,1
        LD (DFLTFLAG),A        ; Save the inexact-literal flag.
        LD A,(DREMAIN)          ; Recover the remaining token-byte count.
        OR A
        JP Z,DSYNTAX           ; This grammar condition rejects the complete token.
        LD HL,(DPTRNEXT)         ; Recover the next input address.
        LD A,(HL)
        CP '+'
        JR Z,DEXPSKIP
        CP '-'
        JR NZ,DEXPLOOP
        LD A,1
        LD (DEXPSIGN),A         ; Save the negative-exponent flag.
; Consume the optional exponent sign, without counting it as an exponent digit.
DEXPSKIP: CALL DGETBYTE            ; Consume one byte; the caller has checked that one remains.
; Check the next exponent digit even after its numeric magnitude saturates.
DEXPLOOP: LD A,(DREMAIN)          ; Recover the remaining token-byte count.
        OR A
        JR Z,DEXPEND
        CALL DGETBYTE            ; Consume one byte; the caller has checked that one remains.
        SUB '0'              ; Convert an ASCII digit candidate to its unsigned numeric value.
        CP 10                ; Only values zero through nine are decimal digits.
        JP NC,DSYNTAX          ; This grammar condition rejects the complete token.
        LD E,A
        LD D,0
        LD A,1
        LD (DEXPDIG),A        ; Save the exponent-digit-present flag.
        LD HL,(DEXPMAGN)         ; Recover the bounded exponent magnitude.
        LD A,H
        OR A
        JR NZ,DEXPSAT
        LD A,L
        CP 100
        JR NC,DEXPSAT
        ADD HL,HL           ; Ten times the bounded exponent plus this digit.
        LD B,H
        LD C,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,BC
        ADD HL,DE
        LD (DEXPMAGN),HL         ; Save the bounded exponent magnitude.
        JR DEXPLOOP
; Larger exponents cannot re-enter the finite decision range for a bounded token.
DEXPSAT:  LD HL,1000
        LD (DEXPMAGN),HL         ; Save the bounded exponent magnitude.
        JR DEXPLOOP
; An exponent marker and optional sign must have been followed by a digit.
DEXPEND:  LD A,(DEXPDIG)        ; Recover the exponent-digit-present flag.
        OR A
        JP Z,DSYNTAX           ; This grammar condition rejects the complete token.
; Grammar is complete. Only now choose integer range checking or float conversion.
DFINISH: LD A,(DSEENFLG)        ; Recover the mantissa-digit-present flag.
        OR A
        JP Z,DSYNTAX           ; This grammar condition rejects the complete token.
        LD A,(DFLTFLAG)        ; Recover the inexact-literal flag.
        OR A
        JP Z,DINTEGER
        LD A,(DSIGCNT)          ; Recover the significant digit count.
        OR A
        JP Z,DZERORES          ; Preserve a floating negative zero at any exponent.
        LD HL,(DEXPMAGN)         ; Recover the bounded exponent magnitude.
        LD A,(DEXPSIGN)         ; Recover the negative-exponent flag.
        OR A
        JR Z,DEXPPOS
        EX DE,HL
        LD HL,0
        OR A
        SBC HL,DE
; HL is the signed written exponent; subtract the number of fractional positions.
DEXPPOS:  LD A,(DFRACNUM)         ; Recover the fractional digit count.
        LD E,A
        LD D,0
        OR A
        SBC HL,DE           ; Effective decimal exponent includes the fraction.
        LD (DEXPSCAL),HL       ; Save the signed decimal scale.
        LD A,(DSIGCNT)          ; Recover the significant digit count.
        DEC A
        LD E,A
        ADD HL,DE           ; Decimal order = significant length - 1 + scale.
        LD DE,6
        OR A
        SBC HL,DE
        JP P,DINFRES         ; Order >= 6 is safely above half precision overflow.
        LD HL,(DEXPSCAL)       ; Recover the signed decimal scale.
        LD A,(DSIGCNT)          ; Recover the significant digit count.
        DEC A
        LD E,A
        LD D,0
        ADD HL,DE
        LD DE,9
        ADD HL,DE
        BIT 7,H             ; ADD HL does not set the sign flag.
        JP NZ,DZERORES         ; Order < -9 is below the first midpoint.
        LD A,1
        LD (DDENOMIN),A         ; Exact rational starts with denominator one.
        LD HL,(DEXPSCAL)       ; Recover the signed decimal scale.
        BIT 7,H
        JR NZ,DNEGSCAL
        LD A,L
        OR A
        JR Z,DNORMAL
        LD (DLOOPCNT),A        ; Save the phase-local loop count.
; A nonnegative decimal scale multiplies only the exact numerator.
DNUMTEN: LD HL,DNUMERAT          ; Select the numerator limbs for the wide operation.
        CALL DMULTEN            ; Multiply this exact integer by ten.
        LD HL,DLOOPCNT
        DEC (HL)
        JR NZ,DNUMTEN
        JR DNORMAL
; A negative decimal scale places its power of ten in the denominator.
DNEGSCAL: XOR A
        SUB L               ; Relevant negative scales fit in one byte (<=72).
        LD (DLOOPCNT),A        ; Save the phase-local loop count.
; Build that power of ten exactly; DLOOPCNT is the remaining multiplication count.
DDENTEN: LD HL,DDENOMIN          ; Select the denominator limbs for the wide operation.
        CALL DMULTEN            ; Multiply this exact integer by ten.
        LD HL,DLOOPCNT
        DEC (HL)
        JR NZ,DDENTEN
; Normalize X/Y. If X>=Y, raise Y until it first exceeds X, then halve Y
; once. Otherwise raise X until X>=Y or exponent -14 is reached. Stopping
; there gives a subnormal significand directly, rather than rounding twice.
DNORMAL:  CALL DCOMPARE            ; Compare exact numerator with divisor; carry means less.
        JR C,DNORMLO
; The numerator is at least the divisor. Raise the divisor by a binary power.
DNORMHI: LD HL,DDENOMIN           ; Select the denominator limbs for the wide operation.
        CALL DSHIFTL            ; Double the selected wide integer without rounding.
        LD HL,DBINEXP
        INC (HL)
        CALL DCOMPARE            ; Compare exact numerator with divisor; carry means less.
        JR NC,DNORMHI
        LD HL,DDENOMIN+39
        CALL DSHIFTR            ; Undo the divisor doubling that first exceeded the numerator.
        LD HL,DBINEXP
        DEC (HL)
        JR DQUOTSET
; The ratio is below one. Raise the numerator until normal or at the subnormal floor.
DNORMLO:  CALL DCOMPARE            ; Compare exact numerator with divisor; carry means less.
        JR NC,DQUOTSET
        LD A,(DBINEXP)         ; Recover the signed binary exponent.
        CP 242              ; Signed byte -14 is the subnormal exponent floor.
        JR Z,DQUOTSET
        LD HL,DNUMERAT           ; Select the numerator limbs for the wide operation.
        CALL DSHIFTL            ; Double the selected wide integer without rounding.
        LD HL,DBINEXP
        DEC (HL)
        JR DNORMLO
; With scale fixed, extract eleven quotient bits into a zero-initialized word.
DQUOTSET:  LD A,11
        LD (DLOOPCNT),A        ; Save the phase-local loop count.
; Each step shifts the collected bits, then tests whether the next bit is one.
DQUOTBIT: LD HL,(DQUOBITS)         ; Recover the collected significand bits.
        ADD HL,HL           ; Make room for the next exact quotient bit.
        LD (DQUOBITS),HL         ; Save the collected significand bits.
        CALL DCOMPARE            ; Compare exact numerator with divisor; carry means less.
        JR C,DQUOTDEC
        CALL DSUBVAL            ; Remove the divisor for the quotient bit just proved to be one.
        LD HL,(DQUOBITS)         ; Recover the collected significand bits.
        INC HL
        LD (DQUOBITS),HL         ; Save the collected significand bits.
; Both quotient-bit paths leave the exact remainder in DNUM.
DQUOTDEC: LD HL,DLOOPCNT
        DEC (HL)
        JR Z,DROUNDCK
        LD HL,DNUMERAT           ; Select the numerator limbs for the wide operation.
        CALL DSHIFTL           ; Bring the next fractional bit into comparison.
        JR DQUOTBIT
; All retained bits are known. The exact remainder still contains every discarded bit.
DROUNDCK: LD HL,DNUMERAT           ; Select the numerator limbs for the wide operation.
        CALL DSHIFTL           ; Compare twice the exact remainder with divisor.
        CALL DCOMPARE            ; Compare exact numerator with divisor; carry means less.
        JR C,DPACKRES
        JR NZ,DROUNDUP
        LD HL,(DQUOBITS)         ; Recover the collected significand bits.
        BIT 0,L             ; At an exact midpoint retain an even significand.
        JR Z,DPACKRES
; Round the significand upward; a carry into bit eleven is handled during packing.
DROUNDUP:    LD HL,(DQUOBITS)         ; Recover the collected significand bits.
        INC HL
        LD (DQUOBITS),HL         ; Save the collected significand bits.
; Combine scale and rounded significand, including subnormal promotion and overflow.
DPACKRES:  LD A,(DBINEXP)         ; Recover the signed binary exponent.
        ADD A,14            ; Exponent -14 contributes zero, also for subnormals.
        LD H,A
        LD L,0
        ADD HL,HL
        ADD HL,HL           ; Bias contribution is (binary exponent + 14)*1024.
        LD DE,(DQUOBITS)
        ADD HL,DE           ; A rounded carry naturally promotes the exponent.
        LD DE,7C00H
        OR A
        SBC HL,DE
        JR NC,DINFRES        ; Round-to-nearest overflow produces signed infinity.
        ADD HL,DE
        JR DSIGNRES
; Exact decimal integers never pass through floating point. High limbs must
; all be zero, then the low word must fit the sign-dependent signed16 limit.
DINTEGER: LD HL,DNUMERAT+2
        LD B,38
; Any nonzero limb above the low word proves this integer is outside signed16.
DINTSCAN:  LD A,(HL)
        OR A
        JR NZ,DINTRANG        ; The exact magnitude exceeds its permitted range.
        INC HL
        DJNZ DINTSCAN
        LD HL,(DNUMERAT)         ; Recover the exact numerator low word.
        LD A,(DNUMSIGN)          ; Recover the saved number sign bit.
        OR A
        JR NZ,DINTNEG
        BIT 7,H
        JR NZ,DINTRANG        ; The exact magnitude exceeds its permitted range.
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Negative integers may have magnitude 32768, one more than the positive maximum.
DINTNEG:  LD DE,8000H
        OR A
        SBC HL,DE
        JR C,DINTGOOD
        JR NZ,DINTRANG        ; The exact magnitude exceeds its permitted range.
; The magnitude fits. Form its two’s-complement payload, then clear success carry.
DINTGOOD: LD DE,(DNUMERAT)
        LD HL,0
        OR A
        SBC HL,DE
        LD A,3               ; Return the public exact-integer value tag.
        OR A
        RET
; Underflow and an all-zero mantissa share the signed floating-zero result.
DZERORES:  LD HL,0
        JR DSIGNRES
; Overflow and an explicit infinity spelling share the signed infinity result.
DINFRES: LD HL,7C00H
; Apply the saved sign to a nonnegative IEEE encoding and return floating tag zero.
DSIGNRES:  LD A,(DNUMSIGN)          ; Recover the saved number sign bit.
        OR H
        LD H,A
        XOR A               ; Floating tag zero and success carry clear.
        RET
; Reject malformed grammar without publishing a numeric value.
DSYNTAX:  LD A,128
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject a token length or input-address extent outside the supported bounds.
DCAPERR:   LD A,129
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; Reject an exact integer outside the public signed16 range.
DINTRANG: LD A,130
        SCF                  ; Mark this diagnostic as a failed conversion.
        RET
; DGETBYTE consumes a byte only after the caller has proved one remains.
DGETBYTE:   LD HL,(DPTRNEXT)         ; Recover the next input address.
        LD A,(HL)
        INC HL
        LD (DPTRNEXT),HL         ; Save the next input address.
        LD HL,DREMAIN
        DEC (HL)
        RET
; Compare the five remaining bytes with the chosen canonical special token.
DMATCH: LD B,5
; Compare all five bytes, stopping at the first difference; preserve its zero flag.
DMATCHLP: LD A,(DE)
        CP (HL)
        RET NZ
        INC DE
        INC HL
        DJNZ DMATCHLP
        RET
; Multiply a 40-byte little-endian integer at HL by ten. Each limb product
; is at most 2550+9. C carries the next decimal multiplication carry;
; DE holds widened addends and HL temporarily holds the limb product.
DMULTEN:   LD B,40
        LD C,0
; Widen one byte before multiplying, then store its low byte and retain carry in C.
DMULTLP: LD A,(HL)
        PUSH HL             ; HL becomes the widened limb product temporarily.
        LD L,A
        LD H,0
        ADD HL,HL
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD E,C
        LD D,0
        ADD HL,DE
        LD A,L
        LD C,H
        POP HL
        LD (HL),A
        INC HL
        DJNZ DMULTLP
        RET
; Wide shifts propagate each bit through carry; INC/DEC HL and DJNZ preserve it.
DSHIFTL:   LD B,40
        OR A                ; Start with a zero incoming low bit.
; Carry transfers the previous limb’s top bit into this limb’s low bit.
DSHFTLP: RL (HL)
        INC HL
        DJNZ DSHFTLP
        RET
DSHIFTR:   LD B,40
        OR A
; Carry transfers the previous limb’s low bit into this limb’s top bit.
DSHFTRP: RR (HL)
        DEC HL
        DJNZ DSHFTRP
        RET
; Compare numerator X with denominator Y, most-significant limb first.
; Carry means X<Y, zero means equality. No integer is modified.
DCOMPARE:   LD HL,DNUMERAT+39
        LD DE,DDENOMIN+39
        LD B,40
; The first unequal high limb decides the ordering of the complete integers.
DCMPLOOP: LD A,(DE)
        LD C,A
        LD A,(HL)
        CP C
        RET NZ
        DEC HL
        DEC DE
        DJNZ DCMPLOOP
        RET
; X := X-Y after comparison proved X>=Y. Borrow crosses every byte intact.
DSUBVAL:   LD HL,DNUMERAT           ; Select the numerator limbs for the wide operation.
        LD DE,DDENOMIN
        LD B,40
        OR A
; Subtract one denominator limb and the incoming borrow from the numerator limb.
DSUBLOOP: LD A,(DE)
        LD C,A
        LD A,(HL)
        SBC A,C
        LD (HL),A
        INC HL
        INC DE
        DJNZ DSUBLOOP
        RET
DINFSTR:  DB "inf.0"
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
