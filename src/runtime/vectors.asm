; Mutable vector values and their collector support.
; A vector is tag seven and points at a managed class block.  The first byte
; stores the element count; every element then uses the same four-byte payload,
; tag and spare-byte shape as an argument packet.  The closure start map owns
; the block, while an odd bit in the persistent mark map identifies a vector.
; A=1 marks a vector root; A=0 classifies a queued allocation and traces it.
SRTVHOOK:
        LD (SRTCLOBJ),HL           ; Keep the queued object across bitmap probes.
        CP 1
        JP Z,SRTVMARK
        CALL SRTSSTA                ; Strings are leaves and need no traversal.
        RET NZ
        CALL SRTVSST                ; Test the vector marker on this allocation.
        JR Z,SRTVHCLS
        LD HL,(SRTCLOBJ)            ; Restore the object after SRTVSST's map lookup.
        CALL SRTMVEC                ; Trace every tagged vector element.
        RET
SRTVHCLS:
        JP SRTMCLOS                 ; The remaining managed allocation is a closure.
; Dispatch the vector primitive range selected by SRTPRIM.
SRTVEC:
        LD A,(SRTPID)              ; Read the zero-based vector operation kind.
        CP 39                      ; Kind thirty-nine is vector?.
        JP Z,SRTVTP                ; Test one value without raising a type error.
        CP 40                      ; Kind forty is make-vector.
        JP Z,SRTVMKV               ; Allocate a counted vector with an optional fill.
        CP 41                      ; Kind forty-one is the short vector constructor.
        JP Z,SRTVMAKE              ; Copy the bounded packet into a new vector.
        CP 42                      ; Kind forty-two is vector-length.
        JP Z,SRTVLEN               ; Return the stored element count.
        CP 43                      ; Kind forty-three is vector-ref.
        JP Z,SRTVREF               ; Read one checked element.
        JP SRTVSET                 ; The remaining kind is vector-set!.
; Return a boolean for vector? without exposing stale heap pointers.
SRTVTP:
        CALL SRTONE                ; Read the single predicate argument.
        CP 7                       ; Only the vector tag can select validation.
        JR NZ,SRTVFAL              ; Other values are ordinary non-vectors.
        CALL SRTVLD                ; Reject freed and interior vector addresses.
        JR C,SRTVFAL               ; A malformed tagged value is not a vector.
        XOR A                      ; Boolean results use the scalar tag.
        LD HL,0FE01H               ; Return canonical true.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the predicate result.
SRTVFAL:
        XOR A                      ; Boolean results use the scalar tag.
        LD HL,0FE00H               ; Return canonical false.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the predicate result.
; Allocate a vector whose length is an exact integer and whose fill is optional.
SRTVMKV:
        LD A,(SRTARGC)             ; make-vector accepts one or two arguments.
        CP 1                       ; Reject a missing length argument.
        JP C,SRTERROR
        CP 3                       ; Reject more than one optional fill value.
        JP NC,SRTERROR
        LD HL,SRTARGPK             ; Read the requested vector length.
        CALL SRTPVAL               ; Return its payload in HL and tag in A.
        CP 3                       ; The length must be an exact integer.
        JP NZ,SRTERROR
        LD A,H                     ; Only a small nonnegative count is supported.
        OR A
        JP NZ,SRTERROR
        LD A,L                     ; Preserve the checked count for allocation.
        CP 65                      ; Class 64 is the largest supported vector.
        JP NC,SRTERROR
        LD (SRTVREQ),A             ; Preserve the request across a collection retry.
        LD A,(SRTARGC)             ; Select the supplied fill only for arity two.
        CP 2
        JR Z,SRTVMKF               ; Read and retain the optional fill value.
        XOR A                      ; The default fill is the canonical false value.
        LD (SRTVFTAG),A
        LD HL,0FE00H               ; Store #f as the default payload.
        LD (SRTVFILL),HL
        JR SRTVMKA                 ; Allocate and initialise every element.
SRTVMKF:
        LD HL,SRTARGPK+4           ; The optional fill is the second packet value.
        CALL SRTPVAL               ; Recover its complete tagged representation.
        LD (SRTVFILL),HL           ; Keep the payload across class allocation.
        LD (SRTVFTAG),A            ; Keep the logical tag beside the payload.
SRTVMKA:
        CALL SRTVACL                ; The packet remains an exact root during GC.
        JP C,SRTERROR              ; Report exhaustion after one collection retry.
        CALL SRTVFIL               ; Fill the newly allocated vector block.
        LD A,7                      ; Tag seven identifies a vector value.
        LD HL,(SRTVOBJ)             ; Return the managed object address.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the new vector value.
; Construct a vector from the current packet, limited by the call packet size.
SRTVMAKE:
        LD A,(SRTARGC)             ; The short constructor accepts zero through seven.
        CP 8
        JP NC,SRTERROR
        LD (SRTVREQ),A             ; Preserve the request across a collection retry.
        CALL SRTVACL                ; Packet values remain roots across a retry.
        JP C,SRTERROR
        CALL SRTVPUT               ; Copy each payload and tag into the block.
        LD A,7                      ; Tag seven identifies a vector value.
        LD HL,(SRTVOBJ)             ; Return the managed object address.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the new vector value.
; Return the length of one checked vector.
SRTVLEN:
        LD A,(SRTARGC)             ; vector-length accepts exactly one argument.
        CP 1
        JP NZ,SRTERROR
        CALL SRTVGET                ; Validate the first packet value.
        JP C,SRTERROR
        LD A,(SRTVLENB)            ; Widen its count into an exact integer value.
        LD L,A
        LD H,0
        LD A,3                      ; Exact integers use logical tag three.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the length result.
; Read a vector element after validating the vector and its exact index.
SRTVREF:
        LD A,(SRTARGC)             ; vector-ref requires a vector and an index.
        CP 2
        JP NZ,SRTERROR
        CALL SRTVGET                ; Validate and retain the vector object.
        JP C,SRTERROR
        LD HL,SRTARGPK+4           ; The second packet value is the index.
        CALL SRTPVAL               ; Return its payload and tag.
        CALL SRTVIX                ; Check its range against the vector length.
        JP C,SRTERROR
        CALL SRTVADR               ; Compute the selected element address.
        LD E,(HL)                  ; Recover the element payload low byte.
        INC HL
        LD D,(HL)                  ; Recover the element payload high byte.
        INC HL
        LD A,(HL)                  ; Recover the element's logical tag.
        EX DE,HL                   ; Return the payload in the standard ABI.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the selected element.
; Replace a vector element and return the unspecified value.
SRTVSET:
        LD A,(SRTARGC)             ; vector-set! requires vector, index and value.
        CP 3
        JP NZ,SRTERROR
        CALL SRTVGET                ; Validate and retain the vector object.
        JP C,SRTERROR
        LD HL,SRTARGPK+4           ; The second packet value is the index.
        CALL SRTPVAL               ; Return its payload and tag.
        CALL SRTVIX                ; Check its range against the vector length.
        JP C,SRTERROR
        LD HL,SRTARGPK+8           ; The third packet value is the replacement.
        CALL SRTPVAL               ; Recover its complete tagged representation.
        LD (SRTVFILL),HL           ; Reuse fill scratch for the replacement payload.
        LD (SRTVFTAG),A            ; Reuse fill scratch for the replacement tag.
        CALL SRTVADR               ; Compute the selected element address.
        LD HL,(SRTVADR1)           ; Recover the selected element address.
        LD DE,(SRTVFILL)           ; Load the replacement payload.
        LD (HL),E                  ; Publish the payload low byte.
        INC HL
        LD (HL),D                  ; Publish the payload high byte.
        INC HL
        LD A,(SRTVFTAG)            ; Publish the logical element tag.
        LD (HL),A
        INC HL
        XOR A                      ; The spare byte carries no state.
        LD (HL),A
        XOR A                      ; Return the unspecified scalar value.
        LD HL,0FE04H
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the mutation result.
; Validate the vector in the first packet record and retain its length.
SRTVGET:
        LD HL,SRTARGPK             ; The vector is always the first argument.
        CALL SRTPVAL               ; Return its payload and tag.
        CP 7                       ; Only the vector tag can select this helper.
        JR NZ,SRTVBAD              ; A non-vector is an operation type error.
        CALL SRTVLD                ; Validate ownership, class and extent.
        JR C,SRTVBAD               ; Return carry for the primitive caller.
        LD (SRTVOBJ),HL            ; Retain the exact vector start.
        LD A,(HL)                  ; Read the vector's bounded element count.
        LD (SRTVLENB),A            ; Keep it for index checks.
        OR A                       ; Clear carry for a successful helper return.
        RET
SRTVBAD:
        SCF                         ; The caller converts this into RUNTIME ERROR.
        RET
; Validate an exact, nonnegative byte index against SRTVLENB.
SRTVIX:
        CP 3                       ; Index values must be exact integers.
        JR NZ,SRTVBAD
        LD A,H                     ; Negative and wide indexes are out of range.
        OR A
        JR NZ,SRTVBAD
        LD A,L                     ; Compare the low byte with the vector count.
        LD A,(SRTVLENB)
        LD B,A                     ; Compare against the stored vector length.
        LD A,L                     ; Restore the index after loading the count.
        CP B
        JR NC,SRTVBAD
        LD (SRTVINDX),A            ; Retain the checked index for address calculation.
        OR A                       ; Clear carry for a successful helper return.
        RET
; Compute the address of the indexed element in SRTVOBJ.
SRTVADR:
        LD A,(SRTVINDX)            ; Four bytes represent one vector element.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        INC HL                     ; Skip the vector length byte.
        LD DE,(SRTVOBJ)            ; Add the vector object base.
        ADD HL,DE
        LD (SRTVADR1),HL           ; Retain the address across packet loads.
        RET
; Fill a vector with the retained SRTVFILL value.
SRTVFIL:
        LD HL,(SRTVOBJ)            ; Publish the count before filling elements.
        LD A,(SRTVREQ)
        LD (HL),A
        INC HL
        LD (SRTVPTR),HL            ; Keep the element cursor in scratch.
        LD A,(SRTVREQ)             ; Copy the bounded element count.
        LD (SRTVLEFT),A
SRTVFLP:
        LD A,(SRTVLEFT)            ; Stop after every element has been written.
        OR A
        RET Z
        LD HL,(SRTVPTR)            ; Recover the current element address.
        LD DE,(SRTVFILL)           ; Copy the fill payload.
        LD (HL),E                  ; Store the payload low byte.
        INC HL
        LD (HL),D                  ; Store the payload high byte.
        INC HL
        LD A,(SRTVFTAG)            ; Store the fill tag.
        LD (HL),A
        INC HL
        XOR A                      ; The fourth byte is unused by vector values.
        LD (HL),A
        INC HL
        LD (SRTVPTR),HL            ; Advance to the next element.
        LD A,(SRTVLEFT)
        DEC A
        LD (SRTVLEFT),A
        JR SRTVFLP
; Copy the packet values into a newly allocated vector.
SRTVPUT:
        LD HL,(SRTVOBJ)            ; Publish the count before copying elements.
        LD A,(SRTVREQ)
        LD (HL),A
        INC HL
        LD (SRTVPTR),HL            ; Keep the destination cursor in scratch.
        LD HL,SRTARGPK             ; The packet begins at its first value record.
        LD (SRTVPKT),HL            ; Keep the source cursor beside the destination.
        LD A,(SRTVREQ)             ; Copy the bounded argument count.
        LD (SRTVLEFT),A
SRTVPLP:
        LD A,(SRTVLEFT)            ; Stop after every argument has been copied.
        OR A
        RET Z
        LD HL,(SRTVPKT)            ; Recover the current packet record.
        LD E,(HL)                  ; Read its payload low byte.
        INC HL
        LD D,(HL)                  ; Read its payload high byte.
        INC HL
        LD A,(HL)                  ; Read its logical tag.
        INC HL
        INC HL                     ; Skip the packet publication flag.
        LD (SRTVPKT),HL            ; Advance the source cursor by four bytes.
        LD HL,(SRTVPTR)            ; Recover the destination element address.
        LD (HL),E                  ; Store the payload low byte.
        INC HL
        LD (HL),D                  ; Store the payload high byte.
        INC HL
        LD (HL),A                  ; Store the logical tag.
        INC HL
        XOR A                      ; The vector spare byte carries no state.
        LD (HL),A
        INC HL
        LD (SRTVPTR),HL            ; Advance to the next destination element.
        LD A,(SRTVLEFT)
        DEC A
        LD (SRTVLEFT),A
        JR SRTVPLP
; Allocate a vector block and set its ownership and type marker.
SRTVACL:
        CALL SRTVSZ                ; Derive the rounded class from the request.
        CALL SRTCLALC              ; Reuse a class block before growing the pool.
        JR NC,SRTVAK               ; Carry clear means a block is reserved.
        CALL SRTGC                  ; Reclaim dead managed objects once.
        CALL SRTVSZ                ; Recompute the request-sized class after collection.
        CALL SRTCLALC              ; Retry the same class after sweeping.
        RET C                      ; Preserve the capacity failure for the caller.
SRTVAK:
        LD (SRTVOBJ),HL            ; Retain the exact block start.
        LD (SRTOBJ),HL             ; SRTCLNEW publishes the common start bitmap.
        CALL SRTCLNEW               ; Publish the allocation start in the map.
        CALL SRTVSMK                ; Mark the block as a vector, not a closure.
        LD HL,(SRTVOBJ)            ; Return the block base to the constructor.
        OR A                       ; Clear carry after successful publication.
        RET

; Compute a rounded four-byte class for one-byte count plus four-byte values.
SRTVSZ:
        LD A,(SRTVREQ)             ; Read the constructor count, not tracer scratch.
        LD L,A
        LD H,0
        ADD HL,HL                  ; Multiply the count by four.
        ADD HL,HL
        INC HL                     ; Add the count byte at the front of the block.
        LD BC,3                    ; Round the one-mod-four size upward.
        ADD HL,BC
        LD A,L
        AND 0FCH                   ; Preserve H while clearing the low residue.
        LD L,A
        LD (SRTCLSZ),HL            ; The class allocator consumes the rounded size.
        SRL H
        RR L
        SRL H
        RR L
        DEC L                      ; Four bytes per class index, zero based.
        LD A,L
        LD (SRTCLIDX),A            ; Publish the selected class for SRTCLALC.
        RET

; Validate a tag-seven vector pointer and return its object base in HL.
SRTVLD:
        LD (SRTCLOBJ),HL           ; Preserve the candidate across range checks.
        LD DE,SRTHEAP              ; Reject values below the managed pool.
        OR A
        SBC HL,DE
        JP C,SRTVBD
        LD HL,(SRTCLOBJ)            ; Vector starts are aligned to four bytes.
        LD A,L
        AND 3
        JP NZ,SRTVBD
        LD DE,(SRTHEAPP)            ; Reject values at or above the pool end.
        OR A
        SBC HL,DE
        JP NC,SRTVBD
        CALL SRTVSST                 ; Require the exact vector marker bit.
        JP Z,SRTVBD
        LD HL,(SRTCLOBJ)            ; Find the owning logical closure page.
        LD (SRTCLBAS),HL
        CALL SRTCLFND
        LD A,(SRTCLPGI)
        CP 80H
        JP NC,SRTVBD                ; A missing owner cannot describe a vector.
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)                   ; The owner byte is class index plus one.
        CP 1
        JP C,SRTVBD
        CP 42H                      ; Class 64 is the two-page upper limit.
        JP NC,SRTVBD
        DEC A
        LD (SRTCLIDX),A
        CALL SRTCLGET                ; Recover the physical page base.
        LD A,(SRTCLIDX)              ; Rebuild the exact class extent from its owner.
        INC A
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD (SRTCLSZ),HL
        LD HL,(SRTCLOBJ)
        LD DE,(SRTCLPGA)
        OR A
        SBC HL,DE                   ; Compute the within-page object offset.
        JP C,SRTVBD
        LD A,(SRTCLIDX)
        CP 40H
        JR Z,SRTV2PG                ; The 260-byte class may start only at zero.
        LD A,H
        OR A
        JP NZ,SRTVBD                ; A one-page class cannot cross its page.
        JR SRTVOCHK
SRTV2PG:
        LD A,H
        OR L
        JP NZ,SRTVBD                ; The two-page class has one legal object start.
SRTVOCHK:
        LD HL,(SRTCLOBJ)            ; Read the length only after ownership is proven.
        LD A,(HL)
        LD (SRTVLENB),A
        CP 65
        JP NC,SRTVBD                ; The stored count must fit the supported class.
        LD L,A
        LD H,0
        ADD HL,HL                  ; Calculate count times four.
        ADD HL,HL
        INC HL                     ; Include the length byte in the used extent.
        LD DE,(SRTCLSZ)
        OR A
        SBC HL,DE
        JR C,SRTVGOOD               ; A smaller used extent fits the class block.
        JR Z,SRTVGOOD               ; An exact class-sized vector is also valid.
        JP SRTVBD                   ; A larger used extent is malformed.
SRTVGOOD:
        LD HL,(SRTCLOBJ)
        OR A
        RET
SRTVBD:
        SCF                         ; The candidate is not a live vector start.
        RET

; Mark a vector allocation as a reachable queued leaf/container.
SRTVMARK:
        LD (SRTCLOBJ),HL           ; Keep the object base for map operations.
        CALL SRTVLD                ; Validate before setting any mark bit.
        RET C
        CALL SRTCLSEE              ; A previously queued vector needs no duplicate.
        RET NZ
        CALL SRTCLSET              ; Set the shared closure mark map.
        LD DE,(SRTMSTK)            ; Queue the object for element tracing.
        LD A,D
        CP 0D4H
        JR NC,SRTVMFUL             ; Defer children when the bounded queue is full.
        LD HL,(SRTCLOBJ)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (SRTMSTK),DE
        RET
SRTVMFUL:
        LD A,1
        LD (SRTMOVER),A            ; The fallback scan will revisit this vector.
        LD (SRTCLER),A             ; Retain the existing overflow diagnostic bit.
        RET

; Trace every tagged element of a queued vector.
SRTMVEC:
        CALL SRTVLD                ; Recover the validated object and its count.
        RET C
        LD A,(SRTVLENB)
        LD (SRTVLEFT),A            ; Keep the loop count outside the value ABI.
        LD HL,(SRTCLOBJ)
        INC HL                     ; Skip the vector length byte.
        LD (SRTVPTR),HL            ; Keep the element cursor across each mark.
SRTVMLP:
        LD A,(SRTVLEFT)
        OR A
        RET Z
        LD HL,(SRTVPTR)            ; Recover the next four-byte element.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        INC HL
        INC HL                     ; Skip the element spare byte.
        LD (SRTVPTR),HL            ; Retain the cursor before tracing the value.
        EX DE,HL                   ; Present the child in the runtime ABI.
        CALL SRTMVALU              ; Mark a pair, closure, string or vector child.
        LD A,(SRTVLEFT)
        DEC A
        LD (SRTVLEFT),A
        JR SRTVMLP

; Test the vector marker in the odd bit of the persistent mark map.
SRTVSST:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        AND C
        RET

; Set the vector marker in the odd bit of the persistent mark map.
SRTVSMK:
        LD HL,(SRTVOBJ)
        LD (SRTCLOBJ),HL
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Vector scratch and saved cursors.
SRTVLENB: DB 0                     ; Element count for the active vector.
SRTVREQ:  DB 0                     ; Requested count preserved across allocation GC.
SRTVINDX: DB 0                     ; Checked byte index for vector-ref/set!.
SRTVFTAG: DB 0                     ; Fill or replacement value tag.
SRTVLEFT: DB 0                     ; Remaining elements in an initialisation/trace.
SRTVOBJ:  DW 0                     ; Active vector allocation start.
SRTVFILL: DW 0                     ; Fill or replacement value payload.
SRTVPTR:  DW 0                     ; Current vector element cursor.
SRTVPKT:  DW 0                     ; Current constructor packet cursor.
SRTVADR1: DW 0                     ; Selected element address.
