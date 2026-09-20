;=============================================================================
;  Runtime support for the scope and control compiler
;=============================================================================
;
;  The compiler writes a short native program after this image.  The program
;  uses the routines below for integer values, lexical slots, global slots,
;  branches and output.  Slot addresses are fixed up by the compiler after
;  the generated program and its data areas have been sized.
;
;  A value is returned as A=tag, HL=payload.  Integer values use tag 3;
;  #f and #t use tag 0 with payload 0 and 1 respectively.
;=============================================================================

ORG 0100H

SRTHEAP    EQU 06000H              ; Closure environments use the lower TPA band.
SRTHEPEN  EQU 0A000H              ; Closure heap stops before the pair arena.
SRTPAIRB  EQU 0A000H              ; Pair cells occupy a separately collected arena.
SRTPAIRE  EQU 0C000H              ; Pair arena end, exclusive.
SRTOPB EQU 0C000H              ; Operator values use the next transient band.
SRTSTKGU  EQU 0D400H              ; Reserve frames, operands and helper scratch.
SRTOPEND  EQU 0C800H              ; Leave a 3 KiB transient band below the guard.
SRTQBASE  EQU 0C800H              ; Quoted-data values use the following band.
SRTQEND   EQU 0D000H              ; Quoted-data stack end, exclusive.
SRTMKBS  EQU 0D000H              ; Collector mark worklist starts here.
SRTMKBE  EQU 0D400H              ; Collector worklist ends at the stack guard.
SRTOWNOF   EQU 12                  ; Descriptor offset of the owned-slot mask.
SRTCAPOF   EQU 28                  ; Descriptor offset of the capture mask.
SRTMASKB   EQU 16                  ; Sixteen bytes cover 128 local slots.

SRTSTART:
        LD SP,0E000H              ; Keep the generated program below the guard.
        LD HL,0E000H              ; The native stack begins at the fixed ceiling.
        LD (SRTLOWSP),HL          ; Record its low-water mark for qualification.
        LD HL,SRTOPB            ; The operator side stack starts above pair cells.
        LD (SRTOPS),HL            ; Reset it for this generated program run.
        LD HL,SRTQBASE             ; Reset the quoted-data stack cursor.
        LD (SRTQSP),HL
        LD HL,SRTMKBS               ; Reset the collector worklist cursor.
        LD (SRTMSTK),HL
        LD HL,SRTPAIRB              ; Clear pair state left by the compiler process.
        LD BC,1024                  ; One state byte is cleared for each fixed cell.
SRTCLR:
        XOR A
        LD (HL),A
        LD DE,8
        ADD HL,DE
        DEC BC
        LD A,B
        OR C
        JR NZ,SRTCLR
SRTCALL:
        CALL 0000H                ; The compiler patches the generated entry.
        JP 0                      ; Return to CP/M through the warm start.

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
        LD A,(HL)                 ; A zero flag means the binding is unbound.
        OR A                      ; Set Z for the unbound case.
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
        LD A,(DE)                 ; Preserve an escape mark already on this cell.
        AND 80H
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
; forms.  Other tag-zero scalars are true when their payload is nonzero.
SRTFALSE:
        LD (SRTTAG),A        ; Keep the logical tag while checking payload.
        OR A                      ; Nonzero tags are always true.
        JR NZ,SRTTRUE             ; Leave the original value untouched.
        LD A,H                    ; A tag-zero value is false only at payload zero.
        OR L                      ; Combine the two payload bytes for the test.
        JR NZ,SRTTRUE             ; A nonzero scalar is true.
        XOR A                     ; Record the false result in the state byte.
        JR SRTBDONE            ; Restore the original tag before returning.
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
        PUSH IX                   ; Restore the generated caller's return address.
        RET                       ; Return the checked value in A and HL.

; Allocate a fresh closure object.  HL names its descriptor and the current
; environment supplies the shared cell pointers for a nested lambda.
SRTMAKE:
        LD (SRTNEWD),HL           ; Retain the immutable procedure descriptor.
        LD DE,3                    ; Descriptor byte three stores the slot count.
        ADD HL,DE                  ; Read the fixed environment extent.
        LD A,(HL)                  ; Every closure receives that bounded slot area.
        LD (SRTSLOTS),A            ; Preserve the count while sizing the object.
        LD L,A                     ; Widen the slot count before doubling it.
        LD H,0
        ADD HL,HL                  ; Two bytes represent each shared cell pointer.
        LD (SRTBYTES),HL           ; Save the environment byte count.
        LD BC,2                    ; Two descriptor bytes precede the environment.
        ADD HL,BC                  ; HL is the complete closure-object size.
        LD BC,(SRTHEAPP)           ; BC is the next free heap address.
        PUSH BC                    ; Keep the object base for its header.
        ADD HL,BC                  ; Form the candidate new heap cursor.
        LD DE,SRTHEPEN           ; The guarded heap ceiling is exclusive.
        OR A                       ; Clear carry before the bound comparison.
        SBC HL,DE                  ; A nonnegative result would cross the ceiling.
        JP NC,SRTERROR             ; Refuse an allocation before touching memory.
        POP DE                     ; DE is the fresh closure object base.
        LD (SRTOBJ),DE             ; Return this pointer after copying the frame.
        LD HL,(SRTBYTES)           ; Recompute the complete object size.
        LD BC,2
        ADD HL,BC
        ADD HL,DE                  ; HL is the new heap cursor.
        LD (SRTHEAPP),HL           ; Publish the allocation before any copy loop.
        LD HL,(SRTNEWD)            ; Store the descriptor pointer in the object.
        LD A,L                     ; Descriptor low byte.
        LD (DE),A
        INC DE
        LD A,H                     ; Descriptor high byte.
        LD (DE),A
        INC DE                     ; DE now names the new environment area.
        LD (SRTNENV),DE          ; Keep the destination across the copy.
        LD HL,(SRTENV)             ; An outer environment may seed this closure.
        LD A,H
        OR L
        JR Z,SRTMAKE0              ; Top-level closures receive cleared slots.
        LD BC,(SRTBYTES)           ; Copy complete logical slots, including tags.
        LD A,B                     ; A nullary closure has no map to copy.
        OR C
        JR Z,SRTMAKEM              ; Skip LDIR when its count is zero.
        LDIR                       ; Source and destination are nonoverlapping.
SRTMAKEM:
        CALL SRTMARKC              ; Captured cells must survive later tail calls.
        JR SRTMAKER                ; Return the object pointer and procedure tag.
SRTMAKE0:
        LD HL,(SRTNENV)          ; Clear the fresh environment when no parent exists.
        LD BC,(SRTBYTES)           ; BC is the bounded byte count.
        LD A,B                     ; A zero-sized map needs no clearing pass.
        OR C
        JR Z,SRTMAKER              ; Nullary closures return immediately.
        XOR A                      ; Uninitialized values start at zero bytes.
SRTMAK0L:
        XOR A                      ; Keep every cleared byte at zero.
        LD (HL),A                  ; Clear one value byte.
        INC HL                     ; Advance through the new environment.
        DEC BC                     ; Consume one byte from the bounded extent.
        LD A,B
        OR C
        JR NZ,SRTMAK0L            ; Stop exactly at the environment boundary.
SRTMAKER:
        LD HL,(SRTOBJ)             ; Return the closure object as the payload.
        LD A,2                     ; Tag two denotes a callable closure object.
        RET                        ; The generated prefix jumps over its body.

; Allocate and clear one four-byte logical value cell from the runtime heap.
SRTCELL:
        LD HL,(SRTHEAPP)           ; The bump cursor names the new cell base.
        LD (SRTCELLP),HL           ; Preserve it while checking the heap guard.
        LD BC,4                    ; Every cell uses payload, tag and initialized flag.
        ADD HL,BC                  ; Form the candidate heap cursor.
        LD (SRTNEXT),HL            ; Keep it while the guard comparison runs.
        LD DE,SRTHEPEN           ; The guarded heap ceiling is exclusive.
        OR A                       ; Clear carry before the bound comparison.
        SBC HL,DE                  ; A nonnegative result would cross the ceiling.
        JP NC,SRTERROR             ; Refuse a cell before touching the heap.
        LD HL,(SRTNEXT)            ; Recover the candidate cursor after comparison.
        LD (SRTHEAPP),HL           ; Publish the new cursor after the check.
        LD HL,(SRTCELLP)           ; Recover the cell base for the clear loop.
        XOR A                      ; Unbound cells start with zero bytes.
        LD (HL),A                  ; Clear the payload low byte.
        INC HL
        LD (HL),A                  ; Clear the payload high byte.
        INC HL
        LD (HL),A                  ; Clear the value tag.
        INC HL
        LD (HL),A                  ; A zero flag keeps the cell unbound.
        LD HL,(SRTCELLP)           ; Return the new cell address in HL.
        RET

; Allocate a stack environment for an ordinary call and install fresh cells
; for every slot owned by the target procedure.
SRTENVIN:
        POP HL                    ; Remove the helper return before moving SP.
        LD (SRTRET),HL            ; Restore it after the activation map is ready.
        LD HL,0                    ; Z80 has no direct LD HL,SP instruction.
        ADD HL,SP                  ; HL is the caller's stack boundary.
        LD (SRTOLDSP),HL           ; The body epilogue restores this boundary.
        LD A,(SRTSLOTS)            ; The descriptor gives the pointer-array extent.
        LD L,A                     ; Widen the slot count before doubling it.
        LD H,0
        ADD HL,HL                  ; Two bytes name every shared cell pointer.
        LD (SRTBYTES),HL           ; Keep the complete pointer-map byte count.
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
        LD (SRTENV),HL             ; Runtime loads and stores use this array.
        LD (SRTNEXT),HL            ; Preserve the candidate stack boundary.
        LD DE,(SRTLOWSP)           ; Compare it with the lowest prior boundary.
        OR A                       ; Clear carry before the signed comparison.
        SBC HL,DE
        JR NC,SRTLOWDN             ; A higher boundary leaves the low-water mark.
        LD HL,(SRTNEXT)            ; Recover the candidate address after the compare.
        LD (SRTLOWSP),HL           ; Publish the deepest native stack boundary.
SRTLOWDN:
        LD HL,(SRTNEXT)            ; Recover the candidate map boundary.
        PUSH HL                   ; Preserve the destination while copying the map.
        POP DE                    ; DE is the destination for the closure map.
        LD HL,(SRTOBJ)             ; The source map begins after the descriptor word.
        INC HL
        INC HL
        LD BC,(SRTBYTES)           ; Skip a zero-length map without wrapping LDIR.
        LD A,B
        OR C
        JR Z,SRTENVCP              ; Nullary programs need no pointer copy.
        LDIR                       ; Preserve captured cells from the closure object.
SRTENVCP:
        CALL SRTOWN                ; Allocate fresh cells for owned slots.
        LD HL,(SRTRET)             ; Place the helper return below the map.
        PUSH HL
        RET

; Fill the active pointer array from the descriptor's owned-slot bit mask.
SRTOWN:
        LD HL,(SRTDESC)            ; Owned mask follows the formal index fields.
        LD DE,SRTOWNOF
        ADD HL,DE
        LD (SRTMASKP),HL           ; The outer loop consumes one mask byte at a time.
        XOR A
        LD (SRTSLOTI),A            ; Slot zero is the first mask bit.
        LD B,SRTMASKB              ; Always scan the fixed 128-slot mask.
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
        LD A,(SRTSLOTI)            ; Address the cell-pointer entry for this slot.
        CALL SRTADR                ; A pointer already present can be reused.
        JR C,SRTOWNN               ; A null pointer needs a fresh cell.
        LD (SRTCELLP),HL           ; Inspect the existing cell before clearing it.
        LD DE,3                    ; The initialized byte carries the escape bit.
        ADD HL,DE
        LD A,(HL)                  ; A high bit means an escaping closure owns it.
        AND 80H
        JR NZ,SRTOWNN              ; Allocate a distinct cell for escaped storage.
        JP SRTOWNC                 ; Reuse the cell and clear its old value.
SRTOWNN:
        PUSH BC                    ; SRTCELL uses BC for its heap increment.
        CALL SRTCELL               ; Allocate and clear the fresh logical cell.
        POP BC                     ; Resume the mask loops at the same bit.
        LD (SRTCELLP),HL           ; Preserve the new cell while finding its entry.
        LD A,(SRTSLOTI)            ; Address the newly allocated pointer entry.
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,(SRTENV)
        ADD HL,DE
        LD (SRTADDR),HL            ; Preserve the pointer-array entry for storage.
        LD DE,(SRTADDR)
        LD HL,(SRTCELLP)           ; Recover the allocated cell address.
        LD A,L                     ; Store its low pointer byte.
        LD (DE),A
        INC DE
        LD A,H                     ; Complete the shared-cell pointer.
        LD (DE),A
        JR SRTOWNNX                ; The new cell is already clear.
SRTOWNC:
        LD HL,(SRTCELLP)           ; Restore the cell base after checking its mark.
        LD (SRTCELLP),HL           ; Keep the reused cell while clearing four bytes.
        XOR A                      ; A reused slot must not retain its old value.
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
SRTOWNNX:
        LD A,(SRTMASKV)            ; Shift this mask bit out before the next slot.
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A            ; Advance through the fixed slot range.
        DEC C
        JR NZ,SRTOWNBT             ; Consume all eight bits in this mask byte.
        DJNZ SRTOWNB               ; Continue through the sixteen mask bytes.
        RET

; Copy only captured pointers from the target closure into the active map.
; Owned pointers remain in place so a tail transfer can reuse their cells.
SRTCOPYC:
        LD HL,(SRTDESC)            ; Capture mask follows the owned-slot mask.
        LD DE,SRTCAPOF
        ADD HL,DE
        LD (SRTMASKP),HL           ; The outer loop consumes one mask byte at a time.
        LD HL,(SRTOBJ)             ; Closure header precedes its captured map.
        LD DE,2
        ADD HL,DE
        LD (SRTSRC),HL             ; Keep the source map base across pointer writes.
        XOR A
        LD (SRTSLOTI),A            ; Slot zero is the first mask bit.
        LD A,SRTMASKB              ; Scan the fixed 128-slot capture mask.
        LD (SRTMASKN),A
SRTCPYB:
        LD HL,(SRTMASKP)
        LD A,(HL)                  ; Read the next eight capture bits.
        INC HL
        LD (SRTMASKP),HL
        LD (SRTMASKV),A
        LD A,8
        LD (SRTBITN),A
SRTCPYBT:
        LD A,(SRTMASKV)
        AND 1
        JR Z,SRTCPYNX              ; Uncaptured slots retain no target pointer.
        LD A,(SRTSLOTI)            ; Address the destination pointer pair.
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,(SRTENV)
        ADD HL,DE
        LD (SRTADDR),HL
        LD A,(SRTSLOTI)            ; Address the corresponding source pair.
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,(SRTSRC)
        ADD HL,DE
        LD E,(HL)                  ; Copy the captured pointer low byte.
        INC HL
        LD D,(HL)                  ; Copy the captured pointer high byte.
        LD HL,(SRTADDR)
        LD (HL),E
        INC HL
        LD (HL),D
SRTCPYNX:
        LD A,(SRTMASKV)            ; Shift this capture bit out before the next slot.
        SRL A
        LD (SRTMASKV),A
        LD A,(SRTSLOTI)
        INC A
        LD (SRTSLOTI),A
        LD A,(SRTBITN)
        DEC A
        LD (SRTBITN),A
        JR NZ,SRTCPYBT             ; Consume all eight bits in this mask byte.
        LD A,(SRTMASKN)
        DEC A
        LD (SRTMASKN),A
        JR NZ,SRTCPYB              ; Continue through the sixteen mask bytes.
        RET

; Mark every cell copied into a closure as escaped.  The mark lives in the
; high bit of the cell's initialized byte and keeps tail-frame reuse safe.
SRTMARKC:
        LD HL,(SRTNEWD)            ; The new descriptor owns the capture mask.
        LD DE,SRTCAPOF
        ADD HL,DE
        LD (SRTMASKP),HL           ; The outer loop consumes one mask byte.
        XOR A
        LD (SRTSLOTI),A            ; Slot zero is the first capture bit.
        LD A,SRTMASKB
        LD (SRTMASKN),A            ; The mask always covers 128 slots.
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
        LD L,A                     ; Widen the zero-based slot index.
        LD H,0
        ADD HL,HL                  ; Two bytes hold each cell pointer.
        LD DE,(SRTENV)
        ADD HL,DE
        LD E,(HL)                  ; Recover the cell pointer low byte.
        INC HL
        LD D,(HL)                  ; Recover the cell pointer high byte.
        LD A,D
        OR E
        RET Z                      ; An unbound capture has no cell to mark.
        EX DE,HL                   ; HL now names the shared cell.
        LD DE,3                    ; The initialized byte is the fourth byte.
        ADD HL,DE
        LD A,(HL)
        OR 80H                     ; Keep the initialized bit and add escape state.
        LD (HL),A
        RET

; Call an operator value saved on the side stack before argument evaluation.
; A contains the argument count and the native stack contains only arguments.
SRTOPINV:
        POP IX                    ; Save this helper's generated continuation.
        LD (SRTRET),IX            ; Packet helpers use IX for their own return.
        LD HL,(SRTENV)            ; Save the caller environment for a closure call.
        LD (SRTCENV),HL
        LD (SRTARGC),A            ; The count remains available to the packet pass.
        CALL SRTPACKO             ; Pack arguments, then recover the saved value.
        JP C,SRTERROR
        LD IX,(SRTRET)
        JR SRTDISP                ; Share primitive and closure dispatch.

; Call a fixed-arity procedure descriptor. A contains the argument count and
; the native stack contains callee, then arguments, in the order emitted by
; SCPUSH. The descriptor records the body address and formal slot addresses.
SRTINVOK:
        POP IX                    ; Save this helper's return address in IX.
        LD (SRTRET),IX            ; SRTPACK uses IX for its own helper return.
        LD HL,(SRTENV)            ; Save the caller environment for the new frame.
        LD (SRTCENV),HL           ; The body may invoke another closure.
        LD (SRTARGC),A            ; The count remains available to the packet pass.
        CALL SRTPACK               ; Move reverse-pushed values into the packet.
        JP C,SRTERROR              ; A malformed packet is a runtime failure.
        LD IX,(SRTRET)             ; Recover the generated continuation after packing.
SRTDISP:
        LD (SRTATMP),A             ; Keep the callee tag while selecting its path.
        LD (SRTVAL),HL             ; Keep the callee payload for both paths.
        OR A                       ; Tag zero may identify a predefined primitive.
        JR Z,SRTIPRIM              ; Validate its reserved payload and dispatch it.
        CP 2                       ; Tag two identifies a closure object.
        JP NZ,SRTERROR             ; Other scalar values cannot be called.
        LD HL,(SRTVAL)             ; Restore the closure object payload.
        LD (SRTOBJ),HL            ; SRTPACK returns the closure object payload.
        LD E,(HL)                  ; Read the descriptor pointer from its header.
        INC HL
        LD D,(HL)
        LD (SRTDESC),DE            ; Keep the descriptor for arity and body lookup.
        INC HL
        INC HL                     ; The object payload now names its environment.
        LD HL,(SRTDESC)            ; SRTDCHK consumes the descriptor address.
        CALL SRTDCHK              ; Validate the callee tag and descriptor arity.
        JP C,SRTERROR              ; Do not jump through an arbitrary value.
        LD HL,(SRTDESC)            ; Descriptor byte three fixes the map extent.
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSLOTS),A
        LD L,A                     ; Widen the slot count before doubling it.
        LD H,0
        ADD HL,HL
        LD (SRTBYTES),HL
        CALL SRTENVIN              ; Build an activation map below the stack.
        CALL SRTSARGS              ; Copy packet values into the formal slots.
        JP C,SRTERROR              ; A descriptor slot outside the image is invalid.
        PUSH IX                    ; Preserve the generated caller return address.
        LD DE,(SRTOLDSP)           ; Release the activation map when the body returns.
        PUSH DE                    ; The old stack boundary follows the return word.
        LD DE,(SRTCENV)            ; Preserve the caller environment below the frame.
        PUSH DE                    ; SRTINEND restores it after the body returns.
        LD HL,(SRTDESC)            ; Keep the descriptor for the epilogue restore.
        PUSH HL                    ; The epilogue restores this descriptor state.
        LD HL,(SRTDESC)            ; Read the descriptor body pointer.
        LD E,(HL)                  ; Body address low byte is descriptor offset zero.
        INC HL                     ; Advance to the body address high byte.
        LD D,(HL)                  ; DE now names the generated procedure body.
        LD HL,SRTINEND             ; Body RET returns through this frame epilogue.
        PUSH HL                    ; Keep descriptor and caller return below it.
        EX DE,HL                   ; HL receives the target body address.
        JP (HL)                    ; Enter without adding a second native return.

; Route a primitive callee through the checked packet dispatcher.
SRTIPRIM:
        CALL SRTIVAL               ; Validate and classify the reserved payload.
        JP SRTPRIM                 ; The generated continuation remains in IX.

; Validate a predefined primitive payload and retain its zero-based kind.
SRTIVAL:
        LD HL,(SRTVAL)             ; Primitive values use the reserved FE20..FE23 range.
        LD A,H
        CP 0FEH
        JP NZ,SRTERROR             ; A tag-zero value outside the range is not callable.
        LD A,L
        CP 20H
        JP C,SRTERROR
        CP 3DH                  ; Integer and type predicates extend the range to 28.
        JP NC,SRTERROR
        SUB 20H
        LD (SRTPID),A              ; Kind zero is addition; kind three is zero?.
        XOR A
        RET

; Proper-tail transfer: replace the current procedure frame before entering
; the target.  The current activation map is reused, so a tail loop does not
; allocate a new pointer array on every iteration.
SRTTAIL:
        LD HL,(SRTDESC)            ; Retain the current descriptor for reuse checks.
        LD (SRTCURD),HL
        LD B,A                     ; Preserve the generated argument count.
        LD A,(SRTSLOTS)            ; Preserve the current map extent for the guard.
        LD (SRTCURS),A
        LD A,B
        LD (SRTARGC),A             ; The tail packet uses the generated count.
        CALL SRTPACK               ; Parse arguments while the current frame remains.
        JP C,SRTERROR             ; A malformed tail packet is terminal.
SRTTARG:
        LD (SRTATMP),A             ; Keep the target tag while selecting its path.
        LD (SRTVAL),HL             ; Keep the target payload for both paths.
        OR A                       ; A predefined primitive has no closure object.
        JP Z,SRTTPRIM              ; Reuse the current epilogue after evaluation.
        CP 2                       ; Only closure objects reach the existing tail path.
        JP NZ,SRTERROR
        LD HL,(SRTVAL)             ; Restore the closure object payload.
        LD (SRTOBJ),HL            ; Resolve the target closure object.
        LD E,(HL)                  ; Read its descriptor pointer.
        INC HL
        LD D,(HL)
        LD (SRTDESC),DE            ; Keep the target descriptor for validation.
        INC HL
        INC HL
        LD HL,(SRTDESC)
        CALL SRTDCHK              ; Validate the target procedure and arity.
        JP C,SRTERROR             ; Do not reuse a frame for an invalid target.
        LD HL,(SRTDESC)            ; Load the target's bounded pointer-map extent.
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSLOTS),A
        LD L,A                     ; Widen the target slot count before doubling.
        LD H,0
        ADD HL,HL
        LD (SRTBYTES),HL
        LD A,(SRTCURS)             ; The active array must hold the target shape.
        LD B,A
        LD A,(SRTSLOTS)
        CP B
        JR C,SRTTERR               ; A larger tail target needs a new activation map.
        CALL SRTCOPYC              ; Replace captured pointers from the target closure.
        CALL SRTOWN                ; Reuse owned cells or allocate missing entries.
        JR SRTTKEEP
SRTTERR:
        JP SRTERROR                ; Reject a tail shape that cannot fit in place.
SRTTKEEP:
        CALL SRTSARGS              ; Install the target's formal values.
        JP C,SRTERROR             ; Reject an invalid descriptor slot.
        POP DE                    ; Discard the current body epilogue address.
        POP DE                    ; Discard the current procedure descriptor.
        POP DE                    ; Recover the caller environment below this frame.
        LD (SRTCENV),DE
        POP DE                    ; Recover the stack boundary below this frame.
        LD (SRTOLDSP),DE
        POP IX                    ; Recover the caller return below this frame.
        PUSH IX                   ; Preserve the original caller return word.
        LD DE,(SRTOLDSP)           ; Keep the reused activation map above the frame.
        PUSH DE
        LD DE,(SRTCENV)            ; Preserve the caller environment below the frame.
        PUSH DE
        LD HL,(SRTDESC)           ; Keep the target descriptor on the new frame.
        PUSH HL                   ; The target returns through SRTINEND.
        LD HL,SRTINEND            ; Install the target's single epilogue.
        PUSH HL                   ; Tail recursion therefore uses constant stack.
        LD HL,(SRTDESC)           ; Read the target body address.
        LD E,(HL)                 ; Body address low byte.
        INC HL                    ; Advance to the high body byte.
        LD D,(HL)                 ; Complete the target body address.
        EX DE,HL                  ; HL receives the target body pointer.
        JP (HL)                   ; Enter without a new continuation.

; Tail transfer for a saved operator.  Arguments are native-stack values and
; the operator was saved in the side stack before their expressions ran.
SRTOTAIL:
        LD HL,(SRTDESC)            ; Retain the current descriptor for reuse checks.
        LD (SRTCURD),HL
        LD B,A                     ; Preserve the generated argument count.
        LD A,(SRTSLOTS)            ; Preserve the current map extent for the guard.
        LD (SRTCURS),A
        LD A,B
        LD (SRTARGC),A             ; The side-stack packet uses the generated count.
        CALL SRTPACKO              ; Pack arguments, then recover the saved value.
        JP C,SRTERROR
        JP SRTTARG                 ; Share closure and primitive tail handling.

; A tail candidate is emitted as CALL until the compiler knows it is final.
; Discard that temporary return address before entering the tail-transfer path.
SRTTCALL:
        POP HL                    ; Remove the wrapper CALL continuation.
        JP SRTTAIL                ; The existing tail path sees the normal stack.

; The side-stack tail wrapper removes CALL's continuation before transfer.
SRTOTCL:
        POP HL
        JP SRTOTAIL

; Move the reverse-pushed argument values into SRTARGPK.  The callee remains
; below the packet and is returned in A:HL for SRTDCHK.
SRTPACK:
        POP IX                   ; Save the SRTPACK call return above the values.
        LD B,A                   ; B counts values still on the native stack.
        LD C,A                   ; C is the packet index, starting at count-1.
        LD A,B                   ; A supplies the zero-count test below.
        OR A                      ; No arguments leaves the callee at the top.
        JR Z,SRTPACKC             ; Skip the packet loop for a nullary call.
        DEC C                     ; The first reverse-pushed value is count minus one.
SRTPACKL:
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
        INC HL                    ; Advance to the tag byte.
        LD A,(SRTATMP)            ; Restore the value tag.
        LD (HL),A                 ; Store the logical tag.
        INC HL                    ; Advance to the packet initialized byte.
        LD A,1                    ; Packet values are always initialized.
        LD (HL),A                 ; Publish the complete argument record.
        DEC C                     ; The preceding source argument has a lower index.
        DJNZ SRTPACKL             ; Consume every staged argument.
SRTPACKC:
        POP HL                   ; Recover the callee payload.
        POP AF                   ; Recover the callee tag.
        PUSH IX                  ; Restore the SRTPACK call return.
        RET                      ; The caller selects closure or primitive dispatch.

; Validate the descriptor's fixed arity and retain its address in SRTDESC.
SRTDCHK:
        LD (SRTDESC),HL          ; The callee payload is the descriptor address.
        LD A,(SRTARGC)           ; Recover the staged argument count.
        LD DE,(SRTDESC)          ; Read the descriptor header.
        INC DE                   ; Skip the body address low byte.
        INC DE                   ; Skip the body address high byte.
        LD A,(DE)                 ; Descriptor offset two stores its arity.
        LD B,A                    ; Compare the staged count with that byte.
        LD A,(SRTARGC)            ; Restore the caller's argument count.
        CP B                      ; Every fixed formal must receive one value.
        JP NZ,SRTERROR             ; Arity mismatch is a runtime failure.
        XOR A                    ; Clear carry after an exact count match.
        RET                     ; SRTSARGS installs the packet values.

; Convert a logical slot number in A into its shared cell pointer.
SRTADR:
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
        JR NZ,SRTADRok
        SCF
        RET
SRTADRok:
        XOR A                     ; Carry clear reports a valid cell pointer.
        RET

; Load a procedure-local value through its current activation map.
SRTLOADI:
        CALL SRTADR               ; A contains the compiler-emitted slot index.
        JP C,SRTERROR             ; An unbound or missing cell is terminal.
        JP SRTLOAD                ; Reuse the checked four-byte cell loader.

; Store A:HL through the current activation map; B contains the slot index.
SRTSTORI:
        LD (SRTATMP),A            ; Preserve the value tag across slot addressing.
        LD (SRTVAL),HL            ; Preserve the value payload as well.
        LD A,B                    ; SRTADR consumes the zero-based slot index.
        CALL SRTADR
        JP C,SRTERROR
        EX DE,HL                  ; SRTSTORE receives its cell address in DE.
        LD HL,(SRTVAL)            ; Restore the caller's payload.
        LD A,(SRTATMP)            ; Restore the caller's tag.
        JP SRTSTORE               ; Publish the value and return it unchanged.

; Store through a local activation map while requiring prior initialization.
SRTSETI:
        LD (SRTATMP),A             ; Preserve the value tag across slot addressing.
        LD (SRTVAL),HL            ; Preserve the value payload as well.
        LD A,B                     ; SRTADR consumes the zero-based slot index.
        CALL SRTADR
        JP C,SRTUNBD
        EX DE,HL                   ; SRTSET receives the cell address in DE.
        LD HL,(SRTVAL)             ; Restore the caller's payload.
        LD A,(SRTATMP)             ; Restore the caller's tag.
        JP SRTSET                  ; Check initialization before storing.

; Copy packet values into the descriptor's formal slots.
SRTSARGS:
        LD A,(SRTARGC)           ; A zero-count procedure needs no stores.
        OR A                     ; Set Z for the nullary path.
        RET Z                    ; The descriptor body can start immediately.
        LD B,A                   ; B counts formal slots to fill.
        LD C,0                   ; C selects packet values in source order.
        LD HL,(SRTDESC)          ; HL begins at the descriptor body address.
        LD DE,4                  ; Formal slot indexes begin at descriptor offset four.
        ADD HL,DE                ; HL points at the first two-byte slot index.
        LD (SRTNEXT),HL          ; Preserve the descriptor cursor across packet work.
SRTSETLP:
        LD HL,(SRTNEXT)          ; Resume at the next formal slot record.
        LD A,(HL)                ; Read the compiler slot index from the descriptor.
        INC HL                   ; Advance to the high index byte.
        INC HL                   ; The next formal slot follows by two bytes.
        LD (SRTNEXT),HL          ; Keep the cursor while loading this argument.
        CALL SRTADR              ; Convert the slot index to the target cell address.
        JP C,SRTERROR              ; Every formal must have an owned cell.
        LD (SRTSLOT),HL          ; Preserve the destination across packet addressing.
        LD A,C                   ; Address packet index C.
        LD L,A                   ; Widen the packet index.
        LD H,0                   ; Each packet value occupies four bytes.
        ADD HL,HL                ; Two-byte offset.
        ADD HL,HL                ; Four-byte offset.
        LD DE,SRTARGPK           ; Add the packet base.
        ADD HL,DE                ; HL points at the packet value.
        LD E,(HL)                ; Read payload low.
        INC HL                   ; Advance to payload high.
        LD D,(HL)                ; DE now contains the payload value.
        INC HL                   ; Advance to the packet tag.
        LD A,(HL)                ; A contains the logical value tag.
        EX DE,HL                 ; HL receives the payload expected by SRTSTORE.
        LD DE,(SRTSLOT)          ; Restore the formal slot address.
        CALL SRTSTORE             ; Publish payload, tag and initialized state.
        INC C                    ; Advance to the next source argument.
        DJNZ SRTSETLP            ; Fill every formal slot.
        XOR A                    ; Carry clear reports a complete activation.
        RET                      ; The caller enters the generated body.

; Return from a generated procedure and restore the caller's frame words.
SRTINEND:
        LD (SRTVAL),HL           ; Save the body result while removing frame words.
        LD (SRTATMP),A           ; Preserve its tag across the frame restore.
        POP HL                   ; Remove the target descriptor below the body return.
        LD (SRTDESC),HL          ; Restore the enclosing descriptor for nested calls.
        POP HL                   ; Restore the caller environment pointer.
        LD (SRTENV),HL           ; Nested closures resume their defining environment.
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
