; Numeric negation and integer-to-binary16 conversion.
; Entry points: NUM_NEG and the arithmetic conversion path NUM_REAL.
; NUM_FLIP is the shared modular word helper for comparison codes.
; Public unary negation of A:CHL. The exact range is asymmetric around zero.
NUM_NEG:
    LD (NUM_ORIG),HL        ; Save the unary input for an overflow return.
    LD B,A
    LD A,C
    LD (NUM_ORIG+2),A
    LD A,B
    CALL NUM_CHK            ; Reject nonnumbers before inspecting representation.
    RET C                   ; Classification preserves HL on failure.
    CP 3                    ; Select integer negation only for tag 3.
    JP NZ,F16_NEG           ; A numeric scalar uses binary16 sign rules.
    LD A,C                  ; Check for the unique integer with no positive opposite.
    CP 80H                  ; Its top byte is 80H.
    JP NZ,.INT              ; Every other top byte permits negation.
    LD A,H                  ; Distinguish 800000H from the other 80xxxxH values.
    OR L                    ; Only 800000H has a zero low word.
    JP Z,NUM_OVER           ; Negating -8388608 would exceed +8388607.
.INT:
    CALL NUM_INV            ; Negate the signed value in place.
    JP NUM_GOOD             ; Return it with exact tag 3.
; Private modular word negation. HL changes; BC/DE are preserved.
; The low-byte borrow is propagated explicitly into the high-byte subtraction.
NUM_FLIP:
    XOR A                   ; Start a bytewise subtraction from zero.
    SUB L                   ; Compute the low byte of 0-HL.
    LD L,A                  ; Store it while retaining the low-byte borrow.
    SBC A,A                 ; Turn that borrow into 00H or FFH.
    SUB H                   ; Complete the high byte: 0-H-borrow, modulo 256.
    LD H,A                  ; HL now holds the two's-complement opposite.
    RET                     ; DE and BC are unchanged by this helper.

; Round integer inputs only after both original values pass classification,
; then run the binary16 operation.  A float result has byte 2 zero.
NUM_REAL:
    LD HL,(NUM_X)           ; Reload the original left value.
    LD A,(NUM_X+2)
    LD C,A
    LD A,(NUM_X+3)          ; Test whether it needs integer-to-float conversion.
    CP 3                    ; Tag 3 selects the raw signed conversion.
    CALL Z,F16_ITOF         ; Round an exact integer to binary16, ties to even.
    LD (NUM_X),HL           ; Save the converted left across the right conversion.
    LD HL,(NUM_Y)           ; Load the original right value.
    LD A,(NUM_Y+2)
    LD C,A
    LD A,(NUM_Y+3)          ; Test the right representation independently.
    CP 3                    ; Tag 3 again requires conversion.
    CALL Z,F16_ITOF         ; Leave an existing float unchanged.
    EX DE,HL                ; Place the right float in the binary16 DE register.
    LD HL,(NUM_X)           ; Restore the left float in HL.
    LD B,0                  ; The right operand is now tag 0.
    LD A,(NUM_OP)           ; Recover the selected arithmetic operation.
    OR A
    JR Z,.ADD
    DEC A
    JR Z,.SUB
    DEC A
    JR Z,.MUL
    XOR A                   ; The left operand is now tag 0 too.
    CALL F16_DIV            ; Operation 3 is division.
    JR .DONE
.MUL:
    XOR A
    CALL F16_MUL
    JR .DONE
.SUB:
    XOR A
    CALL F16_SUB
    JR .DONE
.ADD:
    XOR A
    CALL F16_ADD
.DONE:
    LD C,0                  ; A binary16 result has byte 2 zero; flags are kept.
    RET NC
    JP NUM_FAIL             ; A floating failure also exposes the original left.
