; CP/M source closing and BDOS adapter.
; Entry points: SRC_END, SRC_SHUT and SRC_BDOS.
; SRC_END -- release the source and report the complete stream outcome
;
; Out: carry clear iff open/read/include/close all succeeded; A = SRC_ERR.
; Closing twice is harmless. An earlier error takes precedence over close.
; SRC_SHUT closes only the open part and leaves the stream state unchanged.
; ----------------------------------------------------------------------------
SRC_END:
        LD A,1
        LD (SRC_DONE),A          ; No byte is read after an explicit close.
SRC_SHUT:
        LD HL,SRC_LIVE           ; Close only an FCB that is still open.
        LD A,(HL)
        OR A
        JR Z,.RESULT
        LD (HL),0                ; A failed close is never retried.
        LD DE,SRC_FCB
        LD C,16                  ; BDOS close-file function.
        CALL SRC_BDOS
        INC A                    ; CP/M returns FFH for a failed close.
        LD A,3
        CALL Z,SRC_FAIL          ; Record error 3 unless an earlier one exists.
.RESULT:
        LD A,(SRC_ERR)
        OR A
        RET Z                    ; Carry clear: no source failure is recorded.
        SCF
        RET

SRC_BDOS: PUSH IX        ; CP/M promises the 8080 interface, not Z80 indexes.
        PUSH IY
        CALL 5
        POP IY
        POP IX
        RET
