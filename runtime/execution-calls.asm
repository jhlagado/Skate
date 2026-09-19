;=============================================================================
;  Skate native call and activation services
;=============================================================================

; Dispatch a staged tail call, reusing the activation or returning a primitive.
; Input DE/BC describe the new rooted packet; this routine never allocates.
RTTAIL:
        CALL RTSTKCHK          ; Tail dispatch still needs bounded helper headroom.
        CALL RTCHKPK           ; Validate the complete staged packet before mutation.
        CALL RTDISPCH           ; Resolve either a closure descriptor or primitive wrapper.
        PUSH IX                    ; A tail transfer requires a live activation to reuse.
        POP HL                     ; Inspect the current record address.
        LD A,H                     ; IX zero is reserved for startup, not a procedure frame.
        OR L                       ; A nonzero activation address is mandatory here.
        JP Z,RTINVERR           ; Reject before changing roots, stack or activation state.
        PUSH IX                    ; Read the current record without changing IX.
        POP HL                     ; HL now holds the activation-record address.
        LD DE,RTRECSZ      ; The current record must be the last live record.
        ADD HL,DE                  ; Compute the expected next activation address.
        JP C,RTINVERR           ; A wrapped record pointer indicates corrupted state.
        LD DE,(RTACTCUR)            ; Compare the stack cursor with that expected address.
        OR A                       ; Clear carry before checking the live-record invariant.
        SBC HL,DE                  ; Any difference means IX is not the current top frame.
        JP NZ,RTINVERR          ; Reject before copying or dropping any root slots.
        LD A,(RTISPRIM)            ; Primitive tail calls return through this current activation.
        OR A                       ; Closure tails replace the owned packet in place.
        JP NZ,RTTAILPR             ; A primitive needs neither activation nor packet replacement.
        LD L,(IX+2)                ; Load the packet base owned by this activation.
        LD H,(IX+3)                ; This is the destination of the overlap-safe copy.
        LD (RTPKDST),HL             ; Keep the old packet base outside the record.
        LD HL,(RTPACKET)           ; The staged packet is above the live activation packet.
        LD (RTPKSRC),HL              ; Save its base before checking relative order.
        LD DE,(RTPKDST)             ; Load the activation's current packet base.
        OR A                       ; Clear carry before the source/destination comparison.
        SBC HL,DE                  ; LDIR is safe because the destination cannot be higher.
        JP C,RTINVERR           ; Reject an invalid ordering before writing the destination.
        LD HL,(RTPKDST)             ; The retained packet base must still be a root address.
        LD DE,(RTROOTB)         ; No activation may point below the root arena.
        OR A                       ; Clear carry before the unsigned lower-bound comparison.
        SBC HL,DE                  ; A borrow means the activation record is corrupt.
        JP C,RTINVERR           ; Refuse to copy into runtime or program memory.
        LD HL,(RTPKDST)             ; The destination packet must still fit in the root region.
        LD DE,(RTPKLEN)              ; Use the already checked complete packet length.
        ADD HL,DE                  ; Compute destination end before any copy takes place.
        JP C,RTINVERR           ; A wrapped destination would corrupt unrelated memory.
        LD (RTPKXEND),HL          ; Retain the checked endpoint for the root cursor update.
        LD DE,(RTROOTX)          ; Bound the destination by the configured root limit.
        OR A                       ; Compare destination end with the exclusive root end.
        SBC HL,DE                  ; Carry or equality means the destination fits.
        JP C,RTTAILOK        ; The destination ends below the root limit.
        JP Z,RTTAILOK        ; Ending exactly at the limit is valid.
        JP RTCAPERR              ; Reject before overwriting the current packet.
RTTAILOK:
        LD HL,(RTPKSRC)              ; Copy from the higher staged packet toward the lower base.
        LD DE,(RTPKDST)             ; Forward copying is overlap-safe for this address order.
        LD BC,(RTPKLEN)              ; The length includes environment, callee and all arguments.
        LDIR                       ; The active packet now contains the staged tail-call values.
        LD HL,(RTPKXEND)          ; Drop old temporaries and the staged packet from the root stack.
        PUSH HL                    ; Update both IY and its collector-visible mirror.
        POP IY                     ; The new current packet ends at the checked destination end.
        LD (RTROOTP),HL              ; Future collection scans no discarded tail-call slots.
        LD BC,(RTPKARGC)             ; Publish the new arity in the reused activation record.
        LD (IX+8),C                ; The record stores argument count as a little-endian word.
        LD (IX+9),B                ; The entry helper will verify this reused packet's count.
        LD L,(IX+6)                ; Recover the original entry stack address.
        LD H,(IX+7)                ; It still points at the one caller return word.
        LD A,1                     ; The next procedure entry reuses this record exactly once.
        LD (RTREUSE),A             ; Publish reuse only after packet validation and copy succeed.
        LD SP,HL                   ; Discard staging/helper stack use but preserve the continuation.
        LD DE,(RTPKDST)             ; The target receives the copied packet at its owned base.
        LD BC,(RTPKARGC)             ; Pass the staged packet's validated arity to RTENTER.
        LD HL,(RTTARGET)           ; Tail dispatch uses the resolved closure descriptor entry.
        JP (HL)                    ; No CALL is made, so continuation depth stays constant.
RTTAILPR:
        LD A,1                     ; Mark the next primitive result as a tail return.
        LD (RTREUSE),A             ; RTPRDONE consumes this before entering RTRETURN.
        LD DE,(RTPACKET)           ; Primitive wrappers read arguments from the staged packet.
        LD BC,(RTPKARGC)           ; Preserve the validated arity for the pair services.
        LD HL,(RTTARGET)           ; RTDISPCH selected the primitive's checked wrapper address.
        JP (HL)                    ; The wrapper returns through RTRETURN instead of RET.

; Validate the common entry, push one activation, or consume a tail reuse flag.
; HL is the target's immutable descriptor; DE/BC are packet base and arity.
RTENTER:
        CALL RTSTKCHK          ; The entry check accounts for its own helper return word.
        LD (RTPASSED),HL           ; Direct entries supply their descriptor before any helper call.
        CALL RTCHKPK           ; Root and stack bounds are proved before activation writes.
        CALL RTRESLV             ; Direct and indirect paths enforce the same closure contract.
        LD HL,(RTPASSED)           ; Compare the entered descriptor with the packet's closure.
        LD DE,(RTDESCPT)             ; RESOLVE retained the descriptor reached through the closure.
        OR A                       ; Clear carry before testing descriptor identity.
        SBC HL,DE                  ; A mismatch means the entry does not match its callee value.
        JP NZ,RTINVERR          ; Reject a stale or forged direct entry before frame publication.
        LD A,(RTREUSE)             ; Tail dispatch sets this one-shot flag after staging its packet.
        OR A                       ; Zero requests a fresh activation record.
        JP NZ,RTTAILEN        ; A nonzero flag must match the existing top activation.
        LD HL,0                    ; Copy SP into HL without changing its value.
        ADD HL,SP                  ; RTENTER was called once by the procedure entry stub.
        LD DE,2                    ; Its return word sits above the original caller continuation.
        ADD HL,DE                  ; HL is the actual native entry SP to retain in the record.
        JP C,RTCAPERR            ; A wrapped SP is outside every configured stack region.
        LD (RTUSRSP),HL          ; Save it before any further helper can push a return address.
        PUSH IX                    ; Determine whether the activation stack is internally consistent.
        POP HL                     ; HL is the previous activation record or zero at startup.
        LD A,H                     ; The zero case must still point at the configured arena base.
        OR L                       ; Test whether this is the first activation.
        JP NZ,RTNESTED       ; Nested records must follow their previous record exactly.
        LD HL,(RTACTCUR)            ; Read the next activation address.
        LD DE,(RTARBASE)           ; A zero IX permits only the first arena record.
        OR A                       ; Clear carry before checking that invariant.
        SBC HL,DE                  ; The activation cursor must equal its base.
        JP NZ,RTINVERR          ; Refuse to publish a disconnected activation chain.
        JP RTRECCHK            ; The first record uses the same capacity check as nested calls.
RTNESTED:
        LD DE,RTRECSZ      ; Records are tightly stacked at ten-byte intervals.
        ADD HL,DE                  ; Compute the next address after the previous IX record.
        JP C,RTINVERR           ; A wrapped activation pointer cannot be trusted.
        LD DE,(RTACTCUR)            ; Compare the computed address with the current stack top.
        OR A                       ; Clear carry before testing the live-chain invariant.
        SBC HL,DE                  ; The addresses must match exactly.
        JP NZ,RTINVERR          ; Reject an activation gap before writing a new record.
RTRECCHK:
        LD HL,(RTACTCUR)            ; Reserve one ten-byte record without writing it yet.
        LD DE,RTRECSZ      ; Compute the exclusive end of the candidate record.
        ADD HL,DE                  ; Carry means the activation arena address wrapped.
        JP C,RTCAPERR            ; Fail before changing activation or root state.
        LD DE,(RTAREND)            ; Compare the new end with the configured arena end.
        OR A                       ; Clear carry for the unsigned capacity test.
        SBC HL,DE                  ; Carry or equality means the complete record fits.
        JP C,RTENTOK          ; Candidate record ends below the arena boundary.
        JP Z,RTENTOK          ; A record may end exactly at the exclusive boundary.
        JP RTCAPERR              ; No activation byte has changed on this failure path.
RTENTOK:
        CALL RTFRAME               ; Allocate and publish the parameter environment first.
        LD HL,(RTACTCUR)            ; Remember the record base before publishing the cursor.
        LD (RTACTNEW),HL          ; The completed record will become the new IX.
        PUSH IX                    ; Preserve the previous activation as a raw address.
        POP HL                     ; Retain it while IX is redirected to the new record.
        LD (RTACTPRV),HL             ; The previous activation is the first record field.
        LD HL,(RTACTNEW)          ; IX now addresses the candidate ten-byte record.
        PUSH HL                    ; Copy that address into the index register.
        POP IX                     ; No helper call occurs while the record is incomplete.
        LD HL,(RTACTPRV)             ; Store the previous activation as a little-endian word.
        LD A,L                     ; IX-relative stores use A on the documented Z80 surface.
        LD (IX+0),A                ; Record +0 is the previous activation low byte.
        LD A,H                     ; Recover the high byte for the next field.
        LD (IX+1),A                ; Complete the previous-activation link.
        LD HL,(RTPACKET)           ; The packet base is retained for tail reuse and return.
        LD A,L                     ; Write its low address byte.
        LD (IX+2),A                ; Record +2 is the active root packet base.
        LD A,H                     ; Recover its high address byte.
        LD (IX+3),A                ; Complete the packet-base field.
        LD A,L                     ; The restored caller root top is the same packet base.
        LD (IX+4),A                ; Save its low byte as the post-return root cursor.
        LD A,H                     ; Recover its high byte.
        LD (IX+5),A                ; Complete the root-restore field.
        LD HL,(RTUSRSP)          ; This was saved before any nested helper could run.
        LD A,L                     ; Store the low byte of native entry SP.
        LD (IX+6),A                ; Record +6 points at the original caller return word.
        LD A,H                     ; Recover the high byte of that stack address.
        LD (IX+7),A                ; Complete the native-entry-SP field.
        LD HL,(RTPKARGC)             ; Resolve already proved this count matches the descriptor.
        LD A,L                     ; Store the little-endian arity.
        LD (IX+8),A                ; Record +8 is the argument-count low byte.
        LD A,H                     ; Recover its high byte.
        LD (IX+9),A                ; Complete the record before advancing the activation cursor.
        LD HL,(RTACTCUR)            ; Advance the activation stack by one full record.
        LD DE,RTRECSZ      ; The next unused record follows immediately.
        ADD HL,DE                  ; The prior room check proved this addition fits.
        LD (RTACTCUR),HL            ; Publish the completed record extent.
        LD DE,(RTACTHI)           ; Compare with the greatest activation extent so far.
        OR A                       ; Clear carry before measuring the high-water difference.
        SBC HL,DE                  ; A positive difference records a new maximum.
        JP C,RTACTMAX       ; Keep the prior maximum when nesting did not grow.
        JP Z,RTACTMAX       ; Equal depth leaves the existing high-water mark intact.
        LD HL,(RTACTCUR)            ; Reload the new activation-stack extent after comparison.
        LD (RTACTHI),HL           ; Record the highest used activation address.
RTACTMAX:
        LD HL,(RTCHKTP)         ; Publish the validated root extent after all capacity checks.
        LD (RTROOTP),HL              ; The collector's root descriptor follows this address.
        LD DE,(RTROOTMX)         ; Compare this call's packet extent with prior use.
        OR A                       ; Clear carry before the high-water comparison.
        SBC HL,DE                  ; A positive difference means the root stack grew.
        JP C,RTROOTHI          ; Keep the prior root maximum when this packet is smaller.
        JP Z,RTROOTHI          ; Equal root extent leaves the maximum unchanged.
        LD HL,(RTROOTP)              ; Reload the new validated top after the comparison.
        LD (RTROOTMX),HL         ; Publish the root high-water address.
RTROOTHI:
        XOR A                      ; Clear stale tail-reuse state on every normal entry.
        LD (RTREUSE),A             ; A subsequent ordinary call must push another record.
        RET                        ; Return to the procedure stub with original SP restored.

; Reuse the current record after a proper tail transfer.
RTTAILEN:
        LD HL,0                    ; Compute the original return-word address from helper SP.
        ADD HL,SP                  ; No user continuation was pushed by the tail helper.
        LD DE,2                    ; RTENTER itself contributed exactly one helper return word.
        ADD HL,DE                  ; The target must observe the same entry SP as its predecessor.
        JP C,RTINVERR           ; A wrapped continuation cannot be reused.
        PUSH IX                    ; IX is the record retained by the tail helper.
        POP HL                     ; Compare its address with the saved entry record.
        LD A,H                     ; A zero record cannot be reused.
        OR L                       ; Test both bytes of IX.
        JP Z,RTINVERR           ; The tail helper must have a current activation.
        LD DE,RTRECSZ      ; The activation cursor must still follow this record.
        ADD HL,DE                  ; Compute the expected next activation address.
        JP C,RTINVERR           ; A wrapped activation pointer is invalid.
        LD DE,(RTACTCUR)            ; Compare against the live activation high-water cursor.
        OR A                       ; Clear carry before testing stack ownership.
        SBC HL,DE                  ; The tail target must reuse the top record, not an older one.
        JP NZ,RTINVERR          ; Reject before changing the one-shot reuse flag.
        LD HL,0                    ; Recompute the target entry SP from the current helper frame.
        ADD HL,SP                  ; SP still points at RTENTER's internal return address.
        LD DE,2                    ; Its word is immediately below the user's continuation.
        ADD HL,DE                  ; HL must equal the record's original entry SP.
        LD E,(IX+6)                ; Read that saved SP from the current activation record.
        LD D,(IX+7)                ; DE now contains the original return-word address.
        OR A                       ; Clear carry before the exact SP equality check.
        SBC HL,DE                  ; A zero result confirms the old continuation is untouched.
        JP NZ,RTINVERR          ; Refuse reuse if the native continuation changed.
        LD C,(IX+8)                ; The tail helper wrote the new argument count into the record.
        LD B,(IX+9)                ; Compare that count with the validated staged packet.
        LD HL,(RTPKARGC)             ; Resolve retained the caller's requested argument count.
        OR A                       ; Clear carry before exact arity equality comparison.
        SBC HL,BC                  ; The activation and packet must describe the same call.
        JP NZ,RTINVERR          ; Refuse reuse if either count changed during dispatch.
        LD DE,(RTPACKET)           ; The staged packet has replaced the old packet in place.
        LD L,(IX+2)                ; Load the activation's retained packet base.
        LD H,(IX+3)                ; The copied packet must begin at exactly that address.
        OR A                       ; Clear carry before comparing packet bases.
        SBC HL,DE                  ; A zero result proves tail staging used the owned packet.
        JP NZ,RTINVERR          ; Do not enter with mismatched root and activation ownership.
        XOR A                      ; Clear the one-shot flag before target body or allocation code.
        LD (RTREUSE),A             ; This activation has now been consumed by its new procedure.
        CALL RTFRAME               ; Build the replacement frame before entering its body.
        RET                        ; The procedure body starts with the original return word at SP.

; Store a procedure result in its packet, pop the activation, and RET once.
; Input A:HL is the Scheme value returned by the current native procedure.
RTRETURN:
        LD (RTRESVAL),HL           ; Preserve the value while the register pairs restore state.
        LD (RTRESTAG),A            ; The result tag is stored beside its payload.
        PUSH IX                    ; Reject a return without a current procedure activation.
        POP HL                     ; Inspect IX without changing the record pointer.
        LD A,H                     ; IX=0 is valid only before the first call.
        OR L                       ; A return always requires a nonzero activation record.
        JP Z,RTINVERR           ; Leave roots and activation state untouched on this error.
        LD E,(IX+4)                ; Load the caller's root top to restore.
        LD D,(IX+5)                ; It is the current call packet's first value slot.
        LD H,D                     ; HL becomes that root-slot address.
        LD L,E                     ; The activation fields are little-endian raw pointers.
        LD A,(RTRESTAG)            ; Write the result before dropping callee roots.
        LD (HL),A                  ; The tag occupies the first byte of a root Slot.
        INC HL                     ; Move to its payload low byte.
        LD DE,(RTRESVAL)           ; Reload the preserved two-byte payload.
        LD (HL),E                  ; Store payload low byte.
        INC HL                     ; Advance to payload high byte.
        LD (HL),D                  ; Store payload high byte.
        INC HL                     ; Advance to the collector padding byte.
        LD (HL),0                  ; Every published root Slot has zero padding.
        INC HL                     ; IY points to the first unused slot after this result.
        PUSH HL                    ; Set the architectural root cursor to packet base + 4.
        POP IY                     ; The caller can now use the returned value without a safepoint gap.
        LD (RTROOTP),HL              ; Keep the collector-visible root extent in step with IY.
        CALL RTROOTS               ; Reduce the GC descriptor to the restored caller roots.
        LD L,(IX+6)                ; Save the original caller return-word address.
        LD H,(IX+7)                ; The stack may contain helper scratch below this point.
        LD (RTNATSP),HL            ; Retain it before restoring IX.
        LD L,(IX+0)                ; Save the previous activation address.
        LD H,(IX+1)                ; This is the IX value to restore after the return.
        LD (RTACTPRV),HL             ; Keep it while the current record is still addressable.
        PUSH IX                    ; The current record is now complete and may be popped.
        POP HL                     ; HL is its base address.
        LD (RTACTCUR),HL            ; Reuse that record slot on the next non-tail call.
        LD HL,(RTACTPRV)             ; Restore the caller's current activation record.
        PUSH HL                    ; Transfer the saved pointer into IX.
        POP IX                     ; IX now names the previous frame or zero at startup.
        LD HL,(RTNATSP)            ; Restore SP to the original user-call return word.
        LD SP,HL                   ; All helper and tail-staging words are discarded.
        LD A,(RTRESTAG)            ; Return the same logical tag that was rooted above.
        LD HL,(RTRESVAL)           ; Return the same payload in the public A:HL convention.
        RET                        ; Consume exactly one caller continuation.

; Check the complete rooted packet supplied in DE/BC without changing roots.
; Success saves packet base, argument count, byte length and current IY in scratch.
RTCHKPK:
        LD (RTPACKET),DE           ; Keep the packet base while its extent is checked.
        LD (RTPKARGC),BC             ; Preserve the argument count for descriptor validation.
        PUSH IY                    ; Capture the current root top without modifying it.
        POP HL                     ; HL is the architectural root extent supplied by the caller.
        LD (RTCHKTP),HL         ; Retain it as scratch until activation checks also pass.
        LD DE,(RTROOTX)          ; IY may equal, but must not exceed, the exclusive root end.
        OR A                       ; Clear carry before unsigned comparison.
        SBC HL,DE                  ; A positive result is an invalid root cursor.
        JP C,RTCPTOP           ; A cursor below the limit is valid.
        JP Z,RTCPTOP           ; A cursor at the limit is valid for an empty suffix.
        JP RTCAPERR              ; Reject before activation/root state is committed.
RTCPTOP:
        LD HL,(RTPKARGC)             ; Compute the number of four-byte packet slots.
        LD DE,2                    ; Environment and callee occupy the first two slots.
        ADD HL,DE                  ; Add the argument slots to those fixed headers.
        JP C,RTCAPERR            ; Reject slot-count wrap.
        ADD HL,HL                  ; Convert slots to a two-byte extent.
        JP C,RTCAPERR            ; Reject byte-length overflow.
        ADD HL,HL                  ; Convert to four-byte root Slots.
        JP C,RTCAPERR            ; Reject a wrapped packet length.
        LD (RTPKLEN),HL              ; Retain the complete staged packet size.
        LD HL,(RTPACKET)           ; Check packet base against the root-stack base.
        LD DE,(RTROOTB)         ; A packet may not point into code or runtime state.
        OR A                       ; Clear carry before the unsigned comparison.
        SBC HL,DE                  ; A borrow means the packet begins below ROOTBASE.
        JP C,RTCAPERR            ; Reject an invalid base before reading any slot.
        LD A,L                     ; Every root slot begins on a four-byte boundary.
        AND 3                      ; The configured root base is already aligned.
        JP NZ,RTCAPERR           ; Reject a forged packet base before any slot access.
        LD HL,(RTPACKET)           ; Compute the packet's exclusive endpoint.
        LD DE,(RTPKLEN)              ; The length was checked before this addition.
        ADD HL,DE                  ; HL is packet base plus every packet slot.
        JP C,RTCAPERR            ; Reject an address wrap before slot access.
        LD (RTPKEND),HL              ; Preserve the endpoint for both extent checks.
        LD DE,(RTROOTX)          ; The packet must fit completely within configured roots.
        OR A                       ; Compare its end against the exclusive limit.
        SBC HL,DE                  ; Carry or equality means the packet fits.
        JP C,RTENDOK               ; Packet end is below ROOTEND.
        JP Z,RTENDOK               ; Packet end may equal ROOTEND exactly.
        JP RTCAPERR              ; Reject before the callee slot or activation is changed.
RTENDOK:
        LD HL,(RTPKEND)              ; The staged packet must also be inside the active root extent.
        LD DE,(RTCHKTP)         ; IY is the first unused active root slot.
        OR A                       ; Clear carry before comparing the two endpoints.
        SBC HL,DE                  ; Carry or equality means the whole packet is rooted.
        JP C,RTPKROOT           ; The complete packet lies below IY.
        JP Z,RTPKROOT           ; Ending exactly at IY is the normal packet boundary.
        JP RTCAPERR              ; An unrooted callee or argument is never inspected.
RTPKROOT:
        LD HL,(RTPKARGC)             ; The packet has one environment, one callee and argc values.
        LD DE,2                    ; Add the two fixed header slots.
        ADD HL,DE                  ; RTPKLEN already proved this slot count cannot wrap.
        LD (RTVALCNT),HL           ; Retain the slot count while checking each tagged value.
        LD HL,(RTPACKET)           ; Start at the first tag byte in the validated packet.
RTVALCHK:
        LD A,(HL)                  ; Only three logical tags are valid in a value slot.
        OR A                       ; Tag zero is a scalar or private immediate.
        JP Z,RTVALPAD              ; Continue by checking the slot's reserved padding byte.
        CP 1                       ; Tag one denotes a reference value.
        JP Z,RTVALPAD              ; The callee subtype is checked separately by RTRESLV.
        CP 3                       ; Tag three denotes an exact integer or binary16 number.
        JP NZ,RTINVERR             ; Reject invalid tags before collection can scan this packet.
RTVALPAD:
        INC HL                     ; Skip payload low byte.
        INC HL                     ; Skip payload high byte.
        INC HL                     ; HL now addresses the root slot's padding byte.
        LD A,(HL)                  ; Padding is reserved and must remain zero.
        OR A                       ; Do not let malformed roots enter the collector.
        JP NZ,RTINVERR             ; A nonzero pad is an invariant failure.
        INC HL                     ; Advance to the next four-byte value slot.
        LD BC,(RTVALCNT)           ; Decrement the number of packet values still unchecked.
        DEC BC                     ; The current slot has passed tag and padding validation.
        LD (RTVALCNT),BC           ; Preserve the remaining count across the loop test.
        LD A,B                     ; Combine both bytes to detect the end of the packet.
        OR C                       ; A nonzero remainder means another slot follows.
        JP NZ,RTVALCHK               ; Inspect every environment, callee and argument slot.
        XOR A                      ; All packet slots are bounded, rooted and well formed.
        RET                        ; No durable cursor or activation state changed.

; Decode and validate packet callee into RTDESCPT and RTTARGET without allocation.
; Caller has checked packet extent and owns every value until dispatch completes.
RTRESLV:
        LD HL,(RTPACKET)           ; Start at the packet's first environment slot.
        LD DE,4                    ; The callee is the next four-byte tagged value.
        ADD HL,DE                  ; HL points at the callee tag byte.
        LD A,(HL)                  ; Only a reference-valued callee can be a closure.
        CP 1                       ; Logical tag one identifies all heap/table references.
        JP NZ,RTTYERR          ; Reject scalars, immediates and invalid tags as nonprocedures.
        INC HL                     ; Move to the closure reference's payload low byte.
        LD E,(HL)                  ; Preserve the low index byte.
        INC HL                     ; Move to the payload high byte.
        LD A,(HL)                  ; The high three bits select the reference subtype.
        AND 0E0H                   ; Retain only those subtype bits.
        CP 040H                    ; Subtype two is the heap closure representation.
        JP NZ,RTTYERR          ; Symbols, strings, pairs and environments are not procedures.
        LD A,(HL)                  ; Recover the index bits after checking the subtype.
        AND 01FH                   ; Closure indices occupy thirteen bits.
        LD D,A                     ; DE is now the untagged 13-bit closure index.
        LD A,D                     ; Both index bytes must not describe reserved cell zero.
        OR E                       ; Test whether the closure points at the reserved cell.
        JP Z,RTTYERR           ; Cell zero is not a language closure.
        LD (RTINDEX),DE            ; Save the index while checking it against HCOUNT.
        LD HL,(HCOUNT)             ; HCOUNT includes reserved cell zero.
        EX DE,HL                   ; HL=index, DE=physical cell count.
        OR A                       ; Clear carry before the unsigned bounds comparison.
        SBC HL,DE                  ; A valid closure index is strictly less than HCOUNT.
        JP NC,RTTYERR          ; Reject a forged reference before forming its address.
        LD HL,(RTINDEX)            ; Convert cell index to a four-byte arena offset.
        ADD HL,HL                  ; First doubling gives a two-byte offset.
        ADD HL,HL                  ; Second doubling gives a four-byte cell offset.
        LD DE,(RTHEAPB)         ; The checked runtime map supplies the arena base.
        ADD HL,DE                  ; HL now addresses the closure cell.
        JP C,RTINVERR           ; HINIT proved a valid cell extent cannot wrap.
        LD E,(HL)                  ; Word zero is the immutable procedure-descriptor address.
        INC HL                     ; Advance to descriptor high byte.
        LD D,(HL)                  ; DE holds the absolute descriptor address.
        LD (RTDESCPT),DE             ; Keep the descriptor for entry validation and dispatch.
        INC HL                     ; Advance to the closure's captured-environment link.
        INC HL                     ; The link word follows the descriptor address.
        LD A,(HL)                  ; Its high bits must identify a closure cell.
        AND 0E0H                   ; Ignore the captured environment's low index bits.
        CP 040H                    ; Physical tag two is reserved for closure links.
        JP NZ,RTINVERR          ; A malformed cell cannot safely supply an entry address.
        LD A,(HL)                  ; The high link byte also contains the closure's physical tag.
        AND 01FH                   ; Keep only the captured index's high five bits.
        LD D,A                     ; DE will contain the untagged thirteen-bit parent index.
        DEC HL                     ; Return to word one's low byte at closure cell +2.
        LD E,(HL)                  ; Read the captured environment's low index byte.
        LD (RTCAPENV),DE           ; Frame entry uses this index as the parent environment.
        LD A,D                     ; A zero index means the closure captures no environment.
        OR E                       ; Nonzero links must name an allocated heap cell.
        JP Z,RTENVOK              ; Zero has no HCOUNT comparison to perform.
        LD HL,(RTCAPENV)           ; Compare a captured environment with physical heap size.
        LD DE,(HCOUNT)             ; HCOUNT includes reserved cell zero.
        OR A                       ; Clear carry before the unsigned bounds comparison.
        SBC HL,DE                  ; Every captured index must be strictly below HCOUNT.
        JP NC,RTINVERR             ; Reject an out-of-range closure link before dispatch.
RTENVOK:
        LD HL,(RTDESCPT)             ; Descriptor bytes must fit wholly inside executable data.
        LD DE,(RTCODEB)         ; Begin by proving the descriptor is not below the code image.
        OR A                       ; Clear carry before the unsigned comparison.
        SBC HL,DE                  ; A borrow means the descriptor address is out of range.
        JP C,RTINVERR           ; Reject before reading its first byte.
        LD HL,(RTDESCPT)             ; Compute the exclusive end of the eight-byte descriptor.
        LD DE,8                    ; Entry, minimum arity, slots and rest policy are four words.
        ADD HL,DE                  ; HL is descriptor address plus its complete extent.
        JP C,RTINVERR           ; A wrapped descriptor would point outside the image.
        LD DE,(RTCODEE)          ; Descriptor end may equal the code-range end.
        OR A                       ; Compare the complete descriptor extent.
        SBC HL,DE                  ; Carry or equality means every descriptor byte fits.
        JP C,RTDSCFIT           ; Descriptor ends below the code limit.
        JP Z,RTDSCFIT           ; Descriptor ends exactly at the code limit.
        JP RTINVERR             ; Reject before reading descriptor fields.
RTDSCFIT:
        LD HL,(RTDESCPT)             ; Read the native entry address from descriptor +0.
        LD E,(HL)                  ; The target address is stored little-endian.
        INC HL                     ; Advance to its high byte.
        LD D,(HL)                  ; DE now holds the entry address.
        LD (RTTARGET),DE           ; Preserve it across arity and slot checks.
        LD HL,(RTTARGET)           ; A callable entry must also lie in the code interval.
        LD DE,(RTCODEB)         ; Compare entry with the first resident code byte.
        OR A                       ; Clear carry for the lower-bound check.
        SBC HL,DE                  ; A borrow means the descriptor points outside the program.
        JP C,RTINVERR           ; Reject before jumping through the target.
        LD HL,(RTTARGET)           ; Check the entry against the exclusive code end.
        LD DE,(RTCODEE)          ; The entry itself must not point at that end marker.
        OR A                       ; Clear carry before unsigned comparison.
        SBC HL,DE                  ; Carry means the entry is below the allowed end.
        JP NC,RTINVERR          ; Reject entries at or beyond the end of code.
        LD HL,(RTDESCPT)             ; Descriptor +2 contains the minimum arity.
        INC HL                     ; Skip entry-address low byte.
        INC HL                     ; Skip entry-address high byte.
        LD E,(HL)                  ; Read minimum-arity low byte.
        INC HL                     ; Advance to minimum-arity high byte.
        LD D,(HL)                  ; DE is the descriptor's lower arity bound.
        LD (RTMINAR),DE             ; Keep it for rest-list construction and slots.
        LD HL,(RTDESCPT)             ; Descriptor +6 contains the rest-argument policy.
        INC HL                     ; Skip entry-address low byte.
        INC HL                     ; Skip entry-address high byte.
        INC HL                     ; Skip minimum-arity low byte.
        INC HL                     ; Skip minimum-arity high byte.
        INC HL                     ; Skip slot-count low byte.
        INC HL                     ; Skip slot-count high byte.
        LD A,(HL)                  ; Only zero (fixed) or one (rest) is supported.
        OR A                       ; Zero selects the exact-arity path.
        JP Z,RTFIXAR
        CP 1                       ; Reject future policy bits until they are specified.
        JP NZ,RTINVERR
        LD (RTRESTF),A             ; RTFRAME will build the surplus argument list.
        LD HL,(RTPKARGC)           ; A rest procedure accepts counts at or above minimum.
        LD DE,(RTMINAR)            ; Compare the staged count with that minimum.
        OR A                       ; Clear carry before the unsigned lower-bound check.
        SBC HL,DE                  ; A borrow means too few actual arguments.
        JP C,RTARERR               ; Reject before frame or activation publication.
        JP RTSLOTC
RTFIXAR:
        XOR A                       ; Keep the fixed policy explicit in runtime scratch.
        LD (RTRESTF),A
        LD HL,(RTPKARGC)             ; Fixed procedures still require exact arity equality.
        OR A                       ; Clear carry before exact arity comparison.
        SBC HL,DE                  ; A nonzero result is an arity error.
        JP NZ,RTARERR              ; Reject before frame or activation publication.
RTSLOTC:
        LD HL,(RTDESCPT)             ; Descriptor +4 contains the number of frame slots.
        INC HL                     ; Skip entry-address low byte.
        INC HL                     ; Skip entry-address high byte.
        INC HL                     ; Skip arity low byte.
        INC HL                     ; Skip arity high byte.
        LD E,(HL)                  ; Read slot count low byte.
        INC HL                     ; Advance to slot-count high byte.
        LD D,(HL)                  ; DE is the total lexical binding count.
        LD HL,(RTMINAR)             ; A fixed frame needs at least its parameters.
        LD A,(RTRESTF)              ; A rest frame also needs one list-binding slot.
        OR A
        JP Z,RTSLOTCK
        INC HL                     ; Reserve the rest binding after required parameters.
RTSLOTCK:
        OR A                       ; Clear carry before comparing minimum slots to total.
        SBC HL,DE                  ; Carry or equality means enough lexical slots exist.
        JP C,RTSLOTOK              ; Internal definitions may add slots beyond this minimum.
        JP Z,RTSLOTOK
        JP RTINVERR                ; A descriptor with too few lexical slots is corrupt.
RTSLOTOK:
        LD HL,(RTDESCPT)             ; Store the validated frame slot count for entry setup.
        INC HL                     ; Skip descriptor entry low byte.
        INC HL                     ; Skip descriptor entry high byte.
        INC HL                     ; Skip descriptor arity low byte.
        INC HL                     ; Skip descriptor arity high byte.
        LD E,(HL)                  ; Read slot-count low byte.
        INC HL                     ; Advance to slot-count high byte.
        LD D,(HL)                  ; DE now holds the validated slot count.
        LD (RTSLOTS),DE            ; The frame constructor uses this after dispatch.
        XOR A                      ; Closure, descriptor and arity are all valid.
        RET                        ; RTDESCPT, RTTARGET and RTSLOTS now describe one procedure.
