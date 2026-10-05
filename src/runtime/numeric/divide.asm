; Exact integer division and remainder.
; Entry points: NUM_QUOT and NUM_REM; helper path: NUM_IDIV and .DIVIDE.
; Quotients truncate toward zero and remainders keep the dividend sign.
; Exact twenty-four-bit quotient and remainder of A:CHL by the cell NUM_Y.
; Both paths validate exact integer tags before checking the divisor or
; touching the operands.
NUM_QUOT:
    LD B,0                  ; Operation zero returns the quotient.
    JR NUM_IDIV             ; Share the signed magnitude division path.
NUM_REM:
    LD B,1                  ; Operation one returns the remainder.
NUM_IDIV:
    CALL NUM_LOAD           ; Save both values; the selector lands in NUM_OP.
    RET C
    LD A,(NUM_X+3)
    CP 3
    JP NZ,.BAD_TYPE
    LD A,(NUM_Y+3)
    CP 3
    JP NZ,.BAD_TYPE
    LD HL,(NUM_Y)
    LD A,(NUM_Y+2)
    OR H
    OR L
    JP Z,.BY_ZERO
    LD HL,(NUM_X)           ; The dividend's sign and magnitude.
    LD A,(NUM_X+2)
    LD C,A
    AND 80H
    LD (NUM_QNEG),A
    BIT 7,C
    CALL NZ,NUM_INV
    LD (NUM_NMAG),HL
    LD A,C
    LD (NUM_NMAG+2),A
    LD HL,(NUM_Y)           ; The divisor's sign and magnitude.
    LD A,(NUM_Y+2)
    LD C,A
    AND 80H
    LD (NUM_DNEG),A
    BIT 7,C
    CALL NZ,NUM_INV
    LD (NUM_DMAG),HL
    LD A,C
    LD (NUM_DMAG+2),A
    CALL .DIVIDE
    LD A,(NUM_OP)
    OR A
    JR NZ,.REM
    LD HL,(NUM_QMAG)
    LD A,(NUM_QMAG+2)
    LD C,A
    LD A,(NUM_QNEG)
    LD B,A
    LD A,(NUM_DNEG)
    XOR B
    AND 80H
    JR Z,.QUOT_POS
    LD A,C                  ; A negative quotient may reach magnitude 800000H.
    CP 80H
    JR C,.QUOT_NEG
    JR NZ,.OVER
    LD A,H
    OR L
    JR NZ,.OVER
.QUOT_NEG:
    CALL NUM_INV
    JP NUM_GOOD
.QUOT_POS:
    BIT 7,C
    JP NZ,.OVER
    JP NUM_GOOD
.REM:
    LD HL,(NUM_RMAG)
    LD A,(NUM_RMAG+2)
    LD C,A
    LD A,(NUM_QNEG)
    OR A
    JP Z,NUM_GOOD
    LD A,C
    OR H
    OR L
    JP Z,NUM_GOOD
    CALL NUM_INV
    JP NUM_GOOD
.BAD_TYPE:
    LD A,1
    JP NUM_FAIL
.BY_ZERO:
    LD A,3
    JP NUM_FAIL
.OVER:
    JP NUM_OVER

; Unsigned restoring division for two nonnegative 24-bit magnitudes.
.DIVIDE:
    XOR A
    LD HL,0
    LD (NUM_RMAG),HL
    LD (NUM_RMAG+2),A
    LD (NUM_QMAG),HL
    LD (NUM_QMAG+2),A
    LD A,24
    LD (NUM_CNT),A
.LOOP:
    LD HL,NUM_NMAG          ; Shift the dividend left; carry is its next bit.
    SLA (HL)
    INC HL
    RL (HL)
    INC HL
    RL (HL)
    LD HL,(NUM_RMAG)        ; Shift that bit into the partial remainder.
    LD A,(NUM_RMAG+2)
    LD C,A
    ADC HL,HL
    RL C
    LD DE,(NUM_DMAG)
    LD A,(NUM_DMAG+2)
    LD B,A
    OR A
    SBC HL,DE               ; Try subtracting the divisor.
    LD A,C
    SBC A,B
    JR C,.ZERO_BIT
    LD C,A
    LD (NUM_RMAG),HL
    LD A,C
    LD (NUM_RMAG+2),A
    CALL .QSHIFT
    LD HL,NUM_QMAG
    SET 0,(HL)              ; This quotient bit is one.
    JR .NEXT
.ZERO_BIT:
    ADD HL,DE               ; Restore the partial remainder after a failed test.
    LD (NUM_RMAG),HL
    LD A,C
    LD (NUM_RMAG+2),A
    CALL .QSHIFT            ; This quotient bit remains zero.
.NEXT:
    LD A,(NUM_CNT)
    DEC A
    LD (NUM_CNT),A
    JR NZ,.LOOP
    RET

; Shift the quotient magnitude left one bit.
.QSHIFT:
    LD HL,NUM_QMAG
    SLA (HL)
    INC HL
    RL (HL)
    INC HL
    RL (HL)
    RET
