; Scope compiler quoted forms and list construction.
; Entry points: SCQUOTEF, SCQDAT and SCQLIST.
; Included in compiler order by ../data.asm.

; Quoted data and copied literal support for the compact compiler.
;
; The reader supplies one event at a time.  A quoted list therefore uses the
; generated runtime's four-byte data stack: each element is emitted normally,
; pushed at run time, and folded into pairs when the closing parenthesis arrives.
; Symbols and strings are copied into the output as length-prefixed literals.

QT_LIST  EQU 1                     ; Encoding codes; see src/runtime/quoted.asm.
QT_END   EQU 2
QT_DOT   EQU 3
QT_IMM   EQU 4
QT_BYTE  EQU 5

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

; Quoted lists are compiled as data: CALL QT_BUILD, the cache and end words,
; then an encoding of the whole list that the runtime decodes once (see
; src/runtime/quoted.asm).  SCQENC is set while an encoding is open, so the
; datum compilers below write encoding bytes instead of code.

; Open an encoding: CALL QT_BUILD, the cache word and the end placeholder.
SCQHEAD:
        LD HL,QT_BUILD
        CALL SCCALL
        RET C
        LD A,(SCQCNT)
        CP 255                     ; The byte-sized cache index must not wrap.
        JP NC,SCCAP
        LD (SCQFIX),A
        INC A
        LD (SCQCNT),A
        LD HL,(SCPC)
        LD A,4                     ; Fixup kind four selects quoted cache cells.
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
        LD HL,(SCPC)               ; The end word is patched when the list closes.
        CALL SCBRPUSH
        RET C
        XOR A
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        LD A,1
        LD (SCQENC),A
        RET

; Close the encoding: execution resumes at the current address.
SCQFOOT:
        XOR A
        LD (SCQENC),A
        LD HL,(SCPC)
        CALL SCABS
        JP SCBRPAT

; A nested apostrophe is the two-element list (quote datum).
SCQNEST:
        LD A,(SCQENC)
        OR A
        JR NZ,SCQNESTE
        CALL SCQHEAD
        RET C
        CALL SCQNESTE
        RET C
        JP SCQFOOT
SCQNESTE:
        LD A,QT_LIST
        CALL SINKBYTE
        RET C
        LD HL,SCQUOTE+1            ; Intern the reader's ordinary quote name.
        LD BC,5
        LD IX,SCNCTX
        CALL SYM_ID
        RET C
        LD A,4                     ; The quote operator is a symbol literal.
        CALL SCLITADD
        RET C
        CALL SCNEXT                ; The datum after the nested prefix.
        RET C
        CALL SCQDAT
        RET C
        LD A,QT_END
        JP SINKBYTE

; Dispatch one quoted reader event.
SCQDAT:
        CP 7                       ; Exact integers and booleans are immediate.
        JR Z,SCQDNUM
        CP 87H                     ; Binary16 numeric events retain their marker in replay.
        JR Z,SCQDF16
        CP 5                       ; A symbol is copied as an immutable literal.
        JP Z,SCQSYM
        CP 8                       ; A string is copied with its byte length.
        JP Z,SCQSTR
        CP 1                       ; An opening parenthesis starts a data list.
        JP Z,SCQLIST
        CP 3                       ; Quoted shorthand inside data is a pair.
        JP Z,SCQNEST               ; Construct (quote datum) without collapsing it.
        JP SCSYN                   ; Close, dot and EOF are invalid datum starts.
SCQDNUM:
        LD A,(SCQENC)
        OR A
        JP Z,SCNUM                 ; Outside a list, emit the value as code.
        JR SCQENUM
SCQDF16:
        LD A,(SCQENC)
        OR A
        JP Z,FNUM
        LD (SCVTMP),HL
        LD C,0                     ; Binary16 values use tag zero.
        JR SCQEWID

; Encode a reader scalar: code 5 for a byte-sized exact integer, otherwise
; code 4 with its payload and tag.
SCQENUM:
        LD (SCVTMP),HL
        LD A,(RD_TAG)
        LD C,A
        OR A
        JR NZ,SCQETAG
        LD A,H
        CP 0FFH
        JR Z,SCQEWID               ; A character keeps its FFxx payload.
        LD A,0FEH                  ; A boolean becomes FE00H or FE01H.
        LD (SCVTMP+1),A
        JR SCQEWID
SCQETAG:
        CP 3
        JP NZ,SCUNSUP              ; Other scalar tags are not supported.
        LD A,H
        OR A
        JR NZ,SCQEWID
        LD A,QT_BYTE
        CALL SINKBYTE
        RET C
        LD A,(SCVTMP)
        JP SINKBYTE
SCQEWID:
        LD A,QT_IMM
        CALL SINKBYTE              ; SINKBYTE keeps C, the tag.
        RET C
        LD HL,(SCVTMP)
        CALL SCWORD
        RET C
        LD A,C
        JP SINKBYTE

; Copy a quoted symbol into the output and return a tag-four value.
SCQSYM:
        LD A,4                     ; Runtime tag four identifies a symbol literal.
        JP SCLITADD

; Copy a quoted string into the output and return a tag-five value.
SCQSTR:
        LD A,5                     ; Runtime tag five identifies a string literal.
        JP SCLITADD

; Compile one quoted list.  The outermost list opens the encoding; nested
; lists are encoded within it.  An outermost '() is just the constant.
SCQLIST:
        LD A,(SCQENC)
        OR A
        JR NZ,SCQLBODY
        CALL SCNEXT                ; The first element or the close.
        RET C
        CP 2
        JR NZ,SCQLSOME
        LD HL,0FE02H               ; The empty list.
        JP SCIMM
SCQLSOME:
        PUSH AF                    ; Keep the first event across the header.
        PUSH HL
        LD A,(RD_TAG)
        PUSH AF
        CALL SCQHEAD
        JR C,SCQLHERR
        POP AF
        LD (RD_TAG),A
        POP HL
        POP AF
        CALL SCQLGIVN
        RET C
        JP SCQFOOT
SCQLHERR:
        POP AF
        POP HL
        POP AF
        SCF
        RET

; Encode one list: code 1, its elements, then code 2, or code 3 after a
; dotted tail.  SCQLGIVN starts with the first event already read.
SCQLBODY:
        CALL SCNEXT
        RET C
SCQLGIVN:
        PUSH AF                    ; Keep the first event across code 1.
        PUSH HL
        LD A,(RD_TAG)
        PUSH AF
        LD A,QT_LIST
        CALL SINKBYTE
        JR C,SCQLGERR
        POP AF
        LD (RD_TAG),A
        POP HL
        LD A,(SCQCOUNT)            ; Keep the enclosing list's element count
        EX (SP),HL                 ; below the first event.
        LD B,H                     ; B is the event kind from the saved AF.
        LD H,A
        EX (SP),HL                 ; The stack word is now the count, HL the payload.
        XOR A
        LD (SCQCOUNT),A
        LD A,B
        JR SCQLGOT
SCQLGERR:
        POP AF
        POP HL
        POP AF
        SCF
        RET
SCQLP:
        CALL SCNEXT                ; An element, a dot or the close.
        JR C,SCQFAIL
SCQLGOT:
        CP 2
        JR Z,SCQPROP
        CP 4
        JR Z,SCQDOTF
        OR A                       ; EOF cannot close an open quoted list.
        JR Z,SCQFAIL
        CALL SCQELEM
        JR C,SCQFAIL
        JR SCQLP
SCQDOTF:
        LD A,(SCQCOUNT)            ; A dotted list needs at least one head.
        OR A
        JR Z,SCQFAIL
        CALL SCNEXT                ; Exactly one tail datum.
        JR C,SCQFAIL
        CP 2
        JR Z,SCQFAIL
        CP 4
        JR Z,SCQFAIL
        OR A
        JR Z,SCQFAIL
        CALL SCQELEM
        JR C,SCQFAIL
        CALL SCNEXT                ; The tail must be followed by the close.
        JR C,SCQFAIL
        CP 2
        JR NZ,SCQFAIL
        LD A,QT_DOT
        JR SCQCLOSE
SCQPROP:
        LD A,QT_END
SCQCLOSE:
        CALL SINKBYTE
        JR C,SCQFAIL
        POP AF
        LD (SCQCOUNT),A
        OR A                       ; POP AF restored stale flags.
        RET
SCQFAIL:
        POP AF
        LD (SCQCOUNT),A
        SCF
        RET

; Encode one element, counting it against the quoted-data stack bound.
SCQELEM:
        CALL SCQDAT
        RET C
        LD A,(SCQCOUNT)
        INC A
        LD (SCQCOUNT),A
        CP 64                      ; The decoder's stack is bounded too.
        JP NC,SCCAP
        OR A
        RET

