; string->number, in the numeric module because it uses the compiler's
; decimal parser, which image.asm includes after it.

; (string->number string [radix]).  Radix 10 uses the compiler's decimal
; parser, so text converts exactly as the same literal would: exact
; integers, and decimals and exponents correctly rounded to float24.  Radix
; 2, 8 and 16, given as an argument or a #b, #o or #x prefix, read exact
; integers.  Text that is not a number gives #f; an exact integer out of
; range is an error, as it is for a literal.
STD_S2N:
        LD A,(ARG_CNT)
        DEC A
        CP 2
        JP NC,ERROR
        XOR A
        LD (DEC_BASE),A            ; Decimal unless a radix is given.
        LD A,(ARG_CNT)
        CP 2
        JR C,.TEXT
        CALL PKT_ARG1
        CALL CV_BYTE
        LD B,1                     ; DEC_BASE is the bits per digit.
        CP 2
        JR Z,.BASE
        LD B,3
        CP 8
        JR Z,.BASE
        LD B,4
        CP 16
        JR Z,.BASE
        CP 10
        JP NZ,ERROR
        JR .TEXT
.BASE:
        LD A,B
        LD (DEC_BASE),A
.TEXT:
        CALL PKT_ARG0
        CALL STR_ARG
        JP C,ERROR
        LD C,(HL)                  ; DEC_READ takes the text and its length.
        LD B,0
        INC HL
        CALL DEC_READ
        PUSH AF
        XOR A
        LD (DEC_BASE),A            ; read and literals stay decimal.
        POP AF
        JR C,.FAIL
        PUSH IX                    ; A:CHL is the number, exact or float.
        RET
.FAIL:
        CP 130
        JP Z,ERROR                 ; An exact integer out of range.
        JP STD_NO
