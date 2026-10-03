; Binary16 integer ingress and truncating integer egress.
; Entry points: F16_ITOF, .UNSIGNED, F16_FTOI and .UNSIGNED.
F16_ITOF:
    XOR A                   ; Start with a positive result sign
    LD (F16_SIGN),A            ; Save the provisional sign
    BIT 7,H                 ; Test the raw integer sign bit
    JP Z,.PACK                  ; Nonnegative words are already magnitudes
    LD A,80H                ; Select the negative result sign
    LD (F16_SIGN),A            ; Save it before taking the magnitude
    CALL F16_FLIP              ; Convert the signed word to its unsigned magnitude
    JP .PACK                    ; Use the common integer-to-float packer

; Unsigned raw ingress treats all sixteen input bits as magnitude.
.UNSIGNED:
    XOR A                   ; Select a positive result sign
    LD (F16_SIGN),A            ; Save the unsigned result sign

; Treat raw HL as a guarded significand: exponent 28 compensates for
; the packer dividing it by eight and interpreting an eleven-bit mantissa.
.PACK:
    LD A,28                 ; Use bias 15 plus guarded leading-bit position 13
    LD (F16_EXP),A             ; Initialize the exponent for the raw integer magnitude
    JP F16_PACK             ; Normalize and round through the common packer

; Internal egress truncates toward zero, then range-checks that integer.
F16_FTOI:
    LD C,1                  ; Select signed range checking after truncation
    JP .CONVERT                 ; Enter the common float-to-word conversion

; Unsigned conversion shares truncation and changes only the range check.
.UNSIGNED:
    LD C,0                  ; Select unsigned range checking after truncation

; A normalized significand represents mantissa * 2^(exponent - 25).
; Integer egress shifts by that amount, discarding fractional bits directly.
.CONVERT:
    LD (F16_X),HL                 ; Save the original payload for any range failure
    CALL F16_CHK            ; Validate the language tag and numeric encoding
    RET C                   ; Propagate a type failure without changing HL
    LD A,C                  ; Recover the signed/unsigned mode preserved in C
    LD (F16_MODE),A            ; Save the mode before F16_OPEN replaces C with a class
    LD A,H                  ; Fetch the encoded sign
    AND 80H                 ; Keep only the sign bit
    LD (F16_SIGN),A            ; Save the sign for the final range check
    CALL F16_OPEN              ; Decode the magnitude, exponent and class
    LD B,A                  ; Preserve the decoded exponent in B
    LD A,C                  ; Inspect the decoded class
    CP 2                    ; Infinity and NaN cannot convert to an integer
    JP NC,.NO_FIT            ; Report range failure for either special class
    EX DE,HL                ; Move the decoded significand into HL
    LD A,B                  ; Recover its signed biased exponent
    SUB 25                  ; Compute the binary shift needed for integer units
    JP M,.RIGHT                ; A negative shift discards fractional bits
    LD B,A                  ; Use the nonnegative shift distance as a loop count
    OR A                    ; Test for an already integral scale
    JP Z,.CHK                ; A zero distance needs only range checking

; Finite binary16 needs at most five left shifts here, so the word fits.
.LEFT:
    ADD HL,HL               ; Scale the significand toward integer units
    DJNZ .LEFT               ; Repeat for each required binary place
    JP .CHK                  ; Check the resulting integer against the selected range

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
    JP .CHK                  ; Range-check the truncated integer

; Every magnitude below one truncates to integer zero.
.ZERO:
    LD HL,0                 ; Set the truncated integer magnitude to zero

; Apply signed or unsigned bounds after truncation, not before it.
.CHK:
    LD A,(F16_MODE)            ; Fetch the requested conversion mode
    OR A                    ; Zero selects unsigned conversion
    JP Z,.POS_CHK           ; Check unsigned sign restrictions separately
    LD A,(F16_SIGN)            ; Fetch the original floating-point sign
    OR A                    ; Check whether a signed result will be negative
    JP NZ,.NEG_CHK          ; Negative signed results allow magnitude 32768
    BIT 7,H                 ; Positive signed results must have bit 15 clear
    JP NZ,.NO_FIT            ; Reject positive magnitudes of 32768 or more
    JP F16_OK                   ; Return the nonnegative signed integer

; The signed negative endpoint allows exactly magnitude 8000H (32768).
.NEG_CHK:
    LD A,H                  ; Inspect the magnitude high byte
    CP 80H                  ; Compare with the negative endpoint high byte
    JP C,.NEGATE             ; Anything below 8000H fits when negated
    JP NZ,.NO_FIT            ; Anything above the 80 high byte is too large
    LD A,L                  ; At high byte 80, inspect the remaining magnitude
    OR A                    ; Only a zero low byte is exactly 32768
    JP NZ,.NO_FIT            ; Reject magnitudes above the negative endpoint

; The bounded magnitude becomes a signed two's-complement result.
.NEGATE:
    CALL F16_FLIP              ; Apply the negative sign to the raw integer
    JP F16_OK                   ; Return the signed word successfully

; Negative fractions that truncated to zero are valid unsigned zero.
.POS_CHK:
    LD A,(F16_SIGN)            ; Fetch the original floating-point sign
    OR A                    ; Check whether it was negative
    JP Z,F16_OK                 ; Every nonnegative finite truncated word fits
    LD A,H                  ; Test the truncated negative magnitude
    OR L                    ; Include the low byte
    JP Z,F16_OK                 ; A negative input may still truncate to valid zero

; Conversion failure restores the incoming floating-point payload.
.NO_FIT:
    LD HL,(F16_X)                 ; Recover the original argument bits
    LD A,2                  ; Return conversion-range status two
    SCF                     ; Set the ABI failure flag
    RET                     ; Return without exposing a partial integer result
