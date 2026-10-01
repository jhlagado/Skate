; Scope runtime closure, primitive, apply and tail dispatch.
; Entry points: SRTOPINV, SRTDISP, SRTAPPLY, SRTTAIL and SRTTCALL.
; Included in runtime order by ../core.asm.

; Call an operator value saved on the side stack before argument evaluation.
; A contains the argument count and the native stack contains only arguments.
SRTOPINV:
        POP IX                    ; Save this helper's generated continuation.
        LD (SRTRET),IX            ; Packet helpers use IX for their own return.
        LD B,A                    ; Preserve the generated argument count.
        LD HL,(SRTENV)            ; Save the caller environment for a closure call.
        LD (SRTCENV),HL
        LD HL,(SRTDESC)           ; Save the caller descriptor before dispatch.
        LD (SRTCDESC),HL
        LD A,(SRTSLOTS)            ; The caller map remains a precise root.
        LD (SRTCENVN),A
        LD A,B
        LD (SRTARGC),A            ; The count remains available to the packet pass.
        CALL SRTPACKO             ; Pack arguments, then recover the saved value.
        JP C,SRTERROR
        LD IX,(SRTRET)
        JR SRTDISP                ; Share primitive and closure dispatch.

; Call a fixed-arity procedure descriptor. A contains the argument count and
; the native stack contains callee, then arguments, in the order emitted by
; SCPUSH. The descriptor records the body address and formal slot addresses.
SRTINVOK:
        POP IX                    ; Save this helper's return address in IX.
        LD (SRTRET),IX            ; SRTPACK uses IX for its own helper return.
        LD B,A                    ; Preserve the generated argument count.
        LD HL,(SRTENV)            ; Save the caller environment for the new frame.
        LD (SRTCENV),HL           ; The body may invoke another closure.
        LD HL,(SRTDESC)           ; Save the caller descriptor before dispatch.
        LD (SRTCDESC),HL
        LD A,(SRTSLOTS)            ; Save the caller map's exact slot extent.
        LD (SRTCENVN),A
        LD A,B
        LD (SRTARGC),A            ; The count remains available to the packet pass.
        CALL SRTPACK               ; Move reverse-pushed values into the packet.
        JP C,SRTERROR              ; A malformed packet is a runtime failure.
        LD IX,(SRTRET)             ; Recover the generated continuation after packing.
SRTDISP:
        LD (SRTATMP),A             ; Keep the callee tag while selecting its path.
        LD (SRTVAL),HL             ; Keep the callee payload for both paths.
        OR A                       ; Tag zero may identify a predefined primitive.
        JR Z,SRTIPRIM              ; Validate its reserved payload and dispatch it.
        XOR A                       ; A closure or invalid value clears apply dispatch.
        LD (SRTAPDIS),A
        LD A,(SRTATMP)              ; Restore the tag before the closure check.
        CP 2                       ; Tag two identifies a closure object.
        JP Z,SRTICLOS
        CP 8                       ; Tag eight identifies an active escape token.
        JP Z,SRTIESC
        JP SRTERROR                ; Other scalar values cannot be called.
SRTICLOS:
        LD HL,(SRTVAL)             ; Restore the closure object payload.
        LD (SRTOBJ),HL            ; SRTPACK returns the closure object payload.
        LD E,(HL)                  ; Read the descriptor pointer from its header.
        INC HL
        LD D,(HL)
        LD (SRTDESC),DE            ; Keep the descriptor for arity and body lookup.
        INC HL
        INC HL                     ; The object payload now names its environment.
        LD HL,(SRTDESC)            ; SRTDCHK consumes the descriptor address.
        CALL SRTDCHK              ; Validate the callee tag and descriptor arity.
        JP C,SRTERROR              ; Do not jump through an arbitrary value.
        LD HL,(SRTDESC)            ; Descriptor byte three fixes the map extent.
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSLOTS),A
        LD L,A                     ; Widen the slot count before doubling it.
        LD H,0
        ADD HL,HL
        LD (SRTBYTES),HL
        CALL SRTENVIN              ; Build an activation map below the stack.
        CALL SRTSARGS              ; Copy packet values into the formal slots.
        JP C,SRTERROR              ; A descriptor slot outside the image is invalid.
        XOR A                      ; The closure now owns the argument values.
        LD (SRTARGC),A             ; Retire the packet before entering its body.
        PUSH IX                    ; Preserve the generated caller return address.
        LD DE,(SRTOLDSP)           ; Release the activation map when the body returns.
        PUSH DE                    ; The old stack boundary follows the return word.
        LD DE,(SRTCENV)            ; Preserve the caller environment below the frame.
        PUSH DE                    ; SRTINEND restores it after the body returns.
        LD HL,(SRTCDESC)           ; Keep the caller descriptor for the epilogue.
        PUSH HL                    ; The epilogue restores this descriptor state.
        LD HL,(SRTDESC)            ; Read the descriptor body pointer.
        LD E,(HL)                  ; Body address low byte is descriptor offset zero.
        INC HL                     ; Advance to the body address high byte.
        LD D,(HL)                  ; DE now names the generated procedure body.
        LD HL,SRTINEND             ; Body RET returns through this frame epilogue.
        PUSH HL                    ; Keep descriptor and caller return below it.
        LD HL,(SRTENV)             ; The map base identifies this fixed frame.
        LD (SRTFRAME),HL           ; Exact roots can derive suspended frames from it.
        EX DE,HL                   ; HL receives the target body address.
        JP (HL)                    ; Enter without adding a second native return.

; Route a tag-eight escape token to its dynamic one-shot handler.
SRTIESC:
        LD HL,(SRTVAL)             ; Port values share tag eight with escapes.
        LD A,H
        CP 0F0H
        JP NC,SRTERROR             ; The F000H port namespace is never callable.
        JP SRTCEESC

; Route a primitive callee through the checked packet dispatcher.
SRTIPRIM:
        CALL SRTIVAL               ; Validate and classify the reserved payload.
        LD A,(SRTAPDIS)            ; Apply preserves the outer continuation for primitives.
        OR A
        JR Z,SRTIPN
        XOR A
        LD (SRTAPDIS),A
        LD IX,(SRTRET)             ; The inner primitive returns to the outer call.
SRTIPN:
        JP SRTPRIM                 ; The generated continuation remains in IX.

; Validate a predefined primitive payload and retain its zero-based kind.
SRTIVAL:
        LD HL,(SRTVAL)             ; Primitive values use the reserved FE20..FE55 range.
        LD A,H
        CP 0FEH
        JP NZ,SRTERROR             ; A tag-zero value outside the range is not callable.
        LD A,L
        CP 20H
        JP C,SRTERROR
        CP 5CH                     ; File primitives extend the range through kind 59.
        JP NC,SRTERROR
        SUB 20H
        LD (SRTPID),A              ; Kind zero is addition; kind three is zero?.
        XOR A
        RET

; Proper-tail transfer: replace the current procedure frame before entering
; the target.  The current activation map is reused, so a tail loop does not
; allocate a new pointer array on every iteration.
SRTTAIL:
        LD HL,(SRTDESC)            ; Retain the current descriptor for reuse checks.
        LD (SRTCURD),HL
        LD B,A                     ; Preserve the generated argument count.
        LD A,(SRTSLOTS)            ; Preserve the current map extent for the guard.
        LD (SRTCURS),A
        LD A,B
        LD (SRTARGC),A             ; The tail packet uses the generated count.
        CALL SRTPACK               ; Parse arguments while the current frame remains.
        JP C,SRTERROR             ; A malformed tail packet is terminal.
SRTTARG:
        LD (SRTATMP),A             ; Keep the target tag while selecting its path.
        LD (SRTVAL),HL             ; Keep the target payload for both paths.
        CP 8                       ; A tail escape invokes the active one-shot record.
        JP Z,SRTIESC               ; It discards the current procedure frame safely.
        OR A                       ; A predefined primitive has no closure object.
        JR NZ,SRTTCLOS              ; A closure target reuses the active frame below.
        LD A,(SRTAPMOD)             ; Apply's primitive target keeps that frame intact.
        OR A
        JP NZ,SRTAPRT
        JP SRTTPRIM                 ; Reuse the current epilogue after evaluation.
; Apply's primitive tail path keeps the active frame on the native stack.
SRTAPRT:
        CALL SRTIVAL                ; Revalidate the primitive target.
        LD A,(SRTPID)               ; Inspect the target after validation.
        CP 45                       ; A nested apply must keep spreading in tail mode.
        JR Z,SRTAPNXT               ; Leave its frame epilogue for the next target.
        POP IX                      ; Remove the active frame epilogue before return.
        JP SRTPRIM                  ; Evaluate the primitive through that epilogue.
SRTAPNXT:
        JP SRTAPPLY                  ; Preserve tail mode while applying the next target.
SRTTCLOS:
        LD A,(SRTATMP)              ; Restore the target tag after the mode check.
        CP 2                       ; Only closure objects reach the existing tail path.
        JP NZ,SRTERROR
        XOR A                       ; The apply-tail marker is no longer needed.
        LD (SRTAPMOD),A
        LD HL,(SRTVAL)             ; Restore the closure object payload.
        LD (SRTOBJ),HL            ; Resolve the target closure object.
        LD E,(HL)                  ; Read its descriptor pointer.
        INC HL
        LD D,(HL)
        LD (SRTDESC),DE            ; Keep the target descriptor for validation.
        INC HL
        INC HL
        LD HL,(SRTDESC)
        CALL SRTDCHK              ; Validate the target procedure and arity.
        JP C,SRTERROR             ; Do not reuse a frame for an invalid target.
        LD HL,(SRTDESC)            ; Load the target's bounded pointer-map extent.
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSLOTS),A
        LD L,A                     ; Widen the target slot count before doubling.
        LD H,0
        ADD HL,HL
        LD (SRTBYTES),HL
        LD A,(SRTCURS)             ; The active array must hold the target shape.
        LD B,A
        LD A,(SRTSLOTS)
        CP B
        JR Z,SRTTSAME              ; An equal shape fits the active map exactly.
        JR NC,SRTTERR              ; A larger target cannot fit the active map.
        JR SRTTSAME                ; A target smaller than the current map also fits.
SRTTSAME:
        CALL SRTCOPYC              ; Replace captured pointers from the target closure.
        CALL SRTOWN                ; Reuse owned cells or allocate missing entries.
        JR SRTTKEEP
SRTTERR:
        JP SRTERROR                ; Reject a tail shape that cannot fit in place.
SRTTKEEP:
        CALL SRTSARGS              ; Install the target's formal values.
        JP C,SRTERROR             ; Reject an invalid descriptor slot.
        XOR A                      ; The tail target now owns the argument values.
        LD (SRTARGC),A             ; Retire the packet before entering its body.
        POP DE                    ; Discard the current body epilogue address.
        POP DE                    ; Recover the caller descriptor for the target.
        LD (SRTCDESC),DE
        POP DE                    ; Recover the caller environment below this frame.
        LD (SRTCENV),DE
        POP DE                    ; Recover the stack boundary below this frame.
        LD (SRTOLDSP),DE
        POP IX                    ; Recover the caller return below this frame.
        PUSH IX                   ; Preserve the original caller return word.
        LD DE,(SRTOLDSP)           ; Keep the reused activation map above the frame.
        PUSH DE
        LD DE,(SRTCENV)            ; Preserve the caller environment below the frame.
        PUSH DE
        LD HL,(SRTCDESC)          ; Keep the caller descriptor on the new frame.
        PUSH HL                   ; The target returns through SRTINEND.
        LD HL,SRTINEND            ; Install the target's single epilogue.
        PUSH HL                   ; Tail recursion therefore uses constant stack.
        LD HL,(SRTDESC)           ; Read the target body address.
        LD E,(HL)                 ; Body address low byte.
        INC HL                    ; Advance to the high body byte.
        LD D,(HL)                 ; Complete the target body address.
        EX DE,HL                  ; HL receives the target body pointer.
        JP (HL)                   ; Enter without a new continuation.

; Tail transfer for a saved operator.  Arguments are native-stack values and
; the operator was saved in the side stack before their expressions ran.
SRTOTAIL:
        LD HL,(SRTDESC)            ; Retain the current descriptor for reuse checks.
        LD (SRTCURD),HL
        LD B,A                     ; Preserve the generated argument count.
        LD A,(SRTSLOTS)            ; Preserve the current map extent for the guard.
        LD (SRTCURS),A
        LD A,B
        LD (SRTARGC),A             ; The side-stack packet uses the generated count.
        CALL SRTPACKO              ; Pack arguments, then recover the saved value.
        JP C,SRTERROR
        JP SRTTARG                 ; Share closure and primitive tail handling.

; A tail candidate is emitted as CALL until the compiler knows it is final.
; Discard that temporary return address before entering the tail-transfer path.
SRTTCALL:
        POP HL                    ; Remove the wrapper CALL continuation.
        JP SRTTAIL                ; The existing tail path sees the normal stack.

; The side-stack tail wrapper removes CALL's continuation before transfer.
SRTOTCL:
        POP HL
        JP SRTOTAIL
