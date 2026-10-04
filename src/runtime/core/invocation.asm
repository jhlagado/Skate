; Scope runtime closure, primitive, apply and tail dispatch.
; Entry points: INV_OP, INV_GO, APPLY, INV_TAIL and INV_TC.
; Included in runtime order by ../core.asm.

; Generated code calls the six most frequent helpers with RST 08H..30H, one
; byte instead of three.  CP/M leaves these page-zero vectors to the program;
; RST 38H stays free for a debugger.  The compiler's .VECTORS lists the same
; helpers in the same order.
RST_SET:
        LD HL,.TABLE
        LD DE,0008H
        LD B,6
.VECTOR:
        LD A,0C3H                  ; JP nn.
        LD (DE),A
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        LD A,E
        ADD A,6                    ; The next vector is eight bytes on.
        LD E,A
        DJNZ .VECTOR
        RET
.TABLE:
        DW ARG_PUSH,L_LOAD,PRIM_OP,QT_PUSH,G_OPSH,INV_OP

; Generated code pushes each argument with CALL ARG_PUSH: the value in A:HL is
; recorded as an exact root and pushed as PUSH AF, PUSH HL below the return.
; A and HL are kept.
ARG_PUSH:
%IF PROBE
        CALL PROBE
%ENDIF
        CALL ROOT_ADD
        POP DE                     ; The generated continuation.
        PUSH AF
        PUSH HL
        PUSH DE
        RET

; Recover a value pushed by ARG_PUSH into A:HL and retire its root record.
ARG_POP:
        POP DE                     ; The generated continuation.
        POP HL
        POP AF
        PUSH DE
        JP ROOT_POP                ; Keeps A:HL.

; Call a predefined primitive whose kind is known when the program is
; compiled.  Generated code is CALL PRIM_OP, DB payload, DB count, where the
; payload byte is the primitive value's low byte.  No operator value is
; evaluated or pushed by the generated code; it is pushed here, so the call
; then continues exactly as an operator-stack call does.
PRIM_OP:
        POP HL                     ; The inline payload and count bytes.
        LD E,(HL)
        INC HL
        LD A,(HL)
        INC HL
        PUSH HL                    ; Return after the count byte.
        LD (PRIM_CNT),A
        LD L,E
        LD H,0FEH
        XOR A
        CALL OPS_PUSH
        LD A,(PRIM_CNT)
        JP INV_OP

; The tail-position form: the CALL's return is discarded, as by INV_OPTC.
PRIM_TL:
        POP HL                     ; The inline payload and count bytes.
        LD E,(HL)
        INC HL
        LD A,(HL)
        LD (PRIM_CNT),A
        LD L,E
        LD H,0FEH
        XOR A
        CALL OPS_PUSH
        LD A,(PRIM_CNT)
        JP INV_OPTL

PRIM_CNT: DB 0                     ; Argument count across the operator push.

; Slot helpers.  Generated code names a global or a procedure local with one
; byte after the CALL: CALL G_LOAD, DB slot.  Each helper steps the return
; address over that byte.  Globals live in the fixed area at G_BASE.

; Load global SLOT into A:HL.
G_LOAD:
        POP HL
        LD E,(HL)
        INC HL
        PUSH HL
G_FETCH:
        LD L,E
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,(G_BASE)
        ADD HL,DE
        JP RT_LOAD

; Load global SLOT and save it on the operator side stack: the operator of a
; call to a global procedure.
G_OPSH:
        POP HL
        LD E,(HL)
        INC HL
        PUSH HL
        CALL G_FETCH
        JP OPS_PUSH

; Store A:HL in global SLOT, initializing it (G_STORE) or as a checked
; set! of a bound global (G_SET).  A:HL is returned unchanged by G_STORE.
G_STORE:
        LD (G_TAG),A
        XOR A
        JR G_PUT
G_SET:
        LD (G_TAG),A
        LD A,1
G_PUT:
        LD (G_MODE),A
        EX (SP),HL                 ; HL addresses the slot byte.
        LD E,(HL)
        INC HL
        EX (SP),HL                 ; The return now skips the byte.
        PUSH HL
        LD L,E
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,(G_BASE)
        ADD HL,DE
        EX DE,HL                   ; DE is the slot.
        POP HL
        LD A,(G_MODE)
        OR A
        LD A,(G_TAG)
        JP Z,RT_STORE
        JP RT_SET

G_TAG:  DB 0
G_MODE: DB 0

; Load or store procedure local SLOT through the active environment.
L_LOAD:
        POP HL
        LD A,(HL)
        INC HL
        PUSH HL
        JP FRM_LOAD
L_STORE:
        EX (SP),HL
        LD B,(HL)
        INC HL
        EX (SP),HL
        JP FRM_INIT
L_SET:
        EX (SP),HL
        LD B,(HL)
        INC HL
        EX (SP),HL
        JP FRM_SET

; Call an operator value saved on the side stack before argument evaluation.
; A contains the argument count and the native stack contains only arguments.
INV_OP:
        POP IX                    ; Save this helper's generated continuation.
        LD (FRM_SAVE),IX          ; Packet helpers use IX for their own return.
        LD B,A                    ; Preserve the generated argument count.
        LD HL,(ENV_CUR)           ; Save the caller environment for a closure call.
        LD (ENV_RET),HL
        LD HL,(DESC_CUR)          ; Save the caller descriptor before dispatch.
        LD (DESC_RET),HL
        LD A,(SLOT_CNT)            ; The caller map remains a precise root.
        LD (ENV_RCNT),A
        LD A,B
        LD (ARG_CNT),A            ; The count remains available to the packet pass.
        CALL PKT_PACK             ; Pack arguments, then recover the saved value.
        JP C,ERROR
        LD IX,(FRM_SAVE)
        JR INV_GO                 ; Share primitive and closure dispatch.

; Call a fixed-arity procedure descriptor. A contains the argument count and
; the native stack contains callee, then arguments, in the order emitted by
; EM_PUSH. The descriptor records the body address and formal slot addresses.
INV_CALL:
        POP IX                    ; Save this helper's return address in IX.
        LD (FRM_SAVE),IX          ; FRM_PACK uses IX for its own helper return.
        LD B,A                    ; Preserve the generated argument count.
        LD HL,(ENV_CUR)           ; Save the caller environment for the new frame.
        LD (ENV_RET),HL           ; The body may invoke another closure.
        LD HL,(DESC_CUR)          ; Save the caller descriptor before dispatch.
        LD (DESC_RET),HL
        LD A,(SLOT_CNT)            ; Save the caller map's exact slot extent.
        LD (ENV_RCNT),A
        LD A,B
        LD (ARG_CNT),A            ; The count remains available to the packet pass.
        CALL FRM_PACK              ; Move reverse-pushed values into the packet.
        JP C,ERROR                 ; A malformed packet is a runtime failure.
        LD IX,(FRM_SAVE)           ; Recover the generated continuation after packing.
INV_GO:
        LD (ARG_TAG),A             ; Keep the callee tag while selecting its path.
        LD (ARG_VAL),HL            ; Keep the callee payload for both paths.
        OR A                       ; Tag zero may identify a predefined primitive.
        JR Z,INV_PRIM              ; Validate its reserved payload and dispatch it.
        XOR A                       ; A closure or invalid value clears apply dispatch.
        LD (APPLY_IN),A
        LD A,(ARG_TAG)              ; Restore the tag before the closure check.
        CP 2                       ; Tag two identifies a closure object.
        JP Z,.CLOSURE
        CP 8                       ; Tag eight identifies an active escape token.
        JP Z,INV_ESC
        JP ERROR                   ; Other scalar values cannot be called.
.CLOSURE:
        LD HL,(ARG_VAL)            ; Restore the closure object payload.
        LD (FRM_CLOS),HL          ; FRM_PACK returns the closure object payload.
        LD E,(HL)                  ; Read the descriptor pointer from its header.
        INC HL
        LD D,(HL)
        LD (DESC_CUR),DE           ; Keep the descriptor for arity and body lookup.
        INC HL
        INC HL                     ; The object payload now names its environment.
        LD HL,(DESC_CUR)           ; REST_CHK consumes the descriptor address.
        CALL REST_CHK             ; Validate the callee tag and descriptor arity.
        JP C,ERROR                 ; Do not jump through an arbitrary value.
        LD HL,(DESC_CUR)           ; Descriptor byte three fixes the map extent.
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SLOT_CNT),A
        LD L,A                     ; Widen the slot count before doubling it.
        LD H,0
        ADD HL,HL
        LD (FRM_CLEN),HL
        CALL ENV_NEW               ; Build an activation map below the stack.
        CALL REST_ARG              ; Copy packet values into the formal slots.
        JP C,ERROR                 ; A descriptor slot outside the image is invalid.
        XOR A                      ; The closure now owns the argument values.
        LD (ARG_CNT),A             ; Retire the packet before entering its body.
        PUSH IX                    ; Preserve the generated caller return address.
        LD DE,(FRM_SP)             ; Release the activation map when the body returns.
        PUSH DE                    ; The old stack boundary follows the return word.
        LD DE,(ENV_RET)            ; Preserve the caller environment below the frame.
        PUSH DE                    ; FRM_RET restores it after the body returns.
        LD HL,(DESC_RET)           ; Keep the caller descriptor for the epilogue.
        PUSH HL                    ; The epilogue restores this descriptor state.
        LD HL,(DESC_CUR)           ; Read the descriptor body pointer.
        LD E,(HL)                  ; Body address low byte is descriptor offset zero.
        INC HL                     ; Advance to the body address high byte.
        LD D,(HL)                  ; DE now names the generated procedure body.
        LD HL,FRM_RET              ; Body RET returns through this frame epilogue.
        PUSH HL                    ; Keep descriptor and caller return below it.
        LD HL,(ENV_CUR)            ; The map base identifies this fixed frame.
        LD (FRM_BASE),HL           ; Exact roots can derive suspended frames from it.
        EX DE,HL                   ; HL receives the target body address.
        JP (HL)                    ; Enter without adding a second native return.

; Route a tag-eight escape token to its dynamic one-shot handler.
INV_ESC:
        LD HL,(ARG_VAL)            ; Port values share tag eight with escapes.
        LD A,H
        CP 0F0H
        JP NC,ERROR                ; The F000H port namespace is never callable.
        JP EC_ESC

; Route a primitive callee through the checked packet dispatcher.
INV_PRIM:
        CALL INV_KIND              ; Validate and classify the reserved payload.
        LD A,(APPLY_IN)            ; Apply preserves the outer continuation for primitives.
        OR A
        JR Z,.DISPATCH
        XOR A
        LD (APPLY_IN),A
        LD IX,(FRM_SAVE)           ; The inner primitive returns to the outer call.
.DISPATCH:
        JP PRIM_RUN                ; The generated continuation remains in IX.

; Validate a predefined primitive payload and retain its zero-based kind.
INV_KIND:
        LD HL,(ARG_VAL)            ; Primitive values use the reserved FE20H range.
        LD A,H
        CP 0FEH
        JP NZ,ERROR                ; A tag-zero value outside the range is not callable.
        LD A,L
        CP 20H
        JP C,ERROR
        CP PRIM_LIM                ; Kinds run to the end of the standard set.
        JP NC,ERROR
        SUB 20H
        LD (PRIM_ID),A             ; Kind zero is addition; kind three is zero?.
        XOR A
        RET

; Proper-tail transfer: replace the current procedure frame before entering
; the target.  The current activation map is reused, so a tail loop does not
; allocate a new pointer array on every iteration.
INV_TAIL:
        LD HL,(DESC_CUR)           ; Retain the current descriptor for reuse checks.
        LD (DESC_OLD),HL
        LD B,A                     ; Preserve the generated argument count.
        LD A,(SLOT_CNT)            ; Preserve the current map extent for the guard.
        LD (FRM_SPAN),A
        LD A,B
        LD (ARG_CNT),A             ; The tail packet uses the generated count.
        CALL FRM_PACK              ; Parse arguments while the current frame remains.
        JP C,ERROR                ; A malformed tail packet is terminal.
INV_TLGO:
        LD (ARG_TAG),A             ; Keep the target tag while selecting its path.
        LD (ARG_VAL),HL            ; Keep the target payload for both paths.
        CP 8                       ; A tail escape invokes the active one-shot record.
        JP Z,INV_ESC               ; It discards the current procedure frame safely.
        OR A                       ; A predefined primitive has no closure object.
        JR NZ,.CLOSURE              ; A closure target reuses the active frame below.
        LD A,(APPLY_TL)             ; Apply's primitive target keeps that frame intact.
        OR A
        JP NZ,.APPLY
        JP PRIM_TCO                 ; Reuse the current epilogue after evaluation.
; Apply's primitive tail path keeps the active frame on the native stack.
.APPLY:
        CALL INV_KIND               ; Revalidate the primitive target.
        LD A,(PRIM_ID)              ; Inspect the target after validation.
        CP 45                       ; A nested apply must keep spreading in tail mode.
        JR Z,.NESTED                ; Leave its frame epilogue for the next target.
        POP IX                      ; Remove the active frame epilogue before return.
        JP PRIM_RUN                 ; Evaluate the primitive through that epilogue.
.NESTED:
        JP APPLY                     ; Preserve tail mode while applying the next target.
.CLOSURE:
        LD A,(ARG_TAG)              ; Restore the target tag after the mode check.
        CP 2                       ; Only closure objects reach the existing tail path.
        JP NZ,ERROR
        XOR A                       ; The apply-tail marker is no longer needed.
        LD (APPLY_TL),A
        LD HL,(ARG_VAL)            ; Restore the closure object payload.
        LD (FRM_CLOS),HL          ; Resolve the target closure object.
        LD E,(HL)                  ; Read its descriptor pointer.
        INC HL
        LD D,(HL)
        LD (DESC_CUR),DE           ; Keep the target descriptor for validation.
        INC HL
        INC HL
        LD HL,(DESC_CUR)
        CALL REST_CHK             ; Validate the target procedure and arity.
        JP C,ERROR                ; Do not reuse a frame for an invalid target.
        LD HL,(DESC_CUR)           ; Load the target's bounded pointer-map extent.
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SLOT_CNT),A
        LD L,A                     ; Widen the target slot count before doubling.
        LD H,0
        ADD HL,HL
        LD (FRM_CLEN),HL
        LD A,(FRM_SPAN)            ; The active array must hold the target shape.
        LD B,A
        LD A,(SLOT_CNT)
        CP B
        JR Z,.FITS                 ; An equal shape fits the active map exactly.
        JR NC,.BAD                 ; A larger target cannot fit the active map.
        JR .FITS                   ; A target smaller than the current map also fits.
.FITS:
        CALL ENV_COPY              ; Replace captured pointers from the target closure.
        CALL ENV_OWN               ; Reuse owned cells or allocate missing entries.
        JR .ARGS
.BAD:
        JP ERROR                   ; Reject a tail shape that cannot fit in place.
.ARGS:
        CALL REST_ARG              ; Install the target's formal values.
        JP C,ERROR                ; Reject an invalid descriptor slot.
        XOR A                      ; The tail target now owns the argument values.
        LD (ARG_CNT),A             ; Retire the packet before entering its body.
        POP DE                    ; Discard the current body epilogue address.
        POP DE                    ; Recover the caller descriptor for the target.
        LD (DESC_RET),DE
        POP DE                    ; Recover the caller environment below this frame.
        LD (ENV_RET),DE
        POP DE                    ; Recover the stack boundary below this frame.
        LD (FRM_SP),DE
        POP IX                    ; Recover the caller return below this frame.
        PUSH IX                   ; Preserve the original caller return word.
        LD DE,(FRM_SP)             ; Keep the reused activation map above the frame.
        PUSH DE
        LD DE,(ENV_RET)            ; Preserve the caller environment below the frame.
        PUSH DE
        LD HL,(DESC_RET)          ; Keep the caller descriptor on the new frame.
        PUSH HL                   ; The target returns through FRM_RET.
        LD HL,FRM_RET             ; Install the target's single epilogue.
        PUSH HL                   ; Tail recursion therefore uses constant stack.
        LD HL,(DESC_CUR)          ; Read the target body address.
        LD E,(HL)                 ; Body address low byte.
        INC HL                    ; Advance to the high body byte.
        LD D,(HL)                 ; Complete the target body address.
        EX DE,HL                  ; HL receives the target body pointer.
        JP (HL)                   ; Enter without a new continuation.

; Tail transfer for a saved operator.  Arguments are native-stack values and
; the operator was saved in the side stack before their expressions ran.
INV_OPTL:
        LD HL,(DESC_CUR)           ; Retain the current descriptor for reuse checks.
        LD (DESC_OLD),HL
        LD B,A                     ; Preserve the generated argument count.
        LD A,(SLOT_CNT)            ; Preserve the current map extent for the guard.
        LD (FRM_SPAN),A
        LD A,B
        LD (ARG_CNT),A             ; The side-stack packet uses the generated count.
        CALL PKT_PACK              ; Pack arguments, then recover the saved value.
        JP C,ERROR
        JP INV_TLGO                ; Share closure and primitive tail handling.

; A tail candidate is emitted as CALL until the compiler knows it is final.
; Discard that temporary return address before entering the tail-transfer path.
INV_TC:
        POP HL                    ; Remove the wrapper CALL continuation.
        JP INV_TAIL               ; The existing tail path sees the normal stack.

; The side-stack tail wrapper removes CALL's continuation before transfer.
INV_OPTC:
        POP HL
        JP INV_OPTL
