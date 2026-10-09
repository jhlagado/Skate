; Scope compiler conditionals and short-circuit forms.
;
; Branch patch records are kept in the compiler tables declared by the
; driver module and are resolved before each form returns.

; Compile if, placing a false-arm branch before the consequent and a jump over
; the alternative after it.  Nested forms use the separate IF patch stacks.
; The enclosing tail context stays on the stack for the whole form, because a
; nested if in the test, an arm or an argument reuses ST_TAIL.
IF_FORM:
        LD A,(ST_TAIL)             ; Save the surrounding tail position for both arms.
        PUSH AF                    ; Nested forms cannot overwrite a stacked copy.
        XOR A
        LD (ST_TAIL),A             ; Test evaluation returns to the branch skeleton.
        CALL CMD_NEXT              ; Compile the test value.
        JR C,.FAIL                 ; Preserve a test-expression diagnostic.
        LD HL,RT_TEST              ; Runtime helper returns Z only for #f.
        CALL EM_CALL               ; Check the test without changing its value.
        JR C,.FAIL                 ; Staged output is exhausted.
        CALL EM_JZ                 ; Emit JP Z,zero and return its patch address.
        JR C,.FAIL
        CALL BR_IFNEW              ; Save the false-arm patch for this depth.
        JR C,.FAIL                 ; More than 32 nested ifs is a capacity error.
        CALL IF_TAIL               ; The consequent inherits the enclosing position.
        CALL CMD_NEXT              ; Compile the consequent expression.
        JR C,.FAIL                ; A broken consequent aborts the whole form.
        CALL EM_JP                 ; Skip the alternative after a true arm.
        JR C,.FAIL
        CALL BR_IFEND              ; Save the end-jump patch for this depth.
        LD HL,(ST_PC)              ; The alternative starts at this code address.
        CALL BR_ELSE               ; Patch the false branch before reading the arm.
        JR C,.FAIL
        CALL IF_TAIL               ; The alternative inherits the enclosing position.
        CALL REC_NEXT              ; A close means the optional alternative is absent.
        JR C,.FAIL                ; Preserve a reader error after the consequent.
        CP 2                       ; Closing now selects the unspecified value.
        JR Z,.NO_ELSE              ; Emit it and finish the branch skeleton.
        CALL CMD_EXPR              ; The already-read event is the alternative.
        JR C,.FAIL                ; Propagate an alternative expression failure.
        CALL CMD_END               ; The alternative must close the original list.
        JR .DONE                   ; Patch the end jump after its last byte.
.NO_ELSE:
        CALL EM_VOID               ; An omitted alternative returns UNSPECIFIED.
.DONE:
        JR C,.FAIL
        LD HL,(ST_PC)              ; Both arms now end at this generated address.
        CALL BR_JOIN               ; Patch the unconditional end jump.
        JR C,.FAIL
        POP AF                     ; Restore the enclosing tail context.
        LD (ST_TAIL),A
        JP BR_IFPOP                ; Release this nested if patch record.
.FAIL:
        POP AF                     ; Restore the enclosing tail context.
        LD (ST_TAIL),A
        SCF                        ; Preserve the nested diagnostic.
        RET

; Compile a begin body, preserving the value produced by its final expression.
CMD_SEQ:
        JP CMD_BODY                ; CMD_BODY consumes the matching close.

; Compile and or or with any number of operands.  (and) is #t and (or) is #f.
; Each operand but the last is tested and branches to the end with its value
; when it decides the result: #f for and, any true value for or.  The final
; operand keeps the enclosing tail position.  Whether an operand is final is
; known only after it is compiled, so each one is compiled as a tail candidate
; and EM_PLAIN rewrites its calls when another operand follows, as CMD_BODY does.
;
; Native stack frame, top first: branch-stack top on entry, enclosing tail
; context, enclosing expression mark, mode (0 for and, 1 for or).
IF_AND:
        XOR A
        JR IF_LOGIC
IF_OR:
        LD A,1
IF_LOGIC:
        PUSH AF                    ; Mode.
        LD A,(ST_MARK)
        PUSH AF                    ; The enclosing body's expression mark.
        LD A,(ST_TAIL)
        PUSH AF                    ; The enclosing tail context.
        LD A,(ST_BRTOP)
        PUSH AF                    ; Branches above this mark belong to this form.
        CALL REC_NEXT              ; The first operand, or the close.
        JP C,.FAIL
        CP 2
        JR Z,.EMPTY
.OPERAND:
        PUSH AF                    ; Keep the operand's first event.
        PUSH HL
        LD A,(ST_TAILS)            ; Its tail records start here.
        LD (ST_MARK),A
        LD HL,7                    ; The enclosing tail context is 7 bytes up.
        ADD HL,SP
        LD A,(HL)
        LD (ST_TAIL),A
        POP HL
        POP AF
        CALL CMD_EXPR              ; Compile the operand.
        JR C,.FAIL
        CALL REC_NEXT              ; A close makes it the final operand.
        JR C,.FAIL
        CP 2
        JR Z,.DONE
        PUSH AF                    ; Keep the next operand's first event.
        PUSH HL
        LD A,(RD_TAG)
        PUSH AF
        PUSH BC                    ; C is the operand's byte 2.
        CALL EM_PLAIN              ; Not final: its tail calls must return.
        JR C,.NEXTFAIL
        LD HL,RT_TEST              ; Z means the value is #f; A:HL is kept.
        CALL EM_CALL
        JR C,.NEXTFAIL
        LD HL,15                   ; The mode is 15 bytes up.
        ADD HL,SP
        LD A,(HL)
        OR A
        JR NZ,.OR_TEST
        CALL EM_JZ                 ; and stops at the first #f.
        JR .BRANCH
.OR_TEST:
        CALL EM_JNZ                ; or stops at the first true value.
.BRANCH:
        JR C,.NEXTFAIL
        CALL BR_PUSH
        JR C,.NEXTFAIL
        POP BC
        POP AF
        LD (RD_TAG),A
        POP HL
        POP AF
        JR .OPERAND
.EMPTY:
        LD HL,7                    ; (and) is #t and (or) is #f.
        ADD HL,SP
        LD A,(HL)
        XOR 1
        LD L,A
        LD H,0FEH
        CALL EM_IMM
        JR C,.FAIL
.DONE:
        LD HL,(ST_PC)              ; Every decisive operand lands here.
        CALL BR_ABS
        LD (IF_JOIN),HL
        POP AF                     ; The branch-stack top on entry.
        LD B,A
.PATCH:
        LD A,(ST_BRTOP)
        CP B
        JR Z,.RESTORE
        PUSH BC
        LD HL,(IF_JOIN)
        CALL BR_PATCH
        POP BC
        JR C,.UNWIND
        JR .PATCH
.RESTORE:
        POP AF
        LD (ST_TAIL),A
        POP AF
        LD (ST_MARK),A
        POP AF
        OR A                       ; Carry clear: the form is complete.
        RET
.NEXTFAIL:
        POP BC                     ; Discard the saved next event.
        POP AF
        POP HL
        POP AF
.FAIL:
        POP AF                     ; Discard the branch-stack mark.
.UNWIND:
        POP AF
        LD (ST_TAIL),A
        POP AF
        LD (ST_MARK),A
        POP AF
        SCF
        RET

IF_JOIN: DW 0                      ; Common end address of an and or or form.

; Compile (when test body...) and (unless test body...).  The body runs when
; the test is true (when) or false (unless); otherwise the value is
; unspecified.  The body inherits the enclosing tail position.
IF_WHEN:
        XOR A
        JR IF_GUARD
IF_NOT:
        LD A,1
IF_GUARD:
        PUSH AF                    ; Mode: 0 for when, 1 for unless.
        LD A,(ST_TAIL)
        PUSH AF                    ; IF_TAIL reads the tail context from here.
        XOR A
        LD (ST_TAIL),A             ; The test is never in tail position.
        CALL CMD_NEXT
        JR C,.FAIL
        LD HL,RT_TEST              ; Z means the test value is #f.
        CALL EM_CALL
        JR C,.FAIL
        LD HL,3                    ; The mode is 3 bytes up.
        ADD HL,SP
        LD A,(HL)
        OR A
        JR NZ,.UNLESS
        CALL EM_JZ                 ; when skips the body on #f.
        JR .BRANCH
.UNLESS:
        CALL EM_JNZ                ; unless skips it on any true value.
.BRANCH:
        JR C,.FAIL
        CALL BR_IFNEW
        JR C,.FAIL
        CALL IF_TAIL
        CALL CMD_BODY              ; The body runs to the form's close.
        JR C,.FAIL
        CALL EM_JP
        JR C,.FAIL
        CALL BR_IFEND
        LD HL,(ST_PC)              ; The skipped path yields unspecified.
        CALL BR_ELSE
        JR C,.FAIL
        CALL EM_VOID
        JR C,.FAIL
        LD HL,(ST_PC)
        CALL BR_JOIN
        JR C,.FAIL
        POP AF
        LD (ST_TAIL),A
        POP AF
        JP BR_IFPOP
.FAIL:
        POP AF
        LD (ST_TAIL),A
        POP AF
        SCF
        RET

; Compile (case key ((datum...) body...) ... (else body...)).  The key is
; evaluated once and held on the operator side stack; each datum is loaded and
; compared by STD_CASE, and every match in a clause branches to its body.  The
; key is popped before any body runs, so the stack is balanced for tail calls.
IF_CASE:
        LD A,(ST_TAIL)
        PUSH AF                    ; The cond helpers keep the tail context here.
        CALL IF_OPEN               ; End jumps use a private cond patch frame.
        JP C,IF_ABORT
        XOR A
        LD (ST_TAIL),A
        CALL CMD_NEXT              ; The key.
        JP C,IF_FAIL
        LD HL,OPS_PUSH
        CALL EM_CALL
        JP C,IF_FAIL
.CLAUSE:
        CALL REC_NEXT              ; A clause or the form's close.
        JP C,IF_FAIL
        CP 2
        JP Z,.NO_MATCH
        CP 1
        JP NZ,IF_FAIL
        CALL REC_NEXT              ; A datum list or else.
        JP C,IF_FAIL
        CP 1
        JR Z,.DATA
        CP 5
        JP NZ,IF_FAIL
        LD DE,K_ELSE
        CALL CMD_SAME
        JP NZ,IF_FAIL
        LD HL,OPS_POP              ; Drop the key before the else body.
        CALL EM_CALL
        JP C,IF_FAIL
        JP IF_ELSE
.DATA:
        LD A,(ST_BRTOP)            ; Datum branches above this mark belong to
        LD (.MARK),A               ; this clause; no form nests among datums.
.DATUM:
        CALL REC_NEXT
        JP C,IF_FAIL
        CP 2
        JR Z,.BODY
        CALL QUO_DATA              ; Load the datum into A:HL.
        JP C,IF_FAIL
        LD HL,STD_CASE
        CALL EM_CALL
        JP C,IF_FAIL
        CALL EM_JZ                 ; A match enters this clause's body.
        JP C,IF_FAIL
        CALL BR_PUSH
        JP C,IF_FAIL
        JR .DATUM
.BODY:
        CALL EM_JP                 ; No datum matched: skip the body.
        JP C,IF_FAIL
        CALL BR_IFNEW
        JP C,IF_FAIL
        LD HL,(ST_PC)              ; Every match lands here.
        CALL BR_ABS
        LD (IF_JOIN),HL
.MATCH:
        LD A,(.MARK)
        LD B,A
        LD A,(ST_BRTOP)
        CP B
        JR Z,.ENTER
        LD HL,(IF_JOIN)
        CALL BR_PATCH
        JP C,IF_FAIL
        JR .MATCH
.ENTER:
        LD HL,OPS_POP              ; Drop the key before the body.
        CALL EM_CALL
        JP C,IF_FAIL
        CALL IF_TAIL
        CALL CMD_BODY
        JP C,IF_FAIL
        CALL EM_JP                 ; The body's value is the form's value.
        JP C,IF_FAIL
        CALL IF_SAVE
        JP C,IF_FAIL
        LD HL,(ST_PC)              ; The next clause starts here.
        CALL BR_ELSE
        JP C,IF_FAIL
        CALL BR_IFPOP
        JP .CLAUSE
.NO_MATCH:
        LD HL,OPS_POP              ; No clause matched and there is no else.
        CALL EM_CALL
        JP C,IF_FAIL
        JP IF_NONE

.MARK: DB 0                        ; Branch-stack mark for one case clause.

; Compile a sequence of cond clauses.  Each ordinary clause branches to the
; next test when false and records one end jump for the common result address.
IF_COND:
        LD A,(ST_TAIL)             ; Clauses inherit the surrounding tail state.
        PUSH AF                    ; Keep it below all nested expression frames.
        CALL IF_OPEN               ; Give this cond a private patch-table frame.
        JP C,IF_ABORT               ; Reject a nesting depth beyond the patch bound.
.CLAUSE:
        CALL REC_NEXT              ; Read a clause or the outer closing parenthesis.
        JP C,IF_FAIL
        CP 2
        JP Z,IF_NONE               ; No matching clause yields unspecified.
        CP 1
        JP NZ,IF_FAIL              ; Every clause is a parenthesised list.
        CALL REC_NEXT              ; The first item is either a test or else.
        JP C,IF_FAIL
        LD (ST_EVENT),A            ; Save the event while checking the else spelling.
        LD (ST_EVVAL),HL
        LD A,C
        LD (ST_EVEXT),A
        LD A,(RD_TAG)
        LD (ST_EVTAG),A
        LD A,(ST_EVENT)
        CP 5
        JR NZ,.TEST                ; Non-symbol events are ordinary test expressions.
        LD DE,K_ELSE
        CALL CMD_SAME
        JR Z,IF_ELSE               ; Else is accepted only as the final clause.
.TEST:
        CALL IF_TAIL               ; Restore the enclosing tail state for this clause.
        XOR A                      ; The test itself is never in tail position.
        LD (ST_TAIL),A
        LD A,(ST_EVTAG)
        LD (RD_TAG),A
        LD A,(ST_EVEXT)
        LD C,A
        LD A,(ST_EVENT)
        LD HL,(ST_EVVAL)
        CALL CMD_EXPR              ; Compile the test expression already read.
        JP C,IF_FAIL
        LD HL,RT_TEST
        CALL EM_CALL               ; Z means that the test value is #f.
        JP C,IF_FAIL
        CALL EM_JZ                 ; Save the false path until this clause closes.
        JP C,IF_FAIL
        CALL BR_PUSH
        JP C,IF_FAIL
        CALL IF_TAIL               ; Clause results inherit the cond tail state.
        CALL CMD_BODY              ; Read result expressions through the clause close.
        JP C,IF_FAIL
        CALL EM_JP                 ; A selected clause skips the remaining tests.
        JP C,IF_FAIL
        CALL IF_SAVE               ; Save the common-end patch address.
        JP C,IF_FAIL
        LD HL,(ST_PC)              ; The next clause begins at this output address.
        CALL BR_ABS
        CALL BR_PATCH              ; Resolve the false path to the next test.
        JP C,IF_FAIL
        JP .CLAUSE

; Compile the final else clause and require the outer cond close immediately.
IF_ELSE:
        CALL IF_TAIL               ; Else result expressions inherit tail state.
        CALL CMD_BODY
        JP C,IF_FAIL
        CALL REC_NEXT
        JP C,IF_FAIL
        CP 2
        JP NZ,IF_FAIL              ; Else must be the final clause.
        JR IF_CLOSE

IF_NONE:
        CALL EM_VOID                ; No clause matched, including an empty cond.
IF_CLOSE:
        LD HL,(ST_PC)
        CALL BR_ABS
        CALL IF_PATCH              ; Point every selected clause at the result.
        POP AF                     ; Restore the surrounding tail context.
        LD (ST_TAIL),A
        XOR A
        RET

; Restore the saved cond tail context without consuming its stack word.
IF_TAIL:
        POP DE                    ; Move the helper return below the saved context.
        POP AF                    ; Read the enclosing cond tail context.
        LD (ST_TAIL),A
        PUSH AF                   ; Leave the saved context for the cond's final restore.
        PUSH DE                   ; Restore the helper continuation above it.
        RET

; Open a nested cond patch frame while retaining every outer frame's records.
IF_OPEN:
        LD A,(ST_CNEST)
        CP 32
        JP NC,ERR_CAP
        LD L,A
        LD H,0
        LD DE,W_CBASES
        ADD HL,DE
        LD A,(ST_CBASE)
        LD (HL),A
        LD A,(ST_CNEST)
        LD L,A
        LD H,0
        LD DE,W_CTOPS
        ADD HL,DE
        LD A,(ST_CONDS)
        LD (HL),A
        LD A,(ST_CBASE)
        LD B,A
        LD A,(ST_CONDS)
        ADD A,B
        CP 128                     ; W_CONDS holds 128 words.
        JP NC,ERR_CAP
        LD (ST_CBASE),A
        XOR A
        LD (ST_CONDS),A
        LD A,(ST_CNEST)
        INC A
        LD (ST_CNEST),A
        RET

; Restore the enclosing cond frame after a syntax or capacity failure.
IF_POP:
        LD A,(ST_CNEST)
        DEC A
        LD (ST_CNEST),A
        LD L,A
        LD H,0
        LD DE,W_CBASES
        ADD HL,DE
        LD A,(HL)
        LD (ST_CBASE),A
        LD A,(ST_CNEST)
        LD L,A
        LD H,0
        LD DE,W_CTOPS
        ADD HL,DE
        LD A,(HL)
        LD (ST_CONDS),A
        RET

; Save one unconditional end-jump patch in the bounded cond table.
IF_SAVE:
        LD (ST_PATCH),HL
        LD A,(ST_CONDS)
        CP 128                     ; W_CONDS holds 128 words.
        JP NC,ERR_CAP
        LD C,A
        LD A,(ST_CBASE)
        ADD A,C
        CP 128                     ; W_CONDS holds 128 words.
        JP NC,ERR_CAP
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_CONDS
        ADD HL,DE
        LD DE,(ST_PATCH)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(ST_CONDS)
        INC A
        LD (ST_CONDS),A
        OR A
        RET

; Patch all recorded cond end jumps to the absolute address in HL.
IF_PATCH:
        LD (ST_DEST),HL
        LD A,(ST_CONDS)
        LD B,A
.LOOP:
        LD A,B
        OR A
        JR Z,.DONE
        DEC B
        LD A,B
        LD C,A
        LD A,(ST_CBASE)
        ADD A,C
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_CONDS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD DE,(ST_DEST)
        CALL SINK_FIX
        JR .LOOP
.DONE:
        CALL IF_POP                ; Release this cond's patch frame.
        XOR A                      ; Return carry clear after a complete cond.
        RET

IF_FAIL:
        CALL IF_POP
        POP AF                     ; Restore the caller's tail context on failure.
        LD (ST_TAIL),A
        SCF
        RET

IF_ABORT:
        POP AF                     ; Restore the caller's tail context.
        LD (ST_TAIL),A
        SCF
        RET
