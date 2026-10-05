; Float24 integer conversion.
; Entry points: F24_ITOF and F24_FTOI.

; Convert the signed twenty-four-bit integer C:HL to a float in A:CHL,
; rounding to nearest even.
F24_ITOF:
    LD A,C
    AND 80H
    LD (F24_SIGN),A
    JR Z,.MAG
    CALL F24_INVM           ; -800000H stays 800000H, read unsigned.
.MAG:
    LD A,C
    OR H
    OR L
    JR NZ,.SCALE
    LD (F24_SIGN),A         ; Integer zero is +0.
    JP F24_ZERO
.SCALE:
    LD (F24_M),HL           ; value = M * 2^(82-82).
    LD A,C
    LD (F24_M+2),A
    LD HL,82
    LD (F24_EXP),HL
    JP F24_PACK

; Truncate the float A:CHL toward zero into the signed integer C:HL with
; carry clear.  Infinity, NaN and magnitudes beyond the integer range fail
; with A=2 and carry set.
F24_FTOI:
    CALL F24_OPEN
    LD E,A                  ; The biased exponent.
    LD A,B
    CP 2
    JR NC,.NO_FIT
    OR A
    JR Z,.DONE              ; Zero, with C:HL already clear.
    LD A,E
    SUB 95                  ; value = M * 2^(U-95).
    JR C,.RIGHT
    CP 8
    JR NC,.NO_FIT
    OR A
    JR Z,.SIGNED
    LD B,A
.LEFT:
    ADD HL,HL
    RL C
    DJNZ .LEFT
    BIT 7,C                 ; 2^23 fits only as -8388608.
    JR Z,.SIGNED
    LD A,D
    OR A
    JR Z,.NO_FIT
    LD A,C
    CP 80H
    JR NZ,.NO_FIT
    LD A,H
    OR L
    JR NZ,.NO_FIT
    JR .SIGNED
.RIGHT:
    NEG
    CP 17
    JR NC,.ZERO
    LD B,A
.DROP:
    SRL C
    RR H
    RR L
    DJNZ .DROP
.SIGNED:
    LD A,D
    OR A
    CALL NZ,F24_INVM
.DONE:
    OR A
    RET
.ZERO:
    LD C,0
    LD HL,0
    OR A
    RET
.NO_FIT:
    LD A,2
    SCF
    RET
