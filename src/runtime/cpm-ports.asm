; Byte services used by the standard Scheme ports.
;
; The words at CON_PUT and CON_GET are the only target-specific boundary
; used by normal text I/O. They initially point at the direct CP/M routines
; below. A resident provider or a test harness may replace the words before
; START without changing the Scheme value ABI. A service returns with
; carry clear after accepting or producing one byte; carry set is a checked
; provider failure.

; Indirect calls keep the provider entry outside the compiler's fixed image.
CON_SEND:
        LD HL,(CON_PUT)            ; Load the current output service address.
        JP (HL)                    ; The service returns through this call frame.

CON_READ:
        LD HL,(CON_GET)            ; Load the current input service address.
        JP (HL)                    ; The service returns through this call frame.

; Direct CP/M byte services are the default target profile.
CON_TYPE:
        LD E,A                     ; BDOS function two receives the byte in E.
        LD C,2                     ; Select direct console output.
        CALL 5                     ; Enter the resident CP/M BDOS vector.
        XOR A                      ; Carry clear reports an accepted byte.
        RET

CON_KEY:
        LD C,1                     ; BDOS function one reads one console byte.
        CALL 5                     ; CP/M returns the physical byte in A.
        OR A                       ; Preserve the byte while clearing carry.
        RET

; Resident service vectors. They are data so a provider can patch them before
; running a program; the direct CP/M targets preserve the existing behavior.
CON_PUT: DW CON_TYPE              ; Physical byte output service.
CON_GET: DW CON_KEY               ; Physical byte input service.
