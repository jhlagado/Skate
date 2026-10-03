; Scope compiler conditionals and short-circuit forms.
;
; Branch patch records are kept in the compiler tables declared by the
; driver module and are resolved before each form returns.

; Compile if, placing a false-arm branch before the consequent and a jump over
; the alternative after it.  Nested forms use the separate IF patch stacks.
; The enclosing tail context stays on the stack for the whole form, because a
; nested if in the test, an arm or an argument reuses SCTCTX.
SCIFORM:
        LD A,(SCTCTX)              ; Save the surrounding tail position for both arms.
        PUSH AF                    ; Nested forms cannot overwrite a stacked copy.
        XOR A
        LD (SCTCTX),A              ; Test evaluation returns to the branch skeleton.
        CALL SCEXPR                ; Compile the test value.
        JR C,SCIFERR               ; Preserve a test-expression diagnostic.
        LD HL,SRTFAL               ; Runtime helper returns Z only for #f.
        CALL SCCALL                ; Check the test without changing its value.
        JR C,SCIFERR               ; Staged output is exhausted.
        CALL SCJZ                  ; Emit JP Z,zero and return its patch address.
        JR C,SCIFERR
        CALL SCIFPUSH              ; Save the false-arm patch for this depth.
        JR C,SCIFERR               ; More than 32 nested ifs is a capacity error.
        CALL SCCNCTX               ; The consequent inherits the enclosing position.
        CALL SCEXPR                ; Compile the consequent expression.
        JR C,SCIFERR              ; A broken consequent aborts the whole form.
        CALL SCJP                  ; Skip the alternative after a true arm.
        JR C,SCIFERR
        CALL SCIFENDP              ; Save the end-jump patch for this depth.
        LD HL,(SCPC)               ; The alternative starts at this code address.
        CALL SCIFPATF              ; Patch the false branch before reading the arm.
        JR C,SCIFERR
        CALL SCCNCTX               ; The alternative inherits the enclosing position.
        CALL SCNEXT                ; A close means the optional alternative is absent.
        JR C,SCIFERR              ; Preserve a reader error after the consequent.
        CP 2                       ; Closing now selects the unspecified value.
        JR Z,SCIFNONE              ; Emit it and finish the branch skeleton.
        CALL SCEXPE                ; The already-read event is the alternative.
        JR C,SCIFERR              ; Propagate an alternative expression failure.
        CALL SCEXPECT              ; The alternative must close the original list.
        JR SCIFDONE                ; Patch the end jump after its last byte.
SCIFNONE:
        CALL SCUNS                 ; An omitted alternative returns UNSPECIFIED.
SCIFDONE:
        JR C,SCIFERR
        LD HL,(SCPC)               ; Both arms now end at this generated address.
        CALL SCIFPATE              ; Patch the unconditional end jump.
        JR C,SCIFERR
        POP AF                     ; Restore the enclosing tail context.
        LD (SCTCTX),A
        JP SCIFPOP                 ; Release this nested if patch record.
SCIFERR:
        POP AF                     ; Restore the enclosing tail context.
        LD (SCTCTX),A
        SCF                        ; Preserve the nested diagnostic.
        RET

; Compile a begin body, preserving the value produced by its final expression.
SCBEGINF:
        JP SCBODY                  ; SCBODY consumes the matching close.

; Compile and or or with any number of operands.  (and) is #t and (or) is #f.
; Each operand but the last is tested and branches to the end with its value
; when it decides the result: #f for and, any true value for or.  The final
; operand keeps the enclosing tail position.  Whether an operand is final is
; known only after it is compiled, so each one is compiled as a tail candidate
; and SCTFIX rewrites its calls when another operand follows, as SCBODY does.
;
; Native stack frame, top first: branch-stack top on entry, enclosing tail
; context, enclosing expression mark, mode (0 for and, 1 for or).
SCANDF:
        XOR A
        JR SCLOGF
SCORF:
        LD A,1
SCLOGF:
        PUSH AF                    ; Mode.
        LD A,(SCTMARK)
        PUSH AF                    ; The enclosing body's expression mark.
        LD A,(SCTCTX)
        PUSH AF                    ; The enclosing tail context.
        LD A,(SCBRTOP)
        PUSH AF                    ; Branches above this mark belong to this form.
        CALL SCNEXT                ; The first operand, or the close.
        JP C,SCLOGER
        CP 2
        JP Z,SCLOGEM
SCLOGOP:
        PUSH AF                    ; Keep the operand's first event.
        PUSH HL
        LD A,(SCTTOP)              ; Its tail records start here.
        LD (SCTMARK),A
        LD HL,7                    ; The enclosing tail context is 7 bytes up.
        ADD HL,SP
        LD A,(HL)
        LD (SCTCTX),A
        POP HL
        POP AF
        CALL SCEXPE                ; Compile the operand.
        JP C,SCLOGER
        CALL SCNEXT                ; A close makes it the final operand.
        JP C,SCLOGER
        CP 2
        JP Z,SCLOGDN
        PUSH AF                    ; Keep the next operand's first event.
        PUSH HL
        LD A,(RTAG)
        PUSH AF
        CALL SCTFIX                ; Not final: its tail calls must return.
        JP C,SCLOGE3
        LD HL,SRTFAL               ; Z means the value is #f; A:HL is kept.
        CALL SCCALL
        JP C,SCLOGE3
        LD HL,13                   ; The mode is 13 bytes up.
        ADD HL,SP
        LD A,(HL)
        OR A
        JR NZ,SCLOGOR
        CALL SCJZ                  ; and stops at the first #f.
        JR SCLOGBR
SCLOGOR:
        CALL SCJNZ                 ; or stops at the first true value.
SCLOGBR:
        JP C,SCLOGE3
        CALL SCBRPUSH
        JP C,SCLOGE3
        POP AF
        LD (RTAG),A
        POP HL
        POP AF
        JP SCLOGOP
SCLOGEM:
        LD HL,7                    ; (and) is #t and (or) is #f.
        ADD HL,SP
        LD A,(HL)
        XOR 1
        LD L,A
        LD H,0FEH
        CALL SCIMM
        JP C,SCLOGER
SCLOGDN:
        LD HL,(SCPC)               ; Every decisive operand lands here.
        CALL SCABS
        LD (SCLGEND),HL
        POP AF                     ; The branch-stack top on entry.
        LD B,A
SCLOGPT:
        LD A,(SCBRTOP)
        CP B
        JR Z,SCLOGRS
        PUSH BC
        LD HL,(SCLGEND)
        CALL SCBRPAT
        POP BC
        JP C,SCLOGR3
        JR SCLOGPT
SCLOGRS:
        POP AF
        LD (SCTCTX),A
        POP AF
        LD (SCTMARK),A
        POP AF
        OR A                       ; Carry clear: the form is complete.
        RET
SCLOGE3:
        POP AF                     ; Discard the saved next event.
        POP HL
        POP AF
SCLOGER:
        POP AF                     ; Discard the branch-stack mark.
SCLOGR3:
        POP AF
        LD (SCTCTX),A
        POP AF
        LD (SCTMARK),A
        POP AF
        SCF
        RET

SCLGEND: DW 0                      ; Common end address of an and or or form.

; Compile (when test body...) and (unless test body...).  The body runs when
; the test is true (when) or false (unless); otherwise the value is
; unspecified.  The body inherits the enclosing tail position.
SCWHENF:
        XOR A
        JR SCWHU
SCUNLSF:
        LD A,1
SCWHU:
        PUSH AF                    ; Mode: 0 for when, 1 for unless.
        LD A,(SCTCTX)
        PUSH AF                    ; SCCNCTX reads the tail context from here.
        XOR A
        LD (SCTCTX),A              ; The test is never in tail position.
        CALL SCEXPR
        JR C,.ERR
        LD HL,SRTFAL               ; Z means the test value is #f.
        CALL SCCALL
        JR C,.ERR
        LD HL,3                    ; The mode is 3 bytes up.
        ADD HL,SP
        LD A,(HL)
        OR A
        JR NZ,.UNLESS
        CALL SCJZ                  ; when skips the body on #f.
        JR .BRANCH
.UNLESS:
        CALL SCJNZ                 ; unless skips it on any true value.
.BRANCH:
        JR C,.ERR
        CALL SCIFPUSH
        JR C,.ERR
        CALL SCCNCTX
        CALL SCBODY                ; The body runs to the form's close.
        JR C,.ERR
        CALL SCJP
        JR C,.ERR
        CALL SCIFENDP
        LD HL,(SCPC)               ; The skipped path yields unspecified.
        CALL SCIFPATF
        JR C,.ERR
        CALL SCUNS
        JR C,.ERR
        LD HL,(SCPC)
        CALL SCIFPATE
        JR C,.ERR
        POP AF
        LD (SCTCTX),A
        POP AF
        JP SCIFPOP
.ERR:
        POP AF
        LD (SCTCTX),A
        POP AF
        SCF
        RET

; Compile (case key ((datum...) body...) ... (else body...)).  The key is
; evaluated once and held on the operator side stack; each datum is loaded and
; compared by CASE_EQ, and every match in a clause branches to its body.  The
; key is popped before any body runs, so the stack is balanced for tail calls.
SCCASEF:
        LD A,(SCTCTX)
        PUSH AF                    ; The cond helpers keep the tail context here.
        CALL SCCNOPEN              ; End jumps use a private cond patch frame.
        JP C,SCNOPEN
        XOR A
        LD (SCTCTX),A
        CALL SCEXPR                ; The key.
        JP C,SCCNERR
        LD HL,SRTOPUSH
        CALL SCCALL
        JP C,SCCNERR
SCCSCLA:
        CALL SCNEXT                ; A clause or the form's close.
        JP C,SCCNERR
        CP 2
        JP Z,SCCSEMP
        CP 1
        JP NZ,SCCNERR
        CALL SCNEXT                ; A datum list or else.
        JP C,SCCNERR
        CP 1
        JR Z,.DATA
        CP 5
        JP NZ,SCCNERR
        LD DE,SCELSE
        CALL SCMATCH
        JP NZ,SCCNERR
        LD HL,SRTOPPOP             ; Drop the key before the else body.
        CALL SCCALL
        JP C,SCCNERR
        JP SCCNELSE
.DATA:
        LD A,(SCBRTOP)             ; Datum branches above this mark belong to
        LD (SCCSMRK),A             ; this clause; no form nests among datums.
.DATUM:
        CALL SCNEXT
        JP C,SCCNERR
        CP 2
        JR Z,.BODY
        CALL SCQDAT                ; Load the datum into A:HL.
        JP C,SCCNERR
        LD HL,CASE_EQ
        CALL SCCALL
        JP C,SCCNERR
        CALL SCJZ                  ; A match enters this clause's body.
        JP C,SCCNERR
        CALL SCBRPUSH
        JP C,SCCNERR
        JR .DATUM
.BODY:
        CALL SCJP                  ; No datum matched: skip the body.
        JP C,SCCNERR
        CALL SCIFPUSH
        JP C,SCCNERR
        LD HL,(SCPC)               ; Every match lands here.
        CALL SCABS
        LD (SCLGEND),HL
.MATCH:
        LD A,(SCCSMRK)
        LD B,A
        LD A,(SCBRTOP)
        CP B
        JR Z,.ENTER
        LD HL,(SCLGEND)
        CALL SCBRPAT
        JP C,SCCNERR
        JR .MATCH
.ENTER:
        LD HL,SRTOPPOP             ; Drop the key before the body.
        CALL SCCALL
        JP C,SCCNERR
        CALL SCCNCTX
        CALL SCBODY
        JP C,SCCNERR
        CALL SCJP                  ; The body's value is the form's value.
        JP C,SCCNERR
        CALL SCCNADD
        JP C,SCCNERR
        LD HL,(SCPC)               ; The next clause starts here.
        CALL SCIFPATF
        JP C,SCCNERR
        CALL SCIFPOP
        JP SCCSCLA
SCCSEMP:
        LD HL,SRTOPPOP             ; No clause matched and there is no else.
        CALL SCCALL
        JP C,SCCNERR
        JP SCCNEMP

SCCSMRK: DB 0                      ; Branch-stack mark for one case clause.

; Compile a sequence of cond clauses.  Each ordinary clause branches to the
; next test when false and records one end jump for the common result address.
SCCONDF:
        LD A,(SCTCTX)              ; Clauses inherit the surrounding tail state.
        PUSH AF                    ; Keep it below all nested expression frames.
        CALL SCCNOPEN              ; Give this cond a private patch-table frame.
        JP C,SCNOPEN                ; Reject a nesting depth beyond the patch bound.
SCCNCLA:
        CALL SCNEXT                ; Read a clause or the outer closing parenthesis.
        JP C,SCCNERR
        CP 2
        JP Z,SCCNEMP               ; No matching clause yields unspecified.
        CP 1
        JP NZ,SCCNERR              ; Every clause is a parenthesised list.
        CALL SCNEXT                ; The first item is either a test or else.
        JP C,SCCNERR
        LD (SCBEV),A               ; Save the event while checking the else spelling.
        LD (SCBVAL),HL
        LD A,(RTAG)
        LD (SCBTAG),A
        LD A,(SCBEV)
        CP 5
        JP NZ,SCCNTEST             ; Non-symbol events are ordinary test expressions.
        LD DE,SCELSE
        CALL SCMATCH
        JP Z,SCCNELSE              ; Else is accepted only as the final clause.
SCCNTEST:
        CALL SCCNCTX               ; Restore the enclosing tail state for this clause.
        XOR A                      ; The test itself is never in tail position.
        LD (SCTCTX),A
        LD A,(SCBTAG)
        LD (RTAG),A
        LD A,(SCBEV)
        LD HL,(SCBVAL)
        CALL SCEXPE                ; Compile the test expression already read.
        JP C,SCCNERR
        LD HL,SRTFAL
        CALL SCCALL                ; Z means that the test value is #f.
        JP C,SCCNERR
        CALL SCJZ                  ; Save the false path until this clause closes.
        JP C,SCCNERR
        CALL SCBRPUSH
        JP C,SCCNERR
        CALL SCCNCTX               ; Clause results inherit the cond tail state.
        CALL SCBODY                ; Read result expressions through the clause close.
        JP C,SCCNERR
        CALL SCJP                  ; A selected clause skips the remaining tests.
        JP C,SCCNERR
        CALL SCCNADD               ; Save the common-end patch address.
        JP C,SCCNERR
        LD HL,(SCPC)               ; The next clause begins at this output address.
        CALL SCABS
        CALL SCBRPAT               ; Resolve the false path to the next test.
        JP C,SCCNERR
        JP SCCNCLA

; Compile the final else clause and require the outer cond close immediately.
SCCNELSE:
        CALL SCCNCTX               ; Else result expressions inherit tail state.
        CALL SCBODY
        JP C,SCCNERR
        CALL SCNEXT
        JP C,SCCNERR
        CP 2
        JP NZ,SCCNERR              ; Else must be the final clause.
        JP SCCNDONE

SCCNEMP:
        CALL SCUNS                  ; No clause matched, including an empty cond.
SCCNDONE:
        LD HL,(SCPC)
        CALL SCABS
        CALL SCCNPTCH              ; Point every selected clause at the result.
        POP AF                     ; Restore the surrounding tail context.
        LD (SCTCTX),A
        XOR A
        RET

; Restore the saved cond tail context without consuming its stack word.
SCCNCTX:
        POP DE                    ; Move the helper return below the saved context.
        POP AF                    ; Read the enclosing cond tail context.
        LD (SCTCTX),A
        PUSH AF                   ; Leave the saved context for the cond's final restore.
        PUSH DE                   ; Restore the helper continuation above it.
        RET

; Open a nested cond patch frame while retaining every outer frame's records.
SCCNOPEN:
        LD A,(SCCNDEP)
        CP 32
        JP NC,SCCAP
        LD L,A
        LD H,0
        LD DE,SCNBASE
        ADD HL,DE
        LD A,(SCCNBASE)
        LD (HL),A
        LD A,(SCCNDEP)
        LD L,A
        LD H,0
        LD DE,SCNTOPS
        ADD HL,DE
        LD A,(SCCDTOP)
        LD (HL),A
        LD A,(SCCNBASE)
        LD B,A
        LD A,(SCCDTOP)
        ADD A,B
        CP 64
        JP NC,SCCAP
        LD (SCCNBASE),A
        XOR A
        LD (SCCDTOP),A
        LD A,(SCCNDEP)
        INC A
        LD (SCCNDEP),A
        RET

; Restore the enclosing cond frame after a syntax or capacity failure.
SCNABORT:
        LD A,(SCCNDEP)
        DEC A
        LD (SCCNDEP),A
        LD L,A
        LD H,0
        LD DE,SCNBASE
        ADD HL,DE
        LD A,(HL)
        LD (SCCNBASE),A
        LD A,(SCCNDEP)
        LD L,A
        LD H,0
        LD DE,SCNTOPS
        ADD HL,DE
        LD A,(HL)
        LD (SCCDTOP),A
        RET

; Save one unconditional end-jump patch in the bounded cond table.
SCCNADD:
        LD (SCBPTMP),HL
        LD A,(SCCDTOP)
        CP 64
        JP NC,SCCAP
        LD C,A
        LD A,(SCCNBASE)
        ADD A,C
        CP 64
        JP NC,SCCAP
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCCNPT
        ADD HL,DE
        LD DE,(SCBPTMP)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(SCCDTOP)
        INC A
        LD (SCCDTOP),A
        OR A
        RET

; Patch all recorded cond end jumps to the absolute address in HL.
SCCNPTCH:
        LD (SCBTARG),HL
        LD A,(SCCDTOP)
        LD B,A
SCCNPLP:
        LD A,B
        OR A
        JP Z,SCCNPDN
        DEC B
        LD A,B
        LD C,A
        LD A,(SCCNBASE)
        ADD A,C
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCCNPT
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD DE,(SCBTARG)
        CALL SINKPTCH
        JP SCCNPLP
SCCNPDN:
        CALL SCNABORT              ; Release this cond's patch frame.
        XOR A                      ; Return carry clear after a complete cond.
        RET

SCCNERR:
        CALL SCNABORT
        POP AF                     ; Restore the caller's tail context on failure.
        LD (SCTCTX),A
        SCF
        RET

SCNOPEN:
        POP AF                     ; Restore the caller's tail context.
        LD (SCTCTX),A
        SCF
        RET
