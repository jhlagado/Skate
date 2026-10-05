; Runtime transfer and cleanup of captured slot maps.
; Entry points: MAP_COPY, MAP_ENV and MAP_TRIM.
MAP_COPY:
        LD HL,(DESC_CUR)
        CALL DESC_CAP
        LD (MASK_PTR),HL
        LD (MASK_CNT),A
        LD HL,(FRM_CLOS)
        LD DE,2
        ADD HL,DE
        LD (FRM_SRC),HL
        XOR A
        LD (MASK_IDX),A
        LD A,(MASK_CNT)
        OR A
        RET Z                      ; Nothing is captured.
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
        CALL SLOT_AT
        LD (SLOT_CUR),HL
        LD A,(MASK_IDX)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,(FRM_SRC)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.ZERO
        LD HL,(SLOT_CUR)
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
        LD HL,(SLOT_CUR)
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
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

; Copy promoted active pointers into the new closure's two-byte environment.
; The closure block is cleared before this pass, so uncaptured entries stay zero.
MAP_ENV:
        LD HL,(DESC_NEW)
        CALL DESC_CAP
        LD (MASK_PTR),HL
        LD (MASK_CNT),A
        LD HL,(ENV_CUR)
        LD (FRM_SRC),HL
        LD HL,(ENV_DST)
        LD (SLOT_VAL),HL
        XOR A
        LD (MASK_IDX),A
        LD A,(MASK_CNT)
        OR A
        RET Z                      ; Nothing is captured.
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
        CALL SLOT_AT
        LD (SLOT_CUR),HL
        LD HL,(SLOT_CUR)           ; Active maps use four-byte slots, not closure stride.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (HEAP_OBJ),DE
        LD A,(MASK_IDX)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,(SLOT_VAL)
        ADD HL,DE
        LD DE,(HEAP_OBJ)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
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

; Clear active slots that are neither owned by nor captured into the target.
; This prevents an old tail frame from retaining roots outside its shape.
MAP_TRIM:
        LD HL,(DESC_CUR)
        CALL DESC_OWN
        LD (MASK_PTR),HL
        LD (MASK_FIT),A            ; Mask bytes beyond the width read as zero.
        LD E,A
        LD D,0
        ADD HL,DE
        LD (FRM_SRC),HL
        XOR A
        LD (MASK_IDX),A
        LD A,DESC_MAX              ; Every slot below SLOT_CNT is examined.
        LD (MASK_CNT),A
.BYTE:
        LD A,(MASK_FIT)
        OR A
        JR Z,.NONE                 ; Neither owned nor captured.
        DEC A
        LD (MASK_FIT),A
        LD HL,(MASK_PTR)
        LD A,(HL)
        INC HL
        LD (MASK_PTR),HL
        LD (MASK_VAL),A
        LD HL,(FRM_SRC)
        LD A,(HL)
        INC HL
        LD (FRM_SRC),HL
        LD (SLOT_TAG),A
        JR .BITS
.NONE:
        LD (MASK_VAL),A
        LD (SLOT_TAG),A
.BITS:
        LD A,8
        LD (MASK_BIT),A
.BIT:
        LD A,(MASK_IDX)
        LD C,A
        LD A,(SLOT_CNT)
        CP C
        JR C,.BYTE_END
        JR Z,.BYTE_END
        LD A,(MASK_VAL)
        AND 1
        JR NZ,.NEXT
        LD A,(SLOT_TAG)
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
        LD A,(MASK_VAL)
        SRL A
        LD (MASK_VAL),A
        LD A,(SLOT_TAG)
        SRL A
        LD (SLOT_TAG),A
        LD A,(MASK_IDX)
        INC A
        LD (MASK_IDX),A
        LD A,(MASK_BIT)
        DEC A
        LD (MASK_BIT),A
        JR NZ,.BIT
.BYTE_END:
        LD A,(MASK_CNT)
        DEC A
        LD (MASK_CNT),A
        JR NZ,.BYTE
        RET

; Trace one active four-byte slot during root discovery.
