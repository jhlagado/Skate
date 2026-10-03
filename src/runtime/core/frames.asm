; Scope runtime argument packets, slots and procedure returns.
; Entry points: FRM_PACK, FRM_CELL, FRM_LOAD/FRM_INIT and FRM_RET.
; Included in runtime order by ../core.asm.

; Move the reverse-pushed argument values into SRTARGPK.  The callee remains
; below the packet and is returned in A:HL for REST_CHK.
FRM_PACK:
        POP IX                   ; Save the FRM_PACK call return above the values.
        LD B,A                   ; B counts values still on the native stack.
        LD C,A                   ; C is the packet index, starting at count-1.
        LD A,B                   ; A supplies the zero-count test below.
        OR A                      ; No arguments leaves the callee at the top.
        JR Z,.CALLEE              ; Skip the packet loop for a nullary call.
        DEC C                     ; The first reverse-pushed value is count minus one.
.LOOP:
        POP HL                   ; Recover the argument payload word.
        POP AF                   ; Recover the argument tag word.
        LD (SRTATMP),A            ; Preserve the tag while addressing the packet.
        LD (SRTVAL),HL            ; Preserve the payload while multiplying the index.
        LD L,C                    ; Widen the reverse packet index.
        LD H,0                    ; Each packet value occupies four bytes.
        ADD HL,HL                 ; Two-byte offset.
        ADD HL,HL                 ; Four-byte offset.
        LD DE,SRTARGPK            ; Add the packet base.
        ADD HL,DE                 ; HL points at the packet value.
        LD DE,(SRTVAL)             ; Restore the payload.
        LD (HL),E                 ; Store payload low.
        INC HL                    ; Advance to payload high.
        LD (HL),D                 ; Store payload high.
        INC HL                    ; Advance to the extension byte.
        XOR A
        LD (HL),A                 ; It stays clear.
        INC HL                    ; Advance to the flags and tag.
        LD A,(SRTATMP)            ; Packet values are always live.
        OR CELL_VAL
        LD (HL),A                 ; Publish the complete argument record.
        DEC C                     ; The preceding source argument has a lower index.
        DJNZ .LOOP                ; Consume every staged argument.
.CALLEE:
        POP HL                   ; Recover the callee payload.
        POP AF                   ; Recover the callee tag.
        LD (SRTATMP),A
        LD A,(SRTARGC)           ; The callee and every argument leave the shadow stack.
        INC A
        LD B,A
        CALL ROOT_CUT
        LD A,(SRTATMP)
        PUSH IX                  ; Restore the FRM_PACK call return.
        RET                      ; The caller selects closure or primitive dispatch.

; Convert a logical slot number in A into its shared cell pointer.
FRM_CELL:
        LD L,A                    ; Widen the zero-based slot index.
        LD H,0
        ADD HL,HL                 ; Two bytes hold each cell pointer.
        LD DE,(SRTENV)
        ADD HL,DE
        LD E,(HL)                 ; Recover the cell pointer low byte.
        INC HL
        LD D,(HL)                 ; Recover the cell pointer high byte.
        EX DE,HL
        LD A,H                    ; A null pointer denotes an unbound slot.
        OR L
        JR NZ,.OK
        SCF
        RET
.OK:
        XOR A                     ; Carry clear reports a valid cell pointer.
        RET

; Load a procedure-local value through its current activation map.
FRM_LOAD:
        JP SLOT_GET                ; A contains the compiler-emitted slot index.

; Store A:HL through the current activation map; B contains the slot index.
FRM_INIT:
        JP SLOT_PUT                ; B contains the compiler-emitted slot index.

; Store through a local activation map while requiring prior initialization.
FRM_SET:
        JP SLOT_SET                ; B contains the compiler-emitted slot index.

; Clear a recursive local cell through the current activation map.
FRM_CLR:
        JP SLOT_CLR                ; B contains the compiler-emitted slot index.

; Clear a fixed recursive cell while preserving its escape mark.
RT_CLR:
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND 80H
        LD (HL),A
        RET
RT_EMPTY:
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND BND_ESC+BND_USED+BND_MARK
        LD (HL),A
        RET

; Return from a generated procedure and restore the caller's frame words.
FRM_RET:
        LD (SRTVAL),HL           ; Save the body result while removing frame words.
        LD (SRTATMP),A           ; Preserve its tag across the frame restore.
        POP HL                   ; Remove the target descriptor below the body return.
        LD (SRTDESC),HL          ; Restore the enclosing descriptor for nested calls.
        POP HL                   ; Restore the caller environment pointer.
        LD (SRTENV),HL           ; Nested closures resume their defining environment.
        LD HL,(SRTDESC)           ; The descriptor, not the map, carries the shape.
        LD A,H
        OR L
        JR Z,.TOP
        LD DE,3                   ; The restored descriptor names the active map shape.
        ADD HL,DE
        LD A,(HL)
        JR .SLOTS
.TOP:
        XOR A
.SLOTS:
        LD (SRTSLOTS),A
        LD (SRTCENVN),A
        LD HL,(SRTENV)
        LD (SRTFRAME),HL         ; The caller map now identifies the active frame.
        POP DE                   ; Restore the stack boundary below the map.
        LD (SRTOLDSP),DE
        POP HL                   ; Recover the original caller return address.
        EX DE,HL                 ; Keep the return address while releasing the map.
        LD HL,(SRTOLDSP)
        LD SP,HL
        EX DE,HL                 ; Restore the return address for the final RET.
        PUSH HL                  ; Leave that address ready for the final RET.
        LD HL,(SRTVAL)           ; Restore the body payload for the caller.
        LD A,(SRTATMP)           ; Restore the body tag for the caller.
        RET                      ; Return directly to the generated call site.
