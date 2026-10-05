; Scope replay declaration installation and deferred stores.
; Entry points: REC_DECL, REC_SLOT, REC_PUSH and REC_FILL.
; Included in compiler order by ../replay.asm.

; Install every declaration before replaying any initializer.
REC_DECL:
        LD HL,(ST_EVLO)            ; Scan the retained range without consuming source.
        LD (ST_GETP),HL
        XOR A
        LD (ST_NEST),A             ; No binding pair is open yet.
        LD (ST_HEAD),A             ; No binding name is pending.
        LD (ST_RCNT),A
.LOOP:
        CALL REC_NEXT               ; Read the next retained structural event.
        RET C
        LD (ST_EVENT),A
        LD (ST_EVVAL),HL
        CP 1
        JR Z,.OPEN
        CP 2
        JR Z,.CLOSE
        CP 5
        JR NZ,.LOOP
        LD A,(ST_HEAD)
        OR A
        JR Z,.LOOP
        LD HL,(ST_EVVAL)
        LD (ST_SYMID),HL
        LD A,(ST_RCNT)
        CP 128
        JP NC,ERR_CAP
        CALL LET_DECL              ; Duplicate names are rejected here.
        RET C
        LD (ST_SLOT),A
        CALL EM_CLEAR              ; Every recursive cell starts unbound.
        RET C
        CALL REC_PUSH              ; Installation order drives reverse stores.
        RET C
        LD A,(ST_RCNT)
        INC A
        LD (ST_RCNT),A
        XOR A
        LD (ST_HEAD),A
        JR .LOOP
.OPEN:
        LD A,(ST_NEST)
        OR A
        JR NZ,.NEST
        LD A,1
        LD (ST_NEST),A
        LD A,1
        LD (ST_HEAD),A
        JR .LOOP
.NEST:
        INC A
        LD (ST_NEST),A
        JR .LOOP
.CLOSE:
        LD A,(ST_NEST)
        OR A
        JR Z,.DONE
        DEC A
        LD (ST_NEST),A
        JR .LOOP
.DONE:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        LD A,1
        LD (ST_PLAY),A
        XOR A
        RET

; The replay declaration already has a cell; return its active slot.
REC_SLOT:
        CALL BIND_HAS
        SCF
        RET NC
        OR A
        RET

; Append the selected declaration slot to the deferred initializer list.
REC_PUSH:
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
REC_FILL:
        LD A,(ST_BINDS)
        LD (ST_RIDX),A
        LD A,(ST_RPEND)
        LD (ST_RMARK),A
.LOOP:
        LD A,(ST_RIDX)
        LD C,A
        LD A,(ST_RMARK)
        CP C
        JR Z,.DONE
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
        JR .LOOP
.DONE:
        LD A,(ST_RMARK)
        LD (ST_BINDS),A
        XOR A
        RET
