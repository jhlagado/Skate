; Scope-control runtime output and scalar predicates
;
; The compiler and runtime share the value printer below.  Integer conversion
; remains separate from pair and literal output so each path has one clear
; responsibility and the main runtime module stays within the source limit.

; Return #t for zero and #f for every other exact integer.
SRTZERO:
        CP 3                     ; The predicate is defined only for exact integers.
        JP NZ,SRTERROR            ; Preserve the runtime type contract.
        LD A,H                   ; Combine the two payload bytes for the zero test.
        OR L                     ; Z means the exact integer is zero.
        JR Z,SRTZTRUE             ; Return canonical true for zero.
        LD A,0                   ; Tag zero identifies a boolean value.
        LD HL,0FE00H             ; #f has the reserved false payload.
        RET                      ; Return the false predicate result.
SRTZTRUE:
        LD A,0                   ; Tag zero identifies a boolean value.
        LD HL,0FE01H             ; #t has the reserved true payload.
        RET                      ; Return the true predicate result.

; Dispatch the final value printer.  Pair and literal values use the compact
; writer; the established decimal path remains for exact integers.
SRTPRINT:
        CP 3
        JP Z,SRTNUMPR
        JP SRTWRVAL

; Format an exact integer and print it through CP/M function 9.
SRTNUMPR:
        LD (SRTRES),HL         ; Retain the result during decimal conversion.
        LD DE,SRTBUF          ; Start writing at the message buffer.
        BIT 7,H                   ; A negative value needs a leading minus sign.
        JR Z,SRTIPOS              ; Positive values go directly to place handling.
        LD A,'-'                  ; Store the sign before taking the magnitude.
        LD (DE),A                 ; Write the sign byte.
        INC DE                    ; Advance to the first digit.
        XOR A                     ; Clear A before the low-byte negation.
        SUB L                     ; Negate the low payload byte.
        LD L,A                    ; Retain the low magnitude byte.
        LD A,0                    ; Preserve the low-byte borrow for negating H.
        SBC A,H                    ; Negate the high payload byte with borrow.
        LD H,A                    ; Retain the complete magnitude.
SRTIPOS:
        LD (SRTPTR),DE             ; Give the place routine its output cursor.
        XOR A                     ; No significant digit has been emitted yet.
        LD (SRTBEG),A         ; Suppress leading zeroes until needed.
        LD DE,10000                ; Select the ten-thousands place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,1000                 ; Select the thousands place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,100                  ; Select the hundreds place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,10                   ; Select the tens place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD A,1                     ; Units must always be emitted.
        LD (SRTBEG),A          ; Permit a zero units digit after a prefix.
        LD DE,1                    ; Select the units place.
        CALL SRTPLACE              ; Append the final digit.
        LD HL,(SRTPTR)             ; Locate the first unused message position.
        LD (HL),13                 ; CP/M text output uses carriage return first.
        INC HL                     ; Advance to the line-feed position.
        LD (HL),10                 ; Complete the CP/M line ending.
        INC HL                     ; Advance to function 9's terminator byte.
        LD (HL),'$'                ; Function 9 stops at the dollar byte.
        LD DE,SRTBUF           ; DE points to the completed message.
        LD C,9                     ; Select CP/M's string-output function.
        CALL 5                     ; Print the result and return to the caller.
        RET                       ; Return to SRTSTART for the warm start.

; Subtract one decimal place until the next subtraction would borrow.
SRTPLACE:
        LD B,0                     ; B counts how often the place value fits.
SRTPLP:
        OR A                       ; Clear carry before the signed subtraction.
        SBC HL,DE                  ; Try one more occurrence of this place.
        JR C,SRTPLDN          ; A borrow means the digit is complete.
        INC B                      ; Count the place value that fitted.
        JR SRTPLP            ; Continue until the next one would borrow.
SRTPLDN:
        ADD HL,DE                  ; Restore the first value that did not fit.
        LD A,B                     ; Copy the digit count for output decisions.
        OR A                       ; A nonzero count always becomes a digit.
        JR NZ,SRTPLOUT          ; Emit a significant digit.
        LD A,(SRTBEG)          ; Check whether a prior place emitted a digit.
        OR A                       ; A zero state still suppresses this place.
        RET Z                      ; Leave a leading zero out of the message.
SRTPLOUT:
        LD A,1                     ; Later zeroes are significant after this one.
        LD (SRTBEG),A          ; Publish the started state.
        LD A,B                     ; Convert the count to its ASCII digit.
        ADD A,'0'                  ; Add the ASCII zero offset.
        PUSH HL                    ; Preserve the remaining numeric value.
        LD HL,(SRTPTR)             ; Load the next output position.
        LD (HL),A                  ; Store the decimal digit.
        INC HL                     ; Advance the output cursor.
        LD (SRTPTR),HL             ; Preserve it for the next place.
        POP HL                     ; Restore the remaining numeric value.
        RET                        ; Return for the next decimal place.

SRTUNBD:
        LD DE,SRTUNBT        ; Explain the unbound reference.
        JR SRTOUT             ; Share the CP/M error-output path.
SRTERROR:
        LD DE,SRTERRTX          ; Explain an arithmetic or runtime failure.
SRTOUT:
        LD C,9                     ; Select CP/M's dollar-terminated output.
        CALL 5                     ; Print the terminal diagnostic.
        JP 0                       ; Do not return with a damaged value stack.

; Patched entry and generated-program data fields.
SRTRES:    DW 0                 ; Result payload retained by SRTPRINT.
SRTPTR:       DW 0                 ; Current decimal-output cursor.
SRTBEG:   DB 0                 ; Nonzero after the first significant digit.
SRTTAG:  DB 0                 ; Original tag retained by SRTFALSE.
SRTBOOL:      DB 0                 ; Branch decision retained while restoring A.
SRTOP:        DB 0                 ; Selected checked arithmetic operation.
SRTPID:       DB 0                 ; Predefined primitive kind for the active call.
SRTARGC:      DB 0                 ; Number of values in the current call packet.
SRTNLEFT:     DB 0                 ; Remaining values in an arithmetic or compare fold.
SRTNACCT:     DB 0                 ; Accumulator tag for a variadic numeric fold.
SRTNTAG:      DB 0                 ; Current packet value tag during numeric work.
SRTNPTR:      DW 0                 ; Current packet cursor during a numeric fold.
SRTNACCV:     DW 0                 ; Accumulator payload for a variadic numeric fold.
SRTNVAL:      DW 0                 ; Current packet payload during numeric work.
SRTCCOD:      DW 0                 ; Raw NCMP relation for the current pair.
SRTLCN:       DB 0                 ; Remaining packet values while building list.
SRTLCP:       DW 0                 ; Packet cursor for the list builder.
SRTATMP:      DB 0                 ; Temporary tag while packing one argument.
SRTVAL:       DW 0                 ; Temporary payload while packing one argument.
SRTDESC:      DW 0                 ; Descriptor for the active procedure call.
SRTOBJ:       DW 0                 ; Closure object currently being entered.
SRTENV:       DW 0                 ; Pointer array for the active procedure.
SRTCENV:      DW 0                 ; Caller environment restored at return.
SRTNEWD:      DW 0                 ; Descriptor being copied into a closure.
SRTNENV:    DW 0                 ; Destination map during closure creation.
SRTHEAPP:     DW SRTHEAP           ; Bump cursor for closure cells and objects.
SRTBYTES:     DW 0                 ; Pointer-map byte count for the active shape.
SRTOLDSP:     DW 0                 ; Stack boundary before an activation map.
SRTLOWSP:     DW 0E000H            ; Lowest native stack boundary observed.
SRTRET:       DW 0                 ; Helper return saved while moving the stack.
SRTCELLP:     DW 0                 ; Cell base retained during heap allocation.
SRTADDR:      DW 0                 ; Environment entry being filled.
SRTMASKP:     DW 0                 ; Descriptor mask cursor during activation setup.
SRTCURD:      DW 0                 ; Descriptor active before a tail transfer.
SRTSLOT:      DW 0                 ; Formal cell address during argument transfer.
SRTNEXT:      DW 0                 ; Descriptor cursor during argument transfer.
SRTSRC:       DW 0                 ; Target closure map during a tail transfer.
SRTMASKV:     DB 0                 ; Current owned-mask byte.
SRTMASKN:     DB 0                 ; Capture-mask bytes left in a tail transfer.
SRTBITN:      DB 0                 ; Capture-mask bits left in the current byte.
SRTSLOTI:     DB 0                 ; Slot number represented by the mask cursor.
SRTSLOTS:     DB 0                 ; Number of pointer slots in the current shape.
SRTCURS:      DB 0                 ; Pointer-slot extent of the current frame.
SRTARGPK:     DS 32                ; Eight four-byte argument records.
SRTOPS:       DW SRTOPB        ; Operator side-stack cursor between heap and guard.
SRTBUF:   DS 32                ; Decimal output buffer terminated for BDOS function 9.
SRTERRTX:  DB "RUNTIME ERROR",13,10,"$"
SRTUNBT: DB "UNBOUND",13,10,"$"

SRTEND:
