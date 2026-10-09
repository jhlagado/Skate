; Scope compiler named-let construction and temporary bindings.
; Entry points: LET_NAME, .MAKE, .CALL and .DUP_CHK.
; the call skips over the body on the ordinary path and enters it through the
; descriptor when the generated invocation runs.
LET_NAME:
        LD A,(ST_NLOWN)            ; Nested named forms must restore this scratch word.
        PUSH AF
        LD A,(ST_NLNEW)            ; Preserve the previous named descriptor marker.
        PUSH AF
        LD A,(ST_DESC)             ; Named forms may be nested in a procedure body.
        PUSH AF                    ; Restore the enclosing descriptor on every exit.
        LD A,(ST_ARGS)             ; The enclosing application owns its own count.
        PUSH AF                    ; Named binding arguments must not leak outward.
        LD A,(ST_DSLOT)            ; The enclosing definition may be using this scratch slot.
        PUSH AF                    ; Restore it after this named form has emitted its call.
        LD A,(ST_DESC)
        LD (ST_NLOWN),A            ; LAM_OPEN must save this enclosing descriptor.
        LD A,(ST_BINDS)
        LD (ST_NLREC),A            ; Temporary records hold binding names.
        CALL REC_NEXT              ; The named form still requires a binding list.
        JR NC,.LIST
        JP .FAIL
.LIST:
        CP 1
        JP NZ,.FAIL
        CALL PROC_NEW              ; Reserve the descriptor before emitting its value.
        JP C,.FAIL
        LD A,(ST_DESC)
        LD (ST_NLNEW),A            ; Keep this descriptor while nested forms run.
        CALL BIND_NEW              ; Reserve the recursive procedure's outer cell.
        JP C,.FAIL
        LD (ST_DSLOT),A
        LD A,(ST_NLNEW)            ; BIND_NEW records the outer owner for this cell.
        LD (ST_DESC),A             ; Restore the new descriptor before LAM_MAKE.
        CALL .MAKE                  ; The closure is stored before initializers run.
        JP C,.FAIL
        LD A,(ST_DSLOT)
        LD L,A
        LD A,1
        CALL EM_STORE
        JP C,.FAIL
        XOR A
        LD (ST_ARGS),A
.BINDING:
        CALL REC_NEXT              ; Read a binding or the binding-list close.
        JP C,.FAIL
        CP 2
        JP Z,.CALL
        CP 1
        JP NZ,.FAIL
        CALL REC_NEXT              ; Every binding starts with a formal name.
        JP C,.FAIL
        CP 5
        JP NZ,.FAIL
        LD (ST_SYMID),HL
        CALL .DUP_CHK              ; Reject duplicate formal names early.
        JR NC,.INIT
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP .FAIL
.INIT:
        XOR A                      ; LET_PUSH needs a slot byte; formal slots come later.
        LD (ST_SLOT),A
        CALL LET_PUSH              ; Keep this name while its initializer is emitted.
        JP C,.FAIL
        LD A,(ST_NLREC)            ; Nested named forms use the same scratch words.
        PUSH AF                    ; Preserve this form's pending-name marker.
        LD HL,(ST_NLID)            ; Preserve the enclosing named procedure name.
        PUSH HL
        LD A,(ST_DSLOT)            ; Preserve its closure slot while parsing inside.
        PUSH AF
        LD A,(ST_DESC)             ; Preserve the enclosing descriptor index.
        PUSH AF
        LD A,(ST_NLOWN)            ; Preserve the enclosing named descriptor owner.
        PUSH AF
        LD A,(ST_NLNEW)            ; Preserve the current named descriptor marker.
        PUSH AF
        LD A,(ST_NLOK)             ; Preserve the enclosing let spelling mode.
        PUSH AF
        LD A,(ST_ARGS)             ; Nested expressions may use the same count byte.
        PUSH AF                    ; Preserve the named call's argument count.
        CALL LET_INIT              ; Initializers use only the enclosing environment.
        JR C,.INIT_BAD
        POP AF                     ; Restore the count after the initializer returns.
        LD (ST_ARGS),A
        POP AF                     ; Restore the enclosing let spelling mode.
        LD (ST_NLOK),A
        POP AF                     ; Restore the current named descriptor marker.
        LD (ST_NLNEW),A
        POP AF                     ; Restore the enclosing named descriptor owner.
        LD (ST_NLOWN),A
        POP AF                     ; Restore the enclosing descriptor index.
        LD (ST_DESC),A
        POP AF                     ; Restore the enclosing closure slot.
        LD (ST_DSLOT),A
        POP HL                     ; Restore the enclosing named procedure name.
        LD (ST_NLID),HL
        POP AF                     ; Restore the enclosing pending-name marker.
        LD (ST_NLREC),A
        CALL EM_PUSH               ; Preserve source order in the generated packet.
        JP C,.FAIL
        LD A,(ST_ARGS)
        INC A
        LD (ST_ARGS),A
        CALL CMD_END               ; Close this binding pair before the next one.
        JP C,.FAIL
        JP .BINDING
.INIT_BAD:
        POP AF                     ; Discard the saved argument count.
        POP AF                     ; Discard the saved let spelling mode.
        POP AF                     ; Discard the saved current named descriptor.
        POP AF                     ; Discard the saved enclosing named owner.
        POP AF                     ; Discard the saved descriptor index.
        POP AF                     ; Discard the saved closure slot.
        POP HL                     ; Discard the saved enclosing procedure name.
        POP AF                     ; Discard the saved pending-name marker.
        JP .FAIL

; Keep the named descriptor selected while LAM_MAKE records its fixup.
.MAKE:
        LD A,(ST_NLNEW)
        LD (ST_DESC),A
        JP LAM_MAKE

; Finish initializers, invoke the named procedure, then compile its body.
.CALL:
        LD DE,(ST_NLID)
        LD (ST_SYMID),DE
        LD A,(ST_DSLOT)
        LD (ST_SLOT),A
        CALL BIND_ADD              ; The name is absent from initializers, present in body.
        JP C,.FAIL
        LD A,(ST_DSLOT)
        LD L,A
        LD A,1
        CALL EM_LOAD               ; Load the closure as the compact call operator.
        JR C,.FAIL
        LD HL,OPS_PUSH
        CALL EM_CALL               ; Save it beside the staged argument packet.
        JR C,.FAIL
        LD A,(ST_TAIL)
        LD (ST_ATAIL),A            ; The named call inherits the enclosing tail context.
        LD A,1
        LD (ST_ROUTE),A
        CALL CALL_END              ; Emit ordinary or tail invocation from the packet.
        JR C,.FAIL
        LD HL,(ST_SKIP)            ; Preserve the enclosing jump-over patch.
        LD (ST_NLID),HL            ; The name is no longer needed after the call.
        CALL EM_JP                 ; The ordinary path jumps over the procedure body.
        JR C,.FAIL
        LD (ST_SKIP),HL
        LD A,(ST_NLOWN)            ; Let LAM_OPEN save the actual enclosing owner.
        LD (ST_DESC),A
        CALL LAM_OPEN              ; Formal slots and the body use a new owner.
        JR C,.FAIL
        LD A,(ST_NLNEW)            ; Restore the named descriptor for its formals.
        LD (ST_DESC),A
        LD (ST_PROC),A
        LD HL,(ST_PC)              ; The named body starts after its skip prefix.
        LD (ST_PBODY),HL
        CALL .SKIP_FIX             ; Restore the enclosing skip when this body closes.
        JR C,.FAIL
        CALL .FORMALS              ; Add saved names as fixed procedure formals.
        JR C,.UNWIND
        LD A,1
        LD (ST_TAIL),A
        LD A,(ST_ALONE)
        PUSH AF
        LD A,1
        LD (ST_ALONE),A
        CALL CMD_BODY
        JR C,.BODY_BAD
        POP AF
        LD (ST_ALONE),A
        CALL EM_PRET
        JR C,.UNWIND
        CALL PROC_END             ; Patch the descriptor body and skip target.
        JR C,.UNWIND
        CALL CAP_POP
        JR C,.FAIL
        JR .DONE

.BODY_BAD:
        POP AF
        LD (ST_ALONE),A
.UNWIND:
        CALL CAP_POP

; Named dispatch bypasses LET_OPEN's normal return, so remove that return
; before using the ordinary saved-scope cleanup paths.
.FAIL:
        POP AF                     ; Restore the enclosing definition's slot scratch.
        LD (ST_DSLOT),A
        POP AF                     ; Restore the enclosing application argument count.
        LD (ST_ARGS),A
        POP AF                     ; Restore the enclosing descriptor index.
        LD (ST_DESC),A
        POP AF                     ; Restore the previous named descriptor marker.
        LD (ST_NLNEW),A
        POP AF                     ; Restore the enclosing named descriptor owner.
        LD (ST_NLOWN),A
        POP DE                     ; Remove the return still owned by LET_OPEN.
        JP LET_FAIL
.DONE:
        POP AF                     ; Restore the enclosing definition's slot scratch.
        LD (ST_DSLOT),A
        POP AF                     ; Restore the enclosing application argument count.
        LD (ST_ARGS),A
        POP AF                     ; Restore the enclosing descriptor index.
        LD (ST_DESC),A
        POP AF                     ; Restore the previous named descriptor marker.
        LD (ST_NLNEW),A
        POP AF                     ; Restore the enclosing named descriptor owner.
        LD (ST_NLOWN),A
        POP DE                     ; Remove the return still owned by LET_OPEN.
        JP LET_DONE

; LAM_OPEN follows the named call prefix, so replace its saved skip with the
; value that preceded the prefix.  Nested named forms then restore correctly.
.SKIP_FIX:
        LD A,(ST_BNEST)
        DEC A
        LD L,A
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD DE,W_BODY
        ADD HL,DE
        LD DE,5
        ADD HL,DE
        LD DE,(ST_NLID)
        LD (HL),E
        INC HL
        LD (HL),D
        XOR A
        RET

; Add the temporary named-let records to the procedure descriptor and scope.
.FORMALS:
        LD A,(ST_NLREC)
        LD (ST_NLPOS),A
.FORMAL:
        LD A,(ST_NLPOS)
        LD B,A
        LD A,(ST_BINDS)
        CP B
        RET Z
        LD A,B
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_BKEYS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ST_SYMID),DE
        CALL CAP_DUP
        JR C,.FORM_DUP
        CALL BIND_NEW
        RET C
        LD (ST_SLOT),A
        CALL BIND_ADD
        RET C
        LD A,(ST_SLOT)
        CALL PROC_ARG
        RET C
        LD A,(ST_NLPOS)
        INC A
        LD (ST_NLPOS),A
        JR .FORMAL
.FORM_DUP:
        LD HL,M_DUP
        LD (ST_ERROR),HL
        SCF
        RET

; Check the temporary name records owned by this named-let form.
.DUP_CHK:
        LD A,(ST_NLREC)
        LD C,A
        LD A,(ST_BINDS)
        SUB C
        JR Z,.UNIQUE
        LD B,A
.DUP_LOOP:
        LD A,C
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_BKEYS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(ST_SYMID)
        OR A
        SBC HL,DE
        JR Z,.DUP_YES
        INC C
        DJNZ .DUP_LOOP
.UNIQUE:
        XOR A
        RET
.DUP_YES:
        SCF
        RET
