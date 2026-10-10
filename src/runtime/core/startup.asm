; Scope runtime startup, scalar slots and checked arithmetic.
; Entry points: RT_BOOT, RT_LOAD/RT_STORE and RT_ADD/RT_SUB/RT_MUL.
; Included in runtime order by ../core.asm.

RT_LOEND EQU 0B800H              ; The compiler keeps a program's image below here.
RT_EPAGE   EQU 0E0H               ; Pair tag-seven values above this byte are escapes.
RT_ESC   EQU 0E000H               ; Escape generations occupy the non-heap range.
RT_OPLO EQU 0CF00H             ; Operator values use the next transient band.
RT_OPHI  EQU 0D300H               ; A 1 KiB operator band; page tables follow it.
RT_QTLO  EQU 0D700H               ; Quoted-data values use the following band.
RT_QTHI   EQU 0DB00H              ; Keep 255 records for calls and rest lists.
RT_DRVLO   EQU 0DB00H             ; Reader values occupy 64 four-byte slots.
RT_DRVHI   EQU 0DC00H             ; Reader value stack end, exclusive.
RT_DRFLO   EQU 0DC00H             ; Reader frames occupy 32 eight-byte records.
RT_DRFHI   EQU 0DD00H             ; Reader frame stack end, exclusive.
RT_GCLO  EQU 0DF00H              ; Collector mark worklist starts here.
RT_GCHI  EQU 0E300H              ; Collector mark worklist ends here.
RT_SPARE  EQU 00100H              ; Keep one page between the stack and the heap.
RT_SOFT  EQU 010H                ; Until a collection has run, the heap stays
                                  ; this many pages below HEAP_LIM.
RT_EXTRA EQU 0                   ; The external map band needs no extra pool pages.
RT_TOP   EQU 0E400H               ; The TPA must extend at least this far.
; A descriptor's owned and capture masks are each W bytes, where the width W
; at offset DESC_LEN covers that procedure's highest owned or captured slot.
; The owned mask follows the width; the capture mask follows the owned mask.
DESC_LEN    EQU 5                  ; Descriptor offset of the mask width.
DESC_MAP   EQU 6                   ; Descriptor offset of the owned-slot mask.
DESC_MAX   EQU 16                  ; At most sixteen bytes cover 128 local slots.

RT_BOOT:                          ; START in entry.asm set the boot stack.
        LD A,(0005H)              ; CP/M places JP BDOS at its 0005H entry.
        CP 0C3H
        JR NZ,.TPA_OK             ; A bare provider host has no BDOS to protect.
        LD HL,(0006H)             ; CP/M publishes the BDOS base as the TPA end.
        LD DE,RT_TOP              ; The runtime uses every byte below its ceiling.
        OR A                      ; Clear carry before the unsigned comparison.
        SBC HL,DE
        JP C,RT_NOMEM             ; A smaller TPA would let the stack overwrite BDOS.
.TPA_OK:
        LD SP,RT_GCHI             ; The idle GC worklist holds the start-up stack.
        CALL RST_SET              ; Install the RST vectors generated code uses.
        LD HL,0                    ; Reset the runtime counters for this program.
        LD (CNT_BIND),HL
        LD (CNT_CLOS),HL
        LD (CNT_PAIR),HL
        LD (CNT_GC),HL
        LD (CNT_MAPS),HL
        LD HL,(RT_LIMIT)          ; Recover the compiler's final loaded image end.
        CALL PAGE_INI              ; Lay out the heap, maps and page metadata.
        JP C,ERROR                 ; Refuse to enter generated code without pages.
        LD HL,(HEAP_LIM)           ; The stack grows down from the heap's end.
        LD SP,HL
        LD (RT_LOWSP),HL           ; Record its low-water mark for qualification.
        LD HL,(PAGE_MIN)           ; The stack may come down to a page above the
        INC H                      ; highest heap page; PAGE_NEW raises this.
        LD (STK_FLR),HL
        CALL DR_INIT               ; Reset the pinned symbol arena for this program.
        LD A,1                     ; The first page may pass the soft line: a
        LD (PAGE_HRD),A            ; large program has no page below it.
        CALL PAIR_INI              ; Reserve and clear the first eight-byte pair slab.
        JP C,ERROR                 ; Refuse to enter code without pair capacity.
        LD HL,RT_OPLO              ; The operator side stack starts above pair cells.
        LD (OPS_SP),HL            ; Reset it for this generated program run.
        LD HL,RT_QTLO              ; Reset the quoted-data stack cursor.
        LD (QT_SP),HL
        LD HL,RT_DRVLO              ; Reset the reader's separate value stack.
        LD (DR_SP),HL
        XOR A                       ; No reader frames or construction result exist.
        LD (DR_LIVE),A
        LD (DR_DEPTH),A
        LD (DR_SLOTS),A
        LD (DR_FRAME),A
        LD (DR_FRAME+1),A
        LD HL,RT_GCLO               ; Reset the collector worklist cursor.
        LD (GC_QTOP),HL
        XOR A                      ; No caller environment exists at program entry.
        LD (ENV_RCNT),A
        LD (IN_CR),A               ; No CR is pending at program entry.
        LD (IN_STATE),A            ; No datum-reader lookahead is pending at entry.
        LD (IN_SRC),A               ; Start with the direct console input adapter.
        LD (OUT_SEL),A              ; Start with the direct console output adapter.
        LD (IN_FILE),A             ; No CP/M input file is open at program entry.
        LD (OUT_FILE),A           ; No CP/M output file is open at program entry.
        LD (IN_MODE),A              ; Inactive file modes default to text.
        LD (OUT_MODE),A
        LD (ROOT_TOP),A            ; No generated operands are pending at entry.
        LD (ROOT_TOP+1),A
        LD HL,CL_FREE               ; Empty every rounded closure size class.
        LD DE,CL_FREE+1
        LD BC,129
        XOR A
        LD (HL),A
        LDIR
        LD HL,CL_OWNER              ; No closure page has an owner, a live count
        LD DE,CL_OWNER+1            ; or a physical base, and no binding page is
        LD BC,CL_LIMIT-CL_OWNER-1   ; assigned: the four tables are one block.
        LD (HL),A
        LDIR
        LD HL,(PAGE_ORG)           ; Keep a map base for the first allocation.
        LD (CL_TOP),HL
        LD HL,0                     ; Binding pages supply their own cursors.
        LD (BND_TOP),HL
        XOR A
        LD (BND_FREE),A
        LD (BND_FREE+1),A
        LD (DESC_RET),A            ; The top-level caller has no descriptor.
        LD (DESC_RET+1),A
        LD (FRM_BASE),A            ; No suspended procedure frame exists yet.
        LD (FRM_BASE+1),A
        LD (QT_HELD),A             ; No quoted-list accumulator is live yet.
RT_CALL:
        CALL 0000H                ; The compiler patches the generated entry.
        JP .EXIT                  ; Close open files, then warm-start CP/M.

; Leave the program after flushing and closing any open output file, so text
; written without close-port survives a normal exit.  Only the I/O module can
; have opened one, and it is present whenever OUT_FILE is set.
.EXIT:
        LD A,(OUT_FILE)
        OR A
        CALL NZ,OUT_SHUT           ; A close failure cannot be reported here.
        JP 0                       ; Return to CP/M through the warm start.

; Refuse to run when CP/M's BDOS starts below RT_TOP.  Nothing above the loaded image
; has been written yet, so CP/M can still print the message and warm start.
RT_NOMEM:
        LD DE,.MSG                ; Explain why the program did not start.
        LD C,9                    ; Select CP/M's dollar-terminated output.
        CALL 5                    ; BDOS switches to its own stack for the call.
        JP 0                      ; Return to CP/M without touching high memory.
.MSG:  DB "NOT ENOUGH MEMORY",13,10,"$"
.STACK:  DS 8                     ; Boot stack used only for the TPA check.
RT_STACK:                         ; The boot stack grows down from here.

; Dynamic apply state is declared in this source part so later modules can
; resolve the shared fields without retaining cross-part forward records.
APPLY_TL:  DB 0                    ; Nonzero while apply uses the tail frame.
APPLY_IN:  DB 0                    ; Nonzero while normal apply enters a target.
APPLY_A:  DB 0                     ; Target tag saved while its final list is read.
APPLY_HL:  DW 0                    ; Target payload saved while its final list is read.

; Load a four-byte slot addressed by HL.  The final byte is the initialized
; flag; the preceding byte preserves the value tag for booleans.
RT_LOAD:
        LD E,(HL)                 ; Read the value's low byte.
        INC HL                    ; Advance to the high value byte.
        LD D,(HL)                 ; Read the value's high byte.
        INC HL
        LD C,(HL)                 ; Byte 2 travels in C.
        INC HL                    ; Advance to the flags and tag.
        LD A,(HL)                 ; Bit four records whether the binding is ready.
        AND CELL_VAL              ; Ignore the high escape mark kept for closures.
        JP Z,RT_UNDEF          ; Never return a fabricated value.
        LD A,(HL)
        AND 0FH                   ; The stored tag.
        LD (RT_TAG),A
        EX DE,HL                  ; Return the stored payload in HL.
        RET                       ; Return the value to generated code.

; Probe one quoted-list cache cell.  Carry set means the compiler has not
; materialized this literal yet; a hit returns its stored A:HL value.
QT_CACHE:
        PUSH HL                   ; Keep the cell base while reading its flag.
        INC HL                    ; Skip the payload low byte.
        INC HL                    ; Skip the payload high byte.
        INC HL                    ; Skip the extension byte.
        LD A,(HL)                 ; A clear live bit means the cache is empty.
        AND CELL_VAL
        POP HL                    ; Restore the cell base for a cache hit.
        JR Z,.MISS                ; The caller falls through to list creation.
        LD E,(HL)                 ; Recover the cached payload low byte.
        INC HL
        LD D,(HL)                 ; Recover the cached payload high byte.
        INC HL
        LD C,(HL)                 ; Byte 2.
        INC HL
        LD A,(HL)
        AND 0FH                   ; The cached value tag; carry is clear.
        EX DE,HL                  ; Return the payload in HL.
        RET
.MISS:
        SCF                       ; Carry distinguishes an empty cache cell.
        RET

; Store A:HL into the four-byte slot addressed by DE.
RT_STORE:
%IF PROBE
        CALL PROBE
%ENDIF
        LD (RT_TAG),A             ; Preserve the value tag while writing payload bytes.
        LD A,L                    ; Copy the payload low byte to the slot.
        LD (DE),A                 ; Publish the low byte first.
        INC DE                    ; Advance to the high payload byte.
        LD A,H                    ; Copy the payload high byte.
        LD (DE),A                 ; Publish the complete payload.
        INC DE
        LD A,C
        LD (DE),A                 ; Byte 2 from C.
        INC DE                    ; Advance to the flags and tag.
        PUSH BC
        LD A,(RT_TAG)
        OR CELL_VAL               ; Initialized, with the caller's tag.
        LD B,A
        LD A,(DE)                 ; Preserve the escape mark and other flags.
        AND 0E0H
        OR B
        POP BC
        LD (DE),A                 ; A later load can now observe the value.
        LD A,(RT_TAG)             ; Return the stored value tag to generated code.
        RET                       ; Return with the stored value still in HL.

; Store into an existing binding.  The initialized bit must already be set;
; mutation of an unbound global or local reports the ordinary UNBOUND error.
RT_SET:
        LD (ARG_TAG),A             ; Preserve the new value tag across the check.
        LD (HEAP_OBJ),DE          ; Preserve the destination while checking it.
        INC DE                    ; Skip the payload low byte.
        INC DE                    ; Skip the payload high byte.
        INC DE                    ; Skip the extension byte.
        LD A,(DE)                  ; Bit four records initialization.
        AND CELL_VAL
        JP Z,RT_UNDEF              ; A missing binding cannot be mutated.
        LD DE,(HEAP_OBJ)           ; Restore the cell base for the normal store.
        LD A,(ARG_TAG)             ; Restore the caller's tag before storing.
        CALL RT_STORE               ; Publish the new value and any escape mark.
        LD HL,0FE04H               ; Mutation expressions return UNSPECIFIED.
        XOR A                      ; Tag zero identifies the reserved immediate.
        LD C,A
        RET                        ; The caller receives the language result value.

; Return Z exactly when the value is #f, preserving A and HL for short-circuit
; forms.  Other tag-zero scalars, including numeric zero, are true.
RT_TEST:
        LD (RT_TAG),A             ; Keep the logical tag while checking payload.
        OR A                      ; Nonzero tags are always true.
        JR NZ,.TRUE               ; Leave the original value untouched.
        PUSH HL                   ; Compare the scalar payload without changing it.
        LD DE,0FE00H              ; Only the canonical false payload is false.
        OR A                      ; Clear carry before the subtraction.
        SBC HL,DE                 ; Test for exact #f representation.
        POP HL                    ; Restore the original payload for the caller.
        JR NZ,.TRUE               ; Numeric zero and all other scalars are true.
        XOR A                     ; Record the false result in the state byte.
        JR .DONE                  ; Restore the original tag before returning.
.TRUE:
        LD A,1                    ; Record a true branch decision.
.DONE:
        LD (RT_BOOL),A            ; Keep the decision while restoring the tag.
        LD A,(RT_BOOL)            ; Set flags from the branch decision.
        OR A                      ; Z means false, NZ means true.
        LD A,(RT_TAG)        ; LD does not disturb the decision flags.
        RET                       ; Generated JP Z/JR Z reads the preserved flags.
