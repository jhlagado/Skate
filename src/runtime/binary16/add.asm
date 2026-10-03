; Binary16 addition, subtraction and special-value handling.
; Entry points: F16_ADD, F16_SUB and F16_SUM.
; Addition and subtraction share alignment, magnitude arithmetic and packing.
F16_ADD:
    CALL F16_LOAD              ; Save and validate both language operands
    RET C                   ; Return a type failure before arithmetic
    JP F16_SUM               ; Continue with the operands unchanged
F16_SUB:
    CALL F16_LOAD              ; Save and validate both language operands
    RET C                   ; Return a type failure before changing y
    LD HL,(F16_Y)                 ; Load the saved right payload
    LD A,H                  ; Fetch its sign-bearing byte
    XOR 80H                 ; Turn subtraction into addition of the opposite sign
    LD H,A                  ; Install the flipped sign
    LD (F16_Y),HL                 ; Save the altered right operand

; Handle NaNs, infinities and zeros before finite alignment.
F16_SUM:
    CALL F16_BOTH           ; Decode both prepared operands
    LD A,(F16_XCAT)          ; Read the left class
    CP 3                    ; Check for NaN
    JP Z,F16_NAN                ; NaN propagates canonically
    LD A,(F16_YCAT)          ; Read the right class
    CP 3                    ; Check for NaN
    JP Z,F16_NAN                ; NaN propagates canonically
    LD A,(F16_XCAT)          ; Read the left class again
    CP 2                    ; Check for infinity
    JP Z,.INFINITE          ; Resolve the two-infinity case separately
    LD A,(F16_YCAT)          ; Read the right class
    CP 2                    ; Check for infinity
    JP Z,.RET_Y                ; A finite left plus infinite right returns right
    LD A,(F16_XCAT)          ; Read the left class
    OR A                    ; Check for zero
    JP Z,.ZERO              ; Resolve the two-zero case separately
    LD A,(F16_YCAT)          ; Read the right class
    OR A                    ; Check for zero
    JP Z,.RET_X                ; Adding zero leaves the nonzero left unchanged
    ; Place the larger exponent in x. Difference cannot overflow signed byte.
    LD A,(F16_YEXP)            ; Fetch the right exponent
    LD B,A                  ; Keep it while loading the left exponent
    LD A,(F16_XEXP)            ; Fetch the left exponent
    SUB B                   ; Compute the signed exponent difference
    JP P,.ALIGN              ; A nonnegative difference already has x first
    LD HL,(F16_XMAN)          ; Load the left significand for exchange
    LD DE,(F16_YMAN)          ; Load the right significand for exchange
    LD (F16_XMAN),DE          ; Move the right significand into x
    LD (F16_YMAN),HL          ; Move the left significand into y
    LD A,(F16_XEXP)            ; Fetch the left exponent for exchange
    LD B,A                  ; Keep the old left exponent in B
    LD A,(F16_YEXP)            ; Fetch the right exponent
    LD (F16_XEXP),A            ; The larger exponent now belongs to x
    LD A,B                  ; Recover the old left exponent
    LD (F16_YEXP),A            ; Move it into y
    LD A,(F16_XNEG)           ; Fetch the left sign for exchange
    LD B,A                  ; Keep the old left sign in B
    LD A,(F16_YNEG)           ; Fetch the right sign
    LD (F16_XNEG),A           ; Move the right sign into x
    LD A,B                  ; Recover the old left sign
    LD (F16_YNEG),A           ; Move it into y

; x now has the larger exponent. Each significand gains three low bits
; for guard, round and sticky information before y is aligned to x.
.ALIGN:
    LD A,(F16_XEXP)            ; Load the common result exponent
    LD (F16_EXP),A             ; Initialize the packing exponent
    LD A,(F16_XNEG)           ; Use x as the provisional result sign
    LD (F16_SIGN),A            ; Save the packing sign
    LD HL,(F16_YMAN)          ; Load the smaller-exponent significand
    ADD HL,HL               ; Reserve the first low rounding bit
    ADD HL,HL               ; Reserve the second low rounding bit
    ADD HL,HL               ; Reserve the third low rounding bit
    LD A,(F16_YEXP)            ; Fetch the smaller exponent
    LD B,A                  ; Keep it in B for subtraction
    LD A,(F16_XEXP)            ; Fetch the larger exponent
    SUB B                   ; Compute the nonnegative alignment distance
    LD B,A                  ; Pass the shift count in B
    CALL F16_SHR               ; Align y and retain every discarded one as sticky
    EX DE,HL                ; Keep the aligned y magnitude in DE
    LD HL,(F16_XMAN)          ; Load the x significand
    ADD HL,HL               ; Reserve the first low rounding bit
    ADD HL,HL               ; Reserve the second low rounding bit
    ADD HL,HL               ; Reserve the third low rounding bit
    LD A,(F16_XNEG)           ; Fetch x sign for comparison
    LD B,A                  ; Keep it while fetching y sign
    LD A,(F16_YNEG)           ; Fetch y sign
    XOR B                   ; Zero means the signs agree
    JP NZ,.OPPOSITE         ; Opposite signs require a magnitude difference
    ADD HL,DE               ; Add aligned magnitudes with the common sign
    JP F16_PACK             ; Normalize and round the sum once

; For opposite signs, the subtraction borrow identifies the larger magnitude.
.OPPOSITE:
    OR A                    ; Clear carry so SBC subtracts only DE
    SBC HL,DE               ; Subtract the aligned y magnitude from x
    JP NC,.CANCEL           ; No borrow means the provisional x sign is right
    CALL F16_FLIP              ; Make the negative difference an unsigned magnitude
    LD A,(F16_YNEG)           ; Use y sign when y had the larger magnitude
    LD (F16_SIGN),A            ; Replace the provisional result sign

; Exact cancellation is positive zero under round-to-nearest-even.
.CANCEL:
    LD A,H                  ; Test the remaining magnitude
    OR L                    ; Include its low byte
    JP NZ,F16_PACK          ; A nonzero difference still needs normalization
    XOR A                   ; Select the positive sign for exact cancellation
    LD (F16_SIGN),A            ; Save that zero sign
    JP F16_ZERO                ; Construct positive zero

; Equal-sign infinities survive; opposite-sign infinities produce NaN.
.INFINITE:
    LD A,(F16_YCAT)          ; Inspect the right class
    CP 2                    ; Check whether the right operand is infinite too
    JP NZ,.RET_X               ; An infinite left plus finite right stays infinite
    LD A,(F16_XNEG)           ; Fetch the left sign
    LD B,A                  ; Keep it for the sign comparison
    LD A,(F16_YNEG)           ; Fetch the right sign
    XOR B                   ; Compare the two signs
    JP NZ,F16_NAN               ; Opposite infinities have no numeric sum
    JP .RET_X                  ; Return the original left infinity

; Two zeros yield negative zero only when both inputs are negative.
.ZERO:
    LD A,(F16_YCAT)          ; Inspect the right class
    OR A                    ; Check whether the right operand is zero too
    JP NZ,.RET_Y               ; Zero plus nonzero returns the right operand
    LD A,(F16_XNEG)           ; Fetch the left zero sign
    LD B,A                  ; Keep it for the sign intersection
    LD A,(F16_YNEG)           ; Fetch the right zero sign
    AND B                   ; Keep a negative sign only if both have one
    LD (F16_SIGN),A            ; Save the resulting zero sign
    JP F16_ZERO                ; Construct that signed zero

; Return the prepared left encoding without repacking it.
.RET_X:
    LD HL,(F16_X)                 ; Recover the saved left payload
    JP F16_OK                   ; Return it with success status

; Return the prepared right encoding; subtraction may have flipped its sign.
.RET_Y:
    LD HL,(F16_Y)                 ; Recover the saved right payload
    JP F16_OK                   ; Return it with success status
