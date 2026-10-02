; Vector primitive dispatch, construction and element access.
; SRTVHOOK connects roots and queued allocations to tracing.
; SRTVEC consumes the primitive argument packet and returns through IX.

; HL is the object. A=1 marks a root; A=0 classifies a queued allocation.
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
        INC HL                     ; Skip the reserved extension byte.
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
        XOR A                      ; Keep the future payload extension clear.
        LD (HL),A
        INC HL
        LD A,(SRTVFTAG)            ; Publish the logical element tag.
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
        XOR A                      ; Keep the future payload extension clear.
        LD (HL),A
        INC HL
        LD A,(SRTVFTAG)            ; Store the fill tag in cell metadata.
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
        LD (SRTVFTAG),A            ; Preserve it while clearing the extension.
        INC HL
        INC HL                     ; Skip the packet publication flag.
        LD (SRTVPKT),HL            ; Advance the source cursor by four bytes.
        LD HL,(SRTVPTR)            ; Recover the destination element address.
        LD (HL),E                  ; Store the payload low byte.
        INC HL
        LD (HL),D                  ; Store the payload high byte.
        INC HL
        XOR A                      ; Keep the future payload extension clear.
        LD (HL),A
        INC HL
        LD A,(SRTVFTAG)            ; Store the logical tag in cell metadata.
        LD (HL),A
        INC HL
        LD (SRTVPTR),HL            ; Advance to the next destination element.
        LD A,(SRTVLEFT)
        DEC A
        LD (SRTVLEFT),A
        JR SRTVPLP
