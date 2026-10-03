; Scope runtime activation maps, capture and ownership.
; Entry points: ENV_NEW, ENV_COPY, ENV_OWN and .ESCAPE.
; Included in runtime order by ../core.asm.

; Allocate a stack environment for an ordinary call and install fresh cells
; for every slot owned by the target procedure.
ENV_NEW:
        POP HL                    ; Remove the helper return before moving SP.
        LD (FRM_SAVE),HL          ; Restore it after the activation map is ready.
        LD HL,0                    ; Z80 has no direct LD HL,SP instruction.
        ADD HL,SP                  ; HL is the caller's stack boundary.
        LD (FRM_SP),HL             ; The body epilogue restores this boundary.
        LD A,(SLOT_CNT)            ; The descriptor gives the active-slot count.
        LD L,A                     ; Widen the slot count before sizing both maps.
        LD H,0
        ADD HL,HL                  ; Closure maps retain two-byte cell pointers.
        LD (FRM_CLEN),HL           ; Keep the closure-map byte count for descriptors.
        LD A,(SLOT_CNT)            ; Re-read the count for the four-byte active map.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL                  ; Four bytes describe every active slot.
        LD (FRM_MLEN),HL           ; The stack reservation follows the active extent.
        LD B,H
        LD C,L
        LD HL,(FRM_SP)             ; Reserve the pointer array below the caller stack.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,BC
        LD (DESC_PTR),HL           ; Keep the candidate while checking the guard.
        LD DE,RT_GUARD              ; Leave frame words above the heap boundary.
        OR A                       ; Clear carry before the boundary comparison.
        SBC HL,DE
        JP C,ERROR                 ; Reject a frame before moving the native stack.
        LD HL,(DESC_PTR)           ; Recover the checked activation boundary.
        LD SP,HL                   ; The new array remains above generated pushes.
        LD (ENV_CUR),HL            ; Runtime loads and stores use this four-byte map.
        LD (DESC_PTR),HL           ; Preserve the candidate stack boundary.
        LD DE,(RT_LOWSP)           ; Compare it with the lowest prior boundary.
        OR A                       ; Clear carry before the signed comparison.
        SBC HL,DE
        JR NC,.MAP                 ; A higher boundary leaves the low-water mark.
        LD HL,(DESC_PTR)           ; Recover the candidate address after the compare.
        LD (RT_LOWSP),HL           ; Publish the deepest native stack boundary.
.MAP:
        CALL SLOT_INI              ; Publish a zeroed map before any allocation can run.
        CALL MAP_COPY              ; Expand captured closure pointers into active slots.
        CALL MAP_TRIM              ; Drop any unused entries before root scanning begins.
        LD HL,(CNT_MAPS)           ; Count each activation map before body entry.
        INC HL
        LD (CNT_MAPS),HL
        CALL ENV_OWN               ; Allocate fresh cells for owned slots.
        LD HL,(FRM_SAVE)           ; Place the helper return below the map.
        PUSH HL
        RET

; HL = descriptor: return HL = its owned mask and A = the mask width.
DESC_OWN:
        LD DE,DESC_LEN
        ADD HL,DE
        LD A,(HL)
        INC HL
        RET

; HL = descriptor: return HL = its capture mask and A = the mask width.
DESC_CAP:
        CALL DESC_OWN
        LD E,A
        LD D,0
        ADD HL,DE
        RET

; Prepare the active four-byte slots named by the descriptor's owned mask.
ENV_OWN:
        LD HL,(DESC_CUR)           ; Owned mask follows the formal index fields.
        CALL DESC_OWN
        LD (MASK_PTR),HL           ; The outer loop consumes one mask byte at a time.
        OR A
        RET Z                      ; A zero-width mask owns no slots.
        LD B,A                     ; Scan the descriptor's mask bytes.
        XOR A
        LD (MASK_IDX),A            ; Slot zero is the first mask bit.
.BYTE:
        LD HL,(MASK_PTR)
        LD A,(HL)                  ; Read the next eight ownership bits.
        INC HL
        LD (MASK_PTR),HL
        LD (MASK_VAL),A
        LD C,8
.BIT:
        LD A,(MASK_VAL)
        AND 1
        JR Z,.NEXT                 ; An unset bit retains its captured pointer.
        LD A,(MASK_IDX)            ; Keep the logical index across slot inspection.
        LD (SLOT_NUM),A
        CALL SLOT_AT               ; HL names the four-byte active slot.
        LD (SLOT_CUR),HL
        LD DE,3                    ; The representation flag is the fourth byte.
        ADD HL,DE
        LD A,(HL)
        LD (SLOT_REP),A
        AND SLOT_PTR
        JR Z,.INLINE               ; Inline locals need no managed allocation.
        LD HL,(SLOT_CUR)           ; A promoted slot may reuse its unescaped cell.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.INLINE               ; A malformed null promotion is reset safely.
        EX DE,HL
        LD (HEAP_OBJ),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        AND BND_ESC
	JR NZ,.NEW_CELL            ; Escaped storage cannot be reused by this frame.
	LD HL,(HEAP_OBJ)
	XOR A                       ; Reuse clears the old payload before argument stores.
	LD (HL),A
	INC HL
	LD (HL),A
	INC HL
	LD (HL),A
	INC HL
	LD A,BND_USED               ; Retain allocation while clearing tag and initialization.
	LD (HL),A
	JR .NEXT
.INLINE:
        LD HL,(SLOT_CUR)           ; Clear an inline slot without touching the heap.
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        JR .NEXT
.NEW_CELL:
        PUSH BC                    ; HEAP_NEW may collect and uses the loop registers.
        CALL HEAP_NEW              ; The old escaped cell remains a live root until publish.
        POP BC
        LD (HEAP_OBJ),HL
        LD A,(SLOT_NUM)
        CALL SLOT_AT
        LD DE,(HEAP_OBJ)
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
.NEXT:
        LD A,(MASK_VAL)            ; Shift this mask bit out before the next slot.
        SRL A
        LD (MASK_VAL),A
        LD A,(MASK_IDX)
        INC A
        LD (MASK_IDX),A            ; Advance through the fixed slot range.
        DEC C
        JP NZ,.BIT                 ; Consume all eight bits in this mask byte.
        DEC B
        JP NZ,.BYTE                ; Continue through the sixteen mask bytes.
        RET

; Copy only captured pointers from the target closure into the active map.
; Owned pointers remain in place so a tail transfer can reuse their cells.
ENV_COPY:
        CALL MAP_COPY              ; Expand target captures into the active map.
        JP MAP_TRIM                ; Clear stale roots outside the target masks.

; Mark every cell copied into a closure as escaped.  The mark lives in the
; high bit of the cell's initialized byte and keeps tail-frame reuse safe.
ENV_MARK:
        LD HL,(DESC_NEW)           ; The new descriptor owns the capture mask.
        CALL DESC_CAP
        LD (MASK_PTR),HL           ; The outer loop consumes one mask byte.
        OR A
        RET Z                      ; Nothing is captured.
        LD (MASK_CNT),A            ; The descriptor's mask bytes.
        XOR A
        LD (MASK_IDX),A            ; Slot zero is the first capture bit.
.BYTE:
        LD HL,(MASK_PTR)
        LD A,(HL)                  ; Read the next eight capture bits.
        INC HL
        LD (MASK_PTR),HL
        LD (MASK_VAL),A
        LD A,8
        LD (MASK_BIT),A
.BIT:
        LD A,(MASK_VAL)
        AND 1                       ; A set bit names one captured cell.
        JR Z,.NEXT
        LD A,(MASK_IDX)
        CALL .ESCAPE                ; Set the cell's persistent escape mark.
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
        JR NZ,.BIT                  ; Consume all eight bits in this byte.
        LD A,(MASK_CNT)
        DEC A
        LD (MASK_CNT),A
        JR NZ,.BYTE                ; Continue through the complete mask.
        RET

; Set the escape bit in the active environment cell for slot A.
.ESCAPE:
        LD (SLOT_NUM),A            ; Promotion may collect, so retain the index.
        CALL SLOT_BOX              ; Captured inline values become managed roots first.
        LD A,(SLOT_NUM)
        CALL SLOT_AT
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        RET Z                      ; An unbound capture has no cell to mark.
        EX DE,HL                   ; HL now names the shared cell.
        LD DE,3                    ; The packed binding flags follow the payload.
        ADD HL,DE
        LD A,(HL)
        OR BND_ESC                 ; Keep the initialized bit and add escape state.
        LD (HL),A
        RET
