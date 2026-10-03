; Quoted data stacks and list construction.
; Entry points: QT_PUSH, QT_POP and QT_FOLD.
; Included in runtime order by ../data.asm.

; Pair, quoted-list and literal output services for the generated runtime.
;
; Pair slabs contain 32 eight-byte records.  A record is two adjacent value
; cells: the first stores the CAR payload and metadata, and the second stores
; the CDR payload and metadata.  The first metadata byte retains the current
; allocation and mark bits; each cell carries its logical tag in the low
; nibble.  Logical pair values use tag one and the record address as their
; payload.  Symbols and strings use tags four and five and point at a
; length-prefixed output literal.

; Save one value on the quoted-data stack.
QT_PUSH:
        LD (QT_ATAG),A             ; Keep the logical tag across the bound check.
        LD (QT_ACC),HL             ; Keep the payload beside it.
        LD HL,(QT_SP)
        LD DE,4
        ADD HL,DE
        LD DE,RT_QTHI
        OR A
        SBC HL,DE
        JP NC,ERROR                ; A malformed quoted list cannot overrun the stack.
        LD (QT_NEXT),HL
        LD HL,(QT_SP)
        LD DE,(QT_ACC)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A                  ; The extension byte stays clear.
        INC HL
        LD A,(QT_ATAG)
        LD (HL),A
        INC HL
        LD (QT_SP),HL
        LD A,(QT_ATAG)
        LD HL,(QT_ACC)
        RET

; Pop one value from the quoted-data stack.
QT_POP:
        LD HL,(QT_SP)
        LD DE,RT_QTLO
        OR A
        SBC HL,DE
        JP Z,ERROR
        LD HL,(QT_SP)
        LD DE,4
        OR A
        SBC HL,DE
        LD (QT_SP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH
        EX DE,HL
        RET

; Fold the values on the quoted-data stack into a proper or dotted list.
QT_FOLD:
        LD (QT_CNT),A              ; A counts heads plus the optional tail.
        LD A,1
        LD (QT_HELD),A             ; The accumulator remains live across cons GC.
        LD A,B
        LD (QT_TAIL),A             ; B is nonzero for a dotted tail.
        OR A
        JR Z,.NIL
        CALL QT_POP                 ; The dotted tail is the initial accumulator.
        LD (QT_ATAG),A
        LD (QT_ACC),HL
        LD A,(QT_CNT)
        DEC A
        LD (QT_CNT),A
        JR .LOOP
.NIL:
        XOR A
        LD (QT_ATAG),A
        LD HL,0FE02H               ; Canonical empty-list value.
        LD (QT_ACC),HL
.LOOP:
        LD A,(QT_CNT)
        OR A
        JR Z,.DONE
        CALL QT_POP                 ; The preceding element becomes the new CAR.
        LD (QT_CTAG),A
        LD (QT_CAR),HL
        LD A,(QT_ATAG)
        LD (QT_DTAG),A
        LD HL,(QT_ACC)
        LD (QT_CDR),HL
        CALL PAIR_NEW
        LD (QT_ATAG),A
        LD (QT_ACC),HL
        LD A,(QT_CNT)
        DEC A
        LD (QT_CNT),A
        JR .LOOP
.DONE:
        LD A,(QT_ATAG)
        LD HL,(QT_ACC)
        XOR A
        LD (QT_HELD),A             ; The returned value is now held by its caller.
        LD A,(QT_ATAG)
        RET
