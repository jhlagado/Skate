; Vector reachability and allocation-kind markers.
; VEC_MARK accepts HL as an object address; VEC_SCAN traces its elements.

; Mark a vector allocation as a reachable queued leaf/container.
VEC_MARK:
        LD (CL_OBJ),HL             ; Keep the object base for map operations.
        CALL VEC_CHK               ; Validate before setting any mark bit.
        RET C
        CALL GC_SEEN               ; A previously queued vector needs no duplicate.
        RET NZ
        CALL GC_VISIT              ; Set the shared closure mark map.
        LD DE,(GC_QTOP)            ; Queue the object for element tracing.
        LD A,D
        CP 0D4H
        JR NC,.FULL                ; Defer children when the bounded queue is full.
        LD HL,(CL_OBJ)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (GC_QTOP),DE
        RET
.FULL:
        LD A,1
        LD (GC_OVER),A             ; The fallback scan will revisit this vector.
        LD (CL_FULL),A             ; Retain the existing overflow diagnostic bit.
        RET
; Trace every tagged element of a queued vector.
VEC_SCAN:
        CALL VEC_CHK               ; Recover the validated object and its count.
        RET C
        LD A,(VEC_LEN)
        LD (VEC_LEFT),A            ; Keep the loop count outside the value ABI.
        LD HL,(CL_OBJ)
        INC HL                     ; Skip the vector length byte.
        LD (VEC_PTR),HL            ; Keep the element cursor across each mark.
.LOOP:
        LD A,(VEC_LEFT)
        OR A
        RET Z
        LD HL,(VEC_PTR)            ; Recover the next four-byte element.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        INC HL                     ; Advance past the cell metadata byte.
        LD (VEC_PTR),HL            ; Retain the cursor before tracing the value.
        EX DE,HL                   ; Present the child in the runtime ABI.
        CALL GC_VALUE              ; Mark a pair, closure, string or vector child.
        LD A,(VEC_LEFT)
        DEC A
        LD (VEC_LEFT),A
        JR .LOOP

; Test the vector marker in the odd bit of the persistent mark map.
VEC_TEST:
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,GC_MARKS
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        AND C
        RET

; Set the vector marker in the odd bit of the persistent mark map.
VEC_SETM:
        LD HL,(VEC_OBJ)
        LD (CL_OBJ),HL
        CALL GC_OBJAT
        LD C,A
        LD DE,GC_MARKS
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        OR C
        LD (HL),A
        RET
