; Scope replay reader and nested frame state.
; Entry points: REC_NEXT, REC_OPEN, REC_POP and REC_EXIT.
; Included in compiler order by ../replay.asm.

; A binding list is retained as compact reader events while all of its names
; are installed.  The frame stack lets a nested letrec append a temporary
; range, then resume the enclosing replay at the event after its list.

REC_BUF  EQU 0D740H              ; Four bytes per retained reader event.

; Dispatch compiler reads either to the source reader or to the retained list.
REC_NEXT:
        LD A,(ST_PLAY)            ; Zero selects the ordinary source stream.
        OR A
        JP NZ,.REPLAY              ; Retained events already carry their numeric kind.
        CALL RD_NEXT               ; Read one event from the source reader.
        RET C                      ; Preserve the reader's latched error code.
        CP 7                       ; Scalar events may be exact integers or floats.
        JR NZ,.SOURCE              ; Other event kinds need no reader-tag adjustment.
        LD A,(RD_FLOAT)            ; Check whether this scalar came from decimal text.
        OR A
        JR Z,.EXACT                ; Exact integers retain the ordinary kind seven.
        XOR A
        LD (RD_FLOAT),A            ; Consume the marker once it has become an event kind.
        LD A,87H                   ; High bit seven marks a float source literal.
        RET                        ; RD_TAG:HL still contains the converted payload.
.EXACT:
        LD A,7                     ; Restore the event kind after reading the marker byte.
        OR A                       ; Exact numeric events return with carry clear.
        RET                        ; RD_TAG:HL still contains the exact payload.
.SOURCE:
        OR A                       ; Source events return with carry clear.
        RET                        ; Preserve the reader contract for the caller.
.REPLAY:
        LD HL,(ST_GETP)           ; Read the next retained event.
        LD DE,(ST_EVEND)          ; Stop at the retained stream's actual end.
        OR A                      ; Clear carry before comparing the cursors.
        SBC HL,DE
        JR C,.GET                 ; A cursor below the end has one event left.
        LD A,(ST_BACK)             ; Definition replay returns to its source stream.
        OR A
        JR Z,.FAIL
        CALL REC_EXIT
        JP C,.FAIL
        LD A,(ST_PLAY)             ; Nested replay keeps its enclosing auto flag.
        OR A
        JP NZ,REC_NEXT
        XOR A
        LD (ST_BACK),A
        JP REC_NEXT
.GET:
        LD HL,(ST_GETP)           ; Recover the event address after the check.
        LD A,(HL)                 ; Return its structural kind in A.
        INC HL
        CP 9                      ; Kind 9 is an exact integer with byte 2.
        JR Z,.WIDE
        CP 10                     ; Kind 10 is a float with byte 2.
        JR Z,.FLOAT
        LD C,A                    ; Preserve the kind across tag and payload loads.
        LD A,(HL)                 ; Restore the scalar tag used by CMD_EXPR.
        LD (RD_TAG),A
        INC HL
        LD E,(HL)                 ; Reader payload low byte.
        INC HL
        LD D,(HL)                 ; Reader payload high byte.
        INC HL
        LD (ST_GETP),HL           ; Publish the next event cursor.
        EX DE,HL                  ; Return the saved payload in HL.
        LD A,C
        CP 5
        JR NZ,.RETURN
        PUSH BC
        PUSH HL
        CALL REC_NAME              ; Rebuild the lexer spelling for replayed symbols.
        POP HL
        POP BC
.RETURN:
        LD A,C                    ; Restore the event kind after the address swap.
        LD C,0                    ; Every replayed value but an integer has byte 2 zero.
        OR A                      ; Replay success returns with carry clear.
        RET
.FLOAT:
        LD A,9                    ; The record implies the float tag
        LD (RD_TAG),A
        LD A,87H                  ; and the float event.
        JR .THREE
.WIDE:
        LD A,3                    ; The record implies the exact-integer tag.
        LD (RD_TAG),A
        LD A,7                    ; CMD_EXPR sees an ordinary scalar event.
.THREE:
        PUSH AF
        LD E,(HL)                 ; Payload low byte.
        INC HL
        LD D,(HL)                 ; Payload high byte.
        INC HL
        LD C,(HL)                 ; Payload byte 2.
        INC HL
        LD (ST_GETP),HL           ; Publish the next event cursor.
        EX DE,HL
        POP AF
        OR A
        RET
.FAIL:
        SCF                       ; The compiler treats an exhausted replay as bad input.
        RET

; Address the current sixteen-byte replay frame in the compiler workspace.
REC_ADDR:
        LD A,(ST_PLAYN)            ; The depth is one based while a frame is open.
        DEC A                     ; Select the most recently opened record.
        LD L,A
        LD H,0
        ADD HL,HL                 ; Four doublings form a sixteen-byte stride.
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD DE,W_REPLAY
        ADD HL,DE
        RET

; Save the active recursive and replay state before entering a binding list.
REC_OPEN:
        LD A,(ST_PLAYN)            ; Reject a nested source scope beyond the frame bound.
        CP 16
        JP NC,ERR_CAP
        INC A
        LD (ST_PLAYN),A
        CALL REC_ADDR
        LD A,(ST_PLAY)             ; Save the enclosing replay mode.
        LD (HL),A
        INC HL
        LD A,(ST_RINIT)            ; Save its initializer phase.
        LD (HL),A
        INC HL
        LD A,(ST_RMODE)            ; Save its recursive scope mode.
        LD (HL),A
        INC HL
        LD A,(ST_RBASE)            ; Save its forward-slot range start.
        LD (HL),A
        INC HL
        LD A,(ST_RTOP)             ; Save its forward-slot range limit.
        LD (HL),A
        INC HL
        LD A,(ST_RPROC)            ; Save its owning procedure.
        LD (HL),A
        INC HL
        LD A,(ST_RPEND)            ; Save its deferred-record marker.
        LD (HL),A
        INC HL
        LD A,(ST_RCNT)             ; Save the enclosing declaration count.
        LD (HL),A
        INC HL
        LD DE,(ST_GETP)            ; Save the enclosing replay read cursor.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(ST_EVEND)           ; Save the enclosing replay end.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(ST_PUTP)            ; Save the shared append cursor.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(ST_BACK)             ; Save automatic stream restoration mode.
        LD (HL),A
        LD A,(ST_PLAY)             ; A top-level capture starts at REC_BUF.
        OR A
        JR NZ,.DONE
        LD HL,REC_BUF
        LD (ST_PUTP),HL
.DONE:
        XOR A
        RET

; Update the saved enclosing read cursor after a nested scanner consumes it.
REC_SAVE:
        CALL REC_ADDR
        LD DE,(ST_GETP)
        LD BC,8
        ADD HL,BC
        LD (HL),E
        INC HL
        LD (HL),D
        RET

; Restore the recursive and replay state saved by REC_OPEN.
REC_POP:
        LD A,(ST_PLAYN)
        OR A
        SCF
        RET Z
        CALL REC_ADDR
        LD A,(HL)
        LD (ST_PLAY),A
        INC HL
        LD A,(HL)
        LD (ST_RINIT),A
        INC HL
        LD A,(HL)
        LD (ST_RMODE),A
        INC HL
        LD A,(HL)
        LD (ST_RBASE),A
        INC HL
        LD A,(HL)
        LD (ST_RTOP),A
        INC HL
        LD A,(HL)
        LD (ST_RPROC),A
        INC HL
        LD A,(HL)
        LD (ST_RPEND),A
        INC HL
        LD A,(HL)
        LD (ST_RCNT),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_GETP),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_EVEND),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_PUTP),DE
        INC HL
        LD A,(HL)
        LD (ST_BACK),A
        LD A,(ST_PLAYN)
        DEC A
        LD (ST_PLAYN),A
        XOR A
        RET

; Restore only the saved stream cursors after an automatic replay.
REC_EXIT:
        LD A,(ST_PLAYN)
        OR A
        SCF
        RET Z
        CALL REC_ADDR
        LD A,(HL)
        LD (ST_PLAY),A
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_GETP),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_EVEND),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_PUTP),DE
        INC HL
        LD A,(HL)
        LD (ST_BACK),A
        LD A,(ST_PLAYN)
        DEC A
        LD (ST_PLAYN),A
        XOR A
        RET
