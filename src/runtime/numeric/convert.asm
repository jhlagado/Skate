; Numeric negation and integer-to-float conversion.
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
    JP NZ,F24_NEG           ; A float uses float sign rules.
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

; Convert integer operands to floats in place, then run the float operation
; on the operand cells.
NUM_REAL:
    LD HL,NUM_X
    CALL .TO_FLOAT
    LD HL,NUM_Y
    CALL .TO_FLOAT
    LD A,(NUM_OP)           ; Select the float operation.
    OR A
    JP Z,F24_ADD
    DEC A
    JP Z,F24_SUB
    DEC A
    JP Z,F24_MUL
    JP F24_DIV

; Replace the integer in the cell at HL by the nearest float.
.TO_FLOAT:
    PUSH HL
    INC HL
    INC HL
    INC HL
    LD A,(HL)
    POP HL
    CP 3
    RET NZ                  ; A float stays as it is.
    PUSH HL
    LD E,(HL)
    INC HL
    LD D,(HL)
    INC HL
    LD C,(HL)
    EX DE,HL
    CALL F24_ITOF
    EX DE,HL
    POP HL
    LD (HL),E
    INC HL
    LD (HL),D
    INC HL
    LD (HL),C
    INC HL
    LD (HL),9
    RET
