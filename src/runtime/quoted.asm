; Quoted lists stored as encoded data and built on first use.
;
; Generated code for a quoted list is CALL QT_BUILD followed by
;
;     DW cache      a four-byte static cell holding the built list
;     DW end        the address after the encoding, where execution resumes
;     encoding      one value, as below
;
; The first evaluation decodes the value, stores it in the cache and returns
; it in A:HL; later evaluations return the cached value.  Elements are pushed
; on the quoted-data stack, which is a collector root, and folded into pairs
; by SRTQBLD, exactly as the code the compiler used to emit did.
;
; Encoding of one value:
;     01 values... 02    a proper list
;     01 values... 03    a dotted list; the last value is the tail
;     04 lo hi tag       any immediate value
;     05 n               the exact integer n, 0..255
;     06 lo hi           a symbol literal
;     07 lo hi           a string literal

QT_LIST  EQU 1
QT_END   EQU 2
QT_DOT   EQU 3
QT_IMM   EQU 4
QT_BYTE  EQU 5

QT_BUILD:
        POP HL                     ; The cache word follows the CALL.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                  ; The end address follows it.
        INC HL
        LD B,(HL)
        INC HL
        LD (QT_PTR),HL
        PUSH BC                    ; Return past the encoding.
        PUSH DE
        EX DE,HL
        CALL SRTQGET               ; A hit returns the cached value.
        POP DE
        RET NC
        PUSH DE
        CALL QT_VALUE
        POP DE
        JP SRTSTORE                ; Cache the value; A:HL is returned.

; Decode one value at QT_PTR into A:HL.
QT_VALUE:
        LD HL,(QT_PTR)
        LD A,(HL)
        INC HL
        LD (QT_PTR),HL
        CP QT_LIST
        JR Z,.LIST
        CP QT_BYTE
        JR Z,.BYTE
        CP QT_IMM
        JR Z,.IMM
        SUB 2                      ; Codes 6 and 7 are tags 4 and 5.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (QT_PTR),HL
        EX DE,HL
        RET
.BYTE:
        LD L,(HL)
        LD H,0
        LD A,3
        LD DE,(QT_PTR)
        INC DE
        LD (QT_PTR),DE
        RET
.IMM:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        INC HL
        LD (QT_PTR),HL
        EX DE,HL
        RET
.LIST:
        LD B,0                     ; Elements pushed so far.
.ELEMENT:
        LD HL,(QT_PTR)
        LD A,(HL)
        CP QT_END
        JR Z,.CLOSE
        CP QT_DOT
        JR Z,.CLOSE
        PUSH BC
        CALL QT_VALUE
        CALL SRTQPUT
        POP BC
        INC B
        JR .ELEMENT
.CLOSE:
        INC HL
        LD (QT_PTR),HL
        SUB QT_END                 ; Zero for a proper list, one for dotted.
        LD C,A
        LD A,B
        LD B,C
        JP SRTQBLD

QT_PTR: DW 0                       ; Next encoding byte.
