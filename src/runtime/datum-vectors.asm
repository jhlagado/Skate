; Vector construction for the streaming datum reader.
;
; A vector frame uses the same eight-byte record as a list frame. Its state
; byte is four, its count byte records the child values, and the reader value
; stack keeps every child as an exact four-byte root until the final count is
; known. The existing vector allocator then owns the managed block.

; Parse one datum vector after .HASH has consumed its opening parenthesis.
DR_VEC:
        CALL DR_OPEN               ; Reserve a frame and save the value cursor.
        JP C,ERROR                 ; Reject a nesting depth beyond the frame band.
        LD HL,(DR_FRAME)           ; Select the new frame's state byte.
        INC HL
        INC HL
        LD A,4                     ; State four identifies a vector frame.
        LD (HL),A
.LOOP:
        CALL DR_SKIP               ; Skip whitespace and comments before a child.
        JP C,ERROR                 ; EOF before ')' is malformed vector data.
        CALL DR_PEEK               ; Leave ')' in lookahead until the close path.
        CP ')'                     ; A close supplies the exact vector count.
        JP Z,.CLOSE
        CALL DR_DATUM              ; Nested lists, strings and vectors are values.
        LD B,A                     ; Preserve the child's tag across the status test.
        JP C,ERROR                 ; A malformed child aborts the whole vector.
        LD A,(DR_EOF)               ; EOF cannot be a vector element.
        OR A
        JP NZ,ERROR
        LD A,B                     ; Recover the child tag for the root push.
        CALL DR_PUSH               ; Keep the child rooted until vector allocation.
        JP C,ERROR
        CALL .COUNT                ; Count it in this vector's frame.
        JP C,ERROR
        JP .LOOP                   ; Continue until the closing delimiter.

; Increment the current vector count, rejecting the 65th element.
.COUNT:
        LD HL,(DR_FRAME)           ; Frame byte three contains the child count.
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        INC A
        CP 65                      ; Datum vectors are bounded at 64 elements.
        JP NC,ERROR
        LD (HL),A
        OR A                       ; A successful count update clears carry.
        RET

; Consume ')' and allocate/copy the completed vector.
.CLOSE:
        CALL DR_TAKE               ; Consume the closing delimiter.
        LD HL,(DR_FRAME)           ; Read the vector's exact child count.
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (VEC_REQ),A             ; The common allocator takes a byte count.
        LD HL,(DR_FRAME)           ; Save the value-stack base across allocation.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (.BASE),DE
        CALL VEC_NEW                ; Collection sees the reader stack as roots.
        JP C,ERROR                 ; Preserve the checked managed-capacity error.
        CALL .COPY                 ; Copy every tagged child without allocation.
        LD A,(VEC_REQ)             ; Remove the child records from the reader stack.
        LD B,A
        LD HL,(DR_SP)
        LD E,A
        LD D,0
        SLA E                      ; Four bytes are stored for each child.
        RL D
        SLA E
        RL D
        OR A
        SBC HL,DE
        LD (DR_SP),HL
        LD A,(DR_SLOTS)
        SUB B
        LD (DR_SLOTS),A
        CALL DR_CLOSE              ; Return to the enclosing list/vector frame.
        LD A,7                     ; The completed object has the vector tag.
        LD HL,(VEC_OBJ)            ; Return the managed vector block address.
        OR A                       ; Clear carry after a complete vector.
        RET

; Copy reader-stack values into the allocated vector's four-byte elements.
.COPY:
        LD HL,(VEC_OBJ)            ; Publish the count before copying elements.
        LD A,(VEC_REQ)
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL
        LD HL,(.BASE)              ; Source begins at this frame's saved cursor.
        LD (VEC_PKTP),HL
        LD A,(VEC_REQ)
        LD (VEC_LEFT),A
.NEXT:
        LD A,(VEC_LEFT)             ; Stop after all children have been copied.
        OR A
        RET Z
        LD HL,(VEC_PKTP)            ; Read one source payload, tag and flags.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                   ; Byte 2.
        INC HL
        LD A,(HL)
        AND 0FH
        LD (VEC_TAG),A
        INC HL
        LD (VEC_PKTP),HL
        LD HL,(VEC_PTR)             ; Write the corresponding vector element.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),C
        INC HL
        LD A,(VEC_TAG)
        LD (HL),A
        INC HL
        LD (VEC_PTR),HL
        LD A,(VEC_LEFT)
        DEC A
        LD (VEC_LEFT),A
        JP .NEXT

.BASE:   DW 0                      ; Value-stack base saved for vector copying.
