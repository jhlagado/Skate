; Quoted data and copied literal support for the compact compiler.
;
; The reader supplies one event at a time.  A quoted list therefore uses the
; generated runtime's four-byte data stack: each element is emitted normally,
; pushed at run time, and folded into pairs when the closing parenthesis arrives.
; Symbols and strings are copied into the output as length-prefixed literals.

; Compile the explicit (quote datum) form.
SCQUOTEF:
        CALL RNEXT                 ; Read the one datum after quote.
        RET C                      ; Preserve a source failure.
        CALL SCQDAT                ; Compile it without resolving symbols.
        RET C                      ; Reject malformed quoted structure.
        JP SCEXPECT                ; The quote form accepts exactly one datum.

; Compile the apostrophe shorthand.  Nested shorthand has the same value
; behaviour as quote for this first data release.
SCQSHRT:
        CALL RNEXT                 ; Read the datum following the prefix.
        RET C                      ; Preserve a reader failure.
        JP SCQDAT                  ; Emit the quoted value directly.

; Dispatch one quoted reader event.
SCQDAT:
        CP 7                       ; Exact integers and booleans are immediate.
        JP Z,SCNUM                 ; Existing scalar emission preserves RTAG.
        CP 5                       ; A symbol is copied as an immutable literal.
        JP Z,SCQSYM
        CP 8                       ; A string is copied with its byte length.
        JP Z,SCQSTR
        CP 1                       ; An opening parenthesis starts a data list.
        JP Z,SCQLIST
        CP 3                       ; Quoted shorthand inside data consumes one datum.
        JP Z,SCQSHRT
        JP SCSYN                   ; Close, dot and EOF are invalid datum starts.

; Copy a quoted symbol into the output and return a tag-four value.
SCQSYM:
        LD A,4                     ; Runtime tag four identifies a symbol literal.
        JP SCLITADD

; Copy a quoted string into the output and return a tag-five value.
SCQSTR:
        LD A,5                     ; Runtime tag five identifies a string literal.
        JP SCLITADD

; Compile one quoted list.  Elements are pushed in source order; the runtime
; folds them from the end so both proper and dotted lists retain that order.
SCQLIST:
        LD A,(SCQCOUNT)            ; Preserve a surrounding quoted-list cursor.
        PUSH AF
        LD A,(SCQDOT)              ; Preserve a surrounding dotted-list marker.
        PUSH AF
        XOR A                      ; The new list starts with no elements.
        LD (SCQCOUNT),A
        LD (SCQDOT),A
SCQLP:
        CALL RNEXT                 ; Read an element, dot or the closing parenthesis.
        JP C,SCQFAIL               ; Restore the surrounding list state.
        CP 2                       ; A close finishes a proper list.
        JP Z,SCQEND                ; The list body can exceed a short-branch range.
        CP 4                       ; A dot switches to one required tail datum.
        JP Z,SCQDOTF
        CP 0                       ; EOF cannot close an open quoted list.
        JP Z,SCQFAIL
        LD (SCQEV),A               ; Save the event while nested code is emitted.
        LD (SCQVAL),HL             ; Preserve its payload across SCQDAT.
        LD A,(RTAG)
        LD (SCQTAG),A
        LD A,(SCQCOUNT)            ; Keep this list's counters below nested data.
        PUSH AF
        LD A,(SCQDOT)
        PUSH AF
        LD A,(SCQTAG)
        LD (RTAG),A
        LD A,(SCQEV)
        LD HL,(SCQVAL)
        CALL SCQDAT                ; A:HL becomes the element's run-time value.
        JP C,SCQBADN               ; Balance both saved counters on failure.
        POP AF                     ; Restore this list's dotted marker.
        LD (SCQDOT),A
        POP AF                     ; Restore this list's element count.
        LD (SCQCOUNT),A
        CALL SCQPUT                ; Push the complete value at run time.
        RET C
        LD A,(SCQCOUNT)
        INC A
        LD (SCQCOUNT),A
        CP 64                      ; Keep the generated data stack bounded.
        JP NC,SCCAP
        JP SCQLP

SCQDOTF:
        LD A,(SCQDOT)              ; A second dot is malformed.
        OR A
        JP NZ,SCSYN
        LD A,(SCQCOUNT)            ; A dotted list needs at least one head.
        OR A
        JP Z,SCSYN
        CALL RNEXT                 ; Read exactly one dotted-tail datum.
        JP C,SCQFAIL
        CP 2
        JP Z,SCSYN
        CP 4
        JP Z,SCSYN
        LD (SCQEV),A
        LD (SCQVAL),HL
        LD A,(RTAG)
        LD (SCQTAG),A
        LD A,(SCQCOUNT)
        PUSH AF
        LD A,(SCQDOT)
        PUSH AF
        LD A,(SCQTAG)
        LD (RTAG),A
        LD A,(SCQEV)
        LD HL,(SCQVAL)
        CALL SCQDAT
        JP C,SCQBADN
        POP AF
        LD (SCQDOT),A
        POP AF
        LD (SCQCOUNT),A
        CALL SCQPUT
        RET C
        LD A,(SCQCOUNT)
        INC A
        LD (SCQCOUNT),A
        LD A,1
        LD (SCQDOT),A
        CALL RNEXT                 ; The dotted tail must be followed by close.
        JP C,SCQFAIL
        CP 2
        JP NZ,SCSYN

SCQEND:
        LD A,(SCQCOUNT)            ; Runtime receives the number of stack values.
        LD A,(SCQDOT)              ; Read the dotted-list marker through A.
        LD B,A                     ; B distinguishes proper from dotted folding.
        CALL SCQBUILD              ; Return the completed list as A:HL.
        JP C,SCQFAIL
        POP AF                     ; Restore the enclosing dotted marker.
        LD (SCQDOT),A
        POP AF                     ; Restore the enclosing element count.
        LD (SCQCOUNT),A
        OR A                       ; Return carry clear with the list value live.
        RET

SCQBADN:
        POP AF                     ; Discard the saved dotted marker.
        POP AF                     ; Discard the saved element count.
SCQFAIL:
        POP AF                     ; Restore the enclosing dotted marker.
        LD (SCQDOT),A
        POP AF                     ; Restore the enclosing element count.
        SCF
        RET

; Emit the run-time data-stack push used by quoted lists.
SCQPUT:
        LD HL,SRTQPUT
        JP SCCALL

; Emit the run-time list fold.  A is the number of values and B the dot flag.
SCQBUILD:
        LD A,3EH
        CALL SCBYTE
        RET C
        LD A,(SCQCOUNT)
        CALL SCBYTE
        RET C
        LD A,6                     ; LD B,n carries the dotted-list marker.
        CALL SCBYTE
        RET C
        LD A,(SCQDOT)
        CALL SCBYTE
        RET C
        LD HL,SRTQBLD
        JP SCCALL

; Add one symbol or string spelling to the bounded literal pool.  A is the
; eventual runtime tag (four for symbol, five for string), HL is the reader ID.
SCLITADD:
        LD (SCLITKND),A
        LD (SCLITVAL),HL
        LD A,(SCLITN)
        CP 64
        JP NC,SCCAP
        LD HL,(SCLITVAL)
        LD A,H
        AND 1FH                    ; Remove the reader's reference subtype.
        LD H,A
        LD A,(SCLITKND)
        CP 4
        JP Z,SCLITSYM

; String descriptor: four bytes per identity and an arbitrary byte length.
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        LD DE,SCSTRDS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCLITOFF),DE
        INC HL
        LD A,(HL)
        LD (SCLITLEN),A
        LD DE,SCSTRPL
        LD (SCLITPB),DE
        JP SCLITSP

; Symbol descriptor: three bytes per identity and a one-byte length.
SCLITSYM:
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,DE
        LD DE,SCNAMEDS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCLITOFF),DE
        INC HL
        LD A,(HL)
        LD (SCLITLEN),A
        LD DE,SCNAMEPL
        LD (SCLITPB),DE
SCLITSP:
        LD A,(SCLITLEN)
        LD C,A
        LD B,0
        LD (SCLITREM),BC
        LD HL,(SCLITUSE)
        LD (SCLITPOF),HL
        ADD HL,BC
        LD DE,SCLITPSZ
        OR A
        SBC HL,DE
        JP NC,SCCAP
        LD HL,(SCLITOFF)
        LD DE,(SCLITPB)
        ADD HL,DE
        LD (SCLITSRC),HL
        LD HL,(SCLITUSE)
        LD DE,SCLITPL
        ADD HL,DE
        LD (SCLITDST),HL
        LD BC,(SCLITREM)
        LD DE,(SCLITDST)
        LD HL,(SCLITSRC)
        LDIR
        LD HL,(SCLITUSE)
        LD DE,(SCLITREM)
        ADD HL,DE
        LD (SCLITUSE),HL
        LD A,(SCLITN)
        LD (SCLITIDX),A
        CALL SCLITRCA
        LD DE,(SCLITPOF)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SCLITLEN)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        LD A,(SCLITN)
        INC A
        LD (SCLITN),A
        JP SCLITPTR

; Emit a literal pointer placeholder and remember its record index.
SCLITPTR:
        LD A,21H
        CALL SCBYTE
        RET C
        LD HL,(SCPC)
        LD A,3                     ; Fixup kind three selects SCLITOUT.
        LD (SCFKIND),A
        LD A,(SCLITIDX)
        LD (SCFSLOT),A
        CALL SCFIX
        RET C
        XOR A
        CALL SCBYTE
        RET C
        CALL SCBYTE
        RET C
        LD A,3EH
        CALL SCBYTE
        RET C
        LD A,(SCLITKND)
        JP SCBYTE

; Append copied literals after generated code, slots and procedure records.
SCLITDAT:
        LD A,(SCLITN)
        LD (SCLITRC8),A
        XOR A
        LD (SCLITIDX),A
SCLITDL:
        LD A,(SCLITRC8)
        OR A
        JP Z,SCLITDD
        LD A,(SCLITIDX)
        CALL SCLITRCA
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCLITOFF),DE
        INC HL
        LD A,(HL)
        LD (SCLITLEN),A
        LD HL,(SCPC)
        LD (SCLITBAS),HL
        LD A,(SCLITLEN)
        CALL SCBYTE
        RET C
        LD HL,(SCLITOFF)
        LD DE,SCLITPL
        ADD HL,DE
        LD (SCLITSRC),HL
        LD A,(SCLITLEN)
        LD (SCLITRM8),A
SCLITDB:
        LD A,(SCLITRM8)
        OR A
        JP Z,SCLITDN
        LD HL,(SCLITSRC)
        LD A,(HL)
        INC HL
        LD (SCLITSRC),HL
        CALL SCBYTE
        RET C
        LD A,(SCLITRM8)
        DEC A
        LD (SCLITRM8),A
        JP SCLITDB
SCLITDN:
        LD A,(SCLITIDX)
        CALL SCLITOA
        LD DE,(SCLITBAS)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(SCLITIDX)
        INC A
        LD (SCLITIDX),A
        LD A,(SCLITRC8)
        LD B,A
        LD A,(SCLITIDX)
        CP B
        JP C,SCLITDL
SCLITDD:
        LD HL,(SCPC)
        XOR A
        RET

; Address one four-byte literal record or two-byte output-base entry.
SCLITRCA:
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SCLITREC
        ADD HL,DE
        RET
SCLITOA:
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCLITOUT
        ADD HL,DE
        RET

SCLITKND: DB 0
SCLITIDX:  DB 0
SCLITN:    DB 0
SCLITLEN:  DB 0
SCLITRM8: DB 0
SCLITRC8: DB 0
SCLITDOT:  DB 0
SCLITVAL:  DW 0
SCLITUSE: DW 0
SCLITPOF: DW 0
SCLITREM:  DW 0
SCLITOFF:  DW 0
SCLITBAS:  DW 0
SCLITDST:  DW 0
SCLITSRC:  DW 0
SCLITPB: DW 0
SCQCOUNT:  DB 0
SCQDOT:    DB 0
SCQEV:     DB 0
SCQTAG:    DB 0
SCQVAL:    DW 0
