; Scope runtime argument packets, slots and procedure returns.
; Entry points: FRM_PACK, FRM_LOAD/FRM_INIT and FRM_RET.
; Included in runtime order by ../core.asm.

; Move the reverse-pushed argument values into ARG_PKT.  The callee remains
; below the packet and is returned in A:CHL for REST_CHK.
FRM_PACK:
        POP IX                   ; Save the FRM_PACK call return above the values.
        LD B,A                   ; B counts values still on the native stack.
        LD C,A                   ; C is the packet index, starting at count-1.
        LD A,B                   ; A supplies the zero-count test below.
        OR A                      ; No arguments leaves the callee at the top.
        JR Z,.CALLEE              ; Skip the packet loop for a nullary call.
        DEC C                     ; The first reverse-pushed value is count minus one.
.LOOP:
        LD L,C                    ; Widen the reverse packet index.
        LD H,0                    ; Each packet value occupies four bytes.
        ADD HL,HL                 ; Two-byte offset.
        ADD HL,HL                 ; Four-byte offset.
        LD DE,ARG_PKT             ; Add the packet base.
        ADD HL,DE                 ; HL points at the packet value.
        POP DE                    ; The argument's payload.
        LD (HL),E                 ; Store payload low.
        INC HL                    ; Advance to payload high.
        LD (HL),D                 ; Store payload high.
        INC HL
        POP DE                    ; Its byte 2 in E and tag in D.
        LD (HL),E
        INC HL                    ; Advance to the flags and tag.
        LD A,D                    ; Packet values are always live.
        OR CELL_VAL
        LD (HL),A                 ; Publish the complete argument record.
        DEC C                     ; The preceding source argument has a lower index.
        DJNZ .LOOP                ; Consume every staged argument.
.CALLEE:
        POP HL                   ; Recover the callee payload.
        POP DE                   ; Its byte 2 in E and tag in D.
        LD A,D
        LD (ARG_TAG),A
        LD C,E
        LD A,(ARG_CNT)           ; The callee and every argument leave the shadow stack.
        INC A
        LD B,A
        CALL ROOT_CUT
        LD A,(ARG_TAG)
        PUSH IX                  ; Restore the FRM_PACK call return.
        RET                      ; The caller selects closure or primitive dispatch.

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
        LD (ARG_VAL),HL          ; Save the body result while removing frame words.
        LD (ARG_TAG),A           ; Preserve its tag across the frame restore.
        POP HL                   ; Remove the target descriptor below the body return.
        LD (DESC_CUR),HL         ; Restore the enclosing descriptor for nested calls.
        POP HL                   ; Restore the caller environment pointer.
        LD (ENV_CUR),HL          ; Nested closures resume their defining environment.
        LD HL,(DESC_CUR)          ; The descriptor, not the map, carries the shape.
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
        LD (SLOT_CNT),A
        LD (ENV_RCNT),A
        LD HL,(ENV_CUR)
        LD (FRM_BASE),HL         ; The caller map now identifies the active frame.
        POP DE                   ; Restore the stack boundary below the map.
        LD (FRM_SP),DE
        POP HL                   ; Recover the original caller return address.
        EX DE,HL                 ; Keep the return address while releasing the map.
        LD HL,(FRM_SP)
        LD SP,HL
        EX DE,HL                 ; Restore the return address for the final RET.
        PUSH HL                  ; Leave that address ready for the final RET.
        LD HL,(ARG_VAL)          ; Restore the body payload for the caller.
        LD A,(ARG_TAG)           ; Restore the body tag for the caller.
        RET                      ; Return directly to the generated call site.
