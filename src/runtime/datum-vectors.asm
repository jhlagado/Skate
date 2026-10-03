; Vector construction for the streaming datum reader.
;
; A vector frame uses the same eight-byte record as a list frame. Its state
; byte is four, its count byte records the child values, and the reader value
; stack keeps every child as an exact four-byte root until the final count is
; known. The existing vector allocator then owns the managed block.

; Parse one datum vector after SRTDRHS has consumed its opening parenthesis.
SRTDRVEC:
        CALL SRTDFOPN              ; Reserve a frame and save the value cursor.
        JP C,SRTERROR              ; Reject a nesting depth beyond the frame band.
        LD HL,(SRTDRFP)            ; Select the new frame's state byte.
        INC HL
        INC HL
        LD A,4                     ; State four identifies a vector frame.
        LD (HL),A
SRTDVLP:
        CALL SRTDRSK               ; Skip whitespace and comments before a child.
        JP C,SRTERROR              ; EOF before ')' is malformed vector data.
        CALL SRTDRPK               ; Leave ')' in lookahead until the close path.
        CP ')'                     ; A close supplies the exact vector count.
        JP Z,SRTDVCLS
        CALL SRTDRVAL              ; Nested lists, strings and vectors are values.
        LD B,A                     ; Preserve the child's tag across the status test.
        JP C,SRTERROR              ; A malformed child aborts the whole vector.
        LD A,(SRTDEOF)              ; EOF cannot be a vector element.
        OR A
        JP NZ,SRTERROR
        LD A,B                     ; Recover the child tag for the root push.
        CALL SRTDRPUT              ; Keep the child rooted until vector allocation.
        JP C,SRTERROR
        CALL SRTDVADD              ; Count it in this vector's frame.
        JP C,SRTERROR
        JP SRTDVLP                 ; Continue until the closing delimiter.

; Increment the current vector count, rejecting the 65th element.
SRTDVADD:
        LD HL,(SRTDRFP)            ; Frame byte three contains the child count.
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        INC A
        CP 65                      ; Datum vectors are bounded at 64 elements.
        JP NC,SRTERROR
        LD (HL),A
        OR A                       ; A successful count update clears carry.
        RET

; Consume ')' and allocate/copy the completed vector.
SRTDVCLS:
        CALL SRTDRTK               ; Consume the closing delimiter.
        LD HL,(SRTDRFP)            ; Read the vector's exact child count.
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (SRTVREQ),A             ; The common allocator takes a byte count.
        LD HL,(SRTDRFP)            ; Save the value-stack base across allocation.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTDVBS),DE
        CALL SRTVACL                ; Collection sees the reader stack as roots.
        JP C,SRTERROR              ; Preserve the checked managed-capacity error.
        CALL SRTDVPUT              ; Copy every tagged child without allocation.
        LD A,(SRTVREQ)             ; Remove the child records from the reader stack.
        LD B,A
        LD HL,(SRTDRVP)
        LD E,A
        LD D,0
        SLA E                      ; Four bytes are stored for each child.
        RL D
        SLA E
        RL D
        OR A
        SBC HL,DE
        LD (SRTDRVP),HL
        LD A,(SRTDRVC)
        SUB B
        LD (SRTDRVC),A
        CALL SRTDFCLS              ; Return to the enclosing list/vector frame.
        LD A,7                     ; The completed object has the vector tag.
        LD HL,(SRTVOBJ)            ; Return the managed vector block address.
        OR A                       ; Clear carry after a complete vector.
        RET

; Copy reader-stack values into the allocated vector's four-byte elements.
SRTDVPUT:
        LD HL,(SRTVOBJ)            ; Publish the count before copying elements.
        LD A,(SRTVREQ)
        LD (HL),A
        INC HL
        LD (SRTVPTR),HL
        LD HL,(SRTDVBS)            ; Source begins at this frame's saved cursor.
        LD (SRTVPKT),HL
        LD A,(SRTVREQ)
        LD (SRTVLEFT),A
SRTDVPLP:
        LD A,(SRTVLEFT)             ; Stop after all children have been copied.
        OR A
        RET Z
        LD HL,(SRTVPKT)             ; Read one source payload, tag and flags.
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL                      ; Skip the extension byte.
        LD A,(HL)
        AND 0FH
        LD (SRTVFTAG),A
        INC HL
        LD (SRTVPKT),HL
        LD HL,(SRTVPTR)             ; Write the corresponding vector element.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD A,(SRTVFTAG)
        LD (HL),A
        INC HL
        LD (SRTVPTR),HL
        LD A,(SRTVLEFT)
        DEC A
        LD (SRTVLEFT),A
        JP SRTDVPLP

SRTDVBS:   DW 0                    ; Value-stack base saved for vector copying.
