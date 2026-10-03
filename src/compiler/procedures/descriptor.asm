; Compiler descriptor creation, closure prefixes and mutation forms.
; Entry points: LAM_HEAD, LAM_MAKE, PROC_NEW, PROC_END and BIND_SET.
; Emit a descriptor load, fresh-closure allocation and JP over the body.
; The descriptor pointer is a kind-two fixup filled after slot layout closes.
LAM_HEAD:
        CALL LAM_MAKE              ; Build the closure value before the body.
        RET C                      ; Preserve staged-output or fixup exhaustion.
        CALL EM_JP                 ; Jump over the body during closure creation.
        LD (ST_SKIP),HL            ; Save the jump-over patch for PROC_END.
        RET                        ; ST_PC now points at the procedure body.

; Emit the descriptor load and fresh closure allocation used by definitions and
; named let.  The caller decides where to store the value and how to skip code.
LAM_MAKE:
        LD A,21H                   ; LD HL,nn loads the immutable descriptor address.
        CALL SINK_PUT                ; Append the load opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(ST_DESC)             ; PROC_END patches this placeholder when the
        LD L,A                     ; descriptor is emitted; until then the
        LD H,0                     ; descriptor's address entry holds the site.
        ADD HL,HL
        LD DE,W_PDESC
        ADD HL,DE
        LD DE,(ST_PC)              ; The following word is the descriptor pointer.
        LD (HL),E
        INC HL
        LD (HL),D
        XOR A                      ; The descriptor address is unknown for now.
        CALL SINK_PUT                ; Append its low placeholder byte.
        RET C                      ; Preserve staged-output exhaustion.
        CALL SINK_PUT                ; Append its high placeholder byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,HEAP_LAM              ; Runtime allocates a fresh closure object.
        CALL EM_CALL               ; The returned value carries tag two.
        RET C                      ; Preserve staged-output exhaustion.
        RET                        ; The generated value is in the runtime registers.

; Reserve and clear one procedure metadata record.
; A record exists only while its procedure is open.  PROC_END emits the
; finished descriptor into the image and releases the record, so the count
; of procedures is bounded by W_PROC_N and their nesting by W_OPEN_N.
PROC_NEW:
        LD A,(ST_PNEST)            ; Open records form a stack by nesting depth.
        CP W_OPEN_N
        JP NC,ERR_CAP              ; Reject nesting beyond the record stack.
        LD A,(ST_PROCS)            ; Indices name procedures in fixups.
        CP W_PROC_N
        JP NC,ERR_CAP              ; Reject another procedure before writing memory.
        LD B,A                     ; Return the old count as the descriptor index.
        INC A                      ; Publish the additional descriptor.
        LD (ST_PROCS),A            ; The index is stable for all later fixups.
        LD A,(ST_PNEST)            ; Push the index onto the open-record stack.
        LD E,A
        LD D,0
        LD HL,W_POPEN
        ADD HL,DE
        LD (HL),B
        INC A
        LD (ST_PNEST),A
        LD A,B                     ; Keep the descriptor index for the caller.
        LD (ST_DESC),A             ; PROC_REC uses this state to find its record.
        CALL PROC_REC              ; HL points at the twelve-byte metadata record.
        LD B,W_PRECSZ              ; Clear body, arity, formals and ownership masks.
        XOR A                      ; A zero record has no body or formal slots.
.CLEAR:
        LD (HL),A                  ; Clear one metadata byte.
        INC HL                     ; Advance to the next field.
        DJNZ .CLEAR                ; Clear the complete fixed-size record.
        XOR A                      ; A new descriptor starts with fixed-arity policy.
        LD (ST_REST),A
        LD (ST_RLIST),A
        LD A,(ST_DESC)             ; Return the descriptor index to LAM_FORM.
        OR A                       ; Clear carry without changing the index byte.
        RET                        ; The caller opens the new local scope.

; HL = metadata record for ST_DESC, which must be an open procedure.  BC is
; preserved.  A closed index selects a scratch record so a stray lookup can
; never write over an open procedure's metadata.
PROC_REC:
        PUSH BC
        LD A,(ST_DESC)
        LD C,A                     ; C is the index being searched for.
        LD A,(ST_PNEST)
        LD B,A                     ; B counts the open records still to test.
.FIND:
        LD A,B
        OR A
        JR Z,.SCRATCH              ; No open record carries this index.
        DEC B                      ; Search from the innermost record outward.
        LD L,B
        LD H,0
        LD DE,W_POPEN
        ADD HL,DE
        LD A,(HL)
        CP C
        JR NZ,.FIND
        LD L,B                     ; B is the record's position in the stack.
        POP BC
        LD H,0                     ; Each record carries two 128-bit masks.
        LD D,H                     ; Keep the original index for the final add.
        LD E,L
        ADD HL,HL                  ; Two times the index.
        ADD HL,HL                  ; Four times the index.
        PUSH HL                    ; Keep four times the index.
        ADD HL,HL                  ; Eight times the index.
        PUSH HL                    ; Keep eight times the index.
        ADD HL,HL                  ; Sixteen times the index.
        ADD HL,HL                  ; Thirty-two times the index.
        POP DE                     ; Recover eight times the index.
        ADD HL,DE                  ; Forty times the index.
        POP DE                     ; Recover four times the index.
        ADD HL,DE                  ; Complete the forty-four-byte offset.
        LD DE,W_PRECS              ; Add the open-record base address.
        ADD HL,DE                  ; Return the record address in HL.
        LD A,(ST_DESC)             ; Callers may rely on A holding the index.
        RET                        ; The caller selects the field offset.
.SCRATCH:
        POP BC
        LD HL,W_PTMP
        LD A,(ST_DESC)
        RET

; Save the formal slot number in the current descriptor and advance its arity.
PROC_ARG:
        PUSH AF                    ; Preserve the slot number returned by BIND_NEW.
        CALL PROC_REC              ; Locate the current descriptor metadata.
        INC HL                     ; Skip the body address low byte.
        INC HL                     ; Skip the body address high byte.
        LD A,(HL)                  ; Read the current formal count.
        CP 4                       ; Four fixed arguments keep descriptors compact.
        JR NC,.FULL                ; Reject a fifth formal before table overflow.
        LD E,A                     ; E is the formal index within the record.
        INC A                      ; Publish the new arity.
        LD (HL),A                  ; The runtime uses this count during dispatch.
        LD A,E                     ; Reconstruct the slot field offset four plus index.
        INC HL                     ; Move to the capture mask at offset three.
        INC HL                     ; Move to the first formal slot at offset four.
        LD B,A                     ; The old arity is the number of slots to skip.
        LD A,B                     ; Keep the loop count in the DJNZ register.
        OR A                       ; Zero formals select the first slot directly.
        JR Z,.STORE                ; Avoid a wrapped DJNZ count for arity zero.
.SKIP:
        INC HL                     ; Skip the low byte of one recorded formal.
        INC HL                     ; Skip its reserved high byte as well.
        DJNZ .SKIP                 ; Stop at the slot for the new formal.
.STORE:
        POP AF                     ; Recover the compiler-local slot number.
        LD (HL),A                  ; Runtime publication resolves its address later.
        INC HL                     ; The descriptor keeps a fixed two-byte slot field.
        XOR A                      ; The current compiler slot range fits in one byte.
        LD (HL),A                  ; Keep the high byte reserved and deterministic.
        OR A                       ; Carry clear reports a complete formal record.
        RET                        ; The lambda parser reads the next name.
.FULL:
        POP AF                     ; Keep the compiler stack balanced on rejection.
        SCF                        ; The procedure arity is a checked capacity.
        RET                        ; The lambda error path restores its scope.

; Save the body address, emit the finished descriptor after the body, release
; its record and patch the jump over both.  Byte three, the shared slot
; extent, is only known at the end of the program; PUB_DESC patches it.
PROC_END:
        LD HL,(ST_PBODY)           ; Recover the staged body start recorded above.
        CALL BR_ABS                ; Convert the body pointer to a COM address.
        LD (ST_PBODY),HL           ; Keep it for descriptor serialization.
        CALL PROC_REC              ; Locate the descriptor metadata again.
        LD DE,(ST_PBODY)           ; Write the generated body address at offset zero.
        LD (HL),E                  ; Store the low body byte.
        INC HL                     ; Advance to the high body byte.
        LD (HL),D                  ; Complete the body address field.
        INC HL
        LD C,(HL)                  ; C is the published arity byte.
        INC HL
        XOR A
        LD (HL),A                  ; Byte three is patched once the extent is known.
        LD A,(ST_DESC)             ; Record where this descriptor is emitted.
        LD L,A
        LD H,0
        LD DE,W_PARITY
        ADD HL,DE
        LD (HL),C                  ; The final patch rewrites arity with the extent.
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,W_PDESC
        ADD HL,DE
        LD E,(HL)                  ; DE is the closure-creation placeholder.
        INC HL
        LD D,(HL)
        PUSH DE
        LD DE,(ST_PC)              ; The descriptor starts at the current cursor.
        LD (HL),D                  ; Keep its address for the final extent patch.
        DEC HL
        LD (HL),E
        POP HL
        CALL SINK_FIX              ; Point the closure creation at the descriptor.
        RET C
        CALL PROC_REC              ; Body, arity, extent and formal fields.
        LD A,W_OWNOFF
        CALL .EMIT
        RET C
        CALL PROC_REC              ; The masks are only as wide as needed.
        CALL .MEASURE
        LD (.WIDTH),A
        CALL SINK_PUT
        RET C
        CALL PROC_REC
        LD DE,W_OWNOFF
        ADD HL,DE
        LD A,(.WIDTH)
        CALL .EMIT                 ; The owned mask.
        RET C
        CALL PROC_REC
        LD DE,W_CAPOFF
        ADD HL,DE
        LD A,(.WIDTH)
        CALL .EMIT                 ; The capture mask.
        RET C
        LD A,(ST_PNEST)            ; Release the innermost open record.
        DEC A
        LD (ST_PNEST),A
        LD HL,(ST_PC)              ; The skip target follows the descriptor.
        CALL BR_ABS                ; Convert the target to a COM address.
        EX DE,HL                   ; .ALIAS takes the patch address in HL.
        LD HL,(ST_SKIP)            ; Recover the jump-over patch location.
        JP SINK_FIX                 ; Patch the closure creation jump.

; Emit A bytes from HL.  Carry reports staged-output exhaustion.
.EMIT:
        OR A
        RET Z
        LD B,A
.BYTE:
        LD A,(HL)
        PUSH HL
        CALL SINK_PUT              ; SINK_PUT preserves BC.
        POP HL
        RET C
        INC HL
        DJNZ .BYTE
        OR A
        RET

; HL = metadata record: return in A the number of mask bytes up to the last
; nonzero byte of either the owned or the capture mask.
.MEASURE:
        LD DE,W_OWNOFF+W_MASKSZ-1  ; The last owned-mask byte.
        ADD HL,DE
        LD B,W_MASKSZ
.SCAN:
        LD A,(HL)
        PUSH HL
        LD DE,W_CAPOFF-W_OWNOFF
        ADD HL,DE
        OR (HL)                    ; The matching capture-mask byte.
        POP HL
        JR NZ,.FOUND
        DEC HL
        DJNZ .SCAN
.FOUND:
        LD A,B
        RET

.WIDTH: DB 0                       ; Mask width of the descriptor being emitted.

; Compile set!, preserving the selected slot while the value expression runs.
BIND_SET:
        CALL REC_NEXT              ; Read the target binding name.
        RET C                      ; Preserve source failure.
        CP 5                       ; A mutation target must be an identifier.
        JP NZ,.BAD_NAME             ; Reject a literal or nested list target.
        LD (ST_SYMID),HL           ; Preserve the target identity across lookup.
        CALL .TARGET                ; Select the local or global storage slot.
        RET C                      ; An unknown or full binding table is terminal.
        LD A,(ST_SLOT)             ; Save the selected slot while compiling the value.
        PUSH AF                    ; A nested set! must not replace this slot.
        LD A,(ST_DKIND)             ; Preserve the local/global destination kind too.
        PUSH AF                    ; The value expression may recurse through set!.
        XOR A                      ; The new value is evaluated before the store.
        LD (ST_TAIL),A             ; A mutation target never receives tail position.
        CALL CMD_NEXT              ; Compile the new value.
        JR C,.FAIL                 ; Balance the destination frame on failure.
        POP AF                     ; Recover the selected destination kind.
        LD (ST_DKIND),A            ; Restore local or global storage selection.
        POP AF                     ; Recover the selected destination slot.
        LD (ST_SLOT),A             ; Restore the slot after nested compilation.
        LD L,A                     ; EM_STORE takes the slot number in L.
        LD A,1
        LD (ST_CHECK),A        ; Select a checked mutation store.
        LD A,(ST_DKIND)            ; Recover local or global destination kind.
        CALL EM_STORE              ; Emit the checked mutation update.
        JR C,.MUT_FAIL         ; Balance the mode before reporting failure.
        XOR A
        LD (ST_CHECK),A        ; Definitions resume the initializing path.
        JP CMD_END                 ; Require exactly one closing parenthesis.
.MUT_FAIL:
        XOR A
        LD (ST_CHECK),A        ; The compiler is terminating after this error.
        SCF
        RET C                      ; Preserve output or fixup exhaustion.
.FAIL:
        POP AF                     ; Discard the saved destination kind.
        POP AF                     ; Discard the saved destination slot.
        SCF                       ; Preserve the nested expression diagnostic.
        RET

; Resolve a mutation target without emitting a load.  ST_DKIND records its kind.
.TARGET:
        CALL BIND_HAS              ; Prefer an active local binding.
        JR C,.LOCAL                ; Carry identifies the local path.
        CALL GLB_GET               ; Global references allocate their slot here.
        RET C                      ; Preserve the global-capacity diagnostic.
        LD (ST_SLOT),A             ; Store the selected global slot.
        XOR A                      ; Kind zero denotes a package-global slot.
        LD (ST_DKIND),A            ; Remember it for the later EM_STORE.
        OR A                       ; Clear carry after a complete lookup.
        RET                        ; Return with the slot in ST_SLOT.
.LOCAL:
        LD (ST_SLOT),A             ; Store the selected local slot.
        LD A,1                     ; Kind one denotes a local slot.
        LD (ST_DKIND),A            ; Remember it for the later EM_STORE.
        OR A                       ; Clear carry without changing the slot byte.
        RET                        ; Return to BIND_SET before its value expression.
.BAD_NAME:
        LD HL,M_DEST
        LD (ST_ERROR),HL
        JP ERR_BAD
