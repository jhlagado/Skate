; Binary16 multiplication and division.
; Entry points: F16MUL and F16DIV.
; Multiply two 11-bit significands exactly into a 22-bit product.
; A three-byte accumulator retains every product bit until final reduction.
F16MUL:
    CALL FPREPARE              ; Save and validate both language operands
    RET C                   ; Propagate a type failure
    CALL FUNPBOTH           ; Decode both magnitudes
    CALL FPRODSGN           ; Compute the product sign by XOR
    LD A,(FLEFTCLS)          ; Inspect the left class
    CP 3                    ; Check for NaN
    JP Z,FMAKENAN               ; Propagate canonical NaN
    LD A,(FRIGHTCL)          ; Inspect the right class
    CP 3                    ; Check for NaN
    JP Z,FMAKENAN               ; Propagate canonical NaN
    LD A,(FLEFTCLS)          ; Inspect the left class
    OR A                    ; Check for zero
    JP Z,FMULXZER           ; Resolve zero times infinity separately
    CP 2                    ; Check for infinity
    JP Z,FMULXINF           ; Resolve infinity times zero separately
    LD A,(FRIGHTCL)          ; Inspect the right class
    OR A                    ; Check for zero
    JP Z,FZEROSGN              ; Finite nonzero times zero is signed zero
    CP 2                    ; Check for infinity
    JP Z,FMAKEINF               ; Finite nonzero times infinity is signed infinity
    LD A,(FRIGHTEX)            ; Fetch the right exponent
    LD B,A                  ; Keep it while fetching the left exponent
    LD A,(FLEFTEXP)            ; Fetch the left exponent
    ADD A,B                 ; Add the two biased exponents
    SUB 15                  ; Remove one copy of the binary16 bias
    LD (FRESEXP),A             ; Save the result exponent
    LD HL,(FLEFTSIG)          ; Load the left significand
    LD (FMULCAND),HL          ; Initialize the low word of the shifting multiplicand
    XOR A                   ; Prepare a zero high byte
    LD (FMULHBYT),A          ; Clear the multiplicand extension
    LD (FPRODHI),A           ; Clear the product extension
    LD HL,0                 ; Prepare a zero product low word
    LD (FPRODUCT),HL           ; Clear the product accumulator
    LD HL,(FRIGHTSI)          ; Load the right significand
    LD (FMULTPLR),HL           ; Initialize the bit-at-a-time multiplier
    LD B,11                 ; Process all eleven significand bits

; Each multiplier low bit selects an addition of the current multiplicand.
; The accumulator and multiplicand have a low word and a separate high byte.
FMULLOOP:
    LD HL,(FMULTPLR)           ; Load the remaining multiplier
    SRL H                   ; Shift its high byte toward the low byte
    RR L                    ; Carry now holds the multiplier bit to consume
    LD (FMULTPLR),HL           ; Save the shortened multiplier; LD preserves carry
    JP NC,FMULSHFT          ; A zero multiplier bit contributes no product term
    LD HL,(FPRODUCT)           ; Load the partial product low word
    LD DE,(FMULCAND)          ; Load the current multiplicand low word
    ADD HL,DE               ; Add the selected low-word contribution
    LD (FPRODUCT),HL           ; Save it without disturbing its carry
    LD A,(FMULHBYT)          ; Fetch the multiplicand extension
    LD C,A                  ; Keep it while fetching the product extension
    LD A,(FPRODHI)           ; Fetch the product extension
    ADC A,C                 ; Include the carry from the low-word addition
    LD (FPRODHI),A           ; Save the new product extension

; Advance the multiplicand even when the current multiplier bit was zero.
FMULSHFT:
    LD HL,(FMULCAND)          ; Load the multiplicand low word
    ADD HL,HL               ; Double it; carry is the outgoing bit 15
    LD (FMULCAND),HL          ; Save the low word without changing carry
    LD A,(FMULHBYT)          ; Fetch the multiplicand extension
    RLA                     ; Extend the same shift through its high byte
    LD (FMULHBYT),A          ; Save the shifted extension
    DJNZ FMULLOOP             ; Repeat for the remaining multiplier bits
    LD A,(FPRODHI)           ; Fetch the completed product high byte
    LD HL,(FPRODUCT)           ; Fetch the completed product low word
    LD B,7                  ; Normally reduce bit 20 to guarded leading bit 13
    BIT 5,A                 ; Test for a product with leading bit 21
    JP Z,FMULRED            ; A leading bit 20 needs only seven shifts
    INC B                   ; A leading bit 21 needs eight shifts
    LD C,A                  ; Preserve the product extension across exponent work
    LD A,(FRESEXP)             ; Fetch the result exponent
    INC A                   ; Account for the extra normalization shift
    LD (FRESEXP),A             ; Save the adjusted exponent
    LD A,C                  ; Restore the product extension

; Reduce the three-byte product to HL with three rounding bits.
; Every discarded one is ORed into the sticky bit, including on later shifts.
FMULRED:
    SRL A                   ; Shift the product extension toward H
    RR H                    ; Carry the extension low bit into H
    RR L                    ; Carry H low bit into L; carry now holds discarded data
    JP NC,FMULREDN          ; A discarded zero adds no sticky information
    SET 0,L                 ; Retain a discarded one in the sticky bit

; The reduced product enters the same final packer as addition.
FMULREDN:
    DJNZ FMULRED            ; Continue until all seven or eight shifts are done
    JP FPKNORM              ; Normalize and round the guarded product

; A zero left operand has already passed the NaN checks.
FMULXZER:
    LD A,(FRIGHTCL)          ; Inspect the right class
    CP 2                    ; Check for infinity
    JP Z,FMAKENAN               ; Zero times infinity is NaN
    JP FZEROSGN                ; Every other right class gives signed zero

; An infinite left operand has already passed the NaN checks.
FMULXINF:
    LD A,(FRIGHTCL)          ; Inspect the right class
    OR A                    ; Check for zero
    JP Z,FMAKENAN               ; Infinity times zero is NaN
    JP FMAKEINF                 ; Every other right class gives signed infinity

; Multiplication and division use the XOR of the two sign bits.
FPRODSGN:
    LD A,(FLEFTSGN)           ; Fetch the left sign
    LD B,A                  ; Keep it while loading the right sign
    LD A,(FRIGHTSG)           ; Fetch the right sign
    XOR B                   ; Negative exactly when the signs differ
    LD (FRESIGN),A             ; Save the sign used by all result constructors
    RET                     ; Return to the selected arithmetic operation

; Divide normalized significands with fourteen restoring iterations.
; The quotient has eleven significand bits plus guard, round and sticky bits.
F16DIV:
    CALL FPREPARE              ; Save and validate both language operands
    RET C                   ; Propagate a type failure
    CALL FUNPBOTH           ; Decode both magnitudes
    CALL FPRODSGN           ; Compute the quotient sign by XOR
    LD A,(FLEFTCLS)          ; Inspect the left class
    CP 3                    ; Check for NaN
    JP Z,FMAKENAN               ; Propagate canonical NaN
    LD A,(FRIGHTCL)          ; Inspect the right class
    CP 3                    ; Check for NaN
    JP Z,FMAKENAN               ; Propagate canonical NaN
    LD A,(FLEFTCLS)          ; Inspect the numerator class
    OR A                    ; Check for zero
    JP Z,FDIVXZER           ; Resolve zero divided by zero separately
    CP 2                    ; Check for infinity
    JP Z,FDIVXINF           ; Resolve infinity divided by infinity separately
    LD A,(FRIGHTCL)          ; Inspect the denominator class
    OR A                    ; Check for zero
    JP Z,FMAKEINF               ; Finite nonzero divided by zero is signed infinity
    CP 2                    ; Check for infinity
    JP Z,FZEROSGN              ; Finite divided by infinity is signed zero
    LD A,(FRIGHTEX)            ; Fetch the denominator exponent
    LD B,A                  ; Keep it for subtraction
    LD A,(FLEFTEXP)            ; Fetch the numerator exponent
    SUB B                   ; Subtract the denominator exponent
    ADD A,15                ; Restore one copy of the exponent bias
    LD (FRESEXP),A             ; Save the quotient exponent
    LD HL,(FLEFTSIG)          ; Load the numerator significand
    LD DE,(FRIGHTSI)          ; Load the denominator significand
    OR A                    ; Clear carry before the trial magnitude comparison
    SBC HL,DE               ; Compare numerator against denominator
    JP C,FDIVSCLN           ; A smaller numerator needs one scaling step
    ADD HL,DE               ; Undo the trial subtraction
    JP FDIVNORM             ; The ratio already lies in [1,2)

; A ratio below one is doubled so its first quotient bit is one.
FDIVSCLN:
    ADD HL,DE               ; Restore the numerator after the borrowed subtraction
    ADD HL,HL               ; Double it so the ratio lies in [1,2)
    LD A,(FRESEXP)             ; Fetch the quotient exponent
    DEC A                   ; Compensate for doubling the numerator
    LD (FRESEXP),A             ; Save the adjusted exponent

; HL is the trial remainder, DE is the divisor; quotient lives in scratch.
FDIVNORM:
    LD BC,0                 ; Prepare an empty quotient
    LD (FDIVQUOT),BC           ; Clear the quotient word
    LD B,14                 ; Generate fourteen quotient bits

; Each iteration appends one quotient bit after a trial subtraction.
FDIVLOOP:
    PUSH HL                 ; Preserve the current remainder while updating quotient
    LD HL,(FDIVQUOT)           ; Fetch the quotient assembled so far
    ADD HL,HL               ; Make room for the next quotient bit
    LD (FDIVQUOT),HL           ; Save the shifted quotient
    POP HL                  ; Restore the remainder
    OR A                    ; Clear carry for a fresh trial subtraction
    SBC HL,DE               ; Try removing one divisor from the remainder
    JP C,FDIVNBIT           ; Borrow means this quotient bit is zero
    PUSH HL                 ; Preserve the reduced remainder
    LD HL,(FDIVQUOT)           ; Fetch the quotient with its new low bit clear
    INC HL                  ; Set the current quotient bit to one
    LD (FDIVQUOT),HL           ; Save the extended quotient
    POP HL                  ; Restore the reduced remainder
    JP FDIVBITD             ; Continue with the accepted subtraction

; A failed subtraction contributes a zero quotient bit.
FDIVNBIT:
    ADD HL,DE               ; Restore the remainder to its pre-subtraction value

; Scale the remainder for the next bit, except after the last iteration.
FDIVBITD:
    DEC B                   ; Count the quotient bit just generated
    JP Z,FDIVDONE             ; Fourteen bits are sufficient for final rounding
    ADD HL,HL               ; Double the remainder for the next trial
    JP FDIVLOOP               ; Generate the next quotient bit

; A nonzero remainder represents further quotient bits and sets sticky.
FDIVDONE:
    LD A,H                  ; Test the final remainder
    OR L                    ; Include its low byte
    LD HL,(FDIVQUOT)           ; Load the completed guarded quotient; flags survive
    JP Z,FPKNORM            ; An exact quotient needs no extra sticky bit
    SET 0,L                 ; Record that ungenerated quotient bits contain a one
    JP FPKNORM              ; Normalize and round the quotient

; The numerator is zero and neither input is NaN.
FDIVXZER:
    LD A,(FRIGHTCL)          ; Inspect the denominator class
    OR A                    ; Check for another zero
    JP Z,FMAKENAN               ; Zero divided by zero is NaN
    JP FZEROSGN                ; Zero divided by nonzero is signed zero

; The numerator is infinite and neither input is NaN.
FDIVXINF:
    LD A,(FRIGHTCL)          ; Inspect the denominator class
    CP 2                    ; Check for another infinity
    JP Z,FMAKENAN               ; Infinity divided by infinity is NaN
    JP FMAKEINF                 ; Infinity divided by finite is signed infinity
