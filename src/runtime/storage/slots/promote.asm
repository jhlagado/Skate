; Runtime promotion of captured activation slots into managed cells.
; Entry points: SLOT_BOX and SLOT_CAP.
SLOT_BOX:
        LD (SLOT_NUM),A             ; Preserve the slot across a collecting call.
        CALL SLOT_AT
        LD (SLOT_CUR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SLOT_REP),A
        AND SLOT_PTR
        RET NZ                      ; The slot already names its managed cell.
        LD HL,(SLOT_CUR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL                      ; Skip the extension byte.
        LD A,(HL)
        AND 0FH
        LD (SLOT_TAG),A
        LD (SLOT_VAL),DE
        CALL HEAP_NEW               ; The active inline value remains the root.
        LD (HEAP_OBJ),HL
        LD A,(SLOT_NUM)             ; Recompute scratch clobbered by a collecting call.
        CALL SLOT_AT
        LD (SLOT_CUR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SLOT_REP),A
        AND CELL_VAL
        JR Z,.PUBLISH               ; An uninitialized cell is already cleared.
        LD DE,(HEAP_OBJ)
        LD HL,(SLOT_VAL)
        LD A,(SLOT_TAG)
        CALL HEAP_PUT                ; No allocation occurs during publication.
.PUBLISH:
        LD HL,(SLOT_CUR)
        LD DE,(HEAP_OBJ)
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

; Promote every slot selected by the descriptor in DESC_NEW's capture mask.
SLOT_CAP:
        LD HL,(DESC_NEW)
        CALL DESC_CAP
        LD (MASK_PTR),HL
        OR A
        RET Z                      ; Nothing is captured.
        LD (MASK_CNT),A
        XOR A
        LD (MASK_IDX),A
.BYTE:
        LD HL,(MASK_PTR)
        LD A,(HL)
        INC HL
        LD (MASK_PTR),HL
        LD (MASK_VAL),A
        LD A,8
        LD (MASK_BIT),A
.BIT:
        LD A,(MASK_VAL)
        AND 1
        JR Z,.NEXT
        LD A,(MASK_IDX)
        CALL SLOT_BOX
.NEXT:
        LD A,(MASK_VAL)
        SRL A
        LD (MASK_VAL),A
        LD A,(MASK_IDX)
        INC A
        LD (MASK_IDX),A
        LD A,(MASK_BIT)
        DEC A
        LD (MASK_BIT),A
        JR NZ,.BIT
        LD A,(MASK_CNT)
        DEC A
        LD (MASK_CNT),A
        JR NZ,.BYTE
        RET

; Copy captured two-byte closure pointers into four-byte active slots.
