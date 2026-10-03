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
        LD HL,(SRTGBASE)
        LD DE,(SRTGEND)
        CALL ROOT_FIX
        LD HL,(SRTQROOT)
        LD DE,(SRTQENDR)
        CALL ROOT_FIX
        CALL ROOT_PKT
        CALL ROOT_ARG              ; Generated operand records remain live until consumed.
        CALL ROOT_OPS
        CALL ROOT_QT
        CALL ROOT_DR               ; Reader values remain live during pair folding.
        CALL ROOT_ENV
        CALL SRTCEROT              ; Scan maps saved by active call/ec records.
        LD A,(SRTDRACC)
        OR A
        JR Z,.QUOTED                ; No separate list accumulator is active.
        LD A,(SRTDATAG)
        LD HL,(SRTDAVAL)
        CALL GC_VALUE
.QUOTED:
        LD A,(SRTQACTV)
        OR A
        RET Z
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        JP GC_VALUE

; Record one generated operand in the exact shadow root stack.  A:HL is
; returned unchanged so SCPUSH can continue with the native stack operation.
ROOT_ADD:
        LD (SRTNRTAG),A
        LD (SRTNRVAL),HL
        LD A,(SRTNCT)
        CP 255
        JP NC,SRTERROR
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTNRTAB
        ADD HL,DE
        LD DE,(SRTNRVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A                  ; The extension byte stays clear.
        INC HL
        LD A,(SRTNRTAG)
        OR CELL_VAL                ; A live record and its tag.
        LD (HL),A
        LD A,(SRTNCT)
        INC A
        LD (SRTNCT),A
        LD A,(SRTNRTAG)
        LD HL,(SRTNRVAL)
        RET

; Remove B most-recent generated operand records while preserving A:HL.
ROOT_CUT:
        PUSH AF
        PUSH HL
        LD A,(SRTNCT)
        CP B
        JR C,.BAD
        SUB B
        LD (SRTNCT),A
        POP HL
        POP AF
        OR A                       ; A remains intact while successful removal clears carry.
        RET
.BAD:
        JP SRTERROR

; Remove one generated operand record while preserving A:HL.
ROOT_POP:
        LD B,1
        JP ROOT_CUT

; Mark the active reader value stack during a collection.
ROOT_DR:
        LD A,(SRTDRACT)             ; An inactive reader has no temporary roots.
        OR A
        RET Z
        LD HL,RT_DRVLO              ; Reader values occupy four-byte records.
        LD DE,(SRTDRVP)             ; The live cursor bounds the root range.
        JP ROOT_RAW

; Scan the active generated-operand records.
ROOT_ARG:
        LD A,(SRTNCT)
        OR A
        RET Z
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTNRTAB
        ADD HL,DE
        EX DE,HL
        LD HL,SRTNRTAB
        JP ROOT_RAW

; Walk a half-open range of four-byte static value records.  The final byte
; is the publication flag, so unused cache and static slots are ignored.
ROOT_FIX:
        LD (SRTROOTP),HL
        LD (SRTROOTE),DE
.LOOP:
        LD HL,(SRTROOTP)
        LD DE,(SRTROOTE)
        OR A
        SBC HL,DE
        RET NC
        LD HL,(SRTROOTP)
        CALL .RECORD
        LD HL,(SRTROOTP)
        LD DE,4
        ADD HL,DE
        LD (SRTROOTP),HL
        JR .LOOP

; Visit one published four-byte value record when its initialized bit is set.
.RECORD:
        LD (SRTROOTV),HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND CELL_VAL
        RET Z
        LD A,(HL)
        AND 0FH
        LD (SRTROOTT),A
        LD A,(SRTROOTT)
        LD HL,(SRTROOTV)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP GC_VALUE

; Visit a transient four-byte value record.  The enclosing cursor, rather than
; its spare byte, determines whether this record is live.
ROOT_REC:
        LD (SRTROOTV),HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH
        LD (SRTROOTT),A
        LD A,(SRTROOTT)
        LD HL,(SRTROOTV)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP GC_VALUE

; Scan exactly the active argument packet entries.
ROOT_PKT:
        LD A,(SRTARGC)
        OR A
        RET Z
        LD B,A
        LD HL,SRTARGPK
        LD (SRTROOTP),HL
.LOOP:
        LD HL,(SRTROOTP)
        PUSH BC
        CALL ROOT_REC
        POP BC
        LD HL,(SRTROOTP)
        LD DE,4
        ADD HL,DE
        LD (SRTROOTP),HL
        DJNZ .LOOP
        RET

; Scan active operator-stack records up to the published cursor.
ROOT_OPS:
        LD HL,RT_OPLO
        LD DE,(SRTOPS)
        JP ROOT_RAW

; Scan active quoted-data records up to the published cursor.
ROOT_QT:
        LD HL,RT_QTLO
        LD DE,(SRTQSP)
        JP ROOT_RAW

; Walk a half-open range of active four-byte records without reading a flag.
ROOT_RAW:
        LD (SRTROOTP),HL
        LD (SRTROOTE),DE
.LOOP:
        LD HL,(SRTROOTP)
        LD DE,(SRTROOTE)
        OR A
        SBC HL,DE
        RET NC
        LD HL,(SRTROOTP)
        PUSH HL
        CALL ROOT_REC
        POP HL
        LD DE,4
        ADD HL,DE
        LD (SRTROOTP),HL
        JR .LOOP

; Scan current and suspended environment maps.  Each entry is a binding
; pointer.  A frame is always ten bytes below its map.  Its caller descriptor
; is paired with the caller map saved in the same frame.
ROOT_ENV:
        LD HL,(SRTENV)
        LD A,(SRTSLOTS)
        CALL ROOT_MAP
        LD HL,(SRTFRAME)
        LD (SRTROOTP),HL
        LD DE,(SRTENV)
        OR A
        SBC HL,DE
        JR Z,.WALK
        LD HL,(SRTCENV)
        LD A,(SRTCENVN)
        CALL ROOT_MAP
        LD HL,(SRTFRAME)
.WALK:
        LD HL,(SRTROOTP)
        LD A,H
        OR L
        JR Z,.CALLER
.FRAME:
        LD HL,(SRTROOTP)
        LD DE,8
        OR A
        SBC HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTFRMD),DE
        LD HL,(SRTROOTP)
        LD DE,10
        OR A
        SBC HL,DE
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTROOTP),DE
        LD HL,(SRTROOTP)
        LD A,H
        OR L
        RET Z
        LD HL,(SRTFRMD)
        LD A,H
        OR L
        JR Z,.CALLER
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD HL,(SRTROOTP)
        CALL ROOT_MAP
        LD HL,(SRTROOTP)
        JR .FRAME
.CALLER:
        LD HL,(SRTCENV)
        LD A,(SRTCENVN)
        JP ROOT_MAP

ROOT_MAP:
        OR A
        RET Z
        LD (SRTENVP),HL
        LD (SRTENVN),A
.LOOP:
        LD HL,(SRTENVP)
        PUSH BC
        CALL SLOT_GC              ; Active entries are four-byte inline/promoted slots.
        POP BC
        LD HL,(SRTENVP)
        LD DE,4
        ADD HL,DE
        LD (SRTENVP),HL
        LD A,(SRTENVN)
        DEC A
        LD (SRTENVN),A
        JR NZ,.LOOP
        RET
