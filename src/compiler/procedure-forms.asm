; Procedure forms for the compact compiler.
;
; A procedure value is a tagged pointer to a fixed descriptor.  Descriptors
; name the generated body and its formal slots.  The runtime saves ordinary
; formals around a call; slots referenced by an escaping nested lambda remain
; live so the closure and its creator share the same cell.

; Compile a general application.  The operator value has already been emitted
; and each argument is pushed as A:HL, with the callee below the arguments.
SCAPARGS:
        LD A,(SCTCTX)              ; Save whether the complete call is tail code.
        LD (SCTLSAV),A             ; Arguments themselves are never tail code.
        XOR A                      ; No argument has been staged yet.
        LD (SCARGN),A              ; The runtime receives this bounded count.
SCAPLOOP:
        CALL RNEXT                 ; Read one argument or the application's close.
        RET C                      ; Preserve a source failure before emission.
        CP 2                       ; A close ends the argument sequence.
        JR Z,SCAPDONE              ; Zero-argument calls are valid.
        CP 0                       ; EOF cannot terminate an application.
        JP Z,SCAPSY                ; Report an incomplete call.
        LD (SCAPEV),A              ; Preserve the event kind across SCEXPE.
        LD (SCAPVAL),HL            ; Save the reader payload before SCEXPE reads it.
        LD A,(RTAG)                ; The scalar tag is one byte in the reader state.
        LD (SCAPTAG),A             ; Preserve it while SCEXPE reads the argument.
        LD A,(SCARGN)              ; The packet has a deliberately small bound.
        CP 8                       ; Eight values cover the first procedure tests.
        JP NC,SCCAP                ; A larger call would overrun the runtime packet.
        XOR A                      ; The argument expression is not tail-position.
        LD (SCTCTX),A              ; Nested calls therefore retain their return.
        LD A,(SCAPTAG)             ; Restore the reader's scalar tag byte.
        LD (RTAG),A                ; Symbol and list events ignore this field.
        LD A,(SCAPEV)              ; Restore the event kind for SCEXPE.
        LD HL,(SCAPVAL)            ; Restore its interned ID or numeric payload.
        LD A,(SCARGN)              ; Preserve this application's count across recursion.
        PUSH AF                     ; A nested application uses the same scratch byte.
        LD A,(SCTLSAV)             ; Preserve this application's tail decision as well.
        PUSH AF                     ; The nested parser may replace the shared value.
        LD A,(SCAPMODE)            ; Preserve this application's marker mode as well.
        PUSH AF                     ; Nested operators may select a different mode.
        LD A,(SCAPGSL)             ; Preserve this application's global slot as well.
        PUSH AF                     ; Nested operators may select a different slot.
        LD A,(SCAPTAG)             ; Restore the reader's scalar tag after saving state.
        LD (RTAG),A                ; Symbol and list events ignore this field.
        LD A,(SCAPEV)              ; Restore the event kind for SCEXPE.
        LD HL,(SCAPVAL)            ; Restore its interned ID or numeric payload.
        CALL SCEXPE                ; Compile the argument expression.
        JR C,SCAPERR               ; Balance the saved application state on failure.
        POP AF                     ; Restore the enclosing global slot.
        LD (SCAPGSL),A
        POP AF                     ; Restore the enclosing compact-call mode.
        LD (SCAPMODE),A
        POP AF                     ; Restore the enclosing application's tail decision.
        LD (SCTLSAV),A             ; Its next argument still belongs to that call.
        POP AF                     ; Restore the enclosing argument count.
        LD (SCARGN),A              ; Count the value only after its expression returns.
        CALL SCPUSH                ; Stage the resulting value below later args.
        RET C                      ; Preserve a generated-output capacity failure.
        LD A,(SCARGN)              ; Count the value only after it was emitted.
        INC A                      ; The next packet position follows this one.
        LD (SCARGN),A              ; Publish the complete argument count.
        JR SCAPLOOP                ; Continue in source order.
SCAPDONE:
        LD A,(SCAPMODE)            ; A compact global call needs no callee value.
        OR A
        JR Z,SCAPGEND
        XOR A
        LD (SCAPMODE),A
        LD A,(SCTLSAV)             ; Reuse the normal tail decision for the saved value.
        OR A
        JR NZ,SCAPOTL
        LD HL,SRTOPINV              ; Dispatch the saved operator value.
        JP SCINVOKE
SCAPOTL:
        LD A,2                      ; SCITAIL selects the side-stack tail wrapper.
        LD (SCAPMODE),A
        LD HL,SRTOTAIL
        JP SCITAIL
SCAPGEND:
        LD A,(SCTLSAV)             ; Recover the application's tail context.
        OR A                       ; A tail call uses a jump through the runtime.
        JR NZ,SCAPTAIL             ; The target returns directly to our caller.
        LD HL,SRTINVOK            ; Ordinary calls preserve the current return.
        JP SCINVOKE                ; Emit the count load and runtime CALL.
SCAPTAIL:
        LD HL,SRTTAIL              ; Tail calls reuse the current return address.
        JP SCITAIL                 ; Emit the count load and runtime JP.

; Remove the four compiler-stack words left by a failed nested argument.
SCAPERR:
        POP AF                     ; Discard the saved global slot.
        POP AF                     ; Discard the saved compact-call mode.
        POP AF                     ; Discard the saved tail decision.
        POP AF                     ; Discard the saved argument count.
        SCF                        ; Preserve the nested expression failure.
        RET                        ; The enclosing application is abandoned.
SCAPSY:
        LD HL,SCAPTXT
        LD (SCERRPTR),HL
        JP SCSYN

; Emit A=argument-count followed by CALL or JP HL.  The runtime entry receives
; the callee and arguments from the generated native stack.
SCINVOKE:
        LD (SCWTMP),HL             ; Keep the selected runtime entry address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SCBYTE                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(SCARGN)              ; Recover the count after the opcode write.
        CALL SCBYTE                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(SCWTMP)             ; Restore the runtime target after SCBYTE.
        JP SCCALL                  ; Append CALL nn for an ordinary application.

SCITAIL:
        LD (SCWTMP),HL             ; Keep the selected tail helper address.
        LD A,3EH                   ; LD A,n supplies the packet count.
        CALL SCBYTE                ; Append the opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(SCARGN)              ; Recover the count after the opcode write.
        CALL SCBYTE                ; Append the count byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,0CDH                  ; CALL first gives the body a patchable candidate.
        CALL SCBYTE                ; Append the tail transfer opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(SCPC)               ; The following word names the tail wrapper.
        CALL SCTSAVE               ; Keep it until body finality is known.
        RET C                      ; Preserve tail-record capacity exhaustion.
        LD HL,SRTTCALL              ; The normal wrapper discards CALL's continuation.
        LD A,(SCAPMODE)
        CP 2
        JR NZ,SCITWR
        LD HL,SRTOTCL              ; Side-stack calls use their matching wrapper.
        XOR A
        LD (SCAPMODE),A
SCITWR:
        JP SCWORD                  ; Append its absolute address.

; Emit the fixed-arity lambda expression and its body.  The generated prefix
; constructs a static closure value and jumps over the body until invocation.
SCLAMBF:
        CALL SCLOPEN               ; Save the enclosing local directory and owner.
        RET C                      ; The compiler frame table has a fixed bound.
        CALL SCPNEW                ; Reserve one descriptor metadata record.
        JP C,SCLAMERR              ; Restore the enclosing scope on capacity failure.
        LD (SCTMPPR),A             ; Keep the new descriptor while parsing params.
        LD (SCCURPR),A             ; Formal slots belong to this new descriptor.
        CALL RNEXT                 ; Lambda requires a parenthesised parameter list.
        JP C,SCLAMERR              ; Restore scope state on a reader failure.
        CP 1                       ; The parameter container must be an opening list.
        JP NZ,SCLAMERR             ; Reject dotted and scalar parameter forms.
SCLAMP:
        CALL RNEXT                 ; Read a parameter name or the list close.
        JP C,SCLAMERR              ; Restore the enclosing scope before returning.
        CP 2                       ; A close completes the formal parameter list.
        JR Z,SCLAMPD               ; The body follows immediately after the list.
        CP 5                       ; Every formal is an interned identifier.
        JP NZ,SCLAMERR             ; Reject literals and nested lists as names.
        LD (SCID),HL               ; Preserve the parameter identity for SCADDLOC.
        CALL SCPDUP                ; A procedure cannot bind the same name twice.
        JR NC,SCLAMPNW            ; An outer binding may be shadowed legally.
        LD HL,SCDUPTXT             ; Report duplicate formals as a source error.
        LD (SCERRPTR),HL
        JP SCLAMERR
SCLAMPNW:
        CALL SCNSLOT               ; Allocate its reusable activation slot.
        JP C,SCLAMERR              ; Reject the first local beyond the hard bound.
        LD (SCSLOT),A              ; SCADDLOC reads the selected slot from here.
        CALL SCADDLOC              ; Make the parameter visible in the body.
        JP C,SCLAMERR              ; A full active directory is a compile error.
        LD A,(SCSLOT)              ; SCADDLOC returns the active count in A.
        CALL SCPARAM               ; Record the slot in the descriptor metadata.
        JP C,SCLAMERR              ; Reject an arity above the descriptor capacity.
        JR SCLAMP                  ; Read the next formal name.
SCLAMPD:
        CALL SCPREFX               ; Emit the closure value and jump-over branch.
        LD HL,(SCPC)
        LD (SCPBODY),HL            ; The body starts immediately after the prefix.
        JP C,SCLAMERR              ; Preserve an output or metadata failure.
        LD A,1                     ; A lambda body is always a tail context.
        LD (SCTCTX),A              ; SCBODY passes this to its final expression.
        LD (SCBISOL),A             ; Its tail candidates belong to this procedure.
        CALL SCBODY                ; Compile expressions through the lambda close.
        JP C,SCLAMERR              ; Unwind scope state on any body failure.
        CALL SCRET                 ; A normal body returns its final A:HL value.
        JP C,SCLAMERR              ; The return byte itself is bounded output.
        CALL SCPFIN                ; Save body address and patch the jump-over.
        JP C,SCLAMERR              ; Preserve the descriptor-layout failure.
        JP SCLAMEND                ; Restore the enclosing scope and return closure.

; Save local cursors and select the newly-created procedure as owner.
SCLOPEN:
        LD A,(SCBDEP)              ; The compiler frame table is explicitly bounded.
        CP 32
        JP NC,SCCAP                ; Reject nesting beyond the reserved records.
        LD C,A                     ; C selects the current four-byte frame.
        INC A
        LD (SCBDEP),A              ; Publish the nested body depth.
        LD L,C                     ; Widen the frame index before scaling it.
        LD H,0
        LD D,H                     ; Keep a second copy for the nine-byte scale.
        LD E,L
        ADD HL,HL                  ; Two bytes per partial record.
        ADD HL,HL                  ; Four bytes per saved lambda frame.
        ADD HL,HL                  ; Eight bytes per saved lambda frame.
        ADD HL,DE                  ; Add one byte for the complete record width.
        LD DE,SCBFRAME             ; Locate the saved cursor record.
        ADD HL,DE
        LD A,(SCLOCTOP)            ; Preserve the active outer-binding count.
        LD (HL),A
        INC HL
        LD A,(SCLNEXT)             ; Preserve the reusable local slot cursor.
        LD (HL),A
        INC HL
        LD A,(SCCURPR)             ; Preserve the enclosing procedure owner.
        LD (HL),A
        INC HL
        LD A,(SCTCTX)              ; Preserve the enclosing tail-position state.
        LD (HL),A
        INC HL
        LD A,(SCTMPPR)             ; Preserve the enclosing procedure descriptor.
        LD (HL),A
        INC HL
        LD DE,(SCSKIP)             ; Preserve the enclosing jump-over patch.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(SCPBODY)            ; Preserve the enclosing body cursor.
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(SCTMPPR)             ; Select the new owner for formal slots.
        LD (SCCURPR),A             ; Captured outer names now point at this record.
        XOR A                      ; Carry clear reports a balanced scope opening.
        RET                        ; The parameter parser may allocate locals.

; Restore the enclosing local directory while retaining the closure result.
SCLAMEND:
        LD (SCRESV),HL             ; Preserve the body's result payload.
        LD (SCREST),A              ; Preserve the closure tag while restoring state.
        CALL SCUNWIND                ; Restore the enclosing compiler frame.
        RET C                      ; A missing frame is an internal capacity error.
        LD HL,(SCRESV)             ; Restore the body's result value.
        LD A,(SCREST)              ; Restore the closure or body result tag.
        OR A                        ; The lambda expression itself has no carry error.
        RET                        ; Return the descriptor pointer in A:HL.

SCLAMERR:
        CALL SCUNWIND                ; Balance the frame before reporting failure.
        SCF                        ; The caller reports a compile error.
        RET                        ; No partially generated file is published.

; Return carry when the current procedure already has a formal with SCID.
SCPDUP:
        LD A,(SCLOCTOP)            ; No active records means no duplicate exists.
        OR A
        RET Z
        LD B,A                     ; B counts the active local records.
        LD HL,SCLOCIDS             ; HL scans the two-byte binding identities.
        LD DE,SCLOCSLT             ; DE scans their one-byte slot numbers.
SCPDUPLP:
        LD A,(HL)                  ; Compare the stored identity low byte.
        LD C,A
        LD A,(SCID)
        CP C
        JR NZ,SCPDUPLO             ; A low-byte mismatch skips to the next record.
        INC HL                     ; Compare the stored identity high byte.
        LD C,(HL)
        LD A,(SCID+1)
        CP C
        JR NZ,SCPDUPHI            ; A high-byte mismatch leaves this record.
        LD A,(DE)                  ; Matching names must belong to this procedure.
        LD C,A
        PUSH HL                    ; Preserve the identity cursor during owner lookup.
        PUSH DE                    ; Preserve the slot cursor for the next record.
        LD L,C                     ; Widen the matching slot number.
        LD H,0
        LD DE,SCLOCOWN             ; Locate the owner procedure for that slot.
        ADD HL,DE
        LD A,(HL)
        LD C,A
        LD A,(SCCURPR)
        CP C
        POP DE                     ; Restore the active binding cursors.
        POP HL
        JR Z,SCPDUPOK             ; A same-procedure name is a duplicate.
SCPDUPHI:
        INC HL                     ; Advance from the high identity byte.
        INC DE                     ; Advance to the next slot number.
        DJNZ SCPDUPLP              ; Inspect every active binding.
        XOR A                      ; Carry clear means no duplicate was found.
        RET
SCPDUPLO:
        INC HL                     ; Skip the unmatched low identity byte.
        JR SCPDUPHI              ; Complete the common record advance.
SCPDUPOK:
        SCF                        ; The caller rejects the parameter list.
        RET

; Restore one enclosing lambda frame from the compiler-side frame table.
SCUNWIND:
        LD A,(SCBDEP)              ; A zero depth means no frame can be restored.
        OR A
        SCF
        RET Z
        DEC A
        LD (SCBDEP),A
        LD C,A
        LD L,C
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD DE,SCBFRAME
        ADD HL,DE
        LD A,(HL)                  ; Restore the active local directory extent.
        LD (SCLOCTOP),A
        INC HL
        LD A,(HL)                  ; Restore the reusable slot cursor.
        LD (SCLNEXT),A
        INC HL
        LD A,(HL)                  ; Restore the enclosing procedure owner.
        LD (SCCURPR),A
        INC HL
        LD A,(HL)                  ; Restore the enclosing tail-position state.
        LD (SCTCTX),A
        INC HL
        LD A,(HL)                  ; Restore the enclosing procedure descriptor.
        LD (SCTMPPR),A
        INC HL
        LD E,(HL)                  ; Restore the enclosing jump-over patch.
        INC HL
        LD D,(HL)
        LD (SCSKIP),DE
        INC HL
        LD E,(HL)                  ; Restore the enclosing body cursor.
        INC HL
        LD D,(HL)
        LD (SCPBODY),DE
        XOR A
        RET

; Record the procedure that owns one reusable compiler slot.
SCOWNSET:
        LD (SCMSLOT),A             ; Preserve the slot while addressing the map.
        LD B,A                     ; Keep it while selecting the current owner.
        LD L,A                     ; Widen the slot index to a word.
        LD H,0
        LD DE,SCLOCOWN             ; One owner byte belongs to each slot.
        ADD HL,DE
        LD A,(SCCURPR)             ; FF marks a package-level local scope.
        LD (HL),A                  ; Active binding lookup reads this owner.
        CP 0FFH
        RET Z                       ; Package locals remain in static storage.
        LD A,(SCCURPR)             ; The procedure owns the new slot.
        LD (SCTMPPR),A             ; SCPREC uses the selected descriptor index.
        CALL SCPREC
        LD DE,SCOWNOF              ; The owned mask follows the formal fields.
        ADD HL,DE
        LD (SCMTADR),HL            ; Keep the mask base while selecting its byte.
        LD A,B                     ; Restore the newly allocated slot number.
        LD C,A                     ; Retain the slot while dividing by eight.
        SRL A                      ; Eight slots share one ownership byte.
        SRL A
        SRL A
        LD L,A
        LD H,0
        LD DE,(SCMTADR)
        ADD HL,DE                  ; Address the mask byte for this slot.
        LD A,C                     ; SCBITSET consumes the original slot index.
        JP SCBITSET                ; Set its bit in the descriptor mask.

; Mark a slot captured by the current procedure when its owner is outer.
SCCAPSET:
        LD (SCMSLOT),A             ; Keep the matching slot across owner lookup.
        LD L,A                     ; Locate the owner byte for this slot.
        LD H,0
        LD DE,SCLOCOWN
        ADD HL,DE
        LD B,(HL)                  ; B is the procedure that owns the slot.
        LD A,(SCCURPR)             ; Package-level references never capture.
        CP 0FFH
        RET Z
        CP B                       ; A slot owned by this procedure is local.
        RET Z
        LD A,(SCMSLOT)             ; An outer reference keeps its storage live.
        CALL SCEVSET
        LD A,B                     ; Remember the procedure that owns the cell.
        LD (SCCAPOWN),A
        LD A,(SCCURPR)             ; Preserve the active procedure across mask writes.
        LD (SCORIGPR),A
        LD A,(SCTMPPR)             ; Preserve the descriptor currently being finished.
        LD (SCORIGTM),A
        LD A,(SCMSLOT)              ; Pass the captured slot to the mask writer.
        CALL SCMSKSET               ; The current procedure needs the capture bit.
        LD A,(SCBDEP)              ; Walk through every intermediate procedure.
        LD (SCCHAINN),A
SCCAPCHN:
        LD A,(SCCHAINN)            ; The frame index is one below the current depth.
        OR A
        JR Z,SCCAPRST             ; A malformed chain still restores compiler state.
        DEC A
        LD (SCCHAINN),A
        LD L,A                     ; Widen the frame index before multiplying by nine.
        LD H,0
        LD D,H
        LD E,L
        ADD HL,HL                  ; Two times the frame index.
        ADD HL,HL                  ; Four times the frame index.
        ADD HL,HL                  ; Eight times the frame index.
        ADD HL,DE                  ; Complete the nine-byte frame offset.
        LD DE,SCBFRAME             ; Locate the saved enclosing procedure field.
        ADD HL,DE
        INC HL
        INC HL                     ; The saved owner is the third frame byte.
        LD A,(HL)
        LD B,A                     ; Compare the parent with the cell owner.
        LD A,(SCCAPOWN)
        CP B
        JR Z,SCCAPRST             ; The owner already owns the shared cell.
        LD A,B
        LD (SCCURPR),A             ; Select this intermediate descriptor.
        LD A,(SCMSLOT)             ; Every enclosing mask names the same cell slot.
        CALL SCMSKSET              ; Preserve the cell through this procedure too.
        JR SCCAPCHN              ; Continue toward the procedure that owns it.
SCCAPRST:
        LD A,(SCORIGPR)            ; Restore the active compiler procedure.
        LD (SCCURPR),A
        LD A,(SCORIGTM)            ; Restore the descriptor being finalized.
        LD (SCTMPPR),A
        RET

; Mark one compiler slot as captured so a later sibling cannot reuse its cell.
SCEVSET:
        LD L,A                     ; Widen the zero-based slot index.
        LD H,0
        LD DE,SCLOCEV              ; One byte records the lifetime of each slot.
        ADD HL,DE
        LD A,1
        LD (HL),A                  ; A nonzero flag keeps this slot allocated.
        RET

; Set one bit in the current procedure's 128-slot capture mask.
SCMSKSET:
        LD (SCMSLOT),A             ; Preserve the slot through record arithmetic.
        LD A,(SCCURPR)             ; SCPREC addresses the current descriptor record.
        LD (SCMPR),A
        LD (SCTMPPR),A             ; The record helper uses the same descriptor index.
        CALL SCPREC
        LD DE,SCCAPOF              ; Skip the body, arity, formals and owner mask.
        ADD HL,DE
        LD (SCMTADR),HL            ; Save the start of the capture mask.
        LD A,(SCMSLOT)             ; Divide the slot by eight for its mask byte.
        LD C,A
        SRL A
        SRL A
        SRL A
        LD L,A
        LD H,0
        LD DE,(SCMTADR)
        ADD HL,DE
        LD (SCMTADR),HL            ; HL now names the selected mask byte.
        LD A,C                     ; The low three bits select a bit in that byte.
        JP SCBITSET

; Set one bit in the mask whose base address is in HL.
SCBITSET:
        LD (SCMSLOT),A             ; Preserve the slot through mask arithmetic.
        LD (SCMTADR),HL            ; Save the selected mask's first byte.
        LD A,(SCMSLOT)             ; The low three bits select a bit in that byte.
        AND 7
        LD B,A
        LD A,B
        OR A
        JR Z,SCMSK0
        LD A,1
SCMSKSH:
        ADD A,A
        DJNZ SCMSKSH
        JR SCMSKBIT
SCMSK0:
        LD A,1
SCMSKBIT:
        LD C,A                     ; Preserve the one-bit mask across the read.
        LD HL,(SCMTADR)
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Emit a descriptor load, fresh-closure allocation and JP over the body.
; The descriptor pointer is a kind-two fixup filled after slot layout closes.
SCPREFX:
        LD A,21H                   ; LD HL,nn loads the immutable descriptor address.
        CALL SCBYTE                ; Append the load opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,(SCPC)               ; The following word is the descriptor fixup.
        LD A,2                     ; Fixup kind two selects the procedure table.
        LD (SCFKIND),A             ; Keep the kind with this patch record.
        LD A,(SCTMPPR)             ; The slot byte carries the descriptor index.
        LD (SCFSLOT),A             ; Publication resolves it after SCFIN.
        CALL SCFIX                 ; Record the absolute descriptor patch site.
        RET C                      ; Preserve a full fixup table.
        XOR A                      ; The descriptor address is unknown for now.
        CALL SCBYTE                ; Append its low placeholder byte.
        RET C                      ; Preserve staged-output exhaustion.
        CALL SCBYTE                ; Append its high placeholder byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,SRTMAKE               ; Runtime allocates a fresh closure object.
        CALL SCCALL                ; The returned value carries tag two.
        RET C                      ; Preserve staged-output exhaustion.
        CALL SCJP                  ; Jump over the body during closure creation.
        LD (SCSKIP),HL             ; Save the jump-over patch for SCPFIN.
        RET                        ; SCPC now points at the procedure body.

; Reserve and clear one procedure metadata record.
SCPNEW:
        LD A,(SCPCOUNT)            ; The metadata overlay has room for 21 records.
        CP 21                      ; Keep the table below the reader string area.
        JP NC,SCCAP                ; Reject another procedure before writing memory.
        LD B,A                     ; Return the old count as the descriptor index.
        INC A                      ; Publish the additional descriptor.
        LD (SCPCOUNT),A            ; The index is stable for all later fixups.
        LD A,B                     ; Keep the descriptor index for the caller.
        LD (SCTMPPR),A             ; SCPREC uses this state to find its record.
        CALL SCPREC                ; HL points at the twelve-byte metadata record.
        LD B,SCPRSZ                ; Clear body, arity, formals and ownership masks.
        XOR A                      ; A zero record has no body or formal slots.
SCPNEWLP:
        LD (HL),A                  ; Clear one metadata byte.
        INC HL                     ; Advance to the next field.
        DJNZ SCPNEWLP              ; Clear the complete fixed-size record.
        LD A,(SCTMPPR)             ; Return the descriptor index to SCLAMBF.
        OR A                       ; Clear carry without changing the index byte.
        RET                        ; The caller opens the new local scope.

; HL = metadata record for SCTMPPR.
SCPREC:
        LD A,(SCTMPPR)             ; Widen the descriptor index to a word.
        LD L,A                     ; The high byte is zero for the fixed table.
        LD H,0                     ; Each record carries two 128-bit masks.
        LD D,H                     ; Keep the original index for the final add.
        LD E,L
        ADD HL,HL                  ; Two times the index.
        ADD HL,HL                  ; Four times the index.
        PUSH HL                    ; Keep four times the index.
        ADD HL,HL                  ; Eight times the index.
        PUSH HL                    ; Keep eight times the index.
        ADD HL,HL                  ; Sixteen times the index.
        ADD HL,HL                  ; Thirty-two times the index.
        POP DE                     ; Recover eight times the index.
        ADD HL,DE                  ; Forty times the index.
        POP DE                     ; Recover four times the index.
        ADD HL,DE                  ; Complete the forty-four-byte offset.
        LD DE,SCPMETA              ; Add the metadata overlay base address.
        ADD HL,DE                  ; Return the record address in HL.
        RET                        ; The caller selects the field offset.

; Save the formal slot number in the current descriptor and advance its arity.
SCPARAM:
        PUSH AF                    ; Preserve the slot number returned by SCNSLOT.
        CALL SCPREC                ; Locate the current descriptor metadata.
        INC HL                     ; Skip the body address low byte.
        INC HL                     ; Skip the body address high byte.
        LD A,(HL)                  ; Read the current formal count.
        CP 4                       ; Four fixed arguments keep descriptors compact.
        JR NC,SCPERR               ; Reject a fifth formal before table overflow.
        LD E,A                     ; E is the formal index within the record.
        INC A                      ; Publish the new arity.
        LD (HL),A                  ; The runtime uses this count during dispatch.
        LD A,E                     ; Reconstruct the slot field offset four plus index.
        INC HL                     ; Move to the capture mask at offset three.
        INC HL                     ; Move to the first formal slot at offset four.
        LD B,A                     ; The old arity is the number of slots to skip.
        LD A,B                     ; Keep the loop count in the DJNZ register.
        OR A                       ; Zero formals select the first slot directly.
        JR Z,SCPARMAT              ; Avoid a wrapped DJNZ count for arity zero.
SCPARMSK:
        INC HL                     ; Skip the low byte of one recorded formal.
        INC HL                     ; Skip its reserved high byte as well.
        DJNZ SCPARMSK              ; Stop at the slot for the new formal.
SCPARMAT:
        POP AF                     ; Recover the compiler-local slot number.
        LD (HL),A                  ; Runtime publication resolves its address later.
        INC HL                     ; The descriptor keeps a fixed two-byte slot field.
        XOR A                      ; The current compiler slot range fits in one byte.
        LD (HL),A                  ; Keep the high byte reserved and deterministic.
        OR A                       ; Carry clear reports a complete formal record.
        RET                        ; The lambda parser reads the next name.
SCPERR:
        POP AF                     ; Keep the compiler stack balanced on rejection.
        SCF                        ; The procedure arity is a checked capacity.
        RET                        ; The lambda error path restores its scope.

; Save the body address and patch the jump over the just-emitted procedure.
SCPFIN:
        LD HL,(SCPBODY)            ; Recover the staged body start recorded above.
        CALL SCABS                 ; Convert the body pointer to a COM address.
        LD (SCPBODY),HL            ; Keep it for descriptor serialization.
        CALL SCPREC                ; Locate the descriptor metadata again.
        LD DE,(SCPBODY)            ; Write the generated body address at offset zero.
        LD (HL),E                  ; Store the low body byte.
        INC HL                     ; Advance to the high body byte.
        LD (HL),D                  ; Complete the body address field.
        LD HL,(SCPC)               ; The skip target follows the body return byte.
        CALL SCABS                 ; Convert the target to a COM address.
        EX DE,HL                   ; SCPATCH takes the patch address in HL.
        LD HL,(SCSKIP)             ; Recover the jump-over patch location.
        JP SCPATCH                 ; Patch the closure creation jump.

; Compile set!, preserving the selected slot while the value expression runs.
SCSETF:
        CALL RNEXT                 ; Read the target binding name.
        RET C                      ; Preserve source failure.
        CP 5                       ; A mutation target must be an identifier.
        JP NZ,SCDESTSY              ; Reject a literal or nested list target.
        LD (SCID),HL               ; Preserve the target identity across lookup.
        CALL SCDEST                 ; Select the local or global storage slot.
        RET C                      ; An unknown or full binding table is terminal.
        LD A,(SCSLOT)              ; Save the selected slot while compiling the value.
        PUSH AF                    ; A nested set! must not replace this slot.
        LD A,(SCDESTK)              ; Preserve the local/global destination kind too.
        PUSH AF                    ; The value expression may recurse through set!.
        XOR A                      ; The new value is evaluated before the store.
        LD (SCTCTX),A              ; A mutation target never receives tail position.
        CALL SCEXPR                ; Compile the new value.
        JR C,SCSETERR              ; Balance the destination frame on failure.
        POP AF                     ; Recover the selected destination kind.
        LD (SCDESTK),A             ; Restore local or global storage selection.
        POP AF                     ; Recover the selected destination slot.
        LD (SCSLOT),A              ; Restore the slot after nested compilation.
        LD L,A                     ; SCSTORE takes the slot number in L.
        LD A,1
        LD (SCMUT),A           ; Select a checked mutation store.
        LD A,(SCDESTK)             ; Recover local or global destination kind.
        CALL SCSTORE               ; Emit the checked mutation update.
        JR C,SCMUTERR          ; Balance the mode before reporting failure.
        XOR A
        LD (SCMUT),A           ; Definitions resume the initializing path.
        JP SCEXPECT                ; Require exactly one closing parenthesis.
SCMUTERR:
        XOR A
        LD (SCMUT),A           ; The compiler is terminating after this error.
        SCF
        RET C                      ; Preserve output or fixup exhaustion.
SCSETERR:
        POP AF                     ; Discard the saved destination kind.
        POP AF                     ; Discard the saved destination slot.
        SCF                       ; Preserve the nested expression diagnostic.
        RET

; Compile zero? as a checked unary runtime operation.
SCZEROF:
        XOR A                      ; The predicate operand is consumed by the helper.
        LD (SCTCTX),A              ; It cannot transfer the caller's continuation.
        CALL SCEXPR                ; Compile the one predicate operand.
        RET C                      ; Preserve nested syntax and capacity errors.
        CALL SCEXPECT              ; Reject a missing or extra operand.
        RET C                      ; Preserve the closing delimiter diagnostic.
        LD HL,SRTZERO              ; The runtime returns a canonical boolean.
        JP SCCALL                  ; Emit the helper call after the operand code.

; Resolve a mutation target without emitting a load.  SCDESTK records its kind.
SCDEST:
        CALL SCLOCF                ; Prefer an active local binding.
        JR C,SCDESTL               ; Carry identifies the local path.
        CALL SCGGET                ; Global references allocate their slot here.
        RET C                      ; Preserve the global-capacity diagnostic.
        LD (SCSLOT),A              ; Store the selected global slot.
        XOR A                      ; Kind zero denotes a package-global slot.
        LD (SCDESTK),A             ; Remember it for the later SCSTORE.
        OR A                       ; Clear carry after a complete lookup.
        RET                        ; Return with the slot in SCSLOT.
SCDESTL:
        LD (SCSLOT),A              ; Store the selected local slot.
        LD A,1                     ; Kind one denotes a local slot.
        LD (SCDESTK),A             ; Remember it for the later SCSTORE.
        OR A                       ; Clear carry without changing the slot byte.
        RET                        ; Return to SCSETF before its value expression.
SCDESTSY:
        LD HL,SCDESTT
        LD (SCERRPTR),HL
        JP SCSYN
