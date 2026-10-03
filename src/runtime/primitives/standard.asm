; Standard procedures added after the original primitive set: pair mutation,
; structural equality, character and string comparison, conversions, list
; operations and character classes.
;
; Primitive kinds 60 and above arrive here from SRTPRIM through STD_DISP.
; Each routine reads the argument packet, returns its result in A:HL and
; leaves through IX like every other primitive.  Allocating routines keep
; their partial results reachable: inputs stay in the packet, constructor
; inputs are roots while a pair is made, and anything else is held on the
; operator side stack.
;
; Labels follow the readable convention: globals without the old SRT prefix
; and private `.NAME` labels for branches inside one routine.

STD_BASE EQU 60                   ; First primitive kind handled here.

; Jump to the routine for primitive kind A (60 or above).
STD_DISP:
        SUB STD_BASE
        ADD A,A
        LD L,A
        LD H,0
        LD DE,STD_TAB
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP (HL)

STD_TAB:
        DW SET_CAR,SET_CDR,EQUAL                       ; 60..62
        DW CHAR_REL,CHAR_REL,CHAR_REL,CHAR_REL,CHAR_REL ; 63..67 char=? < > <= >=
        DW STR_REL,STR_REL,STR_REL,STR_REL,STR_REL      ; 68..72 string=? < > <= >=
        DW SYM2STR,STR2SYM,NUM2STR,MODULO,ABS_VAL       ; 73..77
        DW LENGTH,REVERSE,APPEND,LISTTAIL,LIST_REF      ; 78..82
        DW MEMQ,ASSQ,MEMBER,ASSOC,LIST_P                ; 83..87
        DW CHAR_UP,CHAR_DN,IS_ALPHA,IS_DIGIT,IS_SPACE   ; 88..92
        DW SUBSTR                                       ; 93

; ---- Packet and result helpers --------------------------------------------

; Require exactly A arguments.
PKT_NARG:
        LD B,A
        LD A,(SRTARGC)
        CP B
        RET Z
        JP SRTERROR

; Read the first or second packet value into A:HL.
PKT_ARG0:
        LD HL,SRTARGPK
        JP SRTPVAL
PKT_ARG1:
        LD HL,SRTARGPK+4
        JP SRTPVAL

BOOL_T:
        LD HL,0FE01H               ; Canonical true.
        XOR A
        PUSH IX
        RET
BOOL_F:
        LD HL,0FE00H               ; Canonical false.
        XOR A
        PUSH IX
        RET
UNSPEC:
        LD HL,0FE04H               ; The unspecified value.
        XOR A
        PUSH IX
        RET

; Z when A:HL is the empty list.  A and HL are kept; DE is used.
IS_NULL:
        OR A
        RET NZ
        PUSH HL
        LD DE,0FE02H
        SBC HL,DE                  ; Carry is clear after OR A.
        POP HL
        RET

; Z when A:HL is a byte character.
IS_CHAR:
        OR A
        RET NZ
        LD A,H
        CP 0FFH
        LD A,0                     ; Keep the scalar tag for the caller.
        RET

; Z when tag A names a literal or managed string.  A is kept.
IS_STR:
        CP 5
        RET Z
        CP 6
        RET

; Read the four-byte cell at HL: A is its tag nibble, HL its payload.
; BC and DE are kept.
CELL_GET:
        PUSH DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH
        EX DE,HL
        POP DE
        RET

; ---- Pair mutation --------------------------------------------------------

; set-car! and set-cdr! write the value into the selected cell of a live pair,
; keeping the cell's allocation and mark bits.
SET_CAR:
        LD C,0                     ; The CAR cell starts the pair record.
        JR SET_CELL
SET_CDR:
        LD C,4                     ; The CDR cell follows it.
SET_CELL:
        PUSH BC
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL SRTPCHK               ; Reject anything but a live pair.
        POP BC
        JP C,SRTERROR
        LD B,0
        ADD HL,BC                  ; HL is the selected cell.
        PUSH HL
        CALL PKT_ARG1              ; A:HL is the new value.
        EX DE,HL
        POP HL
        CALL CDR_PUT               ; Keeps allocation and mark bits.
        JP UNSPEC

; ---- Structural equality --------------------------------------------------

; equal? compares pairs, strings and vectors by content and everything else
; as eqv? does.
EQUAL:
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG1
        LD C,A
        EX DE,HL
        PUSH BC
        PUSH DE
        CALL PKT_ARG0
        POP DE
        POP BC
        CALL EQ_DEEP
        JP C,BOOL_F
        JP BOOL_T

; Compare A:HL with C:DE.  Carry is clear when they are equal.  The CAR and
; vector elements recurse on the native stack; CDRs iterate.
EQ_DEEP:
        CP C
        JR NZ,.TAGS
        PUSH HL
        OR A
        SBC HL,DE
        POP HL
        RET Z                      ; Same tag and payload: equal, carry clear.
        CP 1
        JR Z,.PAIR
        CP 7
        JR Z,.VECTOR
.TAGS:
        CALL IS_STR                ; Literal and managed strings compare by
        JR NZ,.NO                  ; content even though their tags differ.
        LD B,A
        LD A,C
        CALL IS_STR
        LD A,B
        JR Z,.STRING
.NO:
        SCF
        RET
.STRING:
        PUSH BC
        PUSH DE
        CALL SRTSCHK               ; HL is the left string.
        POP DE
        POP BC
        JR C,.NO
        PUSH HL
        EX DE,HL
        LD A,C
        CALL SRTSCHK               ; HL is the right string.
        POP DE
        JR C,.NO
        EX DE,HL
        CALL STR_CMP
        CP 2
        JR NZ,.NO
        OR A
        RET
.PAIR:
        PUSH DE
        CALL SRTPCHK               ; Validate the left pair.
        POP DE
        JR C,.NO
        PUSH HL
        EX DE,HL
        LD A,1
        CALL SRTPCHK               ; Validate the right pair.
        EX DE,HL
        POP HL
        JR C,.NO
        PUSH HL                    ; Keep both pairs for their CDRs.
        PUSH DE
        EX DE,HL
        CALL CELL_GET              ; A:HL is the right CAR.
        LD C,A
        EX DE,HL                   ; C:DE is the right CAR, HL the left pair.
        CALL CELL_GET              ; A:HL is the left CAR.
        CALL EQ_DEEP
        POP DE
        POP HL
        RET C
        LD BC,4
        ADD HL,BC                  ; Left CDR cell.
        EX DE,HL
        ADD HL,BC                  ; Right CDR cell.
        CALL CELL_GET
        LD C,A
        EX DE,HL                   ; C:DE is the right CDR, HL the left cell.
        CALL CELL_GET
        JP EQ_DEEP
.VECTOR:
        PUSH HL
        PUSH DE
        CALL SRTVLD                ; Validate the left vector.
        POP DE
        POP HL
        JR C,.NO
        PUSH HL
        PUSH DE
        EX DE,HL
        CALL SRTVLD                ; Validate the right vector.
        POP DE
        POP HL
        JR C,.NO
        LD A,(DE)                  ; Equal vectors have equal lengths.
        CP (HL)
        JR NZ,.NO
        LD B,A
        INC HL
        INC DE
.ELEMENT:
        LD A,B
        OR A
        RET Z                      ; Every element matched.
        PUSH BC
        PUSH HL
        PUSH DE
        EX DE,HL
        CALL CELL_GET
        LD C,A
        EX DE,HL
        CALL CELL_GET
        CALL EQ_DEEP
        POP DE
        POP HL
        POP BC
        RET C
        PUSH BC
        LD BC,4
        ADD HL,BC
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        POP BC
        DEC B
        JR .ELEMENT

; Compare the length-prefixed strings at HL and DE byte by byte.  A returns
; 1 when HL sorts first, 2 when they are equal and 4 when DE sorts first.
STR_CMP:
        LD B,(HL)
        LD A,(DE)
        LD C,A
.LOOP:
        LD A,B
        OR A
        JR Z,.LEFT_END
        LD A,C
        OR A
        JR Z,.GREATER
        INC HL
        INC DE
        LD A,(DE)
        CP (HL)
        JR C,.GREATER              ; The right byte is lower.
        JR NZ,.LESS
        DEC B
        DEC C
        JR .LOOP
.LEFT_END:
        LD A,C
        OR A
        LD A,2
        RET Z                      ; Both ended together.
.LESS:
        LD A,1
        RET
.GREATER:
        LD A,4
        RET

; ---- Ordered comparisons --------------------------------------------------

; Codes 1, 2 and 4 mean less, equal and greater.  Each relation accepts the
; codes in its mask: = < > <= >= in kind order.
REL_MASK:
        DB 2,1,4,3,6

; NZ when code A satisfies the relation selected in STD_REL.
REL_TEST:
        PUSH AF
        LD A,(STD_REL)
        LD E,A
        LD D,0
        LD HL,REL_MASK
        ADD HL,DE
        POP AF
        AND (HL)
        RET

; Turn the flags of CP (left minus right) into a comparison code.
CODE_OF:
        JR C,.LESS
        JR Z,.EQUAL
        LD A,4
        RET
.LESS:
        LD A,1
        RET
.EQUAL:
        LD A,2
        RET

; char=? char<? char>? char<=? char>=? over two or more characters.
CHAR_REL:
        LD A,(SRTPID)
        SUB 63
        LD (STD_REL),A
        LD A,(SRTARGC)
        CP 2
        JP C,SRTERROR
        LD B,A
        LD HL,SRTARGPK
.CHECK:
        PUSH BC                    ; Validate every argument first.
        PUSH HL
        CALL SRTPVAL
        CALL IS_CHAR
        POP HL
        POP BC
        JP NZ,SRTERROR
        LD DE,4
        ADD HL,DE
        DJNZ .CHECK
        LD A,(SRTARGC)
        DEC A
        LD B,A
        LD HL,SRTARGPK
.PAIRS:
        LD A,(HL)                  ; Left character byte.
        LD DE,4
        ADD HL,DE
        LD C,(HL)                  ; Right character byte.
        CP C
        CALL CODE_OF
        PUSH HL
        PUSH BC
        CALL REL_TEST
        POP BC
        POP HL
        JP Z,BOOL_F
        DJNZ .PAIRS
        JP BOOL_T

; string=? string<? string>? string<=? string>=? over two or more strings.
STR_REL:
        LD A,(SRTPID)
        SUB 68
        LD (STD_REL),A
        LD A,(SRTARGC)
        CP 2
        JP C,SRTERROR
        LD B,A
        LD HL,SRTARGPK
.CHECK:
        PUSH BC
        PUSH HL
        CALL SRTPVAL
        CALL SRTSCHK
        POP HL
        POP BC
        JP C,SRTERROR
        LD DE,4
        ADD HL,DE
        DJNZ .CHECK
        LD A,(SRTARGC)
        DEC A
        LD B,A
        LD HL,SRTARGPK
        LD (STD_PTR),HL
.PAIRS:
        PUSH BC
        LD HL,(STD_PTR)
        CALL SRTPVAL
        CALL SRTSCHK
        PUSH HL                    ; Left string.
        LD HL,(STD_PTR)
        LD DE,4
        ADD HL,DE
        LD (STD_PTR),HL
        CALL SRTPVAL
        CALL SRTSCHK
        EX DE,HL                   ; Right string.
        POP HL
        CALL STR_CMP
        CALL REL_TEST
        POP BC
        JP Z,BOOL_F
        DJNZ .PAIRS
        JP BOOL_T

; ---- Conversions ----------------------------------------------------------

; A symbol's payload already addresses a length-prefixed spelling outside the
; heap, which is exactly the layout of a literal string.
SYM2STR:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 4
        JP NZ,SRTERROR
        LD A,5
        PUSH IX
        RET

; Intern the string's spelling with the datum reader's symbol table.
STR2SYM:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL SRTSCHK
        JP C,SRTERROR
        LD C,(HL)
        LD B,0
        INC HL
        CALL SRTSYMIN
        PUSH IX
        RET

; number->string for exact integers: a managed string of decimal digits.
NUM2STR:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 3
        JP NZ,SRTERROR
        LD A,H
        LD (STD_SIGN),A
        BIT 7,H
        JR Z,.DIGITS
        XOR A                      ; Negate; -32768 stays 8000H, read unsigned.
        SUB L
        LD L,A
        SBC A,A
        SUB H
        LD H,A
.DIGITS:
        LD DE,STD_NBUF+7           ; Digits are written backwards.
.NEXT:
        CALL DIV10
        ADD A,'0'
        DEC DE
        LD (DE),A
        LD A,H
        OR L
        JR NZ,.NEXT
        LD A,(STD_SIGN)
        BIT 7,A
        JR Z,.SIZED
        DEC DE
        LD A,'-'
        LD (DE),A
.SIZED:
        LD HL,STD_NBUF+7
        OR A
        SBC HL,DE
        LD A,L
        LD (SRTSLENB),A
        LD (STD_PTR),DE
        CALL SRTSACL               ; May collect; nothing here is a heap value.
        JP C,SRTERROR
        LD A,(SRTSLENB)
        LD (HL),A
        INC HL
        EX DE,HL
        LD HL,(STD_PTR)
        LD C,A
        LD B,0
        LDIR
        JP SRTSRET

; Divide HL by ten, unsigned: HL is the quotient and A the remainder.
DIV10:
        PUSH BC
        LD B,16
        XOR A
.BIT:
        ADD HL,HL
        RLA
        CP 10
        JR C,.KEEP
        SUB 10
        INC L
.KEEP:
        DJNZ .BIT
        POP BC
        RET

; ---- Arithmetic -----------------------------------------------------------

; modulo takes the sign of the divisor; remainder takes the dividend's.
MODULO:
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG1
        CP 3
        JP NZ,SRTERROR
        LD (STD_DIV),HL
        CALL PKT_ARG0
        CP 3
        JP NZ,SRTERROR
        LD DE,(STD_DIV)
        LD B,3
        CALL NREM                  ; Rejects division by zero.
        JP C,SRTERROR
        LD A,H
        OR L
        JR Z,.DONE
        LD A,(STD_DIV+1)
        XOR H
        JP P,.DONE                 ; Same signs need no adjustment.
        LD DE,(STD_DIV)
        ADD HL,DE
.DONE:
        LD A,3
        PUSH IX
        RET

; abs for exact integers and binary16 numbers.
ABS_VAL:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 3
        JR NZ,.FLOAT
        BIT 7,H
        JR Z,.DONE
        LD A,H                     ; -32768 has no positive counterpart.
        CP 80H
        JR NZ,.NEGATE
        LD A,L
        OR A
        JP Z,SRTERROR
.NEGATE:
        XOR A
        SUB L
        LD L,A
        SBC A,A
        SUB H
        LD H,A
.DONE:
        LD A,3
        PUSH IX
        RET
.FLOAT:
        CALL SRTNCHK               ; Reject the reserved immediates.
        JP C,SRTERROR
        CALL PKT_ARG0
        RES 7,H                    ; Clear the binary16 sign bit.
        XOR A
        PUSH IX
        RET

; ---- Lists ----------------------------------------------------------------

; length of a proper list.
LENGTH:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        LD BC,0
.LOOP:
        CALL IS_NULL
        JR Z,.DONE
        PUSH BC
        CALL SRTCDRV
        POP BC
        JP C,SRTERROR              ; An improper list has no length.
        INC BC
        JR .LOOP
.DONE:
        LD H,B
        LD L,C
        LD A,3
        PUSH IX
        RET

; list? is true for a proper list.
LIST_P:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
.LOOP:
        CALL IS_NULL
        JP Z,BOOL_T
        CALL SRTCDRV
        JP C,BOOL_F
        JR .LOOP

; reverse returns a new list.
REVERSE:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL REV_INIT
        CALL REV_CORE
        LD HL,(STD_ACC)
        LD A,(STD_ATAG)
        PUSH IX
        RET

; Start a reversal of A:HL into an empty accumulator.
REV_INIT:
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        LD HL,0FE02H
        LD (STD_ACC),HL
        XOR A
        LD (STD_ATAG),A
        RET

; Cons each element of STD_LIST onto STD_ACC.  The list being read must be
; reachable from a root; the accumulator is a constructor input whenever a
; collection can run.
REV_CORE:
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL IS_NULL
        RET Z
        CALL SRTCARV
        JP C,SRTERROR              ; Only a proper list can be reversed.
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL SRTCDRV
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        LD HL,(STD_ACC)
        LD (SRTQCDR),HL
        LD A,(STD_ATAG)
        LD (SRTQDTAG),A
        CALL SRTMAKEP
        LD (STD_ACC),HL
        LD (STD_ATAG),A
        JR REV_CORE

; append copies every list but the last, which becomes the shared tail.  Each
; list is copied front to back, linking every new cell to the one before, so
; no reversed temporary is needed.  The result so far and the head of the copy
; being built are held on the operator side stack so a collection cannot
; reclaim them; the cells after the head are reachable from it.
APPEND:
        LD A,(SRTARGC)
        OR A
        JR NZ,.SOME
        LD HL,0FE02H               ; (append) is the empty list.
        PUSH IX
        RET
.SOME:
        DEC A
        LD (STD_CNT),A             ; Lists still to be copied in front.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTARGPK
        ADD HL,DE
        LD (STD_PTR),HL            ; The last argument's packet record.
        CALL SRTPVAL
        CALL SRTOPUSH              ; Root the result.
        CALL OPS_TOP
        LD (STD_RADR),HL
        LD HL,0FE02H
        XOR A
        CALL SRTOPUSH              ; Root the head of the copy.
        CALL OPS_TOP
        LD (STD_VADR),HL
.NEXT:
        LD A,(STD_CNT)
        OR A
        JP Z,.DONE
        DEC A
        LD (STD_CNT),A
        LD HL,(STD_PTR)
        LD DE,-4
        ADD HL,DE
        LD (STD_PTR),HL
        CALL SRTPVAL
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        LD HL,0
        LD (STD_ACC),HL            ; No cell has been copied yet.
.COPY:
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL IS_NULL
        JP Z,.LINK
        CALL SRTCARV
        JP C,SRTERROR              ; Only proper lists can be copied.
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL SRTCDRV
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        LD HL,0FE02H               ; Each new cell starts as a one-element list.
        LD (SRTQCDR),HL
        XOR A
        LD (SRTQDTAG),A
        CALL SRTMAKEP              ; A:HL is the new cell.
        EX DE,HL
        LD HL,(STD_ACC)
        LD A,H
        OR L
        JR NZ,.CHAIN
        LD HL,(STD_VADR)           ; The first cell is the rooted head.
        LD A,1
        CALL OPS_PUT
        JR .LAST
.CHAIN:
        LD BC,SRPCDDR0             ; Point the previous cell's CDR here.
        ADD HL,BC
        LD A,1
        CALL CDR_PUT
.LAST:
        LD (STD_ACC),DE            ; This cell is now the last one.
        JR .COPY
.LINK:
        LD HL,(STD_ACC)
        LD A,H
        OR L
        JP Z,.NEXT                 ; An empty list leaves the result unchanged.
        LD BC,SRPCDDR0
        ADD HL,BC
        PUSH HL
        LD HL,(STD_RADR)
        CALL OPS_GET               ; The copy ends in the result so far.
        EX DE,HL
        POP HL
        CALL CDR_PUT
        LD HL,(STD_VADR)
        CALL OPS_GET               ; The copy's head is the new result.
        EX DE,HL
        LD HL,(STD_RADR)
        CALL OPS_PUT
        JP .NEXT
.DONE:
        CALL SRTOPPOP              ; Drop the head slot.
        CALL SRTOPPOP              ; A:HL is the result.
        PUSH IX
        RET

; Store A:DE in the pair cell at HL, keeping its metadata flag bits.
; set-car! uses it for the CAR cell too.
CDR_PUT:
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),0
        INC HL
        LD C,A
        LD A,(HL)
        AND 0F0H
        OR C
        LD (HL),A
        RET

; Address of the newest operator side-stack record.
OPS_TOP:
        LD HL,(SRTOPS)
        LD DE,-4
        ADD HL,DE
        RET

; Store A:DE in the side-stack record at HL, or load it as A:HL.
OPS_PUT:
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),A
        RET
OPS_GET:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; list-tail and list-ref.
LISTTAIL:
        CALL TAIL_K
        PUSH IX
        RET
LIST_REF:
        CALL TAIL_K
        CALL SRTCARV
        JP C,SRTERROR
        PUSH IX
        RET

; A:HL is the list after K CDRs, where K is the second argument.
TAIL_K:
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG1
        CP 3
        JP NZ,SRTERROR
        BIT 7,H
        JP NZ,SRTERROR
        LD B,H
        LD C,L
        PUSH BC
        CALL PKT_ARG0
        POP BC
.LOOP:
        PUSH AF
        LD A,B
        OR C
        JR Z,.DONE
        POP AF
        PUSH BC
        CALL SRTCDRV
        POP BC
        JP C,SRTERROR
        DEC BC
        JR .LOOP
.DONE:
        POP AF
        RET

; memq and member return the first tail whose CAR matches, or false.
MEMQ:
        XOR A
        JR MEM_ANY
MEMBER:
        LD A,1
MEM_ANY:
        LD (STD_MODE),A
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG0
        LD (STD_KEY),HL
        LD (STD_KTAG),A
        CALL PKT_ARG1
.LOOP:
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        CALL IS_NULL
        JP Z,BOOL_F
        CALL SRTCARV
        JP C,SRTERROR
        CALL MATCH
        JR NC,.FOUND
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        CALL SRTCDRV
        JP C,SRTERROR
        JR .LOOP
.FOUND:
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        PUSH IX
        RET

; assq and assoc return the first entry whose CAR matches, or false.
ASSQ:
        XOR A
        JR ASS_ANY
ASSOC:
        LD A,1
ASS_ANY:
        LD (STD_MODE),A
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG0
        LD (STD_KEY),HL
        LD (STD_KTAG),A
        CALL PKT_ARG1
.LOOP:
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        CALL IS_NULL
        JP Z,BOOL_F
        CALL SRTCARV
        JP C,SRTERROR
        LD (STD_ENT),HL
        LD (STD_ETAG),A
        CALL SRTCARV               ; Every entry must be a pair.
        JP C,SRTERROR
        CALL MATCH
        JR NC,.FOUND
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        CALL SRTCDRV
        JP C,SRTERROR
        JR .LOOP
.FOUND:
        LD HL,(STD_ENT)
        LD A,(STD_ETAG)
        PUSH IX
        RET

; Compare A:HL with STD_KEY: identity when STD_MODE is zero, equal? otherwise.
; Carry is clear on a match.
MATCH:
        PUSH AF
        LD A,(STD_KTAG)
        LD C,A
        LD DE,(STD_KEY)
        LD A,(STD_MODE)
        OR A
        JR NZ,.DEEP
        POP AF
        CP C
        JR NZ,.NO
        OR A
        SBC HL,DE
        RET Z
.NO:
        SCF
        RET
.DEEP:
        POP AF
        JP EQ_DEEP

; ---- Characters -----------------------------------------------------------

; Read the single character argument into A.
CHAR_ARG:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL IS_CHAR
        JP NZ,SRTERROR
        LD A,L
        RET

CHAR_UP:
        CALL CHAR_ARG
        CP 'a'
        JR C,CHAR_RET
        CP 'z'+1
        JR NC,CHAR_RET
        SUB 32
        JR CHAR_RET
CHAR_DN:
        CALL CHAR_ARG
        CP 'A'
        JR C,CHAR_RET
        CP 'Z'+1
        JR NC,CHAR_RET
        ADD A,32
CHAR_RET:
        LD L,A
        LD H,0FFH
        XOR A
        PUSH IX
        RET

IS_ALPHA:
        CALL CHAR_ARG
        OR 20H                     ; Fold upper case onto lower case.
        CP 'a'
        JP C,BOOL_F
        CP 'z'+1
        JP NC,BOOL_F
        JP BOOL_T
IS_DIGIT:
        CALL CHAR_ARG
        CP '0'
        JP C,BOOL_F
        CP '9'+1
        JP NC,BOOL_F
        JP BOOL_T
IS_SPACE:
        CALL CHAR_ARG
        CP ' '
        JP Z,BOOL_T
        CP 9                       ; Tab, line feed, vertical tab, form feed
        JP C,BOOL_F                ; and carriage return are white space.
        CP 14
        JP C,BOOL_T
        JP BOOL_F

; ---- Strings --------------------------------------------------------------

; (substring string start end) copies bytes start..end-1 into a new string.
SUBSTR:
        LD A,3
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL SRTSCHK
        JP C,SRTERROR
        LD (STD_PTR),HL
        LD HL,SRTARGPK+8
        CALL SRTPVAL
        CALL .INDEX
        LD (STD_END),A
        CALL PKT_ARG1
        CALL .INDEX
        LD (STD_BEG),A
        LD B,A
        LD A,(STD_END)
        CP B
        JP C,SRTERROR              ; The end may not precede the start.
        LD C,A
        LD HL,(STD_PTR)
        LD A,(HL)
        CP C
        JP C,SRTERROR              ; The end may not pass the string.
        LD A,C
        SUB B
        LD (SRTSLENB),A
        CALL SRTSACL               ; The source stays rooted in the packet.
        JP C,SRTERROR
        LD A,(SRTSLENB)
        LD (HL),A
        INC HL
        OR A
        JP Z,SRTSRET
        EX DE,HL
        LD HL,(STD_PTR)
        INC HL
        LD A,(STD_BEG)
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(SRTSLENB)
        LD C,A
        LDIR
        JP SRTSRET
.INDEX:
        CP 3                       ; An index is a byte-sized exact integer.
        JP NZ,SRTERROR
        LD A,H
        OR A
        JP NZ,SRTERROR
        LD A,L
        RET

; ---- case -----------------------------------------------------------------

; Generated case code pushes the key on the operator side stack, then loads
; each datum into A:HL and calls here.  Z means the datum is eqv? to the key.
CASE_EQ:
        EX DE,HL                   ; DE is the datum payload.
        LD HL,(SRTOPS)
        DEC HL
        DEC HL                     ; The key record's tag byte.
        CP (HL)
        RET NZ
        DEC HL
        LD A,(HL)
        CP D
        RET NZ
        DEC HL
        LD A,(HL)
        CP E
        RET

; ---- State ----------------------------------------------------------------

STD_REL:  DB 0                     ; Relation index for an ordered comparison.
STD_PTR:  DW 0                     ; Packet or string cursor.
STD_SIGN: DB 0                     ; High byte of the number being converted.
STD_NBUF: DS 7                     ; Digits of -32768 and shorter numbers.
STD_DIV:  DW 0                     ; Divisor for modulo.
STD_LIST: DW 0                     ; List being walked.
STD_LTAG: DB 0
STD_ACC:  DW 0                     ; Reversal accumulator; append's last cell.
STD_ATAG: DB 0
STD_CNT:  DB 0                     ; Lists still to append.
STD_RADR: DW 0                     ; Side-stack record holding append's result.
STD_VADR: DW 0                     ; Side-stack record holding the copy's head.
STD_MODE: DB 0                     ; Zero compares identity, one equal?.
STD_KEY:  DW 0                     ; Key for memq, member, assq and assoc.
STD_KTAG: DB 0
STD_ENT:  DW 0                     ; Matching association entry.
STD_ETAG: DB 0
STD_BEG:  DB 0                     ; substring start.
STD_END:  DB 0                     ; substring end.
