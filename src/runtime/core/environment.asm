; Scope runtime activation maps, capture and ownership.
; Entry points: SRTENVIN, SRTCOPYC, SRTOWN and SRTESCAP.
; Included in runtime order by ../core.asm.

; Allocate a stack environment for an ordinary call and install fresh cells
; for every slot owned by the target procedure.
SRTENVIN:
        POP HL                    ; Remove the helper return before moving SP.
        LD (SRTRET),HL            ; Restore it after the activation map is ready.
        LD HL,0                    ; Z80 has no direct LD HL,SP instruction.
        ADD HL,SP                  ; HL is the caller's stack boundary.
        LD (SRTOLDSP),HL           ; The body epilogue restores this boundary.
        LD A,(SRTSLOTS)            ; The descriptor gives the active-slot count.
        LD L,A                     ; Widen the slot count before sizing both maps.
        LD H,0
        ADD HL,HL                  ; Closure maps retain two-byte cell pointers.
        LD (SRTBYTES),HL           ; Keep the closure-map byte count for descriptors.
        LD A,(SRTSLOTS)            ; Re-read the count for the four-byte active map.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL                  ; Four bytes describe every active slot.
        LD (SRTMAPB),HL            ; The stack reservation follows the active extent.
        LD B,H
        LD C,L
        LD HL,(SRTOLDSP)           ; Reserve the pointer array below the caller stack.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,BC
        LD (SRTNEXT),HL            ; Keep the candidate while checking the guard.
        LD DE,SRTSTKGU              ; Leave frame words above the heap boundary.
        OR A                       ; Clear carry before the boundary comparison.
        SBC HL,DE
        JP C,SRTERROR              ; Reject a frame before moving the native stack.
        LD HL,(SRTNEXT)            ; Recover the checked activation boundary.
        LD SP,HL                   ; The new array remains above generated pushes.
        LD (SRTENV),HL             ; Runtime loads and stores use this four-byte map.
        LD (SRTNEXT),HL            ; Preserve the candidate stack boundary.
        LD DE,(SRTLOWSP)           ; Compare it with the lowest prior boundary.
        OR A                       ; Clear carry before the signed comparison.
        SBC HL,DE
        JR NC,SRTLOWDN             ; A higher boundary leaves the low-water mark.
        LD HL,(SRTNEXT)            ; Recover the candidate address after the compare.
        LD (SRTLOWSP),HL           ; Publish the deepest native stack boundary.
SRTLOWDN:
        CALL SRTMAPC               ; Publish a zeroed map before any allocation can run.
        CALL SRTCOPYM              ; Expand captured closure pointers into active slots.
        CALL SRTCLNSE              ; Drop any unused entries before root scanning begins.
        LD HL,(SRTACNT)            ; Count each activation map before body entry.
        INC HL
        LD (SRTACNT),HL
        CALL SRTOWN                ; Allocate fresh cells for owned slots.
        LD HL,(SRTRET)             ; Place the helper return below the map.
        PUSH HL
        RET

; HL = descriptor: return HL = its owned mask and A = the mask width.
DESC_OWN:
        LD DE,SRTDWID
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
SRTOWN:
        LD HL,(SRTDESC)            ; Owned mask follows the formal index fields.
        CALL DESC_OWN
        LD (SRTMASKP),HL           ; The outer loop consumes one mask byte at a time.
        OR A
        RET Z                      ; A zero-width mask owns no slots.
        LD B,A                     ; Scan the descriptor's mask bytes.
        XOR A
        LD (SRTSLOTI),A            ; Slot zero is the first mask bit.
SRTOWNB:
        LD HL,(SRTMASKP)
        LD A,(HL)                  ; Read the next eight ownership bits.
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD C,8
SRTOWNBT:
        LD A,(SRTMASKV)
        AND 1
        JR Z,SRTOWNNX              ; An unset bit retains its captured pointer.
        LD A,(SRTSLOTI)            ; Keep the logical index across slot inspection.
        LD (SRTSNUM),A
        CALL SRTSADDR              ; HL names the four-byte active slot.
        LD (SRTSADR),HL
        LD DE,3                    ; The representation flag is the fourth byte.
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        AND SRTSPROM
        JR Z,SRTOWNIN              ; Inline locals need no managed allocation.
        LD HL,(SRTSADR)            ; A promoted slot may reuse its unescaped cell.
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,SRTOWNIN              ; A malformed null promotion is reset safely.
        EX DE,HL
        LD (SRTCELLP),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        AND SRTBESC
	JR NZ,SRTOWNNW             ; Escaped storage cannot be reused by this frame.
	LD HL,(SRTCELLP)
	XOR A                       ; Reuse clears the old payload before argument stores.
	LD (HL),A
	INC HL
	LD (HL),A
	INC HL
	LD (HL),A
	INC HL
	LD A,SRTBALOC               ; Retain allocation while clearing tag and initialization.
	LD (HL),A
	JR SRTOWNNX
SRTOWNIN:
        LD HL,(SRTSADR)            ; Clear an inline slot without touching the heap.
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        JR SRTOWNNX
SRTOWNNW:
        PUSH BC                    ; SRTCELL may collect and uses the loop registers.
        CALL SRTCELL               ; The old escaped cell remains a live root until publish.
        POP BC
        LD (SRTCELLP),HL
        LD A,(SRTSNUM)
        CALL SRTSADDR
        LD DE,(SRTCELLP)
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
SRTOWNNX:
        LD A,(SRTMASKV)            ; Shift this mask bit out before the next slot.
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A            ; Advance through the fixed slot range.
        DEC C
        JP NZ,SRTOWNBT             ; Consume all eight bits in this mask byte.
        DEC B
        JP NZ,SRTOWNB              ; Continue through the sixteen mask bytes.
        RET

; Copy only captured pointers from the target closure into the active map.
; Owned pointers remain in place so a tail transfer can reuse their cells.
SRTCOPYC:
        CALL SRTCOPYM              ; Expand target captures into the active map.
        JP SRTCLNSE                ; Clear stale roots outside the target masks.

; Mark every cell copied into a closure as escaped.  The mark lives in the
; high bit of the cell's initialized byte and keeps tail-frame reuse safe.
SRTMARKC:
        LD HL,(SRTNEWD)            ; The new descriptor owns the capture mask.
        CALL DESC_CAP
        LD (SRTMASKP),HL           ; The outer loop consumes one mask byte.
        OR A
        RET Z                      ; Nothing is captured.
        LD (SRTMASKN),A            ; The descriptor's mask bytes.
        XOR A
        LD (SRTSLOTI),A            ; Slot zero is the first capture bit.
SRTMARKB:
        LD HL,(SRTMASKP)
        LD A,(HL)                  ; Read the next eight capture bits.
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD A,8
        LD (SRTBITN),A
SRTMKBT:
        LD A,(SRTMASKV)
        AND 1                       ; A set bit names one captured cell.
        JR Z,SRTMKNX
        LD A,(SRTSLOTI)
        CALL SRTESCAP               ; Set the cell's persistent escape mark.
SRTMKNX:
        LD A,(SRTMASKV)
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,SRTMKBT               ; Consume all eight bits in this byte.
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,SRTMARKB             ; Continue through the complete mask.
        RET

; Set the escape bit in the active environment cell for slot A.
SRTESCAP:
        LD (SRTSNUM),A             ; Promotion may collect, so retain the index.
        CALL SRTPROM               ; Captured inline values become managed roots first.
        LD A,(SRTSNUM)
        CALL SRTSADDR
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
        OR SRTBESC                 ; Keep the initialized bit and add escape state.
        LD (HL),A
        RET
