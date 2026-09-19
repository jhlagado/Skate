;=============================================================================
;  Skate M7 heap and lexical-frame services
;=============================================================================

;  PURPOSE
;  -------
;  Allocate closures, build traced environments and read lexical bindings.

; Refresh the active-value descriptor while preserving the global-value span.
RTROOTS:
        PUSH IY                    ; Capture the architectural root top without changing it.
        POP HL                     ; HL is the candidate exclusive root address.
        LD DE,(RTROOTB)              ; Every scanned slot must begin at or above ROOTBASE.
        OR A                       ; Clear carry before the unsigned lower-bound check.
        SBC HL,DE                  ; A borrow means the runtime root cursor is corrupt.
        JP C,RTINVERR              ; Do not let collection scan below its configured arena.
        LD A,L                     ; Check that the byte extent contains whole value slots.
        AND 3                      ; A four-byte stride requires two clear low address bits.
        JP NZ,RTINVERR             ; A partial slot is a runtime invariant failure.
        SRL H                      ; Divide the root-byte extent by two.
        RR L                       ; Carry transfers the low bit of the high byte.
        SRL H                      ; Divide by four to obtain the descriptor slot count.
        RR L                       ; The validated extent now fits an unsigned slot count.
        LD (RTROOTCT),HL           ; GC scans exactly the slots below the current IY.
        PUSH IY                    ; Restore the actual root top after the subtraction.
        POP HL                     ; HL again holds the exclusive root address.
        LD (RTROOTP),HL              ; Keep the collector-visible mirror synchronized.
        LD DE,(RTROOTX)               ; The active top may equal, but may not exceed, ROOTEND.
        OR A                       ; Clear carry before the unsigned upper-bound check.
        SBC HL,DE                  ; A positive result means IY has passed the root limit.
        JP C,RTROOTOK              ; A top below ROOTEND is valid.
        JP Z,RTROOTOK              ; An empty suffix may end exactly at ROOTEND.
        JP RTCAPERR                ; Capacity is exhausted before a collection can begin.
RTROOTOK:
        RET                        ; The descriptor and mirror now describe the same extent.

; Allocate a fresh closure; HL is its descriptor and DE its captured ENV index.
RTMKCLOS:
        CALL RTSTKCHK              ; Reserve helper headroom before any nested allocator call.
        LD (RTDSCADR),HL           ; Save the immutable procedure-descriptor address.
        LD (RTCAPIDX),DE           ; Save zero or the captured environment index.
        LD HL,(RTCAPIDX)           ; A zero index denotes a capture-free closure.
        LD A,H                     ; Test both bytes before checking the heap bound.
        OR L                       ; A nonzero parent must name a real environment cell.
        JP Z,RTCAPDON              ; Zero needs no heap-index check.
        LD DE,(HCOUNT)             ; HCOUNT includes reserved cell zero.
        OR A                       ; Clear carry before the unsigned bounds comparison.
        SBC HL,DE                  ; Every live parent index is strictly below HCOUNT.
        JP NC,RTINVERR             ; Refuse to publish a closure with an invalid capture.
RTCAPDON:
        LD HL,(RTDSCADR)           ; The descriptor must fit wholly inside the code image.
        LD DE,(RTCODEB)             ; Begin with its lower address bound.
        OR A                       ; Clear carry before comparing unsigned addresses.
        SBC HL,DE                  ; A borrow means the descriptor points below the image.
        JP C,RTINVERR              ; Reject before reading descriptor bytes.
        LD HL,(RTDSCADR)           ; Compute the descriptor's exclusive eight-byte end.
        LD DE,8                    ; Entry, minimum arity, slots and rest policy are four words.
        ADD HL,DE                  ; HL now describes the complete descriptor extent.
        JP C,RTINVERR              ; A wrapped extent cannot belong to the code image.
        LD DE,(RTCODEE)             ; The descriptor may end exactly at CODEEND.
        OR A                       ; Compare its exclusive end with the code limit.
        SBC HL,DE                  ; Carry or equality means the complete extent fits.
        JP C,RTDSCOK               ; The descriptor ends below CODEEND.
        JP Z,RTDSCOK               ; The descriptor ends exactly at CODEEND.
        JP RTINVERR                ; Reject an out-of-image descriptor before allocation.
RTDSCOK:
        CALL RTROOTS               ; Make the caller's active values visible to a retry GC.
        LD HL,RTROOTDS             ; GRES scans active roots followed by global values.
        LD DE,2                    ; Keep both descriptor records in every collection.
        LD BC,1                    ; A closure occupies one physical heap cell.
        CALL GRES                  ; Collect and retry only while every live value is rooted.
        JP C,RTALLOC               ; Translate allocator capacity separately from corruption.
        CALL HPOP                  ; Consume the reserved cell; GC is forbidden until HDONE.
        JP C,RTINVERR              ; A failed pop violates the successful reservation.
        LD (RTCLOIDX),HL           ; Retain the public cell index across cell initialization.
        LD (RTMKADDR),DE           ; Retain its checked four-byte heap address.
        LD HL,(RTMKADDR)           ; Word zero stores the immutable descriptor address.
        LD DE,(RTDSCADR)           ; Recover the descriptor pointer saved on entry.
        LD (HL),E                  ; Store its low byte.
        INC HL                     ; Advance to descriptor high byte.
        LD (HL),D                  ; Complete the raw descriptor pointer.
        INC HL                     ; Advance to the closure's captured-environment link.
        LD DE,(RTCAPIDX)           ; Recover the validated parent environment index.
        LD A,E                     ; Store the low thirteen-bit link's low byte.
        LD (HL),A                  ; Closure cells trace this link as a heap edge.
        INC HL                     ; Advance to the high byte and physical tag.
        LD A,D                     ; The parent index occupies only the low five high bits.
        AND 1FH                    ; Remove any non-index bits before adding closure tag two.
        OR 40H                     ; Physical tag two marks this cell as a closure.
        LD (HL),A                  ; Finish the closure before ending its reservation.
        CALL HDONE                 ; Publish only the fully initialized closure cell.
        JP C,RTINVERR              ; HDONE cannot fail after this exact reservation was used.
        LD HL,(RTCLOIDX)           ; Build the public REF/CLOSURE payload from its index.
        LD A,H                     ; Recover the high five index bits.
        AND 1FH                    ; Keep only the thirteen-bit heap-cell identity.
        OR 40H                     ; Subtype two identifies a closure value.
        LD H,A                     ; HL is now (closure subtype << 13) | cell index.
        LD A,1                     ; Logical tag one denotes a heap reference.
        RET                        ; Return the fresh closure without an intervening safepoint.

; GRES error one is exhaustion; other errors indicate invalid runtime state.
RTALLOC:
        CP 1                       ; Capacity is the only ordinary allocation failure.
        JP Z,RTCAPERR              ; Report exhausted live heap through the platform boundary.
        JP RTINVERR                ; Bounds, protocol and tracing errors are invariant failures.


; Reserve and build one environment plus its reverse-linked binding cells.
RTFRAME:
        LD HL,(HCOUNT)              ; A frame needs one header plus every descriptor slot.
        LD DE,2                     ; Cell zero is reserved, and one usable cell is the header.
        OR A                        ; Clear carry before checking the physical heap minimum.
        SBC HL,DE                   ; HCOUNT-2 is the largest legal binding count.
        JP C,RTINVERR               ; HINIT should always provide at least two physical cells.
        LD DE,(RTSLOTS)             ; Compare requested bindings with the frame-size limit.
        OR A                        ; Clear carry before the unsigned count comparison.
        SBC HL,DE                   ; Carry means the frame cannot fit in this heap.
        JP C,RTCAPERR               ; Fail before reserving cells or publishing an activation.
        LD A,(RTRESTF)               ; A rest procedure needs a list for its surplus values.
        OR A
        CALL NZ,RTRESTLS              ; Build that list while the original packet is rooted.
        CALL RTROOTS                ; Refresh the collector descriptor from the current IY.
        LD BC,(RTSLOTS)             ; Reserve one header cell and every binding cell together.
        INC BC                      ; The complete request is now bounded by HCOUNT-1.
        LD HL,RTROOTDS              ; GRES scans active roots followed by global values.
        LD DE,2                     ; Keep both descriptor records in every collection.
        CALL GRES                   ; Reserve atomically, collecting and retrying if necessary.
        JP C,RTALLOC                ; Translate exhaustion separately from allocator corruption.
        LD HL,0                     ; No binding has been linked yet.
        LD (RTLINKIX),HL              ; Each new cell points to the previously built cell.
        LD HL,(RTSLOTS)             ; A zero-slot procedure needs only its environment header.
        LD A,H                      ; Test both bytes before forming the first slot index.
        OR L                        ; No binding loop is needed when the slot count is zero.
        JP Z,RTENVHDR               ; Build the header with a null first-binding link.
        DEC HL                      ; Build from the last lexical slot toward slot zero.
        LD (RTSLOTIX),HL            ; The finished chain will then follow lexical slot order.
RTBINDLP:
        LD A,(RTRESTF)               ; Rest frames bind surplus values as one proper list.
        OR A
        JP NZ,RTRESTBD               ; Fixed frames retain the direct argument-copy path.
        LD HL,(RTSLOTIX)            ; Compare this lexical slot with the argument count.
        LD DE,(RTPKARGC)              ; Slots below argc receive the corresponding argument.
        OR A                        ; Clear carry before comparing unsigned slot numbers.
        SBC HL,DE                   ; Carry means this slot belongs to the argument prefix.
        JP C,RTARGCPY                ; Copy that rooted argument into its binding cell.
RTSETUNB:
        XOR A                       ; Extra descriptor slots begin as the UNBOUND immediate.
        LD (RTVALTAG),A              ; UNBOUND is a scalar value, not a heap reference.
        LD HL,0FE05H                ; The private uninitialized-binding payload.
        LD (RTVALPAY),HL             ; Preserve it while HPOP returns the next cell address.
        JP RTPOPBND                  ; Initialize this local through the shared cell writer.
RTARGCPY:
        LD HL,(RTSLOTIX)            ; Convert lexical slot index to its packet byte offset.
        ADD HL,HL                  ; First doubling gives a two-byte payload stride.
        ADD HL,HL                  ; Second doubling gives the four-byte root-slot stride.
        LD DE,8                    ; Argument zero begins after environment and callee slots.
        ADD HL,DE                  ; The index now addresses this argument within the packet.
        LD DE,(RTPACKET)           ; The packet extent was validated before frame construction.
        ADD HL,DE                  ; The resulting address is inside the checked argument area.
        LD A,(HL)                  ; Copy the logical tag from the rooted argument.
        LD (RTVALTAG),A             ; Keep the tag while HPOP clobbers working registers.
        INC HL                     ; Advance to the payload low byte.
        LD E,(HL)                  ; Read the exact low payload byte.
        INC HL                     ; Advance to the payload high byte.
        LD D,(HL)                  ; DE now contains the complete value payload.
        LD (RTVALPAY),DE            ; Retain the value until the cell has been popped.
RTPOPBND:
        CALL HPOP                  ; Consume one cell from the frame's atomic reservation.
        JP C,RTINVERR              ; Every pop must succeed after GRES granted the full frame.
        LD (RTCELLIX),HL           ; Keep this cell's heap index for the next link.
        LD (RTCELADR),DE           ; Keep its arena address while the value is written.
        LD HL,(RTCELADR)           ; Heap CAR payload begins at cell byte zero.
        LD DE,(RTVALPAY)           ; Recover the argument or UNBOUND payload saved before HPOP.
        LD (HL),E                  ; Store the payload low byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),D                  ; Complete the two-byte CAR payload.
        INC HL                     ; Word one stores the next binding index.
        LD DE,(RTLINKIX)           ; Link to the previously built higher-numbered slot.
        LD (HL),E                  ; Store the link's low eight bits.
        INC HL                     ; Advance to link high bits and the CAR's logical tag.
        LD A,D                     ; Keep only the index's five high bits.
        AND 01FH                   ; The link occupies the low thirteen word bits.
        LD D,A                     ; D now contains only the link's high index bits.
        LD A,(RTVALTAG)            ; The physical high bits encode the CAR's logical tag.
        RLCA                       ; Move logical tag bit zero to physical bit five.
        RLCA                       ; Continue shifting the logical CAR tag into place.
        RLCA                       ; The value tag is restricted to 0, 1 or 3.
        RLCA                       ; Five rotations encode it in word-one bits 15..13.
        RLCA                       ; No tag bit is lost for the supported three-bit values.
        OR D                       ; Combine the CAR tag with the link's high index bits.
        LD (HL),A                  ; Publish the complete binding cell within the reservation.
        LD HL,(RTCELLIX)           ; Make this binding the new head of the reversed chain.
        LD (RTLINKIX),HL             ; The next lower slot will link to this cell.
        LD HL,(RTSLOTIX)           ; Stop after writing slot zero.
        LD A,H                     ; Test both bytes without changing the saved slot index.
        OR L                       ; Zero marks the first lexical binding.
        JP Z,RTENVHDR              ; The final header links to slot zero's cell.
        DEC HL                     ; Continue with the next lower-numbered lexical slot.
        LD (RTSLOTIX),HL           ; Save the index for the next construction pass.
        JP RTBINDLP                ; Each iteration consumes exactly one reserved cell.
RTRESTBD:
        LD HL,(RTSLOTIX)            ; The rest parameter occupies the minimum-arity slot.
        LD DE,(RTMINAR)             ; Compare this slot with the descriptor's lower bound.
        OR A                       ; Clear carry before the unsigned slot comparison.
        SBC HL,DE                  ; Equality selects the rooted surplus list.
        JP Z,RTRESTCP               ; Later internal-definition slots remain UNBOUND.
        JP C,RTARGCPY               ; Required parameters still copy their direct arguments.
        JP RTSETUNB
RTRESTCP:
        LD HL,(RTPACKET)            ; RTRESTLS leaves the proper list in the packet callee slot.
        LD DE,4                     ; The callee slot follows the environment slot.
        ADD HL,DE                  ; HL addresses the list's rooted tag byte.
        LD A,(HL)                  ; Copy the list tag before HPOP changes the registers.
        LD (RTVALTAG),A
        INC HL                     ; Read the list payload low byte.
        LD E,(HL)
        INC HL                     ; Read the list payload high byte.
        LD D,(HL)
        LD (RTVALPAY),DE
        JP RTPOPBND
RTENVHDR:
        CALL HPOP                  ; Pop the environment header after all binding cells exist.
        JP C,RTINVERR              ; The reservation guarantees this final pop is available.
        LD (RTFRAMEI),HL           ; Keep the public environment index for the packet value.
        LD (RTFRAMEA),DE           ; Keep the header address while its fields are initialized.
        LD HL,(RTCAPENV)           ; A nonzero capture becomes the new frame's parent value.
        LD A,H                     ; Test both bytes of the captured environment index.
        OR L                       ; Zero means the closure has no lexical parent.
        JP Z,RTENVNIL               ; Store NIL as the parent of a capture-free closure.
        LD A,1                     ; A captured environment is a logical heap reference.
        LD (RTVALTAG),A             ; The parent reference uses logical tag one.
        LD HL,(RTCAPENV)           ; The captured index occupies the low thirteen payload bits.
        LD DE,06000H               ; Subtype three identifies a private environment reference.
        ADD HL,DE                  ; Combine subtype and index into the tagged payload.
        LD (RTVALPAY),HL            ; Retain the complete parent value for the header.
        JP RTENVPAR                ; The common writer also stores the first binding link.
RTENVNIL:
        XOR A                      ; NIL is the parent of a capture-free closure.
        LD (RTVALTAG),A             ; Its logical tag is zero.
        LD HL,0FE02H               ; NIL has the fixed scalar payload FE02H.
        LD (RTVALPAY),HL            ; Preserve the payload while writing the header.
RTENVPAR:
        LD HL,(RTFRAMEA)           ; The header uses the same CAR/link layout as a pair cell.
        LD DE,(RTVALPAY)           ; Recover NIL or REF/ENV(parent).
        LD (HL),E                  ; Store the parent's payload low byte.
        INC HL                     ; Advance to the parent payload high byte.
        LD (HL),D                  ; Complete the two-byte parent payload.
        INC HL                     ; Word one stores the first binding index.
        LD DE,(RTLINKIX)           ; RTLINKIX is zero or the first binding cell index.
        LD (HL),E                  ; Store the link's low eight bits.
        INC HL                     ; Advance to link high bits and the parent's logical tag.
        LD A,D                     ; Keep only the index's five high bits.
        AND 01FH                   ; The link occupies the low thirteen word bits.
        LD D,A                     ; D now contains only the link's high index bits.
        LD A,(RTVALTAG)            ; The physical high bits encode the parent's logical tag.
        RLCA                       ; Move logical tag bit zero to physical bit five.
        RLCA                       ; Shift the parent tag into the three physical tag bits.
        RLCA                       ; NIL is tag zero; REF/ENV is tag one.
        RLCA                       ; The high three bits preserve the CAR classification.
        RLCA                       ; Five rotations match word-one bits 15..13.
        OR D                       ; Combine parent tag and first-binding index.
        LD (HL),A                  ; The environment header is now complete.
        CALL HDONE                 ; Publish the entire environment and binding chain together.
        JP C,RTINVERR              ; HDONE must close the exact reservation just consumed.
        LD HL,(RTFRAMEI)           ; Build the REF/ENV value stored in packet slot zero.
        LD DE,06000H               ; Environment references use subtype three.
        ADD HL,DE                  ; Add the heap index to the reference subtype.
        LD (RTVALPAY),HL            ; Preserve the public tagged payload for packet publication.
        LD HL,(RTPACKET)           ; Replace the packet's initial NIL environment slot.
        LD A,1                     ; Logical tag one denotes the environment reference.
        LD (HL),A                  ; Publish its tag while no collection can occur.
        INC HL                     ; Advance to the payload low byte.
        LD DE,(RTVALPAY)            ; Load subtype and environment index.
        LD (HL),E                  ; Store the payload low byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),D                  ; Complete the REF/ENV value.
        INC HL                     ; Advance to the root-slot padding byte.
        LD (HL),0                  ; Keep the collector's four-byte root slot canonical.
        LD HL,(RTPACKET)           ; Arguments are now copied into traced binding cells.
        LD DE,8                    ; The argument area follows the packet's two header slots.
        ADD HL,DE                  ; Start clearing at argument zero.
        LD BC,(RTPKARGC)             ; Clear each duplicate root after its frame copy is published.
        LD A,B                     ; A zero-argument frame needs no clearing loop.
        OR C                       ; Combine both bytes of argc for that test.
        JP Z,RTFRDONE              ; The frame header and callee are already rooted.
RTCLRARG:
        LD (HL),0                  ; NIL tag removes the old argument reference from the stack.
        INC HL                     ; Advance to the payload low byte.
        LD (HL),2                  ; Write the low byte of the fixed NIL payload.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),0FEH               ; Complete NIL's FE02H payload.
        INC HL                     ; Advance to the root slot's padding byte.
        LD (HL),0                  ; Keep every active root slot well formed.
        INC HL                     ; Move to the next argument root.
        DEC BC                     ; One argument value has been cleared.
        LD A,B                     ; Test whether any argument roots remain.
        OR C                       ; The loop ends after the final four-byte slot.
        JP NZ,RTCLRARG             ; Clear every copied argument before entering the body.
RTFRDONE:
        XOR A                      ; Frame construction and packet publication succeeded.
        RET                        ; No safepoint occurred between HDONE and the rooted ENV slot.

; Build the proper list bound to a dotted formal from surplus packet arguments.
; Preserve the closure in the packet's environment slot while each cons may collect.
; RTFRAME will replace that temporary root with the new environment header later.
RTRESTLS:
        LD HL,(RTPACKET)            ; The environment slot is the packet's first root slot.
        LD DE,4                     ; The callee follows that slot by one tagged value.
        ADD HL,DE                   ; HL now points at the closure root to preserve.
        LD DE,(RTPACKET)            ; DE is the lower destination slot in the same packet.
        LD BC,4                     ; Copy the complete tagged closure value, including padding.
        LDIR                        ; The higher source and lower destination do not overlap unsafely.
        CALL RTSTKCHK               ; Each list pair may enter the collector.
        LD HL,(RTPACKET)            ; Start with the callee slot as the NIL accumulator.
        LD DE,4                     ; It follows the packet's environment slot.
        ADD HL,DE
        LD (RTCDRPTR),HL            ; Keep the rooted accumulator address stable.
        XOR A                       ; NIL is a scalar with the canonical FE02H payload.
        LD (HL),A
        INC HL
        LD (HL),2
        INC HL
        LD (HL),0FEH
        INC HL
        LD (HL),0
        LD HL,(RTPKARGC)            ; Compare actual arguments with the minimum arity.
        LD DE,(RTMINAR)
        OR A
        SBC HL,DE
        JP Z,RTRESTDN               ; No surplus arguments leave the NIL accumulator.
        JP C,RTRESTDN               ; RTRESLV already rejects this malformed state.
        LD HL,(RTPKARGC)            ; Start at the final argument and work backwards.
        DEC HL
        LD (RTRESTIX),HL
RTRESTLO:
        LD HL,(RTRESTIX)            ; Convert the argument index to a packet byte offset.
        ADD HL,HL
        ADD HL,HL
        LD DE,8                     ; Arguments begin after the environment/callee headers.
        ADD HL,DE
        LD DE,(RTPACKET)
        ADD HL,DE
        LD (RTCARPTR),HL            ; RTGETCAR copies the argument before allocation.
        CALL RTGETCAR
        LD HL,(RTCDRPTR)            ; Read the current list accumulator as the CDR.
        LD A,(HL)
        LD (RTCDRTAG),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (RTCDRVAL),DE
        CALL RTMAKEPR               ; Cons the argument onto the rooted accumulator.
        PUSH AF                     ; Preserve the returned list value across its slot update.
        PUSH HL
        LD HL,(RTCDRPTR)
        POP DE
        POP AF
        LD (HL),A
        INC HL
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),0
        LD HL,(RTRESTIX)            ; Stop after the first surplus argument at minArity.
        LD DE,(RTMINAR)
        OR A
        SBC HL,DE
        JP Z,RTRESTDN
        LD HL,(RTRESTIX)
        DEC HL
        LD (RTRESTIX),HL
        JP RTRESTLO
RTRESTDN:
        RET

; Build a child environment for let using its already-rooted initializer packet.
RTLETFRM:
        CALL RTSTKCHK              ; Frame setup uses the same bounded helpers as procedure entry.
        LD (RTPACKET),DE           ; Keep the let packet base while reading the active environment.
        LD (RTPKARGC),BC           ; Each initializer becomes one lexical binding value.
        LD (RTSLOTS),BC            ; The let frame has exactly one slot per binding.
        CALL RTCURCHK              ; Validate the current activation and cache its ENV index.
        LD HL,(RTENVIND)           ; A let frame's parent is the environment active on entry.
        LD (RTCAPENV),HL           ; RTFRAME links the new header back to this parent.
        XOR A                      ; A let frame has no dotted formal or surplus list.
        LD (RTRESTF),A
        CALL RTFRAME               ; Allocate, fill and publish the let environment atomically.
        LD HL,(RTPACKET)           ; RTFRAME replaced the let packet's environment slot.
        LD DE,(RTCURPKT)           ; The active procedure packet keeps its own environment slot.
        LD BC,4                    ; Copy one complete four-byte tagged ENV value.
        LDIR                       ; Lexical depth zero now selects the newly built let frame.
        XOR A                      ; Frame construction completed without an ordinary error.
        RET                        ; Leave the let packet rooted until RTLETEND restores IY.

; Restore the parent environment and saved root top after a non-tail let body.
RTLETEND:
        LD (RTRESVAL),HL           ; Preserve the body result while helpers inspect its frame.
        LD (RTRESTAG),A            ; Keep the logical result tag beside the saved payload.
        CALL RTSTKCHK              ; Check headroom before nested lexical-validation helpers.
        CALL RTCURCHK              ; The active packet currently names the innermost let frame.
        XOR A                      ; RTREADVL must decode the environment as a heap cell.
        LD (RTBINDMD),A            ; Ignore a global mode left by an earlier identifier access.
        LD HL,(RTENVIND)           ; The current environment header stores its parent in CAR.
        LD (RTBNDIND),HL           ; RTREADLK validates the header and records its cell address.
        CALL RTREADLK              ; Check the header, parent tag and first-binding link.
        CALL RTREADVL              ; Copy the parent value into stable tag and payload scratch.
        LD A,(RTGETTAG)            ; A closure-free parent must be the canonical NIL value.
        OR A                       ; Tag zero selects that parent case.
        JP Z,RTLETNIL             ; Verify its payload before restoring the active packet.
        CP 1                       ; A nested frame stores REF/ENV as its parent value.
        JP NZ,RTINVERR             ; Numbers or other immediates cannot parent an environment.
        LD HL,(RTGETPAY)           ; Inspect the reference subtype before using its index.
        LD A,H                     ; The upper three bits identify the reference kind.
        AND 0E0H                   ; Remove all thirteen heap-index bits.
        CP 060H                    ; Environment links use private reference subtype three.
        JP NZ,RTINVERR             ; Do not restore a pair, closure or symbol as an ENV.
        LD A,H                     ; Recover the high five bits of the parent index.
        AND 01FH                   ; Strip the subtype bits from the index.
        LD D,A                     ; DE now contains the untagged parent index.
        LD E,L                     ; Retain its low byte.
        LD A,D                     ; Cell zero is permanently reserved.
        OR E                       ; Test both bytes before checking the heap extent.
        JP Z,RTINVERR              ; A null reference cannot name a live parent environment.
        LD H,D                     ; Compare the untagged parent index with HCOUNT.
        LD L,E                     ; HL now contains the thirteen-bit heap-cell index.
        LD DE,(HCOUNT)             ; HCOUNT includes reserved cell zero.
        OR A                       ; Clear carry before unsigned bounds comparison.
        SBC HL,DE                  ; Every nonzero parent environment is below HCOUNT.
        JP NC,RTINVERR             ; Reject a forged link before restoring it as the active ENV.
        LD HL,(RTGETPAY)           ; Retain the already-validated REF/ENV payload.
        LD (RTVALPAY),HL           ; Prepare it for publication in the active packet.
        LD A,1                     ; The parent environment is a logical heap reference.
        LD (RTVALTAG),A            ; Store its tag separately from the thirteen-bit index.
        JP RTLETRET               ; Both parent encodings now share packet/root restoration.

RTLETNIL:
        LD HL,(RTGETPAY)           ; Tag zero is valid here only for canonical NIL.
        LD DE,0FE02H               ; Environment roots use NIL when they have no parent.
        OR A                       ; Clear carry before comparing the complete payload.
        SBC HL,DE                  ; Equality proves this header has no lexical parent.
        JP NZ,RTINVERR             ; Reject any other immediate in the environment header.
        XOR A                      ; NIL has logical tag zero.
        LD (RTVALTAG),A            ; Save it for the active packet slot.
        LD HL,0FE02H               ; Keep the canonical NIL payload paired with its tag.
        LD (RTVALPAY),HL           ; Preserve it while the root top is restored.

RTLETRET:
        LD HL,(RTCURPKT)           ; Return the parent value to the active procedure packet.
        LD A,(RTVALTAG)            ; Recover the parent environment's logical tag.
        LD (HL),A                  ; Replace the temporary let ENV in packet slot zero.
        INC HL                     ; Advance to the parent payload low byte.
        LD DE,(RTVALPAY)           ; Recover NIL or the checked REF/ENV payload.
        LD (HL),E                  ; Store the low payload byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),D                  ; Complete the restored parent environment value.
        INC HL                     ; The packet's final slot byte is collector padding.
        LD (HL),0                  ; Keep the root slot canonical after the environment change.
        POP BC                     ; Remove the RTLETEND return temporarily.
        POP DE                     ; Retrieve the IY saved before RTPKNEW reserved the let packet.
        PUSH BC                    ; Restore the service continuation above the discarded marker.
        PUSH DE                    ; Move the old root top into IY without losing the return word.
        POP IY                     ; Drop the let packet and every temporary value it owns.
        CALL RTROOTS               ; Refresh the active root descriptor from the restored IY.
        LD A,(RTRESTAG)            ; Restore the Scheme body's logical result tag.
        LD HL,(RTRESVAL)           ; Restore its payload after root-descriptor validation.
        RET                        ; Resume the caller with its original root extent and result.

; Return the active environment index in DE while preserving descriptor HL.
RTCURENV:
        PUSH HL                    ; A compiler may have a descriptor address live in HL.
        CALL RTCURCHK              ; Validate the active frame and cache its environment index.
        LD DE,(RTENVIND)           ; Return the untagged thirteen-bit heap index.
        POP HL                     ; Restore the descriptor for the following RTMKCLOS call.
        RET                        ; No allocation or collection occurs in this leaf service.

; Read one lexical value; CALL RTGETVAL is followed by DW depth, slot.
RTGETVAL:
        POP BC                     ; Consume the inline-operand address, not the caller's return.
        CALL RTREADOP              ; Decode depth and slot; remember the real continuation.
        CALL RTLOCBND              ; Resolve and validate the requested binding cell.
        CALL RTREADVL             ; Copy its logical tag and payload into stable scratch.
        CALL RTUNBCHK              ; Only the exact FE05H scalar denotes an uninitialized slot.
        JP C,RTUNBERR              ; Reading an internal definition before initialization is an error.
        JP RTRETVAL                ; Return the tagged value and skip both inline words.

; Replace the value in an already initialized lexical binding.
RTSETBND:
        LD (RTVALTAG),A            ; Preserve the caller's logical tag before lookup clobbers A.
        LD (RTVALPAY),HL           ; Preserve the two-byte payload before lookup uses HL.
        POP BC                     ; Remove the inline-operand address from the return stack.
        CALL RTREADOP              ; Decode depth and slot and save their following address.
        CALL RTLOCBND              ; Locate the shared binding cell without allocating.
        CALL RTREADVL             ; Read the previous value to check initialization state.
        CALL RTUNBCHK              ; set! is valid only after the binding has been initialized.
        JP C,RTUNBERR              ; Treat assignment to the private UNBOUND sentinel as an error.
        CALL RTWRITEV              ; Preserve the binding link while replacing its tagged CAR.
        JP RTUNSRET                ; set! returns the language's unspecified value.

; Fill a leading internal-definition slot exactly once.
RTINITBD:
        LD (RTVALTAG),A            ; Preserve the initializer's logical tag across lexical lookup.
        LD (RTVALPAY),HL           ; Preserve its two-byte payload across lexical lookup.
        POP BC                     ; Remove the inline-operand address from the return stack.
        CALL RTREADOP              ; Decode depth and slot and save their following address.
        CALL RTLOCBND              ; Locate the shared binding cell without allocating.
        CALL RTREADVL             ; Read the slot's previous value and its logical tag.
        CALL RTUNBCHK              ; Internal definitions may replace only exact UNBOUND.
        JP NC,RTINVERR             ; A repeated initialization contradicts the compiler's scan.
        CALL RTWRITEV              ; Install the initializer while preserving the next-cell link.
        JP RTUNSRET                ; A definition form also evaluates to unspecified.

; Decode the four inline operand bytes addressed by BC.
RTREADOP:
        LD A,(BC)                  ; The first operand byte is lexical depth low.
        LD (RTDEPLO),A             ; Retain it while BC advances through the operand words.
        INC BC                     ; Point at lexical depth high.
        LD A,(BC)                  ; Read the depth's high byte.
        LD (RTDEPHI),A             ; Preserve the complete unsigned depth.
        INC BC                     ; Point at lexical slot low.
        LD A,(BC)                  ; Read the slot number's low byte.
        LD (RTSLOTLO),A            ; Retain it before reading the high byte.
        INC BC                     ; Point at lexical slot high.
        LD A,(BC)                  ; Read the slot's high byte.
        LD (RTSLOTHI),A            ; Preserve the complete unsigned slot number.
        INC BC                     ; BC now points after both inline operands.
        LD (RTACCPTR),BC           ; Save the continuation used by either result path.
        LD A,(RTDEPLO)             ; Assemble the two depth bytes into one word.
        LD L,A                     ; L receives lexical depth low.
        LD A,(RTDEPHI)             ; Read lexical depth high.
        LD H,A                     ; HL now contains the full unsigned depth.
        LD (RTDEPTH),HL            ; Retain the number of parent links to follow.
        LD A,(RTSLOTLO)            ; Assemble the two slot bytes into one word.
        LD L,A                     ; L receives lexical slot low.
        LD A,(RTSLOTHI)             ; Read lexical slot high.
        LD H,A                     ; HL now contains the full unsigned slot number.
        LD (RTSLOTNO),HL           ; Retain the number of binding links to follow.
        RET                        ; The lookup helper can now use BC freely.

; Resolve RTDEPTH parents, then RTSLOTNO binding links into RTCELADR.
RTLOCBND:
        LD HL,(RTDEPTH)            ; Depth FFFFH addresses the generated global table.
        LD DE,0FFFFH               ; Other depths name an activation environment.
        OR A                       ; Clear carry before the sentinel comparison.
        SBC HL,DE                  ; Equality selects the non-heap global binding path.
        JP Z,RTGLBIND              ; Global slots live in the image, not heap cells.
        XOR A                      ; Lexical bindings are addressed by heap-cell index.
        LD (RTBINDMD),A            ; Select the ordinary binding-cell read/write layout.
        CALL RTCURCHK              ; Validate IX and load the current frame's environment.
        LD HL,(RTDEPTH)            ; Begin with the requested lexical depth.
RTGETDEP:
        LD A,H                     ; A zero depth selects the current environment.
        OR L                       ; Test both bytes of the remaining parent count.
        JP Z,RTGETENV              ; Stop once the requested frame has been reached.
        LD HL,(RTENVIND)           ; Convert this environment index to its heap-cell address.
        ADD HL,HL                  ; First doubling gives a two-byte cell offset.
        ADD HL,HL                  ; Second doubling gives a four-byte cell offset.
        LD DE,(RTHEAPB)            ; Add the checked physical heap base.
        ADD HL,DE                  ; HL now addresses the current environment header.
        JP C,RTINVERR              ; HINIT geometry makes a wrapped heap address impossible.
        LD DE,3                    ; The parent's logical tag is in word one's high byte.
        ADD HL,DE                  ; Move to the physical tag byte at header offset three.
        LD A,(HL)                  ; Read the environment parent tag and binding-link high bits.
        AND 0E0H                   ; Discard the first-binding link index.
        SRL A                      ; Move the logical tag toward the low three bits.
        SRL A                      ; Continue decoding the encoded tag.
        SRL A                      ; The parent must be a reference value.
        SRL A                      ; Four shifts leave the tag at bit one.
        SRL A                      ; Five shifts recover the logical value tag.
        CP 1                       ; A nonzero lexical depth requires REF/ENV as parent.
        JP NZ,RTINVERR             ; NIL or any other value cannot satisfy this lookup.
        LD HL,(RTENVIND)           ; Reload the current environment index for its parent.
        ADD HL,HL                  ; First doubling gives a two-byte cell offset.
        ADD HL,HL                  ; Second doubling gives a four-byte cell offset.
        LD DE,(RTHEAPB)            ; Add the checked physical heap base.
        ADD HL,DE                  ; HL again addresses the current environment header.
        JP C,RTINVERR              ; A wrapped address contradicts validated heap geometry.
        LD E,(HL)                  ; Preserve the parent's low index byte.
        INC HL                     ; Advance to the parent's payload high byte.
        LD A,(HL)                  ; Validate that this reference has the ENV subtype.
        AND 0E0H                   ; Retain only the encoded reference subtype.
        CP 060H                    ; Environment links use private reference subtype three.
        JP NZ,RTINVERR             ; Do not follow pairs, closures or table references.
        LD A,(HL)                  ; Recover the parent's high heap-index bits.
        AND 01FH                   ; Remove the ENV subtype from the high byte.
        LD D,A                     ; DE is the untagged parent-environment index.
        LD A,D                     ; Parent environment index zero means no parent exists.
        OR E                       ; Test both index bytes before following the link.
        JP Z,RTINVERR              ; A null parent cannot satisfy the requested depth.
        LD (RTENVIND),DE           ; Continue lookup from the captured parent environment.
        LD HL,(RTENVIND)           ; Check the new index before another dereference.
        LD DE,(HCOUNT)             ; The allocator owns exactly HCOUNT physical cells.
        OR A                       ; Clear carry before comparing unsigned indices.
        SBC HL,DE                  ; Each environment index must be strictly below HCOUNT.
        JP NC,RTINVERR             ; Reject a malformed chain before calculating its address.
        LD HL,(RTDEPTH)            ; One parent link satisfies one unit of lexical depth.
        DEC HL                     ; Move closer to the selected lexical frame.
        LD (RTDEPTH),HL            ; Save the remaining parent count.
        JP RTGETDEP                ; Continue until depth zero selects this environment.
RTGETENV:
        LD HL,(RTENVIND)           ; The selected environment header owns the binding chain.
        LD (RTBNDIND),HL           ; RTREADLK reads its word-one first-binding link.
        CALL RTREADLK              ; Validate the header and load slot zero's cell index.
        LD HL,(RTLINKIX)           ; The head of the chain is lexical slot zero.
        LD (RTBNDIND),HL           ; Preserve it while following the requested slot links.
        LD HL,(RTSLOTNO)           ; The slot operand counts links to follow from the head.
RTSKPBND:
        LD A,H                     ; A zero slot offset selects the current binding cell.
        OR L                       ; Test both bytes of the remaining slot number.
        JP Z,RTLOCEND              ; The current cell is now the requested lexical binding.
        LD HL,(RTBNDIND)           ; Every skipped slot must have a following binding cell.
        LD A,H                     ; Check whether the current chain ended too early.
        OR L                       ; A null link cannot satisfy a larger slot number.
        JP Z,RTINVERR              ; A missing local slot is a corrupt lexical address.
        CALL RTREADLK              ; Read and validate this cell's next binding link.
        LD HL,(RTLINKIX)           ; Advance one cell toward the requested lexical slot.
        LD (RTBNDIND),HL           ; Save the next binding index.
        LD HL,(RTSLOTNO)           ; Reload the remaining slot offset.
        DEC HL                     ; One binding link has now been followed.
        LD (RTSLOTNO),HL           ; Keep the complete unsigned offset in scratch.
        JP RTSKPBND                ; Continue until the requested slot reaches zero.
RTLOCEND:
        LD HL,(RTBNDIND)           ; Select the final binding cell for the common validator.
        LD (RTBNDIND),HL           ; Keep the index stable while RTREADLK validates it.
        JP RTREADLK                ; Return with its heap address in RTCELADR.

; Resolve the global slot index to the tag byte in its six-byte image entry.
RTGLBIND:
        LD HL,(RTSLOTNO)           ; The inline slot operand is the global-table index.
        LD DE,(RTGLOBC)            ; Compare it with the configured number of entries.
        OR A                       ; Clear carry before the unsigned bounds check.
        SBC HL,DE                  ; A valid index is strictly below the global count.
        JP NC,RTINVERR             ; Reject a corrupt or forged global address operand.
        LD HL,(RTSLOTNO)           ; Form six bytes per entry without a multiply helper.
        ADD HL,HL                  ; Preserve two bytes per entry in DE.
        LD D,H                     ; DE is the two-times index.
        LD E,L                     ; Keep that partial product while HL grows to four-times.
        ADD HL,HL                  ; HL now holds four bytes per global entry.
        ADD HL,DE                  ; Add the saved two-byte portion for a six-byte stride.
        LD DE,(RTGLOBDS)           ; The descriptor points at entry zero's value tag.
        ADD HL,DE                  ; Address the selected entry's tag byte.
        JP C,RTINVERR              ; The checked global-table extent must not wrap.
        LD (RTBNDADR),HL           ; Preserve this slot address across value operations.
        LD A,1                     ; Mode one selects the direct image-table layout.
        LD (RTBINDMD),A            ; RTREADVL and RTWRITEV use RTBNDADR in this mode.
        RET                        ; The selected global value remains in the image table.

; Copy the selected binding's tagged CAR into RTGETTAG and RTGETPAY.
RTREADVL:
        LD A,(RTBINDMD)            ; Global slots have no heap-cell link to decode.
        OR A                       ; Zero keeps the lexical-cell layout below.
        JP NZ,RTREADGL             ; Read a global tag, payload and padding directly.
        LD HL,(RTCELADR)           ; The binding's two-byte CAR payload begins at byte zero.
        LD E,(HL)                  ; Read its low payload byte.
        INC HL                     ; Advance to the payload high byte.
        LD D,(HL)                  ; DE now contains the complete CAR payload.
        EX DE,HL                   ; Keep the payload in HL while decoding its tag.
        LD (RTGETPAY),HL           ; Preserve it before HL moves to word one's high byte.
        LD HL,(RTCELADR)           ; Reload the binding cell's first byte.
        INC HL                     ; Skip payload low byte.
        INC HL                     ; Skip payload high byte.
        INC HL                     ; The next byte holds the logical CAR tag and link high bits.
        LD A,(HL)                  ; Logical tags occupy bits seven through five.
        AND 0E0H                   ; Remove the binding link's high index bits.
        SRL A                      ; Move the logical tag toward the low three bits.
        SRL A                      ; Continue decoding the tag field.
        SRL A                      ; The value tag is restricted to 0, 1 or 3.
        SRL A                      ; Four shifts leave its bits at positions one and zero.
        SRL A                      ; Five shifts decode the complete logical tag.
        CP 0                       ; Scalar values and NIL use logical tag zero.
        JP Z,RTTAGOK            ; Keep the decoded tag after validation.
        CP 1                       ; Logical tag one denotes a heap reference.
        JP Z,RTTAGOK            ; The caller interprets the payload subtype.
        CP 3                       ; Logical tag three denotes a number.
        JP NZ,RTINVERR             ; No other CAR tag is part of the value ABI.
RTTAGOK:
        LD (RTGETTAG),A            ; Save the validated result tag beside its payload.
        RET                        ; RTUNBCHK can now distinguish UNBOUND from other scalars.

; Copy a global table value and reject invalid tags or nonzero slot padding.
RTREADGL:
        LD HL,(RTBNDADR)           ; The selected global entry starts at its value tag.
        LD A,(HL)                  ; Global values use the ordinary three-bit logical tag.
        OR A                       ; Tag zero is a scalar or private immediate.
        JP Z,RTGLBTAG              ; Continue after accepting the scalar representation.
        CP 1                       ; Tag one denotes a reference value.
        JP Z,RTGLBTAG              ; Its reference subtype remains in the payload.
        CP 3                       ; Tag three denotes a number.
        JP NZ,RTINVERR             ; No other logical tag belongs to value ABI 2.
RTGLBTAG:
        LD (RTGETTAG),A            ; Preserve the tag while copying its two-byte payload.
        INC HL                     ; The payload low byte follows the tag.
        LD E,(HL)                  ; Keep the low payload byte in E.
        INC HL                     ; Advance to the payload high byte.
        LD D,(HL)                  ; DE now contains the complete global payload.
        EX DE,HL                   ; Move the payload to HL for the shared UNBOUND check.
        LD (RTGETPAY),HL           ; Save it before checking the reserved padding byte.
        EX DE,HL                   ; Restore the payload-high address from DE.
        INC HL                     ; The fourth value byte is reserved padding.
        LD A,(HL)                  ; Generated slots keep this byte at zero.
        OR A                       ; Do not pass malformed values to the collector.
        JP NZ,RTINVERR             ; Treat a nonzero pad as corrupted global-table data.
        RET                        ; RTUNBCHK handles FE05H as UNBOUND.

; Carry reports the exact private scalar used for an uninitialized binding.
RTUNBCHK:
        LD A,(RTGETTAG)            ; UNBOUND is a tag-zero scalar, never a reference.
        OR A                       ; Any nonzero logical tag is already initialized.
        JP NZ,RTBOUND              ; Preserve numbers and heap references without payload matching.
        LD HL,(RTGETPAY)           ; Tag zero alone is insufficient to identify the sentinel.
        LD DE,0FE05H               ; This exact payload distinguishes UNBOUND from all other scalars.
        OR A                       ; Clear carry before the unsigned payload comparison.
        SBC HL,DE                  ; Equality means the binding still awaits its initializer.
        JP NZ,RTBOUND              ; Other immediate values, including NIL, are initialized.
        SCF                        ; Carry is the private helper's uninitialized result.
        RET                        ; Callers choose read, set! or initialize error handling.
RTBOUND:
        OR A                       ; Clear carry while preserving the non-sentinel tag in A.
        RET                        ; Carry clear means the binding already has a value.

; Store RTVALTAG:RTVALPAY in RTCELADR without changing its binding link.
RTWRITEV:
        LD A,(RTVALTAG)            ; Validate the caller's logical value tag before writing.
        OR A                       ; Tag zero is a valid scalar representation.
        JP Z,RTWRMODE              ; Continue after selecting the global or lexical layout.
        CP 1                       ; Tag one denotes a reference value.
        JP Z,RTWRMODE              ; Its subtype remains encoded in the payload.
        CP 3                       ; Tag three denotes an exact integer or binary16 value.
        JP NZ,RTINVERR             ; Reject malformed values before changing the cell.
RTWRMODE:
        LD A,(RTBINDMD)            ; Global slots store tag and payload consecutively.
        OR A                       ; Zero selects the linked heap-cell representation.
        JP NZ,RTWRTGLB            ; Store a validated global value directly in the image.
RTWRITOK:
        LD HL,(RTCELADR)           ; Begin at the selected binding's CAR payload.
        LD DE,(RTVALPAY)           ; Recover the new two-byte payload from stable scratch.
        LD (HL),E                  ; Replace payload low.
        INC HL                     ; Advance to payload high.
        LD (HL),D                  ; Replace payload high.
        INC HL                     ; Skip the next-cell link's low byte.
        INC HL                     ; Reach link high bits and logical CAR tag.
        LD A,(HL)                  ; Read the old tag/link byte.
        AND 01FH                   ; Keep the binding link's upper five index bits.
        LD D,A                     ; Preserve those link bits while encoding the new tag.
        LD A,(RTVALTAG)            ; Read the new logical value tag.
        RLCA                       ; Move tag bit zero toward physical bit five.
        RLCA                       ; Continue shifting the logical tag into place.
        RLCA                       ; Supported tags are zero, one and three.
        RLCA                       ; Four rotations preserve all three logical-tag bits.
        RLCA                       ; Five rotations place them in word-one bits 15..13.
        OR D                       ; Combine the tag with the unchanged link index.
        LD (HL),A                  ; Publish the complete updated binding value.
        RET                        ; The cell remains in the same shared location.

; Store a global value without changing its symbol index or table stride.
RTWRTGLB:
        LD HL,(RTBNDADR)           ; Begin at the selected global value's tag byte.
        LD A,(RTVALTAG)            ; Install the validated logical tag.
        LD (HL),A                  ; Replace only the tag, not the preceding symbol index.
        INC HL                     ; Advance to the payload low byte.
        LD DE,(RTVALPAY)           ; Recover the payload saved by RTSETBND or RTINITBD.
        LD (HL),E                  ; Store the low payload byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),D                  ; Store the high payload byte.
        INC HL                     ; The last byte of the four-byte value slot is padding.
        LD (HL),0                  ; Keep the collector's scanned value slot canonical.
        RET                        ; The global descriptor observes the completed value.

; Return the selected value from RTGETVAL, consuming its two inline operands.
RTRETVAL:
        LD DE,(RTACCPTR)           ; Recover the compiler-emitted instruction after both words.
        PUSH DE                    ; Use it as the return target after restoring A:HL.
        LD A,(RTGETTAG)            ; Return the selected value's logical tag.
        LD HL,(RTGETPAY)           ; Return the selected value's payload.
        RET                        ; Skip inline operands and leave the caller's stack balanced.

; Return the language's unspecified immediate after set! or a definition.
RTUNSRET:
        LD DE,(RTACCPTR)           ; Recover the continuation following lexical operands.
        PUSH DE                    ; Replace the consumed inline return address.
        XOR A                      ; Unspecified is a logical tag-zero immediate.
        LD HL,0FE04H               ; FE04H is the runtime's canonical UNSPECIFIED payload.
        RET                        ; Resume after operands with the caller's SP restored.

; Validate IX and the active packet's REF/ENV slot; save its index in RTENVIND.
RTCURCHK:
        PUSH IX                    ; IX owns the current activation-record address.
        POP HL                     ; Inspect IX without changing the record pointer.
        LD A,H                     ; Zero is reserved for startup before any procedure entry.
        OR L                       ; Test both activation-address bytes.
        JP Z,RTINVERR              ; Lexical services require an active procedure frame.
        LD L,(IX+2)                ; Load the packet base from activation-record field +2.
        LD H,(IX+3)                ; Slot zero at this address contains the environment value.
        LD (RTCURPKT),HL           ; Keep the raw root address for range and alignment checks.
        LD A,L                     ; Compiled packet bases are aligned to four-byte values.
        AND 3                      ; Reject a corrupted address before reading a root slot.
        JP NZ,RTINVERR             ; A misaligned packet base cannot hold a tagged value.
        LD DE,(RTROOTB)            ; The active packet must begin inside the configured root arena.
        OR A                       ; Clear carry before the unsigned lower-bound check.
        SBC HL,DE                  ; A borrow means the activation points below ROOTBASE.
        JP C,RTINVERR              ; Never read environment data from outside the root arena.
        LD HL,(RTCURPKT)           ; Check that the four-byte environment slot is still rooted.
        LD DE,4                    ; One tagged value occupies four bytes.
        ADD HL,DE                  ; Compute the environment slot's exclusive end.
        JP C,RTINVERR              ; A wrapped packet address cannot be valid root storage.
        LD DE,(RTROOTP)            ; ROOTP is the current exclusive end of all live roots.
        OR A                       ; Clear carry before comparing unsigned addresses.
        SBC HL,DE                  ; Carry or equality means the environment slot is rooted.
        JP C,RTCURVAL              ; Slot end lies below the active root cursor.
        JP Z,RTCURVAL              ; Slot end may equal ROOTP exactly.
        JP RTINVERR                ; Reject a stale activation pointing above current roots.
RTCURVAL:
        LD HL,(RTCURPKT)           ; Return to the validated packet base.
        LD A,(HL)                  ; A compiled activation stores REF/ENV in slot zero.
        CP 1                       ; Logical tag one denotes a reference value.
        JP NZ,RTINVERR             ; NIL or a scalar cannot be the active environment.
        INC HL                     ; Advance to the tagged environment payload low byte.
        LD E,(HL)                  ; Preserve the environment index low byte.
        INC HL                     ; Advance to the payload high byte.
        LD A,(HL)                  ; The payload subtype must identify an environment.
        AND 0E0H                   ; Ignore the low thirteen heap-index bits.
        CP 060H                    ; Subtype three is the private ENV reference.
        JP NZ,RTINVERR             ; Do not follow pairs, closures or table references.
        LD A,(HL)                  ; Recover the payload high byte after subtype validation.
        AND 01FH                   ; Remove the environment subtype from its high index bits.
        LD D,A                     ; DE is now the untagged thirteen-bit environment index.
        LD A,D                     ; Environment cell zero is permanently reserved.
        OR E                       ; Test both bytes of the index.
        JP Z,RTINVERR              ; Reject a missing environment before address calculation.
        LD (RTENVIND),DE           ; Save the current environment for lexical lookup.
        LD HL,(RTENVIND)           ; Verify this index against the physical heap size.
        LD DE,(HCOUNT)             ; HCOUNT includes reserved cell zero.
        OR A                       ; Clear carry before unsigned bounds comparison.
        SBC HL,DE                  ; Every live environment index is strictly below HCOUNT.
        JP NC,RTINVERR             ; Reject a forged environment before dereferencing its cell.
        RET                        ; RTENVIND now names the active frame's current environment.

; Read and validate the link of RTBNDIND into RTLINKIX; no allocation occurs.
RTREADLK:
        LD HL,(RTBNDIND)           ; A zero cell index is the end of every lexical chain.
        LD A,H                     ; Check both bytes before address arithmetic.
        OR L                       ; The selected header or binding must be allocated.
        JP Z,RTINVERR              ; A missing cell cannot supply a requested lexical slot.
        LD DE,(HCOUNT)             ; Compare against the allocator's physical cell count.
        OR A                       ; Clear carry before the unsigned index comparison.
        SBC HL,DE                  ; A cell index is valid only when strictly below HCOUNT.
        JP NC,RTINVERR             ; Refuse an out-of-range index before dereferencing it.
        LD HL,(RTBNDIND)           ; Convert the checked thirteen-bit index to a byte offset.
        ADD HL,HL                  ; First doubling gives two bytes per heap cell.
        ADD HL,HL                  ; Second doubling gives four bytes per heap cell.
        LD DE,(RTHEAPB)              ; Load the checked heap base.
        ADD HL,DE                  ; HL addresses the first byte of the selected cell.
        JP C,RTINVERR              ; HINIT proved valid cell addresses cannot wrap.
        LD (RTCELADR),HL           ; Preserve the base for RTREADVL's CAR read.
        INC HL                     ; Advance across logical tag and payload low byte.
        INC HL                     ; Advance to payload high byte.
        INC HL                     ; The high byte of word one contains the physical tag.
        LD A,(HL)                  ; Word one's high byte combines CAR tag and link index.
        LD D,A                     ; Preserve link high bits while checking the CAR tag.
        AND 0E0H                   ; Separate the logical CAR tag from the next-cell index.
        OR A                       ; Tag zero is a scalar-valued binding or NIL parent.
        JP Z,RTLINKOK              ; The GC traces only the cell link for tag zero.
        CP 020H                    ; Tag one marks a reference-valued CAR.
        JP Z,RTLINKOK              ; The GC traces both that reference and the cell link.
        CP 060H                    ; Tag three marks an exact integer or binary16 CAR.
        JP NZ,RTINVERR             ; Other CAR tags are invalid in an environment cell.
RTLINKOK:
        LD A,D                     ; Recover the link's high byte after the tag check.
        AND 01FH                   ; Retain only the link's upper five index bits.
        LD D,A                     ; DE will contain the untagged next-cell index.
        DEC HL                     ; Move from the high link byte to its low byte.
        LD E,(HL)                  ; Read the low eight bits of the next-cell index.
        LD (RTLINKIX),DE             ; Publish the complete thirteen-bit link for lexical lookup.
        RET                        ; The selected cell's CAR remains available at RTCELADR.
