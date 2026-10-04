; Scope replay capture of binding-list events.
; Entry points: REC_KEEP, REC_PUT and .CLOSE.
; Included in compiler order by ../replay.asm.

; Capture the binding-list tail after LET_OPEN has consumed its opening list.
REC_KEEP:
        LD HL,(ST_PUTP)            ; Nested scopes append after the outer stream.
        LD (ST_EVLO),HL            ; This range is the replay source for the scope.
        XOR A
        LD (ST_RCNT),A            ; No declarations have been recorded yet.
        LD (ST_NEST),A            ; The binding list is at structural depth zero.
        LD (ST_HEAD),A            ; No binding header is awaiting its symbol.
.SCAN:
        CALL REC_NEXT              ; Source or enclosing replay; float literals
                                   ; are captured as 87H so replay keeps them.
        RET C                      ; Preserve source I/O or syntax failure.
        LD (ST_EVENT),A           ; Save the event while it is copied.
        LD (ST_EVVAL),HL
        LD A,C
        LD (ST_EVEXT),A
        LD A,(RD_TAG)
        LD (ST_EVTAG),A
        CALL REC_PUT               ; Store the event as four bytes.
        RET C
        LD A,(ST_HEAD)             ; The first item in a binding must be a symbol.
        OR A
        JR Z,.SHAPE
        LD A,(ST_EVENT)
        CP 5
        JR NZ,.BAD                  ; A malformed binding cannot be predeclared.
        LD A,(ST_RCNT)
        INC A
        LD (ST_RCNT),A
        XOR A
        LD (ST_HEAD),A
.SHAPE:
        LD A,(ST_EVENT)
        CP 1
        JR Z,.OPEN
        CP 2
        JR Z,.CLOSE
        JR .SCAN
.OPEN:
        LD A,(ST_NEST)
        OR A
        JR NZ,.NEST
        LD A,1                    ; The opening event starts a binding pair.
        LD (ST_NEST),A
        LD A,1
        LD (ST_HEAD),A
        JR .SCAN
.NEST:
        INC A
        LD (ST_NEST),A
        JR .SCAN
.CLOSE:
        LD A,(ST_NEST)
        OR A
        JR Z,.DONE                ; This close ends the binding container.
        DEC A
        LD (ST_NEST),A
        JR .SCAN
.BAD:
        SCF
        RET
.DONE:
        LD A,(ST_PLAY)             ; Preserve the enclosing cursor after a nested scan.
        OR A
        JR Z,.REPLAY
        CALL REC_SAVE
.REPLAY:
        LD HL,(ST_EVLO)            ; Replay starts at this scope's first event.
        LD (ST_GETP),HL
        LD HL,(ST_PUTP)           ; The cursor also defines the retained extent.
        LD (ST_EVEND),HL
        LD A,1                     ; REC_NEXT now reads the retained binding stream.
        LD (ST_PLAY),A
        XOR A
        RET

; Append one saved event from ST_EVENT/ST_EVTAG/ST_EVVAL/ST_EVEXT.  A record
; is the kind, the tag and the payload word, except that an exact integer is
; recorded as kind 9 and a float as kind 10, each with its three payload
; bytes and the tag implied.
REC_PUT:
        LD HL,(ST_PUTP)
        LD DE,W_REPEND
        OR A
        SBC HL,DE
        JP NC,ERR_CAP
        LD HL,(ST_PUTP)
        LD A,(ST_EVENT)
        CP 87H
        JR Z,.FLOAT
        CP 7
        JR NZ,.KIND
        LD A,(ST_EVTAG)
        CP 3
        LD A,7
        JR NZ,.KIND
        LD (HL),9                  ; Kind 9: an exact integer with byte 2.
        JR .WIDE
.FLOAT:
        LD (HL),10                 ; Kind 10: a float with byte 2.
.WIDE:
        INC HL
        LD DE,(ST_EVVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(ST_EVEXT)
        LD (HL),A
        JR .DONE
.KIND:
        LD (HL),A
        INC HL
        LD A,(ST_EVTAG)
        LD (HL),A
        INC HL
        LD DE,(ST_EVVAL)
        LD (HL),E
        INC HL
        LD (HL),D
.DONE:
        INC HL
        LD (ST_PUTP),HL
        XOR A
        RET
