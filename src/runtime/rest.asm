; Rest-parameter dispatch and argument installation.
;
; A descriptor stores its minimum fixed arity in byte two.  Bit seven marks
; a rest procedure; the low seven bits remain the required argument count.
; Byte four is the slot of the first formal; the others, and the rest
; formal, follow it in consecutive slots.  The packet remains a GC root while the surplus
; values are folded into a proper list.

; Validate the descriptor's minimum arity and retain its address in DESC_CUR.
REST_CHK:
        LD (DESC_CUR),HL         ; The callee payload is the descriptor address.
        INC HL                   ; Skip the body address low byte.
        INC HL                   ; Skip the body address high byte.
        LD A,(HL)                 ; Descriptor offset two stores policy and minimum.
        LD B,A                    ; Preserve the policy while extracting both fields.
        AND 7FH                   ; The low bits are the required fixed arguments.
        LD (REST_MIN),A           ; REST_ARG uses this count before the rest list.
        LD A,B                    ; Recover the descriptor policy bit.
        AND 80H
        LD (REST_ON),A            ; Zero is fixed; 80H requests surplus-list binding.
        LD A,(ARG_CNT)            ; Recover the staged argument count.
        LD B,A                    ; Keep the count while selecting the policy path.
        LD A,(REST_ON)
        OR A
        JR Z,.FIXED               ; Fixed procedures require exact arity equality.
        LD A,B                    ; Rest procedures require at least their minimum.
        LD C,A                    ; Preserve the staged count for the comparison.
        LD A,(REST_MIN)
        LD B,A
        LD A,C
        CP B
        JP C,ERROR                ; Too few values cannot fill the fixed prefix.
        XOR A                      ; Clear carry after a valid lower-bound check.
        RET                        ; REST_ARG builds the proper surplus list.
.FIXED:
        LD A,B                    ; Restore the staged count for the exact comparison.
        LD C,A                    ; Preserve the staged count while loading minimum.
        LD A,(REST_MIN)
        LD B,A
        LD A,C
        CP B
        JP NZ,ERROR                ; Fixed procedures still reject extra or missing values.
        XOR A                    ; Clear carry after an exact count match.
        RET                     ; REST_ARG installs the packet values.


; Copy packet values into the descriptor's formal slots.
REST_ARG:
        LD A,(REST_MIN)          ; Only the fixed prefix is copied directly.
        LD B,A
        LD A,B
        OR A
        JR Z,.FIX_DONE         ; An all-rest procedure starts with no fixed slots.
        LD C,0                   ; C selects packet values in source order.
        CALL .BASE
        LD (REST_NXT),A         ; The first formal's slot.
.FORMAL:
        LD A,C                   ; Address packet index C.
        LD L,A                   ; Widen the packet index.
        LD H,0                   ; Each packet value occupies four bytes.
        ADD HL,HL                ; Two-byte offset.
        ADD HL,HL                ; Four-byte offset.
        LD DE,ARG_PKT            ; Add the packet base.
        ADD HL,DE                ; HL points at the packet value.
        LD E,(HL)                ; Read payload low.
        INC HL                   ; Advance to payload high.
        LD D,(HL)                ; DE now contains the payload value.
        INC HL
        LD A,(HL)
        LD (REST_EXT),A          ; Byte 2, while C is the packet index.
        INC HL                   ; Advance to the flags and tag.
        LD A,(HL)
        AND 0FH                  ; A contains the logical value tag.
        LD (SLOT_TAG),A          ; Keep the tag while selecting the active slot.
        EX DE,HL                 ; HL receives the payload expected by SLOT_PUT.
        PUSH BC                   ; Preserve the formal and packet cursors.
        LD A,(REST_NXT)
        LD B,A                   ; The active slot helper receives its index in B.
        LD A,(REST_EXT)
        LD C,A
        LD A,(SLOT_TAG)
        CALL SLOT_PUT             ; Publish the value in the active four-byte slot.
        POP BC                    ; Continue with the remaining formal slots.
        LD HL,REST_NXT           ; The next formal has the next slot.
        INC (HL)
        INC C                    ; Advance to the next source argument.
        DJNZ .FORMAL             ; Fill every formal slot.
.FIX_DONE:
        LD A,(REST_ON)           ; Fixed procedures have no extra binding to install.
        OR A
        RET Z
        JP .LIST            ; Build and store the proper surplus list.

; Build the proper list bound to the active descriptor's rest slot.  The call
; packet remains rooted by ARG_CNT while each pair allocation may collect.
.LIST:
        LD A,(ARG_CNT)           ; Compute surplus count as argc minus minimum.
        LD B,A
        LD A,(REST_MIN)
        LD C,A
        LD A,B
        SUB C
        LD (REST_CNT),A
        LD (REST_LEN),A           ; QBLD needs the original count after the loop.
        OR A
        JR Z,.EMPTY          ; No surplus values bind the canonical empty list.
        LD A,C
        LD (REST_IDX),A           ; Start reading at the first surplus packet record.
.PUSH:
        CALL .READ             ; Return one packet value as A:HL.
        CALL QT_PUSH               ; Keep it rooted on the quoted-data stack.
        LD A,(REST_IDX)
        INC A
        LD (REST_IDX),A
        LD A,(REST_CNT)
        DEC A
        LD (REST_CNT),A
        JR NZ,.PUSH
        LD A,(REST_LEN)           ; Fold the pushed values into a proper list.
        LD B,0                    ; B=0 selects a proper list for QT_FOLD.
        CALL QT_FOLD
        JR .STORE             ; Store the constructed list in its local cell.
.EMPTY:
        XOR A                      ; The empty list is an immediate scalar value.
        LD HL,0FE02H
.STORE:
        LD (ARG_TAG),A            ; Preserve the list tag while locating the slot.
        LD (ARG_VAL),HL           ; Preserve the list payload across slot selection.
        CALL .SLOT              ; Return the compiler-recorded rest slot in A.
        LD B,A                    ; Active slot helpers take the index in B.
        LD HL,(ARG_VAL)
        LD A,(ARG_TAG)
        LD C,0                    ; A list's byte 2 is zero.
        JP SLOT_PUT                ; Publish the list as an ordinary local value.

; Read the packet record selected by REST_IDX.
.READ:
        LD A,(REST_IDX)
        LD L,A
        LD H,0
        ADD HL,HL                 ; Two-byte payload offset.
        ADD HL,HL                 ; Four-byte packet stride.
        LD DE,ARG_PKT
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD C,(HL)                 ; Byte 2.
        INC HL
        LD A,(HL)
        AND 0FH
        EX DE,HL
        RET

; Return the rest slot in A: it follows the fixed formals.
.SLOT:
        CALL .BASE
        LD HL,REST_MIN
        ADD A,(HL)
        RET

; Return the first formal's slot, descriptor byte four, in A.
.BASE:
        LD HL,(DESC_CUR)
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        RET
