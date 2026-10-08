; Dynamic apply for the bounded procedure-call packet.
;
; The compiler call path accepts ARG_MAX four-byte value records.  Apply keeps
; the procedure and final list aside, moves any leading arguments down, then
; appends the list elements in order.  A proper list longer than the packet is
; rejected before the target is entered.  The ordinary call and tail-call
; dispatchers then perform the same descriptor, closure and rest checks as a
; directly written call.

; Spread the final proper list argument into ARG_PKT and enter its procedure.
APPLY:
        LD A,(ARG_CNT)             ; Apply needs a procedure and a final list.
        CP 2
        JP C,ERROR                 ; A missing list or procedure is malformed.
        LD HL,ARG_PKT              ; Record zero contains the target procedure.
        CALL PKT_VAL
        LD (APPLY_A),A             ; Keep its logical tag while the list is read.
        LD (APPLY_HL),HL          ; Keep its payload beside the tag.
        LD A,(ARG_CNT)             ; The final packet record is the list argument.
        DEC A
        LD L,A
        LD H,0
        ADD HL,HL                  ; Four bytes describe each packet record.
        ADD HL,HL
        LD DE,ARG_PKT
        ADD HL,DE
        CALL PKT_VAL               ; Recover the list tag and payload.
        LD (QT_ATAG),A             ; The existing pair helpers use these fields.
        LD (QT_ACC),HL
        LD A,(ARG_CNT)             ; Leading arguments exclude procedure and list.
        SUB 2
        LD (PKT_LEFT),A            ; This is also the next output record index.
        CALL .MOVE                 ; Move leading records over the procedure slot.
.WALK:
        LD A,(QT_ATAG)             ; NIL is the only non-pair list terminator.
        OR A
        JR NZ,.PAIR
        LD HL,(QT_ACC)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JP NZ,ERROR                 ; Reject booleans, numbers and other scalars.
        JR .ENTER
.PAIR:
        CP 1
        JP NZ,ERROR                 ; A dotted tail is not an apply argument list.
        LD A,(PKT_LEFT)
        CP ARG_MAX
        JP NC,ERROR                 ; The packet is full.
        LD HL,(QT_ACC)              ; Read this pair's CAR before advancing its CDR.
        LD A,1
        CALL PAIR_CAR
        JP C,ERROR
        LD (QT_CTAG),A              ; Preserve the CAR while computing its slot.
        LD (QT_CAR),HL
        LD A,C
        LD (QT_CEXT),A
        LD A,(PKT_LEFT)
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,ARG_PKT
        ADD HL,DE
        EX DE,HL                    ; DE now addresses the next output record.
        LD HL,(QT_CAR)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD A,(QT_CEXT)
        LD (DE),A                   ; Byte 2.
        INC DE
        LD A,(QT_CTAG)
        OR CELL_VAL
        LD (DE),A                   ; Publish the appended value as live.
        LD A,(PKT_LEFT)
        INC A
        LD (PKT_LEFT),A
        LD HL,(QT_ACC)              ; Recover the same pair for its CDR.
        LD A,1
        CALL PAIR_CDR
        JP C,ERROR
        LD (QT_ATAG),A
        LD (QT_ACC),HL
        JR .WALK

; Move the leading apply arguments from records one..n to records zero..n-1.
.MOVE:
        LD A,(PKT_LEFT)
        OR A
        RET Z
        LD B,A
        LD HL,ARG_PKT+4
        LD DE,ARG_PKT
.LOOP:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ .LOOP
        RET

; Enter the target through the ordinary or tail dispatcher selected by the
; caller.  ARG_CNT is reduced to the number of spread arguments before entry.
.ENTER:
        LD A,(PKT_LEFT)
        LD (ARG_CNT),A
        LD A,(APPLY_TL)
        OR A
        JR NZ,.TAIL
        LD A,1
        LD (APPLY_IN),A            ; Preserve the outer continuation for either target.
        LD IX,(FRM_SAVE)            ; Closure targets use the same saved continuation.
        LD A,(APPLY_A)
        LD HL,(APPLY_HL)
        JP INV_GO
.TAIL:
        LD A,(APPLY_A)
        LD HL,(APPLY_HL)
        JP INV_TLGO
