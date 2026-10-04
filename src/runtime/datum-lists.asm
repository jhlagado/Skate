; List construction for the streaming datum reader.
;
; Reader values use a separate 64-slot stack so a read cannot overwrite the
; quoted-data stack used by list, rest and apply.  Each open list owns one
; eight-byte frame: state, value count and the stack cursor at its opening.
; Completed lists are folded through the eight-byte pair allocator.

; Push a parsed value onto the reader's bounded construction stack.
DR_PUSH:
        LD (DR_TAG),A               ; Save the tag while checking the cursor.
        LD (DR_VAL),HL             ; Save the payload beside it.
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
        PUSH HL
        LD A,(DR_TAG)
        EX DE,HL
        CALL RT_WIDEN               ; Reader values are sixteen-bit for now.
        POP HL
        LD (HL),C                   ; Byte 2.
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

; Fold the current frame's values into a proper or dotted list.
; A contains heads plus an optional tail; B is nonzero for a dotted tail.
DR_BUILD:
        LD (DR_FOLD),A              ; Keep the number while pair allocation runs.
        LD A,B
        LD (DR_DOT),A               ; The tail is popped before the list heads.
        LD A,1
        LD (DR_HELD),A              ; The accumulator is a separate exact root.
        LD A,(DR_DOT)
        OR A
        JR Z,.PROPER
        CALL DR_POP                 ; A dotted tail is the initial CDR value.
        JP C,ERROR
        LD (DR_ATAG),A
        LD A,C
        LD (DR_AEXT),A
        LD (DR_ACC),HL
        LD A,(DR_FOLD)
        DEC A
        LD (DR_FOLD),A
        JR .LOOP
.PROPER:
        XOR A
        LD (DR_ATAG),A
        LD (DR_AEXT),A
        LD HL,0FE02H                ; The empty list is the initial proper CDR.
        LD (DR_ACC),HL
.LOOP:
        LD A,(DR_FOLD)
        OR A
        JR Z,.DONE
        CALL DR_POP                 ; The preceding value becomes the new CAR.
        LD (QT_CTAG),A              ; Pair construction already owns these fields.
        LD (QT_CAR),HL
        LD A,C
        LD (QT_CEXT),A
        LD A,(DR_AEXT)
        LD (QT_DEXT),A
        LD A,(DR_ATAG)
        LD (QT_DTAG),A
        LD HL,(DR_ACC)
        LD (QT_CDR),HL
        CALL PAIR_NEW               ; The common constructor roots both operands.
        JP C,ERROR                  ; Propagate allocation failure to the reader.
        LD (DR_ATAG),A             ; The new pair becomes the next accumulator.
        LD (DR_ACC),HL
        XOR A
        LD (DR_AEXT),A
        LD A,(DR_FOLD)
        DEC A
        LD (DR_FOLD),A
        JR .LOOP
.DONE:
        XOR A
        LD (DR_HELD),A              ; The caller now owns the completed value.
        LD A,(DR_ATAG)
        LD HL,(DR_ACC)
        RET

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
        OR A                       ; A successful frame open clears carry.
        RET

; Add one completed child value to the current list frame.
DR_CHILD:
        LD HL,(DR_FRAME)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        INC A
        CP 65
        JP NC,ERROR                 ; A single list cannot exceed 64 values.
        LD (HL),A
        DEC HL                       ; Reach the frame state byte.
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
        CALL DR_PUSH
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

; Consume ')' and fold the frame's values into pair records.
.CLOSE:
        CALL DR_TAKE                 ; Consume the closing delimiter.
        LD HL,(DR_FRAME)
        LD DE,2
        ADD HL,DE
        LD A,(HL)
        CP 2
        JP Z,ERROR                   ; Dot without a tail is malformed.
        LD B,0
        CP 3
        JR NZ,.FOLD
        INC B                         ; DR_BUILD receives a dotted-list flag.
.FOLD:
        INC HL                        ; Reach the frame value count.
        LD A,(HL)
        CALL DR_BUILD
        JP C,ERROR
        LD (DR_TAG),A                ; Preserve the completed list across frame pop.
        LD (DR_VAL),HL
        CALL DR_CLOSE
        JP C,ERROR
        LD A,(DR_TAG)
        LD HL,(DR_VAL)
        OR A
        RET
