; Numeric dispatch and exact arithmetic.
; Entry points: NUM_CHK, NUM_ADD, NUM_SUB, NUM_MUL, NUM_DIV, NUM_INV,
; NUM_TEXT and the NUM_I* helpers.  Validates tagged values, selects
; binary16 paths, and checks exact results.
;
; Binary ABI: the left value is in A:CHL and the right value is the cell at
; NUM_Y (payload, byte 2, tag).  A result returns in A:CHL with carry clear.
; A failure returns carry set, the error code in A and the original left
; value in CHL: 1 for a nonnumber, 2 for an unrepresentable exact result and
; 3 for division by zero.  Exact integers are signed twenty-four-bit values.

; Validate A/HL without changing HL. Integer payloads need no bit check.
NUM_CHK:
    CP 3                    ; Tag 3 accepts every signed integer payload.
    JP NZ,F16_CHK           ; Other tags use the binary16 scalar checks.
    OR A                    ; Preserve the integer tag and clear failure carry.
    RET                     ; HL still contains the original payload.

NUM_ADD:
    LD B,0                  ; Operation 0 selects addition.
    JR NUM_CALC             ; Share validation and representation dispatch.
NUM_SUB:
    LD B,1                  ; Operation 1 selects subtraction.
    JR NUM_CALC             ; Share validation and representation dispatch.
NUM_MUL:
    LD B,2                  ; Operation 2 selects multiplication.
    JR NUM_CALC             ; Share validation and representation dispatch.
NUM_DIV:
    LD B,3                  ; Operation 3 always selects floating division.
; Select exact arithmetic only for integer/integer +, - and *.
NUM_CALC:
    CALL NUM_LOAD           ; Save both values and reject nonnumbers first.
    RET C                   ; Return the original left value on type failure.
    LD A,(NUM_OP)           ; Recover the operation after classification.
    CP 3                    ; Division has no exact-integer result path.
    JP Z,NUM_REAL           ; Convert integer operands before floating division.
    LD A,(NUM_X+3)          ; Exact arithmetic requires tag 3 on both sides.
    CP 3
    JP NZ,NUM_REAL          ; A floating left operand selects floating arithmetic.
    LD A,(NUM_Y+3)
    CP 3
    JP NZ,NUM_REAL          ; A floating right operand also selects that path.
    LD HL,(NUM_X)           ; The exact left value in C:HL.
    LD A,(NUM_X+2)
    LD C,A
    LD DE,(NUM_Y)           ; The exact right value in B:DE.
    LD A,(NUM_Y+2)
    LD B,A
    LD A,(NUM_OP)           ; Select the checked integer operation.
    OR A                    ; Addition is the zero operation.
    JP Z,NUM_IADD
    DEC A                   ; Operation 1 becomes zero here.
    JP Z,NUM_ISUB
    JP NUM_IMUL             ; The remaining exact operation is multiplication.

; Capture the original left before any conversion and classify both inputs.
; A:CHL is the left value, NUM_Y the right and B the operation.
NUM_LOAD:
    LD (NUM_ORIG),HL        ; Retain the failure result before any conversion.
    LD (NUM_X),HL           ; Save the working left payload.
    LD (NUM_X+3),A          ; Save the left representation tag.
    LD A,C
    LD (NUM_ORIG+2),A
    LD (NUM_X+2),A
    LD A,B
    LD (NUM_OP),A
    LD A,(NUM_X+3)          ; Classify the left with its original tag.
    CALL NUM_CHK            ; Accept an integer or a numeric scalar.
    JP C,.BAD_TYPE          ; Translate classification failure to the shared exit.
    LD A,(NUM_Y+3)          ; A packet record keeps flags above its tag nibble.
    AND 0FH
    LD (NUM_Y+3),A
    LD HL,(NUM_Y)           ; Validate the right before converting either value.
    CALL NUM_CHK
    JP C,.BAD_TYPE          ; A bad right operand still returns the original left.
    OR A                    ; Both values are valid; clear failure carry.
    RET                     ; The saved operands now drive either arithmetic path.
.BAD_TYPE:
    LD A,1                  ; Error 1 denotes a nonnumeric input.
    JP NUM_FAIL             ; Restore the original left through the common exit.
NUM_OVER:
    LD A,2                  ; Error 2 denotes an unrepresentable exact result.
NUM_FAIL:
    LD HL,(NUM_ORIG)        ; Failures expose the original left, not a partial result.
    LD B,A
    LD A,(NUM_ORIG+2)
    LD C,A
    LD A,B
    SCF                     ; Carry distinguishes the error code from a result tag.
    RET                     ; Return through the incoming continuation.
; Shared exact-success exit; NUM_RAW below is for machine comparison codes.
NUM_GOOD:
    LD A,3                  ; Tag the checked value as an exact integer.
    OR A                    ; Clear carry without changing the result tag.
    RET                     ; C:HL is the signed result.
NUM_RAW:
    XOR A                   ; Return A=0 and clear carry for a comparison code.
    LD C,A
    RET                     ; HL is an internal code, not an encoded float.

; Checked signed addition and subtraction of C:HL and B:DE.  The top byte's
; P/V flag reports twenty-four-bit signed overflow.
NUM_IADD:
    ADD HL,DE               ; Add the low words.
    LD A,C
    ADC A,B                 ; Add the top bytes with the low carry.
    LD C,A
    JP PE,NUM_OVER          ; PE tests P/V=1: here it means signed overflow.
    JP NUM_GOOD             ; The signed result fits in 24 bits.
NUM_ISUB:
    OR A                    ; SBC must start with no borrow-in.
    SBC HL,DE               ; Subtract the low words.
    LD A,C
    SBC A,B                 ; Subtract the top bytes with the low borrow.
    LD C,A
    JP PE,NUM_OVER          ; PE tests overflow from this subtraction.
    JP NUM_GOOD             ; The signed result fits in 24 bits.

; Negate C:HL in place.  B and DE are kept.
NUM_INV:
    XOR A                   ; Start a bytewise subtraction from zero.
    SUB L                   ; Compute the low byte of 0-HL.
    LD L,A
    LD A,0                  ; Propagate the borrow into the middle byte.
    SBC A,H
    LD H,A
    LD A,0                  ; And into the top byte.
    SBC A,C
    LD C,A
    RET

; Magnitude multiply. A shifted-out multiplicand bit is overflow only
; after the remaining multiplier has been shown nonzero.
; Unsigned shift/add product: C:HL=sum, B:DE=shifted left magnitude,
; NUM_MULT=remaining right magnitude. Each selected bit contributes B:DE to
; C:HL before the next shift.
NUM_IMUL:
    LD A,C                  ; Extract the left sign from its top byte.
    XOR B                   ; A differing right sign makes the product negative.
    AND 80H                 ; Retain only the product sign bit.
    LD (NUM_PNEG),A         ; Save the sign while multiplying unsigned magnitudes.
    BIT 7,C                 ; A negative left value needs two's-complement negation.
    CALL NZ,NUM_INV         ; 800000H remains the unsigned magnitude 8388608.
    EX DE,HL                ; Exchange the payloads and top bytes:
    LD A,B                  ; B:DE becomes the left magnitude
    LD B,C                  ; and C:HL the right value.
    LD C,A
    BIT 7,C                 ; Check the right operand sign.
    CALL NZ,NUM_INV         ; Convert it to an unsigned magnitude too.
    LD (NUM_MULT),HL        ; The multiplier is consumed from memory.
    LD A,C
    LD (NUM_MULT+2),A
    LD HL,0                 ; C:HL accumulates the unsigned product from zero.
    LD C,0
.LOOP:
    PUSH HL
    LD HL,(NUM_MULT+1)      ; Test all three multiplier bytes for zero.
    LD A,(NUM_MULT)
    OR H
    OR L
    POP HL
    JP Z,.DONE              ; Finish even when the multiplicand is large.
    LD A,(NUM_MULT)
    BIT 0,A                 ; The low multiplier bit selects this partial product.
    JP Z,.SHIFT             ; A zero bit contributes nothing to the sum.
    ADD HL,DE               ; Add the current shifted multiplicand to the product.
    LD A,C
    ADC A,B
    LD C,A
    JP C,NUM_OVER           ; A carry out of 24 bits already exceeds either bound.
.SHIFT:
    PUSH HL
    LD HL,NUM_MULT+2        ; Shift the multiplier right, top byte first.
    SRL (HL)
    DEC HL
    RR (HL)
    DEC HL
    RR (HL)
    LD A,(HL)               ; Check whether another multiplier bit remains.
    INC HL
    OR (HL)
    INC HL
    OR (HL)
    POP HL
    JP Z,.DONE              ; Avoid rejecting a shift that would never be used.
    SLA E                   ; Double the multiplicand, low byte first.
    RL D
    RL B                    ; Carry reports bit 23 leaving the magnitude.
    JP C,NUM_OVER           ; A lost high bit with more multiplier bits means overflow.
    JP .LOOP                ; Accumulate the next selected partial product.
.DONE:
    LD A,(NUM_PNEG)         ; Recover the sign of the mathematical product.
    OR A                    ; Zero selects the nonnegative result bound.
    JP Z,.POS               ; Positive magnitudes must be at most 8388607.
    LD A,C                  ; Negative magnitudes may reach exactly 8388608.
    CP 80H                  ; Compare the top byte against that boundary.
    JP C,.NEG               ; Anything below 800000H fits after negation.
    JP NZ,NUM_OVER          ; Anything above the boundary top byte overflows.
    LD A,H                  ; At top byte 80H, only a zero low word fits.
    OR L
    JP NZ,NUM_OVER          ; Reject magnitudes 800001H through 80FFFFH.
.NEG:
    CALL NUM_INV            ; Apply the negative sign, including 800000H -> 800000H.
    JP NUM_GOOD             ; Return the checked exact product.
.POS:
    BIT 7,C                 ; A set top bit exceeds the positive signed limit.
    JP NZ,NUM_OVER          ; Reject positive magnitudes of 8388608 or greater.
    JP NUM_GOOD             ; Return the nonnegative exact product.

; Convert the exact integer C:HL to decimal text, built backwards in NUM_BUF.
; HL returns the first byte and A and B the length, one to eight.
NUM_TEXT:
    LD A,C
    LD (NUM_PNEG),A         ; Keep the sign while the magnitude is divided.
    BIT 7,C
    CALL NZ,NUM_INV         ; 800000H stays 800000H, read as unsigned.
    LD DE,NUM_BUF+9         ; Digits are written backwards from the end.
.NEXT:
    CALL .DIV_TEN
    ADD A,'0'
    DEC DE
    LD (DE),A
    LD A,C
    OR H
    OR L
    JR NZ,.NEXT
    LD A,(NUM_PNEG)
    BIT 7,A
    JR Z,.SIZED
    DEC DE
    LD A,'-'
    LD (DE),A
.SIZED:
    LD HL,NUM_BUF+9
    OR A
    SBC HL,DE
    LD A,L                  ; The length is the distance written.
    LD B,A
    EX DE,HL                ; HL addresses the first byte.
    RET

; Divide C:HL by ten, unsigned: C:HL is the quotient and A the remainder.
.DIV_TEN:
    LD B,24
    XOR A
.BIT:
    ADD HL,HL
    RL C
    RLA
    CP 10
    JR C,.KEEP
    SUB 10
    INC L
.KEEP:
    DJNZ .BIT
    RET
