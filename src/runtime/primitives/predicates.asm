; Primitive logical and type predicates.
; Entry points: SRTNOT, SRTTYPE and canonical boolean results.
; Included in runtime order by ../primitives.asm.

; not and the type predicates return canonical boolean values.
SRTNOT:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTFALSE
        JP Z,SRTBYES
        JP SRTBNO
SRTTYPE:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD A,(SRTPID)
        CP 22
        JP Z,SRTTNUM
        CP 23
        JP Z,SRTTBOOL
        CP 24
        JP Z,SRTTSYM
        CP 25
        JP Z,SRTTPRO
        CP 26
        JP Z,SRTTSTR
        CP 27
        JP Z,SRTTCHAR
        JP SRTTEOF
SRTTNUM:
        LD A,(SRTNTAG)
        LD HL,(SRTNVAL)
        CALL SRTNCHK
        JP C,SRTBNO
        JP SRTBYES
SRTTBOOL:
        LD A,(SRTNTAG)
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JP Z,SRTBYES
        LD HL,(SRTNVAL)
        LD DE,0FE01H
        OR A
        SBC HL,DE
        JP Z,SRTBYES
        JP SRTBNO
SRTTSYM:
        LD A,(SRTNTAG)
        CP 4
        JP Z,SRTBYES
        JP SRTBNO
SRTTPRO:
        LD A,(SRTNTAG)
        CP 8
        JR NZ,SRTTPROC
        LD HL,(SRTNVAL)
        LD A,H
        CP 0F0H
        JP NC,SRTBNO                ; Port tokens are opaque, not procedures.
        JP SRTBYES
SRTTPROC:
        CP 2
        JP Z,SRTBYES
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD A,H
        CP 0FEH
        JP NZ,SRTBNO
        LD A,L
        CP 20H
        JP C,SRTBNO
        CP SRTPRLIM
        JP C,SRTBYES
        JP SRTBNO
SRTTSTR:
        LD A,(SRTNTAG)
        CP 5
        JP Z,SRTBYES
        CP 6
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        CALL SRTSVLD
        JP C,SRTBNO
        JP SRTBYES
SRTTCHAR:
        LD A,(SRTNTAG)
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD A,H
        CP 0FFH
        JP Z,SRTBYES
        JP SRTBNO
SRTTEOF:
        LD A,(SRTNTAG)
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD DE,0FE03H
        OR A
        SBC HL,DE
        JP NZ,SRTBNO
SRTBYES:
        LD A,1
SRTPBRES:
        OR A
        JR Z,SRTBZERO
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
SRTBZERO:
        XOR A
        LD HL,0FE00H
        PUSH IX
        RET
SRTBNO:
        XOR A
        JR SRTPBRES
