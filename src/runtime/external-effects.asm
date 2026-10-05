; CP/M byte bridge for external-effect providers.
; FX_PUT: A = byte; success returns A=0/carry clear. FF is rejected because BDOS
; function 6 reserves it as the input selector. FX_GET returns a byte or A=0 when
; no byte is available; direct BDOS polling cannot distinguish an available zero.
; Both entries preserve IX, IY and SP. The provider owns framing and device
; meaning; this bridge carries only the byte-preserving console subset.

FX_PUT:
        CP 0FFH                ; Keep the BDOS input selector out of output.
        JR Z,.FAIL
        PUSH IX                 ; BDOS may clobber the index registers.
        PUSH IY                 ; Preserve the caller's second index register.
        LD E,A                  ; Direct BDOS 6 takes its output byte in E.
        LD C,6                  ; Select direct console I/O.
        CALL 5                  ; Enter the resident CP/M BDOS vector.
        POP IY                  ; Restore the caller's index registers.
        POP IX
        XOR A                   ; The byte was accepted; return a clear status.
        RET

.FAIL:
        LD A,1                  ; FF is unavailable on the portable console.
        SCF
        RET

; Poll one byte through direct console input without BDOS echo.
FX_GET:
        PUSH IX                 ; Preserve IX before the BDOS call.
        PUSH IY                 ; Preserve IY before the BDOS call.
        LD E,0FFH               ; BDOS 6/FF requests a direct input poll.
        LD C,6                  ; Select direct console I/O.
        CALL 5                  ; BDOS returns a byte, or zero when empty.
        POP IY                  ; Restore index registers without changing A.
        POP IX
        RET
