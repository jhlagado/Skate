; CP/M source closing and BDOS adapter.
; Entry points: CSCLOSE and CSBDOS.
; CSCLOSE -- release source and report the complete stream outcome
;
; Out: carry clear iff open/read/close all succeeded; A = CSERROR.
; Closing twice is harmless. An earlier error takes precedence over close.
; ----------------------------------------------------------------------------
CSCLOSE:
        LD A,(CSINDEX+1)
        CP 2
        JP Z,CICLOSE
        OR A
        JR NZ,.PKCLOS
        LD A,(CSACTIVE)
        OR A
        JR Z,.RESULT
        XOR A
        LD (CSACTIVE),A
        LD DE,CSFCB
        LD C,16
        CALL CSBDOS
        CP 255
        JR NZ,.RESULT
        LD A,(CSERROR)
        OR A
        JR NZ,.RESULT
        LD A,3
        LD (CSERROR),A
.RESULT:
        LD A,1
        LD (CSDONE),A
        LD A,(CSERROR)
        OR A
        RET Z
        SCF
        RET
.PKCLOS:
        LD A,(CSINDEX+3)
        OR A
        JR Z,.PKMAN
        XOR A
        LD (CSINDEX+3),A
        LD DE,CSFCB
        LD C,16
        CALL CSBDOS
        CP 255
        JR NZ,.PKMAN
        LD A,(CSERROR)
        OR A
        JR NZ,.PKMAN
        LD A,3
        LD (CSERROR),A
.PKMAN:
        LD A,(CSINDEX+2)
        OR A
        JR Z,.RESULT
        XOR A
        LD (CSINDEX+2),A
        LD DE,CSMANFCB
        LD C,16
        CALL CSBDOS
        CP 255
        JR NZ,.RESULT
        LD A,(CSERROR)
        OR A
        JR NZ,.RESULT
        LD A,3
        LD (CSERROR),A
CSBDOS: PUSH IX          ; CP/M promises the 8080 interface, not Z80 indexes.
        PUSH IY
        CALL 5
        POP IY
        POP IX
        LD (CSWORK+1),A
        RET
CSWORK:
