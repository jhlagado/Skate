;=============================================================================
;  Skate literal-recipe installation service
;=============================================================================
;
;  PURPOSE
;  -------
;  Rebuild the bounded postfix recipe emitted for quoted pair data.  The
;  compiler owns serialization; the runtime owns heap allocation, rooting and
;  pair representation.  Keeping the interpreter here prevents the generated
;  caller from knowing the collector's cell layout.
;
;  PUBLIC INTERFACE
;  ----------------
;
;  RTLIT
;    Input:  HL = first recipe byte, BC = recipe byte count.
;    Output: A:HL = the recipe's tagged value, carry clear.
;            Carry set means a malformed recipe or an impossible stack shape.
;
;  Recipe bytes use the native compiler's N8SERIAL shape.  A byte with bit 7
;  set introduces one tagged value followed by its little-endian payload word.
;  A zero byte combines the two preceding stack values with pairs.cons.  The
;  temporary rooted packet has four value-stack slots and four call slots;
;  that is the current bounded literal depth, not a heap-size assumption.
;=============================================================================

RTLIT:
        ; An empty recipe is the canonical empty list and needs no roots.
        LD A,B                  ; Test the complete 16-bit recipe length.
        OR C                    ; A zero length selects the NIL fast path.
        JP Z,RTLINIL            ; Do not reserve a packet for an empty stream.
        LD (RTLIPTR),HL         ; Retain the first byte across packet setup.
        LD (RTLILEFT),BC        ; Retain the bounded byte count independently.

        ; Eight four-byte slots leave four value-stack cells and four call
        ; cells (environment, callee and two arguments) in the one packet.
        LD BC,6                 ; RTPKNEW adds its two header slots.
        CALL RTPKNEW            ; Every recipe value is rooted before a cons.
        LD (RTLIPACK),DE        ; Keep the packet base for the interpreter.
        LD HL,16                ; The value stack starts after four headers.
        ADD HL,DE               ; DE remains the packet base for later calls.
        LD (RTLIBASE),HL        ; Four stack cells fit in the declared roots.
        XOR A                   ; The recipe has not pushed a value yet.
        LD (RTLIDEP),A          ; Depth is a byte because the bound is four.

        ; The temporary call packet uses slot one as the primitive callee.
        LD HL,4                 ; Slot zero is the environment header.
        ADD HL,DE               ; HL now points at the callee tag byte.
        LD (HL),0               ; Primitive values use logical tag zero.
        INC HL                  ; Advance to the callee payload low byte.
        LD (HL),29H             ; Primitive id 9 is pairs.cons (FE29H).
        INC HL                  ; Advance to the payload high byte.
        LD (HL),0FEH            ; Complete the private primitive encoding.
        INC HL                  ; Advance to the collector padding byte.
        LD (HL),0               ; Keep packet padding canonical.

RTLILP:
        ; Stop only after every recipe byte has been consumed.
        LD HL,(RTLILEFT)        ; Read the remaining byte count.
        LD A,H                  ; Combine both bytes for the zero test.
        OR L                    ; A nonzero count still has one operation.
        JP Z,RTLIDONE           ; The final stack must contain exactly one value.
        LD HL,(RTLIPTR)         ; Read the next operation byte.
        LD A,(HL)               ; Bit seven distinguishes values from cons.
        INC HL                  ; The cursor always advances past the opcode.
        LD (RTLIPTR),HL         ; Publish it before any operation can fail.
        LD HL,(RTLILEFT)        ; Remove the opcode from the remaining count.
        DEC HL                  ; The caller checked that the count was nonzero.
        LD (RTLILEFT),HL        ; Keep the count synchronized with the cursor.
        OR A                    ; Zero is the only non-value operation.
        JP Z,RTLIPAIR           ; Combine the two top stack values.
        BIT 7,A                 ; Every atom must carry the value marker bit.
        JP Z,RTLIBAD            ; A stray nonzero byte cannot be a recipe op.
        AND 7                   ; Logical tags occupy the low three bits.
        LD (RTLITAG),A          ; Preserve the tag while checking its payload.

        ; An atom needs two payload bytes after its marker.
        LD HL,(RTLILEFT)        ; At least two bytes must remain.
        LD DE,2                 ; Compare the remaining count with two.
        OR A                    ; Clear carry before the unsigned subtraction.
        SBC HL,DE               ; A borrow means the payload is truncated.
        JP C,RTLIBAD            ; Reject before reading beyond the recipe.
        LD (RTLILEFT),HL        ; Consume the two payload bytes atomically.
        LD HL,(RTLIPTR)         ; Read the little-endian payload word.
        LD E,(HL)               ; Preserve the low payload byte.
        INC HL                  ; Advance to the payload high byte.
        LD D,(HL)               ; DE now contains the complete value payload.
        INC HL                  ; Advance to the next recipe operation.
        LD (RTLIPTR),HL         ; Keep the cursor at the next opcode.
        LD HL,(RTLIDEP)         ; The value stack has one slot per depth.
        LD A,H                  ; A valid depth is a byte-sized value.
        OR A                    ; A nonzero high byte signals corruption.
        JP NZ,RTLIBAD           ; Do not calculate a wrapped slot address.
        LD A,L                  ; Convert the depth to a stack-slot index.
        CP 4                    ; Four value slots are reserved in the packet.
        JP NC,RTLIBAD           ; Reject a fifth value before any write.
        CALL RTLISLOT           ; Return HL at the slot selected by A.
        LD A,(RTLITAG)          ; Restore the atom's logical tag.
        LD (HL),A               ; Publish the tag before its payload bytes.
        INC HL                  ; Advance to the payload low byte.
        LD (HL),E               ; Store the payload in little-endian order.
        INC HL                  ; Advance to the payload high byte.
        LD (HL),D               ; Complete the tagged value.
        INC HL                  ; Advance to the collector padding byte.
        LD (HL),0               ; Every value slot has canonical zero padding.
        LD HL,(RTLIDEP)         ; Increment the checked stack depth.
        INC HL                  ; Exactly one atom has just been pushed.
        LD (RTLIDEP),HL         ; Preserve the complete word for the next op.
        JP RTLILP               ; Continue with the next recipe byte.

RTLIPAIR:
        ; A pair operation consumes the two most recent values.
        LD HL,(RTLIDEP)         ; Check the complete stack depth first.
        LD DE,2                 ; At least CAR and CDR must be present.
        OR A                    ; Clear carry before the unsigned comparison.
        SBC HL,DE               ; The subtraction also yields the result index.
        JP C,RTLIBAD            ; A pair without two operands is malformed.
        LD (RTLIDEST),HL        ; The result replaces the two operands' slots.
        LD A,L                  ; The result index is bounded by four slots.
        CALL RTLISLOT           ; HL points at the destination stack slot.
        LD (RTLIDEST),HL        ; Preserve the address across the runtime call.

        ; Copy CAR (the lower operand) into the temporary call packet.
        LD HL,(RTLIDEP)         ; Read the pre-pop pair depth again.
        DEC HL                  ; CDR index is depth minus one.
        DEC HL                  ; CAR index is depth minus two.
        LD A,L                  ; The checked result index is now in A.
        CALL RTLISLOT           ; HL points at CAR's value slot.
        CALL RTLCAR             ; Save its tag and payload in literal scratch.
        LD HL,(RTLIDEP)         ; Restore the pre-pop depth for CDR indexing.
        DEC HL                  ; CDR is the final value on the stack.
        LD A,L                  ; Convert its index to a byte-sized slot number.
        CALL RTLISLOT           ; HL points at CDR's value slot.
        CALL RTLCDR             ; Save CDR while the call packet is filled.

        ; The temporary packet's arguments are slots two and three.
        LD HL,(RTLIPACK)        ; Recover the packet base after both copies.
        LD DE,8                 ; Argument zero begins after two headers.
        ADD HL,DE               ; HL points at the CAR tag byte.
        LD A,(RTLICART)         ; Restore CAR's logical tag.
        LD (HL),A               ; Store CAR tag in the call packet.
        INC HL                  ; Advance to CAR payload low byte.
        LD DE,(RTLICARV)        ; Restore CAR payload.
        LD (HL),E               ; Store its low byte.
        INC HL                  ; Advance to CAR payload high byte.
        LD (HL),D               ; Store its high byte.
        INC HL                  ; Advance to CAR padding.
        LD (HL),0               ; Keep the call packet's padding canonical.
        INC HL                  ; Move to the CDR tag byte.
        LD A,(RTLICDRT)         ; Restore CDR's logical tag.
        LD (HL),A               ; Store CDR tag in the call packet.
        INC HL                  ; Advance to CDR payload low byte.
        LD DE,(RTLICDRV)        ; Restore CDR payload.
        LD (HL),E               ; Store its low byte.
        INC HL                  ; Advance to CDR payload high byte.
        LD (HL),D               ; Store its high byte.
        INC HL                  ; Advance to CDR padding.
        LD (HL),0               ; Keep the second argument slot canonical.

        LD DE,(RTLIPACK)        ; RTINVOKE receives the rooted call packet.
        LD BC,2                 ; pairs.cons consumes exactly two values.
        LD (RTPKARGC),BC        ; Dispatch must validate the two live call slots.
        CALL RTINVOKE           ; The runtime owns heap representation/GC.
        JP C,RTLIBAD            ; A provider failure cannot publish a result.
        LD DE,(RTLIDEST)        ; Restore the destination stack-slot address.
        LD (DE),A               ; Publish the returned pair's logical tag.
        INC DE                  ; Advance to the returned payload low byte.
        LD A,L                  ; Move the payload low byte through A for (DE).
        LD (DE),A               ; Store the payload in little-endian order.
        INC DE                  ; Advance to the returned payload high byte.
        LD A,H                  ; Move the payload high byte through A.
        LD (DE),A               ; Complete the returned pair reference.
        INC DE                  ; Advance to the destination padding byte.
        XOR A                   ; Padding is always canonical zero.
        LD (DE),A               ; Keep the resulting stack slot canonical.
        LD HL,(RTLIDEP)         ; Two values became one result.
        DEC HL                  ; Decrease the stack depth by one.
        LD (RTLIDEP),HL         ; Preserve the post-pair depth.
        JP RTLILP               ; Continue until the recipe cursor is empty.

RTLIDONE:
        ; Exactly one value must remain after the final recipe operation.
        LD HL,(RTLIDEP)         ; Read the complete post-parse depth.
        LD DE,1                 ; A valid recipe reduces to one root value.
        OR A                    ; Clear carry before comparing the depth.
        SBC HL,DE               ; Equality is the only successful terminal state.
        JP NZ,RTLIBAD           ; Empty or multiply-rooted recipes are invalid.
        LD A,0                  ; Select stack index zero for the final value.
        CALL RTLISLOT           ; HL points at the first value-stack slot.
        CALL RTLRET              ; Return its tag and payload in A:HL.
        ; Collapse the temporary packet to one rooted slot before returning.
        LD HL,(RTLIPACK)        ; The packet's first slot becomes the root anchor.
        LD DE,(RTLIBASE)        ; Read the old stack base to locate the result.
        LD A,(DE)               ; Preserve the final tag before copying it down.
        LD (HL),A               ; Store it in packet slot zero.
        INC DE                  ; Read the final payload low byte.
        INC HL                  ; Advance to the root payload low byte.
        LD A,(DE)               ; Copy the low payload byte.
        LD (HL),A               ; Publish it in the retained root slot.
        INC DE                  ; Read the final payload high byte.
        INC HL                  ; Advance to the root payload high byte.
        LD A,(DE)               ; Copy the high payload byte.
        LD (HL),A               ; Complete the retained root value.
        INC HL                  ; Advance to root padding.
        LD (HL),0               ; Keep the retained root slot canonical.
        LD HL,(RTLIPACK)        ; The first slot is the only live literal root.
        LD DE,4                 ; Move IY to the end of that one slot.
        ADD HL,DE               ; HL is the new root cursor.
        PUSH HL                 ; Update the architectural root cursor.
        POP IY                  ; The collector sees the same compact root span.
        LD (RTROOTP),HL         ; Keep the provider's collector descriptor aligned.
        LD HL,(RTLIPACK)        ; Re-select the compacted root slot.
        CALL RTLRET              ; Reload A:HL after the root compaction writes.
        OR A                    ; Preserve the result tag while clearing carry.
        RET                     ; The caller may enter generated top-level code.

RTLINIL:
        XOR A                   ; NIL is logical tag zero.
        LD HL,0FE02H            ; The canonical empty-list payload.
        OR A                    ; Return with carry clear.
        RET                     ; Empty recipes are valid scalar results.

RTLIBAD:
        SCF                     ; Malformed recipe or depth is a checked failure.
        RET                     ; The caller maps carry to its boot-failure path.

; Convert a byte-sized stack index in A to its four-byte slot address.
RTLISLOT:
        LD L,A                  ; Zero-extend the bounded stack index.
        LD H,0                  ; Four-byte slots use two left shifts.
        ADD HL,HL               ; First shift multiplies the index by two.
        ADD HL,HL               ; Second shift multiplies it by four.
        LD DE,(RTLIBASE)        ; Add the value-stack base after the shifts.
        ADD HL,DE               ; Return the selected slot address in HL.
        RET                     ; The caller owns the slot's read/write contract.

; Copy one value-stack slot into scratch before the packet is overwritten.
RTLCAR:
        LD A,(HL)               ; Save CAR's logical tag.
        LD (RTLICART),A         ; Preserve it across the CDR lookup.
        INC HL                  ; Advance to CAR payload low byte.
        LD E,(HL)               ; Preserve the low payload byte.
        INC HL                  ; Advance to CAR payload high byte.
        LD D,(HL)               ; DE is CAR's complete payload.
        LD (RTLICARV),DE        ; Keep it until the call packet is filled.
        RET                     ; The slot remains rooted in the packet.

RTLCDR:
        LD A,(HL)               ; Save CDR's logical tag.
        LD (RTLICDRT),A         ; Preserve it across the packet fill.
        INC HL                  ; Advance to CDR payload low byte.
        LD E,(HL)               ; Preserve the low payload byte.
        INC HL                  ; Advance to CDR payload high byte.
        LD D,(HL)               ; DE is CDR's complete payload.
        LD (RTLICDRV),DE        ; Keep it until RTINVOKE returns.
        RET                     ; The slot remains rooted in the packet.

RTLRET:
        LD A,(HL)               ; Read the selected value's logical tag.
        LD (RTLICRET),A         ; Keep it while loading the payload word.
        INC HL                  ; Advance to payload low byte.
        LD E,(HL)               ; Preserve the low payload byte.
        INC HL                  ; Advance to payload high byte.
        LD D,(HL)               ; DE is the selected payload.
        LD (RTLICREV),DE        ; Save it across root compaction writes.
        LD A,(RTLICRET)         ; Restore the selected logical tag.
        LD HL,(RTLICREV)        ; Restore the selected payload.
        RET                     ; Return the complete value in A:HL.
