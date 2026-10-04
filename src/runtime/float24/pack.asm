; Float24 normalisation, rounding and result construction.
; Entry points: F24_PACK, F24_ZERO, F24_INF, F24_NAN and F24_SHR.
;
; F24_M holds a guarded magnitude whose value is M * 2^(F24_EXP - 82): with
; the leading one at bit 19, F24_EXP is the biased exponent and bits 2..0 are
; guard, round and sticky.  F24_SIGN is the result sign.  Every exit returns
; the float in A:CHL with A=9 and carry clear.
F24_PACK:
    LD HL,(F24_M)
    LD A,(F24_M+2)
    OR H
    OR L
    JP Z,F24_ZERO
; A leading one above bit 19 moves down with a sticky shift.
.BIG:
    LD A,(F24_M+2)
    AND 0F0H
    JR Z,.SMALL
    CALL F24_SHR
    CALL .INC_EXP
    JR .BIG
; A leading one below bit 19 moves up exactly.
.SMALL:
    LD A,(F24_M+2)
    BIT 3,A
    JR NZ,.RANGE
    LD HL,F24_M
    SLA (HL)
    INC HL
    RL (HL)
    INC HL
    RL (HL)
    LD HL,(F24_EXP)
    DEC HL
    LD (F24_EXP),HL
    JR .SMALL
; Exponents of zero and below become subnormals; 127 and above overflow.
.RANGE:
    LD HL,(F24_EXP)
    BIT 7,H
    JR NZ,.SUBNORM
    LD A,H
    OR L
    JR Z,.SUBNORM
    LD A,H
    OR A
    JP NZ,F24_INF
    LD A,L
    CP 127
    JP NC,F24_INF
    JR .ROUND
; Shift to the scale of exponent 1, keeping every lost bit as sticky.
.SUBNORM:
    EX DE,HL                ; Shift distance is 1 - F24_EXP.
    LD HL,1
    OR A
    SBC HL,DE
    LD A,H
    OR A
    JR NZ,.GONE
    LD A,L
    CP 24
    JR NC,.GONE
    LD B,A
.SUB_SHR:
    CALL F24_SHR
    DJNZ .SUB_SHR
    JR .SCALED
.GONE:
    LD HL,1                 ; Only the sticky bit of a nonzero value remains.
    LD (F24_M),HL
    XOR A
    LD (F24_M+2),A
.SCALED:
    LD HL,1
    LD (F24_EXP),HL
; Round to nearest even: add 3 plus the retained low bit, drop three bits.
.ROUND:
    LD HL,(F24_M)
    LD A,(F24_M+2)
    LD C,A
    LD DE,3
    BIT 3,L
    JR Z,.BIAS
    INC E
.BIAS:
    ADD HL,DE
    LD A,C
    ADC A,0
    LD C,A
    LD B,3
.DROP:
    SRL C
    RR H
    RR L
    DJNZ .DROP
    BIT 1,C                 ; Rounding carried into bit 17.
    JR Z,.ENCODE
    SRL C
    RR H
    RR L
    PUSH HL
    CALL .INC_EXP
    POP HL
; A normal result drops its implicit bit and stores the exponent.
.ENCODE:
    LD A,(F24_EXP+1)
    OR A
    JP NZ,F24_INF
    LD A,(F24_EXP)
    CP 127
    JP NC,F24_INF
    BIT 0,C
    LD C,0
    JR Z,.SIGN              ; A subnormal has exponent field zero.
    LD C,A
.SIGN:
    LD A,(F24_SIGN)
    OR C
    LD C,A
    LD A,9
    OR A
    RET

.INC_EXP:
    LD HL,(F24_EXP)
    INC HL
    LD (F24_EXP),HL
    RET

; A zero with the selected sign.
F24_ZERO:
    LD A,(F24_SIGN)
    LD C,A
    LD HL,0
    LD A,9
    OR A
    RET

; An infinity with the selected sign.
F24_INF:
    LD A,(F24_SIGN)
    OR 7FH
    LD C,A
    LD HL,0
    LD A,9
    OR A
    RET

; The canonical NaN.
F24_NAN:
    LD C,7FH
    LD HL,8000H
    LD A,9
    OR A
    RET

; Shift F24_M right one place, keeping a discarded one in bit 0.
F24_SHR:
    LD HL,F24_M+2
    SRL (HL)
    DEC HL
    RR (HL)
    DEC HL
    RR (HL)
    RET NC
    SET 0,(HL)
    RET
