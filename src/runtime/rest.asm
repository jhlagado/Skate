; Rest-parameter dispatch and argument installation.
;
; A descriptor stores its minimum fixed arity in byte two.  Bit seven marks
; a rest procedure; the low seven bits remain the required argument count.
; The compiler records the rest binding's local slot in a reserved high byte
; of the formal-slot area.  The packet remains a GC root while the surplus
; values are folded into a proper list.

; Validate the descriptor's minimum arity and retain its address in SRTDESC.
SRTDCHK:
        LD (SRTDESC),HL          ; The callee payload is the descriptor address.
        INC HL                   ; Skip the body address low byte.
        INC HL                   ; Skip the body address high byte.
        LD A,(HL)                 ; Descriptor offset two stores policy and minimum.
        LD B,A                    ; Preserve the policy while extracting both fields.
        AND 7FH                   ; The low bits are the required fixed arguments.
        LD (SRTMINAR),A           ; SRTSARGS uses this count before the rest list.
        LD A,B                    ; Recover the descriptor policy bit.
        AND 80H
        LD (SRTRESTF),A           ; Zero is fixed; 80H requests surplus-list binding.
        LD A,(SRTARGC)            ; Recover the staged argument count.
        LD B,A                    ; Keep the count while selecting the policy path.
        LD A,(SRTRESTF)
        OR A
        JR Z,SRTDFIX              ; Fixed procedures require exact arity equality.
        LD A,B                    ; Rest procedures require at least their minimum.
        LD C,A                    ; Preserve the staged count for the comparison.
        LD A,(SRTMINAR)
        LD B,A
        LD A,C
        CP B
        JP C,SRTERROR             ; Too few values cannot fill the fixed prefix.
        XOR A                      ; Clear carry after a valid lower-bound check.
        RET                        ; SRTSARGS builds the proper surplus list.
SRTDFIX:
        LD A,B                    ; Restore the staged count for the exact comparison.
        LD C,A                    ; Preserve the staged count while loading minimum.
        LD A,(SRTMINAR)
        LD B,A
        LD A,C
        CP B
        JP NZ,SRTERROR             ; Fixed procedures still reject extra or missing values.
        XOR A                    ; Clear carry after an exact count match.
        RET                     ; SRTSARGS installs the packet values.


; Copy packet values into the descriptor's formal slots.
SRTSARGS:
        LD A,(SRTMINAR)          ; Only the fixed prefix is copied directly.
        LD B,A
        LD A,B
        OR A
        JR Z,SRTFDONE          ; An all-rest procedure starts with no fixed slots.
        LD C,0                   ; C selects packet values in source order.
        LD HL,(SRTDESC)          ; HL begins at the descriptor body address.
        LD DE,4                  ; Formal slot indexes begin at descriptor offset four.
        ADD HL,DE                ; HL points at the first two-byte slot index.
        LD (SRTNEXT),HL          ; Preserve the descriptor cursor across packet work.
SRTSETLP:
        LD HL,(SRTNEXT)          ; Resume at the next formal slot record.
        LD A,(HL)                ; Read the compiler slot index from the descriptor.
        INC HL                   ; Advance to the high index byte.
        INC HL                   ; The next formal slot follows by two bytes.
        LD (SRTNEXT),HL          ; Keep the cursor while loading this argument.
        CALL SRTADR              ; Convert the slot index to the target cell address.
        JP C,SRTERROR              ; Every formal must have an owned cell.
        LD (SRTSLOT),HL          ; Preserve the destination across packet addressing.
        LD A,C                   ; Address packet index C.
        LD L,A                   ; Widen the packet index.
        LD H,0                   ; Each packet value occupies four bytes.
        ADD HL,HL                ; Two-byte offset.
        ADD HL,HL                ; Four-byte offset.
        LD DE,SRTARGPK           ; Add the packet base.
        ADD HL,DE                ; HL points at the packet value.
        LD E,(HL)                ; Read payload low.
        INC HL                   ; Advance to payload high.
        LD D,(HL)                ; DE now contains the payload value.
        INC HL                   ; Advance to the packet tag.
        LD A,(HL)                ; A contains the logical value tag.
        EX DE,HL                 ; HL receives the payload expected by SRTSTORE.
        LD DE,(SRTSLOT)          ; Restore the formal slot address.
        PUSH BC                   ; SRTBSTOR uses B while preserving the count.
        CALL SRTBSTOR             ; Publish the three-byte heap binding value.
        POP BC                    ; Continue with the remaining formal slots.
        INC C                    ; Advance to the next source argument.
        DJNZ SRTSETLP            ; Fill every formal slot.
SRTFDONE:
        LD A,(SRTRESTF)          ; Fixed procedures have no extra binding to install.
        OR A
        RET Z
        JP SRTRBLD          ; Build and store the proper surplus list.

; Build the proper list bound to the active descriptor's rest slot.  The call
; packet remains rooted by SRTARGC while each pair allocation may collect.
SRTRBLD:
        LD A,(SRTARGC)           ; Compute surplus count as argc minus minimum.
        LD B,A
        LD A,(SRTMINAR)
        LD C,A
        LD A,B
        SUB C
        LD (SRTRESTN),A
        LD (SRTRESTC),A           ; QBLD needs the original count after the loop.
        OR A
        JR Z,SRTREMP         ; No surplus values bind the canonical empty list.
        LD A,C
        LD (SRTRESTI),A           ; Start reading at the first surplus packet record.
SRTRLOOP:
        CALL SRTRREAD          ; Return one packet value as A:HL.
        CALL SRTQPUT               ; Keep it rooted on the quoted-data stack.
        LD A,(SRTRESTI)
        INC A
        LD (SRTRESTI),A
        LD A,(SRTRESTN)
        DEC A
        LD (SRTRESTN),A
        JR NZ,SRTRLOOP
        LD A,(SRTRESTC)           ; Fold the pushed values into a proper list.
        LD B,0                    ; B=0 selects a proper list for SRTQBLD.
        CALL SRTQBLD
        JR SRTRSTOR           ; Store the constructed list in its local cell.
SRTREMP:
        XOR A                      ; The empty list is an immediate scalar value.
        LD HL,0FE02H
SRTRSTOR:
        LD (SRTATMP),A            ; Preserve the list tag while locating the slot.
        LD (SRTVAL),HL            ; Preserve the list payload across SRTADR.
        CALL SRTRSLOT           ; Return the compiler-recorded rest slot in A.
        CALL SRTADR                ; Resolve that slot through the active map.
        JP C,SRTERROR              ; Every rest binding must have an owned cell.
        LD (SRTSLOT),HL           ; Preserve the destination while restoring the value.
        LD DE,(SRTSLOT)
        LD HL,(SRTVAL)
        LD A,(SRTATMP)
        JP SRTBSTOR                ; Publish the list as an ordinary local value.

; Read the packet record selected by SRTRESTI.
SRTRREAD:
        LD A,(SRTRESTI)
        LD L,A
        LD H,0
        ADD HL,HL                 ; Two-byte payload offset.
        ADD HL,HL                 ; Four-byte packet stride.
        LD DE,SRTARGPK
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; Read the rest slot from the reserved high byte of the descriptor.
SRTRSLOT:
        LD HL,(SRTDESC)
        LD DE,4
        ADD HL,DE                 ; First two-byte formal slot field.
        LD A,(SRTMINAR)
        CP 4
        JR Z,SRTRLAST
        ADD A,A
        LD E,A
        LD D,0
        ADD HL,DE
        INC HL                    ; Select the reserved high byte.
        LD A,(HL)
        RET
SRTRLAST:
        LD DE,7                   ; Four fixed formals use field three's high byte.
        ADD HL,DE
        LD A,(HL)
        RET
