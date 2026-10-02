; Scope replay capture of binding-list events.
; Entry points: SCRECBUF, SCRECPUT and SCRECCLS.
; Included in compiler order by ../replay.asm.

; Capture the binding-list tail after SCLETSET has consumed its opening list.
SCRECBUF:
        LD HL,(SCRECWP)            ; Nested scopes append after the outer stream.
        LD (SCRECBAS),HL           ; This range is the replay source for the scope.
        XOR A
        LD (SCRECCNT),A           ; No declarations have been recorded yet.
        LD (SCREDEP),A            ; The binding list is at structural depth zero.
        LD (SCRECHD),A            ; No binding header is awaiting its symbol.
SCRECSCN:
        LD A,(SCREP)               ; A nested scope reads from its enclosing stream.
        OR A
        JR Z,SCRECRN               ; The outermost scope reads the source directly.
        CALL SCNEXT                ; Consume the enclosing retained event stream.
        JR SCRECGET
SCRECRN:
        CALL RNEXT                 ; Scan the real source once, without replay.
SCRECGET:
        RET C                      ; Preserve source I/O or syntax failure.
        LD (SCBEV),A              ; Save the event while it is copied.
        LD (SCBVAL),HL
        LD A,(RTAG)
        LD (SCBTAG),A
        CALL SCRECPUT              ; Store kind, tag and payload as four bytes.
        RET C
        LD A,(SCRECHD)             ; The first item in a binding must be a symbol.
        OR A
        JR Z,SCRECSHP
        LD A,(SCBEV)
        CP 5
        JR NZ,SCRECBAD              ; A malformed binding cannot be predeclared.
        LD A,(SCRECCNT)
        INC A
        LD (SCRECCNT),A
        XOR A
        LD (SCRECHD),A
SCRECSHP:
        LD A,(SCBEV)
        CP 1
        JR Z,SCRECOP
        CP 2
        JR Z,SCRECCLS
        JR SCRECSCN
SCRECOP:
        LD A,(SCREDEP)
        OR A
        JR NZ,SCRECNI
        LD A,1                    ; The opening event starts a binding pair.
        LD (SCREDEP),A
        LD A,1
        LD (SCRECHD),A
        JR SCRECSCN
SCRECNI:
        INC A
        LD (SCREDEP),A
        JR SCRECSCN
SCRECCLS:
        LD A,(SCREDEP)
        OR A
        JR Z,SCRECDN              ; This close ends the binding container.
        DEC A
        LD (SCREDEP),A
        JR SCRECSCN
SCRECBAD:
        SCF
        RET
SCRECDN:
        LD A,(SCREP)               ; Preserve the enclosing cursor after a nested scan.
        OR A
        JR Z,SCRECOUT
        CALL SCRECSAV
SCRECOUT:
        LD HL,(SCRECBAS)           ; Replay starts at this scope's first event.
        LD (SCRECRP),HL
        LD HL,(SCRECWP)           ; The cursor also defines the retained extent.
        LD (SCREWEND),HL
        LD A,1                     ; SCNEXT now reads the retained binding stream.
        LD (SCREP),A
        XOR A
        RET

; Append one saved event from SCBEV/SCBTAG/SCBVAL.
SCRECPUT:
        LD HL,(SCRECWP)
        LD DE,SCRECEND
        OR A
        SBC HL,DE
        JP NC,SCCAP
        LD HL,(SCRECWP)
        LD A,(SCBEV)
        LD (HL),A
        INC HL
        LD A,(SCBTAG)
        LD (HL),A
        INC HL
        LD DE,(SCBVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (SCRECWP),HL
        XOR A
        RET
