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
        LD A,(SCTOP)               ; Nested define is outside this increment.
        OR A                       ; Nonzero is the package-level permission.
        JP Z,SCDEFSYN              ; Reject definitions inside an expression body.
        CALL SCNEXT                ; Read the new global's symbol name.
        RET C                      ; Propagate source failure before allocation.
        CP 1                       ; An opening list selects procedure shorthand.
        JP Z,SCDEFPR               ; The header list supplies the procedure name.
        CP 5                       ; Definitions require one identifier.
        JP NZ,SCDEFNSY             ; A list or literal is not a binding name.
        LD (SCID),HL               ; Preserve the full identity across the initializer.
        CALL SCGGET                ; Forward references use this same slot.
        RET C                      ; Reject the 257th distinct package name.
        LD (SCDEFSL),A             ; The store below targets this global slot.
        LD A,(SCDEFSL)             ; Nested local definitions reuse this scratch byte.
        PUSH AF                    ; Keep the package slot across the initializer.
        CALL SCEXPR                ; Compile the initializer before publishing it.
        JR C,SCDFERR               ; Restore the package slot before reporting failure.
        POP AF                     ; Recover the package slot after recursive compilation.
        LD (SCDEFSL),A             ; The store below must target the package binding.
        LD A,(SCDEFSL)             ; Recover the selected global slot.
        LD L,A                     ; Pass the slot number to SCSTORE.
        XOR A                      ; Kind zero denotes a package-global slot.
        CALL SCSTORE               ; Emit the initialized flag update at runtime.
        RET C                      ; A fixup-capacity error is terminal.
        CALL SCEXPECT              ; Require the definition's closing parenthesis.
        RET                        ; The stored value remains the form result.
SCDFERR:
        POP AF                     ; Discard the saved package slot on failure.
        LD (SCDEFSL),A             ; Restore it before the caller unwinds.
        SCF                        ; Preserve the initializer diagnostic.
        RET

; Compile a package-level fixed-parameter procedure definition.  The opening
; list has already been consumed; SCIDPROC reads its name and formal names.
SCDEFPR:
        LD A,1
        LD (SCIDMODE),A            ; SCIDPROC stores the closure in a global cell.
        JP SCIDPROC

; Copy the current reader event into the bounded replay stream.
SCDEFPUT:
        LD (SCBEV),A
        LD (SCBVAL),HL
        LD A,(RD_TAG)
        LD (SCBTAG),A
        JP SCRECPUT

; Capture leading definitions and the first ordinary body form.
SCDEFCAP:
        CALL SCRECOPN              ; Save the source or enclosing replay cursor.
        RET C                      ; The nested body bound is explicit.
        LD HL,(SCRECWP)
        LD (SCRECBAS),HL           ; This body owns the appended event range.
        XOR A
        LD (SCDFCNT),A             ; No definitions have been predeclared yet.
        LD A,(SCLNEXT)
        LD (SCRECST),A
        LD (SCRECLIM),A
        LD A,(SCBMODE)
        CP 2
        JP NZ,SCDFSEL
        LD A,(SCLEBASE)
        LD (SCDEFSB),A             ; Let bindings and definitions share one scope.
        JR SCDFOK
SCDFSEL:
        LD A,(SCLOCTOP)
        LD (SCDEFSB),A             ; Procedure formals are checked separately.
SCDFOK:
        LD A,(SCCURPR)
        LD (SCRECPR),A
        LD A,(SCBNDTOP)
        LD (SCRECPND),A
        LD A,1
        LD (SCRECMOD),A
        LD (SCRECPHS),A
SCDEFFRM:
        CALL SCNEXT                ; Read the next body form, marking binary16 literals.
        JP C,SCDEFFAL
        CALL SCDEFPUT
        JP C,SCDEFFAL
        LD A,(SCBEV)
        CP 2                       ; A close is an empty or definition-only body.
        JP Z,SCDEFDON
        CP 1                       ; Every body form starts with an opening list.
        JP NZ,SCDEFDON             ; A scalar body form needs only one replay event.
        LD A,1
        LD (SCREDEP),A
        CALL SCNEXT                ; The operator identifies a definition form.
        JP C,SCDEFFAL
        CALL SCDEFPUT
        JP C,SCDEFFAL
        LD A,(SCBEV)
        CP 5
        JP NZ,SCDEFDON             ; Computed operators are ordinary body forms.
        LD DE,SCDEF
        CALL SCMATCH
        JR Z,SCDEFYES
        XOR A
        LD (SCDFMOD),A
        JP SCDEFDON                ; Let the normal body parser read the rest.
SCDEFYES:
        LD A,1
        LD (SCDFMOD),A
SCDEFSKP:
        CALL SCNEXT                ; Source or enclosing replay, as SCNEXT selects.
        JP C,SCDEFFAL
        CALL SCDEFPUT
        JP C,SCDEFFAL
        LD A,(SCBEV)
        CP 1
        JR Z,SCDEFINC
        CP 2
        JR Z,SCDEFDEC
        JR SCDEFSKP
SCDEFINC:
        LD A,(SCREDEP)
        INC A
        LD (SCREDEP),A
        JR SCDEFSKP
SCDEFDEC:
        LD A,(SCREDEP)
        DEC A
        LD (SCREDEP),A
        JR NZ,SCDEFSKP
        LD A,(SCDFMOD)
        OR A
        JP NZ,SCDEFFRM            ; Keep buffering another leading definition.
SCDEFDON:
        LD A,(SCREP)
        OR A
        JR Z,SCDEFSET
        CALL SCRECSAV              ; Preserve the enclosing replay cursor.
SCDEFSET:
        LD HL,(SCRECBAS)
        LD (SCRECRP),HL
        LD HL,(SCRECWP)
        LD (SCREWEND),HL
        LD A,1
        LD (SCRECAUT),A            ; SCNEXT will restore the source after replay.
        LD (SCREP),A
        CALL SCDEFPRE              ; Install every definition before replay.
        RET C
        LD A,(SCDFCNT)
        OR A
        RET NZ                     ; Keep recursive state for the definition body.
        CALL SCRECRST              ; A non-definition body keeps outer scope rules.
        XOR A
        RET

; Predeclare each leading definition in the retained range.
SCDEFPRE:
        LD HL,(SCRECBAS)
        LD (SCRECRP),HL
        XOR A
        LD (SCDFCNT),A
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
        LD DE,SCDEF
        CALL SCMATCH
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
        LD (SCREDEP),A            ; Include it while skipping the definition body.
SCDEPNAM:
        LD (SCID),HL
        CALL SCDEFDUP              ; Reject a name already in this lexical scope.
        JR NC,SCDEPNOK
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP SCDEFFAL
SCDEPNOK:
        LD A,(SCREDEP)
        OR A
        JR NZ,SCDEPSK
        LD A,1                    ; A variable definition has one open list.
        LD (SCREDEP),A
SCDEPSK:
        CALL SCRECDEC              ; The active directory now contains the name.
        RET C
        LD (SCSLOT),A
        CALL SCCLEAR               ; A reused static cell begins unbound.
        RET C
        LD A,(SCDFCNT)
        INC A
        LD (SCDFCNT),A
        CALL SCDEFSKR               ; Skip the rest of this definition form.
        RET C
        JP SCDEPLP

; Return carry when SCID is already active in the current definition scope.
SCDEFDUP:
        LD A,(SCDEFSB)
        LD B,A
        LD A,(SCLOCTOP)
        CP B
        RET Z
        LD C,A
        LD L,B
        LD H,0
        ADD HL,HL
        LD DE,SCLOCIDS
        ADD HL,DE
SCDEFDLP:
        LD A,(SCID)
        CP (HL)
        JR NZ,SCDEFDNX
        INC HL
        LD A,(SCID+1)
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
        LD HL,(SCRECBAS)
        LD (SCRECRP),HL
        LD A,1
        LD (SCREP),A
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
        LD A,(SCREDEP)
        DEC A
        LD (SCREDEP),A
        JR NZ,SCDEFSKL
        XOR A
        RET
SCDEFSKI:
        LD A,(SCREDEP)
        INC A
        LD (SCREDEP),A
        JR SCDEFSKL

; Restore recursive fields from the enclosing replay frame without ending it.
SCRECRST:
        CALL SCRECADR
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
        RET

SCDEFFAL:
        CALL SCRECPOP
        SCF
        RET

; Compile a leading internal definition. Its cell is available before the
