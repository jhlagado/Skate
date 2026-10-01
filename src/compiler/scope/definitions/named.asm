; Scope compiler named-let construction and temporary bindings.
; Entry points: SCNAMED, SCNMAKE, SCNAMGO and SCNAMDUP.
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
