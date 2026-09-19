;=============================================================================
;  Skate M9 pair and list services
;=============================================================================

;  PURPOSE
;  -------
;  Construct and inspect ordinary or escaped Scheme pairs.

;  PUBLIC INTERFACE
;  ----------------
;
;  Every entry receives DE = a rooted packet base and BC = its argument count.
;  The packet has the execution ABI's environment and callee headers, followed
;  by four-byte value slots. Success returns A:HL as one tagged value. Errors
;  terminate through RTERROR; IX, IY and SP remain under the execution ABI.
;
;  RTCONSP  two values; allocates one ordinary or two escaped cells.
;  RTPAIRCA   one pair; returns its CAR.
;  RTPAIRCD   one pair; returns its CDR.
;  RTPAIRP one value; returns #t only for a pair anchor.
;  RTNULLP one value; returns #t only for NIL.
;  RTEQVAL    two values; compares logical tags and payloads.
;  RTLIST  zero or more values; allocates a fresh proper list.
;=============================================================================

; Construct a pair from two already evaluated, rooted arguments.
RTCONSP:
        CALL RTSTKCHK              ; Pair construction may enter the collector.
        CALL RTCHKPK               ; Prove the complete argument packet is rooted.
        CALL RTARGTWO                ; A constructor must receive exactly two values.
        LD HL,(RTPACKET)           ; Argument zero starts after two header slots.
        LD DE,8                    ; Each header or argument slot occupies four bytes.
        ADD HL,DE                  ; HL now points at CAR's tag byte.
        LD (RTCARPTR),HL            ; Keep its checked address for the value copy.
        LD DE,4                    ; CDR immediately follows CAR in this packet.
        ADD HL,DE                  ; HL now points at CDR's tag byte.
        LD (RTCDRPTR),HL            ; Keep its checked address for the value copy.
        CALL RTGETCAR               ; Copy the CAR tag and payload into runtime scratch.
        CALL RTGETCDR               ; Copy the CDR tag and payload into runtime scratch.
        JP RTMAKEPR                 ; Allocate, initialize and publish the pair.

; Return the CAR of one checked pair argument.
RTPAIRCA:
        CALL RTSTKCHK              ; Leave room for bounded validation helpers.
        CALL RTCHKPK               ; Validate all staged values before reading one.
        CALL RTARGONE                ; CAR requires exactly one argument.
        CALL RTGETARG               ; Return the argument as A:HL for pair decoding.
        CALL RTPAIRCK               ; Validate the pair anchor and locate its fields.
        JP C,RTTYERR               ; A nonpair value is a language type error.
        LD HL,(RTPAIRAD)           ; The anchor's first word always stores the CAR payload.
        LD E,(HL)                  ; Preserve the low payload byte.
        INC HL                     ; Advance to the payload's high byte.
        LD D,(HL)                  ; DE is the complete CAR payload.
        EX DE,HL                   ; Return that payload in HL.
        LD (RTGETPAY),HL           ; Save CAR payload while reading escaped metadata.
        LD A,(RTPHYTAG)             ; The anchor tag contains the CAR tag for an ordinary pair.
        CP 0E0H                    ; Escaped pairs store both logical tags in their auxiliary.
        JP Z,RTCARDEC               ; Select the escaped metadata path when physical tag is seven.
        SRL A                      ; Shift physical bits 15..13 into logical tag bits 2..0.
        SRL A                      ; Continue decoding the ordinary CAR tag.
        SRL A                      ; The physical tag's low five bits are not involved.
        SRL A                      ; Four shifts leave one tag bit in bit zero.
        SRL A                      ; Complete the five-bit shift from physical to logical tag.
        RET                        ; A:HL now contains the exact stored CAR value.
RTCARDEC:
        LD HL,(RTAUXADR)            ; The escaped metadata byte sits in auxiliary word one.
        INC HL                     ; Skip CDR payload low byte.
        INC HL                     ; Skip CDR payload high byte.
        LD A,(HL)                  ; Bits 5..3 hold the logical CAR tag.
        SRL A                      ; Move the high tag field towards bit zero.
        SRL A                      ; Continue shifting the three-bit CAR tag.
        SRL A                      ; A now contains the CAR tag in bits 2..0.
        AND 7                      ; Remove all remaining metadata bits.
        LD HL,(RTGETPAY)           ; Restore the payload saved before reading metadata.
        RET                        ; Return the escaped pair's exact CAR value.

; Return the CDR of one checked pair argument.
RTPAIRCD:
        CALL RTSTKCHK              ; Leave room for bounded validation helpers.
        CALL RTCHKPK               ; Validate all staged values before reading one.
        CALL RTARGONE                ; CDR requires exactly one argument.
        CALL RTGETARG               ; Return the argument as A:HL for pair decoding.
        CALL RTPAIRCK               ; Validate the pair anchor and locate its fields.
        JP C,RTTYERR               ; A nonpair value is a language type error.
        LD A,(RTPHYTAG)             ; Ordinary pairs encode CDR as a pair index or zero.
        CP 0E0H                    ; Escaped pairs store the complete CDR value in auxiliary.
        JP Z,RTCDRESC               ; Decode its payload and logical tag separately.
        LD HL,(RTPAIRAD)           ; Locate the ordinary pair's packed tag/link word.
        INC HL                     ; Skip CAR payload low byte.
        INC HL                     ; Skip CAR payload high byte.
        LD E,(HL)                  ; Read the CDR index's low eight bits.
        INC HL                     ; Advance to the index high bits and CAR tag.
        LD A,(HL)                  ; Read the packed high byte.
        AND 1FH                    ; Remove the CAR tag, leaving CDR index bits 12..8.
        LD D,A                     ; DE is now the complete thirteen-bit pair index.
        LD A,D                     ; Test both bytes for the zero/NIL sentinel.
        OR E                       ; A zero link represents the empty list.
        JP Z,RTNILVAL              ; Return the canonical tagged NIL value.
        LD H,D                     ; A nonzero link is a REF/PAIR payload.
        LD L,E                     ; The pair subtype is zero, so no subtype bits are added.
        LD A,1                     ; Logical tag one denotes a heap reference.
        RET                        ; Return REF/PAIR at the stored CDR index.
RTCDRESC:
        LD HL,(RTAUXADR)            ; The auxiliary's first word stores the CDR payload.
        LD E,(HL)                  ; Read its low byte.
        INC HL                     ; Advance to payload high byte.
        LD D,(HL)                  ; DE is the complete CDR payload.
        LD (RTGETPAY),DE           ; Preserve it while decoding the metadata byte.
        INC HL                     ; Skip to auxiliary word one's low byte.
        LD A,(HL)                  ; Read both logical tags and reserved bits.
        AND 7                      ; Bits 2..0 are the CDR tag.
        LD HL,(RTGETPAY)           ; Restore its payload.
        RET                        ; Return the escaped pair's exact CDR value.
RTNILVAL:
        XOR A                      ; NIL has logical scalar tag zero.
        LD HL,0FE02H               ; FE02H is the canonical empty-list payload.
        RET                        ; Return the ordinary pair's NIL terminator.

; Report whether one value is the canonical NIL immediate.
RTNULLP:
        CALL RTSTKCHK              ; Keep helper depth within the native-stack guard.
        CALL RTCHKPK               ; Validate all staged values before reading one.
        CALL RTARGONE                ; null? takes exactly one value.
        CALL RTGETARG               ; Load its logical tag and payload.
        OR A                       ; A zero tag is necessary for NIL.
        JP NZ,RTFALSE              ; References and exact integers are not NIL.
        LD DE,0FE02H               ; Compare against the canonical NIL payload.
        OR A                       ; Clear carry before subtracting the tagged payload.
        SBC HL,DE                  ; Equality leaves Z set.
        JP Z,RTTRUE                ; Only scalar FE02H denotes NIL.
        JP RTFALSE                 ; Other scalar immediates are not the empty list.

; Report whether one value names a valid pair anchor.
RTPAIRP:
        CALL RTSTKCHK              ; Keep helper depth within the native-stack guard.
        CALL RTCHKPK               ; Validate all staged values before reading one.
        CALL RTARGONE                ; pair? takes exactly one value.
        CALL RTGETARG               ; Load its logical tag and payload.
        CALL RTPAIRCK               ; Carry distinguishes a valid nonpair from a pair.
        JP C,RTFALSE               ; Numbers, strings, symbols and procedures are not pairs.
        JP RTTRUE                  ; The helper has validated a nonzero pair anchor.

; Compare the two values by representation identity: both tag and payload.
RTEQVAL:
        CALL RTSTKCHK              ; Keep helper depth within the native-stack guard.
        CALL RTCHKPK               ; Validate every slot, including both operands.
        CALL RTARGTWO                ; eq? takes exactly two values.
        LD HL,(RTPACKET)           ; Argument zero begins at packet offset eight.
        LD DE,8                    ; Skip environment and callee headers.
        ADD HL,DE                  ; HL points at the first logical tag.
        LD A,(HL)                  ; Save its logical tag.
        LD (RTCARTAG),A             ; Reuse pair scratch after packet validation.
        INC HL                     ; Read payload low byte.
        LD E,(HL)                  ; Preserve the low byte.
        INC HL                     ; Read payload high byte.
        LD D,(HL)                  ; DE is the complete first payload.
        LD (RTCARVAL),DE            ; Save it while locating the second argument.
        LD HL,(RTPACKET)           ; Reload the packet base.
        LD DE,12                   ; Argument one begins at offset twelve.
        ADD HL,DE                  ; HL points at the second logical tag.
        LD A,(HL)                  ; Compare logical tags first.
        LD B,A                     ; Keep the second tag while loading the first.
        LD A,(RTCARTAG)             ; Recover argument zero's tag.
        CP B                       ; Equal tags are necessary for eq?.
        JP NZ,RTFALSE              ; A tag difference proves the values are distinct.
        INC HL                     ; Read payload low byte.
        LD E,(HL)                  ; Preserve the low byte.
        INC HL                     ; Read payload high byte.
        LD D,(HL)                  ; DE is argument one's complete payload.
        LD HL,(RTCARVAL)            ; Load argument zero's payload.
        OR A                       ; Clear carry before comparing the two words.
        SBC HL,DE                  ; Equality means both tagged values are identical.
        JP Z,RTTRUE                ; Matching tag and payload means true.
        JP RTFALSE                 ; Any payload difference means false.

; Construct a fresh proper list by consing arguments from right to left.
RTLIST:
        CALL RTSTKCHK              ; Each list cell may enter the collector.
        CALL RTCHKPK               ; Validate all staged arguments before construction.
        LD HL,(RTPACKET)           ; The callee slot is an unused rooted accumulator.
        LD DE,4                    ; It follows the environment slot.
        ADD HL,DE                  ; Keep this address rooted across every allocation.
        LD (RTCDRPTR),HL            ; The packet begins with NIL in this slot.
        LD (HL),0                  ; The generic M10 path stored the primitive callee here.
        INC HL                     ; Replace that callee tag with the rooted NIL accumulator.
        LD (HL),2                  ; NIL payload low byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),0FEH               ; Complete FE02, the proper-list terminator.
        INC HL                     ; Keep the collector padding canonical as well.
        LD (HL),0                  ; The accumulator slot is now a valid rooted value.
        LD HL,(RTPKARGC)           ; An empty list needs no cell allocation.
        LD A,H                     ; Test the full argument count.
        OR L                       ; Zero arguments return the initial NIL accumulator.
        JP Z,RTLISTDN              ; The common epilogue loads that rooted value.
        DEC HL                     ; Start with the final argument.
        LD (RTLISTIX),HL           ; Each pass moves one argument toward index zero.
RTLISTLP:
        LD HL,(RTLISTIX)           ; Convert this argument index to a byte offset.
        ADD HL,HL                  ; First doubling gives two bytes per index.
        ADD HL,HL                  ; Second doubling gives the four-byte root-slot stride.
        LD DE,8                    ; Arguments begin after the two packet headers.
        ADD HL,DE                  ; HL is the argument's offset within the packet.
        LD DE,(RTPACKET)           ; Load the already validated packet base.
        ADD HL,DE                  ; The resulting address names this rooted argument.
        LD (RTCARPTR),HL            ; RTGETCAR copies its tag and payload before allocation.
        CALL RTGETCAR               ; Prepare the next list element as CAR.
        LD HL,(RTCDRPTR)            ; The accumulator is the rooted CDR value.
        LD A,(HL)                  ; Copy its logical tag.
        LD (RTCDRTAG),A             ; Preserve the tag while reading its payload.
        INC HL                     ; Advance to payload low byte.
        LD E,(HL)                  ; Read the low payload byte.
        INC HL                     ; Advance to payload high byte.
        LD D,(HL)                  ; DE now contains the accumulator payload.
        LD (RTCDRVAL),DE            ; Save it for the common pair constructor.
        CALL RTMAKEPR               ; A NIL or pair CDR always uses one ordinary cell.
        PUSH AF                    ; Preserve the returned tag across the rooted-slot write.
        PUSH HL                    ; Preserve the returned payload across address calculation.
        LD HL,(RTCDRPTR)            ; Replace the accumulator only after the pair is complete.
        POP DE                     ; DE now holds the new pair payload.
        POP AF                     ; A now holds its logical reference tag.
        LD (HL),A                  ; Publish the new accumulator's logical tag.
        INC HL                     ; Advance to its payload low byte.
        LD (HL),E                  ; Store the low payload byte.
        INC HL                     ; Advance to its payload high byte.
        LD (HL),D                  ; Store the high payload byte.
        INC HL                     ; Advance to the slot's reserved padding byte.
        LD (HL),0                  ; Keep the collector's root-slot padding canonical.
        LD HL,(RTLISTIX)           ; Check whether argument zero has just been consumed.
        LD A,H                     ; Test both bytes without modifying the index.
        OR L                       ; A zero index completes the list.
        JP Z,RTLISTDN              ; The rooted accumulator now contains the complete list.
        DEC HL                     ; Move to the preceding source argument.
        LD (RTLISTIX),HL           ; Save the next index before the following allocation.
        JP RTLISTLP                ; Build the list from right to left.
RTLISTDN:
        LD HL,(RTCDRPTR)            ; Return the accumulator rooted in the packet's callee slot.
        LD A,(HL)                  ; Read the result tag.
        INC HL                     ; Read payload low byte.
        LD E,(HL)                  ; Preserve it in E.
        INC HL                     ; Read payload high byte.
        LD D,(HL)                  ; DE is the complete list payload.
        EX DE,HL                   ; Return the payload in HL.
        RET                        ; The caller may now discard this primitive packet.

; Load the tagged values addressed by RTCARPTR and RTCDRPTR into scratch.
RTGETCAR:
        LD HL,(RTCARPTR)            ; The pointer names a checked four-byte value slot.
        LD A,(HL)                  ; Read the logical tag before its payload.
        LD (RTCARTAG),A             ; Save CAR's tag through the allocation attempt.
        INC HL                     ; Advance to payload low byte.
        LD E,(HL)                  ; Preserve payload low byte.
        INC HL                     ; Advance to payload high byte.
        LD D,(HL)                  ; DE is the complete CAR payload.
        LD (RTCARVAL),DE            ; Keep it until the reserved cell is initialized.
        RET                        ; No input root or packet state was changed.
RTGETCDR:
        LD HL,(RTCDRPTR)            ; The pointer names a checked four-byte value slot.
        LD A,(HL)                  ; Read the logical tag before its payload.
        LD (RTCDRTAG),A             ; Save CDR's tag through the allocation attempt.
        INC HL                     ; Advance to payload low byte.
        LD E,(HL)                  ; Preserve payload low byte.
        INC HL                     ; Advance to payload high byte.
        LD D,(HL)                  ; DE is the complete CDR payload.
        LD (RTCDRVAL),DE            ; Keep it until the reserved cell is initialized.
        RET                        ; No input root or packet state was changed.

; Count and validate the final apply list without allocating or mutating roots.
RTAPCNTL:
        LD A,(RTAPLTAG)            ; NIL is the only scalar that may terminate the list.
        OR A                       ; A nonzero tag must name a pair reference.
        JP NZ,RTAPCREF             ; Follow a pair and continue the bounded count pass.
        LD HL,(RTAPLLST)           ; Compare the scalar payload with canonical NIL.
        LD DE,0FE02H               ; FE02 is the sole proper-list terminator.
        OR A                       ; Clear carry before the exact payload comparison.
        SBC HL,DE                  ; Equality leaves Z set for a complete proper list.
        RET Z                      ; The count in RTAPCNT is ready for packet reservation.
        JP RTTYERR                 ; A scalar tail other than NIL is an improper list.
RTAPCREF:
        CP 1                       ; Pair anchors are logical references with subtype zero.
        JP NZ,RTTYERR              ; Integers, strings and other references are improper tails.
        LD HL,(RTAPLLST)           ; Present the pair value to the checked pair decoder.
        CALL RTPAIRCK              ; Bounds and physical pair metadata are validated here.
        JP C,RTTYERR               ; A nonpair reference is a language type error.
        CALL RTAPCDR               ; Read the next logical list value without allocation.
        LD (RTAPLTAG),A            ; Continue from the decoded CDR on the next iteration.
        LD (RTAPLLST),HL           ; The pair remains rooted by the original apply packet.
        LD HL,(RTAPCNT)            ; Increment only after the complete pair passed validation.
        INC HL                     ; One more list element will become one packet argument.
        LD (RTAPCNT),HL            ; Preserve the count across the capacity comparison.
        LD DE,510                  ; Match the compiler's maximum rooted application arity.
        OR A                       ; Clear carry before comparing the unsigned count.
        SBC HL,DE                  ; Counts above the bound cannot fit a generated packet.
        JP C,RTAPCNTL              ; Continue while the proper list remains within capacity.
        JP Z,RTAPCNTL              ; Exactly 510 values is valid; the next element is not.
        JP RTCAPERR                ; This also terminates cyclic lists deterministically.

; Copy one validated list element into the next new-packet argument slot.
RTAPFILL:
        LD A,(RTAPLTAG)            ; Every counted element must still be a pair anchor.
        CP 1                       ; A proper list cannot expose a scalar before its count ends.
        JP NZ,RTINVERR             ; Any mismatch indicates corruption between the two passes.
        LD HL,(RTAPLLST)           ; Decode the current pair's CAR and CDR.
        CALL RTPAIRCK              ; Recheck the anchor before reading its fields.
        JP C,RTINVERR              ; The count pass already proved this reference was a pair.
        CALL RTAPCAR               ; Return the CAR's logical tag and payload in A:HL.
        LD (RTAPVTAG),A            ; Preserve the value while calculating its destination.
        LD (RTAPVVAL),HL           ; Preserve the value before decoding the pair's CDR.
        LD HL,(RTAPDST)            ; The destination is a four-byte rooted packet slot.
        LD A,(RTAPVTAG)            ; Copy the CAR tag into the new argument slot.
        LD (HL),A                  ; Publish the logical tag before its payload bytes.
        INC HL                     ; Advance to payload low byte.
        LD DE,(RTAPVVAL)           ; Restore the CAR payload.
        LD (HL),E                  ; Store payload low.
        INC HL                     ; Advance to payload high byte.
        LD (HL),D                  ; Complete the copied argument value.
        INC HL                     ; Advance to the reserved padding byte.
        LD (HL),0                  ; Keep the packet slot valid for the collector.
        CALL RTAPCDR               ; Advance the source list after the value is rooted.
        LD (RTAPLTAG),A            ; The next iteration consumes this CDR.
        LD (RTAPLLST),HL           ; The original apply packet still roots the list graph.
        LD HL,(RTAPLEFT)           ; Consume the element copied by this iteration.
        DEC HL                     ; The underflow case is impossible after the count pass.
        LD (RTAPLEFT),HL           ; Preserve the remaining element count.
        LD A,H                     ; Test whether the final element was just copied.
        OR L                       ; Zero selects the proper-list completion check.
        JP Z,RTAPFEND              ; No destination increment is needed after the last slot.
        LD HL,(RTAPDST)            ; Advance to the next packet argument slot.
        LD DE,4                    ; Every tagged value occupies one four-byte root slot.
        ADD HL,DE                  ; A wrapped root pointer indicates corrupted runtime state.
        JP C,RTINVERR              ; Do not write outside the staged packet on corruption.
        LD (RTAPDST),HL            ; Publish the next destination before another pair decode.
        JP RTAPFILL                ; Continue until every counted list element is copied.
RTAPFEND:
        LD A,(RTAPLTAG)            ; The two passes must finish at canonical NIL together.
        OR A                       ; A reference here would contradict the counted length.
        JP NZ,RTINVERR             ; Refuse to dispatch a packet with a mismatched source list.
        LD HL,(RTAPLLST)           ; Check the final scalar payload as an invariant.
        LD DE,0FE02H               ; Proper lists terminate at FE02.
        OR A                       ; Clear carry before comparing the payload words.
        SBC HL,DE                  ; Equality leaves Z set for the expected terminator.
        JP NZ,RTINVERR             ; A changed or malformed list cannot reach the target.
        RET                        ; The staged packet is complete and fully rooted.

; Decode a validated pair's CAR without requiring a one-value packet wrapper.
RTAPCAR:
        LD HL,(RTPAIRAD)           ; The anchor's first word stores the CAR payload.
        LD E,(HL)                  ; Preserve payload low.
        INC HL                     ; Advance to payload high.
        LD D,(HL)                  ; DE now contains the complete CAR payload.
        EX DE,HL                   ; Return the payload in HL after reading its tag.
        LD A,(RTPHYTAG)             ; Ordinary physical tags encode the CAR tag directly.
        CP 0E0H                    ; Escaped pairs keep both logical tags in the auxiliary.
        JP Z,RTAPCAUX              ; Read the escaped metadata when required.
        SRL A                      ; Move physical tag bits 15..13 into logical bits 2..0.
        SRL A                      ; Continue the five-bit physical-to-logical shift.
        SRL A
        SRL A
        SRL A
        RET                        ; A:HL is the exact stored CAR value.
RTAPCAUX:
        LD (RTAPVVAL),HL           ; Keep the payload while locating auxiliary metadata.
        LD HL,(RTAUXADR)           ; Auxiliary word one stores both logical field tags.
        INC HL                     ; Skip CDR payload low.
        INC HL                     ; Skip CDR payload high.
        LD A,(HL)                  ; Bits 5..3 are the escaped CAR's logical tag.
        SRL A                      ; Move the field down toward bit zero.
        SRL A
        SRL A
        AND 7                      ; Remove CDR and reserved metadata bits.
        LD HL,(RTAPVVAL)           ; Restore the CAR payload for the caller.
        RET                        ; Return the escaped CAR in the same value ABI.

; Decode a validated pair's CDR without allocating or changing packet roots.
RTAPCDR:
        LD A,(RTPHYTAG)            ; Ordinary pairs encode a pair-link or NIL in word one.
        CP 0E0H                    ; Escaped pairs store the complete CDR in their auxiliary.
        JP Z,RTAPCDAX              ; Select the metadata path for arbitrary CDR values.
        LD HL,(RTPAIRAD)           ; Locate the ordinary anchor's packed link word.
        INC HL                     ; Skip CAR payload low.
        INC HL                     ; Skip CAR payload high.
        LD E,(HL)                  ; Read CDR link low.
        INC HL                     ; Advance to link high and physical CAR tag.
        LD A,(HL)                  ; Remove the physical tag bits from the high link byte.
        AND 1FH                    ; Keep only the thirteen-bit pair index.
        LD D,A                     ; DE is now the complete ordinary CDR link.
        LD A,D                     ; A zero link is the canonical NIL sentinel.
        OR E                       ; Test both bytes of the link.
        JP Z,RTAPNIL               ; Return NIL when the ordinary link is zero.
        LD H,D                     ; Nonzero ordinary links are REF/PAIR payloads.
        LD L,E                     ; Preserve the thirteen-bit heap index.
        LD A,1                     ; Logical reference tag identifies the next pair.
        RET                        ; Return the ordinary CDR in the value ABI.
RTAPCDAX:
        LD HL,(RTAUXADR)           ; Auxiliary word zero stores the escaped CDR payload.
        LD E,(HL)                  ; Preserve payload low.
        INC HL                     ; Advance to payload high.
        LD D,(HL)                  ; DE now contains the complete escaped CDR payload.
        INC HL                     ; Auxiliary word one stores the logical CDR tag.
        LD A,(HL)                  ; Bits 2..0 identify the CDR's logical value tag.
        AND 7                      ; Remove CAR and reserved metadata bits.
        EX DE,HL                   ; Return the payload in HL alongside the tag in A.
        RET                        ; The CDR is now ready for the next count/fill iteration.
RTAPNIL:
        XOR A                      ; NIL uses the scalar logical tag.
        LD HL,0FE02H               ; Canonical empty-list payload.
        RET                        ; Return the proper-list terminator.


; Require exact unary or binary arity after RTCHKPK validates the packet.
RTARGONE:
        LD HL,(RTPKARGC)           ; Compare the staged count against one.
        LD DE,1                    ; Unary pair operations take one value.
        OR A                       ; Clear carry before unsigned subtraction.
        SBC HL,DE                  ; Zero means one argument; either sign means mismatch.
        JP NZ,RTARERR              ; Report the standard arity error before reading values.
        RET                        ; The checked packet has the required unary shape.
RTARGTWO:
        LD HL,(RTPKARGC)           ; Compare the staged count against two.
        LD DE,2                    ; Constructor and identity operations take two values.
        OR A                       ; Clear carry before unsigned subtraction.
        SBC HL,DE                  ; Zero means exactly two arguments.
        JP NZ,RTARERR              ; Reject missing or extra values through the shared error.
        RET                        ; The checked packet has the required binary shape.

; Require an empty argument list after RTCHKPK validates the packet.
RTARZERO:
        LD HL,(RTPKARGC)           ; A zero-argument primitive has no value slots.
        LD A,H                     ; Test both bytes of the supplied count.
        OR L                       ; Zero is the only accepted arity.
        JP NZ,RTARERR              ; Reject missing or extra values through the shared error.
        RET                        ; The checked packet has the required empty shape.

; Load argument zero from a checked unary packet as A:HL.
RTGETARG:
        LD HL,(RTPACKET)           ; Load the rooted packet base.
        LD DE,8                    ; Argument zero follows two four-byte headers.
        ADD HL,DE                  ; HL now points to its logical tag.
        LD A,(HL)                  ; Read the tag before moving to its payload.
        INC HL                     ; Advance to payload low byte.
        LD E,(HL)                  ; Preserve the low byte.
        INC HL                     ; Advance to payload high byte.
        LD D,(HL)                  ; DE holds the payload.
        EX DE,HL                   ; Return A:HL in the runtime value convention.
        RET                        ; The complete input remains rooted in its packet.

; Locate and validate A:HL as a pair; return DE=anchor address or carry if not.
RTPAIRCK:
        CP 1                       ; Only a reference value can be a pair.
        JP NZ,RTNOPAIR              ; All scalars and exact integers are nonpairs.
        LD A,H                     ; Reference subtype occupies payload bits 15..13.
        AND 0E0H                   ; Remove the thirteen-bit table or heap index.
        OR A                       ; Subtype zero denotes a pair anchor.
        JP Z,RTPAIRID               ; Validate its nonzero heap index.
        CP 20H                     ; Subtype one denotes an interned symbol.
        JP Z,RTNOPAIR               ; Symbols are valid references, but never pairs.
        CP 40H                     ; Subtype two denotes a closure.
        JP Z,RTNOPAIR               ; A procedure is not a pair.
        CP 60H                     ; Subtype three denotes an environment.
        JP Z,RTNOPAIR               ; An environment is not a pair.
        CP 80H                     ; Subtype four denotes an interned string.
        JP Z,RTNOPAIR               ; Strings are valid references, but never pairs.
        JP RTINVERR                ; Reserved reference subtypes indicate corrupt data.
RTPAIRID:
        LD A,H                     ; Recover the thirteen-bit pair index.
        AND 1FH                    ; Keep only payload bits 12..8.
        LD H,A                     ; HL is now the untagged cell index.
        LD A,H                     ; Pair references may not target reserved cell zero.
        OR L                       ; Test both bytes of the index.
        JP Z,RTINVERR              ; NIL is an immediate, never a REF/PAIR index.
        LD (RTPAIRIX),HL           ; Keep the index while checking the arena bound.
        LD DE,(HCOUNT)             ; HCOUNT includes reserved cell zero.
        OR A                       ; Clear carry before the unsigned bound check.
        SBC HL,DE                  ; A live cell index must be below HCOUNT.
        JP NC,RTINVERR             ; Reject a forged reference before forming its address.
        LD HL,(RTPAIRIX)           ; Convert the checked index to a four-byte byte offset.
        ADD HL,HL                  ; First doubling gives two bytes per cell index.
        ADD HL,HL                  ; Second doubling gives a four-byte cell offset.
        LD DE,(RTHEAPB)            ; Use the validated execution heap base.
        ADD HL,DE                  ; HL now addresses the physical pair anchor.
        JP C,RTINVERR              ; A valid initialized heap cannot wrap its cell address.
        LD (RTPAIRAD),HL           ; Save the anchor while inspecting its physical tag.
        INC HL                     ; Skip CAR payload low byte.
        INC HL                     ; Skip CAR payload high byte.
        LD E,(HL)                  ; Read physical word one's low byte.
        INC HL                     ; Advance to its high byte.
        LD D,(HL)                  ; DE is the physical tag and internal link.
        LD A,D                     ; The upper three bits identify the physical cell kind.
        AND 0E0H                   ; Extract ordinary, auxiliary or escaped tag.
        LD (RTPHYTAG),A             ; CAR and CDR decoders use the validated representation.
        CP 0E0H                    ; Escaped pairs point to a private auxiliary cell.
        JP Z,RTESCCHK               ; Validate its index, physical tag and logical tag fields.
        OR A                       ; Ordinary CAR tag zero is valid.
        JP Z,RTORDCHK               ; Check its CDR link before accepting the anchor.
        CP 20H                     ; Ordinary CAR tag one is a reference.
        JP Z,RTORDCHK               ; The collector validates its referent when tracing.
        CP 60H                     ; Ordinary CAR tag three is an exact integer or number.
        JP Z,RTORDCHK               ; No other ordinary physical tag is a valid pair anchor.
        JP RTINVERR                ; Reject closure, raw, auxiliary and reserved cells.
RTORDCHK:
        LD A,D                     ; The ordinary link shares word one with the CAR tag.
        AND 1FH                    ; Retain only the link index's high five bits.
        LD H,A                     ; HL becomes the thirteen-bit CDR pair index.
        LD L,E                     ; The word's low byte contains its low eight bits.
        LD A,H                     ; A zero link is NIL and needs no heap-bound check.
        OR L                       ; Test both bytes of the complete index.
        JP Z,RTPAIROK              ; The anchor is valid with a NIL CDR.
        LD DE,(HCOUNT)             ; Every nonzero link must name a physical arena cell.
        OR A                       ; Clear carry before comparing unsigned indices.
        SBC HL,DE                  ; Carry means the link is below HCOUNT.
        JP NC,RTINVERR             ; Reject an out-of-arena pair link.
        JP RTPAIROK                ; The ordinary anchor and CDR index are bounded.
RTESCCHK:
        LD A,D                     ; The escaped anchor's link is an auxiliary index.
        AND 1FH                    ; Remove physical tag bits from its high byte.
        LD H,A                     ; HL is now the thirteen-bit auxiliary index.
        LD L,E                     ; Preserve the link's low eight bits.
        LD A,H                     ; Escaped anchors require a nonzero auxiliary cell.
        OR L                       ; Test both bytes of that index.
        JP Z,RTINVERR              ; A missing auxiliary is malformed heap state.
        LD (RTAUXIDX),HL            ; Keep the index while checking its arena bound.
        LD DE,(HCOUNT)             ; HCOUNT includes cell zero.
        OR A                       ; Clear carry before the unsigned bound check.
        SBC HL,DE                  ; Every auxiliary index is below HCOUNT.
        JP NC,RTINVERR             ; Reject a forged auxiliary link before memory access.
        LD HL,(RTAUXIDX)            ; Convert the checked auxiliary index to its byte offset.
        ADD HL,HL                  ; First doubling gives a two-byte cell offset.
        ADD HL,HL                  ; Second doubling gives a four-byte cell offset.
        LD DE,(RTHEAPB)            ; Use the validated execution heap base.
        ADD HL,DE                  ; HL now addresses the auxiliary cell.
        JP C,RTINVERR              ; A valid initialized heap cannot wrap its cell address.
        LD (RTAUXADR),HL            ; Save the auxiliary address for CAR and CDR decoding.
        INC HL                     ; Skip CDR payload low byte.
        INC HL                     ; Skip CDR payload high byte.
        LD A,(HL)                  ; Auxiliary word one's low byte stores both logical tags.
        LD (RTMETALO),A             ; Preserve it while checking reserved bits.
        AND 0C0H                   ; Metadata bits 7..6 must remain zero.
        JP NZ,RTINVERR             ; Reject an auxiliary with nonzero reserved bits.
        INC HL                     ; Advance to the metadata word's high byte.
        LD A,(HL)                  ; Physical tag six has no other high-byte bits set.
        CP 0C0H                    ; Require C000H as the metadata word's upper byte.
        JP NZ,RTINVERR             ; Reject a non-auxiliary target or reserved upper bits.
        LD A,(RTMETALO)             ; Recover the CDR logical tag from bits 2..0.
        AND 7                      ; Isolate its three-bit value tag.
        CALL RTTAGCHK               ; Only scalar, reference and exact-integer tags are valid.
        LD A,(RTMETALO)             ; Recover the CAR logical tag from bits 5..3.
        SRL A                      ; Shift the CAR tag field towards bit zero.
        SRL A                      ; Continue extracting its three-bit value tag.
        SRL A                      ; Bits 2..0 now hold the CAR tag.
        AND 7                      ; Remove every remaining metadata bit.
        CALL RTTAGCHK               ; Reject malformed logical tags before returning the pair.
RTPAIROK:
        LD DE,(RTPAIRAD)           ; Return the checked anchor address to the caller.
        OR A                       ; Clear carry to mark a valid pair.
        RET                        ; The caller may decode either logical field.
RTNOPAIR:
        SCF                        ; Carry means the supplied value is not a pair.
        RET                        ; Predicates consume this result; car/cdr report a type error.

; Accept only the three logical value tags supported by the object format.
RTTAGCHK:
        OR A                       ; Scalar tag zero is valid.
        RET Z                       ; The caller's tag remains available in A.
        CP 1                       ; Reference tag one is valid.
        RET Z                       ; References are further checked when traced or dereferenced.
        CP 3                       ; Exact integer and binary16 values share tag three.
        RET Z                       ; No other logical tag may be stored in an escaped pair.
        JP RTINVERR                ; Corrupt metadata must not escape into Scheme code.

; Common allocation path for a pair whose tagged fields are in scratch.
RTMAKEPR:
        LD A,(RTCDRTAG)             ; NIL and pair references use the compact ordinary form.
        OR A                       ; Check for scalar tag zero first.
        JP NZ,RTCDRREF              ; A reference may still be an ordinary pair tail.
        LD HL,(RTCDRVAL)            ; Distinguish canonical NIL from every other scalar.
        LD DE,0FE02H               ; NIL is the only ordinary scalar CDR.
        OR A                       ; Clear carry before the payload comparison.
        SBC HL,DE                  ; Equality selects a zero ordinary link.
        JP Z,RTNILCDR               ; Reserve one cell and encode link zero.
        JP RTESCRES                ; Other scalar CDRs require the escaped representation.
RTCDRREF:
        CP 1                       ; Only a logical reference may name another pair.
        JP NZ,RTESCRES             ; Exact integers and other tags need an auxiliary cell.
        LD HL,(RTCDRVAL)            ; A REF/PAIR has subtype zero in the high payload bits.
        LD A,H                     ; Inspect the reference subtype before choosing a layout.
        AND 0E0H                   ; Remove the thirteen-bit heap index.
        OR A                       ; Zero identifies REF/PAIR rather than another reference.
        JP NZ,RTESCRES             ; Closures, environments, symbols and strings are arbitrary CDRs.
        LD A,1                     ; Validate this reference as an actual live pair anchor.
        CALL RTPAIRCK               ; The helper returns carry only for a nonpair subtype.
        JP C,RTINVERR              ; A payload encoded as REF/PAIR must name a real pair.
        LD HL,(RTCDRVAL)            ; Restore the ordinary CDR pair identity.
        LD A,H                     ; Remove any subtype bits before saving its index.
        AND 1FH                    ; Keep only the thirteen-bit pair index.
        LD H,A                     ; HL is the compact physical CDR link.
        LD (RTPAIRIX),HL           ; Preserve the link while reserving the new cell.
        JP RTORDRES                 ; A pair CDR needs only one ordinary cell.
RTNILCDR:
        LD HL,0                    ; NIL's ordinary CDR link is the zero sentinel.
        LD (RTPAIRIX),HL           ; Save that link for the common cell initializer.
RTORDRES:
        XOR A                      ; Clear the escaped-pair flag.
        LD (RTESCFLG),A             ; The allocation reserves one ordinary cell.
        LD BC,1                    ; Ordinary pairs occupy one four-byte cell.
        JP RTRESERV                 ; Use the shared rooted reservation path.
RTESCRES:
        LD A,1                     ; Non-NIL, nonpair CDRs need a private auxiliary cell.
        LD (RTESCFLG),A             ; The anchor will point to its completed auxiliary.
        LD BC,2                    ; Escaped pairs reserve anchor and auxiliary atomically.
RTRESERV:
        CALL RTROOTS               ; Refresh roots after every caller slot is fully initialized.
        LD HL,RTROOTDS             ; GRES scans active roots followed by global values.
        LD DE,2                    ; Keep both descriptor records in every collection.
        CALL GRES                  ; Collect and retry before removing any free cells.
        JP C,RTALLOC               ; Report exhaustion separately from heap corruption.
        CALL HPOP                  ; Consume the reserved anchor cell.
        JP C,RTINVERR              ; HPOP cannot fail after GRES granted this reservation.
        LD (RTNEWIDX),HL           ; Retain the public pair identity.
        LD (RTNEWADR),DE           ; Retain its checked four-byte heap address.
        LD A,(RTESCFLG)             ; Select the exact physical layout reserved above.
        OR A                       ; Zero means the pair occupies only its anchor.
        JP NZ,RTESCNEW              ; Escaped form also needs one auxiliary cell.
RTORDNEW:
        LD HL,(RTNEWADR)           ; Start writing the ordinary anchor's CAR payload.
        LD DE,(RTCARVAL)            ; Recover the tagged CAR payload saved before allocation.
        LD (HL),E                  ; Store its low byte.
        INC HL                     ; Advance to its high byte.
        LD (HL),D                  ; Complete CAR payload.
        INC HL                     ; Word one combines CAR tag and CDR pair index.
        LD DE,(RTPAIRIX)           ; NIL is zero; a pair CDR is its thirteen-bit index.
        LD (HL),E                  ; Store the low eight CDR-index bits.
        INC HL                     ; Advance to high index bits and physical CAR tag.
        LD A,D                     ; Recover the link's high index bits.
        AND 1FH                    ; Keep only physical link bits 12..8.
        LD D,A                     ; Preserve those bits while encoding the CAR tag.
        LD A,(RTCARTAG)             ; Logical CAR tag occupies physical bits 15..13.
        RLCA                       ; Begin shifting its three-bit tag into the high field.
        RLCA                       ; Continue the value-tag encoding.
        RLCA                       ; The supported tags are zero, one and three.
        RLCA                       ; Four rotations leave the tag near its physical position.
        RLCA                       ; Five rotations place the tag in bits 7..5.
        OR D                       ; Combine tag and high bits of the CDR index.
        LD (HL),A                  ; Publish the completed ordinary word one.
        CALL HDONE                 ; Close the one-cell reservation after initialization.
        JP C,RTINVERR              ; A fully consumed reservation must close successfully.
        JP RTPAIRVL                 ; Return the common REF/PAIR value.
RTESCNEW:
        CALL HPOP                  ; Consume the second reserved cell for escaped metadata.
        JP C,RTINVERR              ; The atomic two-cell reservation guarantees this pop.
        LD (RTAUXIDX),HL            ; Save the private auxiliary index.
        LD (RTAUXADR),DE            ; Save its four-byte heap address.
        LD HL,(RTNEWADR)           ; Write the escaped anchor's CAR payload first.
        LD DE,(RTCARVAL)            ; Recover the first tagged field's payload.
        LD (HL),E                  ; Store its low byte.
        INC HL                     ; Advance to its high byte.
        LD (HL),D                  ; Complete CAR payload.
        INC HL                     ; The anchor's word one stores an E000 auxiliary link.
        LD DE,(RTAUXIDX)            ; Load the private cell index.
        LD A,D                     ; Remove any bits outside the thirteen-bit link.
        AND 1FH                    ; Keep its high five index bits.
        OR 0E0H                    ; Physical tag seven identifies an escaped-pair anchor.
        LD D,A                     ; DE now contains the complete encoded anchor word.
        LD (HL),E                  ; Store the auxiliary index's low byte.
        INC HL                     ; Advance to its physical tag and high index bits.
        LD (HL),D                  ; Publish the escaped anchor's complete word one.
        LD HL,(RTAUXADR)            ; Initialize the auxiliary's complete logical CDR.
        LD DE,(RTCDRVAL)            ; Recover CDR payload without interpreting its type.
        LD (HL),E                  ; Store its low byte.
        INC HL                     ; Advance to CDR payload high byte.
        LD (HL),D                  ; Complete the payload.
        INC HL                     ; Word one packs both logical tags.
        LD A,(RTCARTAG)             ; Start with the logical CAR tag.
        ADD A,A                    ; Move it to metadata bits 1..0 temporarily.
        ADD A,A                    ; Continue shifting towards bits 5..3.
        ADD A,A                    ; Three shifts encode CAR tag * 8.
        LD B,A                     ; Keep the encoded CAR tag while loading CDR's tag.
        LD A,(RTCDRTAG)             ; Load the complete logical CDR tag.
        AND 7                      ; Keep only its three supported bits.
        OR B                       ; Combine CAR and CDR logical tags.
        LD (HL),A                  ; Store only tags in bits 5..0; bits 7..6 stay zero.
        INC HL                     ; Advance to metadata high byte.
        LD (HL),0C0H               ; C000H contains physical tag six and zero reserved bits.
        CALL HDONE                 ; Publish both fully initialized cells together.
        JP C,RTINVERR              ; A fully consumed reservation must close successfully.
RTPAIRVL:
        LD HL,(RTNEWIDX)           ; The language-visible identity is always the anchor index.
        LD A,1                     ; Logical tag one denotes a heap reference.
        RET                        ; Return REF/PAIR without exposing the auxiliary index.

; Return canonical boolean immediates shared by all predicates.
RTTRUE:
        XOR A                      ; Booleans are scalar immediates.
        LD HL,0FE01H               ; FE01H encodes true.
        RET                        ; Return #t as A:HL.
RTFALSE:
        XOR A                      ; Booleans are scalar immediates.
        LD HL,0FE00H               ; FE00H encodes false.
        RET                        ; Return #f as A:HL.
