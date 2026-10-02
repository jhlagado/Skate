; Scope runtime startup, scalar slots and checked arithmetic.
; Entry points: SRTSTART, SRTLOAD/SRTSTORE and SRTADD/SRTSUB/SRTMUL.
; Included in runtime order by ../core.asm.

ORG 0100H

SRTHEAP    EQU 03000H              ; Base used by the full-pool allocation maps.
SRTLOEND EQU 09000H              ; Low pages end before the external mark maps.
SRTMPEND  EQU 0B800H              ; The managed high band begins after the maps.
SRTHEPEN  EQU 0C000H              ; Managed objects stop before transient storage.
SRTETOH   EQU 0E0H                ; Pair tag-seven values above this byte are escapes.
SRTETOK   EQU 0E000H              ; Escape generations occupy the non-heap range.
SRTOPB EQU 0C000H              ; Operator values use the next transient band.
SRTOPEND  EQU 0C800H              ; Leave a 3 KiB transient band below the guard.
SRTQBASE  EQU 0C800H              ; Quoted-data values use the following band.
SRTQEND   EQU 0CC00H              ; Keep 255 records for calls and rest lists.
SRTDRVB   EQU 0CC00H              ; Reader values occupy 64 four-byte slots.
SRTDRVE   EQU 0CD00H              ; Reader value stack end, exclusive.
SRTDRFB   EQU 0CD00H              ; Reader frames occupy 32 eight-byte records.
SRTDRFE   EQU 0CE00H              ; Reader frame stack end, exclusive.
SRTMKBS  EQU 0D000H              ; Collector mark worklist starts here.
SRTMKBE  EQU 0D400H              ; Collector mark worklist ends here.
SRTSTKRS  EQU 00100H              ; Reserve one page for calls below a frame.
SRTSTKGU  EQU SRTMKBE+SRTSTKRS    ; Keep native stack work above the mark queue.
SRTMHIGH EQU 0                   ; The external map band needs no extra pool pages.
SRTOWNOF   EQU 12                  ; Descriptor offset of the owned-slot mask.
SRTCAPOF   EQU 28                  ; Descriptor offset of the capture mask.
SRTMASKB   EQU 16                  ; Sixteen bytes cover 128 local slots.

SRTSTART:
        LD SP,0E400H              ; Use the full four-kilobyte guarded stack band.
        LD HL,0E400H              ; The native stack begins at the fixed ceiling.
        LD (SRTLOWSP),HL          ; Record its low-water mark for qualification.
        LD HL,0                    ; Reset the runtime counters for this program.
        LD (SRTBCNT),HL
        LD (SRTCCNT),HL
        LD (SRTPCNT),HL
        LD (SRTGCNT),HL
        LD (SRTACNT),HL
        LD HL,(SRTIMGE)           ; Recover the compiler's final loaded image end.
        CALL SRTGPINI              ; Derive and initialise the page-domain metadata.
        JP C,SRTERROR              ; Refuse to enter generated code without pages.
        CALL SRTSYINI              ; Reset the pinned symbol arena for this program.
        CALL SRTPIN                ; Reserve and clear the first eight-byte pair slab.
        JP C,SRTERROR              ; Refuse to enter code without pair capacity.
        LD HL,SRTOPB               ; The operator side stack starts above pair cells.
        LD (SRTOPS),HL            ; Reset it for this generated program run.
        LD HL,SRTQBASE             ; Reset the quoted-data stack cursor.
        LD (SRTQSP),HL
        LD HL,SRTDRVB               ; Reset the reader's separate value stack.
        LD (SRTDRVP),HL
        XOR A                       ; No reader frames or construction result exist.
        LD (SRTDRACT),A
        LD (SRTDRFC),A
        LD (SRTDRVC),A
        LD (SRTDRACC),A
        LD (SRTDRFP),A
        LD (SRTDRFP+1),A
        LD HL,SRTMKBS               ; Reset the collector worklist cursor.
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
        LD BC,11FFH
        LD (HL),A
        LDIR
        LD HL,SRTCFREE              ; Empty every rounded closure size class.
        LD DE,SRTCFREE+1
        LD BC,129
        XOR A
        LD (HL),A
        LDIR
        LD HL,SRTCLOWN              ; No closure slab owns a page at startup.
        LD DE,SRTCLOWN+1
        LD BC,255
        LD (HL),A
        LDIR
        LD HL,SRTCLUSE              ; No closure object occupies a slab yet.
        LD DE,SRTCLUSE+1
        LD BC,127
        LD (HL),A
        LDIR
        LD HL,SRTCLPBA              ; No closure page has a physical base yet.
        LD DE,SRTCLPBA+1
        LD BC,127
        LD (HL),A
        LDIR
        LD HL,SRTBPGS               ; No binding page has a physical base yet.
        LD DE,SRTBPGS+1
        LD BC,127
        LD (HL),A
        LDIR
        LD HL,SRTHEAP               ; Keep a map base for the first allocation.
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
SRTCALL:
        CALL 0000H                ; The compiler patches the generated entry.
        JP 0                      ; Return to CP/M through the warm start.

; Dynamic apply state is declared in this source part so later modules can
; resolve the shared fields without retaining cross-part forward records.
SRTAPMOD:  DB 0                    ; Nonzero while apply uses the tail frame.
SRTAPDIS:  DB 0                    ; Nonzero while normal apply enters a target.
SRTAPTAG:  DB 0                    ; Target tag saved while its final list is read.
SRTAPVAL:  DW 0                    ; Target payload saved while its final list is read.

; Load a four-byte slot addressed by HL.  The final byte is the initialized
; flag; the preceding byte preserves the value tag for booleans.
SRTLOAD:
        LD E,(HL)                 ; Read the value's low byte.
        INC HL                    ; Advance to the high value byte.
        LD D,(HL)                 ; Read the value's high byte.
        INC HL                    ; Advance to the stored value tag.
        LD A,(HL)                 ; Recover the stored scalar tag.
        LD (SRTTAG),A             ; Preserve it while testing initialization.
        INC HL                    ; Advance to the initialized flag.
        LD A,(HL)                 ; Bit zero records whether the binding is ready.
        AND 1                     ; Ignore the high escape mark kept for closures.
        JP Z,SRTUNBD           ; Never return a fabricated value.
        EX DE,HL                  ; Return the stored payload in HL.
        LD A,(SRTTAG)             ; Restore the stored value tag.
        RET                       ; Return the value to generated code.

; Probe one quoted-list cache cell.  Carry set means the compiler has not
; materialized this literal yet; a hit returns its stored A:HL value.
SRTQGET:
        PUSH HL                   ; Keep the cell base while reading its flag.
        INC HL                    ; Skip the payload low byte.
        INC HL                    ; Skip the payload high byte.
        INC HL                    ; Skip the value tag.
        LD A,(HL)                 ; A zero flag means the cache is empty.
        OR A
        POP HL                    ; Restore the cell base for a cache hit.
        JR Z,SRTQMISS             ; The caller falls through to list creation.
        LD E,(HL)                 ; Recover the cached payload low byte.
        INC HL
        LD D,(HL)                 ; Recover the cached payload high byte.
        INC HL
        LD A,(HL)                 ; Recover the cached value tag.
        EX DE,HL                  ; Return the payload in HL.
        RET
SRTQMISS:
        SCF                       ; Carry distinguishes an empty cache cell.
        RET

; Store A:HL into the four-byte slot addressed by DE.
SRTSTORE:
        LD (SRTTAG),A             ; Preserve the value tag while writing payload bytes.
        LD A,L                    ; Copy the payload low byte to the slot.
        LD (DE),A                 ; Publish the low byte first.
        INC DE                    ; Advance to the high payload byte.
        LD A,H                    ; Copy the payload high byte.
        LD (DE),A                 ; Publish the complete payload.
        INC DE                    ; Advance to the stored value tag.
        LD A,(SRTTAG)             ; Copy the caller's tag into the slot.
        LD (DE),A                 ; Publish the tag after both payload bytes.
        INC DE                    ; Advance to the initialized flag.
        LD A,(DE)                 ; Preserve allocation, capture and mark bits.
        AND 0FEH
        OR 1                       ; Mark the slot initialized after all value bytes.
        LD (DE),A                 ; A later load can now observe the value.
        LD A,(SRTTAG)             ; Return the stored value tag to generated code.
        RET                       ; Return with the stored value still in HL.

; Store into an existing binding.  The initialized bit must already be set;
; mutation of an unbound global or local reports the ordinary UNBOUND error.
SRTSET:
        LD (SRTATMP),A             ; Preserve the new value tag across the check.
        LD (SRTCELLP),DE          ; Preserve the destination while checking it.
        INC DE                    ; Skip the payload low byte.
        INC DE                    ; Skip the payload high byte.
        INC DE                    ; Skip the stored value tag.
        LD A,(DE)                  ; The low flag bit records initialization.
        AND 1
        JP Z,SRTUNBD               ; A missing binding cannot be mutated.
        LD DE,(SRTCELLP)           ; Restore the cell base for the normal store.
        LD A,(SRTATMP)             ; Restore the caller's tag before storing.
        CALL SRTSTORE               ; Publish the new value and any escape mark.
        LD HL,0FE04H               ; Mutation expressions return UNSPECIFIED.
        XOR A                      ; Tag zero identifies the reserved immediate.
        RET                        ; The caller receives the language result value.

; Return Z exactly when the value is #f, preserving A and HL for short-circuit
; forms.  Other tag-zero scalars, including numeric zero, are true.
SRTFALSE:
        LD (SRTTAG),A             ; Keep the logical tag while checking payload.
        OR A                      ; Nonzero tags are always true.
        JR NZ,SRTTRUE             ; Leave the original value untouched.
        PUSH HL                   ; Compare the scalar payload without changing it.
        LD DE,0FE00H              ; Only the canonical false payload is false.
        OR A                      ; Clear carry before the subtraction.
        SBC HL,DE                 ; Test for exact #f representation.
        POP HL                    ; Restore the original payload for the caller.
        JR NZ,SRTTRUE             ; Numeric zero and all other scalars are true.
        XOR A                     ; Record the false result in the state byte.
        JR SRTBDONE               ; Restore the original tag before returning.
SRTTRUE:
        LD A,1                    ; Record a true branch decision.
SRTBDONE:
        LD (SRTBOOL),A            ; Keep the decision while restoring the tag.
        LD A,(SRTBOOL)            ; Set flags from the branch decision.
        OR A                      ; Z means false, NZ means true.
        LD A,(SRTTAG)        ; LD does not disturb the decision flags.
        RET                       ; Generated JP Z/JR Z reads the preserved flags.

; Binary helpers pop two values in the order emitted by the compiler and call
; the shared checked numeric ABI.  The helper keeps the generated code small.
SRTADD:
        XOR A                     ; Operation zero selects integer addition.
        JR SRTBIN              ; Join the common stack and dispatch path.
SRTSUB:
        LD A,1                    ; Operation one selects subtraction.
        JR SRTBIN              ; Join the common stack and dispatch path.
SRTMUL:
        LD A,2                    ; Operation two selects multiplication.
SRTBIN:
        LD (SRTOP),A              ; Save the operation while popping operands.
        POP IX                    ; Save the CALL return address above the values.
        POP DE                    ; Recover the right payload.
        POP BC                    ; Recover right AF; B is the right tag.
        POP HL                    ; Recover the left payload.
        POP AF                    ; Recover left AF; A is the left tag.
        LD (SRTTAG),A             ; Preserve the left tag while selecting the op.
        LD A,(SRTOP)              ; Select the checked operation.
        OR A                      ; Addition is the zero operation.
        JR Z,SRTDOADD             ; Call NADD with the recovered ABI values.
        CP 1                      ; Subtraction is operation one.
        JR Z,SRTDOSUB             ; Call NSUB with the recovered ABI values.
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NMUL                 ; Operation two is checked multiplication.
        JR SRTBRES           ; Common carry handling and return.
SRTDOADD:
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NADD                 ; Checked addition uses A/B and HL/DE.
        JR SRTBRES           ; Common carry handling and return.
SRTDOSUB:
        LD A,(SRTTAG)             ; Restore the left tag for the numeric ABI.
        CALL NSUB                 ; Checked subtraction uses A/B and HL/DE.
SRTBRES:
        JP C,SRTERROR             ; Overflow or an invalid value is terminal.
        LD B,2                    ; The two native operands are now consumed.
        CALL SRTNPOPB
        PUSH IX                   ; Restore the generated caller's return address.
        RET                       ; Return the checked value in A and HL.
