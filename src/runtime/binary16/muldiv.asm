; Binary16 multiplication and division.
; Entry points: F16_MUL and F16_DIV.
; Multiply two 11-bit significands exactly into a 22-bit product.
; A three-byte accumulator retains every product bit until final reduction.
F16_MUL:
    CALL F16_LOAD              ; Save and validate both language operands
    RET C                   ; Propagate a type failure
    CALL F16_BOTH           ; Decode both magnitudes
    CALL F16_XOR            ; Compute the product sign by XOR
    LD A,(F16_XCAT)          ; Inspect the left class
    CP 3                    ; Check for NaN
    JP Z,F16_NAN                ; Propagate canonical NaN
    LD A,(F16_YCAT)          ; Inspect the right class
    CP 3                    ; Check for NaN
    JP Z,F16_NAN                ; Propagate canonical NaN
    LD A,(F16_XCAT)          ; Inspect the left class
    OR A                    ; Check for zero
    JP Z,.X_ZERO            ; Resolve zero times infinity separately
    CP 2                    ; Check for infinity
    JP Z,.X_INF             ; Resolve infinity times zero separately
    LD A,(F16_YCAT)          ; Inspect the right class
    OR A                    ; Check for zero
    JP Z,F16_ZERO              ; Finite nonzero times zero is signed zero
    CP 2                    ; Check for infinity
    JP Z,F16_INF                ; Finite nonzero times infinity is signed infinity
    LD A,(F16_YEXP)            ; Fetch the right exponent
    LD B,A                  ; Keep it while fetching the left exponent
    LD A,(F16_XEXP)            ; Fetch the left exponent
    ADD A,B                 ; Add the two biased exponents
    SUB 15                  ; Remove one copy of the binary16 bias
    LD (F16_EXP),A             ; Save the result exponent
    LD HL,(F16_XMAN)          ; Load the left significand
    LD (F16_TERM),HL          ; Initialize the low word of the shifting multiplicand
    XOR A                   ; Prepare a zero high byte
    LD (F16_THI),A           ; Clear the multiplicand extension
    LD (F16_PHI),A           ; Clear the product extension
    LD HL,0                 ; Prepare a zero product low word
    LD (F16_PROD),HL           ; Clear the product accumulator
    LD HL,(F16_YMAN)          ; Load the right significand
    LD (F16_BITS),HL           ; Initialize the bit-at-a-time multiplier
    LD B,11                 ; Process all eleven significand bits

; Each multiplier low bit selects an addition of the current multiplicand.
; The accumulator and multiplicand have a low word and a separate high byte.
.LOOP:
    LD HL,(F16_BITS)           ; Load the remaining multiplier
    SRL H                   ; Shift its high byte toward the low byte
    RR L                    ; Carry now holds the multiplier bit to consume
    LD (F16_BITS),HL           ; Save the shortened multiplier; LD preserves carry
    JP NC,.SHIFT            ; A zero multiplier bit contributes no product term
    LD HL,(F16_PROD)           ; Load the partial product low word
    LD DE,(F16_TERM)          ; Load the current multiplicand low word
    ADD HL,DE               ; Add the selected low-word contribution
    LD (F16_PROD),HL           ; Save it without disturbing its carry
    LD A,(F16_THI)           ; Fetch the multiplicand extension
    LD C,A                  ; Keep it while fetching the product extension
    LD A,(F16_PHI)           ; Fetch the product extension
    ADC A,C                 ; Include the carry from the low-word addition
    LD (F16_PHI),A           ; Save the new product extension

; Advance the multiplicand even when the current multiplier bit was zero.
.SHIFT:
    LD HL,(F16_TERM)          ; Load the multiplicand low word
    ADD HL,HL               ; Double it; carry is the outgoing bit 15
    LD (F16_TERM),HL          ; Save the low word without changing carry
    LD A,(F16_THI)           ; Fetch the multiplicand extension
    RLA                     ; Extend the same shift through its high byte
    LD (F16_THI),A           ; Save the shifted extension
    DJNZ .LOOP                ; Repeat for the remaining multiplier bits
    LD A,(F16_PHI)           ; Fetch the completed product high byte
    LD HL,(F16_PROD)           ; Fetch the completed product low word
    LD B,7                  ; Normally reduce bit 20 to guarded leading bit 13
    BIT 5,A                 ; Test for a product with leading bit 21
    JP Z,.REDUCE            ; A leading bit 20 needs only seven shifts
    INC B                   ; A leading bit 21 needs eight shifts
    LD C,A                  ; Preserve the product extension across exponent work
    LD A,(F16_EXP)             ; Fetch the result exponent
    INC A                   ; Account for the extra normalization shift
    LD (F16_EXP),A             ; Save the adjusted exponent
    LD A,C                  ; Restore the product extension

; Reduce the three-byte product to HL with three rounding bits.
; Every discarded one is ORed into the sticky bit, including on later shifts.
.REDUCE:
    SRL A                   ; Shift the product extension toward H
    RR H                    ; Carry the extension low bit into H
    RR L                    ; Carry H low bit into L; carry now holds discarded data
    JP NC,.NEXT             ; A discarded zero adds no sticky information
    SET 0,L                 ; Retain a discarded one in the sticky bit

; The reduced product enters the same final packer as addition.
.NEXT:
    DJNZ .REDUCE            ; Continue until all seven or eight shifts are done
    JP F16_PACK             ; Normalize and round the guarded product

; A zero left operand has already passed the NaN checks.
.X_ZERO:
    LD A,(F16_YCAT)          ; Inspect the right class
    CP 2                    ; Check for infinity
    JP Z,F16_NAN                ; Zero times infinity is NaN
    JP F16_ZERO                ; Every other right class gives signed zero

; An infinite left operand has already passed the NaN checks.
.X_INF:
    LD A,(F16_YCAT)          ; Inspect the right class
    OR A                    ; Check for zero
    JP Z,F16_NAN                ; Infinity times zero is NaN
    JP F16_INF                  ; Every other right class gives signed infinity

; Multiplication and division use the XOR of the two sign bits.
F16_XOR:
    LD A,(F16_XNEG)           ; Fetch the left sign
    LD B,A                  ; Keep it while loading the right sign
    LD A,(F16_YNEG)           ; Fetch the right sign
    XOR B                   ; Negative exactly when the signs differ
    LD (F16_SIGN),A            ; Save the sign used by all result constructors
    RET                     ; Return to the selected arithmetic operation

; Divide normalized significands with fourteen restoring iterations.
; The quotient has eleven significand bits plus guard, round and sticky bits.
F16_DIV:
    CALL F16_LOAD              ; Save and validate both language operands
    RET C                   ; Propagate a type failure
    CALL F16_BOTH           ; Decode both magnitudes
    CALL F16_XOR            ; Compute the quotient sign by XOR
    LD A,(F16_XCAT)          ; Inspect the left class
    CP 3                    ; Check for NaN
    JP Z,F16_NAN                ; Propagate canonical NaN
    LD A,(F16_YCAT)          ; Inspect the right class
    CP 3                    ; Check for NaN
    JP Z,F16_NAN                ; Propagate canonical NaN
    LD A,(F16_XCAT)          ; Inspect the numerator class
    OR A                    ; Check for zero
    JP Z,.X_ZERO            ; Resolve zero divided by zero separately
    CP 2                    ; Check for infinity
    JP Z,.X_INF             ; Resolve infinity divided by infinity separately
    LD A,(F16_YCAT)          ; Inspect the denominator class
    OR A                    ; Check for zero
    JP Z,F16_INF                ; Finite nonzero divided by zero is signed infinity
    CP 2                    ; Check for infinity
    JP Z,F16_ZERO              ; Finite divided by infinity is signed zero
    LD A,(F16_YEXP)            ; Fetch the denominator exponent
    LD B,A                  ; Keep it for subtraction
    LD A,(F16_XEXP)            ; Fetch the numerator exponent
    SUB B                   ; Subtract the denominator exponent
    ADD A,15                ; Restore one copy of the exponent bias
    LD (F16_EXP),A             ; Save the quotient exponent
    LD HL,(F16_XMAN)          ; Load the numerator significand
    LD DE,(F16_YMAN)          ; Load the denominator significand
    OR A                    ; Clear carry before the trial magnitude comparison
    SBC HL,DE               ; Compare numerator against denominator
    JP C,.SCALE             ; A smaller numerator needs one scaling step
    ADD HL,DE               ; Undo the trial subtraction
    JP .SETUP               ; The ratio already lies in [1,2)

; A ratio below one is doubled so its first quotient bit is one.
.SCALE:
    ADD HL,DE               ; Restore the numerator after the borrowed subtraction
    ADD HL,HL               ; Double it so the ratio lies in [1,2)
    LD A,(F16_EXP)             ; Fetch the quotient exponent
    DEC A                   ; Compensate for doubling the numerator
    LD (F16_EXP),A             ; Save the adjusted exponent

; HL is the trial remainder, DE is the divisor; quotient lives in scratch.
.SETUP:
    LD BC,0                 ; Prepare an empty quotient
    LD (F16_QUOT),BC           ; Clear the quotient word
    LD B,14                 ; Generate fourteen quotient bits

; Each iteration appends one quotient bit after a trial subtraction.
.LOOP:
    PUSH HL                 ; Preserve the current remainder while updating quotient
    LD HL,(F16_QUOT)           ; Fetch the quotient assembled so far
    ADD HL,HL               ; Make room for the next quotient bit
    LD (F16_QUOT),HL           ; Save the shifted quotient
    POP HL                  ; Restore the remainder
    OR A                    ; Clear carry for a fresh trial subtraction
    SBC HL,DE               ; Try removing one divisor from the remainder
    JP C,.ZERO_BIT          ; Borrow means this quotient bit is zero
    PUSH HL                 ; Preserve the reduced remainder
    LD HL,(F16_QUOT)           ; Fetch the quotient with its new low bit clear
    INC HL                  ; Set the current quotient bit to one
    LD (F16_QUOT),HL           ; Save the extended quotient
    POP HL                  ; Restore the reduced remainder
    JP .NEXT                ; Continue with the accepted subtraction

; A failed subtraction contributes a zero quotient bit.
.ZERO_BIT:
    ADD HL,DE               ; Restore the remainder to its pre-subtraction value

; Scale the remainder for the next bit, except after the last iteration.
.NEXT:
    DEC B                   ; Count the quotient bit just generated
    JP Z,.DONE                ; Fourteen bits are sufficient for final rounding
    ADD HL,HL               ; Double the remainder for the next trial
    JP .LOOP                  ; Generate the next quotient bit

; A nonzero remainder represents further quotient bits and sets sticky.
.DONE:
    LD A,H                  ; Test the final remainder
    OR L                    ; Include its low byte
    LD HL,(F16_QUOT)           ; Load the completed guarded quotient; flags survive
    JP Z,F16_PACK           ; An exact quotient needs no extra sticky bit
    SET 0,L                 ; Record that ungenerated quotient bits contain a one
    JP F16_PACK             ; Normalize and round the quotient

; The numerator is zero and neither input is NaN.
.X_ZERO:
    LD A,(F16_YCAT)          ; Inspect the denominator class
    OR A                    ; Check for another zero
    JP Z,F16_NAN                ; Zero divided by zero is NaN
    JP F16_ZERO                ; Zero divided by nonzero is signed zero

; The numerator is infinite and neither input is NaN.
.X_INF:
    LD A,(F16_YCAT)          ; Inspect the denominator class
    CP 2                    ; Check for another infinity
    JP Z,F16_NAN                ; Infinity divided by infinity is NaN
    JP F16_INF                  ; Infinity divided by finite is signed infinity
