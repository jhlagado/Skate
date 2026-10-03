; Scope compiler leading-definition capture and predeclaration.
; Entry points: SCDEFINE, SCDEFCAP, SCDEFPRE and SCDEFDUP.
; Leading internal-definition support.
;
; A procedure body is retained only through its leading definition region and
; the first ordinary form.  Names are installed before any initializer runs;
; the body then replays those bounded events and returns to the source stream.

; Compile a package-level definition.  The initializer is compiled before the
; global cell is published, while the selected slot survives nested scopes.
SCDEFINE:
        LD A,(ST_ATTOP)            ; Nested define is outside this increment.
        OR A                       ; Nonzero is the package-level permission.
        JP Z,ERR_DEF               ; Reject definitions inside an expression body.
        CALL SCNEXT                ; Read the new global's symbol name.
        RET C                      ; Propagate source failure before allocation.
        CP 1                       ; An opening list selects procedure shorthand.
        JP Z,SCDEFPR               ; The header list supplies the procedure name.
        CP 5                       ; Definitions require one identifier.
        JP NZ,ERR_NAME             ; A list or literal is not a binding name.
        LD (ST_SYMID),HL           ; Preserve the full identity across the initializer.
        CALL SCGGET                ; Forward references use this same slot.
        RET C                      ; Reject the 257th distinct package name.
        LD (ST_DSLOT),A            ; The store below targets this global slot.
        LD A,(ST_DSLOT)            ; Nested local definitions reuse this scratch byte.
        PUSH AF                    ; Keep the package slot across the initializer.
        CALL CMD_NEXT              ; Compile the initializer before publishing it.
        JR C,SCDFERR               ; Restore the package slot before reporting failure.
        POP AF                     ; Recover the package slot after recursive compilation.
        LD (ST_DSLOT),A            ; The store below must target the package binding.
        LD A,(ST_DSLOT)            ; Recover the selected global slot.
        LD L,A                     ; Pass the slot number to EM_STORE.
        XOR A                      ; Kind zero denotes a package-global slot.
        CALL EM_STORE              ; Emit the initialized flag update at runtime.
        RET C                      ; A fixup-capacity error is terminal.
        CALL CMD_END               ; Require the definition's closing parenthesis.
        RET                        ; The stored value remains the form result.
SCDFERR:
        POP AF                     ; Discard the saved package slot on failure.
        LD (ST_DSLOT),A            ; Restore it before the caller unwinds.
        SCF                        ; Preserve the initializer diagnostic.
        RET

; Compile a package-level fixed-parameter procedure definition.  The opening
; list has already been consumed; SCIDPROC reads its name and formal names.
SCDEFPR:
        LD A,1
        LD (ST_INPKG),A            ; SCIDPROC stores the closure in a global cell.
        JP SCIDPROC

; Copy the current reader event into the bounded replay stream.
SCDEFPUT:
        LD (ST_EVENT),A
        LD (ST_EVVAL),HL
        LD A,(RD_TAG)
        LD (ST_EVTAG),A
        JP SCRECPUT

; Capture leading definitions and the first ordinary body form.
SCDEFCAP:
        CALL SCRECOPN              ; Save the source or enclosing replay cursor.
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
        JP NZ,SCDFSEL
        LD A,(ST_LETLO)
        LD (ST_DEFLO),A            ; Let bindings and definitions share one scope.
        JR SCDFOK
SCDFSEL:
        LD A,(ST_LTOP)
        LD (ST_DEFLO),A            ; Procedure formals are checked separately.
SCDFOK:
        LD A,(ST_PROC)
        LD (ST_RPROC),A
        LD A,(ST_BINDS)
        LD (ST_RPEND),A
        LD A,1
        LD (ST_RMODE),A
        LD (ST_RINIT),A
SCDEFFRM:
        CALL SCNEXT                ; Read the next body form, marking binary16 literals.
        JP C,SCDEFFAL
        CALL SCDEFPUT
        JP C,SCDEFFAL
        LD A,(ST_EVENT)
        CP 2                       ; A close is an empty or definition-only body.
        JP Z,SCDEFDON
        CP 1                       ; Every body form starts with an opening list.
        JP NZ,SCDEFDON             ; A scalar body form needs only one replay event.
        LD A,1
        LD (ST_NEST),A
        CALL SCNEXT                ; The operator identifies a definition form.
        JP C,SCDEFFAL
        CALL SCDEFPUT
        JP C,SCDEFFAL
        LD A,(ST_EVENT)
        CP 5
        JP NZ,SCDEFDON             ; Computed operators are ordinary body forms.
        LD DE,K_DEFINE
        CALL CMD_SAME
        JR Z,SCDEFYES
        XOR A
        LD (ST_LEAD),A
        JP SCDEFDON                ; Let the normal body parser read the rest.
SCDEFYES:
        LD A,1
        LD (ST_LEAD),A
SCDEFSKP:
        CALL SCNEXT                ; Source or enclosing replay, as SCNEXT selects.
        JP C,SCDEFFAL
        CALL SCDEFPUT
        JP C,SCDEFFAL
        LD A,(ST_EVENT)
        CP 1
        JR Z,SCDEFINC
        CP 2
        JR Z,SCDEFDEC
        JR SCDEFSKP
SCDEFINC:
        LD A,(ST_NEST)
        INC A
        LD (ST_NEST),A
        JR SCDEFSKP
SCDEFDEC:
        LD A,(ST_NEST)
        DEC A
        LD (ST_NEST),A
        JR NZ,SCDEFSKP
        LD A,(ST_LEAD)
        OR A
        JP NZ,SCDEFFRM            ; Keep buffering another leading definition.
SCDEFDON:
        LD A,(ST_PLAY)
        OR A
        JR Z,SCDEFSET
        CALL SCRECSAV              ; Preserve the enclosing replay cursor.
SCDEFSET:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        LD HL,(ST_PUTP)
        LD (ST_EVEND),HL
        LD A,1
        LD (ST_BACK),A             ; SCNEXT will restore the source after replay.
        LD (ST_PLAY),A
        CALL SCDEFPRE              ; Install every definition before replay.
        RET C
        LD A,(ST_LEADS)
        OR A
        RET NZ                     ; Keep recursive state for the definition body.
        CALL SCRECRST              ; A non-definition body keeps outer scope rules.
        XOR A
        RET

; Predeclare each leading definition in the retained range.
SCDEFPRE:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        XOR A
        LD (ST_LEADS),A
SCDEPLP:
        CALL SCNEXT
        RET C
        CP 2
        JP Z,SCDEPPD
        CP 1
        JP NZ,SCDEPPD
        CALL SCNEXT                ; Read and verify the define operator.
        RET C
        CP 5
        JP NZ,SCDEPPD
        LD DE,K_DEFINE
        CALL CMD_SAME
        JP NZ,SCDEPPD
        CALL SCNEXT                ; A variable name or shorthand header follows.
        RET C
        CP 1
        JR Z,SCDEPHDR
        CP 5
        JP NZ,SCDEFFAL
        JR SCDEPNAM
SCDEPHDR:
        CALL SCNEXT
        RET C
        CP 5
        JP NZ,SCDEFFAL
        LD A,2                    ; The header opening is already part of the form.
        LD (ST_NEST),A            ; Include it while skipping the definition body.
SCDEPNAM:
        LD (ST_SYMID),HL
        CALL SCDEFDUP              ; Reject a name already in this lexical scope.
        JR NC,SCDEPNOK
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP SCDEFFAL
SCDEPNOK:
        LD A,(ST_NEST)
        OR A
        JR NZ,SCDEPSK
        LD A,1                    ; A variable definition has one open list.
        LD (ST_NEST),A
SCDEPSK:
        CALL SCRECDEC              ; The active directory now contains the name.
        RET C
        LD (ST_SLOT),A
        CALL EM_CLEAR              ; A reused static cell begins unbound.
        RET C
        LD A,(ST_LEADS)
        INC A
        LD (ST_LEADS),A
        CALL SCDEFSKR               ; Skip the rest of this definition form.
        RET C
        JP SCDEPLP

; Return carry when ST_SYMID is already active in the current definition scope.
SCDEFDUP:
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
SCDEFDLP:
        LD A,(ST_SYMID)
        CP (HL)
        JR NZ,SCDEFDNX
        INC HL
        LD A,(ST_SYMID+1)
        CP (HL)
        JP Z,SCDFDUP
        DEC HL
SCDEFDNX:
        INC HL
        INC HL
        INC B
        LD A,B
        CP C
        JR NZ,SCDEFDLP
        XOR A
        RET
SCDFDUP:
        SCF
        RET

; Finish the declaration scan and replay the retained body from its start.
SCDEPPD:
        LD HL,(ST_EVLO)
        LD (ST_GETP),HL
        LD A,1
        LD (ST_PLAY),A
        XOR A
        RET

; Skip one retained top-level form after its definition name.
SCDEFSKR:
SCDEFSKL:
        CALL SCNEXT
        RET C
        CP 1
        JR Z,SCDEFSKI
        CP 2
        JR NZ,SCDEFSKL
        LD A,(ST_NEST)
        DEC A
        LD (ST_NEST),A
        JR NZ,SCDEFSKL
        XOR A
        RET
SCDEFSKI:
        LD A,(ST_NEST)
        INC A
        LD (ST_NEST),A
        JR SCDEFSKL

; Restore recursive fields from the enclosing replay frame without ending it.
SCRECRST:
        CALL SCRECADR
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

SCDEFFAL:
        CALL SCRECPOP
        SCF
        RET

; Compile a leading internal definition. Its cell is available before the
