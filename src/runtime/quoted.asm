; Quoted lists stored as encoded data and built on first use.
;
; Generated code for a quoted list is CALL QT_BUILD followed by
;
;     DW cache      a four-byte static cell holding the built list
;     DW end        the address after the encoding, where execution resumes
;     encoding      one value, as below
;
; The first evaluation decodes the value, stores it in the cache and returns
; it in A:CHL; later evaluations return the cached value.  Elements are pushed
; on the quoted-data stack, which is a collector root, and folded into pairs
; by QT_FOLD, exactly as the code the compiler used to emit did.
;
; Encoding of one value:
;     01 values... 02    a proper list
;     01 values... 03    a dotted list; the last value is the tail
;     04 lo hi tag       any immediate value
;     05 n               the exact integer n, 0..255
;     06 lo hi           a symbol literal
;     07 lo hi           a string literal

QUO_LIST  EQU 1
QUO_END   EQU 2
QUO_DOT   EQU 3
QUO_IMM   EQU 4
QUO_BYTE  EQU 5

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
        LD (.PTR),HL
        PUSH BC                    ; Return past the encoding.
        PUSH DE
        EX DE,HL
        CALL QT_CACHE              ; A hit returns the cached value.
        POP DE
        RET NC
        PUSH DE
        CALL .VALUE
        CALL RT_WIDEN              ; Encoded integers are sixteen-bit for now.
        POP DE
        JP RT_STORE                ; Cache the value; A:HL is returned.

; Decode one value at .PTR into A:HL.
.VALUE:
        LD HL,(.PTR)
        LD A,(HL)
        INC HL
        LD (.PTR),HL
        CP QUO_LIST
        JR Z,.LIST
        CP QUO_BYTE
        JR Z,.BYTE
        CP QUO_IMM
        JR Z,.IMM
        SUB 2                      ; Codes 6 and 7 are tags 4 and 5.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (.PTR),HL
        EX DE,HL
        RET
.BYTE:
        LD L,(HL)
        LD H,0
        LD A,3
        LD DE,(.PTR)
        INC DE
        LD (.PTR),DE
        RET
.IMM:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        INC HL
        LD (.PTR),HL
        EX DE,HL
        RET
.LIST:
        LD B,0                     ; Elements pushed so far.
.ELEMENT:
        LD HL,(.PTR)
        LD A,(HL)
        CP QUO_END
        JR Z,.CLOSE
        CP QUO_DOT
        JR Z,.CLOSE
        PUSH BC
        CALL .VALUE
        CALL RT_WIDEN
        CALL QT_PUSH
        POP BC
        INC B
        JR .ELEMENT
.CLOSE:
        INC HL
        LD (.PTR),HL
        SUB QUO_END                ; Zero for a proper list, one for dotted.
        LD C,A
        LD A,B
        LD B,C
        JP QT_FOLD

.PTR: DW 0                         ; Next encoding byte.
