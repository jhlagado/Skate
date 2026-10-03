; Scope replay reader and nested frame state.
; Entry points: SCNEXT, SCRECOPN, SCRECPOP and SCRECSTR.
; Included in compiler order by ../replay.asm.

; A binding list is retained as compact reader events while all of its names
; are installed.  The frame stack lets a nested letrec append a temporary
; range, then resume the enclosing replay at the event after its list.

SCREBUF  EQU 0D740H              ; Four bytes per retained reader event.

; Dispatch compiler reads either to the source reader or to the retained list.
SCNEXT:
        LD A,(ST_PLAY)            ; Zero selects the ordinary source stream.
        OR A
        JP NZ,SCREPRD              ; Retained events already carry their numeric kind.
        CALL RD_NEXT               ; Read one event from the source reader.
        RET C                      ; Preserve the reader's latched error code.
        CP 7                       ; Scalar events may be exact or binary16 numerics.
        JR NZ,SCNOK                ; Other event kinds need no reader-tag adjustment.
        LD A,(RD_FLOAT)            ; Check whether this scalar came from decimal text.
        OR A
        JR Z,SCNEX                 ; Exact integers retain the ordinary kind seven.
        XOR A
        LD (RD_FLOAT),A            ; Consume the marker once it has become an event kind.
        LD A,87H                   ; High bit seven marks a binary16 source literal.
        RET                        ; RD_TAG:HL still contains the converted payload.
SCNEX:
        LD A,7                     ; Restore the event kind after reading the marker byte.
        OR A                       ; Exact numeric events return with carry clear.
        RET                        ; RD_TAG:HL still contains the exact payload.
SCNOK:
        OR A                       ; Source events return with carry clear.
        RET                        ; Preserve the reader contract for the caller.
SCREPRD:
        LD HL,(ST_GETP)           ; Read the next retained event.
        LD DE,(ST_EVEND)          ; Stop at the retained stream's actual end.
        OR A                      ; Clear carry before comparing the cursors.
        SBC HL,DE
        JR C,SCREPGET             ; A cursor below the end has one event left.
        LD A,(ST_BACK)             ; Definition replay returns to its source stream.
        OR A
        JR Z,SCREPERR
        CALL SCRECSTR
        JP C,SCREPERR
        LD A,(ST_PLAY)             ; Nested replay keeps its enclosing auto flag.
        OR A
        JP NZ,SCNEXT
        XOR A
        LD (ST_BACK),A
        JP SCNEXT
SCREPGET:
        LD HL,(ST_GETP)           ; Recover the event address after the check.
        LD A,(HL)                 ; Return its structural kind in A.
        INC HL
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
        JR NZ,SCNRET
        PUSH BC
        PUSH HL
        CALL SCSPELL               ; Rebuild the lexer spelling for replayed symbols.
        POP HL
        POP BC
SCNRET:
        LD A,C                    ; Restore the event kind after the address swap.
        OR A                      ; Replay success returns with carry clear.
        RET
SCREPERR:
        SCF                       ; The compiler treats an exhausted replay as bad input.
        RET

; Address the current sixteen-byte replay frame in the compiler workspace.
SCRECADR:
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
SCRECOPN:
        LD A,(ST_PLAYN)            ; Reject a nested source scope beyond the frame bound.
        CP 16
        JP NC,ERR_CAP
        INC A
        LD (ST_PLAYN),A
        CALL SCRECADR
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
        LD A,(ST_PLAY)             ; A top-level capture starts at SCREBUF.
        OR A
        JR NZ,SCRECPOK
        LD HL,SCREBUF
        LD (ST_PUTP),HL
SCRECPOK:
        XOR A
        RET

; Update the saved enclosing read cursor after a nested scanner consumes it.
SCRECSAV:
        CALL SCRECADR
        LD DE,(ST_GETP)
        LD BC,8
        ADD HL,BC
        LD (HL),E
        INC HL
        LD (HL),D
        RET

; Restore the recursive and replay state saved by SCRECOPN.
SCRECPOP:
        LD A,(ST_PLAYN)
        OR A
        SCF
        RET Z
        CALL SCRECADR
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
SCRECSTR:
        LD A,(ST_PLAYN)
        OR A
        SCF
        RET Z
        CALL SCRECADR
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
