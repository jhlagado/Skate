; Exact integer division and remainder.
; Entry points: NQUOT and NREM; helper path: NIDIV and NIDRUN.
; Quotients truncate toward zero and remainders keep the dividend sign.
; Exact signed16 quotient and remainder.  The public quotient truncates toward
; zero; the remainder keeps the dividend's sign.  Both paths validate exact
; integer tags before checking the divisor or touching the operands.
NQUOT:
    LD (NIDLT),A            ; Preserve the caller's left representation tag.
    XOR A                   ; Operation zero returns the quotient.
    JR NIDIV                ; Share the signed magnitude division path.
NREM:
    LD (NIDLT),A            ; Preserve the caller's left representation tag.
    LD A,1                  ; Operation one returns the remainder.
NIDIV:
    LD (NIDOP),A            ; Preserve the selected result across validation.
    LD A,B                  ; Retain the right representation tag.
    LD (NIDRT),A
    LD (NIDLEFT),HL         ; Preserve the original left payload for errors.
    LD (NORIGVAL),HL        ; The shared error exit returns that original word.
    LD (NIDRIGHT),DE        ; Preserve the original right payload as well.
    JR NIDIVCHK

; Front ends preserve both tags before selecting the shared operation.
NIDIVCHK:
    LD A,(NIDLT)
    CP 3
    JP NZ,NIDTYPE
    LD A,(NIDRT)
    CP 3
    JP NZ,NIDTYPE
    LD HL,(NIDLEFT)
    LD DE,(NIDRIGHT)
    LD A,D
    OR E
    JP Z,NIDZERO
    LD A,H
    AND 80H
    LD (NIDSIGN),A
    BIT 7,H
    CALL NZ,NWORDNEG
    LD (NIDNUM),HL
    EX DE,HL
    LD A,H
    AND 80H
    LD (NIDRSIGN),A
    BIT 7,H
    CALL NZ,NWORDNEG
    LD (NIDDIV),HL
    CALL NIDRUN
    LD A,(NIDOP)
    OR A
    JR NZ,NIDREST
    LD HL,(NIDQUO)
    LD A,(NIDSIGN)
    LD B,A
    LD A,(NIDRSIGN)
    XOR B
    AND 80H
    LD (NIDSIGN),A
    OR A
    JR Z,NIDQPOS
    LD A,H
    CP 80H
    JR C,NIDQNEG
    JR NZ,NIDOVF
    LD A,L
    OR A
    JR NZ,NIDOVF
NIDQNEG:
    CALL NWORDNEG
    JP NINTGOOD
NIDQPOS:
    BIT 7,H
    JP NZ,NIDOVF
    JP NINTGOOD
NIDREST:
    LD HL,(NIDREM)
    LD A,(NIDSIGN)
    OR A
    JP Z,NINTGOOD
    LD A,H
    OR L
    JP Z,NINTGOOD
    CALL NWORDNEG
    JP NINTGOOD
NIDTYPE:
    LD A,1
    JP NERRRET
NIDZERO:
    LD A,3
    JP NERRRET
NIDOVF:
    JP NOVERFLW

; Unsigned restoring division for two nonnegative 16-bit magnitudes.
NIDRUN:
    LD HL,0
    LD (NIDREM),HL
    LD (NIDQUO),HL
    LD A,16
    LD (NIDCNT),A
NIDLOOP:
    LD HL,(NIDNUM)
    ADD HL,HL               ; Carry is the next dividend bit.
    LD (NIDNUM),HL
    LD HL,(NIDREM)
    ADC HL,HL               ; Shift that bit into the partial remainder.
    LD DE,(NIDDIV)
    OR A
    SBC HL,DE
    JR C,NIDBIT0
    LD (NIDREM),HL
    LD HL,(NIDQUO)
    ADD HL,HL
    INC L                   ; This quotient bit is one.
    LD (NIDQUO),HL
    JR NIDNEXT
NIDBIT0:
    ADD HL,DE               ; Restore the partial remainder after a failed test.
    LD (NIDREM),HL
    LD HL,(NIDQUO)
    ADD HL,HL               ; This quotient bit remains zero.
    LD (NIDQUO),HL
NIDNEXT:
    LD A,(NIDCNT)
    DEC A
    LD (NIDCNT),A
    JR NZ,NIDLOOP
    RET
