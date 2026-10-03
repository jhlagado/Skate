; List construction for the streaming datum reader.
;
; Reader values use a separate 64-slot stack so a read cannot overwrite the
; quoted-data stack used by list, rest and apply.  Each open list owns one
; eight-byte frame: state, value count and the stack cursor at its opening.
; Completed lists are folded through the eight-byte pair allocator.

; Push a parsed value onto the reader's bounded construction stack.
SRTDRPUT:
        LD (SRTDRTAG),A             ; Save the tag while checking the cursor.
        LD (SRTDVAL),HL            ; Save the payload beside it.
        LD A,(SRTDRVC)              ; The aggregate construction limit is 64 values.
        CP 64
        JP NC,SRTERROR
        LD HL,(SRTDRVP)             ; Advance by one four-byte value record.
        LD DE,4
        ADD HL,DE
        LD DE,SRTDRVE
        OR A
        SBC HL,DE
        JP C,SRTDRPUS               ; A cursor below the end remains in range.
        JP Z,SRTDRPUS               ; Equality names the legitimate 64th slot.
        JP SRTERROR                 ; A cursor beyond the fixed band is invalid.
SRTDRPUS:
        LD HL,(SRTDRVP)             ; Publish payload before tag and cursor.
        LD DE,(SRTDVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A                   ; The extension byte stays clear.
        INC HL
        LD A,(SRTDRTAG)
        LD (HL),A
        INC HL
        LD (SRTDRVP),HL
        LD A,(SRTDRVC)
        INC A
        LD (SRTDRVC),A
        LD A,(SRTDRTAG)
        LD HL,(SRTDVAL)
        OR A                       ; A successful push must clear carry.
        RET

; Pop the most recent reader value while preserving all older list values.
SRTDRPOP:
        LD A,(SRTDRVC)              ; An empty frame is a malformed list.
        OR A
        JP Z,SRTERROR
        DEC A
        LD (SRTDRVC),A
        LD HL,(SRTDRVP)
        LD DE,4
        OR A
        SBC HL,DE
        LD (SRTDRVP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH                    ; Clears carry: a successful pop.
        EX DE,HL
        RET

; Fold the current frame's values into a proper or dotted list.
; A contains heads plus an optional tail; B is nonzero for a dotted tail.
SRTDRBLD:
        LD (SRTDRNR),A              ; Keep the number while pair allocation runs.
        LD A,B
        LD (SRTDRDOT),A             ; The tail is popped before the list heads.
        LD A,1
        LD (SRTDRACC),A             ; The accumulator is a separate exact root.
        LD A,(SRTDRDOT)
        OR A
        JR Z,SRTDRNIL
        CALL SRTDRPOP               ; A dotted tail is the initial CDR value.
        JP C,SRTERROR
        LD (SRTDATAG),A
        LD (SRTDAVAL),HL
        LD A,(SRTDRNR)
        DEC A
        LD (SRTDRNR),A
        JR SRTDRBLP
SRTDRNIL:
        XOR A
        LD (SRTDATAG),A
        LD HL,0FE02H                ; The empty list is the initial proper CDR.
        LD (SRTDAVAL),HL
SRTDRBLP:
        LD A,(SRTDRNR)
        OR A
        JR Z,SRTDRBDN
        CALL SRTDRPOP               ; The preceding value becomes the new CAR.
        LD (SRTQCTAG),A             ; Pair construction already owns these fields.
        LD (SRTQCAR),HL
        LD A,(SRTDATAG)
        LD (SRTQDTAG),A
        LD HL,(SRTDAVAL)
        LD (SRTQCDR),HL
        CALL SRTMAKEP               ; The common constructor roots both operands.
        JP C,SRTERROR               ; Propagate allocation failure to the reader.
        LD (SRTDATAG),A            ; The new pair becomes the next accumulator.
        LD (SRTDAVAL),HL
        LD A,(SRTDRNR)
        DEC A
        LD (SRTDRNR),A
        JR SRTDRBLP
SRTDRBDN:
        XOR A
        LD (SRTDRACC),A             ; The caller now owns the completed value.
        LD A,(SRTDATAG)
        LD HL,(SRTDAVAL)
        RET

; Open a list frame at the current reader value-stack cursor.
SRTDFOPN:
        LD A,(SRTDRFC)
        CP 32
        JP NC,SRTERROR              ; The reader has a bounded nesting depth.
        LD L,A
        LD H,0
        ADD HL,HL                   ; Eight bytes describe one frame.
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTDRFB
        ADD HL,DE
        LD (SRTDRFP),HL
        LD DE,(SRTDRVP)             ; Save the value-stack base for diagnostics.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A                   ; State zero expects the first list head.
        INC HL
        LD (HL),A                   ; No values belong to this frame yet.
        LD A,(SRTDRFC)
        INC A
        LD (SRTDRFC),A
        OR A                       ; A successful frame open clears carry.
        RET

; Add one completed child value to the current list frame.
SRTDFADD:
        LD HL,(SRTDRFP)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        INC A
        CP 65
        JP NC,SRTERROR              ; A single list cannot exceed 64 values.
        LD (HL),A
        DEC HL                       ; Reach the frame state byte.
        LD A,(HL)
        CP 2
        JR Z,SRTDRFTL                ; The value fills a dotted tail.
        OR A
        RET NZ                       ; State one remains ordinary list data.
        INC A
        LD (HL),A                   ; The first value changes state to one.
        OR A
        RET
SRTDRFTL:
        INC A
        LD (HL),A                   ; State three requires the closing delimiter.
        OR A
        RET

; Close the current list frame and select its parent frame, if any.
SRTDFCLS:
        LD A,(SRTDRFC)
        DEC A
        LD (SRTDRFC),A
        JR Z,SRTDFZER
        LD HL,(SRTDRFP)
        LD DE,8
        OR A
        SBC HL,DE
        LD (SRTDRFP),HL
        OR A
        RET
SRTDFZER:
        XOR A
        LD (SRTDRFP),A
        LD (SRTDRFP+1),A
        RET

; Parse one complete parenthesised list and return its tagged value.
SRTDRLST:
        CALL SRTDFOPN              ; The frame remains live through every child.
        JP C,SRTERROR
SRTDRLLP:
        CALL SRTDRSK                 ; Whitespace and comments precede each child.
        JP C,SRTERROR               ; EOF before ')' leaves a malformed list.
        CALL SRTDRPK
        CP ')'                       ; A close finishes proper or dotted data.
        JP Z,SRTDLCLS
        CP '.'                       ; A dot changes the frame to tail state.
        JP Z,SRTDLDOT
        CALL SRTDRVAL                ; Nested lists recurse through the same path.
        LD B,A
        JP C,SRTERROR
        LD A,(SRTDEOF)
        OR A
        JP NZ,SRTERROR               ; EOF cannot be a child inside a list.
        LD A,B
        CALL SRTDRPUT
        JP C,SRTERROR
        CALL SRTDFADD
        JP C,SRTERROR
        JR SRTDRLLP

; Read one dotted-list tail and require ')' immediately afterward.
SRTDLDOT:
        LD HL,(SRTDRFP)
        LD DE,2
        ADD HL,DE
        LD A,(HL)
        CP 1
        JP NZ,SRTERROR               ; Dot requires at least one preceding head.
        CALL SRTDRTK                 ; Consume the dot retained by the peek.
        JP C,SRTERROR               ; A dot cannot be followed by end of input.
        CALL SRTDRPK                ; A punctuation dot must end at a delimiter.
        JP C,SRTERROR
        CALL SRTDISDL
        JP NZ,SRTERROR              ; Reject `(1 .2)` instead of reinterpreting it.
        LD HL,(SRTDRFP)
        LD DE,2
        ADD HL,DE
        LD A,2
        LD (HL),A                   ; State two expects exactly one tail datum.
        CALL SRTDRSK
        JP C,SRTERROR
        CALL SRTDRPK
        CP ')'
        JP Z,SRTERROR               ; A dotted tail cannot be empty.
        CP '.'
        JP Z,SRTERROR               ; A second dot is malformed punctuation.
        CALL SRTDRVAL
        LD B,A
        JP C,SRTERROR
        LD A,(SRTDEOF)
        OR A
        JP NZ,SRTERROR
        LD A,B
        CALL SRTDRPUT
        JP C,SRTERROR
        CALL SRTDFADD               ; State two becomes state three.
        JP C,SRTERROR
        CALL SRTDRSK
        JP C,SRTERROR
        CALL SRTDRPK
        CP ')'
        JP NZ,SRTERROR               ; No datum may follow a dotted tail.

; Consume ')' and fold the frame's values into pair records.
SRTDLCLS:
        CALL SRTDRTK                 ; Consume the closing delimiter.
        LD HL,(SRTDRFP)
        LD DE,2
        ADD HL,DE
        LD A,(HL)
        CP 2
        JP Z,SRTERROR                ; Dot without a tail is malformed.
        LD B,0
        CP 3
        JR NZ,SRTDRLPR
        INC B                         ; SRTDRBLD receives a dotted-list flag.
SRTDRLPR:
        INC HL                        ; Reach the frame value count.
        LD A,(HL)
        CALL SRTDRBLD
        JP C,SRTERROR
        LD (SRTDRTAG),A              ; Preserve the completed list across frame pop.
        LD (SRTDVAL),HL
        CALL SRTDFCLS
        JP C,SRTERROR
        LD A,(SRTDRTAG)
        LD HL,(SRTDVAL)
        OR A
        RET
