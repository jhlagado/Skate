;=============================================================================
;  Shared native compiler command support
;=============================================================================
;
;  Arithmetic and control-flow commands share the CP/M guard, diagnostics and
;  source-close path.  Keeping this small support block separate lets each
;  front end carry only its own evaluator while preserving one command
;  contract.
;=============================================================================

ARMEMERR:
        LD DE,ARMEMTXT             ; Point at the guarded-memory diagnostic.
        JP ARPRINT                 ; Use the shared CP/M message path.

; Print one diagnostic and return to the CCP.  The command error code
; separates reader/I/O failure from a language failure without exposing the
; imported error values.
ARFAIL:
        CALL ARCLOSE               ; Closing twice is harmless and preserves I/O.
        LD A,(ARCODE)              ; Read the command's saved failure code.
        CP 2                       ; Code 2 identifies source I/O failure.
        JR Z,ARPERR                ; Select the source I/O message.
        CP 4                       ; Code 4 identifies publication failure.
        JR Z,AROERR                ; Select the output message.
        LD DE,ARBADTXT             ; All other failures are compile errors.
        JR ARPRINT                 ; Print the selected diagnostic.
ARPERR:
        LD DE,ARIOTXT              ; Point at the source I/O diagnostic.
        JR ARPRINT                 ; Print the selected diagnostic.
AROERR:
        LD DE,AROUTTXT             ; Point at the output diagnostic.
ARPRINT:
        LD C,9                      ; CP/M function 9 prints a dollar-terminated string.
        CALL 5                     ; CP/M console output always uses the vector.
        LD C,0                     ; CP/M function 0 returns to the CCP.
        CALL 5                     ; Warm boot returns to the CCP prompt.
        JP 0                       ; Keep the return address out of the command stack.

; Close the source only when CSOPEN has made it active.  This helper is also
; used after output errors, where the source must not remain locked.
ARCLOSE:
        LD A,(AROPEN)              ; Check whether CSOPEN made the source active.
        OR A                       ; Set flags from the open-state marker.
        RET Z                      ; Nothing needs closing when the marker is clear.
        CALL CSCLOSE                ; Close the source and preserve its sticky status.
        XOR A                      ; Clear the marker even after a close attempt.
        LD (AROPEN),A              ; Prevent a second cleanup from reopening the file.
        RET                        ; Return with the close status from CSCLOSE.
