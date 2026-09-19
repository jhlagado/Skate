;=============================================================================
;  Skate binary16 runtime
;=============================================================================

;  PURPOSE
;  -------
;  Provide tagged binary16 classification, conversion and arithmetic.

;  PUBLIC INTERFACE
;  ----------------
;

;+---------------------------------------------------------------------------+
;|  UNARY - F16CLASS, F16NEG, F16TOI and F16TOU.                             |
;|                                                                           |
;|  CALL                                                                     |
;|    A = tag; HL = value.                                                   |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  BINARY - F16ADD, F16SUB, F16MUL, F16DIV and F16CMP.                      |
;|                                                                           |
;|  CALL                                                                     |
;|    A/B = operand tags; HL/DE = operand values.                            |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RAW INGRESS - F16BITS, F16FRI and F16FRU.                                |
;|                                                                           |
;|  CALL                                                                     |
;|    HL = raw bits or integer; A is ignored.                                |
;+---------------------------------------------------------------------------+

;  RESULTS AND CONSTRAINTS
;  -----------------------
;
;  SUCCESS  A = 0; HL = result; carry clear.
;  FAILURE  Carry set; A = 1 for type error or A = 2 for conversion range.
;           HL returns the original input value.
;
;  REGISTERS  BC/DE/flags are clobbered; IX/IY are preserved; SP is balanced.
;  ALLOCATION NOALLOC. Static scratch makes the module non-reentrant.
;  CALLBACKS  None.
;  ARITHMETIC Round-to-nearest-even with gradual underflow.
;  NaN is canonicalized.
;=============================================================================

; Validate a language scalar; only 7E00 is a numeric NaN. HL stays intact.
F16CLASS:
    OR A                    ; Test the incoming logical tag
    JP NZ,F16TYERR            ; Any nonzero tag is outside this leaf module
    LD A,H                  ; Extract the high byte of the encoded scalar
    AND 7CH                 ; Keep only the five exponent bits
    CP 7CH                  ; An all-ones exponent needs special handling
    JP NZ,F16OKAY               ; Every finite encoding is a valid number
    LD A,H                  ; Inspect the high fraction bits
    AND 3                   ; Remove sign and exponent
    OR L                    ; Combine all ten fraction bits
    JP Z,F16OKAY                ; A zero fraction here denotes infinity
    LD A,H                  ; Check the complete high byte of canonical NaN
    CP 7EH                  ; Canonical NaN must start with 7E
    JP NZ,F16TYERR            ; Reject all other NaN encodings at the language boundary
    LD A,L                  ; Check its low byte as well
    OR A                    ; Canonical NaN ends in 00
    JP Z,F16OKAY                ; Accept exactly 7E00

; Shared type failure preserves the original argument in HL.
F16TYERR:
    LD A,1                  ; Type-error status
    SCF                     ; Set the ABI failure flag
    RET                     ; Return the unchanged payload

; Shared success return: HL already contains the requested result.
F16OKAY:
    XOR A                   ; Set status zero and clear carry together
    RET                     ; Return through the caller continuation

; Raw IEEE ingress only: canonicalize NaNs before constructing a Value.
F16BITS:
    LD A,H                  ; Inspect the raw IEEE exponent
    AND 7CH                 ; Isolate its five bits
    CP 7CH                  ; All ones denotes infinity or NaN
    JP NZ,F16OKAY               ; Finite bits need no alteration
    LD A,H                  ; Inspect the fraction high bits
    AND 3                   ; Remove sign and exponent
    OR L                    ; Include the low fraction byte
    JP Z,F16OKAY                ; Preserve either signed infinity
    JP FMAKENAN                 ; Replace every raw NaN with canonical 7E00

; Negate a language number while preserving the sole numeric NaN encoding.
F16NEG:
    CALL F16CLASS           ; Reject nonnumbers before touching the payload
    RET C                   ; Propagate the type failure
    LD A,H                  ; Check for the canonical NaN high byte
    CP 7EH                  ; NaN cannot acquire a negative sign
    JP NZ,FNEGFIN           ; Other values can flip their sign directly
    LD A,L                  ; Inspect the remaining NaN bits
    OR A                    ; Confirm the canonical NaN low byte is zero
    JP Z,FMAKENAN               ; Return NaN unchanged

; The sign bit is independent of the finite magnitude or infinity.
FNEGFIN:
    LD A,H                  ; Fetch the sign-bearing high byte
    XOR 80H                 ; Toggle bit 15, including for signed zero
    LD H,A                  ; Install the new sign
    JP F16OKAY                  ; Return the altered payload successfully

; Save both operands, then validate both tags before arithmetic.
; EX preserves the second validation carry while restoring the left HL.
FPREPARE:
    LD (FLEFTVAL),HL              ; Save the original left payload
    LD (FRIGHTVL),DE              ; Save the original right payload
    CALL F16CLASS           ; Validate the left tag and bits
    RET C                   ; Leave HL untouched on left failure
    EX DE,HL                ; Put the right payload in the unary argument register
    LD A,B                  ; Use the saved right tag from B
    CALL F16CLASS           ; Validate the right operand
    EX DE,HL                ; Restore left HL without changing failure carry
    RET                     ; Return the validation status

; Decode |HL|. For finite nonzero values, DE is a normalized 11-bit
; mantissa and A is the signed biased exponent (-9..30). C is the class:
; 0 zero, 1 finite nonzero, 2 infinity, 3 NaN. Zero returns DE=0 and A=0;
; the arithmetic paths use only C for infinity and NaN.
FUNPACK:
    LD A,H                  ; Extract the encoded fraction high byte
    AND 3                   ; Keep the two explicit high fraction bits
    LD D,A                  ; Start the unsigned significand in DE
    LD E,L                  ; Append the eight low fraction bits
    LD A,H                  ; Extract the encoded exponent
    AND 7CH                 ; Discard sign and fraction
    RRCA                    ; Move exponent toward bit zero
    RRCA                    ; A now contains the five-bit biased exponent
    LD C,1                  ; Default to the finite nonzero class
    OR A                    ; An exponent of zero needs subnormal handling
    JP Z,FUNPSUB             ; Normalize zero or a subnormal separately
    CP 31                   ; Exponent 31 denotes infinity or NaN
    JP Z,FUNPSPEC             ; Classify the special encoding
    SET 2,D                 ; Supply the implicit leading one of a normal value
    RET                     ; Return DE significand and A exponent

; Subnormals use exponent 1 without an implicit leading one.
FUNPSUB:
    LD A,D                  ; Test the explicit significand
    OR E                    ; Include its low byte
    JP Z,FUNPZERO              ; Zero has no leading one to normalize
    LD A,1                  ; Start with the subnormal effective exponent

; Shift a subnormal until bit 10 is set; exponent falls with each shift.
FUNPNORM:
    BIT 2,D                 ; Test the normalized leading-one position at bit 10
    RET NZ                  ; Return the normalized significand and exponent
    SLA E                   ; Shift the low significand byte
    RL D                    ; Carry its outgoing bit into the high byte
    DEC A                   ; Compensate for doubling the significand
    JP FUNPNORM             ; Continue until the leading bit is in position

; Zero is reported separately so arithmetic can preserve signed-zero rules.
FUNPZERO:
    LD C,0                  ; Class zero
    XOR A                   ; Return exponent zero as well
    RET                     ; Return the zero classification

; An all-ones exponent is infinity exactly when its fraction is zero.
FUNPSPEC:
    LD C,2                  ; Default to the infinity class
    LD A,D                  ; Test the explicit fraction
    OR E                    ; Include the low fraction bits
    RET Z                   ; A zero fraction confirms infinity
    INC C                   ; A nonzero fraction changes the class to NaN
    RET                     ; Return the special classification

; Decode saved x and y into sign, exponent, significand and class fields.
; Signs are stored as 00/80; classes are zero/finite/infinity/NaN = 0/1/2/3.
FUNPBOTH:
    LD HL,(FLEFTVAL)              ; Load the saved left encoding
    LD A,H                  ; Extract its high byte
    AND 80H                 ; Keep the sign in its final byte position
    LD (FLEFTSGN),A           ; Save the left sign
    CALL FUNPACK               ; Decode the left magnitude
    LD (FLEFTEXP),A            ; Save the exponent used for finite nonzero arithmetic
    LD (FLEFTSIG),DE          ; Save the significand used for finite nonzero arithmetic
    LD A,C                  ; Move the classification to a storeable register
    LD (FLEFTCLS),A          ; Save the left class
    LD HL,(FRIGHTVL)              ; Load the saved right encoding
    LD A,H                  ; Extract its high byte
    AND 80H                 ; Keep the right sign bit
    LD (FRIGHTSG),A           ; Save the right sign
    CALL FUNPACK               ; Decode the right magnitude
    LD (FRIGHTEX),A            ; Save the exponent used for finite nonzero arithmetic
    LD (FRIGHTSI),DE          ; Save the significand used for finite nonzero arithmetic
    LD A,C                  ; Move the right classification into A
    LD (FRIGHTCL),A          ; Save the right class
    RET                     ; Return with both decoded operands in scratch

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

; HL has mantissa with three G/R/S bits. Exponent is signed biased.
; Normalize before the single final rounding operation.
FPKNORM:
    LD A,H                  ; Test the guarded magnitude
    OR L                    ; Include its low byte
    JP Z,FZEROSGN              ; An empty magnitude produces the saved signed zero

; The guarded leading one belongs at bit 13; larger values shift right.
FPACKLGE:
    BIT 7,H                 ; Check whether bit 15 is set
    JP NZ,FPACKRSH              ; A leading bit 15 needs a sticky right shift
    BIT 6,H                 ; Check whether bit 14 is set
    JP Z,FPACKSML              ; With neither high bit set, test for a small magnitude

; One right shift halves the significand and increases its exponent.
FPACKRSH:
    LD B,1                  ; Request one sticky right shift
    CALL FJAMSHFT              ; Retain discarded information for final rounding
    LD A,(FRESEXP)             ; Fetch the signed biased exponent
    INC A                   ; Compensate for halving the magnitude
    LD (FRESEXP),A             ; Save the new exponent
    JP FPACKLGE                ; Check whether another right shift is needed

; A nonzero guarded magnitude is normalized when bit 13 is set.
FPACKSML:
    BIT 5,H                 ; Check the target leading-one position
    JP NZ,FPACKVAL               ; The significand is now ready for exponent handling
    ADD HL,HL               ; Move the leading one toward bit 13
    LD A,(FRESEXP)             ; Fetch the signed biased exponent
    DEC A                   ; Compensate for doubling the magnitude
    LD (FRESEXP),A             ; Save the new exponent
    JP FPACKSML                ; Continue until bit 13 is set

; Exponent 1 is the smallest normal scale; lower values become subnormals.
FPACKVAL:
    LD A,(FRESEXP)             ; Fetch the normalized exponent
    OR A                    ; Test its zero and sign flags
    JP Z,FPACKSUB             ; Exponent zero needs a subnormal shift
    JP M,FPACKSUB             ; A negative exponent also needs a subnormal shift
    CP 31                   ; Exponent 31 is beyond the largest finite encoding
    JP NC,FMAKEINF              ; Overflow produces signed infinity
    JP FPACKRND               ; A normal-range exponent can round directly

; Shift to the scale for exponent 1 before rounding, retaining sticky data.
FPACKSUB:
    NEG                     ; Form the negated exponent
    INC A                   ; The shift distance is 1 minus exponent
    LD B,A                  ; Pass that distance in B
    CALL FJAMSHFT              ; Shift into the gradual-underflow range
    LD A,1                  ; Use the smallest normal exponent as the working scale
    LD (FRESEXP),A             ; Save that scale for rounding and encoding
FPACKRND:
    ; Round nearest-even: add 3 + retained low bit, then drop G/R/S.
    LD DE,3                 ; Bias by three before dropping three rounding bits
    BIT 3,L                 ; Inspect the least significant retained bit
    JP Z,FROUNDAD           ; An even retained value uses the smaller bias
    INC DE                  ; An odd retained value adds four for ties-to-even

; Adding 3 + retained parity resolves halfway cases before truncation.
FROUNDAD:
    ADD HL,DE               ; Apply the rounding bias to the guarded magnitude
    SRL H                   ; Start dropping the sticky position from the word
    RR L                    ; Complete the first right shift
    SRL H                   ; Start dropping the round position
    RR L                    ; Complete the second right shift
    SRL H                   ; Start dropping the guard position
    RR L                    ; HL holds the rounded significand, possibly with carry
    BIT 3,H                 ; Test for rounding carry into bit 11
    JP Z,FPACKENC              ; No carry means the exponent is unchanged
    SRL H                   ; Shift the rounding carry toward the normal leading bit
    RR L                    ; Complete that extra right shift
    LD A,(FRESEXP)             ; Fetch the exponent before carry normalization
    INC A                   ; Account for the extra shift
    LD (FRESEXP),A             ; Save the rounded exponent

; A rounded subnormal has no implicit bit; a normal value removes bit 10.
FPACKENC:
    LD A,(FRESEXP)             ; Fetch the final exponent
    CP 31                   ; Check for overflow caused by rounding
    JP NC,FMAKEINF              ; Return infinity if rounding crossed the finite limit
    BIT 2,H                 ; Test for the implicit bit of a normal significand
    JP Z,FPACKSGN             ; Without it, encode an exponent-zero subnormal
    RES 2,H                 ; Remove the implicit leading one from the stored fraction
    RLCA                    ; Move the exponent toward its high-byte field
    RLCA                    ; Place exponent bits in positions 2 through 6
    OR H                    ; Combine exponent and high fraction bits
    LD H,A                  ; Install the encoded magnitude high byte

; The magnitude is encoded; only the saved sign remains to be applied.
FPACKSGN:
    LD A,(FRESIGN)             ; Fetch the result sign in bit 7
    OR H                    ; Combine sign with the encoded magnitude
    LD H,A                  ; Install the complete high byte
    JP F16OKAY                  ; Return the rounded binary16 result

; Construct a zero with the sign selected by the arithmetic path.
FZEROSGN:
    LD A,(FRESIGN)             ; Fetch the selected sign bit
    LD H,A                  ; The high byte contains only the sign
    LD L,0                  ; The low fraction byte is zero
    JP F16OKAY                  ; Return signed zero successfully

; Construct infinity with the sign selected by the arithmetic path.
FMAKEINF:
    LD A,(FRESIGN)             ; Fetch the selected sign bit
    OR 7CH                  ; Set the all-ones exponent with a zero fraction
    LD H,A                  ; Install sign and exponent
    LD L,0                  ; Keep the fraction low byte zero
    JP F16OKAY                  ; Return signed infinity successfully

; Every numeric NaN result uses the sole language NaN encoding.
FMAKENAN:
    LD HL,7E00H             ; Construct canonical numeric NaN
    JP F16OKAY                  ; Return it as a successful arithmetic result

; Shift HL right B places, OR every discarded bit into sticky bit zero.
FJAMSHFT:
    LD A,B                  ; Test the requested shift count
    OR A                    ; A zero count leaves the magnitude unchanged
    RET Z                   ; Return without entering the decrementing loop

; Once sticky is one, subsequent shifts retain it even if other bits vanish.
FJAMLOOP:
    SRL H                   ; Shift the high magnitude byte toward L
    RR L                    ; Shift the low byte; carry is the discarded bit
    JP NC,FJAMNEXT          ; No extra sticky bit is needed for a discarded zero
    SET 0,L                 ; OR a discarded one into the low bit

; B counts remaining shifts; the jammed low bit summarizes lost precision.
FJAMNEXT:
    DJNZ FJAMLOOP            ; Repeat for the requested alignment distance
    RET                     ; Return the shifted magnitude in HL

; Negate a raw 16-bit word modulo 65536; 8000H remains its own negation.
FNEGWORD:
    LD A,L                  ; Fetch the low byte
    CPL                     ; Invert its bits
    LD L,A                  ; Save the inverted low byte
    LD A,H                  ; Fetch the high byte
    CPL                     ; Invert its bits
    LD H,A                  ; Save the inverted high byte
    INC HL                  ; Add one to complete two's-complement negation
    RET                     ; Return the negated raw word

; Raw comparison code: FFFF less, 0 equal, 1 greater, 2 unordered.
F16CMP:
    CALL FPREPARE              ; Save and validate both language operands
    RET C                   ; Propagate a type failure
    CALL FUNPBOTH           ; Decode signs and special classes
    LD A,(FLEFTCLS)          ; Inspect the left class
    CP 3                    ; Check for NaN
    JP Z,FCMPUNOR             ; NaN makes the comparison unordered
    LD A,(FRIGHTCL)          ; Inspect the right class
    CP 3                    ; Check for NaN
    JP Z,FCMPUNOR             ; NaN makes the comparison unordered
    LD A,(FLEFTCLS)          ; Fetch the left zero/nonzero class
    LD B,A                  ; Keep it while loading the right class
    LD A,(FRIGHTCL)          ; Fetch the right class
    OR B                    ; Both classes are zero only for two zeros
    JP Z,FCMPEQOK             ; Treat positive and negative zero as equal
    LD A,(FLEFTSGN)           ; Fetch the left sign
    LD B,A                  ; Keep it while loading the right sign
    LD A,(FRIGHTSG)           ; Fetch the right sign
    XOR B                   ; Compare the signs
    JP NZ,FCMPSGN           ; Use sign ordering after handling the two-zero case
    LD HL,(FLEFTVAL)              ; Load the complete left encoding
    LD DE,(FRIGHTVL)              ; Load the complete right encoding
    OR A                    ; Clear carry before comparing the unsigned bit patterns
    SBC HL,DE               ; Compare encoded magnitudes for these equal-sign inputs
    JP Z,FCMPEQOK             ; Identical encodings denote equal numbers
    JP C,FCMPBITL           ; Borrow means the left encoding is smaller
    LD A,(FLEFTSGN)           ; Fetch the common sign
    OR A                    ; Check whether ordering must be reversed
    JP NZ,FCMPLTR            ; For negatives, a larger encoding means a smaller number
    JP FCMPGTR               ; For positives, the larger encoding means greater

; Unsigned encoding order reverses when both numbers are negative.
FCMPBITL:
    LD A,(FLEFTSGN)           ; Fetch the common sign
    OR A                    ; Check whether both numbers are negative
    JP NZ,FCMPGTR            ; A smaller negative encoding denotes a greater value
    JP FCMPLTR               ; A smaller positive encoding denotes a lesser value

; The signs differ and the two-zero case has already been handled.
FCMPSGN:
    LD A,(FLEFTSGN)           ; Fetch the left sign
    OR A                    ; Check whether the left operand is negative
    JP NZ,FCMPLTR            ; A negative left operand is the lesser value

; Raw comparison result for left greater than right.
FCMPGTR:
    LD HL,1                 ; Return code +1
    JP F16OKAY                  ; Clear the success status and carry

; Raw comparison result for left less than right.
FCMPLTR:
    LD HL,0FFFFH            ; Return code -1 as a raw word
    JP F16OKAY                  ; Clear the success status and carry

; Raw comparison result for equality, including either pairing of zeros.
FCMPEQOK:
    LD HL,0                 ; Return code zero
    JP F16OKAY                  ; Clear the success status and carry

; Raw comparison result when either operand is numeric NaN.
FCMPUNOR:
    LD HL,2                 ; Return unordered code two
    JP F16OKAY                  ; Clear the success status and carry

; Internal raw integer ingress; no Scheme integer tag is constructed.
F16FRI:
    XOR A                   ; Start with a positive result sign
    LD (FRESIGN),A             ; Save the provisional sign
    BIT 7,H                 ; Test the raw integer sign bit
    JP Z,FRAWPACK               ; Nonnegative words are already magnitudes
    LD A,80H                ; Select the negative result sign
    LD (FRESIGN),A             ; Save it before taking the magnitude
    CALL FNEGWORD              ; Convert the signed word to its unsigned magnitude
    JP FRAWPACK                 ; Use the common integer-to-float packer

; Unsigned raw ingress treats all sixteen input bits as magnitude.
F16FRU:
    XOR A                   ; Select a positive result sign
    LD (FRESIGN),A             ; Save the unsigned result sign

; Treat raw HL as a guarded significand: exponent 28 compensates for
; the packer dividing it by eight and interpreting an eleven-bit mantissa.
FRAWPACK:
    LD A,28                 ; Use bias 15 plus guarded leading-bit position 13
    LD (FRESEXP),A             ; Initialize the exponent for the raw integer magnitude
    JP FPKNORM              ; Normalize and round through the common packer

; Internal egress truncates toward zero, then range-checks that integer.
F16TOI:
    LD C,1                  ; Select signed range checking after truncation
    JP FTOIWORK                 ; Enter the common float-to-word conversion

; Unsigned conversion shares truncation and changes only the range check.
F16TOU:
    LD C,0                  ; Select unsigned range checking after truncation

; A normalized significand represents mantissa * 2^(exponent - 25).
; Integer egress shifts by that amount, discarding fractional bits directly.
FTOIWORK:
    LD (FLEFTVAL),HL              ; Save the original payload for any range failure
    CALL F16CLASS           ; Validate the language tag and numeric encoding
    RET C                   ; Propagate a type failure without changing HL
    LD A,C                  ; Recover the signed/unsigned mode preserved in C
    LD (FCONMODE),A            ; Save the mode before FUNPACK replaces C with a class
    LD A,H                  ; Fetch the encoded sign
    AND 80H                 ; Keep only the sign bit
    LD (FRESIGN),A             ; Save the sign for the final range check
    CALL FUNPACK               ; Decode the magnitude, exponent and class
    LD B,A                  ; Preserve the decoded exponent in B
    LD A,C                  ; Inspect the decoded class
    CP 2                    ; Infinity and NaN cannot convert to an integer
    JP NC,FRANGEER           ; Report range failure for either special class
    EX DE,HL                ; Move the decoded significand into HL
    LD A,B                  ; Recover its signed biased exponent
    SUB 25                  ; Compute the binary shift needed for integer units
    JP M,FTOIRSHF              ; A negative shift discards fractional bits
    LD B,A                  ; Use the nonnegative shift distance as a loop count
    OR A                    ; Test for an already integral scale
    JP Z,FTOICHK             ; A zero distance needs only range checking

; Finite binary16 needs at most five left shifts here, so the word fits.
FTOILEFT:
    ADD HL,HL               ; Scale the significand toward integer units
    DJNZ FTOILEFT            ; Repeat for each required binary place
    JP FTOICHK               ; Check the resulting integer against the selected range

; Right shifts truncate the magnitude toward zero; no sticky rounding here.
FTOIRSHF:
    NEG                     ; Make the fractional shift distance positive
    CP 16                   ; A shift of sixteen or more removes the entire word
    JP NC,FTOIZERO             ; Return a zero magnitude for such small inputs
    LD B,A                  ; Pass the remaining fractional shift count in B

; Discard fractional bits one place at a time.
FTOIRLOP:
    SRL H                   ; Shift the magnitude high byte toward L
    RR L                    ; Discard the low bit without jamming it back in
    DJNZ FTOIRLOP            ; Continue until all fractional positions are removed
    JP FTOICHK               ; Range-check the truncated integer

; Every magnitude below one truncates to integer zero.
FTOIZERO:
    LD HL,0                 ; Set the truncated integer magnitude to zero

; Apply signed or unsigned bounds after truncation, not before it.
FTOICHK:
    LD A,(FCONMODE)            ; Fetch the requested conversion mode
    OR A                    ; Zero selects unsigned conversion
    JP Z,FTOUCHK            ; Check unsigned sign restrictions separately
    LD A,(FRESIGN)             ; Fetch the original floating-point sign
    OR A                    ; Check whether a signed result will be negative
    JP NZ,FTOINEGC          ; Negative signed results allow magnitude 32768
    BIT 7,H                 ; Positive signed results must have bit 15 clear
    JP NZ,FRANGEER           ; Reject positive magnitudes of 32768 or more
    JP F16OKAY                  ; Return the nonnegative signed integer

; The signed negative endpoint allows exactly magnitude 8000H (32768).
FTOINEGC:
    LD A,H                  ; Inspect the magnitude high byte
    CP 80H                  ; Compare with the negative endpoint high byte
    JP C,FTOINEG             ; Anything below 8000H fits when negated
    JP NZ,FRANGEER           ; Anything above the 80 high byte is too large
    LD A,L                  ; At high byte 80, inspect the remaining magnitude
    OR A                    ; Only a zero low byte is exactly 32768
    JP NZ,FRANGEER           ; Reject magnitudes above the negative endpoint

; The bounded magnitude becomes a signed two's-complement result.
FTOINEG:
    CALL FNEGWORD              ; Apply the negative sign to the raw integer
    JP F16OKAY                  ; Return the signed word successfully

; Negative fractions that truncated to zero are valid unsigned zero.
FTOUCHK:
    LD A,(FRESIGN)             ; Fetch the original floating-point sign
    OR A                    ; Check whether it was negative
    JP Z,F16OKAY                ; Every nonnegative finite truncated word fits
    LD A,H                  ; Test the truncated negative magnitude
    OR L                    ; Include the low byte
    JP Z,F16OKAY                ; A negative input may still truncate to valid zero

; Conversion failure restores the incoming floating-point payload.
FRANGEER:
    LD HL,(FLEFTVAL)              ; Recover the original argument bits
    LD A,2                  ; Return conversion-range status two
    SCF                     ; Set the ABI failure flag
    RET                     ; Return without exposing a partial integer result

; Code ends here. The following 27 bytes are private writable scratch.
F16END:
F16WORK:
FLEFTVAL: DW 0                    ; Original/prepared left binary16 payload; also conversion error backup
FRIGHTVL: DW 0                    ; Original/prepared right binary16 payload
FLEFTSIG: DW 0                ; Left normalized unsigned 11-bit significand
FRIGHTSI: DW 0                ; Right normalized unsigned 11-bit significand
FLEFTEXP: DB 0                 ; Left signed biased exponent after subnormal normalization
FRIGHTEX: DB 0                 ; Right signed biased exponent after subnormal normalization
FLEFTSGN: DB 0                ; Left sign as 00 or 80
FRIGHTSG: DB 0                ; Right sign as 00 or 80
FLEFTCLS: DB 0               ; Left class: 0 zero, 1 finite nonzero, 2 infinity, 3 NaN
FRIGHTCL: DB 0               ; Right class with the same four encodings
FRESIGN: DB 0                  ; Result sign as 00 or 80 for the shared packer
FRESEXP: DB 0                  ; Result signed biased exponent for the shared packer
FMULCAND: DW 0                ; Low word of the shifting multiplication multiplicand
FMULHBYT: DB 0               ; High byte extending the multiplicand to 24 bits
FMULTPLR: DW 0                 ; Remaining multiplier bits, consumed from the low end
FPRODUCT: DW 0                 ; Low word of the exact significand product
FPRODHI: DB 0                ; High byte extending the product to 24 bits
FDIVQUOT: DW 0                 ; Fourteen-bit quotient accumulated by restoring division
FCONMODE: DB 0                 ; Integer egress mode: 0 unsigned, 1 signed
F16WEND:
