; Scope replay capture of binding-list events.
; Entry points: SCRECBUF, SCRECPUT and SCRECCLS.
; Included in compiler order by ../replay.asm.

; Capture the binding-list tail after SCLETSET has consumed its opening list.
SCRECBUF:
        LD HL,(ST_PUTP)            ; Nested scopes append after the outer stream.
        LD (ST_EVLO),HL            ; This range is the replay source for the scope.
        XOR A
        LD (ST_RCNT),A            ; No declarations have been recorded yet.
        LD (ST_NEST),A            ; The binding list is at structural depth zero.
        LD (ST_HEAD),A            ; No binding header is awaiting its symbol.
SCRECSCN:
        CALL SCNEXT                ; Source or enclosing replay; binary16 literals
                                   ; are captured as 87H so replay keeps them.
        RET C                      ; Preserve source I/O or syntax failure.
        LD (ST_EVENT),A           ; Save the event while it is copied.
        LD (ST_EVVAL),HL
        LD A,(RD_TAG)
        LD (ST_EVTAG),A
        CALL SCRECPUT              ; Store kind, tag and payload as four bytes.
        RET C
        LD A,(ST_HEAD)             ; The first item in a binding must be a symbol.
        OR A
        JR Z,SCRECSHP
        LD A,(ST_EVENT)
        CP 5
        JR NZ,SCRECBAD              ; A malformed binding cannot be predeclared.
        LD A,(ST_RCNT)
        INC A
        LD (ST_RCNT),A
        XOR A
        LD (ST_HEAD),A
SCRECSHP:
        LD A,(ST_EVENT)
        CP 1
        JR Z,SCRECOP
        CP 2
        JR Z,SCRECCLS
        JR SCRECSCN
SCRECOP:
        LD A,(ST_NEST)
        OR A
        JR NZ,SCRECNI
        LD A,1                    ; The opening event starts a binding pair.
        LD (ST_NEST),A
        LD A,1
        LD (ST_HEAD),A
        JR SCRECSCN
SCRECNI:
        INC A
        LD (ST_NEST),A
        JR SCRECSCN
SCRECCLS:
        LD A,(ST_NEST)
        OR A
        JR Z,SCRECDN              ; This close ends the binding container.
        DEC A
        LD (ST_NEST),A
        JR SCRECSCN
SCRECBAD:
        SCF
        RET
SCRECDN:
        LD A,(ST_PLAY)             ; Preserve the enclosing cursor after a nested scan.
        OR A
        JR Z,SCRECOUT
        CALL SCRECSAV
SCRECOUT:
        LD HL,(ST_EVLO)            ; Replay starts at this scope's first event.
        LD (ST_GETP),HL
        LD HL,(ST_PUTP)           ; The cursor also defines the retained extent.
        LD (ST_EVEND),HL
        LD A,1                     ; SCNEXT now reads the retained binding stream.
        LD (ST_PLAY),A
        XOR A
        RET

; Append one saved event from ST_EVENT/ST_EVTAG/ST_EVVAL.
SCRECPUT:
        LD HL,(ST_PUTP)
        LD DE,W_REPEND
        OR A
        SBC HL,DE
        JP NC,ERR_CAP
        LD HL,(ST_PUTP)
        LD A,(ST_EVENT)
        LD (HL),A
        INC HL
        LD A,(ST_EVTAG)
        LD (HL),A
        INC HL
        LD DE,(ST_EVVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (ST_PUTP),HL
        XOR A
        RET
