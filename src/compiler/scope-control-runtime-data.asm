; Pair, quoted-list and literal output services for the generated runtime.
;
; Pair cells are fixed eight-byte records in the separately collected arena:
; state, CAR payload/tag, CDR payload/tag, and one reserved byte.  Logical pair
; values use tag one and the record address as their payload.  Symbols and
; strings use tags four and five and point at a length-prefixed output literal.

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
        RET

; Construct a pair from the two scratch values used by both cons and lists.
SRTCONS:
        POP IX                     ; Preserve the generated continuation.
        POP DE                     ; Recover the CDR payload.
        POP BC                     ; Recover the CDR tag in B.
        POP HL                     ; Recover the CAR payload.
        POP AF                     ; Recover the CAR tag in A.
        LD (SRTQCDR),DE
        LD (SRTQCTAG),A
        LD A,B
        LD (SRTQDTAG),A
        LD (SRTQCAR),HL
        CALL SRTMAKEP
        PUSH IX
        RET

; Allocate, initialise and return one pair cell.
SRTMAKEP:
        CALL SRTFINDP
        JR NC,SRTPINIT
        CALL SRTGC                  ; Reclaim unreachable cells when full.
        CALL SRTFINDP
        JP C,SRTERROR
SRTPINIT:
        LD (SRTQPAIR),HL
        LD DE,(SRTQCAR)
        INC HL
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTQCTAG)
        LD (HL),A
        INC HL
        LD DE,(SRTQCDR)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTQDTAG)
        LD (HL),A
        LD HL,(SRTQPAIR)
        LD A,1
        RET

; Find and reserve a free pair record.
SRTFINDP:
        LD HL,SRTPAIRB
        LD BC,1024
SRTFPLP:
        LD A,(HL)
        OR A
        JR Z,SRTFPGET
        LD DE,8
        ADD HL,DE
        DEC BC
        LD A,B
        OR C
        JR NZ,SRTFPLP
        SCF
        RET
SRTFPGET:
        LD (HL),1
        XOR A
        RET

; Check A:HL and return carry clear only for a live pair pointer.
SRTPCHK:
        CP 1
        JR NZ,SRTNPAIR
        LD A,H
        CP 0A0H
        JR C,SRTNPAIR
        CP 0C0H
        JR NC,SRTNPAIR
        LD A,L
        AND 7
        JR NZ,SRTNPAIR
        LD A,(HL)
        OR A
        JR Z,SRTNPAIR
        XOR A
        RET
SRTNPAIR:
        SCF
        RET

; car and cdr selectors.
SRTCAR:
        POP IX
        POP HL
        POP AF
        CALL SRTCARV
        JP C,SRTERROR
        PUSH IX
        RET

SRTCARV:
        LD (SRTQAVAL),HL
        LD (SRTQATAG),A
        CALL SRTPCHK
        RET C
        LD HL,(SRTQAVAL)
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET
SRTCDR:
        POP IX
        POP HL
        POP AF
        CALL SRTCDRV
        JP C,SRTERROR
        PUSH IX
        RET

SRTCDRV:
        LD (SRTQAVAL),HL
        LD (SRTQATAG),A
        CALL SRTPCHK
        RET C
        LD HL,(SRTQAVAL)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; Return booleans for pair? and null?.
SRTPAIRP:
        POP IX
        POP HL
        POP AF
        CALL SRTPCHK
        JR C,SRTFPALS
        XOR A
        LD HL,1
        PUSH IX
        RET
SRTFPALS:
        XOR A
        LD HL,0
        PUSH IX
        RET
SRTNULLP:
        POP IX
        POP HL
        POP AF
        OR A
        JR NZ,SRTFPALS
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR NZ,SRTFPALS
        XOR A
        LD HL,1
        PUSH IX
        RET

; Conservative mark-and-sweep for the pair arena.  Every live pair pointer
; found outside the arena is treated as a root, which preserves safety when a
; value is temporarily held in a generated stack frame.
SRTGC:
        LD HL,SRTPAIRB
        LD BC,1024
SRTGCLR:
        LD A,(HL)
        CP 2
        JR NZ,SRTGCNX
        LD (HL),1
SRTGCNX:
        LD DE,8
        ADD HL,DE
        DEC BC
        LD A,B
        OR C
        JR NZ,SRTGCLR
        LD HL,SRTMKBS
        LD (SRTMSTK),HL
        LD HL,0100H
        LD DE,0A000H
        CALL SRTSCAN
        LD HL,0C000H
        LD DE,0E000H
        CALL SRTSCAN
SRTGWORK:
        LD HL,(SRTMSTK)
        LD DE,SRTMKBS
        OR A
        SBC HL,DE
        JR Z,SRTGSWEP
        LD HL,(SRTMSTK)
        LD DE,2
        OR A
        SBC HL,DE
        LD (SRTMSTK),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD A,1
        CALL SRTMARKV
        JR SRTGWORK
SRTGSWEP:
        LD HL,SRTPAIRB
        LD BC,1024
SRTGSLP:
        LD A,(HL)
        CP 2
        JR NZ,SRTGSN
        LD (HL),1
        JR SRTGSN2
SRTGSN:
        XOR A
        LD (HL),A
SRTGSN2:
        LD DE,8
        ADD HL,DE
        DEC BC
        LD A,B
        OR C
        JR NZ,SRTGSLP
        RET

; Scan a half-open byte range for the three-byte pattern payload,tag-one.
SRTSCAN:
        LD (SRTSCP),HL
        LD (SRTSCE),DE
SRTSCLP:
        LD HL,(SRTSCP)
        LD DE,(SRTSCE)
        OR A
        SBC HL,DE
        JR NC,SRTSCEND
        LD HL,(SRTSCP)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        CP 1
        JR NZ,SRTSCNX
        EX DE,HL
        CALL SRTMARK
SRTSCNX:
        LD HL,(SRTSCP)
        INC HL
        LD (SRTSCP),HL
        JR SRTSCLP
SRTSCEND:
        RET

; Mark one pair and queue it for child scanning.
SRTMARK:
        LD A,H
        CP 0A0H
        RET C
        CP 0C0H
        RET NC
        LD A,L
        AND 7
        RET NZ
        LD A,(HL)
        CP 1
        RET NZ
        LD (HL),2
        LD DE,(SRTMSTK)
        LD A,D
        CP 0D4H
        RET NC
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (SRTMSTK),DE
        RET

; Trace the CAR and CDR pair edges of one queued record.
SRTMARKV:
        LD (SRTMVAL),HL
        LD A,1
        CALL SRTPCHK
        RET C
        ; Mark the CAR edge when it is itself a pair.
        LD HL,(SRTMVAL)
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        CP 1
        JR NZ,SRTMVC
        EX DE,HL
        JP SRTMARK

SRTMVC:
        ; The CDR payload begins four bytes after the pair state byte.
        LD HL,(SRTMVAL)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        CP 1
        RET NZ
        EX DE,HL
        JP SRTMARK

; Write a value using CP/M function two, including nested pair structure.
SRTWRVAL:
        CP 3
        JP Z,SRTWRNUM
        CP 1
        JP Z,SRTWPAIR
        CP 4
        JP Z,SRTWRLIT
        CP 5
        JP Z,SRTWRSTR
        OR A
        JP NZ,SRTERROR
        PUSH HL
        LD DE,0FE02H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWNIL
        PUSH HL
        LD DE,0FE04H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWUNS
        LD DE,SRTWQF
        LD A,H
        OR L
        JR Z,SRTWMSG
        LD DE,SRTWQT
SRTWMSG:
        LD C,9
        JP 5

SRTWNIL:
        LD DE,SRTWNILT
        LD C,9
        JP 5

SRTWUNS:
        LD DE,SRTWUNST
        LD C,9
        JP 5

SRTWPAIR:
        PUSH HL                     ; CP/M output is allowed to clobber HL.
        LD A,'('
        CALL SRTCH
        POP HL
        PUSH HL                     ; Keep the outer pair while printing its CAR.
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        CALL SRTWRVAL
        POP HL
        PUSH HL                     ; Keep the outer pair while inspecting its CDR.
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        LD (SRTQATAG),A
        EX DE,HL
        LD (SRTQAVAL),HL
        LD A,(SRTQATAG)
        CP 1
        JR NZ,SRTWRDOT
        LD HL,(SRTQAVAL)
        CALL SRTPCHK
        JR C,SRTWRDOT
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWTAIL
        POP HL
        JR SRTWCLS
SRTWRDOT:
        LD A,(SRTQATAG)
        OR A
        JR NZ,SRTWRDV
        LD HL,(SRTQAVAL)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR Z,SRTWRNIL
SRTWRDV:
        LD A,' '
        CALL SRTCH
        LD A,'.'
        CALL SRTCH
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWRVAL
        POP HL
        JR SRTWCLS
SRTWRNIL:
        POP HL
        JR SRTWCLS
SRTWCLS:
        LD A,')'
        JP SRTCH

; Print the tail of a proper list without opening another parenthesis.
SRTWTAIL:
        PUSH HL                     ; Preserve this pair across its CAR output.
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        CALL SRTWRVAL
        POP HL
        PUSH HL                     ; Preserve this pair while inspecting its CDR.
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        LD (SRTQATAG),A
        EX DE,HL
        LD (SRTQAVAL),HL
        LD A,(SRTQATAG)
        CP 1
        JR NZ,SRTWTNIL
        LD HL,(SRTQAVAL)
        CALL SRTPCHK
        JR C,SRTWTDOT
        LD A,' '
        CALL SRTCH
        LD HL,(SRTQAVAL)
        CALL SRTWTAIL
        POP HL
        RET
SRTWTNIL:
        OR A
        JR NZ,SRTWTDOT
        LD HL,(SRTQAVAL)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR NZ,SRTWTDOT
        POP HL
        RET
SRTWTDOT:
        LD A,' '
        CALL SRTCH
        LD A,'.'
        CALL SRTCH
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWRVAL
        POP HL
        RET

SRTWRSTR:
        PUSH HL                     ; Preserve the literal pointer across BDOS.
        LD A,'"'
        CALL SRTCH
        POP HL
        CALL SRTWRLIT
        LD A,'"'
        JP SRTCH
SRTWRLIT:
        LD B,(HL)
        INC HL
SRTWLLP:
        LD A,B
        OR A
        RET Z
        LD A,(HL)
        INC HL
        PUSH HL                     ; Preserve the literal cursor across BDOS.
        PUSH BC                     ; Preserve the remaining count across BDOS.
        CALL SRTCH
        POP BC
        POP HL
        DJNZ SRTWLLP
        RET

SRTWRNUM:
        XOR A
        LD (SRTWBEG),A
        BIT 7,H
        JR Z,SRTWNP
        LD A,'-'
        CALL SRTCH
        XOR A
        SUB L
        LD L,A
        XOR A
        SBC A,H
        LD H,A
SRTWNP:
        LD DE,10000
        CALL SRTWDIG
        LD DE,1000
        CALL SRTWDIG
        LD DE,100
        CALL SRTWDIG
        LD DE,10
        CALL SRTWDIG
        LD A,1
        LD (SRTWBEG),A
        LD DE,1
        JP SRTWDIG
SRTWDIG:
        LD B,0
SRTWDL:
        OR A
        SBC HL,DE
        JR C,SRTWDD
        INC B
        JR SRTWDL
SRTWDD:
        ADD HL,DE
        LD A,B
        OR A
        JR NZ,SRTWDOUT
        LD A,(SRTWBEG)
        OR A
        RET Z
SRTWDOUT:
        LD A,1
        LD (SRTWBEG),A
        LD A,B
        ADD A,'0'
        JP SRTCH

SRTCH:
        LD E,A
        LD C,2
        JP 5

SRTWQF:    DB "#f$"
SRTWQT:    DB "#t$"
SRTWNILT: DB "()$"
SRTWUNST:  DB "#<unspecified>$"

SRTQSP:   DW SRTQBASE
SRTQNXT:  DW 0
SRTQCAR:  DW 0
SRTQCDR:  DW 0
SRTQAVAL: DW 0
SRTQPAIR: DW 0
SRTQCTAG: DB 0
SRTQDTAG: DB 0
SRTQATAG: DB 0
SRTQNR:   DB 0
SRTQDOTR: DB 0
SRTMSTK:  DW SRTMKBS
SRTSCP:   DW 0
SRTSCE:   DW 0
SRTMVAL:  DW 0
SRTMTAG:  DB 0
SRTWRP:   DW 0
SRTWBEG:  DB 0
