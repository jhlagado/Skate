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
        JP SRTTEXT                 ; Send the completed text through byte output.

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
        JP SRTOUT             ; Share the CP/M error-output path.
SRTERROR:
        CALL SRTDCLN              ; Clear active datum-reader roots before failure.
        LD DE,SRTERRTX          ; Explain an arithmetic or runtime failure.
SRTOUT:
        LD C,9                     ; Select CP/M's dollar-terminated output.
        CALL 5                     ; Print the terminal diagnostic.
        JP 0                       ; Do not return with a damaged value stack.

; Send a dollar-terminated runtime message through the selected byte service.
; Normal value output uses this path so a provider sees the same bytes as CP/M.
SRTTEXT:
        LD A,(DE)                  ; Read the next message byte.
        INC DE                     ; Advance before the service call can clobber DE.
        CP '$'                     ; Dollar terminates the internal text strings.
        RET Z                      ; Do not expose the terminator to the provider.
        CALL SRTCH                 ; Route one byte through the provider boundary.
        JR SRTTEXT                 ; Continue until the complete message is sent.
