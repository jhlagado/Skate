; Decimal wide-integer helpers for scaling, shifting, comparison and subtraction.
; Entry points: DEC_BYTE, DEC_MUL, DEC_SHL, DEC_SHR, DEC_CMP and DEC_SUB.
DEC_BYTE:   LD HL,(DEC_SRCP)         ; Recover the next input address.
        LD A,(HL)
        INC HL
        LD (DEC_SRCP),HL         ; Save the next input address.
        LD HL,DEC_LEFT
        DEC (HL)
        RET
; Compare the five remaining bytes with the chosen canonical special token.
DEC_SAME: LD B,5
; Compare all five bytes, stopping at the first difference; preserve its zero flag.
.LOOP: LD A,(DE)
        CP (HL)
        RET NZ
        INC DE
        INC HL
        DJNZ .LOOP
        RET
; Multiply a 40-byte little-endian integer at HL by ten. Each limb product
; is at most 2550+9. C carries the next decimal multiplication carry;
; DE holds widened addends and HL temporarily holds the limb product.
DEC_MUL:   LD B,40
        LD C,0
; Widen one byte before multiplying, then store its low byte and retain carry in C.
.LOOP: LD A,(HL)
        PUSH HL             ; HL becomes the widened limb product temporarily.
        LD L,A
        LD H,0
        ADD HL,HL
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD E,C
        LD D,0
        ADD HL,DE
        LD A,L
        LD C,H
        POP HL
        LD (HL),A
        INC HL
        DJNZ .LOOP
        RET
; Wide shifts propagate each bit through carry; INC/DEC HL and DJNZ preserve it.
DEC_SHL:   LD B,40
        OR A                ; Start with a zero incoming low bit.
; Carry transfers the previous limb’s top bit into this limb’s low bit.
.LOOP: RL (HL)
        INC HL
        DJNZ .LOOP
        RET
DEC_SHR:   LD B,40
        OR A
; Carry transfers the previous limb’s low bit into this limb’s top bit.
.LOOP: RR (HL)
        DEC HL
        DJNZ .LOOP
        RET
; Compare numerator X with denominator Y, most-significant limb first.
; Carry means X<Y, zero means equality. No integer is modified.
DEC_CMP:   LD HL,DEC_NUM+39
        LD DE,DEC_DEN+39
        LD B,40
; The first unequal high limb decides the ordering of the complete integers.
.LOOP: LD A,(DE)
        LD C,A
        LD A,(HL)
        CP C
        RET NZ
        DEC HL
        DEC DE
        DJNZ .LOOP
        RET
; X := X-Y after comparison proved X>=Y. Borrow crosses every byte intact.
DEC_SUB:   LD HL,DEC_NUM            ; Select the numerator limbs for the wide operation.
        LD DE,DEC_DEN
        LD B,40
        OR A
; Subtract one denominator limb and the incoming borrow from the numerator limb.
.LOOP: LD A,(DE)
        LD C,A
        LD A,(HL)
        SBC A,C
        LD (HL),A
        INC HL
        INC DE
        DJNZ .LOOP
        RET
DEC_INF0:  DB "inf.0"
