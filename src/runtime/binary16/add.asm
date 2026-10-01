; Binary16 addition, subtraction and special-value handling.
; Entry points: F16ADD, F16SUB and FADDCORE.
; Addition and subtraction share alignment, magnitude arithmetic and packing.
F16ADD:
    CALL FPREPARE              ; Save and validate both language operands
    RET C                   ; Return a type failure before arithmetic
    JP FADDCORE              ; Continue with the operands unchanged
F16SUB:
    CALL FPREPARE              ; Save and validate both language operands
    RET C                   ; Return a type failure before changing y
    LD HL,(FRIGHTVL)              ; Load the saved right payload
    LD A,H                  ; Fetch its sign-bearing byte
    XOR 80H                 ; Turn subtraction into addition of the opposite sign
    LD H,A                  ; Install the flipped sign
    LD (FRIGHTVL),HL              ; Save the altered right operand

; Handle NaNs, infinities and zeros before finite alignment.
FADDCORE:
    CALL FUNPBOTH           ; Decode both prepared operands
    LD A,(FLEFTCLS)          ; Read the left class
    CP 3                    ; Check for NaN
    JP Z,FMAKENAN               ; NaN propagates canonically
    LD A,(FRIGHTCL)          ; Read the right class
    CP 3                    ; Check for NaN
    JP Z,FMAKENAN               ; NaN propagates canonically
    LD A,(FLEFTCLS)          ; Read the left class again
    CP 2                    ; Check for infinity
    JP Z,FADDXINF           ; Resolve the two-infinity case separately
    LD A,(FRIGHTCL)          ; Read the right class
    CP 2                    ; Check for infinity
    JP Z,FRETRGHT              ; A finite left plus infinite right returns right
    LD A,(FLEFTCLS)          ; Read the left class
    OR A                    ; Check for zero
    JP Z,FADDZERO           ; Resolve the two-zero case separately
    LD A,(FRIGHTCL)          ; Read the right class
    OR A                    ; Check for zero
    JP Z,FRETLEFT              ; Adding zero leaves the nonzero left unchanged
    ; Place the larger exponent in x. Difference cannot overflow signed byte.
    LD A,(FRIGHTEX)            ; Fetch the right exponent
    LD B,A                  ; Keep it while loading the left exponent
    LD A,(FLEFTEXP)            ; Fetch the left exponent
    SUB B                   ; Compute the signed exponent difference
    JP P,FADDALGN            ; A nonnegative difference already has x first
    LD HL,(FLEFTSIG)          ; Load the left significand for exchange
    LD DE,(FRIGHTSI)          ; Load the right significand for exchange
    LD (FLEFTSIG),DE          ; Move the right significand into x
    LD (FRIGHTSI),HL          ; Move the left significand into y
    LD A,(FLEFTEXP)            ; Fetch the left exponent for exchange
    LD B,A                  ; Keep the old left exponent in B
    LD A,(FRIGHTEX)            ; Fetch the right exponent
    LD (FLEFTEXP),A            ; The larger exponent now belongs to x
    LD A,B                  ; Recover the old left exponent
    LD (FRIGHTEX),A            ; Move it into y
    LD A,(FLEFTSGN)           ; Fetch the left sign for exchange
    LD B,A                  ; Keep the old left sign in B
    LD A,(FRIGHTSG)           ; Fetch the right sign
    LD (FLEFTSGN),A           ; Move the right sign into x
    LD A,B                  ; Recover the old left sign
    LD (FRIGHTSG),A           ; Move it into y

; x now has the larger exponent. Each significand gains three low bits
; for guard, round and sticky information before y is aligned to x.
FADDALGN:
    LD A,(FLEFTEXP)            ; Load the common result exponent
    LD (FRESEXP),A             ; Initialize the packing exponent
    LD A,(FLEFTSGN)           ; Use x as the provisional result sign
    LD (FRESIGN),A             ; Save the packing sign
    LD HL,(FRIGHTSI)          ; Load the smaller-exponent significand
    ADD HL,HL               ; Reserve the first low rounding bit
    ADD HL,HL               ; Reserve the second low rounding bit
    ADD HL,HL               ; Reserve the third low rounding bit
    LD A,(FRIGHTEX)            ; Fetch the smaller exponent
    LD B,A                  ; Keep it in B for subtraction
    LD A,(FLEFTEXP)            ; Fetch the larger exponent
    SUB B                   ; Compute the nonnegative alignment distance
    LD B,A                  ; Pass the shift count in B
    CALL FJAMSHFT              ; Align y and retain every discarded one as sticky
    EX DE,HL                ; Keep the aligned y magnitude in DE
    LD HL,(FLEFTSIG)          ; Load the x significand
    ADD HL,HL               ; Reserve the first low rounding bit
    ADD HL,HL               ; Reserve the second low rounding bit
    ADD HL,HL               ; Reserve the third low rounding bit
    LD A,(FLEFTSGN)           ; Fetch x sign for comparison
    LD B,A                  ; Keep it while fetching y sign
    LD A,(FRIGHTSG)           ; Fetch y sign
    XOR B                   ; Zero means the signs agree
    JP NZ,FADDOPP           ; Opposite signs require a magnitude difference
    ADD HL,DE               ; Add aligned magnitudes with the common sign
    JP FPKNORM              ; Normalize and round the sum once

; For opposite signs, the subtraction borrow identifies the larger magnitude.
FADDOPP:
    OR A                    ; Clear carry so SBC subtracts only DE
    SBC HL,DE               ; Subtract the aligned y magnitude from x
    JP NC,FADDDIFF          ; No borrow means the provisional x sign is right
    CALL FNEGWORD              ; Make the negative difference an unsigned magnitude
    LD A,(FRIGHTSG)           ; Use y sign when y had the larger magnitude
    LD (FRESIGN),A             ; Replace the provisional result sign

; Exact cancellation is positive zero under round-to-nearest-even.
FADDDIFF:
    LD A,H                  ; Test the remaining magnitude
    OR L                    ; Include its low byte
    JP NZ,FPKNORM           ; A nonzero difference still needs normalization
    XOR A                   ; Select the positive sign for exact cancellation
    LD (FRESIGN),A             ; Save that zero sign
    JP FZEROSGN                ; Construct positive zero

; Equal-sign infinities survive; opposite-sign infinities produce NaN.
FADDXINF:
    LD A,(FRIGHTCL)          ; Inspect the right class
    CP 2                    ; Check whether the right operand is infinite too
    JP NZ,FRETLEFT             ; An infinite left plus finite right stays infinite
    LD A,(FLEFTSGN)           ; Fetch the left sign
    LD B,A                  ; Keep it for the sign comparison
    LD A,(FRIGHTSG)           ; Fetch the right sign
    XOR B                   ; Compare the two signs
    JP NZ,FMAKENAN              ; Opposite infinities have no numeric sum
    JP FRETLEFT                ; Return the original left infinity

; Two zeros yield negative zero only when both inputs are negative.
FADDZERO:
    LD A,(FRIGHTCL)          ; Inspect the right class
    OR A                    ; Check whether the right operand is zero too
    JP NZ,FRETRGHT             ; Zero plus nonzero returns the right operand
    LD A,(FLEFTSGN)           ; Fetch the left zero sign
    LD B,A                  ; Keep it for the sign intersection
    LD A,(FRIGHTSG)           ; Fetch the right zero sign
    AND B                   ; Keep a negative sign only if both have one
    LD (FRESIGN),A             ; Save the resulting zero sign
    JP FZEROSGN                ; Construct that signed zero

; Return the prepared left encoding without repacking it.
FRETLEFT:
    LD HL,(FLEFTVAL)              ; Recover the saved left payload
    JP F16OKAY                  ; Return it with success status

; Return the prepared right encoding; subtraction may have flipped its sign.
FRETRGHT:
    LD HL,(FRIGHTVL)              ; Recover the saved right payload
    JP F16OKAY                  ; Return it with success status
