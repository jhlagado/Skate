;=============================================================================
;  Scope compiler byte emitter and bounded fixup tables
;=============================================================================
;
;  The parser writes native Z80 bytes into the staged image.  Immediate slot
;  addresses remain zero until the global and local data extents are known.
;  Each fixup is four bytes: staged patch address, slot kind and slot number.
;=============================================================================

; Emit a little-endian word from HL.
SCWORD:
        LD (SCWTMP),HL            ; Preserve both bytes across SCBYTE calls.
        LD A,(SCWTMP)             ; Emit the low address byte first.
        CALL SINKBYTE               ; Append the low byte to the image.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,(SCWTMP+1)           ; Recover the high address byte.
        JP SINKBYTE                 ; Append it and return through the emitter.

; Emit CALL address in HL.
SCCALL:
        LD (SCWTMP),HL            ; Preserve the target while writing the opcode.
        LD DE,SCRSTT              ; The runtime installs these as RST 08H..30H.
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
        JP SINKBYTE
.SKIP:
        INC DE
        LD A,C
        ADD A,8                   ; The next RST opcode.
        LD C,A
        DJNZ .FIND
        LD A,0CDH                 ; Z80 CALL has opcode CDH.
        CALL SINKBYTE               ; Append the opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(SCWTMP)            ; Restore the target word.
        JP SCWORD                 ; Append it and return.

; Runtime helpers reached by RST 08H..30H, in vector order (see RST_SET).
SCRSTT: DW ARG_PUSH,L_LOAD,PRIM_OP,QT_PUSH,G_OPSH,INV_OP

; Emit a literal exact integer in HL.
SCLIT:
        LD (SCVTMP),HL            ; Preserve the literal while writing opcodes.
        LD A,21H                  ; LD HL,nn loads the result payload.
        CALL SINKBYTE               ; Append the load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(SCVTMP)            ; Recover the literal payload.
        CALL SCWORD               ; Append the payload word.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,3EH                  ; LD A,3 selects the exact-integer tag.
        CALL SINKBYTE               ; Append the tag-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,3                    ; The generated value is an exact integer.
        JP SINKBYTE                 ; Append the tag and return.

; Emit a binary16 literal whose payload is already in HL.
FNUM:
        LD (SCVTMP),HL            ; Preserve the inexact payload during opcode emission.
        LD A,21H                  ; LD HL,nn loads the binary16 payload.
        CALL SINKBYTE                ; Append the payload-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(SCVTMP)            ; Recover the binary16 payload.
        CALL SCWORD                ; Append the payload in little-endian order.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINKBYTE

; Emit an unbound predefined procedure as a reserved immediate value.
; A contains its one-based primitive kind; the runtime subtracts $20 from the
; payload low byte when it selects the dispatcher entry.
SCPRIM:
        LD (SCPKIND),A            ; Preserve the kind while writing the value.
        LD A,21H                  ; LD HL,nn loads the reserved payload.
        CALL SINKBYTE
        RET C
        LD A,(SCPKIND)
        DEC A
        ADD A,20H
        CALL SINKBYTE                 ; Payload low byte is $20 plus kind minus one.
        RET C
        LD A,0FEH
        CALL SINKBYTE                 ; All primitive payloads use the reserved high byte.
        RET C
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINKBYTE

; Emit and save a predefined procedure on the runtime operator side stack.
SCPRIMV:
        CALL SCPRIM                ; Leave the immediate value in A:HL.
        RET C
        LD HL,SRTOPUSH             ; Preserve it while application arguments compile.
        JP SCCALL

; Emit #f or #t.  Booleans use the reserved FE00/FE01 scalar payloads so
; every other tag-zero payload remains available to binary16 numbers.
SCBOOL:
        LD (SCBTMP),A             ; Preserve the reader's zero-or-one value.
        LD A,21H                  ; Load the boolean payload into HL.
        CALL SINKBYTE               ; Append the payload-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD H,0FEH                 ; Both booleans use the reserved FE scalar range.
        LD A,(SCBTMP)             ; Recover the selected low payload byte.
        LD L,A                    ; FE00H and FE01H distinguish the booleans.
        CALL SCWORD               ; Append the payload word.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINKBYTE

; Emit a byte character.  Characters share the scalar tag with booleans, but
; keep the FFxx payload so predicates can distinguish them from numbers.
SCCHAR:
        LD (SCVTMP),HL            ; Preserve the complete FFxx payload.
        LD A,21H                  ; Load the character payload into HL.
        CALL SINKBYTE               ; Append the payload-load opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(SCVTMP)            ; Recover the character payload.
        CALL SCWORD               ; Append both payload bytes unchanged.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINKBYTE

; Emit the canonical unspecified value (tag zero, payload FE04H).
SCUNS:
        LD HL,0FE04H              ; FE04H is the language's UNSPECIFIED value.
; Emit LD HL,nn and LD A,0 for the tag-zero immediate in HL.
SCIMM:
        PUSH HL
        LD A,21H                  ; Load the reserved immediate payload.
        CALL SINKBYTE               ; Append the LD HL,nn opcode.
        POP HL
        RET C                     ; Preserve a staged-output capacity failure.
        CALL SCWORD                ; Append the payload in little-endian order.
        RET C                     ; Preserve a staged-output capacity failure.
        LD A,0AFH                 ; XOR A: the tag is zero.
        JP SINKBYTE

; Record the value before emitting PUSH AF/PUSH HL.  The runtime collector
; uses the parallel records while a nested allocation is in progress.
SCPUSH:
        LD HL,ARG_PUSH             ; Root the operand, then PUSH AF and PUSH HL.
        JP SCCALL

; Recover a value saved by SCPUSH.  The payload was pushed after its tag.
SCPOP:
        LD HL,ARG_POP             ; POP HL, POP AF and retire the root record.
        JP SCCALL

; Emit a clear of a recursive cell before its first initializer runs.
SCCLEAR:
        LD A,L
        LD (SCFSLOT),A
        LD A,1
        CALL SCLOCALQ
        JR Z,SCCLRS
        LD A,06H
        CALL SINKBYTE
        RET C
        LD A,(SCFSLOT)
        CALL SINKBYTE
        RET C
        LD HL,FRM_CLR
        JP SCCALL
SCCLRS:
        LD A,21H
        CALL SINKBYTE
        RET C
        LD HL,(SCPC)
        LD A,1
        LD (SCFKIND),A
        LD A,(SCFSLOT)
        CALL SCFIX
        RET C
        XOR A
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        LD HL,RT_CLR
        JP SCCALL

; Emit CALL HL followed by the slot byte SCFSLOT.  Globals and procedure
; locals are named this way; the runtime helper finds the slot.
SCSLOTC:
        CALL SCCALL
        RET C
        LD A,(SCFSLOT)
        JP SINKBYTE

; Emit the placeholder address word of static local SCFSLOT.  Static locals
; are placed after the code, so the word is recorded as a fixup.
SCSLOTW:
        LD HL,(SCPC)              ; The next two bytes are the patch location.
        CALL SCFIX                ; Record them before writing placeholder zeroes.
        RET C                     ; A full fixup table aborts the current form.
        XOR A                     ; Address bytes are filled after layout closes.
        CALL SINKBYTE
        RET C
        JP SINKBYTE

; Emit a direct load from a compiler-assigned slot.  A=0 selects a global
; slot; A=1 selects a local slot.  L contains the slot number.
SCLOAD:
        LD (SCFKIND),A            ; Keep the slot kind with the pending record.
        LD A,L                    ; Copy the slot number into the pending record.
        LD (SCFSLOT),A            ; A single byte addresses every current slot.
        LD A,(SCFKIND)
        CP 1
        JR NZ,SCLDFIX               ; Globals and top-level lets retain static slots.
        CALL SCLOCALQ              ; Package-owned locals remain static.
        JR Z,SCLDFIX
        LD HL,L_LOAD               ; Load through the active environment map.
        JP SCSLOTC
SCLDFIX:
        LD A,(SCFKIND)
        OR A
        LD HL,G_LOAD               ; Globals have fixed slots.
        JP Z,SCSLOTC
        LD A,21H                  ; LD HL,nn receives the slot address.
        CALL SINKBYTE               ; Append the load opcode.
        RET C
        CALL SCSLOTW              ; Emit the address or its fixup placeholder.
        RET C
        LD HL,SRTLDA         ; Generated code calls the runtime slot loader.
        JP SCCALL                 ; Append the call and return.

; Emit a store to a compiler-assigned slot.  The value remains in A/HL for the
; caller; the generated code moves the destination address into DE first.
SCSTORE:
        LD (SCFKIND),A            ; Keep the slot kind with the pending record.
        LD A,L                    ; Copy the slot number into the pending record.
        LD (SCFSLOT),A            ; A single byte addresses every current slot.
        LD A,(SCFKIND)             ; Procedure locals use the active environment.
        CP 1
        JR NZ,SCSTFIX               ; Globals and top-level lets retain static slots.
        LD A,(SCCURPR)
        CALL SCLOCALQ              ; Package-owned locals remain static.
        JR Z,SCSTFIX
        LD HL,L_STORE              ; Store through the active environment map.
        LD A,(SCMUT)           ; Mutation selects the checked local helper.
        OR A
        JP Z,SCSLOTC              ; Definitions use the initializing helper.
        LD HL,L_SET
        JP SCSLOTC
SCSTFIX:
        LD A,(SCFKIND)
        OR A
        JR NZ,SCSTSTA
        LD HL,G_STORE              ; Globals have fixed slots.
        LD A,(SCMUT)
        OR A
        JP Z,SCSLOTC
        LD HL,G_SET
        JP SCSLOTC
SCSTSTA:
        LD A,11H                  ; LD DE,nn receives the slot address.
        CALL SINKBYTE               ; Append the store-address opcode.
        RET C
        CALL SCSLOTW              ; Emit the address or its fixup placeholder.
        RET C
        LD HL,SRTSTA                ; Generated code calls the runtime slot store.
        LD A,(SCMUT)            ; Mutation selects the checked static helper.
        OR A
        JR Z,SCSTSTAT              ; Definitions initialize the destination.
        LD HL,SRTSETS
SCSTSTAT:
        JP SCCALL                 ; Append the call and return.

; Save the value of a predefined global procedure before its arguments run.
; The side stack preserves Scheme's operator-first evaluation order without
; placing a callee word on the native stack for every recursive call.
SCGMARK:
        LD A,(SCAPGSL)            ; The marker carries the selected global slot.
        LD (SCFSLOT),A
        LD HL,G_OPSH              ; Load it and save it on the side stack.
        JP SCSLOTC

; Record a two-byte staged address, slot kind and slot number.
SCFIX:
        LD (SCFPTR),HL            ; Preserve the patch address while indexing.
        LD HL,(SCFIXN)            ; The table admits the full global fixup target.
        LD DE,320                 ; Leave one guarded region before the tables.
        OR A                      ; Clear carry before the capacity comparison.
        SBC HL,DE                 ; A carry-free result means the table is full.
        JP NC,SCCAP               ; A full fixup table is a capacity error.
        LD HL,(SCFIXN)            ; Recover the record index after the comparison.
        LD DE,SCFIXTAB             ; Locate the next free fixup record.
        ADD HL,HL                 ; Multiply the record index by two.
        ADD HL,HL                 ; Multiply by four for the record width.
        ADD HL,DE                 ; HL points at its staged-address field.
        LD DE,(SCFPTR)            ; Restore the address of the two patch bytes.
        LD (HL),E                 ; Store the patch address low byte.
        INC HL                    ; Advance to the high patch-address byte.
        LD (HL),D                 ; Store the patch address high byte.
        INC HL                    ; Advance to the kind byte.
        LD A,(SCFKIND)            ; Store global or local kind.
        LD (HL),A                 ; Publish the kind before the slot number.
        INC HL                    ; Advance to the slot-number byte.
        LD A,(SCFSLOT)            ; Store the compiler-assigned slot number.
        LD (HL),A                 ; Complete the fixup record.
        LD HL,(SCFIXN)            ; Increment the record count after the write.
        INC HL                    ; The next record uses the following four bytes.
        LD (SCFIXN),HL            ; Publish the complete fixup.
        XOR A                     ; A successful record returns with carry clear.
        RET                       ; Return to the code emitter.

SCFIXERR:
        SCF                       ; Branch patch failures are terminal.
        RET                       ; No staged output is published on this path.

; Record the staged operand word of a tail-call wrapper for later rewriting.
SCTSAVE:
        LD (SCTPTR),HL             ; Preserve the operand address during indexing.
        LD A,(SCTTOP)              ; Each record occupies one staged address word.
        CP SCTMAX                  ; Refuse a body that exceeds the patch bound.
        JP NC,SCCAP                ; A partial tail record cannot be emitted safely.
        LD L,A                     ; Widen the record index before doubling it.
        LD H,0
        ADD HL,HL
        LD DE,SCTAILPT             ; Locate the next free tail-candidate record.
        ADD HL,DE
        LD DE,(SCTPTR)             ; Restore the staged operand address.
        LD (HL),E                  ; Store its low byte.
        INC HL
        LD (HL),D                  ; Store its high byte.
        LD L,A                     ; Reuse the candidate index for its side flag.
        LD H,0
        LD DE,SCTAILK
        ADD HL,DE
        LD A,(SCAPMODE)            ; Modes two and three become flags one and two.
        CP 2
        JR C,SCTSAVEG
        DEC A
SCTSAVEG:
        LD (HL),A                  ; Preserve the dispatch path for later rewriting.
        LD A,(SCTTOP)              ; Advance the candidate count after the write.
        INC A
        LD (SCTTOP),A
        XOR A
        RET

; Rewrite the current body's non-final tail candidates as ordinary calls.
SCTFIX:
        LD A,(SCTMARK)             ; The current expression owns records from here.
        LD B,A                     ; B walks the bounded patch-record range.
SCTFIXLP:
        LD A,(SCTTOP)              ; Stop when every candidate in this expression is fixed.
        CP B
        JR Z,SCTFIXDN
        LD L,B                     ; Address the candidate word by its record index.
        LD H,0
        ADD HL,HL
        LD DE,SCTAILPT
        ADD HL,DE
        LD E,(HL)                  ; Recover the staged operand address.
        INC HL
        LD D,(HL)
        EX DE,HL                   ; HL now names the generated CALL operand.
        PUSH HL                    ; Preserve the patch address while reading its flag.
        LD L,B                     ; The flag table uses one byte per candidate.
        LD H,0
        LD DE,SCTAILK
        ADD HL,DE
        LD A,(HL)                  ; A nonzero flag selects the side-stack entry.
        POP HL                     ; Restore the staged operand address.
        OR A
        JR Z,SCTFIXG
        LD DE,PRIM_OP              ; A direct primitive returns normally.
        CP 2
        JR Z,SCTFIXW
        LD DE,INV_OP               ; Keep operator-first evaluation for this call.
        JR SCTFIXW
SCTFIXG:
        LD DE,INV_CALL             ; Ordinary calls preserve the continuation.
SCTFIXW:
        CALL SINKPTCH             ; Route tail-call rewrites through the sink.
        INC B                      ; Advance to the next tail candidate.
        JR SCTFIXLP
SCTFIXDN:
        LD A,B                     ; Discard the records just rewritten.
        LD (SCTTOP),A
        XOR A
        RET

; Return Z when the selected local slot belongs to package-level storage.
SCLOCALQ:
        LD A,(SCFSLOT)             ; Address the owner byte for the selected slot.
        LD L,A
        LD H,0
        LD DE,SCLOCOWN
        ADD HL,DE
        LD A,(HL)
        CP 0FFH
        RET

; Emit a conditional absolute jump and return its patch address in HL.  The
; caller patches the address when the matching branch target is known.
SCJZ:
        LD A,0CAH                 ; JP Z,nn branches when RT_TEST returns Z.
        CALL SINKBYTE               ; Append the conditional-jump opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(SCPC)              ; The following word is the branch patch.
        PUSH HL                   ; Preserve the patch address across zero writes.
        XOR A                     ; Start with an unresolved target word.
        CALL SINKBYTE               ; Append the low placeholder byte.
        JR C,SCJFAIL              ; Leave the patch address off the stack.
        CALL SINKBYTE               ; Append the high placeholder byte.
        JR C,SCJFAIL              ; Leave the patch address off the stack.
        POP HL                    ; Return the branch patch location.
        OR A                      ; Successful emission returns carry clear.
        RET                       ; The caller owns the patch stack.

SCJNZ:
        LD A,0C2H                 ; JP NZ,nn is the OR short-circuit branch.
        CALL SINKBYTE               ; Append the conditional-jump opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(SCPC)              ; The following word is the branch patch.
        PUSH HL                   ; Preserve the patch address across zero writes.
        XOR A                     ; Start with an unresolved target word.
        CALL SINKBYTE               ; Append the low placeholder byte.
        JR C,SCJFAIL              ; Leave the patch address off the stack.
        CALL SINKBYTE               ; Append the high placeholder byte.
        JR C,SCJFAIL              ; Leave the patch address off the stack.
        POP HL                    ; Return the branch patch location.
        OR A                      ; Successful emission returns carry clear.
        RET                       ; The caller owns the patch stack.

; Emit JP nn and return its two-byte patch location in HL.
SCJP:
        LD A,0C3H                 ; Absolute Z80 jump opcode.
        CALL SINKBYTE               ; Append the unconditional-jump opcode.
        RET C                     ; Preserve a staged-output capacity failure.
        LD HL,(SCPC)              ; The following word is the branch patch.
        PUSH HL                   ; Preserve the patch address across zero writes.
        XOR A                     ; Start with an unresolved target word.
        CALL SINKBYTE               ; Append the low placeholder byte.
        JR C,SCJFAIL              ; Leave the patch address off the stack.
        CALL SINKBYTE               ; Append the high placeholder byte.
        JR C,SCJFAIL              ; Leave the patch address off the stack.
        POP HL                    ; Return the branch patch location.
        OR A                      ; Successful emission returns carry clear.
        RET                       ; The caller owns the patch stack.

SCJFAIL:
        POP HL                    ; Remove the saved patch address on failure.
        SCF                       ; Keep the staged-output diagnostic asserted.
        RET

; Append the return instruction used by the runtime entry point.
SCRET:
        LD A,0C9H                 ; RET hands the final value to RT_CALL.
        JP SINKBYTE                 ; Append the single-byte instruction.
