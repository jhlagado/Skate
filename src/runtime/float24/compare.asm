; Float24 comparison.
; Entry point: F24_CMP.  Compare the float cells NUM_X and NUM_Y and return
; the raw code in HL: FFFFH less, 0 equal, 1 greater, 2 unordered; A=0,
; C=0 and carry clear.
F24_CMP:
    CALL F24_BOTH
    LD A,(F24_XC)
    CP 3
    JR Z,.NAN
    LD B,A
    LD A,(F24_YC)
    CP 3
    JR Z,.NAN
    OR B
    JR Z,.SAME              ; +0 and -0 are equal.
    LD A,(F24_XS)
    LD B,A
    LD A,(F24_YS)
    CP B
    JR NZ,.BY_SIGN
; Equal signs: the encodings order like the magnitudes.
    LD HL,(NUM_X)
    LD DE,(NUM_Y)
    LD A,(NUM_Y+2)
    AND 7FH
    LD B,A
    LD A,(NUM_X+2)
    AND 7FH
    LD C,A
    OR A
    SBC HL,DE
    LD A,C
    SBC A,B
    JR C,.BELOW
    OR H
    OR L
    JR Z,.SAME
    LD A,(F24_XS)           ; The left magnitude is larger.
    OR A
    JR NZ,.LESS
    JR .MORE
.BELOW:
    LD A,(F24_XS)
    OR A
    JR NZ,.MORE
    JR .LESS
.BY_SIGN:
    LD A,(F24_XS)
    OR A
    JR NZ,.LESS
.MORE:
    LD HL,1
    JR .DONE
.LESS:
    LD HL,0FFFFH
    JR .DONE
.SAME:
    LD HL,0
    JR .DONE
.NAN:
    LD HL,2
.DONE:
    XOR A
    LD C,A
    RET
