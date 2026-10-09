; string->number, in the numeric module because it uses the compiler's
; decimal parser, which image.asm includes after it.

; (string->number string [radix]).  Radix 10 uses the compiler's decimal
; parser, so text converts exactly as the same literal would: exact
; integers, and decimals and exponents correctly rounded to float24.  Radix
; 2, 8 and 16 read exact integers.  Text that is not a number gives #f; an
; exact integer out of range is an error, as it is for a literal.
STD_S2N:
        LD A,(ARG_CNT)
        DEC A
        CP 2
        JP NC,ERROR
        LD A,10
        LD (CV_RAD),A
        LD A,(ARG_CNT)
        CP 2
        JR C,.TEXT
        CALL PKT_ARG1
        CALL CV_BYTE
        LD (CV_RAD),A
        CP 2
        JR Z,.TEXT
        CP 8
        JR Z,.TEXT
        CP 10
        JR Z,.TEXT
        CP 16
        JP NZ,ERROR
.TEXT:
        CALL PKT_ARG0
        CALL STR_ARG
        JP C,ERROR
        LD A,(CV_RAD)
        CP 10
        JR NZ,.RADIX
        LD C,(HL)                  ; DEC_READ takes the text and its length.
        LD B,0
        INC HL
        CALL DEC_READ
        JR C,.FAIL
        PUSH IX                    ; A:CHL is the number, exact or float.
        RET
.FAIL:
        CP 130
        JP Z,ERROR                 ; An exact integer out of range.
        JP STD_NO
.RADIX:
        LD A,(HL)
        LD (STD_CNT),A
        INC HL
        LD (STD_PTR),HL
        XOR A
        LD (CV_NEG),A
        LD A,(STD_CNT)
        CP 2
        JR C,.DIGITS               ; A lone sign is not a number.
        LD A,(HL)
        CP '+'
        JR Z,.SIGN
        CP '-'
        JR NZ,.DIGITS
        LD (CV_NEG),A
.SIGN:
        INC HL
        LD (STD_PTR),HL
        LD HL,STD_CNT
        DEC (HL)
.DIGITS:
        LD A,(STD_CNT)
        OR A
        JP Z,STD_NO                ; No digits.
        LD HL,0                    ; C:HL accumulates the magnitude.
        LD C,L
.NEXT:
        PUSH HL
        LD HL,(STD_PTR)
        LD A,(HL)
        INC HL
        LD (STD_PTR),HL
        POP HL
        LD B,A                     ; Keep the character for the error checks.
        SUB '0'
        CP 10
        JR C,.VALUE
        LD A,B
        OR 20H
        SUB 'a'
        CP 6
        JR NC,.OTHER
        ADD A,10
.VALUE:
        LD E,A
        LD A,(CV_RAD)
        DEC A
        CP E
        JR C,.OTHER                ; Not a digit in this radix.
        PUSH DE
        LD (CV_T),HL               ; Multiply C:HL by the radix.
        LD A,C
        LD (CV_T+2),A
        LD HL,0
        LD C,L
        LD A,(CV_RAD)
        LD B,A
.TIMES:
        LD DE,(CV_T)
        ADD HL,DE
        LD A,(CV_T+2)
        ADC A,C
        JP C,ERROR                 ; Beyond 24 bits.
        LD C,A
        DJNZ .TIMES
        POP DE
        LD D,0
        ADD HL,DE
        LD A,C
        ADC A,D
        JP C,ERROR
        LD C,A
        LD A,(STD_CNT)
        DEC A
        LD (STD_CNT),A
        JR NZ,.NEXT
        LD A,C                     ; The magnitude must fit: 8388607, or
        CP 80H                     ; 8388608 when negative.
        JR C,.FITS
        JP NZ,ERROR
        LD A,H
        OR L
        JP NZ,ERROR
        LD A,(CV_NEG)
        OR A
        JP Z,ERROR
.FITS:
        LD A,(CV_NEG)
        OR A
        JR Z,.EXACT
        LD A,L                     ; Negate C:HL.
        CPL
        LD L,A
        LD A,H
        CPL
        LD H,A
        LD A,C
        CPL
        LD C,A
        LD DE,1
        ADD HL,DE
        LD A,C
        ADC A,D
        LD C,A
.EXACT:
        LD A,3
        PUSH IX
        RET
.OTHER:
        JP STD_NO                  ; Not a digit in this radix.

CV_RAD:  DB 0                      ; Radix of string->number.
CV_NEG:  DB 0                      ; Nonzero for a leading minus sign.
CV_T:    DS 3                      ; The magnitude being multiplied.
