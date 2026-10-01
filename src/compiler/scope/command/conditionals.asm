; Scope compiler conditionals and short-circuit forms.
;
; Branch patch records are kept in the compiler tables declared by the
; driver module and are resolved before each form returns.

; Compile if, placing a false-arm branch before the consequent and a jump over
; the alternative after it.  Nested forms use the separate IF patch stacks.
SCIFORM:
        LD A,(SCTCTX)              ; Save the surrounding tail position for both arms.
        LD (SCIFTAIL),A            ; The predicate itself is never a tail call.
        XOR A
        LD (SCTCTX),A              ; Test evaluation returns to the branch skeleton.
        CALL SCEXPR                ; Compile the test value.
        RET C                      ; Preserve a test-expression diagnostic.
        LD HL,SRTFAL               ; Runtime helper returns Z only for #f.
        CALL SCCALL                ; Check the test without changing its value.
        CALL SCJZ                  ; Emit JP Z,zero and return its patch address.
        CALL SCIFPUSH              ; Save the false-arm patch for this depth.
        LD A,(SCIFTAIL)            ; The consequent inherits the enclosing position.
        LD (SCTCTX),A
        CALL SCEXPR                ; Compile the consequent expression.
        RET C                      ; A broken consequent aborts the whole form.
        CALL SCJP                  ; Skip the alternative after a true arm.
        CALL SCIFENDP              ; Save the end-jump patch for this depth.
        LD HL,(SCPC)               ; The alternative starts at this code address.
        CALL SCABS                 ; Convert its staged address to output address.
        CALL SCIFPATF            ; Patch the false branch before reading the arm.
        LD A,(SCIFTAIL)            ; The alternative inherits the enclosing position.
        LD (SCTCTX),A
        CALL SCNEXT                ; A close means the optional alternative is absent.
        RET C                      ; Preserve a reader error after the consequent.
        CP 2                       ; Closing now selects the unspecified value.
        JR Z,SCIFNONE              ; Emit it and finish the branch skeleton.
        CALL SCEXPE                ; The already-read event is the alternative.
        RET C                      ; Propagate an alternative expression failure.
        CALL SCEXPECT              ; The alternative must close the original list.
        JR SCIFDONE                ; Patch the end jump after its last byte.
SCIFNONE:
        CALL SCUNS                 ; An omitted alternative returns UNSPECIFIED.
SCIFDONE:
        LD HL,(SCPC)               ; Both arms now end at this generated address.
        CALL SCABS                 ; Convert it to the output's absolute address.
        CALL SCIFPATE            ; Patch the unconditional end jump.
        JP SCIFPOP                 ; Release this nested if patch record.

; Compile a begin body, preserving the value produced by its final expression.
SCBEGINF:
        CALL SCBODY                ; SCBODY consumes the matching close.
        RET                        ; The last emitted value remains in registers.

; Compile the two short-circuit operands of and.
SCANDF:
        LD A,(SCTCTX)              ; Save the surrounding tail position.
        PUSH AF                    ; The first operand itself is never tail code.
        XOR A
        LD (SCTCTX),A
        CALL SCEXPR                ; Compile the first operand.
        JR C,SCANDERR              ; Balance the saved context on failure.
        POP AF                     ; Recover the enclosing tail position.
        LD (SCTCTX),A              ; Only the second operand can inherit it.
        LD HL,SRTFAL               ; Test the value while retaining its registers.
        CALL SCCALL                ; Z means the first operand is #f.
        CALL SCJZ                  ; Branch to the first operand's final-value path.
        CALL SCBRPUSH              ; Save the patch in the nested branch stack.
        CALL SCEXPR                ; Compile the second operand only when needed.
        RET C                      ; Preserve a nested syntax or capacity error.
        CALL SCEXPECT              ; And is exactly two operands in this increment.
        RET C                      ; A missing or extra operand is syntax.
        LD HL,(SCPC)               ; The second operand is the true path's result.
        CALL SCABS                 ; Convert its end address for the branch target.
        JP SCBRPAT                 ; Patch the pending branch to this target.
SCANDERR:
        POP AF                     ; Remove the saved tail position after failure.
        SCF
        RET

; Compile the two short-circuit operands of or.
SCORF:
        LD A,(SCTCTX)              ; Save the surrounding tail position.
        PUSH AF                    ; The first operand itself is never tail code.
        XOR A
        LD (SCTCTX),A
        CALL SCEXPR                ; Compile the first operand.
        JR C,SCORERR               ; Balance the saved context on failure.
        POP AF                     ; Recover the enclosing tail position.
        LD (SCTCTX),A              ; Only the second operand can inherit it.
        LD HL,SRTFAL               ; Test the value while retaining its registers.
        CALL SCCALL                ; Z means the first operand is false.
        CALL SCJNZ                 ; A true first operand skips the second.
        CALL SCBRPUSH              ; Save the patch in the nested branch stack.
        CALL SCEXPR                ; Compile the second operand only when needed.
        RET C                      ; Preserve a nested syntax or capacity error.
        CALL SCEXPECT              ; Or is exactly two operands in this increment.
        RET C                      ; A missing or extra operand is syntax.
        LD HL,(SCPC)               ; The second operand is the false path's result.
        CALL SCABS                 ; Convert its end address for the branch target.
        JP SCBRPAT                 ; Patch the pending branch to this target.
SCORERR:
        POP AF                     ; Remove the saved tail position after failure.
        SCF
        RET

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
        XOR A
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
