; Exact root discovery for stacks, packets, static slots and frames.
; Entry points: ROOT_ALL, ROOT_ADD, ROOT_RAW and ROOT_ENV.
; Included in runtime order by ../roots.asm.

; Exact root discovery for the scope-control runtime.
;
; Static value records are bounded by compiler-patched addresses.  Transient
; stacks and packets are bounded by live cursors, and environment maps carry
; explicit slot counts.  The tracer dispatches by the stored Scheme tag before
; interpreting a payload as a pair, closure or binding reference.

; Visit every declared root category.  Static ranges are compiler-patched;
; transient ranges use their active cursors, and frame maps use slot counts.
ROOT_ALL:
        CALL GC_CONS               ; Constructor inputs are roots at allocation.
        LD HL,(G_BASE)
        LD DE,(G_END)
        CALL ROOT_FIX
        LD HL,(QT_START)
        LD DE,(QT_STOP)
        CALL ROOT_FIX
        CALL ROOT_PKT
        CALL ROOT_ARG              ; Generated operand records remain live until consumed.
        CALL ROOT_OPS
        CALL ROOT_QT
        CALL ROOT_DR               ; Reader values remain live during pair folding.
        CALL ROOT_ENV
        CALL EC_ROOTS              ; Scan maps saved by active call/ec records.
        LD A,(DR_HELD)
        OR A
        JR Z,.QUOTED                ; No separate list accumulator is active.
        LD A,(DR_ATAG)
        LD HL,(DR_ACC)
        CALL GC_VALUE
.QUOTED:
        LD A,(QT_HELD)
        OR A
        RET Z
        LD A,(QT_ATAG)
        LD HL,(QT_ACC)
        JP GC_VALUE

; Record one generated operand in the exact shadow root stack.  A:HL is
; returned unchanged so EM_PUSH can continue with the native stack operation.
ROOT_ADD:
        LD (ROOT_TAG),A
        LD (ROOT_VAL),HL
        LD A,(ROOT_CNT)
        CP 255
        JP NC,ERROR
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,ROOT_TAB
        ADD HL,DE
        LD DE,(ROOT_VAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A                  ; The extension byte stays clear.
        INC HL
        LD A,(ROOT_TAG)
        OR CELL_VAL                ; A live record and its tag.
        LD (HL),A
        LD A,(ROOT_CNT)
        INC A
        LD (ROOT_CNT),A
        LD A,(ROOT_TAG)
        LD HL,(ROOT_VAL)
        RET

; Remove B most-recent generated operand records while preserving A:HL.
ROOT_CUT:
        PUSH AF
        PUSH HL
        LD A,(ROOT_CNT)
        CP B
        JR C,.BAD
        SUB B
        LD (ROOT_CNT),A
        POP HL
        POP AF
        OR A                       ; A remains intact while successful removal clears carry.
        RET
.BAD:
        JP ERROR

; Remove one generated operand record while preserving A:HL.
ROOT_POP:
        LD B,1
        JP ROOT_CUT

; Mark the active reader value stack during a collection.
ROOT_DR:
        LD A,(DR_LIVE)              ; An inactive reader has no temporary roots.
        OR A
        RET Z
        LD HL,RT_DRVLO              ; Reader values occupy four-byte records.
        LD DE,(DR_SP)               ; The live cursor bounds the root range.
        JP ROOT_RAW

; Scan the active generated-operand records.
ROOT_ARG:
        LD A,(ROOT_CNT)
        OR A
        RET Z
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,ROOT_TAB
        ADD HL,DE
        EX DE,HL
        LD HL,ROOT_TAB
        JP ROOT_RAW

; Walk a half-open range of four-byte static value records.  The final byte
; is the publication flag, so unused cache and static slots are ignored.
ROOT_FIX:
        LD (ROOT_PTR),HL
        LD (ROOT_END),DE
.LOOP:
        LD HL,(ROOT_PTR)
        LD DE,(ROOT_END)
        OR A
        SBC HL,DE
        RET NC
        LD HL,(ROOT_PTR)
        CALL .RECORD
        LD HL,(ROOT_PTR)
        LD DE,4
        ADD HL,DE
        LD (ROOT_PTR),HL
        JR .LOOP

; Visit one published four-byte value record when its initialized bit is set.
.RECORD:
        LD (GC_VAL),HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND CELL_VAL
        RET Z
        LD A,(HL)
        AND 0FH
        LD (GC_TAG),A
        LD A,(GC_TAG)
        LD HL,(GC_VAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP GC_VALUE

; Visit a transient four-byte value record.  The enclosing cursor, rather than
; its spare byte, determines whether this record is live.
ROOT_REC:
        LD (GC_VAL),HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH
        LD (GC_TAG),A
        LD A,(GC_TAG)
        LD HL,(GC_VAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP GC_VALUE

; Scan exactly the active argument packet entries.
ROOT_PKT:
        LD A,(ARG_CNT)
        OR A
        RET Z
        LD B,A
        LD HL,ARG_PKT
        LD (ROOT_PTR),HL
.LOOP:
        LD HL,(ROOT_PTR)
        PUSH BC
        CALL ROOT_REC
        POP BC
        LD HL,(ROOT_PTR)
        LD DE,4
        ADD HL,DE
        LD (ROOT_PTR),HL
        DJNZ .LOOP
        RET

; Scan active operator-stack records up to the published cursor.
ROOT_OPS:
        LD HL,RT_OPLO
        LD DE,(OPS_SP)
        JP ROOT_RAW

; Scan active quoted-data records up to the published cursor.
ROOT_QT:
        LD HL,RT_QTLO
        LD DE,(QT_SP)
        JP ROOT_RAW

; Walk a half-open range of active four-byte records without reading a flag.
ROOT_RAW:
        LD (ROOT_PTR),HL
        LD (ROOT_END),DE
.LOOP:
        LD HL,(ROOT_PTR)
        LD DE,(ROOT_END)
        OR A
        SBC HL,DE
        RET NC
        LD HL,(ROOT_PTR)
        PUSH HL
        CALL ROOT_REC
        POP HL
        LD DE,4
        ADD HL,DE
        LD (ROOT_PTR),HL
        JR .LOOP

; Scan current and suspended environment maps.  Each entry is a binding
; pointer.  A frame is always ten bytes below its map.  Its caller descriptor
; is paired with the caller map saved in the same frame.
ROOT_ENV:
        LD HL,(ENV_CUR)
        LD A,(SLOT_CNT)
        CALL ROOT_MAP
        LD HL,(FRM_BASE)
        LD (ROOT_PTR),HL
        LD DE,(ENV_CUR)
        OR A
        SBC HL,DE
        JR Z,.WALK
        LD HL,(ENV_RET)
        LD A,(ENV_RCNT)
        CALL ROOT_MAP
        LD HL,(FRM_BASE)
.WALK:
        LD HL,(ROOT_PTR)
        LD A,H
        OR L
        JR Z,.CALLER
.FRAME:
        LD HL,(ROOT_PTR)
        LD DE,8
        OR A
        SBC HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (DESC_FRM),DE
        LD HL,(ROOT_PTR)
        LD DE,10
        OR A
        SBC HL,DE
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (ROOT_PTR),DE
        LD HL,(ROOT_PTR)
        LD A,H
        OR L
        RET Z
        LD HL,(DESC_FRM)
        LD A,H
        OR L
        JR Z,.CALLER
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD HL,(ROOT_PTR)
        CALL ROOT_MAP
        LD HL,(ROOT_PTR)
        JR .FRAME
.CALLER:
        LD HL,(ENV_RET)
        LD A,(ENV_RCNT)
        JP ROOT_MAP

ROOT_MAP:
        OR A
        RET Z
        LD (GC_ENVP),HL
        LD (GC_LEFT),A
.LOOP:
        LD HL,(GC_ENVP)
        PUSH BC
        CALL SLOT_GC              ; Active entries are four-byte inline/promoted slots.
        POP BC
        LD HL,(GC_ENVP)
        LD DE,4
        ADD HL,DE
        LD (GC_ENVP),HL
        LD A,(GC_LEFT)
        DEC A
        LD (GC_LEFT),A
        JR NZ,.LOOP
        RET
