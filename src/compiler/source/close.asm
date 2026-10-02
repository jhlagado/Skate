; CP/M source closing and BDOS adapter.
; Entry points: CSCLOSE, CICLOSE and CSBDOS.
; CSCLOSE -- release the source and report the complete stream outcome
;
; Out: carry clear iff open/read/include/close all succeeded; A = CSERROR.
; Closing twice is harmless. An earlier error takes precedence over close.
; CICLOSE closes only the open part and leaves the stream state unchanged.
; ----------------------------------------------------------------------------
CSCLOSE:
        LD A,1
        LD (CSDONE),A            ; No byte is read after an explicit close.
CICLOSE:
        LD HL,CSOPENF            ; Close only an FCB that is still open.
        LD A,(HL)
        OR A
        JR Z,.RESULT
        LD (HL),0                ; A failed close is never retried.
        LD DE,CSFCB
        LD C,16                  ; BDOS close-file function.
        CALL CSBDOS
        INC A                    ; CP/M returns FFH for a failed close.
        LD A,3
        CALL Z,CSFAIL            ; Record error 3 unless an earlier one exists.
.RESULT:
        LD A,(CSERROR)
        OR A
        RET Z                    ; Carry clear: no source failure is recorded.
        SCF
        RET

CSBDOS: PUSH IX          ; CP/M promises the 8080 interface, not Z80 indexes.
        PUSH IY
        CALL 5
        POP IY
        POP IX
        RET
