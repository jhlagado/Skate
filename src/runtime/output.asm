; Scope-control runtime output and scalar predicates
;
; The compiler and runtime share the value printer below.  Integer conversion
; remains separate from pair and literal output so each path has one clear
; responsibility and the main runtime module stays within the source limit.

; Return #t for zero and #f for every other exact integer.
NUM_ZERO:
        CP 3                     ; The predicate is defined only for exact integers.
        JP NZ,ERROR               ; Preserve the runtime type contract.
        LD A,H                   ; Combine the two payload bytes for the zero test.
        OR L                     ; Z means the exact integer is zero.
        JR Z,.TRUE                ; Return canonical true for zero.
        LD A,0                   ; Tag zero identifies a boolean value.
        LD HL,0FE00H             ; #f has the reserved false payload.
        RET                      ; Return the false predicate result.
.TRUE:
        LD A,0                   ; Tag zero identifies a boolean value.
        LD HL,0FE01H             ; #t has the reserved true payload.
        RET                      ; Return the true predicate result.

; Dispatch the final value printer.  Pair and literal values use the compact
; writer; the established decimal path remains for exact integers.
OUT_SHOW:
        CP 3
        JP Z,.NUMBER
        JP WR_VALUE

; Format an exact integer and print it through CP/M function 9.
.NUMBER:
        LD (OUT_NUM),HL        ; Retain the result during decimal conversion.
        LD DE,OUT_BUF         ; Start writing at the message buffer.
        BIT 7,H                   ; A negative value needs a leading minus sign.
        JR Z,.PLACES              ; Positive values go directly to place handling.
        LD A,'-'                  ; Store the sign before taking the magnitude.
        LD (DE),A                 ; Write the sign byte.
        INC DE                    ; Advance to the first digit.
        XOR A                     ; Clear A before the low-byte negation.
        SUB L                     ; Negate the low payload byte.
        LD L,A                    ; Retain the low magnitude byte.
        LD A,0                    ; Preserve the low-byte borrow for negating H.
        SBC A,H                    ; Negate the high payload byte with borrow.
        LD H,A                    ; Retain the complete magnitude.
.PLACES:
        LD (OUT_DSTP),DE           ; Give the place routine its output cursor.
        XOR A                     ; No significant digit has been emitted yet.
        LD (OUT_SEEN),A       ; Suppress leading zeroes until needed.
        LD DE,10000                ; Select the ten-thousands place.
        CALL .PLACE                ; Append a digit when this place is used.
        LD DE,1000                 ; Select the thousands place.
        CALL .PLACE                ; Append a digit when this place is used.
        LD DE,100                  ; Select the hundreds place.
        CALL .PLACE                ; Append a digit when this place is used.
        LD DE,10                   ; Select the tens place.
        CALL .PLACE                ; Append a digit when this place is used.
        LD A,1                     ; Units must always be emitted.
        LD (OUT_SEEN),A        ; Permit a zero units digit after a prefix.
        LD DE,1                    ; Select the units place.
        CALL .PLACE                ; Append the final digit.
        LD HL,(OUT_DSTP)           ; Locate the first unused message position.
        LD (HL),13                 ; CP/M text output uses carriage return first.
        INC HL                     ; Advance to the line-feed position.
        LD (HL),10                 ; Complete the CP/M line ending.
        INC HL                     ; Advance to function 9's terminator byte.
        LD (HL),'$'                ; Function 9 stops at the dollar byte.
        LD DE,OUT_BUF          ; DE points to the completed message.
        JP OUT_TEXT                ; Send the completed text through byte output.

; Subtract one decimal place until the next subtraction would borrow.
.PLACE:
        LD B,0                     ; B counts how often the place value fits.
.SUB_LOOP:
        OR A                       ; Clear carry before the signed subtraction.
        SBC HL,DE                  ; Try one more occurrence of this place.
        JR C,.COUNTED         ; A borrow means the digit is complete.
        INC B                      ; Count the place value that fitted.
        JR .SUB_LOOP         ; Continue until the next one would borrow.
.COUNTED:
        ADD HL,DE                  ; Restore the first value that did not fit.
        LD A,B                     ; Copy the digit count for output decisions.
        OR A                       ; A nonzero count always becomes a digit.
        JR NZ,.DIGIT            ; Emit a significant digit.
        LD A,(OUT_SEEN)        ; Check whether a prior place emitted a digit.
        OR A                       ; A zero state still suppresses this place.
        RET Z                      ; Leave a leading zero out of the message.
.DIGIT:
        LD A,1                     ; Later zeroes are significant after this one.
        LD (OUT_SEEN),A        ; Publish the started state.
        LD A,B                     ; Convert the count to its ASCII digit.
        ADD A,'0'                  ; Add the ASCII zero offset.
        PUSH HL                    ; Preserve the remaining numeric value.
        LD HL,(OUT_DSTP)           ; Load the next output position.
        LD (HL),A                  ; Store the decimal digit.
        INC HL                     ; Advance the output cursor.
        LD (OUT_DSTP),HL           ; Preserve it for the next place.
        POP HL                     ; Restore the remaining numeric value.
        RET                        ; Return for the next decimal place.

; Clear active reader state before the common fatal runtime-error message.
DR_CLEAR:
        LD A,(DR_LIVE)               ; Inactive runtime errors need no cleanup.
        OR A
        RET Z
        XOR A                        ; Drop temporary roots and parser cursors.
        LD (DR_LIVE),A
        LD (DR_ROOTS),A
        LD (DR_DEPTH),A
        LD (DR_SLOTS),A
        LD (DR_HELD),A
        LD (DR_FRAME),A
        LD (DR_FRAME+1),A
        LD HL,RT_DRVLO               ; Failed construction cannot retain stack roots.
        LD (DR_SP),HL
        LD (DR_LEN),A
        LD (DR_SIZE),A
        LD (IN_STATE),A          ; A failed read cannot retain a stale byte.
        LD (IN_CR),A                 ; Reset the physical line-ending state too.
        RET

RT_UNDEF:
        LD DE,TX_UNDEF       ; Explain the unbound reference.
        JP OUT_FAIL           ; Share the provider error-output path.
ERROR:
        CALL DR_CLEAR             ; Clear active datum-reader roots before failure.
        LD DE,TX_ERROR          ; Explain an arithmetic or runtime failure.
OUT_FAIL:
        PUSH DE                    ; Keep the message while files are closed.
        LD A,(OUT_FILE)            ; Only the I/O module can have opened a file.
        OR A
        CALL NZ,OUT_SHUT           ; Flush and close it; ignore status.
        POP DE                     ; Recover the diagnostic message.
.NEXT:
        LD A,(DE)                  ; Read the next diagnostic byte.
        INC DE                     ; Advance before the service can clobber DE.
        CP '$'                     ; Dollar terminates the internal text strings.
        JP Z,0                     ; Do not return with a damaged value stack.
        PUSH DE                    ; Keep the message cursor across the service.
        CALL CON_SEND              ; Use the patchable byte service, not BDOS 9;
        POP DE                     ; a failing provider cannot report itself.
        JR .NEXT                   ; Continue until the complete message is sent.

; Send a dollar-terminated runtime message through the selected byte service.
; Normal value output uses this path so a provider sees the same bytes as CP/M.
OUT_TEXT:
        LD A,(DE)                  ; Read the next message byte.
        INC DE                     ; Advance before the service call can clobber DE.
        CP '$'                     ; Dollar terminates the internal text strings.
        RET Z                      ; Do not expose the terminator to the provider.
        CALL OUT_CHAR              ; Route one byte through the provider boundary.
        JR OUT_TEXT                ; Continue until the complete message is sent.
