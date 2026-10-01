; Scope replay reader and nested frame state.
; Entry points: SCNEXT, SCRECOPN, SCRECPOP and SCRECSTR.
; Included in compiler order by ../replay.asm.

; A binding list is retained as compact reader events while all of its names
; are installed.  The frame stack lets a nested letrec append a temporary
; range, then resume the enclosing replay at the event after its list.

SCREBUF  EQU 0D740H              ; Four bytes per retained reader event.

; Dispatch compiler reads either to the source reader or to the retained list.
SCNEXT:
        LD A,(SCREP)              ; Zero selects the ordinary source stream.
        OR A
        JP NZ,SCREPRD              ; Retained events already carry their numeric kind.
        CALL RNEXT                 ; Read one event from the source reader.
        RET C                      ; Preserve the reader's latched error code.
        CP 7                       ; Scalar events may be exact or binary16 numerics.
        JR NZ,SCNOK                ; Other event kinds need no reader-tag adjustment.
        LD A,(RNUMFLT)             ; Check whether this scalar came from decimal text.
        OR A
        JR Z,SCNEX                 ; Exact integers retain the ordinary kind seven.
        XOR A
        LD (RNUMFLT),A             ; Consume the marker once it has become an event kind.
        LD A,87H                   ; High bit seven marks a binary16 source literal.
        RET                        ; RTAG:HL still contains the converted payload.
SCNEX:
        LD A,7                     ; Restore the event kind after reading the marker byte.
        OR A                       ; Exact numeric events return with carry clear.
        RET                        ; RTAG:HL still contains the exact payload.
SCNOK:
        OR A                       ; Source events return with carry clear.
        RET                        ; Preserve the reader contract for the caller.
SCREPRD:
        LD HL,(SCRECRP)           ; Read the next retained event.
        LD DE,(SCREWEND)          ; Stop at the retained stream's actual end.
        OR A                      ; Clear carry before comparing the cursors.
        SBC HL,DE
        JR C,SCREPGET             ; A cursor below the end has one event left.
        LD A,(SCRECAUT)            ; Definition replay returns to its source stream.
        OR A
        JR Z,SCREPERR
        CALL SCRECSTR
        JP C,SCREPERR
        LD A,(SCREP)               ; Nested replay keeps its enclosing auto flag.
        OR A
        JP NZ,SCNEXT
        XOR A
        LD (SCRECAUT),A
        JP SCNEXT
SCREPGET:
        LD HL,(SCRECRP)           ; Recover the event address after the check.
        LD A,(HL)                 ; Return its structural kind in A.
        INC HL
        LD C,A                    ; Preserve the kind across tag and payload loads.
        LD A,(HL)                 ; Restore the scalar tag used by SCEXPE.
        LD (RTAG),A
        INC HL
        LD E,(HL)                 ; Reader payload low byte.
        INC HL
        LD D,(HL)                 ; Reader payload high byte.
        INC HL
        LD (SCRECRP),HL           ; Publish the next event cursor.
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
        LD A,(SCRECFD)             ; The depth is one based while a frame is open.
        DEC A                     ; Select the most recently opened record.
        LD L,A
        LD H,0
        ADD HL,HL                 ; Four doublings form a sixteen-byte stride.
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD DE,SCRECFR
        ADD HL,DE
        RET

; Save the active recursive and replay state before entering a binding list.
SCRECOPN:
        LD A,(SCRECFD)             ; Reject a nested source scope beyond the frame bound.
        CP 16
        JP NC,SCCAP
        INC A
        LD (SCRECFD),A
        CALL SCRECADR
        LD A,(SCREP)               ; Save the enclosing replay mode.
        LD (HL),A
        INC HL
        LD A,(SCRECPHS)            ; Save its initializer phase.
        LD (HL),A
        INC HL
        LD A,(SCRECMOD)            ; Save its recursive scope mode.
        LD (HL),A
        INC HL
        LD A,(SCRECST)             ; Save its forward-slot range start.
        LD (HL),A
        INC HL
        LD A,(SCRECLIM)            ; Save its forward-slot range limit.
        LD (HL),A
        INC HL
        LD A,(SCRECPR)             ; Save its owning procedure.
        LD (HL),A
        INC HL
        LD A,(SCRECPND)            ; Save its deferred-record marker.
        LD (HL),A
        INC HL
        LD A,(SCRECCNT)            ; Save the enclosing declaration count.
        LD (HL),A
        INC HL
        LD DE,(SCRECRP)            ; Save the enclosing replay read cursor.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(SCREWEND)           ; Save the enclosing replay end.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(SCRECWP)            ; Save the shared append cursor.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SCRECAUT)            ; Save automatic stream restoration mode.
        LD (HL),A
        LD A,(SCREP)               ; A top-level capture starts at SCREBUF.
        OR A
        JR NZ,SCRECPOK
        LD HL,SCREBUF
        LD (SCRECWP),HL
SCRECPOK:
        XOR A
        RET

; Update the saved enclosing read cursor after a nested scanner consumes it.
SCRECSAV:
        CALL SCRECADR
        LD DE,(SCRECRP)
        LD BC,8
        ADD HL,BC
        LD (HL),E
        INC HL
        LD (HL),D
        RET

; Restore the recursive and replay state saved by SCRECOPN.
SCRECPOP:
        LD A,(SCRECFD)
        OR A
        SCF
        RET Z
        CALL SCRECADR
        LD A,(HL)
        LD (SCREP),A
        INC HL
        LD A,(HL)
        LD (SCRECPHS),A
        INC HL
        LD A,(HL)
        LD (SCRECMOD),A
        INC HL
        LD A,(HL)
        LD (SCRECST),A
        INC HL
        LD A,(HL)
        LD (SCRECLIM),A
        INC HL
        LD A,(HL)
        LD (SCRECPR),A
        INC HL
        LD A,(HL)
        LD (SCRECPND),A
        INC HL
        LD A,(HL)
        LD (SCRECCNT),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCRECRP),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCREWEND),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCRECWP),DE
        INC HL
        LD A,(HL)
        LD (SCRECAUT),A
        LD A,(SCRECFD)
        DEC A
        LD (SCRECFD),A
        XOR A
        RET

; Restore only the saved stream cursors after an automatic replay.
SCRECSTR:
        LD A,(SCRECFD)
        OR A
        SCF
        RET Z
        CALL SCRECADR
        LD A,(HL)
        LD (SCREP),A
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
        LD (SCRECRP),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCREWEND),DE
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCRECWP),DE
        INC HL
        LD A,(HL)
        LD (SCRECAUT),A
        LD A,(SCRECFD)
        DEC A
        LD (SCRECFD),A
        XOR A
        RET
