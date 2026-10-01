; Primitive character input and output adapters.
; Entry points: SRTWCHR and SRTRDCH.
; Included in runtime order by ../primitives.asm.

; Character output and console input use the CP/M console byte interface.
SRTIO:
        LD A,(SRTPID)
        CP 29
        JP Z,SRTWCHR
        JP SRTRDCH

; write-char accepts one byte character and an optional output port, then
; returns UNSPECIFIED.  The one-argument form remains source-compatible.
SRTWCHR:
        CALL SRTOUT1
        CALL SRTONE
        OR A
        JP NZ,SRTERROR              ; Only scalar character values are writable.
        LD A,H
        CP 0FFH
        JP NZ,SRTERROR              ; FFxx is the byte-character representation.
        LD A,L
        CALL SRTCH                   ; BDOS function two writes the selected byte.
        JP SRTUNSP

; read-char accepts no arguments or an explicit current input port and maps
; CP/M Control-Z to the EOF singleton.
SRTRDCH:
        CALL SRTINSET
        CALL SRTINNXT              ; Shared input consumes pending lookahead first.
        PUSH IX
        RET
