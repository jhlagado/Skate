; Scope compiler quoted forms and list construction.
; Entry points: SCQUOTEF, SCQDAT, SCQLIST and SCQBUILD.
; Included in compiler order by ../data.asm.

; Quoted data and copied literal support for the compact compiler.
;
; The reader supplies one event at a time.  A quoted list therefore uses the
; generated runtime's four-byte data stack: each element is emitted normally,
; pushed at run time, and folded into pairs when the closing parenthesis arrives.
; Symbols and strings are copied into the output as length-prefixed literals.

; Compile the explicit (quote datum) form.
SCQUOTEF:
        CALL SCNEXT                ; Read the one datum after quote.
        RET C                      ; Preserve a source failure.
        CALL SCQDAT                ; Compile it without resolving symbols.
        RET C                      ; Reject malformed quoted structure.
        JP SCEXPECT                ; The quote form accepts exactly one datum.

; Compile the apostrophe shorthand.  A nested apostrophe is data and therefore
; becomes the ordinary two-element list (quote datum).
SCQSHRT:
        CALL SCNEXT                ; Read the datum following the prefix.
        RET C                      ; Preserve a reader failure.
        CP 3                       ; A second apostrophe is a quoted symbol.
        JP Z,SCQNEST               ; Preserve it as (quote datum).
        JP SCQDAT                  ; Emit the quoted value directly.

; Emit the pair represented by a nested apostrophe: (quote datum).
SCQNEST:
        LD A,(SCQFIX)              ; Preserve the enclosing literal's cache index.
        PUSH AF
        CALL SCQCACH                ; Nested quote pairs are literals as well.
        JP C,SCNFAIL
        LD HL,SCQUOTE+1            ; Intern the reader's ordinary quote name.
        LD BC,5
        LD IX,SCNCTX
        CALL INTERN
        JP C,SCNFAIL
        LD A,4                     ; The quote operator is a symbol literal.
        CALL SCLITADD
        JP C,SCNFAIL
        CALL SCQPUT                ; Push quote as the first pair element.
        JP C,SCNFAIL
        CALL SCNEXT                ; Read the datum after the nested prefix.
        JP C,SCNFAIL
        CALL SCQDAT
        JP C,SCNFAIL
        CALL SCQPUT                ; Push the quoted datum as the second element.
        JP C,SCNFAIL
        LD A,2
        LD (SCQCOUNT),A
        XOR A
        LD (SCQDOT),A
        LD B,A
        CALL SCQBUILD
        JP C,SCNFAIL
        CALL SCQSTOR
        JP C,SCNFAIL
        LD HL,(SCPC)
        CALL SCBRPAT
        JP C,SCNFAIL
        POP AF                     ; Restore the enclosing cache index.
        LD (SCQFIX),A
        RET

SCNFAIL:
        POP AF                     ; Keep compiler stack balanced on every exit.
        LD (SCQFIX),A
        SCF
        RET

; Dispatch one quoted reader event.
SCQDAT:
        CP 7                       ; Exact integers and booleans are immediate.
        JP Z,SCNUM                 ; Existing scalar emission preserves RTAG.
        CP 87H                     ; Binary16 numeric events retain their marker in replay.
        JP Z,FNUM                  ; Emit the tag-zero payload as a scalar literal.
        CP 5                       ; A symbol is copied as an immutable literal.
        JP Z,SCQSYM
        CP 8                       ; A string is copied with its byte length.
        JP Z,SCQSTR
        CP 1                       ; An opening parenthesis starts a data list.
        JP Z,SCQLIST
        CP 3                       ; Quoted shorthand inside data is a pair.
        JP Z,SCQNEST               ; Construct (quote datum) without collapsing it.
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
        LD A,(SCQFIX)              ; Preserve the enclosing literal's cache index.
        PUSH AF
        LD A,(SCQCOUNT)            ; Preserve a surrounding quoted-list cursor.
        PUSH AF
        LD A,(SCQDOT)              ; Preserve a surrounding dotted-list marker.
        PUSH AF
        CALL SCQCACH                ; Probe the stable cell for this literal.
        JP C,SCQFAIL
        XOR A                      ; The new list starts with no elements.
        LD (SCQCOUNT),A
        LD (SCQDOT),A
SCQLP:
        CALL SCNEXT                ; Read an element, dot or the closing parenthesis.
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
        JP C,SCQFAIL               ; Unwind the enclosing list state.
        LD A,(SCQCOUNT)
        INC A
        LD (SCQCOUNT),A
        CP 64                      ; Keep the generated data stack bounded.
        JP NC,SCQCAPF
        JP SCQLP

SCQDOTF:
        LD A,(SCQDOT)              ; A second dot is malformed.
        OR A
        JP NZ,SCQFAIL
        LD A,(SCQCOUNT)            ; A dotted list needs at least one head.
        OR A
        JP Z,SCQFAIL
        CALL SCNEXT                ; Read exactly one dotted-tail datum.
        JP C,SCQFAIL
        CP 2
        JP Z,SCQFAIL
        CP 4
        JP Z,SCQFAIL
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
        JP C,SCQFAIL               ; Unwind the enclosing list state.
        LD A,(SCQCOUNT)
        INC A
        LD (SCQCOUNT),A
        LD A,1
        LD (SCQDOT),A
        CALL SCNEXT                ; The dotted tail must be followed by close.
        JP C,SCQFAIL
        CP 2
        JP NZ,SCQFAIL

SCQEND:
        LD A,(SCQCOUNT)            ; Runtime receives the number of stack values.
        LD A,(SCQDOT)              ; Read the dotted-list marker through A.
        LD B,A                     ; B distinguishes proper from dotted folding.
        CALL SCQBUILD              ; Return the completed list as A:HL.
        JP C,SCQFAIL
        CALL SCQSTOR               ; Retain the pair graph for later evaluations.
        JP C,SCQFAIL
        LD HL,(SCPC)               ; Cache hits branch to the code after this store.
        CALL SCBRPAT
        JP C,SCQFAIL
        POP AF                     ; Restore the enclosing dotted marker.
        LD (SCQDOT),A
        POP AF                     ; Restore the enclosing element count.
        LD (SCQCOUNT),A
        POP AF                     ; Restore the enclosing literal's cache index.
        LD (SCQFIX),A
        OR A                       ; Return carry clear with the list value live.
        RET

SCQBADN:
        POP AF                     ; Discard the saved dotted marker.
        POP AF                     ; Discard the saved element count.
SCQFAIL:
        POP AF                     ; Restore the enclosing dotted marker.
        LD (SCQDOT),A
        POP AF                     ; Restore the enclosing element count.
        POP AF                     ; Restore the enclosing literal's cache index.
        LD (SCQFIX),A
        SCF
        RET

SCQCAPF:
        CALL SCCAP                 ; Preserve the capacity diagnostic text.
        JP SCQFAIL                 ; Unwind the three saved list-state words.

; Emit the run-time data-stack push used by quoted lists.
SCQPUT:
        LD HL,SRTQPUT
        JP SCCALL

; Emit the run-time list fold.  A is the number of values and B the dot flag.
SCQBUILD:
        LD A,3EH
        CALL SINKBYTE
        RET C
        LD A,(SCQCOUNT)
        CALL SINKBYTE
        RET C
        LD A,6                     ; LD B,n carries the dotted-list marker.
        CALL SINKBYTE
        RET C
        LD A,(SCQDOT)
        CALL SINKBYTE
        RET C
        LD HL,SRTQBLD
        JP SCCALL

; Reserve one static cache cell and emit its hit probe.  A cache hit returns
; directly through the conditional branch; a miss falls through to list code.
SCQCACH:
        LD A,(SCQCNT)
        CP 255                      ; The byte-sized cache index must not wrap.
        JP NC,SCCAP
        LD (SCQFIX),A
        INC A
        LD (SCQCNT),A
        LD A,21H                    ; LD HL,nn receives the cache-cell address.
        CALL SINKBYTE
        RET C
        LD HL,(SCPC)
        LD A,4                       ; Fixup kind four selects quoted cache cells.
        LD (SCFKIND),A
        LD A,(SCQFIX)
        LD (SCFSLOT),A
        CALL SCFIX
        RET C
        XOR A
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        LD HL,SRTQGET
        CALL SCCALL
        RET C
        LD A,0D2H                    ; JP NC skips the builder when the cache hits.
        CALL SINKBYTE
        RET C
        LD HL,(SCPC)
        CALL SCBRPUSH
        RET C
        XOR A
        CALL SINKBYTE
        RET C
        JP SINKBYTE

; Emit the static store that publishes a freshly built quoted pair graph.
SCQSTOR:
        LD A,(SCQFIX)
        LD L,A
        LD A,4                       ; The cache cells use the fourth fixup kind.
        JP SCSTORE
