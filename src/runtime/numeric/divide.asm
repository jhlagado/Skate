; Exact integer division and remainder.
; Entry points: NUM_QUOT and NUM_REM; helper path: NUM_IDIV and .DIVIDE.
; Quotients truncate toward zero and remainders keep the dividend sign.
; Exact signed16 quotient and remainder.  The public quotient truncates toward
; zero; the remainder keeps the dividend's sign.  Both paths validate exact
; integer tags before checking the divisor or touching the operands.
NUM_QUOT:
    LD (NUM_NTAG),A         ; Preserve the caller's left representation tag.
    XOR A                   ; Operation zero returns the quotient.
    JR NUM_IDIV             ; Share the signed magnitude division path.
NUM_REM:
    LD (NUM_NTAG),A         ; Preserve the caller's left representation tag.
    LD A,1                  ; Operation one returns the remainder.
NUM_IDIV:
    LD (NUM_WANT),A         ; Preserve the selected result across validation.
    LD A,B                  ; Retain the right representation tag.
    LD (NUM_DTAG),A
    LD (NUM_NARG),HL        ; Preserve the original left payload for errors.
    LD (NUM_ORIG),HL        ; The shared error exit returns that original word.
    LD (NUM_DARG),DE        ; Preserve the original right payload as well.
    JR .CHECK

; Front ends preserve both tags before selecting the shared operation.
.CHECK:
    LD A,(NUM_NTAG)
    CP 3
    JP NZ,.BAD_TYPE
    LD A,(NUM_DTAG)
    CP 3
    JP NZ,.BAD_TYPE
    LD HL,(NUM_NARG)
    LD DE,(NUM_DARG)
    LD A,D
    OR E
    JP Z,.BY_ZERO
    LD A,H
    AND 80H
    LD (NUM_QNEG),A
    BIT 7,H
    CALL NZ,NUM_FLIP
    LD (NUM_NMAG),HL
    EX DE,HL
    LD A,H
    AND 80H
    LD (NUM_DNEG),A
    BIT 7,H
    CALL NZ,NUM_FLIP
    LD (NUM_DMAG),HL
    CALL .DIVIDE
    LD A,(NUM_WANT)
    OR A
    JR NZ,.REM
    LD HL,(NUM_QMAG)
    LD A,(NUM_QNEG)
    LD B,A
    LD A,(NUM_DNEG)
    XOR B
    AND 80H
    LD (NUM_QNEG),A
    OR A
    JR Z,.QUOT_POS
    LD A,H
    CP 80H
    JR C,.QUOT_NEG
    JR NZ,.OVER
    LD A,L
    OR A
    JR NZ,.OVER
.QUOT_NEG:
    CALL NUM_FLIP
    JP NUM_GOOD
.QUOT_POS:
    BIT 7,H
    JP NZ,.OVER
    JP NUM_GOOD
.REM:
    LD HL,(NUM_RMAG)
    LD A,(NUM_QNEG)
    OR A
    JP Z,NUM_GOOD
    LD A,H
    OR L
    JP Z,NUM_GOOD
    CALL NUM_FLIP
    JP NUM_GOOD
.BAD_TYPE:
    LD A,1
    JP NUM_FAIL
.BY_ZERO:
    LD A,3
    JP NUM_FAIL
.OVER:
    JP NUM_OVER

; Unsigned restoring division for two nonnegative 16-bit magnitudes.
.DIVIDE:
    LD HL,0
    LD (NUM_RMAG),HL
    LD (NUM_QMAG),HL
    LD A,16
    LD (NUM_CNT),A
.LOOP:
    LD HL,(NUM_NMAG)
    ADD HL,HL               ; Carry is the next dividend bit.
    LD (NUM_NMAG),HL
    LD HL,(NUM_RMAG)
    ADC HL,HL               ; Shift that bit into the partial remainder.
    LD DE,(NUM_DMAG)
    OR A
    SBC HL,DE
    JR C,.ZERO_BIT
    LD (NUM_RMAG),HL
    LD HL,(NUM_QMAG)
    ADD HL,HL
    INC L                   ; This quotient bit is one.
    LD (NUM_QMAG),HL
    JR .NEXT
.ZERO_BIT:
    ADD HL,DE               ; Restore the partial remainder after a failed test.
    LD (NUM_RMAG),HL
    LD HL,(NUM_QMAG)
    ADD HL,HL               ; This quotient bit remains zero.
    LD (NUM_QMAG),HL
.NEXT:
    LD A,(NUM_CNT)
    DEC A
    LD (NUM_CNT),A
    JR NZ,.LOOP
    RET
