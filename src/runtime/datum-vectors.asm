; Vector construction for the streaming datum reader.
;
; A vector frame uses the same eight-byte record as a list frame, with state
; four.  Its children are consed onto the frame's accumulator as they are
; read, so a vector holds up to 255 elements; at the close the vector is
; allocated while the accumulator is still a reader root, then filled from
; its last element back.

; Parse one datum vector after .HASH has consumed its opening parenthesis.
DR_VEC:
        CALL DR_OPEN               ; Reserve a frame and its accumulator.
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
        LD A,B                     ; Recover the child tag.
        CALL DR_CONS               ; Cons it on; the 256th is an error.
        JP C,ERROR
        JP .LOOP

; Consume ')', allocate the vector and fill it from the accumulator.
.CLOSE:
        CALL DR_TAKE               ; Consume the closing delimiter.
        LD HL,(DR_FRAME)           ; Read the vector's exact child count.
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (VEC_REQ),A             ; The common allocator takes a byte count.
        CALL VEC_NEW                ; Collection sees the accumulator as a root.
        JP C,ERROR                 ; Preserve the checked managed-capacity error.
        LD HL,(VEC_OBJ)
        LD A,(VEC_REQ)
        LD (HL),A
        LD L,A                     ; The last element is at base + 4n - 3.
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,(VEC_OBJ)
        ADD HL,DE
        DEC HL
        DEC HL
        DEC HL
        LD (VEC_PTR),HL
        CALL DR_DROP               ; A:CHL is the reversed list of elements.
.NEXT:
        CALL STD_NIL
        JR Z,.DONE
        LD (DR_VAL),HL
        LD (DR_TAG),A
        CALL PAIR_CAR              ; Copy this element.
        EX DE,HL
        LD HL,(VEC_PTR)
        PUSH HL
        CALL OPS_PUT
        POP HL
        LD DE,-4
        ADD HL,DE
        LD (VEC_PTR),HL
        LD HL,(DR_VAL)
        LD A,(DR_TAG)
        CALL PAIR_CDR
        JR .NEXT
.DONE:
        CALL DR_CLOSE              ; Return to the enclosing list/vector frame.
        LD A,7                     ; The completed object has the vector tag.
        LD HL,(VEC_OBJ)            ; Return the managed vector block address.
        OR A                       ; Clear carry after a complete vector.
        RET
