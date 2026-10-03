; Decimal token grammar, exact rational normalisation and binary16 packing.
; Entry point: DEC_READ.
DEC_READ: LD A,B            ; A byte count above 255 exceeds the token bound.
        OR A
        JP NZ,DEC_LONG
        LD A,C
        OR A
        JP Z,DEC_BAD           ; This grammar condition rejects the complete token.
        CP 65
        JP NC,DEC_LONG
        PUSH HL             ; Save the input while clearing private state.
        ADD HL,BC           ; Reject an extent that wraps beyond address 65536.
        JR NC,.FITS
        LD A,H
        OR L                ; A carry with zero sum is the exact legal end.
        JR Z,.FITS
        POP HL
        JP DEC_LONG
; The whole input extent is valid. Clear all per-call state before parsing.
.FITS:  POP HL
        PUSH HL
        PUSH BC
        LD HL,DEC_WORK
        LD DE,DEC_WORK+1
        LD BC,100           ; 101 workspace bytes; census test guards this size.
        LD (HL),0
        LDIR                ; Every call starts with zero limbs and flags.
        POP BC
        POP HL
        LD (DEC_SRCP),HL         ; Save the next input address.
        LD A,C
        LD (DEC_LEFT),A         ; Save the remaining token-byte count.
        LD A,(HL)
        CP '+'
        JR Z,.SIGNED
        CP '-'
        JR NZ,.SPECIAL
        LD A,128
        LD (DEC_NEG),A          ; Final IEEE sign bit, or integer negation request.
; Consume either leading sign; the negative path already saved its sign bit.
.SIGNED:  LD A,1
        LD (DEC_LEAD),A      ; Special spellings require an explicit sign.
        CALL DEC_BYTE            ; Consume one byte; the caller has checked that one remains.
; Recognize only the three signed, five-byte special tails before mantissa parsing.
.SPECIAL:  LD A,(DEC_LEFT)         ; Recover the remaining token-byte count.
        CP 5
        JR NZ,.MANTISSA
        LD A,(DEC_LEAD)       ; Recover the explicit-sign flag.
        OR A
        JR Z,.MANTISSA
        LD HL,(DEC_SRCP)         ; Recover the next input address.
        LD A,(HL)
        CP 'i'
        JR Z,.INF
        CP 'n'
        JR NZ,.MANTISSA
        LD A,(DEC_NEG)           ; Recover the saved number sign bit.
        OR A
        JP NZ,DEC_BAD         ; Only +nan.0 is a valid canonical NaN spelling.
        LD DE,DEC_NAN0
        CALL DEC_SAME        ; Compare the remaining spelling with the selected constant.
        JP NZ,DEC_BAD          ; This grammar condition rejects the complete token.
        LD HL,7E00H
        XOR A
        RET
; Validate the entire infinity tail before returning its signed encoding.
.INF:   LD DE,DEC_INF0
        CALL DEC_SAME        ; Compare the remaining spelling with the selected constant.
        JP NZ,DEC_BAD          ; This grammar condition rejects the complete token.
        JP DEC_INF
; Read the mantissa, retaining every digit exactly, including those beyond
; binary16 precision. DEC_FRAC counts digits after the point; DEC_LEN ignores only
; leading zeroes and later gives the decimal order without wide arithmetic.
.MANTISSA:  LD A,(DEC_LEFT)       ; Recover the remaining token-byte count.
        OR A
        JP Z,.FINISH
        CALL DEC_BYTE            ; Consume one byte; the caller has checked that one remains.
        CP '.'
        JR Z,.POINT
        CP 'e'
        JR Z,.EXPONENT
        CP 'E'
        JR Z,.EXPONENT
        SUB '0'              ; Convert an ASCII digit candidate to its unsigned numeric value.
        CP 10                ; Only values zero through nine are decimal digits.
        JP NC,DEC_BAD          ; This grammar condition rejects the complete token.
        LD (DEC_DIG),A        ; Save the current decimal digit.
        LD A,1
        LD (DEC_SEEN),A         ; Save the mantissa-digit-present flag.
        LD A,(DEC_DIG)        ; Recover the current decimal digit.
        OR A
        JR NZ,.SIG_ADD
        LD A,(DEC_LEN)          ; Recover the significant digit count.
        OR A
        JR Z,.FRACTION
; Once a nonzero digit occurs, every later digit contributes to decimal order.
.SIG_ADD: LD HL,DEC_LEN
        INC (HL)
; Count fractional positions even when their digits are leading zeroes.
.FRACTION:   LD A,(DEC_DOT)        ; Recover the decimal-point-present flag.
        OR A
        JR Z,.DIGIT
        LD HL,DEC_FRAC
        INC (HL)
; Accumulate this digit without losing low bits needed at a rounding midpoint.
.DIGIT:   LD HL,DEC_NUM            ; Select the numerator limbs for the wide operation.
        CALL DEC_MUL           ; Numerator = previous digits times ten.
        LD A,(DEC_DIG)        ; Recover the current decimal digit.
        LD HL,DEC_NUM            ; Select the numerator limbs for the wide operation.
        ADD A,(HL)
        LD (HL),A
        JR NC,.MANTISSA
        LD B,39
; A low-limb digit addition overflowed; increment successive higher limbs.
.CARRY: INC HL
        INC (HL)            ; Propagate decimal digit addition through limbs.
        JR NZ,.MANTISSA
        DJNZ .CARRY
        JR .MANTISSA
; Permit one decimal point, and remember that this is an inexact literal.
.POINT:   LD A,(DEC_DOT)            ; Recover the decimal-point-present flag.
        OR A
        JP NZ,DEC_BAD          ; This grammar condition rejects the complete token.
        INC A
        LD (DEC_DOT),A          ; Save the decimal-point-present flag.
        LD (DEC_FLT),A         ; Save the inexact-literal flag.
        JR .MANTISSA
; Exponents are bounded at 1000, beyond every decision boundary for 64-byte
; tokens. Saturation affects magnitude only; every remaining byte is checked.
.EXPONENT: LD A,(DEC_SEEN)       ; Recover the mantissa-digit-present flag.
        OR A
        JP Z,DEC_BAD           ; This grammar condition rejects the complete token.
        LD A,1
        LD (DEC_FLT),A         ; Save the inexact-literal flag.
        LD A,(DEC_LEFT)         ; Recover the remaining token-byte count.
        OR A
        JP Z,DEC_BAD           ; This grammar condition rejects the complete token.
        LD HL,(DEC_SRCP)         ; Recover the next input address.
        LD A,(HL)
        CP '+'
        JR Z,.EXP_SIGN
        CP '-'
        JR NZ,.EXP_LOOP
        LD A,1
        LD (DEC_ENEG),A         ; Save the negative-exponent flag.
; Consume the optional exponent sign, without counting it as an exponent digit.
.EXP_SIGN: CALL DEC_BYTE           ; Consume one byte; the caller has checked that one remains.
; Check the next exponent digit even after its numeric magnitude saturates.
.EXP_LOOP: LD A,(DEC_LEFT)        ; Recover the remaining token-byte count.
        OR A
        JR Z,.EXP_END
        CALL DEC_BYTE            ; Consume one byte; the caller has checked that one remains.
        SUB '0'              ; Convert an ASCII digit candidate to its unsigned numeric value.
        CP 10                ; Only values zero through nine are decimal digits.
        JP NC,DEC_BAD          ; This grammar condition rejects the complete token.
        LD E,A
        LD D,0
        LD A,1
        LD (DEC_EDIG),A       ; Save the exponent-digit-present flag.
        LD HL,(DEC_EXP)          ; Recover the bounded exponent magnitude.
        LD A,H
        OR A
        JR NZ,.SATURATE
        LD A,L
        CP 100
        JR NC,.SATURATE
        ADD HL,HL           ; Ten times the bounded exponent plus this digit.
        LD B,H
        LD C,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,BC
        ADD HL,DE
        LD (DEC_EXP),HL          ; Save the bounded exponent magnitude.
        JR .EXP_LOOP
; Larger exponents cannot re-enter the finite decision range for a bounded token.
.SATURATE:  LD HL,1000
        LD (DEC_EXP),HL          ; Save the bounded exponent magnitude.
        JR .EXP_LOOP
; An exponent marker and optional sign must have been followed by a digit.
.EXP_END:  LD A,(DEC_EDIG)      ; Recover the exponent-digit-present flag.
        OR A
        JP Z,DEC_BAD           ; This grammar condition rejects the complete token.
; Grammar is complete. Only now choose integer range checking or float conversion.
.FINISH: LD A,(DEC_SEEN)        ; Recover the mantissa-digit-present flag.
        OR A
        JP Z,DEC_BAD           ; This grammar condition rejects the complete token.
        LD A,(DEC_FLT)         ; Recover the inexact-literal flag.
        OR A
        JP Z,DEC_INT
        LD A,(DEC_LEN)          ; Recover the significant digit count.
        OR A
        JP Z,DEC_ZERO          ; Preserve a floating negative zero at any exponent.
        LD HL,(DEC_EXP)          ; Recover the bounded exponent magnitude.
        LD A,(DEC_ENEG)         ; Recover the negative-exponent flag.
        OR A
        JR Z,.SCALE
        EX DE,HL
        LD HL,0
        OR A
        SBC HL,DE
; HL is the signed written exponent; subtract the number of fractional positions.
.SCALE:  LD A,(DEC_FRAC)          ; Recover the fractional digit count.
        LD E,A
        LD D,0
        OR A
        SBC HL,DE           ; Effective decimal exponent includes the fraction.
        LD (DEC_TENS),HL       ; Save the signed decimal scale.
        LD A,(DEC_LEN)          ; Recover the significant digit count.
        DEC A
        LD E,A
        ADD HL,DE           ; Decimal order = significant length - 1 + scale.
        LD DE,6
        OR A
        SBC HL,DE
        JP P,DEC_INF         ; Order >= 6 is safely above half precision overflow.
        LD HL,(DEC_TENS)       ; Recover the signed decimal scale.
        LD A,(DEC_LEN)          ; Recover the significant digit count.
        DEC A
        LD E,A
        LD D,0
        ADD HL,DE
        LD DE,9
        ADD HL,DE
        BIT 7,H             ; ADD HL does not set the sign flag.
        JP NZ,DEC_ZERO         ; Order < -9 is below the first midpoint.
        LD A,1
        LD (DEC_DEN),A          ; Exact rational starts with denominator one.
        LD HL,(DEC_TENS)       ; Recover the signed decimal scale.
        BIT 7,H
        JR NZ,.NEGATIVE
        LD A,L
        OR A
        JR Z,.NORMAL
        LD (DEC_CNT),A         ; Save the phase-local loop count.
; A nonnegative decimal scale multiplies only the exact numerator.
.NUM_TEN: LD HL,DEC_NUM          ; Select the numerator limbs for the wide operation.
        CALL DEC_MUL            ; Multiply this exact integer by ten.
        LD HL,DEC_CNT
        DEC (HL)
        JR NZ,.NUM_TEN
        JR .NORMAL
; A negative decimal scale places its power of ten in the denominator.
.NEGATIVE: XOR A
        SUB L               ; Relevant negative scales fit in one byte (<=72).
        LD (DEC_CNT),A         ; Save the phase-local loop count.
; Build that power of ten exactly; DEC_CNT is the remaining multiplication count.
.DEN_TEN: LD HL,DEC_DEN          ; Select the denominator limbs for the wide operation.
        CALL DEC_MUL            ; Multiply this exact integer by ten.
        LD HL,DEC_CNT
        DEC (HL)
        JR NZ,.DEN_TEN
; Normalize X/Y. If X>=Y, raise Y until it first exceeds X, then halve Y
; once. Otherwise raise X until X>=Y or exponent -14 is reached. Stopping
; there gives a subnormal significand directly, rather than rounding twice.
.NORMAL:  CALL DEC_CMP             ; Compare exact numerator with divisor; carry means less.
        JR C,.NORM_LO
; The numerator is at least the divisor. Raise the divisor by a binary power.
.NORM_HI: LD HL,DEC_DEN           ; Select the denominator limbs for the wide operation.
        CALL DEC_SHL            ; Double the selected wide integer without rounding.
        LD HL,DEC_EXP2
        INC (HL)
        CALL DEC_CMP             ; Compare exact numerator with divisor; carry means less.
        JR NC,.NORM_HI
        LD HL,DEC_DEN+39
        CALL DEC_SHR            ; Undo the divisor doubling that first exceeded the numerator.
        LD HL,DEC_EXP2
        DEC (HL)
        JR .QUOTIENT
; The ratio is below one. Raise the numerator until normal or at the subnormal floor.
.NORM_LO:  CALL DEC_CMP            ; Compare exact numerator with divisor; carry means less.
        JR NC,.QUOTIENT
        LD A,(DEC_EXP2)        ; Recover the signed binary exponent.
        CP 242              ; Signed byte -14 is the subnormal exponent floor.
        JR Z,.QUOTIENT
        LD HL,DEC_NUM            ; Select the numerator limbs for the wide operation.
        CALL DEC_SHL            ; Double the selected wide integer without rounding.
        LD HL,DEC_EXP2
        DEC (HL)
        JR .NORM_LO
; With scale fixed, extract eleven quotient bits into a zero-initialized word.
.QUOTIENT:  LD A,11
        LD (DEC_CNT),A         ; Save the phase-local loop count.
; Each step shifts the collected bits, then tests whether the next bit is one.
.QUO_BIT: LD HL,(DEC_BITS)         ; Recover the collected significand bits.
        ADD HL,HL           ; Make room for the next exact quotient bit.
        LD (DEC_BITS),HL         ; Save the collected significand bits.
        CALL DEC_CMP             ; Compare exact numerator with divisor; carry means less.
        JR C,.QUO_NEXT
        CALL DEC_SUB            ; Remove the divisor for the quotient bit just proved to be one.
        LD HL,(DEC_BITS)         ; Recover the collected significand bits.
        INC HL
        LD (DEC_BITS),HL         ; Save the collected significand bits.
; Both quotient-bit paths leave the exact remainder in DNUM.
.QUO_NEXT: LD HL,DEC_CNT
        DEC (HL)
        JR Z,.ROUND
        LD HL,DEC_NUM            ; Select the numerator limbs for the wide operation.
        CALL DEC_SHL           ; Bring the next fractional bit into comparison.
        JR .QUO_BIT
; All retained bits are known. The exact remainder still contains every discarded bit.
.ROUND: LD HL,DEC_NUM              ; Select the numerator limbs for the wide operation.
        CALL DEC_SHL           ; Compare twice the exact remainder with divisor.
        CALL DEC_CMP             ; Compare exact numerator with divisor; carry means less.
        JR C,.PACK
        JR NZ,.ROUND_UP
        LD HL,(DEC_BITS)         ; Recover the collected significand bits.
        BIT 0,L             ; At an exact midpoint retain an even significand.
        JR Z,.PACK
; Round the significand upward; a carry into bit eleven is handled during packing.
.ROUND_UP:    LD HL,(DEC_BITS)        ; Recover the collected significand bits.
        INC HL
        LD (DEC_BITS),HL         ; Save the collected significand bits.
; Combine scale and rounded significand, including subnormal promotion and overflow.
.PACK:  LD A,(DEC_EXP2)           ; Recover the signed binary exponent.
        ADD A,14            ; Exponent -14 contributes zero, also for subnormals.
        LD H,A
        LD L,0
        ADD HL,HL
        ADD HL,HL           ; Bias contribution is (binary exponent + 14)*1024.
        LD DE,(DEC_BITS)
        ADD HL,DE           ; A rounded carry naturally promotes the exponent.
        LD DE,7C00H
        OR A
        SBC HL,DE
        JR NC,DEC_INF        ; Round-to-nearest overflow produces signed infinity.
        ADD HL,DE
        JR DEC_SIGN
