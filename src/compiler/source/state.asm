; CP/M source stream state and private buffers.
; Data labels are shared by the source modules.
CSERROR: DB 0
        DB 0                  ; Last raw BDOS status (CSWORK+1).
CSACTIVE: DB 0
CSDONE: DB 0
CSPARTNO: DB 0               ; Current zero-based source-table ordinal.
CSPEND: DB 0              ; First real byte has not reset this part yet.
CSINDEX: DB 128
        ; Package state bytes follow CSINDEX (mode through part-done).
        DB 0
        DB 0
        DB 0
        DB 0
        DB 0
        DB 0
        DB 128
        DB 0
        DB 0
        DB 0
        DB 0
        DB 128
        DB 0
        DB 0                  ; Manifest byte count low/high at CSINDEX+14/+15.
        DB 0
        DB 0                  ; Native root skip low/high at CSINDEX+16/+17.
        DB 0
        DB 0                  ; Native output part index and phase at +18/+19.
        DB 0
CILAST:  DB 0                ; Last emitted byte, for clean part boundaries.
        DB 0
        DB 0
        DB 0
        DB 0
        DB 0
CIHEADS: DB "include"        ; Native include parser's fixed directive spelling.
CIFORM:  DW 0                 ; Opening offset of the current root form.
CIPOS:   DW 0                 ; Physical root scan position.
CIPLEN:  DB 0                 ; Length of the current quoted filename.
CIPDOT:  DB 0                 ; Extension separator has been seen.
CIBASE:  DB 0                 ; Base-name character count.
CIEXT:   DB 0                 ; Extension character count.
CIARG:   DB 0                 ; Current include form has at least one name.
CITGT:   DW 0                 ; Destination prefix while a name is assembled.
CSFCB: DS 36
CSMANFCB: DS 36
CSPART: DS 12
CSSEEN: DS 384
CSMANBUF: DS 128
CSBUFFER: DS 128

CSWEND:
