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

; Read from the enclosing replay when this body is nested in a retained form.
SCDEFGET:
        LD A,(SCREP)
        OR A
        JP NZ,SCNEXT
        JP RNEXT

; Copy the current reader event into the bounded replay stream.
SCDEFPUT:
        LD (SCBEV),A
        LD (SCBVAL),HL
        LD A,(RTAG)
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
        CALL SCDEFGET              ; Read the next top-level body form.
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
        CALL SCDEFGET              ; The operator identifies a definition form.
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
        CALL SCDEFGET
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
; initializer so later definitions can refer back to it.
; The prepass has already claimed the current-range cell, so a definition
; reuses that claim instead of being mistaken for a duplicate declaration.
SCDEFUSE:
        CALL SCLOCF
        JP NC,SCRECDEC
        LD B,A
        LD A,(SCRECST)
        CP B
        JR Z,SCDEFOK
        JP NC,SCRECDEC
        LD A,(SCRECLIM)
        CP B
        JP C,SCRECDEC
        JP Z,SCRECDEC
SCDEFOK:
        LD A,B
        OR A
        RET

SCIDEF:
        XOR A
        LD (SCIDMODE),A            ; Internal definitions use local procedure cells.
        LD A,(SCRECPHS)
        OR A
        JR NZ,SCIDREAD
        LD A,(SCLNEXT)
        LD (SCRECST),A
        LD (SCRECLIM),A
        LD A,(SCCURPR)
        LD (SCRECPR),A
        LD A,1
        LD (SCRECMOD),A
        LD (SCRECPHS),A
SCIDREAD:
        CALL SCNEXT                ; A name is either a variable or a header list.
        JP C,SCSYN
        CP 1
        JP Z,SCIDPROC              ; Procedure-definition shorthand.
        CP 5
        JP NZ,SCDEFNSY
        LD (SCID),HL
        LD A,(SCBMODE)
        CP 1
        JR NZ,SCIDFOK              ; A let body may shadow an enclosing formal.
        CALL SCPFORM               ; A procedure body cannot redeclare a formal.
        JR NC,SCIDFOK
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP C,SCIDERR
SCIDFOK:
        CALL SCDEFUSE
        RET C
        LD (SCSLOT),A
        LD A,(SCSLOT)
        PUSH AF
        CALL SCINIT                ; Initializers run before the body expression.
        JP C,SCIDIERR
        POP AF
        LD (SCSLOT),A
        LD A,(SCSLOT)
        LD L,A
        LD A,1
        CALL SCSTORE
        RET C
        CALL SCEXPECT
        RET C
        LD A,1
        LD (SCISDEF),A
        LD (SCBDEFIN),A
        XOR A
        RET
SCIDIERR:
        POP AF
        JP SCIDERR

; Compile (define (name arg ...) body ...) inside a procedure body. The
; function cell is allocated in the enclosing scope, then the generated code
; creates its closure before jumping over the procedure body.
SCIDPROC:
        CALL SCNEXT                ; The header starts with the procedure name.
        JP C,SCIDERR
        CP 5
        JP NZ,SCDEFNSY
        LD (SCID),HL
        LD A,(SCBMODE)
        CP 1
        JR NZ,SCIDPFOK             ; A let body may shadow an enclosing formal.
        CALL SCPFORM               ; A procedure body cannot reuse a formal.
        JR NC,SCIDPFOK
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP SCIDERR
SCIDPFOK:
        LD A,(SCIDMODE)
        OR A
        JR NZ,SCIDGLOB              ; Package shorthand uses a global procedure cell.
        CALL SCDEFUSE               ; The name is a recursive local definition.
        JP C,SCIDERR
        JR SCIDCELL
SCIDGLOB:
        CALL SCGGET                 ; Allocate the package cell before its body.
        JP C,SCIDERR
SCIDCELL:
        LD (SCDEFSL),A              ; Preserve its slot while formals are parsed.
        CALL SCLOPEN                ; Enter the procedure's local activation scope.
        JP C,SCIDERR
        CALL SCPNEW                 ; Reserve its descriptor metadata record.
        JP C,SCIDUNW
        LD (SCCURPR),A              ; Formal slots belong to this descriptor.
SCIDPAR:
        CALL SCNEXT                 ; Read a formal name or the list close.
        JP C,SCIDUNW
        CP 2
        JR Z,SCIDPEND
        CP 5
        JP NZ,SCIDUNW
        LD (SCID),HL
        CALL SCPDUP                 ; Reject duplicate formals in this procedure.
        JR NC,SCIDPNEW
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP SCIDUNW
SCIDPNEW:
        CALL SCNSLOT
        JP C,SCIDUNW
        LD (SCSLOT),A
        CALL SCADDLOC
        JP C,SCIDUNW
        LD A,(SCSLOT)
        CALL SCPARAM
        JP C,SCIDUNW
        JR SCIDPAR
SCIDPEND:
        CALL SCMAKE                 ; Build the closure without a body jump yet.
        JP C,SCIDUNW
        LD A,(SCDEFSL)              ; Store the closure in the definition's cell.
        LD L,A
        LD A,(SCIDMODE)
        OR A
        JR Z,SCIDLOC
        XOR A                       ; Kind zero denotes a package-global cell.
        CALL SCSTORE
        JP C,SCIDUNW
        JR SCIDSTOK
SCIDLOC:
        LD A,1                      ; Kind one denotes an enclosing local cell.
        CALL SCSTORE
        JP C,SCIDUNW
SCIDSTOK:
        CALL SCJP                   ; Skip the procedure body during definition.
        JP C,SCIDUNW
        LD (SCSKIP),HL
        LD HL,(SCPC)
        LD (SCPBODY),HL
        LD A,1
        LD (SCTCTX),A
        LD A,(SCBISOL)
        PUSH AF
        LD A,1
        LD (SCBISOL),A
        CALL SCBODY
        JP C,SCIDBERR
        POP AF
        LD (SCBISOL),A
        CALL SCRET
        JP C,SCIDUNW
        CALL SCPFIN
        JP C,SCIDUNW
        CALL SCUNWIND
        JP C,SCIDERR
        LD A,1
        LD (SCISDEF),A
        LD (SCBDEFIN),A
        XOR A
        LD (SCIDMODE),A
        RET
SCIDBERR:
        POP AF                     ; Restore the enclosing body isolation flag.
        LD (SCBISOL),A
SCIDUNW:
        CALL SCUNWIND
SCIDERR:
        XOR A
        LD (SCIDMODE),A
        SCF
        RET

; Compile named let. The procedure is created before its initializers, then
; the call skips over the body on the ordinary path and enters it through the
; descriptor when the generated invocation runs.
SCNAMED:
        LD A,(SCNAMOP)             ; Nested named forms must restore this scratch word.
        PUSH AF
        LD A,(SCNAMNP)             ; Preserve the previous named descriptor marker.
        PUSH AF
        LD A,(SCTMPPR)             ; Named forms may be nested in a procedure body.
        PUSH AF                    ; Restore the enclosing descriptor on every exit.
        LD A,(SCARGN)              ; The enclosing application owns its own count.
        PUSH AF                    ; Named binding arguments must not leak outward.
        LD A,(SCDEFSL)             ; The enclosing definition may be using this scratch slot.
        PUSH AF                    ; Restore it after this named form has emitted its call.
        LD A,(SCTMPPR)
        LD (SCNAMOP),A             ; SCLOPEN must save this enclosing descriptor.
        LD A,(SCBNDTOP)
        LD (SCNAMBS),A             ; Temporary records hold binding names.
        CALL SCNEXT                ; The named form still requires a binding list.
        JR NC,SCNOK1
        JP SCNAMERR
SCNOK1:
        CP 1
        JP NZ,SCNAMERR
        CALL SCPNEW                ; Reserve the descriptor before emitting its value.
        JP C,SCNAMERR
        LD A,(SCTMPPR)
        LD (SCNAMNP),A             ; Keep this descriptor while nested forms run.
        CALL SCNSLOT               ; Reserve the recursive procedure's outer cell.
        JP C,SCNAMERR
        LD (SCDEFSL),A
        LD A,(SCNAMNP)             ; SCNSLOT records the outer owner for this cell.
        LD (SCTMPPR),A             ; Restore the new descriptor before SCMAKE.
        CALL SCNMAKE                ; The closure is stored before initializers run.
        JP C,SCNAMERR
        LD A,(SCDEFSL)
        LD L,A
        LD A,1
        CALL SCSTORE
        JP C,SCNAMERR
        XOR A
        LD (SCARGN),A
SCNAMB:
        CALL SCNEXT                ; Read a binding or the binding-list close.
        JP C,SCNAMERR
        CP 2
        JP Z,SCNAMGO
        CP 1
        JP NZ,SCNAMERR
        CALL SCNEXT                ; Every binding starts with a formal name.
        JP C,SCNAMERR
        CP 5
        JP NZ,SCNAMERR
        LD (SCID),HL
        CALL SCNAMDUP              ; Reject duplicate formal names early.
        JR NC,SCNAMNEW
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP SCNAMERR
SCNAMNEW:
        XOR A                      ; SCPEND needs a slot byte; formal slots come later.
        LD (SCSLOT),A
        CALL SCPEND                ; Keep this name while its initializer is emitted.
        JP C,SCNAMERR
        LD A,(SCNAMBS)             ; Nested named forms use the same scratch words.
        PUSH AF                    ; Preserve this form's pending-name marker.
        LD HL,(SCNAMID)            ; Preserve the enclosing named procedure name.
        PUSH HL
        LD A,(SCDEFSL)             ; Preserve its closure slot while parsing inside.
        PUSH AF
        LD A,(SCTMPPR)             ; Preserve the enclosing descriptor index.
        PUSH AF
        LD A,(SCNAMOP)             ; Preserve the enclosing named descriptor owner.
        PUSH AF
        LD A,(SCNAMNP)             ; Preserve the current named descriptor marker.
        PUSH AF
        LD A,(SCLETMOD)            ; Preserve the enclosing let spelling mode.
        PUSH AF
        LD A,(SCARGN)              ; Nested expressions may use the same count byte.
        PUSH AF                    ; Preserve the named call's argument count.
        CALL SCINIT                ; Initializers use only the enclosing environment.
        JR C,SCNMINI
        POP AF                     ; Restore the count after the initializer returns.
        LD (SCARGN),A
        POP AF                     ; Restore the enclosing let spelling mode.
        LD (SCLETMOD),A
        POP AF                     ; Restore the current named descriptor marker.
        LD (SCNAMNP),A
        POP AF                     ; Restore the enclosing named descriptor owner.
        LD (SCNAMOP),A
        POP AF                     ; Restore the enclosing descriptor index.
        LD (SCTMPPR),A
        POP AF                     ; Restore the enclosing closure slot.
        LD (SCDEFSL),A
        POP HL                     ; Restore the enclosing named procedure name.
        LD (SCNAMID),HL
        POP AF                     ; Restore the enclosing pending-name marker.
        LD (SCNAMBS),A
        CALL SCPUSH                ; Preserve source order in the generated packet.
        JP C,SCNAMERR
        LD A,(SCARGN)
        INC A
        LD (SCARGN),A
        CALL SCEXPECT              ; Close this binding pair before the next one.
        JP C,SCNAMERR
        JP SCNAMB
SCNMINI:
        POP AF                     ; Discard the saved argument count.
        POP AF                     ; Discard the saved let spelling mode.
        POP AF                     ; Discard the saved current named descriptor.
        POP AF                     ; Discard the saved enclosing named owner.
        POP AF                     ; Discard the saved descriptor index.
        POP AF                     ; Discard the saved closure slot.
        POP HL                     ; Discard the saved enclosing procedure name.
        POP AF                     ; Discard the saved pending-name marker.
        JP SCNAMERR

; Keep the named descriptor selected while SCMAKE records its fixup.
SCNMAKE:
        LD A,(SCNAMNP)
        LD (SCTMPPR),A
        JP SCMAKE

; Finish initializers, invoke the named procedure, then compile its body.
SCNAMGO:
        LD DE,(SCNAMID)
        LD (SCID),DE
        LD A,(SCDEFSL)
        LD (SCSLOT),A
        CALL SCADDLOC              ; The name is absent from initializers, present in body.
        JP C,SCNAMERR
        LD A,(SCDEFSL)
        LD L,A
        LD A,1
        CALL SCLOAD                ; Load the closure as the compact call operator.
        JP C,SCNAMERR
        LD HL,SRTOPUSH
        CALL SCCALL                ; Save it beside the staged argument packet.
        JP C,SCNAMERR
        LD A,(SCTCTX)
        LD (SCTLSAV),A             ; The named call inherits the enclosing tail context.
        LD A,1
        LD (SCAPMODE),A
        CALL SCAPDONE              ; Emit ordinary or tail invocation from the packet.
        JP C,SCNAMERR
        LD HL,(SCSKIP)             ; Preserve the enclosing jump-over patch.
        LD (SCNAMID),HL            ; The name is no longer needed after the call.
        CALL SCJP                  ; The ordinary path jumps over the procedure body.
        JP C,SCNAMERR
        LD (SCSKIP),HL
        LD A,(SCNAMOP)             ; Let SCLOPEN save the actual enclosing owner.
        LD (SCTMPPR),A
        CALL SCLOPEN               ; Formal slots and the body use a new owner.
        JP C,SCNAMERR
        LD A,(SCNAMNP)             ; Restore the named descriptor for its formals.
        LD (SCTMPPR),A
        LD (SCCURPR),A
        LD HL,(SCPC)               ; The named body starts after its skip prefix.
        LD (SCPBODY),HL
        CALL SCNAMSKP              ; Restore the enclosing skip when this body closes.
        JP C,SCNAMERR
        CALL SCNAMFRM              ; Add saved names as fixed procedure formals.
        JP C,SCNAMUNW
        LD A,1
        LD (SCTCTX),A
        LD A,(SCBISOL)
        PUSH AF
        LD A,1
        LD (SCBISOL),A
        CALL SCBODY
        JR C,SCNMBERR
        POP AF
        LD (SCBISOL),A
        CALL SCRET
        JP C,SCNAMUNW
        CALL SCPFIN               ; Patch the descriptor body and skip target.
        JP C,SCNAMUNW
        CALL SCUNWIND
        JP C,SCNAMERR
        JP SCNAMEND

SCNMBERR:
        POP AF
        LD (SCBISOL),A
SCNAMUNW:
        CALL SCUNWIND
        JP SCNAMERR

; Named dispatch bypasses SCLETSET's normal return, so remove that return
; before using the ordinary saved-scope cleanup paths.
SCNAMERR:
        POP AF                     ; Restore the enclosing definition's slot scratch.
        LD (SCDEFSL),A
        POP AF                     ; Restore the enclosing application argument count.
        LD (SCARGN),A
        POP AF                     ; Restore the enclosing descriptor index.
        LD (SCTMPPR),A
        POP AF                     ; Restore the previous named descriptor marker.
        LD (SCNAMNP),A
        POP AF                     ; Restore the enclosing named descriptor owner.
        LD (SCNAMOP),A
        POP DE                     ; Remove the return still owned by SCLETSET.
        JP SCLETERR
SCNAMEND:
        POP AF                     ; Restore the enclosing definition's slot scratch.
        LD (SCDEFSL),A
        POP AF                     ; Restore the enclosing application argument count.
        LD (SCARGN),A
        POP AF                     ; Restore the enclosing descriptor index.
        LD (SCTMPPR),A
        POP AF                     ; Restore the previous named descriptor marker.
        LD (SCNAMNP),A
        POP AF                     ; Restore the enclosing named descriptor owner.
        LD (SCNAMOP),A
        POP DE                     ; Remove the return still owned by SCLETSET.
        JP SCLETEND

; SCLOPEN follows the named call prefix, so replace its saved skip with the
; value that preceded the prefix.  Nested named forms then restore correctly.
SCNAMSKP:
        LD A,(SCBDEP)
        DEC A
        LD L,A
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD DE,SCBFRAME
        ADD HL,DE
        LD DE,5
        ADD HL,DE
        LD DE,(SCNAMID)
        LD (HL),E
        INC HL
        LD (HL),D
        XOR A
        RET

; Add the temporary named-let records to the procedure descriptor and scope.
SCNAMFRM:
        LD A,(SCNAMBS)
        LD (SCNAMCUR),A
SCNAMP:
        LD A,(SCNAMCUR)
        LD B,A
        LD A,(SCBNDTOP)
        CP B
        RET Z
        LD A,B
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCBINDID
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SCID),DE
        CALL SCPDUP
        JP C,SCNMDUPF
        CALL SCNSLOT
        RET C
        LD (SCSLOT),A
        CALL SCADDLOC
        RET C
        LD A,(SCSLOT)
        CALL SCPARAM
        RET C
        LD A,(SCNAMCUR)
        INC A
        LD (SCNAMCUR),A
        JR SCNAMP
SCNMDUPF:
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        SCF
        RET

; Check the temporary name records owned by this named-let form.
SCNAMDUP:
        LD A,(SCNAMBS)
        LD C,A
        LD A,(SCBNDTOP)
        SUB C
        JR Z,SCNAMDN
        LD B,A
SCNADLP:
        LD A,C
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCBINDID
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(SCID)
        OR A
        SBC HL,DE
        JR Z,SCNADUP
        INC C
        DJNZ SCNADLP
SCNAMDN:
        XOR A
        RET
SCNADUP:
        SCF
        RET
