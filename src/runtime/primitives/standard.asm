; Standard procedures added after the original primitive set: pair mutation,
; structural equality, character and string comparison, conversions, list
; operations and character classes.
;
; Primitive kinds 60 and above arrive here from PRIM_RUN through STD_DISP.
; Each routine reads the argument packet, returns its result in A:HL and
; leaves through IX like every other primitive.  Allocating routines keep
; their partial results reachable: inputs stay in the packet, constructor
; inputs are roots while a pair is made, and anything else is held on the
; operator side stack.
;
; Labels follow the readable convention: globals without the old SRT prefix
; and private `.NAME` labels for branches inside one routine.

STD_BASE EQU 60                   ; First primitive kind handled here.

; The first byte of the optional standard-procedure module.  The generator
; records this address as the length of the core runtime.
STD_MOD:

; Jump to the routine for primitive kind A (60 or above).
STD_DISP:
        SUB STD_BASE
        ADD A,A
        LD L,A
        LD H,0
        LD DE,.TABLE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP (HL)

.TABLE:
        DW STD_SCAR,STD_SCDR,STD_SAME                  ; 60..62
        DW STD_CHR,STD_CHR,STD_CHR,STD_CHR,STD_CHR      ; 63..67 char=? < > <= >=
        DW STD_STR,STD_STR,STD_STR,STD_STR,STD_STR      ; 68..72 string=? < > <= >=
        DW STD_NAME,STD_SYM,STD_NUM,STD_FMOD,STD_ABS    ; 73..77
        DW STD_LEN,STD_REV,STD_JOIN,STD_TAIL,STD_NTH    ; 78..82
        DW STD_MEMQ,STD_ASSQ,STD_MEMB,STD_ASSO,STD_PROP ; 83..87
        DW STD_UP,STD_DOWN,STD_ATOZ,STD_0TO9,STD_SPC    ; 88..92
        DW STD_SUBS                                     ; 93

; ---- Packet and result helpers --------------------------------------------

; Require exactly A arguments.
PKT_NARG:
        LD B,A
        LD A,(ARG_CNT)
        CP B
        RET Z
        JP ERROR

; Read the first or second packet value into A:HL.
PKT_ARG0:
        LD HL,ARG_PKT
        JP PKT_VAL
PKT_ARG1:
        LD HL,ARG_PKT+4
        JP PKT_VAL

STD_YES:
        LD HL,0FE01H               ; Canonical true.
        XOR A
        PUSH IX
        RET
STD_NO:
        LD HL,0FE00H               ; Canonical false.
        XOR A
        PUSH IX
        RET
STD_VOID:
        LD HL,0FE04H               ; The unspecified value.
        XOR A
        PUSH IX
        RET

; Z when A:HL is the empty list.  A and HL are kept; DE is used.
STD_NIL:
        OR A
        RET NZ
        PUSH HL
        LD DE,0FE02H
        SBC HL,DE                  ; Carry is clear after OR A.
        POP HL
        RET

; Z when A:HL is a byte character.
STD_BYTE:
        OR A
        RET NZ
        LD A,H
        CP 0FFH
        LD A,0                     ; Keep the scalar tag for the caller.
        RET

; Z when tag A names a literal or managed string.  A is kept.
STD_TEXT:
        CP 5
        RET Z
        CP 6
        RET

; Read the four-byte cell at HL: A is its tag nibble, HL its payload.
; BC and DE are kept.
STD_GET:
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
STD_SCAR:
        LD C,0                     ; The CAR cell starts the pair record.
        JR STD_SET
STD_SCDR:
        LD C,4                     ; The CDR cell follows it.
STD_SET:
        PUSH BC
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL PAIR_CHK              ; Reject anything but a live pair.
        POP BC
        JP C,ERROR
        LD B,0
        ADD HL,BC                  ; HL is the selected cell.
        PUSH HL
        CALL PKT_ARG1              ; A:HL is the new value.
        EX DE,HL
        POP HL
        CALL STD_PUT               ; Keeps allocation and mark bits.
        JP STD_VOID

; ---- Structural equality --------------------------------------------------

; equal? compares pairs, strings and vectors by content and everything else
; as eqv? does.
STD_SAME:
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
        CALL STD_DEEP
        JP C,STD_NO
        JP STD_YES

; Compare A:HL with C:DE.  Carry is clear when they are equal.  The CAR and
; vector elements recurse on the native stack; CDRs iterate.
STD_DEEP:
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
        CALL STD_TEXT              ; Literal and managed strings compare by
        JR NZ,.NO                  ; content even though their tags differ.
        LD B,A
        LD A,C
        CALL STD_TEXT
        LD A,B
        JR Z,.STRING
.NO:
        SCF
        RET
.STRING:
        PUSH BC
        PUSH DE
        CALL STR_ARG               ; HL is the left string.
        POP DE
        POP BC
        JR C,.NO
        PUSH HL
        EX DE,HL
        LD A,C
        CALL STR_ARG               ; HL is the right string.
        POP DE
        JR C,.NO
        EX DE,HL
        CALL STD_CMP
        CP 2
        JR NZ,.NO
        OR A
        RET
.PAIR:
        PUSH DE
        CALL PAIR_CHK              ; Validate the left pair.
        POP DE
        JR C,.NO
        PUSH HL
        EX DE,HL
        LD A,1
        CALL PAIR_CHK              ; Validate the right pair.
        EX DE,HL
        POP HL
        JR C,.NO
        PUSH HL                    ; Keep both pairs for their CDRs.
        PUSH DE
        EX DE,HL
        CALL STD_GET               ; A:HL is the right CAR.
        LD C,A
        EX DE,HL                   ; C:DE is the right CAR, HL the left pair.
        CALL STD_GET               ; A:HL is the left CAR.
        CALL STD_DEEP
        POP DE
        POP HL
        RET C
        LD BC,4
        ADD HL,BC                  ; Left CDR cell.
        EX DE,HL
        ADD HL,BC                  ; Right CDR cell.
        CALL STD_GET
        LD C,A
        EX DE,HL                   ; C:DE is the right CDR, HL the left cell.
        CALL STD_GET
        JP STD_DEEP
.VECTOR:
        PUSH HL
        PUSH DE
        CALL VEC_CHK               ; Validate the left vector.
        POP DE
        POP HL
        JR C,.NO
        PUSH HL
        PUSH DE
        EX DE,HL
        CALL VEC_CHK               ; Validate the right vector.
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
        CALL STD_GET
        LD C,A
        EX DE,HL
        CALL STD_GET
        CALL STD_DEEP
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
STD_CMP:
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
STD_MASK:
        DB 2,1,4,3,6

; NZ when code A satisfies the relation selected in STD_REL.
STD_TEST:
        PUSH AF
        LD A,(STD_REL)
        LD E,A
        LD D,0
        LD HL,STD_MASK
        ADD HL,DE
        POP AF
        AND (HL)
        RET

; Turn the flags of CP (left minus right) into a comparison code.
STD_CODE:
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
STD_CHR:
        LD A,(PRIM_ID)
        SUB 63
        LD (STD_REL),A
        LD A,(ARG_CNT)
        CP 2
        JP C,ERROR
        LD B,A
        LD HL,ARG_PKT
.CHECK:
        PUSH BC                    ; Validate every argument first.
        PUSH HL
        CALL PKT_VAL
        CALL STD_BYTE
        POP HL
        POP BC
        JP NZ,ERROR
        LD DE,4
        ADD HL,DE
        DJNZ .CHECK
        LD A,(ARG_CNT)
        DEC A
        LD B,A
        LD HL,ARG_PKT
.PAIRS:
        LD A,(HL)                  ; Left character byte.
        LD DE,4
        ADD HL,DE
        LD C,(HL)                  ; Right character byte.
        CP C
        CALL STD_CODE
        PUSH HL
        PUSH BC
        CALL STD_TEST
        POP BC
        POP HL
        JP Z,STD_NO
        DJNZ .PAIRS
        JP STD_YES

; string=? string<? string>? string<=? string>=? over two or more strings.
STD_STR:
        LD A,(PRIM_ID)
        SUB 68
        LD (STD_REL),A
        LD A,(ARG_CNT)
        CP 2
        JP C,ERROR
        LD B,A
        LD HL,ARG_PKT
.CHECK:
        PUSH BC
        PUSH HL
        CALL PKT_VAL
        CALL STR_ARG
        POP HL
        POP BC
        JP C,ERROR
        LD DE,4
        ADD HL,DE
        DJNZ .CHECK
        LD A,(ARG_CNT)
        DEC A
        LD B,A
        LD HL,ARG_PKT
        LD (STD_PTR),HL
.PAIRS:
        PUSH BC
        LD HL,(STD_PTR)
        CALL PKT_VAL
        CALL STR_ARG
        PUSH HL                    ; Left string.
        LD HL,(STD_PTR)
        LD DE,4
        ADD HL,DE
        LD (STD_PTR),HL
        CALL PKT_VAL
        CALL STR_ARG
        EX DE,HL                   ; Right string.
        POP HL
        CALL STD_CMP
        CALL STD_TEST
        POP BC
        JP Z,STD_NO
        DJNZ .PAIRS
        JP STD_YES

; ---- Conversions ----------------------------------------------------------

; A symbol's payload already addresses a length-prefixed spelling outside the
; heap, which is exactly the layout of a literal string.
STD_NAME:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 4
        JP NZ,ERROR
        LD A,5
        PUSH IX
        RET

; Intern the string's spelling with the datum reader's symbol table.
STD_SYM:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL STR_ARG
        JP C,ERROR
        LD C,(HL)
        LD B,0
        INC HL
        CALL DR_FIND
        PUSH IX
        RET

; number->string for exact integers: a managed string of decimal digits.
STD_NUM:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CP 3
        JP NZ,ERROR
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
        LD DE,STD_BUF+7            ; Digits are written backwards.
.NEXT:
        CALL .DIV_TEN
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
        LD HL,STD_BUF+7
        OR A
        SBC HL,DE
        LD A,L
        LD (STR_LEN),A
        LD (STD_PTR),DE
        CALL STR_NEW               ; May collect; nothing here is a heap value.
        JP C,ERROR
        LD A,(STR_LEN)
        LD (HL),A
        INC HL
        EX DE,HL
        LD HL,(STD_PTR)
        LD C,A
        LD B,0
        LDIR
        JP STR_RET

; Divide HL by ten, unsigned: HL is the quotient and A the remainder.
.DIV_TEN:
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
STD_FMOD:
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG1
        CP 3
        JP NZ,ERROR
        LD (STD_DIV),HL
        CALL PKT_ARG0
        CP 3
        JP NZ,ERROR
        LD DE,(STD_DIV)
        LD B,3
        CALL NUM_REM               ; Rejects division by zero.
        JP C,ERROR
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
STD_ABS:
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
        JP Z,ERROR
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
        CALL PRIM_NUM              ; Reject the reserved immediates.
        JP C,ERROR
        CALL PKT_ARG0
        RES 7,H                    ; Clear the binary16 sign bit.
        XOR A
        PUSH IX
        RET

; ---- Lists ----------------------------------------------------------------

; length of a proper list.
STD_LEN:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        LD BC,0
.LOOP:
        CALL STD_NIL
        JR Z,.DONE
        PUSH BC
        CALL PAIR_CDR
        POP BC
        JP C,ERROR                 ; An improper list has no length.
        INC BC
        JR .LOOP
.DONE:
        LD H,B
        LD L,C
        LD A,3
        PUSH IX
        RET

; list? is true for a proper list.
STD_PROP:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
.LOOP:
        CALL STD_NIL
        JP Z,STD_YES
        CALL PAIR_CDR
        JP C,STD_NO
        JR .LOOP

; reverse returns a new list.
STD_REV:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL .START
        CALL .CONS_ALL
        LD HL,(STD_ACC)
        LD A,(STD_ATAG)
        PUSH IX
        RET

; Start a reversal of A:HL into an empty accumulator.
.START:
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
.CONS_ALL:
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL STD_NIL
        RET Z
        CALL PAIR_CAR
        JP C,ERROR                 ; Only a proper list can be reversed.
        LD (QT_CAR),HL
        LD (QT_CTAG),A
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL PAIR_CDR
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        LD HL,(STD_ACC)
        LD (QT_CDR),HL
        LD A,(STD_ATAG)
        LD (QT_DTAG),A
        CALL PAIR_NEW
        LD (STD_ACC),HL
        LD (STD_ATAG),A
        JR .CONS_ALL

; append copies every list but the last, which becomes the shared tail.  Each
; list is copied front to back, linking every new cell to the one before, so
; no reversed temporary is needed.  The result so far and the head of the copy
; being built are held on the operator side stack so a collection cannot
; reclaim them; the cells after the head are reachable from it.
STD_JOIN:
        LD A,(ARG_CNT)
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
        LD DE,ARG_PKT
        ADD HL,DE
        LD (STD_PTR),HL            ; The last argument's packet record.
        CALL PKT_VAL
        CALL OPS_PUSH              ; Root the result.
        CALL OPS_TOP
        LD (STD_RES),HL
        LD HL,0FE02H
        XOR A
        CALL OPS_PUSH              ; Root the head of the copy.
        CALL OPS_TOP
        LD (STD_HEAD),HL
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
        CALL PKT_VAL
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        LD HL,0
        LD (STD_ACC),HL            ; No cell has been copied yet.
.COPY:
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL STD_NIL
        JP Z,.LINK
        CALL PAIR_CAR
        JP C,ERROR                 ; Only proper lists can be copied.
        LD (QT_CAR),HL
        LD (QT_CTAG),A
        LD A,(STD_LTAG)
        LD HL,(STD_LIST)
        CALL PAIR_CDR
        LD (STD_LIST),HL
        LD (STD_LTAG),A
        LD HL,0FE02H               ; Each new cell starts as a one-element list.
        LD (QT_CDR),HL
        XOR A
        LD (QT_DTAG),A
        CALL PAIR_NEW              ; A:HL is the new cell.
        EX DE,HL
        LD HL,(STD_ACC)
        LD A,H
        OR L
        JR NZ,.CHAIN
        LD HL,(STD_HEAD)           ; The first cell is the rooted head.
        LD A,1
        CALL OPS_PUT
        JR .LAST
.CHAIN:
        LD BC,CDR_LO               ; Point the previous cell's CDR here.
        ADD HL,BC
        LD A,1
        CALL STD_PUT
.LAST:
        LD (STD_ACC),DE            ; This cell is now the last one.
        JR .COPY
.LINK:
        LD HL,(STD_ACC)
        LD A,H
        OR L
        JP Z,.NEXT                 ; An empty list leaves the result unchanged.
        LD BC,CDR_LO
        ADD HL,BC
        PUSH HL
        LD HL,(STD_RES)
        CALL OPS_GET               ; The copy ends in the result so far.
        EX DE,HL
        POP HL
        CALL STD_PUT
        LD HL,(STD_HEAD)
        CALL OPS_GET               ; The copy's head is the new result.
        EX DE,HL
        LD HL,(STD_RES)
        CALL OPS_PUT
        JP .NEXT
.DONE:
        CALL OPS_POP               ; Drop the head slot.
        CALL OPS_POP               ; A:HL is the result.
        PUSH IX
        RET

; Store A:DE in the pair cell at HL, keeping its metadata flag bits.
; set-car! uses it for the CAR cell too.
STD_PUT:
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
        LD HL,(OPS_SP)
        LD DE,-4
        ADD HL,DE
        RET

; Store A:DE in the side-stack record at HL, or load it as A:HL.
OPS_PUT:
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),0                  ; The extension byte stays clear.
        INC HL
        LD (HL),A
        RET
OPS_GET:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH
        EX DE,HL
        RET

; list-tail and list-ref.
STD_TAIL:
        CALL STD_DROP
        PUSH IX
        RET
STD_NTH:
        CALL STD_DROP
        CALL PAIR_CAR
        JP C,ERROR
        PUSH IX
        RET

; A:HL is the list after K CDRs, where K is the second argument.
STD_DROP:
        LD A,2
        CALL PKT_NARG
        CALL PKT_ARG1
        CP 3
        JP NZ,ERROR
        BIT 7,H
        JP NZ,ERROR
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
        CALL PAIR_CDR
        POP BC
        JP C,ERROR
        DEC BC
        JR .LOOP
.DONE:
        POP AF
        RET

; memq and member return the first tail whose CAR matches, or false.
STD_MEMQ:
        XOR A
        JR STD_FIND
STD_MEMB:
        LD A,1
STD_FIND:
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
        CALL STD_NIL
        JP Z,STD_NO
        CALL PAIR_CAR
        JP C,ERROR
        CALL STD_LIKE
        JR NC,.FOUND
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        CALL PAIR_CDR
        JP C,ERROR
        JR .LOOP
.FOUND:
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        PUSH IX
        RET

; assq and assoc return the first entry whose CAR matches, or false.
STD_ASSQ:
        XOR A
        JR STD_LOOK
STD_ASSO:
        LD A,1
STD_LOOK:
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
        CALL STD_NIL
        JP Z,STD_NO
        CALL PAIR_CAR
        JP C,ERROR
        LD (STD_ENT),HL
        LD (STD_ETAG),A
        CALL PAIR_CAR              ; Every entry must be a pair.
        JP C,ERROR
        CALL STD_LIKE
        JR NC,.FOUND
        LD HL,(STD_LIST)
        LD A,(STD_LTAG)
        CALL PAIR_CDR
        JP C,ERROR
        JR .LOOP
.FOUND:
        LD HL,(STD_ENT)
        LD A,(STD_ETAG)
        PUSH IX
        RET

; Compare A:HL with STD_KEY: identity when STD_MODE is zero, equal? otherwise.
; Carry is clear on a match.
STD_LIKE:
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
        JP STD_DEEP

; ---- Characters -----------------------------------------------------------

; Read the single character argument into A.
STD_CHAR:
        LD A,1
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL STD_BYTE
        JP NZ,ERROR
        LD A,L
        RET

STD_UP:
        CALL STD_CHAR
        CP 'a'
        JR C,STD_CVAL
        CP 'z'+1
        JR NC,STD_CVAL
        SUB 32
        JR STD_CVAL
STD_DOWN:
        CALL STD_CHAR
        CP 'A'
        JR C,STD_CVAL
        CP 'Z'+1
        JR NC,STD_CVAL
        ADD A,32
STD_CVAL:
        LD L,A
        LD H,0FFH
        XOR A
        PUSH IX
        RET

STD_ATOZ:
        CALL STD_CHAR
        OR 20H                     ; Fold upper case onto lower case.
        CP 'a'
        JP C,STD_NO
        CP 'z'+1
        JP NC,STD_NO
        JP STD_YES
STD_0TO9:
        CALL STD_CHAR
        CP '0'
        JP C,STD_NO
        CP '9'+1
        JP NC,STD_NO
        JP STD_YES
STD_SPC:
        CALL STD_CHAR
        CP ' '
        JP Z,STD_YES
        CP 9                       ; Tab, line feed, vertical tab, form feed
        JP C,STD_NO                ; and carriage return are white space.
        CP 14
        JP C,STD_YES
        JP STD_NO

; ---- Strings --------------------------------------------------------------

; (substring string start end) copies bytes start..end-1 into a new string.
STD_SUBS:
        LD A,3
        CALL PKT_NARG
        CALL PKT_ARG0
        CALL STR_ARG
        JP C,ERROR
        LD (STD_PTR),HL
        LD HL,ARG_PKT+8
        CALL PKT_VAL
        CALL .INDEX
        LD (STD_END),A
        CALL PKT_ARG1
        CALL .INDEX
        LD (STD_BEG),A
        LD B,A
        LD A,(STD_END)
        CP B
        JP C,ERROR                 ; The end may not precede the start.
        LD C,A
        LD HL,(STD_PTR)
        LD A,(HL)
        CP C
        JP C,ERROR                 ; The end may not pass the string.
        LD A,C
        SUB B
        LD (STR_LEN),A
        CALL STR_NEW               ; The source stays rooted in the packet.
        JP C,ERROR
        LD A,(STR_LEN)
        LD (HL),A
        INC HL
        OR A
        JP Z,STR_RET
        EX DE,HL
        LD HL,(STD_PTR)
        INC HL
        LD A,(STD_BEG)
        LD C,A
        LD B,0
        ADD HL,BC
        LD A,(STR_LEN)
        LD C,A
        LDIR
        JP STR_RET
.INDEX:
        CP 3                       ; An index is a byte-sized exact integer.
        JP NZ,ERROR
        LD A,H
        OR A
        JP NZ,ERROR
        LD A,L
        RET

; ---- case -----------------------------------------------------------------

; Generated case code pushes the key on the operator side stack, then loads
; each datum into A:HL and calls here.  Z means the datum is eqv? to the key.
STD_CASE:
        EX DE,HL                   ; DE is the datum payload.
        LD C,A
        LD HL,(OPS_SP)
        DEC HL                     ; The key record's flags and tag.
        LD A,(HL)
        AND 0FH
        CP C
        RET NZ
        DEC HL                     ; Skip the extension byte.
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
STD_BUF: DS 7                      ; Digits of -32768 and shorter numbers.
STD_DIV:  DW 0                     ; Divisor for modulo.
STD_LIST: DW 0                     ; List being walked.
STD_LTAG: DB 0
STD_ACC:  DW 0                     ; Reversal accumulator; append's last cell.
STD_ATAG: DB 0
STD_CNT:  DB 0                     ; Lists still to append.
STD_RES: DW 0                      ; Side-stack record holding append's result.
STD_HEAD: DW 0                     ; Side-stack record holding the copy's head.
STD_MODE: DB 0                     ; Zero compares identity, one equal?.
STD_KEY:  DW 0                     ; Key for memq, member, assq and assoc.
STD_KTAG: DB 0
STD_ENT:  DW 0                     ; Matching association entry.
STD_ETAG: DB 0
STD_BEG:  DB 0                     ; substring start.
STD_END:  DB 0                     ; substring end.
