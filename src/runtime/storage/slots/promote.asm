; Runtime promotion of captured activation slots into managed cells.
; Entry points: SLOT_BOX and SLOT_CAP.
SLOT_BOX:
        LD (SRTSNUM),A              ; Preserve the slot across a collecting call.
        CALL SLOT_AT
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        AND SLOT_PTR
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
        CALL HEAP_NEW               ; The active inline value remains the root.
        LD (SRTCELLP),HL
        LD A,(SRTSNUM)              ; Recompute scratch clobbered by a collecting call.
        CALL SLOT_AT
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        AND CELL_VAL
        JR Z,.PUBLISH               ; An uninitialized cell is already cleared.
        LD DE,(SRTCELLP)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        CALL HEAP_PUT                ; No allocation occurs during publication.
.PUBLISH:
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
        LD A,SLOT_PTR
        LD (HL),A                   ; Publish the representation only after the cell.
        RET

; Promote every slot selected by the descriptor in SRTNEWD's capture mask.
SLOT_CAP:
        LD HL,(SRTNEWD)
        CALL DESC_CAP
        LD (SRTMASKP),HL
        OR A
        RET Z                      ; Nothing is captured.
        LD (SRTMASKN),A
        XOR A
        LD (SRTSLOTI),A
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
        CALL SLOT_BOX
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

; Copy captured two-byte closure pointers into four-byte active slots.
