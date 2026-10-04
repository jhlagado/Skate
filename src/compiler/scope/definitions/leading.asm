; Scope compiler leading-definition capture and predeclaration.
; Entry points: DEF_TOP, DEF_LEAD, .DECLARE and .DUP_CHK.
; Leading internal-definition support.
;
; A procedure body is retained only through its leading definition region and
; the first ordinary form.  Names are installed before any initializer runs;
; the body then replays those bounded events and returns to the source stream.

; Compile a package-level definition.  The initializer is compiled before the
; global cell is published, while the selected slot survives nested scopes.
DEF_TOP:
        LD A,(ST_ATTOP)            ; Nested define is outside this increment.
        OR A                       ; Nonzero is the package-level permission.
        JP Z,ERR_DEF               ; Reject definitions inside an expression body.
        CALL REC_NEXT              ; Read the new global's symbol name.
        RET C                      ; Propagate source failure before allocation.
        CP 1                       ; An opening list selects procedure shorthand.
        JP Z,.PROC                 ; The header list supplies the procedure name.
        CP 5                       ; Definitions require one identifier.
        JP NZ,ERR_NAME             ; A list or literal is not a binding name.
        LD (ST_SYMID),HL           ; Preserve the full identity across the initializer.
        CALL GLB_GET               ; Forward references use this same slot.
        RET C                      ; Reject the 257th distinct package name.
        LD (ST_DSLOT),A            ; The store below targets this global slot.
        LD A,(ST_DSLOT)            ; Nested local definitions reuse this scratch byte.
        PUSH AF                    ; Keep the package slot across the initializer.
        CALL CMD_NEXT              ; Compile the initializer before publishing it.
        JR C,.FAIL                 ; Restore the package slot before reporting failure.
        POP AF                     ; Recover the package slot after recursive compilation.
        LD (ST_DSLOT),A            ; The store below must target the package binding.
        LD A,(ST_DSLOT)            ; Recover the selected global slot.
        LD L,A                     ; Pass the slot number to EM_STORE.
        XOR A                      ; Kind zero denotes a package-global slot.
        CALL EM_STORE              ; Emit the initialized flag update at runtime.
        RET C                      ; A fixup-capacity error is terminal.
        CALL CMD_END               ; Require the definition's closing parenthesis.
        RET                        ; The stored value remains the form result.
.FAIL:
        POP AF                     ; Discard the saved package slot on failure.
        LD (ST_DSLOT),A            ; Restore it before the caller unwinds.
        SCF                        ; Preserve the initializer diagnostic.
        RET

; Compile a package-level fixed-parameter procedure definition.  The opening
; list has already been consumed; DEF_PROC reads its name and formal names.
.PROC:
        LD A,1
        LD (ST_INPKG),A            ; DEF_PROC stores the closure in a global cell.
        JP DEF_PROC

; Copy the current reader event into the bounded replay stream.
DEF_PUT:
        LD (ST_EVENT),A
        LD (ST_EVVAL),HL
        LD A,C
        LD (ST_EVEXT),A
        LD A,(RD_TAG)
        LD (ST_EVTAG),A
        JP REC_PUT

; Capture leading definitions and the first ordinary body form.
DEF_LEAD:
        CALL REC_OPEN              ; Save the source or enclosing replay cursor.
        RET C                      ; The nested body bound is explicit.
        LD HL,(ST_PUTP)
        LD (ST_EVLO),HL            ; This body owns the appended event range.
        XOR A
        LD (ST_LEADS),A            ; No definitions have been predeclared yet.
        LD A,(ST_LNEXT)
        LD (ST_RBASE),A
        LD (ST_RTOP),A
        LD A,(ST_BMODE)
        CP 2
        JP NZ,.FORMALS
        LD A,(ST_LETLO)
        LD (ST_DEFLO),A            ; Let bindings and definitions share one scope.
        JR .STATE
.FORMALS:
        LD A,(ST_LTOP)
        LD (ST_DEFLO),A            ; Procedure formals are checked separately.
.STATE:
        LD A,(ST_PROC)
        LD (ST_RPROC),A
        LD A,(ST_BINDS)
        LD (ST_RPEND),A
        LD A,1
        LD (ST_RMODE),A
        LD (ST_RINIT),A
.FORM:
        CALL REC_NEXT              ; Read the next body form, marking float literals.
        JP C,.FAIL
        CALL DEF_PUT
        JP C,.FAIL
        LD A,(ST_EVENT)
        CP 2                       ; A close is an empty or definition-only body.
        JP Z,.CAPTURED
        CP 1                       ; Every body form starts with an opening list.
        JP NZ,.CAPTURED            ; A scalar body form needs only one replay event.
        LD A,1
        LD (ST_NEST),A
        CALL REC_NEXT              ; The operator identifies a definition form.
        JP C,.FAIL
        CALL DEF_PUT
        JP C,.FAIL
        LD A,(ST_EVENT)
        CP 5
        JP NZ,.CAPTURED            ; Computed operators are ordinary body forms.
        LD DE,K_DEFINE
        CALL CMD_SAME
        JR Z,.DEFINE
        XOR A
        LD (ST_LEAD),A
        JP .CAPTURED               ; Let the normal body parser read the rest.
.DEFINE:
        LD A,1
        LD (ST_LEAD),A
.SKIP:
        CALL REC_NEXT              ; Source or enclosing replay, as REC_NEXT selects.
        JP C,.FAIL
        CALL DEF_PUT
        JP C,.FAIL
        LD A,(ST_EVENT)
        CP 1
        JR Z,.SKIP_IN
        CP 2
        JR Z,.SKIP_OUT
        JR .SKIP
.SKIP_IN:
        LD A,(ST_NEST)
        INC A
        LD (ST_NEST),A
        JR .SKIP
.SKIP_OUT:
        LD A,(ST_NEST)
        DEC A
        LD (ST_NEST),A
        JR NZ,.SKIP
        LD A,(ST_LEAD)
        OR A
        JP NZ,.FORM               ; Keep buffering another leading definition.
.CAPTURED:
        LD A,(ST_PLAY)
        OR A
        JR Z,.REPLAY
        CALL REC_SAVE              ; Preserve the enclosing replay cursor.
.REPLAY:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        LD HL,(ST_PUTP)
        LD (ST_EVEND),HL
        LD A,1
        LD (ST_BACK),A             ; REC_NEXT will restore the source after replay.
        LD (ST_PLAY),A
        CALL .DECLARE              ; Install every definition before replay.
        RET C
        LD A,(ST_LEADS)
        OR A
        RET NZ                     ; Keep recursive state for the definition body.
        CALL .RESTORE              ; A non-definition body keeps outer scope rules.
        XOR A
        RET

; Predeclare each leading definition in the retained range.
.DECLARE:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        XOR A
        LD (ST_LEADS),A
.NEXT_DEF:
        CALL REC_NEXT
        RET C
        CP 2
        JP Z,.DECLARED
        CP 1
        JP NZ,.DECLARED
        CALL REC_NEXT              ; Read and verify the define operator.
        RET C
        CP 5
        JP NZ,.DECLARED
        LD DE,K_DEFINE
        CALL CMD_SAME
        JP NZ,.DECLARED
        CALL REC_NEXT              ; A variable name or shorthand header follows.
        RET C
        CP 1
        JR Z,.HEADER
        CP 5
        JP NZ,.FAIL
        JR .NAME
.HEADER:
        CALL REC_NEXT
        RET C
        CP 5
        JP NZ,.FAIL
        LD A,2                    ; The header opening is already part of the form.
        LD (ST_NEST),A            ; Include it while skipping the definition body.
.NAME:
        LD (ST_SYMID),HL
        CALL .DUP_CHK              ; Reject a name already in this lexical scope.
        JR NC,.UNIQUE
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP .FAIL
.UNIQUE:
        LD A,(ST_NEST)
        OR A
        JR NZ,.INSTALL
        LD A,1                    ; A variable definition has one open list.
        LD (ST_NEST),A
.INSTALL:
        CALL LET_DECL              ; The active directory now contains the name.
        RET C
        LD (ST_SLOT),A
        CALL EM_CLEAR              ; A reused static cell begins unbound.
        RET C
        LD A,(ST_LEADS)
        INC A
        LD (ST_LEADS),A
        CALL .DEF_SKIP              ; Skip the rest of this definition form.
        RET C
        JP .NEXT_DEF

; Return carry when ST_SYMID is already active in the current definition scope.
.DUP_CHK:
        LD A,(ST_DEFLO)
        LD B,A
        LD A,(ST_LTOP)
        CP B
        RET Z
        LD C,A
        LD L,B
        LD H,0
        ADD HL,HL
        LD DE,W_LKEYS
        ADD HL,DE
.DUP_LOOP:
        LD A,(ST_SYMID)
        CP (HL)
        JR NZ,.DUP_NEXT
        INC HL
        LD A,(ST_SYMID+1)
        CP (HL)
        JP Z,.DUP_YES
        DEC HL
.DUP_NEXT:
        INC HL
        INC HL
        INC B
        LD A,B
        CP C
        JR NZ,.DUP_LOOP
        XOR A
        RET
.DUP_YES:
        SCF
        RET

; Finish the declaration scan and replay the retained body from its start.
.DECLARED:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        LD A,1
        LD (ST_PLAY),A
        XOR A
        RET

; Skip one retained top-level form after its definition name.
.DEF_SKIP:
.DEF_NEXT:
        CALL REC_NEXT
        RET C
        CP 1
        JR Z,.DEF_IN
        CP 2
        JR NZ,.DEF_NEXT
        LD A,(ST_NEST)
        DEC A
        LD (ST_NEST),A
        JR NZ,.DEF_NEXT
        XOR A
        RET
.DEF_IN:
        LD A,(ST_NEST)
        INC A
        LD (ST_NEST),A
        JR .DEF_NEXT

; Restore recursive fields from the enclosing replay frame without ending it.
.RESTORE:
        CALL REC_ADDR
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
        RET

.FAIL:
        CALL REC_POP
        SCF
        RET

; Compile a leading internal definition. Its cell is available before the
