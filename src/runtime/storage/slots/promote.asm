; Runtime promotion of captured activation slots into managed cells.
; Entry points: SRTPROM and SRTPRALL.
SRTPROM:
        LD (SRTSNUM),A              ; Preserve the slot across a collecting call.
        CALL SRTSADDR
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        AND SRTSPROM
        RET NZ                      ; The slot already names its managed cell.
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL                      ; Skip the extension byte.
        LD A,(HL)
        AND 0FH
        LD (SRTSVTAG),A
        LD (SRTSVAL),DE
        CALL SRTCELL                ; The active inline value remains the root.
        LD (SRTCELLP),HL
        LD A,(SRTSNUM)              ; Recompute scratch clobbered by a collecting call.
        CALL SRTSADDR
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        AND SRTCLIVE
        JR Z,SRTPROUN               ; An uninitialized cell is already cleared.
        LD DE,(SRTCELLP)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        CALL SRTBSTOR                ; No allocation occurs during publication.
SRTPROUN:
        LD HL,(SRTSADR)
        LD DE,(SRTCELLP)
        LD A,E
        LD (HL),A                   ; Replace the payload with the cell pointer.
        INC HL
        LD A,D
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A                   ; The promoted cell owns the tag.
        INC HL
        LD A,SRTSPROM
        LD (HL),A                   ; Publish the representation only after the cell.
        RET

; Promote every slot selected by the descriptor in SRTNEWD's capture mask.
SRTPRALL:
        LD HL,(SRTNEWD)
        CALL DESC_CAP
        LD (SRTMASKP),HL
        OR A
        RET Z                      ; Nothing is captured.
        LD (SRTMASKN),A
        XOR A
        LD (SRTSLOTI),A
SRTPRLB:
        LD HL,(SRTMASKP)
        LD A,(HL)
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD A,8
        LD (SRTBITN),A
SRTPRLBT:
        LD A,(SRTMASKV)
        AND 1
        JR Z,SRTPRLN
        LD A,(SRTSLOTI)
        CALL SRTPROM
SRTPRLN:
        LD A,(SRTMASKV)
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,SRTPRLBT
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,SRTPRLB
        RET

; Copy captured two-byte closure pointers into four-byte active slots.
