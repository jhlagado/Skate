; Decimal token grammar, exact rational normalisation and binary16 packing.
; Entry point: DPARSE.
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
