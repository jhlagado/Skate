; Decimal wide-integer helpers for scaling, shifting, comparison and subtraction.
; Entry points: DGETBYTE, DMULTEN, DSHIFTL, DSHIFTR, DCOMPARE and DSUBVAL.
DGETBYTE:   LD HL,(DPTRNEXT)         ; Recover the next input address.
        LD A,(HL)
        INC HL
        LD (DPTRNEXT),HL         ; Save the next input address.
        LD HL,DREMAIN
        DEC (HL)
        RET
; Compare the five remaining bytes with the chosen canonical special token.
DMATCH: LD B,5
; Compare all five bytes, stopping at the first difference; preserve its zero flag.
DMATCHLP: LD A,(DE)
        CP (HL)
        RET NZ
        INC DE
        INC HL
        DJNZ DMATCHLP
        RET
; Multiply a 40-byte little-endian integer at HL by ten. Each limb product
; is at most 2550+9. C carries the next decimal multiplication carry;
; DE holds widened addends and HL temporarily holds the limb product.
DMULTEN:   LD B,40
        LD C,0
; Widen one byte before multiplying, then store its low byte and retain carry in C.
DMULTLP: LD A,(HL)
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
        DJNZ DMULTLP
        RET
; Wide shifts propagate each bit through carry; INC/DEC HL and DJNZ preserve it.
DSHIFTL:   LD B,40
        OR A                ; Start with a zero incoming low bit.
; Carry transfers the previous limb’s top bit into this limb’s low bit.
DSHFTLP: RL (HL)
        INC HL
        DJNZ DSHFTLP
        RET
DSHIFTR:   LD B,40
        OR A
; Carry transfers the previous limb’s low bit into this limb’s top bit.
DSHFTRP: RR (HL)
        DEC HL
        DJNZ DSHFTRP
        RET
; Compare numerator X with denominator Y, most-significant limb first.
; Carry means X<Y, zero means equality. No integer is modified.
DCOMPARE:   LD HL,DNUMERAT+39
        LD DE,DDENOMIN+39
        LD B,40
; The first unequal high limb decides the ordering of the complete integers.
DCMPLOOP: LD A,(DE)
        LD C,A
        LD A,(HL)
        CP C
        RET NZ
        DEC HL
        DEC DE
        DJNZ DCMPLOOP
        RET
; X := X-Y after comparison proved X>=Y. Borrow crosses every byte intact.
DSUBVAL:   LD HL,DNUMERAT           ; Select the numerator limbs for the wide operation.
        LD DE,DDENOMIN
        LD B,40
        OR A
; Subtract one denominator limb and the incoming borrow from the numerator limb.
DSUBLOOP: LD A,(DE)
        LD C,A
        LD A,(HL)
        SBC A,C
        LD (HL),A
        INC HL
        INC DE
        DJNZ DSUBLOOP
        RET
DINFSTR:  DB "inf.0"
