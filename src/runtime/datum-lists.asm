; List construction for the streaming datum reader.
;
; Reader values use a separate 64-slot stack so a read cannot overwrite the
; quoted-data stack used by list, rest and apply.  Each open list owns one
; eight-byte frame (its accumulator slot, state and count) and one slot: the
; values read so far, consed in reverse.  A list of any length therefore uses
; two slots at most, and the close relinks the reversed pairs in place.

; Push a parsed value onto the reader's bounded construction stack.
DR_PUSH:
        LD (DR_TAG),A               ; Save the tag while checking the cursor.
        LD (DR_VAL),HL             ; Save the payload beside it.
        CP 3                        ; Only an integer or a float owns byte 2.
        JR Z,.WIDE
        CP 9
        JR Z,.WIDE
        LD C,0
.WIDE:
        LD A,C
        LD (DR_EXT),A
        LD A,(DR_SLOTS)             ; The aggregate construction limit is 64 values.
        CP 64
        JP NC,ERROR
        LD HL,(DR_SP)               ; Advance by one four-byte value record.
        LD DE,4
        ADD HL,DE
        LD DE,RT_DRVHI
        OR A
        SBC HL,DE
        JP C,.STORE                 ; A cursor below the end remains in range.
        JP Z,.STORE                 ; Equality names the legitimate 64th slot.
        JP ERROR                    ; A cursor beyond the fixed band is invalid.
.STORE:
        LD HL,(DR_SP)               ; Publish payload before tag and cursor.
        LD DE,(DR_VAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(DR_EXT)
        LD (HL),A                   ; Byte 2.
        INC HL
        LD A,(DR_TAG)
        LD (HL),A
        INC HL
        LD (DR_SP),HL
        LD A,(DR_SLOTS)
        INC A
        LD (DR_SLOTS),A
        LD A,(DR_TAG)
        LD HL,(DR_VAL)
        OR A                       ; A successful push must clear carry.
        RET

; Pop the most recent reader value while preserving all older list values.
DR_POP:
        LD A,(DR_SLOTS)             ; An empty frame is a malformed list.
        OR A
        JP Z,ERROR
        DEC A
        LD (DR_SLOTS),A
        LD HL,(DR_SP)
        LD DE,4
        OR A
        SBC HL,DE
        LD (DR_SP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                  ; Byte 2.
        INC HL
        LD A,(HL)
        AND 0FH                    ; Clears carry: a successful pop.
        EX DE,HL
        RET

; Cons the completed child A:CHL onto the current frame's accumulator, which
; holds the frame's values so far as a reversed list in the frame's first
; reader slot.  The child stays a reader root while its pair is allocated.
DR_CONS:
        CALL DR_PUSH
        JP C,ERROR
        LD (QT_CAR),HL
        LD (QT_CTAG),A
        LD A,C
        LD (QT_CEXT),A
        CALL DR_BASE                ; HL addresses the accumulator slot.
        CALL DR_GET
        LD (QT_CDR),HL
        LD (QT_DTAG),A
        LD A,C
        LD (QT_DEXT),A
        CALL PAIR_NEW
        JP C,ERROR
        PUSH HL
        CALL DR_BASE
        POP DE
        LD C,0
        CALL OPS_PUT                ; The new pair is the accumulator.
        CALL DR_POP                 ; Drop the child's root.
        LD HL,(DR_FRAME)            ; Count the child; a vector holds 255.
        INC HL
        INC HL
        LD A,(HL)
        INC HL
        INC (HL)
        RET NZ
        CP 4
        JP Z,ERROR
        DEC (HL)                    ; A list's count stops at 255.
        OR A
        RET

; HL = the current frame's accumulator slot.
DR_BASE:
        LD HL,(DR_FRAME)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        RET

; Load the four-byte reader slot at HL as A:CHL.
DR_GET:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; Drop the current frame's slots and return its accumulator as A:CHL.
DR_DROP:
        CALL DR_BASE
        LD (DR_SP),HL
        LD A,(DR_SLOTS)
        DEC A
        LD (DR_SLOTS),A
        JR DR_GET

; Open a list frame at the current reader value-stack cursor.
DR_OPEN:
        LD A,(DR_DEPTH)
        CP 32
        JP NC,ERROR                 ; The reader has a bounded nesting depth.
        LD L,A
        LD H,0
        ADD HL,HL                   ; Eight bytes describe one frame.
        ADD HL,HL
        ADD HL,HL
        LD DE,RT_DRFLO
        ADD HL,DE
        LD (DR_FRAME),HL
        LD DE,(DR_SP)               ; Save the value-stack base for diagnostics.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A                   ; State zero expects the first list head.
        INC HL
        LD (HL),A                   ; No values belong to this frame yet.
        LD A,(DR_DEPTH)
        INC A
        LD (DR_DEPTH),A
        XOR A                      ; The accumulator starts as the empty list.
        LD C,A
        LD HL,0FE02H
        JP DR_PUSH

; Add one completed child value to the current list frame.
DR_CHILD:
        LD HL,(DR_FRAME)
        INC HL
        INC HL
        LD A,(HL)
        CP 2
        JR Z,.TAIL                   ; The value fills a dotted tail.
        OR A
        RET NZ                       ; State one remains ordinary list data.
        INC A
        LD (HL),A                   ; The first value changes state to one.
        OR A
        RET
.TAIL:
        INC A
        LD (HL),A                   ; State three requires the closing delimiter.
        OR A
        RET

; Close the current list frame and select its parent frame, if any.
DR_CLOSE:
        LD A,(DR_DEPTH)
        DEC A
        LD (DR_DEPTH),A
        JR Z,.EMPTY
        LD HL,(DR_FRAME)
        LD DE,8
        OR A
        SBC HL,DE
        LD (DR_FRAME),HL
        OR A
        RET
.EMPTY:
        XOR A
        LD (DR_FRAME),A
        LD (DR_FRAME+1),A
        RET

; Parse one complete parenthesised list and return its tagged value.
DR_LIST:
        CALL DR_OPEN               ; The frame remains live through every child.
        JP C,ERROR
.LOOP:
        CALL DR_SKIP                 ; Whitespace and comments precede each child.
        JP C,ERROR                  ; EOF before ')' leaves a malformed list.
        CALL DR_PEEK
        CP ')'                       ; A close finishes proper or dotted data.
        JP Z,.CLOSE
        CP '.'                       ; A dot changes the frame to tail state.
        JP Z,.DOT
        CALL DR_DATUM                ; Nested lists recurse through the same path.
        LD B,A
        JP C,ERROR
        LD A,(DR_EOF)
        OR A
        JP NZ,ERROR                  ; EOF cannot be a child inside a list.
        LD A,B
        CALL DR_CONS
        JP C,ERROR
        CALL DR_CHILD
        JP C,ERROR
        JR .LOOP

; Read one dotted-list tail and require ')' immediately afterward.
.DOT:
        LD HL,(DR_FRAME)
        LD DE,2
        ADD HL,DE
        LD A,(HL)
        CP 1
        JP NZ,ERROR                  ; Dot requires at least one preceding head.
        CALL DR_TAKE                 ; Consume the dot retained by the peek.
        JP C,ERROR                  ; A dot cannot be followed by end of input.
        CALL DR_PEEK                ; A punctuation dot must end at a delimiter.
        JP C,ERROR
        CALL DR_DELIM
        JP NZ,ERROR                 ; Reject `(1 .2)` instead of reinterpreting it.
        LD HL,(DR_FRAME)
        LD DE,2
        ADD HL,DE
        LD A,2
        LD (HL),A                   ; State two expects exactly one tail datum.
        CALL DR_SKIP
        JP C,ERROR
        CALL DR_PEEK
        CP ')'
        JP Z,ERROR                  ; A dotted tail cannot be empty.
        CP '.'
        JP Z,ERROR                  ; A second dot is malformed punctuation.
        CALL DR_DATUM
        LD B,A
        JP C,ERROR
        LD A,(DR_EOF)
        OR A
        JP NZ,ERROR
        LD A,B
        CALL DR_PUSH
        JP C,ERROR
        CALL DR_CHILD               ; State two becomes state three.
        JP C,ERROR
        CALL DR_SKIP
        JP C,ERROR
        CALL DR_PEEK
        CP ')'
        JP NZ,ERROR                  ; No datum may follow a dotted tail.

; Consume ')' and reverse the accumulator in place onto the tail.  The pairs
; are the reader's own, and nothing is allocated while their links change.
.CLOSE:
        CALL DR_TAKE                 ; Consume the closing delimiter.
        LD HL,(DR_FRAME)
        INC HL
        INC HL
        LD A,(HL)
        CP 2
        JP Z,ERROR                   ; Dot without a tail is malformed.
        LD HL,0FE02H                 ; A proper list ends in the empty list.
        LD C,0
        CP 3
        LD A,0
        CALL Z,DR_POP                ; A dotted list ends in its tail.
        LD (DR_ACC),HL
        LD (DR_ATAG),A
        LD A,C
        LD (DR_AEXT),A
        CALL DR_DROP                 ; A:CHL is the reversed list.
.FLIP:
        CALL STD_NIL
        JR Z,.DONE
        LD DE,CDR_LO
        ADD HL,DE
        PUSH HL
        CALL DR_GET                  ; The next pair.
        AND 0FH
        LD (DR_TAG),A
        LD (DR_VAL),HL
        LD A,C
        LD (DR_EXT),A
        POP HL
        PUSH HL
        LD DE,(DR_ACC)               ; Link this pair to the list after it.
        LD A,(DR_AEXT)
        LD C,A
        LD A,(DR_ATAG)
        CALL STD_PUT
        POP HL
        LD DE,-CDR_LO
        ADD HL,DE
        LD (DR_ACC),HL               ; This pair heads the list so far.
        LD A,1
        LD (DR_ATAG),A
        XOR A
        LD (DR_AEXT),A
        LD HL,(DR_VAL)
        LD A,(DR_EXT)
        LD C,A
        LD A,(DR_TAG)
        JR .FLIP
.DONE:
        CALL DR_CLOSE
        LD HL,(DR_ACC)
        LD A,(DR_AEXT)
        LD C,A
        LD A,(DR_ATAG)
        OR A
        RET
