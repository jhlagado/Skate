; Quoted data stacks and list construction.
; Entry points: SRTQPUT, SRTQPOP and SRTQBLD.
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
SRTQPUT:
        LD (SRTQATAG),A            ; Keep the logical tag across the bound check.
        LD (SRTQAVAL),HL           ; Keep the payload beside it.
        LD HL,(SRTQSP)
        LD DE,4
        ADD HL,DE
        LD DE,SRTQEND
        OR A
        SBC HL,DE
        JP NC,SRTERROR             ; A malformed quoted list cannot overrun the stack.
        LD (SRTQNXT),HL
        LD HL,(SRTQSP)
        LD DE,(SRTQAVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTQATAG)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD (SRTQSP),HL
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        RET

; Pop one value from the quoted-data stack.
SRTQPOP:
        LD HL,(SRTQSP)
        LD DE,SRTQBASE
        OR A
        SBC HL,DE
        JP Z,SRTERROR
        LD HL,(SRTQSP)
        LD DE,4
        OR A
        SBC HL,DE
        LD (SRTQSP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; Fold the values on the quoted-data stack into a proper or dotted list.
SRTQBLD:
        LD (SRTQNR),A              ; A counts heads plus the optional tail.
        LD A,1
        LD (SRTQACTV),A            ; The accumulator remains live across cons GC.
        LD A,B
        LD (SRTQDOTR),A            ; B is nonzero for a dotted tail.
        OR A
        JR Z,SRTQNIL
        CALL SRTQPOP                ; The dotted tail is the initial accumulator.
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQNR)
        DEC A
        LD (SRTQNR),A
        JR SRTQLP
SRTQNIL:
        XOR A
        LD (SRTQATAG),A
        LD HL,0FE02H               ; Canonical empty-list value.
        LD (SRTQAVAL),HL
SRTQLP:
        LD A,(SRTQNR)
        OR A
        JR Z,SRTQDONE
        CALL SRTQPOP                ; The preceding element becomes the new CAR.
        LD (SRTQCTAG),A
        LD (SRTQCAR),HL
        LD A,(SRTQATAG)
        LD (SRTQDTAG),A
        LD HL,(SRTQAVAL)
        LD (SRTQCDR),HL
        CALL SRTMAKEP
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQNR)
        DEC A
        LD (SRTQNR),A
        JR SRTQLP
SRTQDONE:
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        XOR A
        LD (SRTQACTV),A            ; The returned value is now held by its caller.
        LD A,(SRTQATAG)
        RET
