; Numeric dispatch and exact arithmetic.
; Entry points: NUM_CHK, NUM_ADD, NUM_SUB, NUM_MUL, NUM_DIV and NINT*.
; Validates tagged values, selects binary16 paths, and checks exact results.
; Validate A/HL without changing HL. Integer payloads need no bit check.
NUM_CHK:
    CP 3                    ; Tag 3 accepts every signed 16-bit payload.
    JP NZ,F16_CHK           ; Other tags use the binary16 scalar checks.
    OR A                    ; Preserve the integer tag and clear failure carry.
    RET                     ; HL still contains the original payload.

NUM_ADD:
    LD C,0                  ; Operation 0 selects addition.
    JP NUM_CALC               ; Share validation and representation dispatch.
NUM_SUB:
    LD C,1                  ; Operation 1 selects subtraction.
    JP NUM_CALC               ; Share validation and representation dispatch.
NUM_MUL:
    LD C,2                  ; Operation 2 selects multiplication.
    JP NUM_CALC               ; Share validation and representation dispatch.
NUM_DIV:
    LD C,3                  ; Operation 3 always selects floating division.
; Select exact arithmetic only for integer/integer +, - and *.
NUM_CALC:
    LD (NUM_OP),BC              ; Save C (operation) without disturbing A/B input tags.
    CALL NUM_LOAD              ; Save both values and reject nonnumbers first.
    RET C                   ; Return the original left payload on type failure.
    LD A,(NUM_OP)               ; Recover the operation after classification.
    CP 3                    ; Division has no exact-integer result path.
    JP Z,NUM_REAL             ; Convert integer operands before floating division.
    LD A,(NUM_XTAG)             ; Inspect the saved left tag.
    CP 3                    ; Exact arithmetic requires tag 3 on both sides.
    JP NZ,NUM_REAL            ; A floating left operand selects floating arithmetic.
    LD A,(NUM_YTAG)              ; Inspect the saved right tag.
    CP 3                    ; Check the second half of the exact/exact case.
    JP NZ,NUM_REAL            ; A floating right operand also selects that path.
    LD HL,(NUM_X)                ; Restore the exact left word.
    LD DE,(NUM_Y)                 ; Restore the exact right word.
    LD A,(NUM_OP)               ; Select the checked integer operation.
    OR A                    ; Operation 0 sets zero here.
    JP Z,NUM_IADD             ; Add two signed words.
    DEC A                   ; Operation 1 becomes zero here.
    JP Z,NUM_ISUB             ; Subtract the right word from the left.
    JP NUM_IMUL               ; The remaining exact operation is multiplication.

; Capture the original left before any conversion and classify both inputs.
NUM_LOAD:
    LD (NUM_ORIG),HL           ; Retain the failure result before any conversion.
    LD (NUM_X),HL                ; Save the working left payload.
    LD (NUM_Y),DE                 ; Save the working right payload.
    LD (NUM_XTAG),A             ; Save the left representation tag.
    LD A,B                  ; Move the right tag into the classifier register.
    LD (NUM_YTAG),A              ; Save it before classification clobbers registers.
    LD A,(NUM_XTAG)             ; Classify the left with its original tag.
    CALL NUM_CHK            ; Accept an integer or a numeric scalar.
    JP C,.BAD_TYPE             ; Translate classification failure to the shared exit.
    LD HL,(NUM_Y)                 ; Load the original right payload.
    LD A,(NUM_YTAG)              ; Pair it with its saved tag.
    CALL NUM_CHK            ; Validate the right before converting either value.
    JP C,.BAD_TYPE             ; A bad right operand still returns the original left.
    OR A                    ; Both values are valid; clear failure carry.
    RET                     ; The saved operands now drive either arithmetic path.
.BAD_TYPE:
    LD A,1                  ; Error 1 denotes a nonnumeric input.
    JP NUM_FAIL              ; Restore the original left through the common exit.
NUM_OVER:
    LD A,2                  ; Error 2 denotes an unrepresentable exact result.
NUM_FAIL:
    LD HL,(NUM_ORIG)           ; Failures expose the original left, not a partial result.
    SCF                     ; Carry distinguishes the error code from a result tag.
    RET                     ; Return through the incoming continuation.
; Shared exact-success exit; NUM_RAW below is for machine comparison codes.
NUM_GOOD:
    LD A,3                  ; Tag the checked word as an exact integer.
    OR A                    ; Clear carry without changing the result tag.
    RET                     ; HL is the signed result.
NUM_RAW:
    XOR A                   ; Return A=0 and clear carry for a comparison code.
    RET                     ; HL is an internal code, not an encoded float.

; Checked signed addition and subtraction use P/V, not unsigned carry.
NUM_IADD:
    OR A                    ; ADC must start with no carry-in.
    ADC HL,DE               ; Compute the sum and set signed-overflow P/V.
    JP PE,NUM_OVER             ; PE tests P/V=1: here it means signed overflow.
    JP NUM_GOOD               ; The signed result fits in 16 bits.
NUM_ISUB:
    OR A                    ; SBC must start with no borrow-in.
    SBC HL,DE               ; Compute the difference and set signed-overflow P/V.
    JP PE,NUM_OVER             ; PE tests overflow from this subtraction.
    JP NUM_GOOD               ; The signed result fits in 16 bits.

; Magnitude multiply. A shifted-out multiplicand bit is overflow only
; after the remaining multiplier has been shown nonzero.
; Unsigned shift/add product: HL=sum, DE=shifted left magnitude, BC=remaining
; right magnitude. Each selected bit contributes DE to HL before the next shift.
NUM_IMUL:
    LD A,H                  ; Extract the left sign from its high byte.
    XOR D                   ; A differing right sign makes the product negative.
    AND 80H                 ; Retain only the product sign bit.
    LD (NUM_PNEG),A            ; Save the sign while multiplying unsigned magnitudes.
    BIT 7,H                 ; A negative left word needs two's-complement negation.
    CALL NZ,NUM_FLIP        ; 8000H remains the unsigned magnitude 32768.
    EX DE,HL                ; DE becomes the left magnitude; HL becomes the right.
    BIT 7,H                 ; Check the right operand sign.
    CALL NZ,NUM_FLIP        ; Convert it to an unsigned magnitude too.
    LD B,H                  ; BC is the remaining multiplier.
    LD C,L                  ; Copy its low byte without changing DE.
    LD HL,0                 ; HL accumulates the unsigned product from zero.
.LOOP:
    LD A,B                  ; Test both bytes of the remaining multiplier.
    OR C                    ; Zero means no further partial products remain.
    JP Z,.DONE                ; Finish even when the multiplicand is large.
    BIT 0,C                 ; The low multiplier bit selects this partial product.
    JP Z,.SHIFT              ; A zero bit contributes nothing to the sum.
    ADD HL,DE               ; Add the current shifted multiplicand to the product.
    JP C,NUM_OVER              ; An unsigned 16-bit carry already exceeds either bound.
.SHIFT:
    SRL B                   ; Shift the multiplier right, high byte first.
    RR C                    ; Carry transfers the old B bit 0 into C bit 7.
    LD A,B                  ; Check whether another multiplier bit remains.
    OR C                    ; Combine both remaining bytes for the zero test.
    JP Z,.DONE                ; Avoid rejecting a shift that would never be used.
    SLA E                   ; Double the multiplicand, low byte first.
    RL D                    ; Carry joins the bytes and reports bit 15 leaving DE.
    JP C,NUM_OVER              ; A lost high bit with more multiplier bits means overflow.
    JP .LOOP                  ; Accumulate the next selected partial product.
.DONE:
    LD A,(NUM_PNEG)            ; Recover the sign of the mathematical product.
    OR A                    ; Zero selects the nonnegative result bound.
    JP Z,.POS                 ; Positive magnitudes must be at most 32767.
    LD A,H                  ; Negative magnitudes may reach exactly 32768.
    CP 80H                  ; Compare the high byte against that boundary.
    JP C,.NEG                 ; Anything below 8000H fits after negation.
    JP NZ,NUM_OVER             ; Anything above the boundary high byte overflows.
    LD A,L                  ; At high byte 80H, only a zero low byte fits.
    OR A                    ; Check for the one permitted boundary value 8000H.
    JP NZ,NUM_OVER             ; Reject magnitudes 8001H through 80FFH.
.NEG:
    CALL NUM_FLIP           ; Apply the negative sign, including 8000H -> 8000H.
    JP NUM_GOOD               ; Return the checked exact product.
.POS:
    BIT 7,H                 ; A set high bit exceeds the positive signed limit.
    JP NZ,NUM_OVER             ; Reject positive magnitudes of 32768 or greater.
    JP NUM_GOOD               ; Return the nonnegative exact product.
