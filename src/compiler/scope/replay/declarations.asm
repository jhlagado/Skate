; Scope replay declaration installation and deferred stores.
; Entry points: SCRECPRE, SCRECUSE, SCRECPEN and SCRECSTO.
; Included in compiler order by ../replay.asm.

; Install every declaration before replaying any initializer.
SCRECPRE:
        LD HL,(ST_EVLO)            ; Scan the retained range without consuming source.
        LD (ST_GETP),HL
        XOR A
        LD (ST_NEST),A             ; No binding pair is open yet.
        LD (ST_HEAD),A             ; No binding name is pending.
        LD (ST_RCNT),A
SCRECPRL:
        CALL SCNEXT                 ; Read the next retained structural event.
        RET C
        LD (ST_EVENT),A
        LD (ST_EVVAL),HL
        CP 1
        JR Z,SCRECPRO
        CP 2
        JR Z,SCRECCPR
        CP 5
        JR NZ,SCRECPRL
        LD A,(ST_HEAD)
        OR A
        JR Z,SCRECPRL
        LD HL,(ST_EVVAL)
        LD (ST_SYMID),HL
        LD A,(ST_RCNT)
        CP 128
        JP NC,ERR_CAP
        CALL SCRECDEC              ; Duplicate names are rejected here.
        RET C
        LD (ST_SLOT),A
        CALL EM_CLEAR              ; Every recursive cell starts unbound.
        RET C
        CALL SCRECPEN              ; Installation order drives reverse stores.
        RET C
        LD A,(ST_RCNT)
        INC A
        LD (ST_RCNT),A
        XOR A
        LD (ST_HEAD),A
        JR SCRECPRL
SCRECPRO:
        LD A,(ST_NEST)
        OR A
        JR NZ,SCRECINC
        LD A,1
        LD (ST_NEST),A
        LD A,1
        LD (ST_HEAD),A
        JR SCRECPRL
SCRECINC:
        INC A
        LD (ST_NEST),A
        JR SCRECPRL
SCRECCPR:
        LD A,(ST_NEST)
        OR A
        JR Z,SCRECPRD
        DEC A
        LD (ST_NEST),A
        JR SCRECPRL
SCRECPRD:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        LD A,1
        LD (ST_PLAY),A
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
        LD A,(ST_BINDS)
        CP 128
        JP NC,ERR_CAP
        LD L,A
        LD H,0
        LD DE,W_BSLOTS
        ADD HL,DE
        LD A,(ST_SLOT)
        LD (HL),A
        LD A,(ST_BINDS)
        INC A
        LD (ST_BINDS),A
        XOR A
        RET

; Pop deferred values in reverse declaration order and initialize their cells.
SCRECSTO:
        LD A,(ST_BINDS)
        LD (ST_RIDX),A
        LD A,(ST_RPEND)
        LD (ST_RMARK),A
SCRECSTL:
        LD A,(ST_RIDX)
        LD C,A
        LD A,(ST_RMARK)
        CP C
        JR Z,SCRECSTD
        LD A,C
        DEC A
        LD (ST_RIDX),A
        LD L,A
        LD H,0
        LD DE,W_BSLOTS
        ADD HL,DE
        LD A,(HL)
        LD (ST_SLOT),A
        CALL EM_POP                ; Recover the value saved after its initializer.
        RET C
        LD A,(ST_SLOT)
        LD L,A
        LD A,1
        CALL EM_STORE
        RET C
        JR SCRECSTL
SCRECSTD:
        LD A,(ST_RMARK)
        LD (ST_BINDS),A
        XOR A
        RET
