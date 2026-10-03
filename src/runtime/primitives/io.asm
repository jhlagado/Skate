; Primitive character input and output adapters.
; Entry points: .PUT_CHAR and PKT_GETC.
; Included in runtime order by ../primitives.asm.

; Character output and console input use the CP/M console byte interface.
PRIM_IO:
        LD A,(SRTPID)
        CP 29
        JP Z,.PUT_CHAR
        JP PKT_GETC

; write-char accepts one byte character and an optional output port, then
; returns UNSPECIFIED.  The one-argument form remains source-compatible.
.PUT_CHAR:
        CALL SRTOUT1
        CALL PKT_ONE
        OR A
        JP NZ,SRTERROR              ; Only scalar character values are writable.
        LD A,H
        CP 0FFH
        JP NZ,SRTERROR              ; FFxx is the byte-character representation.
        LD A,L
        CALL SRTCH                   ; BDOS function two writes the selected byte.
        JP PKT_VOID

; read-char accepts no arguments or an explicit current input port and maps
; CP/M Control-Z to the EOF singleton.
PKT_GETC:
        CALL SRTINSET
        CALL SRTINNXT              ; Shared input consumes pending lookahead first.
        PUSH IX
        RET
