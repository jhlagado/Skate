; Float24 addition, subtraction, multiplication and division.
; Entry points: F24_ADD, F24_SUB, F24_MUL and F24_DIV.
; Both operands are float cells, NUM_X and NUM_Y; the result returns in
; A:CHL with A=9 and carry clear.  Every result is rounded once.

F24_SUB:
    LD A,(NUM_Y+2)          ; x - y is x + (-y).
    XOR 80H
    LD (NUM_Y+2),A
F24_ADD:
    CALL F24_BOTH
    LD A,(F24_XC)
    CP 3
    JP Z,F24_NAN
    LD B,A
    LD A,(F24_YC)
    CP 3
    JP Z,F24_NAN
    LD C,A
    LD A,B
    CP 2
    JP Z,.X_INF
    LD A,C
    CP 2
    JP Z,F24_RETY           ; Finite plus infinity is that infinity.
    LD A,B
    OR A
    JP Z,.X_ZERO
    LD A,C
    OR A
    JP Z,F24_RETX           ; Adding zero changes nothing.
; Put the larger exponent in X.
    LD A,(F24_YU)
    LD B,A
    LD A,(F24_XU)
    CP B
    JR NC,.ALIGN
    LD HL,F24_XS            ; Exchange the five-byte X and Y fields.
    LD DE,F24_YS
    LD B,5
.SWAP:
    LD A,(DE)
    LD C,(HL)
    LD (HL),A
    LD A,C
    LD (DE),A
    INC HL
    INC DE
    DJNZ .SWAP
; Both significands gain three rounding bits; Y is aligned with sticky.
.ALIGN:
    LD A,(F24_XS)
    LD (F24_SIGN),A
    LD A,(F24_XU)
    SUB 16
    LD L,A
    LD H,0
    JR NC,.EXP_SET
    DEC H
.EXP_SET:
    LD (F24_EXP),HL
    LD HL,(F24_XM)          ; Guard X and keep it on the stack.
    LD A,(F24_XM+2)
    CALL F24_GRD
    LD HL,(F24_M)
    LD A,(F24_M+2)
    PUSH HL
    PUSH AF
    LD HL,(F24_YM)
    LD A,(F24_YM+2)
    CALL F24_GRD
    LD A,(F24_YU)
    LD B,A
    LD A,(F24_XU)
    SUB B                   ; The alignment distance, 0..141.
    JR Z,.ALIGNED
    CP 24
    JR C,.SHIFT_Y
    LD HL,1                 ; Every bit of Y is below the sticky position.
    LD (F24_M),HL
    XOR A
    LD (F24_M+2),A
    JR .ALIGNED
.SHIFT_Y:
    LD B,A
.SHIFT:
    CALL F24_SHR
    DJNZ .SHIFT
.ALIGNED:
    LD DE,(F24_M)           ; B:DE is aligned Y,
    LD A,(F24_M+2)
    LD B,A
    POP AF                  ; C:HL is guarded X.
    LD C,A
    POP HL
    LD A,(F24_YS)
    PUSH HL
    LD HL,F24_XS
    XOR (HL)
    POP HL
    JP NZ,.OPPOSITE
    ADD HL,DE
    LD A,C
    ADC A,B
    LD C,A
    JP F24_PUT
.OPPOSITE:
    OR A
    SBC HL,DE
    LD A,C
    SBC A,B
    LD C,A
    JR NC,.CANCEL
    CALL F24_INVM           ; Y had the larger magnitude.
    LD A,(F24_YS)
    LD (F24_SIGN),A
.CANCEL:
    LD A,C
    OR H
    OR L
    JP NZ,F24_PUT
    XOR A                   ; Exact cancellation is +0.
    LD (F24_SIGN),A
    JP F24_ZERO
.X_INF:
    LD A,C
    CP 2
    JP NZ,F24_RETX
    LD A,(F24_XS)           ; Two infinities: opposite signs give NaN.
    LD B,A
    LD A,(F24_YS)
    XOR B
    JP NZ,F24_NAN
    JP F24_RETX
.X_ZERO:
    LD A,C
    OR A
    JP NZ,F24_RETY
    LD A,(F24_XS)           ; Two zeros: negative only when both are.
    LD B,A
    LD A,(F24_YS)
    AND B
    LD (F24_SIGN),A
    JP F24_ZERO

; Return an operand cell unchanged.
F24_RETX:
    LD HL,(NUM_X)
    LD A,(NUM_X+2)
    LD C,A
    LD A,9
    OR A
    RET
F24_RETY:
    LD HL,(NUM_Y)
    LD A,(NUM_Y+2)
    LD C,A
    LD A,9
    OR A
    RET

; Store A:HL << 3 into F24_M: a significand with three rounding bits.
F24_GRD:
    LD C,A
    LD B,3
.LOOP:
    ADD HL,HL
    RL C
    DJNZ .LOOP
    LD (F24_M),HL
    LD A,C
    LD (F24_M+2),A
    RET

; Store C:HL in F24_M and pack it.
F24_PUT:
    LD (F24_M),HL
    LD A,C
    LD (F24_M+2),A
    JP F24_PACK

; Negate C:HL.
F24_INVM:
    XOR A
    SUB L
    LD L,A
    LD A,0
    SBC A,H
    LD H,A
    LD A,0
    SBC A,C
    LD C,A
    RET

; The product and quotient sign.
F24_XOR:
    LD A,(F24_XS)
    LD B,A
    LD A,(F24_YS)
    XOR B
    LD (F24_SIGN),A
    RET

; Reject NaN operands for multiplication and division; Z means the result
; is the canonical NaN.
F24_NANS:
    LD A,(F24_XC)
    CP 3
    RET Z
    LD A,(F24_YC)
    CP 3
    RET

F24_MUL:
    CALL F24_BOTH
    CALL F24_XOR
    CALL F24_NANS
    JP Z,F24_NAN
    LD A,(F24_XC)
    OR A
    JP Z,.X_ZERO
    CP 2
    JP Z,.X_INF
    LD A,(F24_YC)
    OR A
    JP Z,F24_ZERO
    CP 2
    JP Z,F24_INF
; value = XM*YM * 2^(XU+YU-190) = P * 2^(EXP-82), so EXP = XU+YU-108.
    LD A,(F24_XU)
    LD L,A
    LD H,0
    LD A,(F24_YU)
    LD E,A
    LD D,0
    ADD HL,DE
    LD DE,-108
    ADD HL,DE
    LD (F24_EXP),HL
    LD HL,F24_P             ; Clear the product and widen the multiplicand.
    LD B,10
    XOR A
.CLEAR:
    LD (HL),A
    INC HL
    DJNZ .CLEAR
    LD HL,(F24_XM)
    LD (F24_T),HL
    LD A,(F24_XM+2)
    LD (F24_T+2),A
    LD HL,(F24_YM)
    LD (F24_Q),HL
    LD A,(F24_YM+2)
    LD (F24_Q+2),A
    LD A,17
    LD (F24_CNT),A
.STEP:
    LD HL,F24_Q+2           ; The next multiplier bit, low end first.
    SRL (HL)
    DEC HL
    RR (HL)
    DEC HL
    RR (HL)
    JR NC,.DOUBLE
    LD HL,F24_P             ; P += T, five bytes.
    LD DE,F24_T
    LD B,5
    OR A
.ADD:
    LD A,(DE)
    ADC A,(HL)
    LD (HL),A
    INC HL
    INC DE
    DJNZ .ADD
.DOUBLE:
    LD HL,F24_T             ; T <<= 1, five bytes.
    LD B,5
    OR A
.SHL:
    RL (HL)
    INC HL
    DJNZ .SHL
    LD HL,F24_CNT
    DEC (HL)
    JR NZ,.STEP
; Reduce the product to 24 bits; a lost bit stays sticky.
.REDUCE:
    LD A,(F24_P+3)
    LD B,A
    LD A,(F24_P+4)
    OR B
    JR Z,.REDUCED
    LD HL,F24_P+4
    LD B,5
    OR A
.RIGHT:
    RR (HL)
    DEC HL
    DJNZ .RIGHT
    JR NC,.EXP_UP
    LD HL,F24_P
    SET 0,(HL)
.EXP_UP:
    LD HL,(F24_EXP)
    INC HL
    LD (F24_EXP),HL
    JR .REDUCE
.REDUCED:
    LD HL,(F24_P)
    LD A,(F24_P+2)
    LD C,A
    JP F24_PUT
.X_ZERO:
    LD A,(F24_YC)
    CP 2
    JP Z,F24_NAN            ; Zero times infinity.
    JP F24_ZERO
.X_INF:
    LD A,(F24_YC)
    OR A
    JP Z,F24_NAN            ; Infinity times zero.
    JP F24_INF

F24_DIV:
    CALL F24_BOTH
    CALL F24_XOR
    CALL F24_NANS
    JP Z,F24_NAN
    LD A,(F24_XC)
    OR A
    JP Z,.X_ZERO
    CP 2
    JP Z,.X_INF
    LD A,(F24_YC)
    OR A
    JP Z,F24_INF            ; Finite over zero.
    CP 2
    JP Z,F24_ZERO           ; Finite over infinity.
; value = Q * 2^-19 * 2^(XU-YU-scale) = Q * 2^(EXP-82): EXP = XU-YU+63-scale.
    LD A,(F24_XU)
    LD L,A
    LD H,0
    LD A,(F24_YU)
    LD E,A
    LD D,0
    OR A
    SBC HL,DE
    LD DE,63
    ADD HL,DE
    LD (F24_EXP),HL
    LD DE,(F24_YM)          ; B:DE is the divisor,
    LD A,(F24_YM+2)
    LD B,A
    LD HL,(F24_XM)          ; C:HL the remainder.
    LD A,(F24_XM+2)
    LD C,A
    PUSH HL                 ; A numerator below the divisor is doubled.
    OR A
    SBC HL,DE
    LD A,C
    SBC A,B
    POP HL
    JR NC,.START
    ADD HL,HL
    RL C
    PUSH HL
    LD HL,(F24_EXP)
    DEC HL
    LD (F24_EXP),HL
    POP HL
.START:
    XOR A
    LD (F24_M),A
    LD (F24_M+1),A
    LD (F24_M+2),A
    LD A,20                 ; Seventeen bits and three rounding bits.
    LD (F24_CNT),A
.STEP:
    PUSH HL                 ; Make room for the next quotient bit.
    LD HL,F24_M
    SLA (HL)
    INC HL
    RL (HL)
    INC HL
    RL (HL)
    POP HL
    OR A                    ; Try subtracting the divisor.
    SBC HL,DE
    LD A,C
    SBC A,B
    JR C,.RESTORE
    LD C,A
    PUSH HL
    LD HL,F24_M
    SET 0,(HL)
    POP HL
    JR .NEXT
.RESTORE:
    ADD HL,DE
.NEXT:
    ADD HL,HL
    RL C
    LD A,(F24_CNT)
    DEC A
    LD (F24_CNT),A
    JR NZ,.STEP
    LD A,C                  ; A nonzero remainder is sticky.
    OR H
    OR L
    JP Z,F24_PACK
    LD HL,F24_M
    SET 0,(HL)
    JP F24_PACK
.X_ZERO:
    LD A,(F24_YC)
    OR A
    JP Z,F24_NAN            ; Zero over zero.
    JP F24_ZERO
.X_INF:
    LD A,(F24_YC)
    CP 2
    JP Z,F24_NAN            ; Infinity over infinity.
    JP F24_INF
