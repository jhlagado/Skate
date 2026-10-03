;=============================================================================
;  Scope compiler byte emitter and bounded fixup tables
;=============================================================================
;
;  The parser writes native Z80 bytes into the staged image.  Immediate slot
;  addresses remain zero until the global and local data extents are known.
;  Each fixup is four bytes: staged patch address, slot kind and slot number.
;=============================================================================

; Emit a little-endian word from HL.
EM_WORD:
        LD (ST_WORD),HL           ; Preserve both bytes across SINK_PUT calls.
        LD A,(ST_WORD)            ; Emit the low address byte first.
        CALL SINK_PUT               ; Append the low byte to the image.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,(ST_WORD+1)          ; Recover the high address byte.
        JP SINK_PUT                 ; Append it and return through the emitter.

; Emit CALL address in HL.
EM_CALL:
        LD (ST_WORD),HL           ; Preserve the target while writing the opcode.
        LD DE,.VECTORS            ; The runtime installs these as RST 08H..30H.
        LD BC,06CFH               ; Six vectors; RST 08H is opcode CFH.
.FIND:
        LD A,(DE)
        INC DE
        CP L
        JR NZ,.SKIP
        LD A,(DE)
        CP H
        JR NZ,.SKIP
        LD A,C                    ; A one-byte RST replaces the CALL.
        JP SINK_PUT
.SKIP:
        INC DE
        LD A,C
        ADD A,8                   ; The next RST opcode.
        LD C,A
        DJNZ .FIND
        LD A,0CDH                 ; Z80 CALL has opcode CDH.
        CALL SINK_PUT               ; Append the opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(ST_WORD)           ; Restore the target word.
        JP EM_WORD                ; Append it and return.

; Runtime helpers reached by RST 08H..30H, in vector order (see RST_SET).
.VECTORS: DW ARG_PUSH,L_LOAD,PRIM_OP,QT_PUSH,G_OPSH,INV_OP

; Emit a literal exact integer in HL.
EM_INT:
        LD (ST_IMMED),HL          ; Preserve the literal while writing opcodes.
        LD A,21H                  ; LD HL,nn loads the result payload.
        CALL SINK_PUT               ; Append the load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(ST_IMMED)          ; Recover the literal payload.
        CALL EM_WORD              ; Append the payload word.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,3EH                  ; LD A,3 selects the exact-integer tag.
        CALL SINK_PUT               ; Append the tag-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,3                    ; The generated value is an exact integer.
        JP SINK_PUT                 ; Append the tag and return.

; Emit a binary16 literal whose payload is already in HL.
EM_FLOAT:
        LD (ST_IMMED),HL          ; Preserve the inexact payload during opcode emission.
        LD A,21H                  ; LD HL,nn loads the binary16 payload.
        CALL SINK_PUT                ; Append the payload-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(ST_IMMED)          ; Recover the binary16 payload.
        CALL EM_WORD               ; Append the payload in little-endian order.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINK_PUT

; Emit an unbound predefined procedure as a reserved immediate value.
; A contains its one-based primitive kind; the runtime subtracts $20 from the
; payload low byte when it selects the dispatcher entry.
EM_PRIM:
        LD (ST_PRIM),A            ; Preserve the kind while writing the value.
        LD A,21H                  ; LD HL,nn loads the reserved payload.
        CALL SINK_PUT
        RET C
        LD A,(ST_PRIM)
        DEC A
        ADD A,20H
        CALL SINK_PUT                 ; Payload low byte is $20 plus kind minus one.
        RET C
        LD A,0FEH
        CALL SINK_PUT                 ; All primitive payloads use the reserved high byte.
        RET C
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINK_PUT

; Emit and save a predefined procedure on the runtime operator side stack.
.SAVE:
        CALL EM_PRIM               ; Leave the immediate value in A:HL.
        RET C
        LD HL,OPS_PUSH             ; Preserve it while application arguments compile.
        JP EM_CALL

; Emit #f or #t.  Booleans use the reserved FE00/FE01 scalar payloads so
; every other tag-zero payload remains available to binary16 numbers.
EM_BOOL:
        LD (ST_BYTE),A            ; Preserve the reader's zero-or-one value.
        LD A,21H                  ; Load the boolean payload into HL.
        CALL SINK_PUT               ; Append the payload-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD H,0FEH                 ; Both booleans use the reserved FE scalar range.
        LD A,(ST_BYTE)            ; Recover the selected low payload byte.
        LD L,A                    ; FE00H and FE01H distinguish the booleans.
        CALL EM_WORD              ; Append the payload word.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINK_PUT

; Emit a byte character.  Characters share the scalar tag with booleans, but
; keep the FFxx payload so predicates can distinguish them from numbers.
EM_CHAR:
        LD (ST_IMMED),HL          ; Preserve the complete FFxx payload.
        LD A,21H                  ; Load the character payload into HL.
        CALL SINK_PUT               ; Append the payload-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(ST_IMMED)          ; Recover the character payload.
        CALL EM_WORD              ; Append both payload bytes unchanged.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINK_PUT

; Emit the canonical unspecified value (tag zero, payload FE04H).
EM_VOID:
        LD HL,0FE04H              ; FE04H is the language's UNSPECIFIED value.
; Emit LD HL,nn and LD A,0 for the tag-zero immediate in HL.
EM_IMM:
        PUSH HL
        LD A,21H                  ; Load the reserved immediate payload.
        CALL SINK_PUT               ; Append the LD HL,nn opcode.
        POP HL
        RET C                     ; Preserve a staged-output capacity failure.
        CALL EM_WORD               ; Append the payload in little-endian order.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINK_PUT

; Record the value before emitting PUSH AF/PUSH HL.  The runtime collector
; uses the parallel records while a nested allocation is in progress.
EM_PUSH:
        LD HL,ARG_PUSH             ; Root the operand, then PUSH AF and PUSH HL.
        JP EM_CALL

; Recover a value saved by EM_PUSH.  The payload was pushed after its tag.
EM_POP:
        LD HL,ARG_POP             ; POP HL, POP AF and retire the root record.
        JP EM_CALL

; Emit a clear of a recursive cell before its first initializer runs.
EM_CLEAR:
        LD A,L
        LD (ST_FSLOT),A
        LD A,1
        CALL EM_ISPKG
        JR Z,.STATIC
        LD A,06H
        CALL SINK_PUT
        RET C
        LD A,(ST_FSLOT)
        CALL SINK_PUT
        RET C
        LD HL,FRM_CLR
        JP EM_CALL
.STATIC:
        LD A,21H
        CALL SINK_PUT
        RET C
        LD HL,(ST_PC)
        LD A,1
        LD (ST_FKIND),A
        LD A,(ST_FSLOT)
        CALL EM_FIXUP
        RET C
        XOR A
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        LD HL,RT_CLR
        JP EM_CALL

; Emit CALL HL followed by the slot byte ST_FSLOT.  Globals and procedure
; locals are named this way; the runtime helper finds the slot.
EM_SLOT:
        CALL EM_CALL
        RET C
        LD A,(ST_FSLOT)
        JP SINK_PUT

; Emit the placeholder address word of static local ST_FSLOT.  Static locals
; are placed after the code, so the word is recorded as a fixup.
EM_ADDR:
        LD HL,(ST_PC)             ; The next two bytes are the patch location.
        CALL EM_FIXUP             ; Record them before writing placeholder zeroes.
        RET C                     ; A full fixup table aborts the current form.
        XOR A                     ; Address bytes are filled after layout closes.
        CALL SINK_PUT
        RET C
        JP SINK_PUT

; Emit a direct load from a compiler-assigned slot.  A=0 selects a global
; slot; A=1 selects a local slot.  L contains the slot number.
EM_LOAD:
        LD (ST_FKIND),A           ; Keep the slot kind with the pending record.
        LD A,L                    ; Copy the slot number into the pending record.
        LD (ST_FSLOT),A           ; A single byte addresses every current slot.
        LD A,(ST_FKIND)
        CP 1
        JR NZ,.STATIC               ; Globals and top-level lets retain static slots.
        CALL EM_ISPKG              ; Package-owned locals remain static.
        JR Z,.STATIC
        LD HL,L_LOAD               ; Load through the active environment map.
        JP EM_SLOT
.STATIC:
        LD A,(ST_FKIND)
        OR A
        LD HL,G_LOAD               ; Globals have fixed slots.
        JP Z,EM_SLOT
        LD A,21H                  ; LD HL,nn receives the slot address.
        CALL SINK_PUT               ; Append the load opcode.
        RET C
        CALL EM_ADDR              ; Emit the address or its fixup placeholder.
        RET C
        LD HL,RT_LOAD        ; Generated code calls the runtime slot loader.
        JP EM_CALL                ; Append the call and return.

; Emit a store to a compiler-assigned slot.  The value remains in A/HL for the
; caller; the generated code moves the destination address into DE first.
EM_STORE:
        LD (ST_FKIND),A           ; Keep the slot kind with the pending record.
        LD A,L                    ; Copy the slot number into the pending record.
        LD (ST_FSLOT),A           ; A single byte addresses every current slot.
        LD A,(ST_FKIND)            ; Procedure locals use the active environment.
        CP 1
        JR NZ,.STATIC               ; Globals and top-level lets retain static slots.
        LD A,(ST_PROC)
        CALL EM_ISPKG              ; Package-owned locals remain static.
        JR Z,.STATIC
        LD HL,L_STORE              ; Store through the active environment map.
        LD A,(ST_CHECK)        ; Mutation selects the checked local helper.
        OR A
        JP Z,EM_SLOT              ; Definitions use the initializing helper.
        LD HL,L_SET
        JP EM_SLOT
.STATIC:
        LD A,(ST_FKIND)
        OR A
        JR NZ,.ADDRESS
        LD HL,G_STORE              ; Globals have fixed slots.
        LD A,(ST_CHECK)
        OR A
        JP Z,EM_SLOT
        LD HL,G_SET
        JP EM_SLOT
.ADDRESS:
        LD A,11H                  ; LD DE,nn receives the slot address.
        CALL SINK_PUT               ; Append the store-address opcode.
        RET C
        CALL EM_ADDR              ; Emit the address or its fixup placeholder.
        RET C
        LD HL,RT_STORE              ; Generated code calls the runtime slot store.
        LD A,(ST_CHECK)         ; Mutation selects the checked static helper.
        OR A
        JR Z,.HELPER               ; Definitions initialize the destination.
        LD HL,RT_SET
.HELPER:
        JP EM_CALL                ; Append the call and return.

; Save the value of a predefined global procedure before its arguments run.
; The side stack preserves Scheme's operator-first evaluation order without
; placing a callee word on the native stack for every recursive call.
EM_HOLD:
        LD A,(ST_GCALL)           ; The marker carries the selected global slot.
        LD (ST_FSLOT),A
        LD HL,G_OPSH              ; Load it and save it on the side stack.
        JP EM_SLOT

; Record a two-byte staged address, slot kind and slot number.
EM_FIXUP:
        LD (ST_FADDR),HL          ; Preserve the patch address while indexing.
        LD HL,(ST_FIXES)          ; The table admits the full global fixup target.
        LD DE,320                 ; Leave one guarded region before the tables.
        OR A                      ; Clear carry before the capacity comparison.
        SBC HL,DE                 ; A carry-free result means the table is full.
        JP NC,ERR_CAP             ; A full fixup table is a capacity error.
        LD HL,(ST_FIXES)          ; Recover the record index after the comparison.
        LD DE,W_FIXUPS             ; Locate the next free fixup record.
        ADD HL,HL                 ; Multiply the record index by two.
        ADD HL,HL                 ; Multiply by four for the record width.
        ADD HL,DE                 ; HL points at its staged-address field.
        LD DE,(ST_FADDR)          ; Restore the address of the two patch bytes.
        LD (HL),E                 ; Store the patch address low byte.
        INC HL                    ; Advance to the high patch-address byte.
        LD (HL),D                 ; Store the patch address high byte.
        INC HL                    ; Advance to the kind byte.
        LD A,(ST_FKIND)           ; Store global or local kind.
        LD (HL),A                 ; Publish the kind before the slot number.
        INC HL                    ; Advance to the slot-number byte.
        LD A,(ST_FSLOT)           ; Store the compiler-assigned slot number.
        LD (HL),A                 ; Complete the fixup record.
        LD HL,(ST_FIXES)          ; Increment the record count after the write.
        INC HL                    ; The next record uses the following four bytes.
        LD (ST_FIXES),HL          ; Publish the complete fixup.
        XOR A                     ; A successful record returns with carry clear.
        RET                       ; Return to the code emitter.

EM_FAIL:
        SCF                       ; Branch patch failures are terminal.
        RET                       ; No staged output is published on this path.

; Record the staged operand word of a tail-call wrapper for later rewriting.
EM_TAIL:
        LD (ST_TAILP),HL           ; Preserve the operand address during indexing.
        LD A,(ST_TAILS)            ; Each record occupies one staged address word.
        CP W_TAIL_N                ; Refuse a body that exceeds the patch bound.
        JP NC,ERR_CAP              ; A partial tail record cannot be emitted safely.
        LD L,A                     ; Widen the record index before doubling it.
        LD H,0
        ADD HL,HL
        LD DE,W_TCALLS             ; Locate the next free tail-candidate record.
        ADD HL,DE
        LD DE,(ST_TAILP)           ; Restore the staged operand address.
        LD (HL),E                  ; Store its low byte.
        INC HL
        LD (HL),D                  ; Store its high byte.
        LD L,A                     ; Reuse the candidate index for its side flag.
        LD H,0
        LD DE,W_TAILOP
        ADD HL,DE
        LD A,(ST_ROUTE)            ; Modes two and three become flags one and two.
        CP 2
        JR C,.FLAG
        DEC A
.FLAG:
        LD (HL),A                  ; Preserve the dispatch path for later rewriting.
        LD A,(ST_TAILS)            ; Advance the candidate count after the write.
        INC A
        LD (ST_TAILS),A
        XOR A
        RET

; Rewrite the current body's non-final tail candidates as ordinary calls.
EM_PLAIN:
        LD A,(ST_MARK)             ; The current expression owns records from here.
        LD B,A                     ; B walks the bounded patch-record range.
.LOOP:
        LD A,(ST_TAILS)            ; Stop when every candidate in this expression is fixed.
        CP B
        JR Z,.DONE
        LD L,B                     ; Address the candidate word by its record index.
        LD H,0
        ADD HL,HL
        LD DE,W_TCALLS
        ADD HL,DE
        LD E,(HL)                  ; Recover the staged operand address.
        INC HL
        LD D,(HL)
        EX DE,HL                   ; HL now names the generated CALL operand.
        PUSH HL                    ; Preserve the patch address while reading its flag.
        LD L,B                     ; The flag table uses one byte per candidate.
        LD H,0
        LD DE,W_TAILOP
        ADD HL,DE
        LD A,(HL)                  ; A nonzero flag selects the side-stack entry.
        POP HL                     ; Restore the staged operand address.
        OR A
        JR Z,.ORDINARY
        LD DE,PRIM_OP              ; A direct primitive returns normally.
        CP 2
        JR Z,.WRITE
        LD DE,INV_OP               ; Keep operator-first evaluation for this call.
        JR .WRITE
.ORDINARY:
        LD DE,INV_CALL             ; Ordinary calls preserve the continuation.
.WRITE:
        CALL SINK_FIX             ; Route tail-call rewrites through the sink.
        INC B                      ; Advance to the next tail candidate.
        JR .LOOP
.DONE:
        LD A,B                     ; Discard the records just rewritten.
        LD (ST_TAILS),A
        XOR A
        RET

; Return Z when the selected local slot belongs to package-level storage.
EM_ISPKG:
        LD A,(ST_FSLOT)            ; Address the owner byte for the selected slot.
        LD L,A
        LD H,0
        LD DE,W_LOWNER
        ADD HL,DE
        LD A,(HL)
        CP 0FFH
        RET

; Emit a conditional absolute jump and return its patch address in HL.  The
; caller patches the address when the matching branch target is known.
EM_JZ:
        LD A,0CAH                 ; JP Z,nn branches when RT_TEST returns Z.
        CALL SINK_PUT               ; Append the conditional-jump opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(ST_PC)             ; The following word is the branch patch.
        PUSH HL                   ; Preserve the patch address across zero writes.
        XOR A                     ; Start with an unresolved target word.
        CALL SINK_PUT               ; Append the low placeholder byte.
        JR C,EM_ABORT             ; Leave the patch address off the stack.
        CALL SINK_PUT               ; Append the high placeholder byte.
        JR C,EM_ABORT             ; Leave the patch address off the stack.
        POP HL                    ; Return the branch patch location.
        OR A                      ; Successful emission returns carry clear.
        RET                       ; The caller owns the patch stack.

EM_JNZ:
        LD A,0C2H                 ; JP NZ,nn is the OR short-circuit branch.
        CALL SINK_PUT               ; Append the conditional-jump opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(ST_PC)             ; The following word is the branch patch.
        PUSH HL                   ; Preserve the patch address across zero writes.
        XOR A                     ; Start with an unresolved target word.
        CALL SINK_PUT               ; Append the low placeholder byte.
        JR C,EM_ABORT             ; Leave the patch address off the stack.
        CALL SINK_PUT               ; Append the high placeholder byte.
        JR C,EM_ABORT             ; Leave the patch address off the stack.
        POP HL                    ; Return the branch patch location.
        OR A                      ; Successful emission returns carry clear.
        RET                       ; The caller owns the patch stack.

; Emit JP nn and return its two-byte patch location in HL.
EM_JP:
        LD A,0C3H                 ; Absolute Z80 jump opcode.
        CALL SINK_PUT               ; Append the unconditional-jump opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(ST_PC)             ; The following word is the branch patch.
        PUSH HL                   ; Preserve the patch address across zero writes.
        XOR A                     ; Start with an unresolved target word.
        CALL SINK_PUT               ; Append the low placeholder byte.
        JR C,EM_ABORT             ; Leave the patch address off the stack.
        CALL SINK_PUT               ; Append the high placeholder byte.
        JR C,EM_ABORT             ; Leave the patch address off the stack.
        POP HL                    ; Return the branch patch location.
        OR A                      ; Successful emission returns carry clear.
        RET                       ; The caller owns the patch stack.

EM_ABORT:
        POP HL                    ; Remove the saved patch address on failure.
        SCF                       ; Keep the staged-output diagnostic asserted.
        RET

; Append the return instruction used by the runtime entry point.
EM_RET:
        LD A,0C9H                 ; RET hands the final value to RT_CALL.
        JP SINK_PUT                 ; Append the single-byte instruction.
