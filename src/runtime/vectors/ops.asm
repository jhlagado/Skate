; Vector primitive dispatch, construction and element access.
; VEC_HOOK connects roots and queued allocations to tracing.
; VEC_PRIM consumes the primitive argument packet and returns through IX.

; HL is the object. A=1 marks a root; A=0 classifies a queued allocation.
VEC_HOOK:
        LD (CL_OBJ),HL             ; Keep the queued object across bitmap probes.
        CP 1
        JP Z,VEC_MARK
        CALL STR_TEST               ; Strings are leaves and need no traversal.
        RET NZ
        CALL VEC_TEST               ; Test the vector marker on this allocation.
        JR Z,.CLOSURE
        LD HL,(CL_OBJ)              ; Restore the object after VEC_TEST's map lookup.
        CALL VEC_SCAN               ; Trace every tagged vector element.
        RET
.CLOSURE:
        JP GC_CAPS                  ; The remaining managed allocation is a closure.
; Dispatch the vector primitive range selected by PRIM_RUN.
VEC_PRIM:
        LD A,(PRIM_ID)             ; Read the zero-based vector operation kind.
        CP 39                      ; Kind thirty-nine is vector?.
        JP Z,.IS_VEC               ; Test one value without raising a type error.
        CP 40                      ; Kind forty is make-vector.
        JP Z,.MAKE                 ; Allocate a counted vector with an optional fill.
        CP 41                      ; Kind forty-one is the short vector constructor.
        JP Z,.VECTOR               ; Copy the bounded packet into a new vector.
        CP 42                      ; Kind forty-two is vector-length.
        JP Z,.LENGTH               ; Return the stored element count.
        CP 43                      ; Kind forty-three is vector-ref.
        JP Z,.REF                  ; Read one checked element.
        JP .SET                    ; The remaining kind is vector-set!.
; Return a boolean for vector? without exposing stale heap pointers.
.IS_VEC:
        CALL PKT_ONE               ; Read the single predicate argument.
        CP 7                       ; Only the vector tag can select validation.
        JR NZ,.FALSE               ; Other values are ordinary non-vectors.
        CALL VEC_CHK               ; Reject freed and interior vector addresses.
        JR C,.FALSE                ; A malformed tagged value is not a vector.
        XOR A                      ; Boolean results use the scalar tag.
        LD HL,0FE01H               ; Return canonical true.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the predicate result.
.FALSE:
        XOR A                      ; Boolean results use the scalar tag.
        LD HL,0FE00H               ; Return canonical false.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the predicate result.
; Allocate a vector whose length is an exact integer and whose fill is optional.
.MAKE:
        LD A,(ARG_CNT)             ; make-vector accepts one or two arguments.
        CP 1                       ; Reject a missing length argument.
        JP C,ERROR
        CP 3                       ; Reject more than one optional fill value.
        JP NC,ERROR
        LD HL,ARG_PKT              ; Read the requested vector length.
        CALL PKT_VAL               ; Return its payload in HL and tag in A.
        CP 3                       ; The length must be an exact integer.
        JP NZ,ERROR
        LD A,C                     ; Only a small nonnegative count is supported.
        OR H
        JP NZ,ERROR
        LD A,L                     ; Preserve the checked count for allocation.
        CP 65                      ; Class 64 is the largest supported vector.
        JP NC,ERROR
        LD (VEC_REQ),A             ; Preserve the request across a collection retry.
        LD A,(ARG_CNT)             ; Select the supplied fill only for arity two.
        CP 2
        JR Z,.FILL_ARG             ; Read and retain the optional fill value.
        XOR A                      ; The default fill is the canonical false value.
        LD (VEC_TAG),A
        LD (VEC_EXT),A
        LD HL,0FE00H               ; Store #f as the default payload.
        LD (VEC_VAL),HL
        JR .ALLOC                  ; Allocate and initialise every element.
.FILL_ARG:
        LD HL,ARG_PKT+4            ; The optional fill is the second packet value.
        CALL PKT_VAL               ; Recover its complete tagged representation.
        LD (VEC_VAL),HL            ; Keep the payload across class allocation.
        LD (VEC_TAG),A             ; Keep the logical tag beside the payload.
        LD A,C
        LD (VEC_EXT),A
.ALLOC:
        CALL VEC_NEW                ; The packet remains an exact root during GC.
        JP C,ERROR                 ; Report exhaustion after one collection retry.
        CALL VEC_FILL              ; Fill the newly allocated vector block.
        LD A,7                      ; Tag seven identifies a vector value.
        LD HL,(VEC_OBJ)             ; Return the managed object address.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the new vector value.
; Construct a vector from the current packet, limited by its eight records.
.VECTOR:
        LD A,(ARG_CNT)             ; The short constructor accepts zero through eight.
        CP ARG_MAX+1               ; A full packet of values.
        JP NC,ERROR                ; Only a malformed caller can exceed the packet.
        LD (VEC_REQ),A             ; Preserve the request across a collection retry.
        CALL VEC_NEW                ; Packet values remain roots across a retry.
        JP C,ERROR
        CALL VEC_COPY              ; Copy each payload and tag into the block.
        LD A,7                      ; Tag seven identifies a vector value.
        LD HL,(VEC_OBJ)             ; Return the managed object address.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the new vector value.
; Return the length of one checked vector.
.LENGTH:
        LD A,(ARG_CNT)             ; vector-length accepts exactly one argument.
        CP 1
        JP NZ,ERROR
        CALL .ARG                   ; Validate the first packet value.
        JP C,ERROR
        LD A,(VEC_LEN)             ; Widen its count into an exact integer value.
        LD L,A
        LD H,0
        LD C,H
        LD A,3                      ; Exact integers use logical tag three.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the length result.
; Read a vector element after validating the vector and its exact index.
.REF:
        LD A,(ARG_CNT)             ; vector-ref requires a vector and an index.
        CP 2
        JP NZ,ERROR
        CALL .ARG                   ; Validate and retain the vector object.
        JP C,ERROR
        LD HL,ARG_PKT+4            ; The second packet value is the index.
        CALL PKT_VAL               ; Return its payload and tag.
        CALL VEC_IDX               ; Check its range against the vector length.
        JP C,ERROR
        CALL VEC_ADDR              ; Compute the selected element address.
        LD E,(HL)                  ; Recover the element payload low byte.
        INC HL
        LD D,(HL)                  ; Recover the element payload high byte.
        INC HL
        LD C,(HL)                  ; Byte 2.
        INC HL
        LD A,(HL)                  ; Recover the element's logical tag.
        EX DE,HL                   ; Return the payload in the standard ABI.
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the selected element.
; Replace a vector element and return the unspecified value.
.SET:
        LD A,(ARG_CNT)             ; vector-set! requires vector, index and value.
        CP 3
        JP NZ,ERROR
        CALL .ARG                   ; Validate and retain the vector object.
        JP C,ERROR
        LD HL,ARG_PKT+4            ; The second packet value is the index.
        CALL PKT_VAL               ; Return its payload and tag.
        CALL VEC_IDX               ; Check its range against the vector length.
        JP C,ERROR
        LD HL,ARG_PKT+8            ; The third packet value is the replacement.
        CALL PKT_VAL               ; Recover its complete tagged representation.
        LD (VEC_VAL),HL            ; Reuse fill scratch for the replacement payload.
        LD (VEC_TAG),A             ; Reuse fill scratch for the replacement tag.
        LD A,C
        LD (VEC_EXT),A
        CALL VEC_ADDR              ; Compute the selected element address.
        LD HL,(VEC_CELL)           ; Recover the selected element address.
        LD DE,(VEC_VAL)            ; Load the replacement payload.
        LD (HL),E                  ; Publish the payload low byte.
        INC HL
        LD (HL),D                  ; Publish the payload high byte.
        INC HL
        LD A,(VEC_EXT)
        LD (HL),A                  ; Byte 2.
        INC HL
        LD A,(VEC_TAG)             ; Publish the logical element tag.
        LD (HL),A
        XOR A                      ; Return the unspecified scalar value.
        LD HL,0FE04H
        PUSH IX                    ; Retire the packet through the common cleanup.
        RET                        ; Deliver the mutation result.
; Validate the vector in the first packet record and retain its length.
.ARG:
        LD HL,ARG_PKT              ; The vector is always the first argument.
        CALL PKT_VAL               ; Return its payload and tag.
        CP 7                       ; Only the vector tag can select this helper.
        JR NZ,VEC_BAD              ; A non-vector is an operation type error.
        CALL VEC_CHK               ; Validate ownership, class and extent.
        JR C,VEC_BAD               ; Return carry for the primitive caller.
        LD (VEC_OBJ),HL            ; Retain the exact vector start.
        LD A,(HL)                  ; Read the vector's bounded element count.
        LD (VEC_LEN),A             ; Keep it for index checks.
        OR A                       ; Clear carry for a successful helper return.
        RET
VEC_BAD:
        SCF                         ; The caller converts this into RUNTIME ERROR.
        RET
; Validate an exact, nonnegative byte index against VEC_LEN.
VEC_IDX:
        CP 3                       ; Index values must be exact integers.
        JR NZ,VEC_BAD
        LD A,C                     ; Negative and wide indexes are out of range.
        OR H
        JR NZ,VEC_BAD
        LD A,L                     ; Compare the low byte with the vector count.
        LD A,(VEC_LEN)
        LD B,A                     ; Compare against the stored vector length.
        LD A,L                     ; Restore the index after loading the count.
        CP B
        JR NC,VEC_BAD
        LD (VEC_POS),A             ; Retain the checked index for address calculation.
        OR A                       ; Clear carry for a successful helper return.
        RET
; Compute the address of the indexed element in VEC_OBJ.
VEC_ADDR:
        LD A,(VEC_POS)             ; Four bytes represent one vector element.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        INC HL                     ; Skip the vector length byte.
        LD DE,(VEC_OBJ)            ; Add the vector object base.
        ADD HL,DE
        LD (VEC_CELL),HL           ; Retain the address across packet loads.
        RET
; Fill a vector with the retained VEC_VAL value.
VEC_FILL:
        LD HL,(VEC_OBJ)            ; Publish the count before filling elements.
        LD A,(VEC_REQ)
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL            ; Keep the element cursor in scratch.
        LD A,(VEC_REQ)             ; Copy the bounded element count.
        LD (VEC_LEFT),A
.LOOP:
        LD A,(VEC_LEFT)            ; Stop after every element has been written.
        OR A
        RET Z
        LD HL,(VEC_PTR)            ; Recover the current element address.
        LD DE,(VEC_VAL)            ; Copy the fill payload.
        LD (HL),E                  ; Store the payload low byte.
        INC HL
        LD (HL),D                  ; Store the payload high byte.
        INC HL
        LD A,(VEC_EXT)
        LD (HL),A                  ; Byte 2.
        INC HL
        LD A,(VEC_TAG)             ; Store the fill tag in cell metadata.
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL            ; Advance to the next element.
        LD A,(VEC_LEFT)
        DEC A
        LD (VEC_LEFT),A
        JR .LOOP
; Copy the packet values into a newly allocated vector.
VEC_COPY:
        LD HL,(VEC_OBJ)            ; Publish the count before copying elements.
        LD A,(VEC_REQ)
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL            ; Keep the destination cursor in scratch.
        LD HL,ARG_PKT              ; The packet begins at its first value record.
        LD (VEC_PKTP),HL           ; Keep the source cursor beside the destination.
        LD A,(VEC_REQ)             ; Copy the bounded argument count.
        LD (VEC_LEFT),A
.LOOP:
        LD A,(VEC_LEFT)            ; Stop after every argument has been copied.
        OR A
        RET Z
        LD HL,(VEC_PKTP)           ; Recover the current packet record.
        LD E,(HL)                  ; Read its payload low byte.
        INC HL
        LD D,(HL)                  ; Read its payload high byte.
        INC HL
        LD C,(HL)                  ; Byte 2.
        INC HL
        LD A,(HL)
        AND 0FH                    ; Its logical tag.
        LD (VEC_TAG),A
        INC HL
        LD (VEC_PKTP),HL           ; Advance the source cursor by four bytes.
        LD HL,(VEC_PTR)            ; Recover the destination element address.
        LD (HL),E                  ; Store the payload low byte.
        INC HL
        LD (HL),D                  ; Store the payload high byte.
        INC HL
        LD (HL),C                  ; Byte 2.
        INC HL
        LD A,(VEC_TAG)             ; Store the logical tag in cell metadata.
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL            ; Advance to the next destination element.
        LD A,(VEC_LEFT)
        DEC A
        LD (VEC_LEFT),A
        JR .LOOP
