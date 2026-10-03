; Bounded one-shot escape continuations.
;
; A call/ec value is a tagged scalar with tag eight and a token payload.
; The token is valid only while its matching dynamic record is active. The
; record saves the caller state before the target procedure is entered, so an
; escape can discard the target and any nested calls by restoring the saved
; native stack pointer.
;
; Token layout, within E000H-EFFFH (F000H and above belong to ports):
;
;   1110 gggg gggg gsss    sss = record slot 0..7, g = slot generation 0..511
;
; Each record keeps the last token issued for its slot in bytes 0..1. Opening
; the slot again advances that slot's generation by one, wrapping from 511 back
; to 0, so there is no global token budget and a program may perform any number
; of sequential call/ec operations. An escape reads the slot directly from the
; token, requires that slot to be active and requires the record's stored token
; to match exactly; a token whose slot has since been reopened therefore fails
; as stale. The remaining reuse window is per slot: a token saved beyond its
; extent becomes indistinguishable from a live one only after that same slot
; has been reopened exactly 512 times and is active again, a limit inherent in
; the twelve bits available below the port namespace.

SRTCECAL:
        POP IX                     ; Save the generated continuation after call/ec.
        LD (SRTCECT),IX            ; The record returns here on an ordinary result.
        POP HL                     ; Recover the target procedure payload.
        LD (SRTCEFV),HL            ; Keep it while the escape record is opened.
        POP AF                     ; Recover the target procedure tag.
        LD (SRTCEFT),A             ; Keep the tag beside its payload.
        LD HL,0                    ; Form the current native stack pointer in HL.
        ADD HL,SP
        LD (SRTCEBS),HL            ; The caller frame remains below this boundary.
        CALL SRTCEOPN              ; Reserve one dynamic record and make a token.
        LD A,(SRTCEFT)             ; Restore the target value for INV_CALL.
        LD HL,(SRTCEFV)
        PUSH AF                    ; The target is the callee record.
        PUSH HL
        LD A,8                     ; Escape tokens use the private tag-eight type.
        LD HL,(SRTCETK)            ; The active record's generation is its payload.
        CALL ROOT_ADD              ; Keep the token visible during call setup.
        PUSH AF                    ; The token is the one argument to the target.
        PUSH HL
        LD HL,SRTCEPRE             ; A normal target return completes call/ec.
        PUSH HL
        LD A,1                     ; The target receives exactly one escape value.
        JP INV_CALL                ; Use the ordinary closure and arity machinery.

; Compute the address of dynamic record A. Records are twenty-one bytes wide.
SRTCEADR:
        LD L,A                     ; Widen the record index before multiplying.
        LD H,0
        LD D,H                     ; DE becomes the two-byte contribution.
        LD E,L
        ADD HL,HL                  ; Index times two.
        ADD HL,HL                  ; Index times four.
        ADD HL,HL                  ; Index times eight.
        ADD HL,HL                  ; Index times sixteen.
        ADD HL,DE                  ; Add five for the twenty-one-byte stride.
        ADD HL,DE
        ADD HL,DE
        ADD HL,DE
        ADD HL,DE
        LD DE,SRTCEFR              ; Select the dynamic-record table base.
        ADD HL,DE
        RET

; Open a record for the current call/ec and return its generation in HL.
SRTCEOPN:
        LD A,(SRTCEDEP)            ; The table has a deliberately small bound.
        CP 8
        JP NC,SRTERROR             ; Excessive dynamic nesting is a runtime error.
        LD (SRTCEIX),A             ; Retain the record index across address work.
        CALL SRTCEADR              ; HL now names the selected record.
        LD (SRTCEPTR),HL           ; Keep the record base for its fields.
        LD E,(HL)                  ; Read the slot's previous token low byte.
        INC HL
        LD D,(HL)                  ; Read the previous token high byte.
        EX DE,HL                   ; HL is the last token issued for this slot.
        LD DE,8                    ; One generation step lies above the slot bits.
        ADD HL,DE                  ; Advance the generation; slot bits are unchanged.
        LD A,(SRTCEIX)             ; The low three bits must still name this slot.
        LD B,A                     ; Keep the slot number for the comparisons.
        LD A,L
        AND 7                      ; Isolate the slot bits of the candidate token.
        CP B
        JR NZ,SRTCEG0              ; An uninitialised record starts at generation zero.
        LD A,H
        AND 0F0H                   ; Tokens must stay below the F000H port namespace.
        CP 0E0H
        JR Z,SRTCEGOK              ; The advanced token is still in E000H-EFFFH.
SRTCEG0:
        LD L,B                     ; Generation 511 wraps to zero for this slot.
        LD H,RT_ESC/256            ; Generation zero has only the slot bits set.
SRTCEGOK:
        LD (SRTCETK),HL            ; SRTCECAL reads this value after the save.
        LD DE,(SRTCEPTR)
        LD A,L                     ; Store the token low byte.
        LD (DE),A
        INC DE
        LD A,H                     ; Store the token high byte.
        LD (DE),A
        INC DE
        LD HL,(SRTCECT)            ; Store the generated continuation.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD HL,(SRTCEBS)            ; Store the stack boundary to restore on escape.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD HL,(SRTENV)             ; Store the caller's active environment map.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD HL,(SRTDESC)            ; Store the caller's active descriptor.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD HL,(SRTFRAME)           ; Store the caller's suspended-frame cursor.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD HL,(SRTCENV)            ; Store the caller environment for exact roots.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD HL,(SRTOLDSP)           ; Store the caller's activation boundary.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD A,(SRTSLOTS)            ; Store the caller's active slot count.
        LD (DE),A
        INC DE
        LD A,(SRTCENVN)            ; Store the caller-map slot count.
        LD (DE),A
        INC DE
        LD A,(SRTNCT)              ; The target is still rooted on the native stack.
        OR A
        JP Z,SRTERROR              ; A call/ec target must have an exact root record.
        DEC A                       ; Save the cursor before that target was pushed.
        LD (DE),A
        INC DE
        LD HL,(SRTOPS)             ; Save the operator-stack cursor across an escape.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        LD A,(SRTCEIX)             ; Publish the complete record only after all fields.
        INC A
        LD (SRTCEDEP),A            ; The new record is now the active top record.
        LD HL,(SRTCETK)            ; Return the generation token to the caller.
        RET

; A target that returns normally leaves its value in A:HL and its record on top.
SRTCEPRE:
        LD (SRTCEV),HL             ; Preserve the result while retiring the record.
        LD (SRTCEAT),A
        LD A,(SRTCEDEP)
        OR A
        JP Z,SRTERROR              ; An unmatched return indicates damaged control state.
        DEC A
        LD (SRTCEDEP),A            ; The enclosing dynamic record, if any, remains active.
        CALL SRTCEADR              ; Address the record whose continuation we need.
        LD (SRTCEPTR),HL           ; The newest record may have replaced the shared cursor.
        LD DE,2
        ADD HL,DE
        LD E,(HL)                  ; Recover the generated continuation low byte.
        INC HL
        LD D,(HL)
        LD (SRTCEJMP),DE           ; Keep it while restoring the result registers.
        LD HL,(SRTCEPTR)
        LD DE,18
        ADD HL,DE
        LD A,(HL)                  ; Restore the caller's exact shadow-root cursor.
        LD (SRTNCT),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTOPS),DE             ; Restore side-stack state before returning.
        LD A,(SRTCEAT)             ; Restore the target result after the record scan.
        LD HL,(SRTCEV)
        LD IX,(SRTCEJMP)
        JP (IX)                    ; Continue after call/ec with the target result.

; Invoke an escape token. Its slot bits select the record directly, so an
; outer escape may intentionally discard one or more nested dynamic extents.
SRTCEESC:
        LD A,(SRTARGC)             ; An escape procedure accepts one result value.
        CP 1
        JP NZ,SRTERROR
        LD HL,(SRTVAL)             ; The callee payload is the slot and generation.
        LD (SRTCEKEY),HL
        LD A,L
        AND 7                      ; The low three bits name the token's record slot.
        LD (SRTCEIX),A             ; Retain the slot for the record address and hit.
        LD HL,SRTCEDEP             ; Only slots below the current depth are active.
        CP (HL)
        JP NC,SRTERROR             ; A retired slot cannot escape another computation.
        CALL SRTCEADR
        LD (SRTCEPTR),HL           ; Retain the selected record for the hit path.
        LD E,(HL)                  ; Read the slot's current token low byte.
        INC HL
        LD D,(HL)                  ; Read its high byte; DE holds slot and generation.
        LD HL,(SRTCEKEY)
        OR A                       ; Clear carry before the exact comparison.
        SBC HL,DE
        JP NZ,SRTERROR             ; An older generation of this slot is stale.

SRTCEHIT:
        LD A,(SRTCEIX)
        LD (SRTCEIDX),A            ; This index becomes the new dynamic depth.
        CALL SRTONE                ; Read and retain the value supplied to the escape.
        LD (SRTCEAT),A
        LD (SRTCEV),HL
        LD HL,(SRTCEPTR)
        LD DE,2
        ADD HL,DE
        LD E,(HL)                  ; Recover the saved continuation low byte.
        INC HL
        LD D,(HL)
        LD (SRTCEJMP),DE
        LD HL,(SRTCEPTR)
        LD DE,4
        ADD HL,DE
        LD E,(HL)                  ; Recover the native stack boundary low byte.
        INC HL
        LD D,(HL)
        LD (SRTCEBS),DE
        LD HL,(SRTCEPTR)
        LD DE,6
        ADD HL,DE
        LD E,(HL)                  ; Restore the caller environment map.
        INC HL
        LD D,(HL)
        LD (SRTENV),DE
        INC HL
        LD E,(HL)                  ; Restore the caller descriptor pointer.
        INC HL
        LD D,(HL)
        LD (SRTDESC),DE
        INC HL
        LD E,(HL)                  ; Restore the caller frame cursor.
        INC HL
        LD D,(HL)
        LD (SRTFRAME),DE
        LD HL,(SRTCEPTR)
        LD DE,12
        ADD HL,DE
        LD E,(HL)                  ; Restore the caller environment root map.
        INC HL
        LD D,(HL)
        LD (SRTCENV),DE
        LD HL,(SRTCEPTR)
        LD DE,14
        ADD HL,DE
        LD E,(HL)                  ; Restore the caller activation boundary.
        INC HL
        LD D,(HL)
        LD (SRTOLDSP),DE
        LD HL,(SRTCEPTR)
        LD DE,16
        ADD HL,DE
        LD A,(HL)                  ; Restore the caller's active slot count.
        LD (SRTSLOTS),A
        INC HL
        LD A,(HL)                  ; Restore its caller-map slot count.
        LD (SRTCENVN),A
        LD HL,(SRTCEPTR)
        LD DE,18
        ADD HL,DE
        LD A,(HL)                  ; Restore roots owned by the enclosing call.
        LD (SRTNCT),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTOPS),DE             ; Drop operator records created inside the target.
        LD A,(SRTCEIDX)
        LD (SRTCEDEP),A            ; Remove the matched record and all inner records.
        XOR A                       ; The escaped packet is no longer live.
        LD (SRTARGC),A
        LD (APPLY_TL),A            ; Return through the ordinary caller path.
        LD (APPLY_IN),A
        LD HL,(SRTCEBS)
        LD SP,HL                   ; Discard the target and every nested call frame.
        LD A,(SRTCEAT)
        LD HL,(SRTCEV)
        LD IX,(SRTCEJMP)
        JP (IX)                    ; The escape value is the call/ec result.

; Preserve maps saved by active escape records while the collector is running.
SRTCEROT:
        LD A,(SRTCEDEP)
        OR A
        RET Z
        LD (SRTCEIX),A
SRTCERL:
        LD A,(SRTCEIX)
        DEC A
        LD (SRTCEIX),A
        CALL SRTCEADR
        LD (SRTCEPTR),HL
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (SRTCERMP),HL           ; Keep the recovered map while reading record fields.
        LD HL,(SRTCEPTR)
        LD DE,16
        ADD HL,DE
        LD A,(HL)
        LD HL,(SRTCERMP)
        CALL ROOT_MAP               ; Mark the saved caller map's binding cells.
        LD HL,(SRTCEPTR)
        LD DE,12
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (SRTCERMP),HL           ; Keep the nested caller map across the slot lookup.
        LD HL,(SRTCEPTR)
        LD DE,17
        ADD HL,DE
        LD A,(HL)
        LD HL,(SRTCERMP)
        CALL ROOT_MAP               ; Mark its caller map as well.
        LD A,(SRTCEIX)
        OR A
        JR NZ,SRTCERL
        RET

; Dynamic escape state and the bounded record table.
SRTCEDEP:  DB 0                    ; Number of active call/ec records.
SRTCECT:   DW 0                    ; Generated continuation during record setup.
SRTCEBS:   DW 0                    ; Native stack boundary during record setup.
SRTCEFV:   DW 0                    ; Target procedure payload during setup.
SRTCEFT:   DB 0                    ; Target procedure tag during setup.
SRTCETK:   DW 0                    ; Token returned by the current record.
SRTCEPTR:  DW 0                    ; Dynamic record pointer.
SRTCEIX:   DB 0                    ; Dynamic record index or search cursor.
SRTCEIDX:  DB 0                    ; Matched record index during an escape.
SRTCEKEY:  DW 0                    ; Token being sought by SRTCEESC.
SRTCEV:    DW 0                    ; Escape or normal-result payload.
SRTCEAT:   DB 0                    ; Escape or normal-result tag.
SRTCEJMP:  DW 0                    ; Continuation retained across state restore.
SRTCERMP:  DW 0                    ; Saved map pointer during collector root scans.
SRTCEFR:   DS 168                  ; Eight records, twenty-one bytes each.
