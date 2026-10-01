; Runtime transfer and cleanup of captured slot maps.
; Entry points: SRTCOPYM, SRTCLSC and SRTCLNSE.
SRTCOPYM:
        LD HL,(SRTDESC)
        LD DE,SRTCAPOF
        ADD HL,DE
        LD (SRTMASKP),HL
        LD HL,(SRTOBJ)
        LD DE,2
        ADD HL,DE
        LD (SRTSRC),HL
        XOR A
        LD (SRTSLOTI),A
        LD A,SRTMASKB
        LD (SRTMASKN),A
SRTCPMB:
        LD HL,(SRTMASKP)
        LD A,(HL)
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD A,8
        LD (SRTBITN),A
SRTCPMBT:
        LD A,(SRTMASKV)
        AND 1
        JR Z,SRTCPMN
        LD A,(SRTSLOTI)
        CALL SRTSADDR
        LD (SRTSADR),HL
        LD A,(SRTSLOTI)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,(SRTSRC)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,SRTCPMZ
        LD HL,(SRTSADR)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD A,SRTSPROM
        LD (HL),A
        JR SRTCPMN
SRTCPMZ:
        LD HL,(SRTSADR)
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
SRTCPMN:
        LD A,(SRTMASKV)
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,SRTCPMBT
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,SRTCPMB
        RET

; Copy promoted active pointers into the new closure's two-byte environment.
; The closure block is cleared before this pass, so uncaptured entries stay zero.
SRTCLSC:
        LD HL,(SRTNEWD)
        LD DE,SRTCAPOF
        ADD HL,DE
        LD (SRTMASKP),HL
        LD HL,(SRTENV)
        LD (SRTSRC),HL
        LD HL,(SRTNENV)
        LD (SRTSVAL),HL
        XOR A
        LD (SRTSLOTI),A
        LD A,SRTMASKB
        LD (SRTMASKN),A
SRTCLSB:
        LD HL,(SRTMASKP)
        LD A,(HL)
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD A,8
        LD (SRTBITN),A
SRTCLST:
        LD A,(SRTMASKV)
        AND 1
        JR Z,SRTCLSN
        LD A,(SRTSLOTI)
        CALL SRTSADDR
        LD (SRTSADR),HL
        LD HL,(SRTSADR)            ; Active maps use four-byte slots, not closure stride.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTCELLP),DE
        LD A,(SRTSLOTI)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,(SRTSVAL)
        ADD HL,DE
        LD DE,(SRTCELLP)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
SRTCLSN:
        LD A,(SRTMASKV)
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,SRTCLST
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,SRTCLSB
        RET

; Clear active slots that are neither owned by nor captured into the target.
; This prevents an old tail frame from retaining roots outside its shape.
SRTCLNSE:
        LD HL,(SRTDESC)
        LD DE,SRTOWNOF
        ADD HL,DE
        LD (SRTMASKP),HL
        LD HL,(SRTDESC)
        LD DE,SRTCAPOF
        ADD HL,DE
        LD (SRTSRC),HL
        XOR A
        LD (SRTSLOTI),A
        LD A,SRTMASKB
        LD (SRTMASKN),A
SRTCLNB:
        LD HL,(SRTMASKP)
        LD A,(HL)
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD HL,(SRTSRC)
        LD A,(HL)
        INC HL
        LD (SRTSRC),HL
        LD (SRTSVTAG),A
        LD A,8
        LD (SRTBITN),A
SRTCLNT:
        LD A,(SRTSLOTI)
        LD C,A
        LD A,(SRTSLOTS)
        CP C
        JR C,SRTCLND
        JR Z,SRTCLND
        LD A,(SRTMASKV)
        AND 1
        JR NZ,SRTCLNN
        LD A,(SRTSVTAG)
        AND 1
        JR NZ,SRTCLNN
        LD A,C
        CALL SRTSADDR
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
SRTCLNN:
        LD A,(SRTMASKV)
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSVTAG)
        SRL A
        LD (SRTSVTAG),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,SRTCLNT
SRTCLND:
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,SRTCLNB
        RET

; Trace one active four-byte slot during root discovery.
