; Binary16 classification, ingress validation and unpacking.
; Entry points: F16_CHK, .FROM_RAW, F16_NEG, F16_LOAD, F16_OPEN and F16_BOTH.
; Validate a language scalar; only 7E00 is a numeric NaN. HL stays intact.
F16_CHK:
    OR A                    ; Test the incoming logical tag
    JP NZ,.BAD_TYPE           ; Any nonzero tag is outside this leaf module
    LD A,H                  ; Extract the high byte of the encoded scalar
    AND 7CH                 ; Keep only the five exponent bits
    CP 7CH                  ; An all-ones exponent needs special handling
    JP NZ,F16_OK                ; Every finite encoding is a valid number
    LD A,H                  ; Inspect the high fraction bits
    AND 3                   ; Remove sign and exponent
    OR L                    ; Combine all ten fraction bits
    JP Z,F16_OK                 ; A zero fraction here denotes infinity
    LD A,H                  ; Check the complete high byte of canonical NaN
    CP 7EH                  ; Canonical NaN must start with 7E
    JP NZ,.BAD_TYPE           ; Reject all other NaN encodings at the language boundary
    LD A,L                  ; Check its low byte as well
    OR A                    ; Canonical NaN ends in 00
    JP Z,F16_OK                 ; Accept exactly 7E00

; Shared type failure preserves the original argument in HL.
.BAD_TYPE:
    LD A,1                  ; Type-error status
    SCF                     ; Set the ABI failure flag
    RET                     ; Return the unchanged payload

; Shared success return: HL already contains the requested result.
F16_OK:
    XOR A                   ; Set status zero and clear carry together
    RET                     ; Return through the caller continuation

; Raw IEEE ingress only: canonicalize NaNs before constructing a Value.
.FROM_RAW:
    LD A,H                  ; Inspect the raw IEEE exponent
    AND 7CH                 ; Isolate its five bits
    CP 7CH                  ; All ones denotes infinity or NaN
    JP NZ,F16_OK                ; Finite bits need no alteration
    LD A,H                  ; Inspect the fraction high bits
    AND 3                   ; Remove sign and exponent
    OR L                    ; Include the low fraction byte
    JP Z,F16_OK                 ; Preserve either signed infinity
    JP F16_NAN                  ; Replace every raw NaN with canonical 7E00

; Negate a language number while preserving the sole numeric NaN encoding.
F16_NEG:
    CALL F16_CHK            ; Reject nonnumbers before touching the payload
    RET C                   ; Propagate the type failure
    LD A,H                  ; Check for the canonical NaN high byte
    CP 7EH                  ; NaN cannot acquire a negative sign
    JP NZ,.TOGGLE           ; Other values can flip their sign directly
    LD A,L                  ; Inspect the remaining NaN bits
    OR A                    ; Confirm the canonical NaN low byte is zero
    JP Z,F16_NAN                ; Return NaN unchanged

; The sign bit is independent of the finite magnitude or infinity.
.TOGGLE:
    LD A,H                  ; Fetch the sign-bearing high byte
    XOR 80H                 ; Toggle bit 15, including for signed zero
    LD H,A                  ; Install the new sign
    JP F16_OK                   ; Return the altered payload successfully

; Save both operands, then validate both tags before arithmetic.
; EX preserves the second validation carry while restoring the left HL.
F16_LOAD:
    LD (F16_X),HL                 ; Save the original left payload
    LD (F16_Y),DE                 ; Save the original right payload
    CALL F16_CHK            ; Validate the left tag and bits
    RET C                   ; Leave HL untouched on left failure
    EX DE,HL                ; Put the right payload in the unary argument register
    LD A,B                  ; Use the saved right tag from B
    CALL F16_CHK            ; Validate the right operand
    EX DE,HL                ; Restore left HL without changing failure carry
    RET                     ; Return the validation status

; Decode |HL|. For finite nonzero values, DE is a normalized 11-bit
; mantissa and A is the signed biased exponent (-9..30). C is the class:
; 0 zero, 1 finite nonzero, 2 infinity, 3 NaN. Zero returns DE=0 and A=0;
; the arithmetic paths use only C for infinity and NaN.
F16_OPEN:
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
    JP Z,.SUBNORM            ; Normalize zero or a subnormal separately
    CP 31                   ; Exponent 31 denotes infinity or NaN
    JP Z,.SPECIAL             ; Classify the special encoding
    SET 2,D                 ; Supply the implicit leading one of a normal value
    RET                     ; Return DE significand and A exponent

; Subnormals use exponent 1 without an implicit leading one.
.SUBNORM:
    LD A,D                  ; Test the explicit significand
    OR E                    ; Include its low byte
    JP Z,.ZERO                 ; Zero has no leading one to normalize
    LD A,1                  ; Start with the subnormal effective exponent

; Shift a subnormal until bit 10 is set; exponent falls with each shift.
.NORMAL:
    BIT 2,D                 ; Test the normalized leading-one position at bit 10
    RET NZ                  ; Return the normalized significand and exponent
    SLA E                   ; Shift the low significand byte
    RL D                    ; Carry its outgoing bit into the high byte
    DEC A                   ; Compensate for doubling the significand
    JP .NORMAL              ; Continue until the leading bit is in position

; Zero is reported separately so arithmetic can preserve signed-zero rules.
.ZERO:
    LD C,0                  ; Class zero
    XOR A                   ; Return exponent zero as well
    RET                     ; Return the zero classification

; An all-ones exponent is infinity exactly when its fraction is zero.
.SPECIAL:
    LD C,2                  ; Default to the infinity class
    LD A,D                  ; Test the explicit fraction
    OR E                    ; Include the low fraction bits
    RET Z                   ; A zero fraction confirms infinity
    INC C                   ; A nonzero fraction changes the class to NaN
    RET                     ; Return the special classification

; Decode saved x and y into sign, exponent, significand and class fields.
; Signs are stored as 00/80; classes are zero/finite/infinity/NaN = 0/1/2/3.
F16_BOTH:
    LD HL,(F16_X)                 ; Load the saved left encoding
    LD A,H                  ; Extract its high byte
    AND 80H                 ; Keep the sign in its final byte position
    LD (F16_XNEG),A           ; Save the left sign
    CALL F16_OPEN              ; Decode the left magnitude
    LD (F16_XEXP),A            ; Save the exponent used for finite nonzero arithmetic
    LD (F16_XMAN),DE          ; Save the significand used for finite nonzero arithmetic
    LD A,C                  ; Move the classification to a storeable register
    LD (F16_XCAT),A          ; Save the left class
    LD HL,(F16_Y)                 ; Load the saved right encoding
    LD A,H                  ; Extract its high byte
    AND 80H                 ; Keep the right sign bit
    LD (F16_YNEG),A           ; Save the right sign
    CALL F16_OPEN              ; Decode the right magnitude
    LD (F16_YEXP),A            ; Save the exponent used for finite nonzero arithmetic
    LD (F16_YMAN),DE          ; Save the significand used for finite nonzero arithmetic
    LD A,C                  ; Move the right classification into A
    LD (F16_YCAT),A          ; Save the right class
    RET                     ; Return with both decoded operands in scratch
