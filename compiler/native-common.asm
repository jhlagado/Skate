;=============================================================================
;  Shared native compiler command support
;=============================================================================
;
;  N4 and N5 share the CP/M guard, diagnostics and source-close path.  Keeping
;  this small support block separate lets each front end carry only its own
;  evaluator while preserving one command contract.
;=============================================================================

N4MEMERR:
        LD DE,N4MEMTXT
        JP N4PRINT

; Print one diagnostic and return to the CCP.  N4CODE separates reader/I/O
; failure from a language failure without exposing the imported error values.
N4FAIL:
        CALL N4CLOSE               ; Closing twice is harmless and preserves I/O.
        LD A,(N4CODE)
        CP 2
        JR Z,N4PERR
        CP 4
        JR Z,N4OERR
        LD DE,N4BADTXT
        JR N4PRINT
N4PERR:
        LD DE,N4IOTXT
        JR N4PRINT
N4OERR:
        LD DE,N4OUTTXT
N4PRINT:
        LD C,9
        CALL 5                     ; CP/M console output always uses the vector.
        LD C,0
        CALL 5                     ; Warm boot returns to the CCP prompt.
        JP 0

; Close the source only when CSOPEN has made it active.  This helper is also
; used after output errors, where the source must not remain locked.
N4CLOSE:
        LD A,(N4OPEN)
        OR A
        RET Z
        CALL CSCLOSE
        XOR A
        LD (N4OPEN),A
        RET
