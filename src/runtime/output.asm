; Scope-control runtime output and scalar predicates
;
; The compiler and runtime share the value printer below.  Integer conversion
; remains separate from pair and literal output so each path has one clear
; responsibility and the main runtime module stays within the source limit.

; Return #t for zero and #f for every other exact integer.
NUM_ZERO:
        CP 3                     ; The predicate is defined only for exact integers.
        JP NZ,ERROR               ; Preserve the runtime type contract.
        LD A,C                   ; Combine the three payload bytes for the zero test.
        OR H
        OR L                     ; Z means the exact integer is zero.
        JR Z,.TRUE                ; Return canonical true for zero.
        XOR A                    ; Tag zero identifies a boolean value.
        LD C,A
        LD HL,0FE00H             ; #f has the reserved false payload.
        RET                      ; Return the false predicate result.
.TRUE:
        XOR A                    ; Tag zero identifies a boolean value.
        LD C,A
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
        CALL NUM_TEXT              ; HL is the decimal text and B its length.
        LD DE,OUT_BUF              ; Copy it into the message buffer.
        LD C,B
        LD B,0
        LDIR
        EX DE,HL
        LD (HL),13                 ; CP/M text output uses carriage return first.
        INC HL                     ; Advance to the line-feed position.
        LD (HL),10                 ; Complete the CP/M line ending.
        INC HL                     ; Advance to function 9's terminator byte.
        LD (HL),'$'                ; Function 9 stops at the dollar byte.
        LD DE,OUT_BUF              ; DE points to the completed message.
        JP OUT_TEXT                ; Send the completed text through byte output.

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
