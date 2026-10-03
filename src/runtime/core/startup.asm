; Scope runtime startup, scalar slots and checked arithmetic.
; Entry points: RT_BOOT, RT_LOAD/RT_STORE and RT_ADD/RT_SUB/RT_MUL.
; Included in runtime order by ../core.asm.

RT_HEAP    EQU 03000H              ; Base used by the full-pool allocation maps.
RT_LOEND EQU 09000H              ; Low pages end before the external mark maps.
RT_HIGH  EQU 0AB00H               ; The managed high band begins after the maps.
RT_HPAGE  EQU 0ABH                ; High byte of RT_HIGH for page mapping.
RT_HIEND  EQU 0C000H              ; Managed objects stop before transient storage.
RT_EPAGE   EQU 0E0H               ; Pair tag-seven values above this byte are escapes.
RT_ESC   EQU 0E000H               ; Escape generations occupy the non-heap range.
RT_OPLO EQU 0C000H             ; Operator values use the next transient band.
RT_OPHI  EQU 0C400H               ; A 1 KiB operator band; page tables follow it.
RT_QTLO  EQU 0C800H               ; Quoted-data values use the following band.
RT_QTHI   EQU 0CC00H              ; Keep 255 records for calls and rest lists.
RT_DRVLO   EQU 0CC00H             ; Reader values occupy 64 four-byte slots.
RT_DRVHI   EQU 0CD00H             ; Reader value stack end, exclusive.
RT_DRFLO   EQU 0CD00H             ; Reader frames occupy 32 eight-byte records.
RT_DRFHI   EQU 0CE00H             ; Reader frame stack end, exclusive.
RT_GCLO  EQU 0D000H              ; Collector mark worklist starts here.
RT_GCHI  EQU 0D400H              ; Collector mark worklist ends here.
RT_SPARE  EQU 00100H              ; Reserve one page for calls below a frame.
RT_GUARD  EQU RT_GCHI+RT_SPARE    ; Keep native stack work above the mark queue.
RT_EXTRA EQU 0                   ; The external map band needs no extra pool pages.
RT_TOP   EQU 0E400H               ; Stack ceiling: the TPA must extend at least this far.
; A descriptor's owned and capture masks are each W bytes, where the width W
; at offset DESC_LEN covers that procedure's highest owned or captured slot.
; The owned mask follows the width; the capture mask follows the owned mask.
DESC_LEN    EQU 12                 ; Descriptor offset of the mask width.
DESC_MAP   EQU 13                  ; Descriptor offset of the owned-slot mask.
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
        LD SP,RT_TOP              ; Use the full four-kilobyte guarded stack band.
        CALL RST_SET              ; Install the RST vectors generated code uses.
        LD HL,RT_TOP              ; The native stack begins at the fixed ceiling.
        LD (SRTLOWSP),HL          ; Record its low-water mark for qualification.
        LD HL,0                    ; Reset the runtime counters for this program.
        LD (SRTBCNT),HL
        LD (SRTCCNT),HL
        LD (SRTPCNT),HL
        LD (SRTGCNT),HL
        LD (SRTACNT),HL
        LD HL,(SRTIMGE)           ; Recover the compiler's final loaded image end.
        CALL PAGE_INI              ; Derive and initialise the page-domain metadata.
        JP C,SRTERROR              ; Refuse to enter generated code without pages.
        CALL SRTSYINI              ; Reset the pinned symbol arena for this program.
        CALL PAIR_INI              ; Reserve and clear the first eight-byte pair slab.
        JP C,SRTERROR              ; Refuse to enter code without pair capacity.
        LD HL,RT_OPLO              ; The operator side stack starts above pair cells.
        LD (SRTOPS),HL            ; Reset it for this generated program run.
        LD HL,RT_QTLO              ; Reset the quoted-data stack cursor.
        LD (SRTQSP),HL
        LD HL,RT_DRVLO              ; Reset the reader's separate value stack.
        LD (SRTDRVP),HL
        XOR A                       ; No reader frames or construction result exist.
        LD (SRTDRACT),A
        LD (SRTDRFC),A
        LD (SRTDRVC),A
        LD (SRTDRACC),A
        LD (SRTDRFP),A
        LD (SRTDRFP+1),A
        LD HL,RT_GCLO               ; Reset the collector worklist cursor.
        LD (SRTMSTK),HL
        XOR A                      ; No caller environment exists at program entry.
        LD (SRTCENVN),A
        LD (SRTINCR),A             ; No CR is pending at program entry.
        LD (SRTINST),A             ; No datum-reader lookahead is pending at entry.
        LD (SRTINSEL),A             ; Start with the direct console input adapter.
        LD (SRTOUTS),A              ; Start with the direct console output adapter.
        LD (SRTFIACT),A            ; No CP/M input file is open at program entry.
        LD (SRTFOACT),A           ; No CP/M output file is open at program entry.
        LD (SRTFIMOD),A             ; Inactive file modes default to text.
        LD (SRTFWMDE),A
        LD (SRTNCT),A              ; No generated operands are pending at entry.
        LD HL,SRTCLBM              ; Clear closure-start metadata for this run.
        LD DE,SRTCLBM+1
        LD BC,08FFH
        LD (HL),A
        LDIR
        LD HL,SRTCLMK              ; Clear closure mark metadata for this run.
        LD DE,SRTCLMK+1
        LD BC,08FFH
        LD (HL),A
        LDIR
        LD HL,SRTBMB               ; Clear binding allocation-start metadata.
        LD DE,SRTBMB+1
        LD BC,047FH
        LD (HL),A
        LDIR
        LD HL,SRTCFREE              ; Empty every rounded closure size class.
        LD DE,SRTCFREE+1
        LD BC,129
        XOR A
        LD (HL),A
        LDIR
        LD HL,SRTCLOWN              ; No closure page has an owner, a live count
        LD DE,SRTCLOWN+1            ; or a physical base, and no binding page is
        LD BC,SRTPTEND-SRTCLOWN-1   ; assigned: the four tables are one block.
        LD (HL),A
        LDIR
        LD HL,RT_HEAP               ; Keep a map base for the first allocation.
        LD (SRTCLCUR),HL
        LD HL,0                     ; Binding pages supply their own cursors.
        LD (SRTBEND),HL
        XOR A
        LD (SRTBHEAD),A
        LD (SRTBHEAD+1),A
        LD (SRTCDESC),A            ; The top-level caller has no descriptor.
        LD (SRTCDESC+1),A
        LD (SRTFRAME),A            ; No suspended procedure frame exists yet.
        LD (SRTFRAME+1),A
        LD (SRTQACTV),A            ; No quoted-list accumulator is live yet.
RT_CALL:
        CALL 0000H                ; The compiler patches the generated entry.
        JP .EXIT                  ; Close open files, then warm-start CP/M.

; Leave the program after flushing and closing any open output file, so text
; written without close-port survives a normal exit.  Only the I/O module can
; have opened one, and it is present whenever SRTFOACT is set.
.EXIT:
        LD A,(SRTFOACT)
        OR A
        CALL NZ,SRTFCLW            ; A close failure cannot be reported here.
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
        INC HL                    ; Skip the clear extension byte.
        INC HL                    ; Advance to the flags and tag.
        LD A,(HL)                 ; Bit four records whether the binding is ready.
        AND CELL_VAL              ; Ignore the high escape mark kept for closures.
        JP Z,SRTUNBD           ; Never return a fabricated value.
        LD A,(HL)
        AND 0FH                   ; The stored tag.
        LD (SRTTAG),A
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
        LD (SRTTAG),A             ; Preserve the value tag while writing payload bytes.
        LD A,L                    ; Copy the payload low byte to the slot.
        LD (DE),A                 ; Publish the low byte first.
        INC DE                    ; Advance to the high payload byte.
        LD A,H                    ; Copy the payload high byte.
        LD (DE),A                 ; Publish the complete payload.
        INC DE                    ; Advance to the extension byte.
        XOR A
        LD (DE),A                 ; It stays clear.
        INC DE                    ; Advance to the flags and tag.
        PUSH BC
        LD A,(SRTTAG)
        OR CELL_VAL               ; Initialized, with the caller's tag.
        LD B,A
        LD A,(DE)                 ; Preserve the escape mark and other flags.
        AND 0E0H
        OR B
        POP BC
        LD (DE),A                 ; A later load can now observe the value.
        LD A,(SRTTAG)             ; Return the stored value tag to generated code.
        RET                       ; Return with the stored value still in HL.

; Store into an existing binding.  The initialized bit must already be set;
; mutation of an unbound global or local reports the ordinary UNBOUND error.
RT_SET:
        LD (SRTATMP),A             ; Preserve the new value tag across the check.
        LD (SRTCELLP),DE          ; Preserve the destination while checking it.
        INC DE                    ; Skip the payload low byte.
        INC DE                    ; Skip the payload high byte.
        INC DE                    ; Skip the extension byte.
        LD A,(DE)                  ; Bit four records initialization.
        AND CELL_VAL
        JP Z,SRTUNBD               ; A missing binding cannot be mutated.
        LD DE,(SRTCELLP)           ; Restore the cell base for the normal store.
        LD A,(SRTATMP)             ; Restore the caller's tag before storing.
        CALL RT_STORE               ; Publish the new value and any escape mark.
        LD HL,0FE04H               ; Mutation expressions return UNSPECIFIED.
        XOR A                      ; Tag zero identifies the reserved immediate.
        RET                        ; The caller receives the language result value.

; Return Z exactly when the value is #f, preserving A and HL for short-circuit
; forms.  Other tag-zero scalars, including numeric zero, are true.
RT_TEST:
        LD (SRTTAG),A             ; Keep the logical tag while checking payload.
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
        LD (SRTBOOL),A            ; Keep the decision while restoring the tag.
        LD A,(SRTBOOL)            ; Set flags from the branch decision.
        OR A                      ; Z means false, NZ means true.
        LD A,(SRTTAG)        ; LD does not disturb the decision flags.
        RET                       ; Generated JP Z/JR Z reads the preserved flags.

; Binary helpers pop two values in the order emitted by the compiler and call
; the shared checked numeric ABI.  The helper keeps the generated code small.
RT_ADD:
        XOR A                     ; Operation zero selects integer addition.
        JR RT_BINOP            ; Join the common stack and dispatch path.
RT_SUB:
        LD A,1                    ; Operation one selects subtraction.
        JR RT_BINOP            ; Join the common stack and dispatch path.
RT_MUL:
        LD A,2                    ; Operation two selects multiplication.
RT_BINOP:
        LD (SRTOP),A              ; Save the operation while popping operands.
        POP IX                    ; Save the CALL return address above the values.
        POP DE                    ; Recover the right payload.
        POP BC                    ; Recover right AF; B is the right tag.
        POP HL                    ; Recover the left payload.
        POP AF                    ; Recover left AF; A is the left tag.
        LD (SRTTAG),A             ; Preserve the left tag while selecting the op.
        LD A,(SRTOP)              ; Select the checked operation.
        OR A                      ; Addition is the zero operation.
        JR Z,.ADD                 ; Call NUM_ADD with the recovered ABI values.
        CP 1                      ; Subtraction is operation one.
        JR Z,.SUB                 ; Call NUM_SUB with the recovered ABI values.
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NUM_MUL              ; Operation two is checked multiplication.
        JR .RESULT           ; Common carry handling and return.
.ADD:
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NUM_ADD              ; Checked addition uses A/B and HL/DE.
        JR .RESULT           ; Common carry handling and return.
.SUB:
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NUM_SUB              ; Checked subtraction uses A/B and HL/DE.
.RESULT:
        JP C,SRTERROR             ; Overflow or an invalid value is terminal.
        LD B,2                    ; The two native operands are now consumed.
        CALL ROOT_CUT
        PUSH IX                   ; Restore the generated caller's return address.
        RET                       ; Return the checked value in A and HL.
