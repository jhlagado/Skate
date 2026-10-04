; Binary16 integer ingress and truncating integer egress.
; Entry points: F16_ITOF and F16_FTOI.
; Convert the signed twenty-four-bit integer C:HL to binary16, rounding to
; nearest even.  Magnitudes above 65504 become infinity.
F16_ITOF:
    XOR A                   ; Start with a positive result sign
    LD (F16_SIGN),A            ; Save the provisional sign
    BIT 7,C                 ; Test the integer sign bit
    JP Z,.PACK                  ; Nonnegative values are already magnitudes
    LD A,80H                ; Select the negative result sign
    LD (F16_SIGN),A            ; Save it before taking the magnitude
    XOR A                   ; Negate C:HL into its unsigned magnitude
    SUB L
    LD L,A
    LD A,0
    SBC A,H
    LD H,A
    LD A,0
    SBC A,C
    LD C,A

; Treat raw HL as a guarded significand: exponent 28 compensates for
; the packer dividing it by eight and interpreting an eleven-bit mantissa.
; Byte 2 is folded into the word first, one sticky right shift per bit.
.PACK:
    LD A,28                 ; Use bias 15 plus guarded leading-bit position 13
    LD (F16_EXP),A             ; Initialize the exponent for the raw integer magnitude
.FOLD:
    LD A,C                  ; A clear byte 2 leaves a sixteen-bit significand
    OR A
    JP Z,F16_PACK           ; Normalize and round through the common packer
    SRL C                   ; Halve the magnitude, retaining the lost bit
    RR H
    RR L
    JR NC,.SCALED
    SET 0,L                 ; A discarded one bit stays sticky for rounding
.SCALED:
    LD A,(F16_EXP)          ; Compensate the exponent for the halving
    INC A
    LD (F16_EXP),A
    JP .FOLD

; Internal egress truncates toward zero into the signed integer C:HL.  Every
; finite binary16 value fits twenty-four bits, so only an infinity or NaN
; fails, with status two.
F16_FTOI:
    LD (F16_X),HL                 ; Save the original payload for any range failure
    CALL F16_CHK            ; Validate the language tag and numeric encoding
    RET C                   ; Propagate a type failure without changing HL
    LD A,H                  ; Fetch the encoded sign
    AND 80H                 ; Keep only the sign bit
    LD (F16_SIGN),A            ; Save the sign for the final negation
    CALL F16_OPEN              ; Decode the magnitude, exponent and class
    LD B,A                  ; Preserve the decoded exponent in B
    LD A,C                  ; Inspect the decoded class
    CP 2                    ; Infinity and NaN cannot convert to an integer
    JP NC,.NO_FIT            ; Report range failure for either special class
    EX DE,HL                ; Move the decoded significand into HL
    LD C,0                  ; Byte 2 of the magnitude starts clear
    LD A,B                  ; Recover its signed biased exponent
    SUB 25                  ; Compute the binary shift needed for integer units
    JP M,.RIGHT                ; A negative shift discards fractional bits
    LD B,A                  ; Use the nonnegative shift distance as a loop count
    OR A                    ; Test for an already integral scale
    JP Z,.SIGNED             ; A zero distance needs only the sign

; A normalized significand represents mantissa * 2^(exponent - 25).
; Finite binary16 needs at most five left shifts here.
.LEFT:
    ADD HL,HL               ; Scale the significand toward integer units
    RL C
    DJNZ .LEFT               ; Repeat for each required binary place
    JP .SIGNED

; Right shifts truncate the magnitude toward zero; no sticky rounding here.
.RIGHT:
    NEG                     ; Make the fractional shift distance positive
    CP 16                   ; A shift of sixteen or more removes the entire word
    JP NC,.ZERO                ; Return a zero magnitude for such small inputs
    LD B,A                  ; Pass the remaining fractional shift count in B

; Discard fractional bits one place at a time.
.DROP:
    SRL H                   ; Shift the magnitude high byte toward L
    RR L                    ; Discard the low bit without jamming it back in
    DJNZ .DROP               ; Continue until all fractional positions are removed
    JP .SIGNED

; Every magnitude below one truncates to integer zero.
.ZERO:
    LD HL,0                 ; Set the truncated integer magnitude to zero

; Apply the sign; a negative fraction that truncated to zero stays zero.
.SIGNED:
    LD A,(F16_SIGN)            ; Fetch the original floating-point sign
    OR A
    JP Z,F16_OK                 ; Return the nonnegative integer
    XOR A                   ; Negate C:HL
    SUB L
    LD L,A
    LD A,0
    SBC A,H
    LD H,A
    LD A,0
    SBC A,C
    LD C,A
    JP F16_OK                   ; Return the signed integer successfully

; Conversion failure restores the incoming floating-point payload.
.NO_FIT:
    LD HL,(F16_X)                 ; Recover the original argument bits
    LD A,2                  ; Return conversion-range status two
    SCF                     ; Set the ABI failure flag
    RET                     ; Return without exposing a partial integer result
