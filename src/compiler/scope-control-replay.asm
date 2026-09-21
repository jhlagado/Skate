; A binding list is retained as compact reader events while all of its names
; are installed.  The frame stack lets a nested letrec append a temporary
; range, then resume the enclosing replay at the event after its list.

SCREBUF  EQU 0D600H              ; Four bytes per retained reader event.

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

; Restore LBUFFER/LBUFLEN for an interned symbol retained in a replay event.
SCSPELL:
        LD A,H                    ; Strip the symbol subtype from the identity.
        AND 01FH
        LD H,A
        LD B,H                    ; Preserve the thirteen-bit identity in BC.
        LD C,L
        ADD HL,HL                 ; Two identity bytes are not enough: use stride three.
        ADD HL,BC
        PUSH HL                   ; Retain the descriptor offset while reading the context.
        LD HL,(RSYMCTX)
        LD E,(HL)                 ; Descriptor table base, low byte.
        INC HL
        LD D,(HL)                 ; Descriptor table base, high byte.
        POP HL
        ADD HL,DE                 ; Address the selected three-byte descriptor.
        LD E,(HL)                 ; Packed-name offset, low byte.
        INC HL
        LD D,(HL)                 ; Packed-name offset, high byte.
        INC HL
        LD A,(HL)                 ; Symbol spelling length is the third descriptor byte.
        LD (LBUFLEN),A
        LD C,A                    ; LDIR takes the recovered length in the low byte.
        XOR A
        LD B,A                    ; The lexer limits symbol spellings to 31 bytes.
        PUSH DE                   ; Preserve the packed-name offset across context lookup.
        LD HL,(RSYMCTX)
        INC HL
        INC HL
        INC HL
        INC HL
        LD E,(HL)                 ; Symbol pool base, low byte.
        INC HL
        LD D,(HL)                 ; Symbol pool base, high byte.
        POP HL                    ; Recover the packed-name offset.
        ADD HL,DE                 ; HL now points at the permanent spelling bytes.
        LD DE,LBUFFER              ; The permanent spelling is the source; LBUFFER receives it.
        LDIR                       ; Recreate the normal lexer-buffer contract.
        RET

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
SCRECAP:
        SCF
        RET
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
