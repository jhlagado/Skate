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
;     08 lo hi ext       an exact integer with three payload bytes
;     09 lo hi ext       a float with three payload bytes
;     0A values... 02    a vector

QUO_LIST  EQU 1
QUO_END   EQU 2
QUO_DOT   EQU 3
QUO_IMM   EQU 4
QUO_BYTE  EQU 5
QUO_INT   EQU 8
QUO_FLT   EQU 9
QUO_VEC   EQU 0AH

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
        POP DE
        JP RT_STORE                ; Cache the value; A:HL is returned.

; Decode one value at .PTR into A:CHL.
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
        CP QUO_INT
        JR Z,.INT
        CP QUO_FLT
        JR Z,.FLT
        CP QUO_VEC
        JR Z,.VECTOR
        SUB 2                      ; Codes 6 and 7 are tags 4 and 5.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (.PTR),HL
        EX DE,HL
        LD C,0
        RET
.BYTE:
        LD L,(HL)
        LD H,0
        LD C,H
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
        LD C,0
        RET
.FLT:
        LD A,9
        JR .WIDE
.INT:
        LD A,3
.WIDE:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)
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

; Push each element, allocate the vector while they are roots, then move
; them into its cells.
.VECTOR:
        LD B,0                     ; Elements pushed so far.
.V_ITEM:
        LD HL,(.PTR)
        LD A,(HL)
        CP QUO_END
        JR Z,.V_BUILD
        PUSH BC
        CALL .VALUE
        CALL QT_PUSH
        POP BC
        INC B
        JR .V_ITEM
.V_BUILD:
        INC HL                     ; Past the end code.
        LD (.PTR),HL
        LD A,B
        LD (VEC_REQ),A
        CALL VEC_NEW               ; May collect; the elements are QT roots.
        JP C,ERROR
        LD A,(VEC_REQ)
        LD (HL),A                  ; The length byte.
        INC HL
        EX DE,HL                   ; DE is the first cell.
        LD L,A                     ; The elements are the top A records.
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD B,H
        LD C,L
        LD HL,(QT_SP)
        OR A
        SBC HL,BC
        LD (QT_SP),HL              ; Pop them,
        LD A,B
        OR C
        JR Z,.V_DONE
        LDIR                       ; and copy them in order.
.V_DONE:
        LD HL,(VEC_OBJ)
        LD C,0
        LD A,7
        RET

.PTR: DW 0                         ; Next encoding byte.
