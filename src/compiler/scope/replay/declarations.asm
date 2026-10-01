; Scope replay declaration installation and deferred stores.
; Entry points: SCRECPRE, SCRECUSE, SCRECPEN and SCRECSTO.
; Included in compiler order by ../replay.asm.

; Install every declaration before replaying any initializer.
SCRECPRE:
        LD HL,(SCRECBAS)           ; Scan the retained range without consuming source.
        LD (SCRECRP),HL
        XOR A
        LD (SCREDEP),A             ; No binding pair is open yet.
        LD (SCRECHD),A             ; No binding name is pending.
        LD (SCRECCNT),A
SCRECPRL:
        CALL SCNEXT                 ; Read the next retained structural event.
        RET C
        LD (SCBEV),A
        LD (SCBVAL),HL
        CP 1
        JR Z,SCRECPRO
        CP 2
        JR Z,SCRECCPR
        CP 5
        JR NZ,SCRECPRL
        LD A,(SCRECHD)
        OR A
        JR Z,SCRECPRL
        LD HL,(SCBVAL)
        LD (SCID),HL
        LD A,(SCRECCNT)
        CP 128
        JP NC,SCCAP
        CALL SCRECDEC              ; Duplicate names are rejected here.
        RET C
        LD (SCSLOT),A
        CALL SCCLEAR               ; Every recursive cell starts unbound.
        RET C
        CALL SCRECPEN              ; Installation order drives reverse stores.
        RET C
        LD A,(SCRECCNT)
        INC A
        LD (SCRECCNT),A
        XOR A
        LD (SCRECHD),A
        JR SCRECPRL
SCRECPRO:
        LD A,(SCREDEP)
        OR A
        JR NZ,SCRECINC
        LD A,1
        LD (SCREDEP),A
        LD A,1
        LD (SCRECHD),A
        JR SCRECPRL
SCRECINC:
        INC A
        LD (SCREDEP),A
        JR SCRECPRL
SCRECCPR:
        LD A,(SCREDEP)
        OR A
        JR Z,SCRECPRD
        DEC A
        LD (SCREDEP),A
        JR SCRECPRL
SCRECPRD:
        LD HL,(SCRECBAS)
        LD (SCRECRP),HL
        LD A,1
        LD (SCREP),A
        XOR A
        RET

; The replay declaration already has a cell; return its active slot.
SCRECUSE:
        CALL SCLOCF
        SCF
        RET NC
        OR A
        RET

; Append the selected declaration slot to the deferred initializer list.
SCRECPEN:
        LD A,(SCBNDTOP)
        CP 128
        JP NC,SCCAP
        LD L,A
        LD H,0
        LD DE,SCBINDSL
        ADD HL,DE
        LD A,(SCSLOT)
        LD (HL),A
        LD A,(SCBNDTOP)
        INC A
        LD (SCBNDTOP),A
        XOR A
        RET

; Pop deferred values in reverse declaration order and initialize their cells.
SCRECSTO:
        LD A,(SCBNDTOP)
        LD (SCRECIDX),A
        LD A,(SCRECPND)
        LD (SCRECMRK),A
SCRECSTL:
        LD A,(SCRECIDX)
        LD C,A
        LD A,(SCRECMRK)
        CP C
        JR Z,SCRECSTD
        LD A,C
        DEC A
        LD (SCRECIDX),A
        LD L,A
        LD H,0
        LD DE,SCBINDSL
        ADD HL,DE
        LD A,(HL)
        LD (SCSLOT),A
        CALL SCPOP                 ; Recover the value saved after its initializer.
        RET C
        LD A,(SCSLOT)
        LD L,A
        LD A,1
        CALL SCSTORE
        RET C
        JR SCRECSTL
SCRECSTD:
        LD A,(SCRECMRK)
        LD (SCBNDTOP),A
        XOR A
        RET
