; Runtime transfer and cleanup of captured slot maps.
; Entry points: MAP_COPY, MAP_ENV and MAP_TRIM.
MAP_COPY:
        LD HL,(SRTDESC)
        CALL DESC_CAP
        LD (SRTMASKP),HL
        LD (SRTMASKN),A
        LD HL,(SRTOBJ)
        LD DE,2
        ADD HL,DE
        LD (SRTSRC),HL
        XOR A
        LD (SRTSLOTI),A
        LD A,(SRTMASKN)
        OR A
        RET Z                      ; Nothing is captured.
.BYTE:
        LD HL,(SRTMASKP)
        LD A,(HL)
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD A,8
        LD (SRTBITN),A
.BIT:
        LD A,(SRTMASKV)
        AND 1
        JR Z,.NEXT
        LD A,(SRTSLOTI)
        CALL SLOT_AT
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
        JR Z,.ZERO
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
        LD A,SLOT_PTR
        LD (HL),A
        JR .NEXT
.ZERO:
        LD HL,(SRTSADR)
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
.NEXT:
        LD A,(SRTMASKV)
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,.BIT
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,.BYTE
        RET

; Copy promoted active pointers into the new closure's two-byte environment.
; The closure block is cleared before this pass, so uncaptured entries stay zero.
MAP_ENV:
        LD HL,(SRTNEWD)
        CALL DESC_CAP
        LD (SRTMASKP),HL
        LD (SRTMASKN),A
        LD HL,(SRTENV)
        LD (SRTSRC),HL
        LD HL,(SRTNENV)
        LD (SRTSVAL),HL
        XOR A
        LD (SRTSLOTI),A
        LD A,(SRTMASKN)
        OR A
        RET Z                      ; Nothing is captured.
.BYTE:
        LD HL,(SRTMASKP)
        LD A,(HL)
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD A,8
        LD (SRTBITN),A
.BIT:
        LD A,(SRTMASKV)
        AND 1
        JR Z,.NEXT
        LD A,(SRTSLOTI)
        CALL SLOT_AT
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
.NEXT:
        LD A,(SRTMASKV)
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,.BIT
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,.BYTE
        RET

; Clear active slots that are neither owned by nor captured into the target.
; This prevents an old tail frame from retaining roots outside its shape.
MAP_TRIM:
        LD HL,(SRTDESC)
        CALL DESC_OWN
        LD (SRTMASKP),HL
        LD (SRTMASKR),A            ; Mask bytes beyond the width read as zero.
        LD E,A
        LD D,0
        ADD HL,DE
        LD (SRTSRC),HL
        XOR A
        LD (SRTSLOTI),A
        LD A,SRTMASKB              ; Every slot below SRTSLOTS is examined.
        LD (SRTMASKN),A
.BYTE:
        LD A,(SRTMASKR)
        OR A
        JR Z,.NONE                 ; Neither owned nor captured.
        DEC A
        LD (SRTMASKR),A
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
        JR .BITS
.NONE:
        LD (SRTMASKV),A
        LD (SRTSVTAG),A
.BITS:
        LD A,8
        LD (SRTBITN),A
.BIT:
        LD A,(SRTSLOTI)
        LD C,A
        LD A,(SRTSLOTS)
        CP C
        JR C,.BYTE_END
        JR Z,.BYTE_END
        LD A,(SRTMASKV)
        AND 1
        JR NZ,.NEXT
        LD A,(SRTSVTAG)
        AND 1
        JR NZ,.NEXT
        LD A,C
        CALL SLOT_AT
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
.NEXT:
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
        JR NZ,.BIT
.BYTE_END:
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,.BYTE
        RET

; Trace one active four-byte slot during root discovery.
