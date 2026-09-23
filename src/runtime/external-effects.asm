;=============================================================================
;  CP/M byte bridge for external-effect providers
;=============================================================================
;
;  SEPUT writes one byte through CP/M direct console output (BDOS 6).  SEGET polls
;  direct console input (BDOS 6, E=FF), which does not echo a byte.  The
;  provider owns framing, mode changes and device meaning; this bridge only
;  carries the byte-preserving subset and preserves the Z80 index registers
;  around BDOS.
;
;  SEPUT: A = byte to send; returns A = 0/carry clear when accepted.  FF is
;         rejected with A = 1/carry set because BDOS 6 reserves E=FF for input.
;  SEGET: returns A = byte received, or A = 0 when no byte is available.
;         Portable BDOS cannot distinguish an available zero byte from an
;         empty console, so a full raw byte stream needs a provider-specific
;         channel rather than this console poll.
;  IX, IY and SP are preserved by both entry points.  Other registers are
;  scratch.  The bridge is deliberately independent of the Scheme runtime.
;=============================================================================

; Send one byte through direct console output.  Direct BDOS 6 does not expand
; tabs, but E=FF is reserved for input and therefore cannot be emitted here.
SEPUT:
        CP 0FFH                ; Keep the BDOS input selector out of output.
        JR Z,SEPFAIL
        PUSH IX                 ; BDOS may clobber the index registers.
        PUSH IY                 ; Preserve the caller's second index register.
        LD E,A                  ; Direct BDOS 6 takes its output byte in E.
        LD C,6                  ; Select direct console I/O.
        CALL 5                  ; Enter the resident CP/M BDOS vector.
        POP IY                  ; Restore the caller's index registers.
        POP IX
        XOR A                   ; The byte was accepted; return a clear status.
        RET

SEPFAIL:
        LD A,1                  ; FF is unavailable on the portable console.
        SCF
        RET

; Poll one byte through direct console input without BDOS echo.
SEGET:
        PUSH IX                 ; Preserve IX before the BDOS call.
        PUSH IY                 ; Preserve IY before the BDOS call.
        LD E,0FFH               ; BDOS 6/FF requests a direct input poll.
        LD C,6                  ; Select direct console I/O.
        CALL 5                  ; BDOS returns a byte, or zero when empty.
        POP IY                  ; Restore index registers without changing A.
        POP IX
        RET
