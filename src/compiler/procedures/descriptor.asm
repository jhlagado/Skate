; Compiler descriptor creation, closure prefixes and mutation forms.
; Entry points: SCPREFX, SCMAKE, SCPNEW, SCPFIN and SCSETF.
; Emit a descriptor load, fresh-closure allocation and JP over the body.
; The descriptor pointer is a kind-two fixup filled after slot layout closes.
SCPREFX:
        CALL SCMAKE                ; Build the closure value before the body.
        RET C                      ; Preserve staged-output or fixup exhaustion.
        CALL SCJP                  ; Jump over the body during closure creation.
        LD (SCSKIP),HL             ; Save the jump-over patch for SCPFIN.
        RET                        ; SCPC now points at the procedure body.

; Emit the descriptor load and fresh closure allocation used by definitions and
; named let.  The caller decides where to store the value and how to skip code.
SCMAKE:
        LD A,21H                   ; LD HL,nn loads the immutable descriptor address.
        CALL SINKBYTE                ; Append the load opcode.
        RET C                      ; Preserve staged-output exhaustion.
        LD A,(SCTMPPR)             ; SCPFIN patches this placeholder when the
        LD L,A                     ; descriptor is emitted; until then the
        LD H,0                     ; descriptor's address entry holds the site.
        ADD HL,HL
        LD DE,SCPADDR
        ADD HL,DE
        LD DE,(SCPC)               ; The following word is the descriptor pointer.
        LD (HL),E
        INC HL
        LD (HL),D
        XOR A                      ; The descriptor address is unknown for now.
        CALL SINKBYTE                ; Append its low placeholder byte.
        RET C                      ; Preserve staged-output exhaustion.
        CALL SINKBYTE                ; Append its high placeholder byte.
        RET C                      ; Preserve staged-output exhaustion.
        LD HL,HEAP_LAM              ; Runtime allocates a fresh closure object.
        CALL SCCALL                ; The returned value carries tag two.
        RET C                      ; Preserve staged-output exhaustion.
        RET                        ; The generated value is in the runtime registers.

; Reserve and clear one procedure metadata record.
; A record exists only while its procedure is open.  SCPFIN emits the
; finished descriptor into the image and releases the record, so the count
; of procedures is bounded by SCPMAXN and their nesting by SCPDMAX.
SCPNEW:
        LD A,(SCPDEPTH)            ; Open records form a stack by nesting depth.
        CP SCPDMAX
        JP NC,SCCAP                ; Reject nesting beyond the record stack.
        LD A,(SCPCOUNT)            ; Indices name procedures in fixups.
        CP SCPMAXN
        JP NC,SCCAP                ; Reject another procedure before writing memory.
        LD B,A                     ; Return the old count as the descriptor index.
        INC A                      ; Publish the additional descriptor.
        LD (SCPCOUNT),A            ; The index is stable for all later fixups.
        LD A,(SCPDEPTH)            ; Push the index onto the open-record stack.
        LD E,A
        LD D,0
        LD HL,SCPOPEN
        ADD HL,DE
        LD (HL),B
        INC A
        LD (SCPDEPTH),A
        LD A,B                     ; Keep the descriptor index for the caller.
        LD (SCTMPPR),A             ; SCPREC uses this state to find its record.
        CALL SCPREC                ; HL points at the twelve-byte metadata record.
        LD B,SCPRSZ                ; Clear body, arity, formals and ownership masks.
        XOR A                      ; A zero record has no body or formal slots.
SCPNEWLP:
        LD (HL),A                  ; Clear one metadata byte.
        INC HL                     ; Advance to the next field.
        DJNZ SCPNEWLP              ; Clear the complete fixed-size record.
        XOR A                      ; A new descriptor starts with fixed-arity policy.
        LD (SCRESTF),A
        LD (SCRESTS),A
        LD A,(SCTMPPR)             ; Return the descriptor index to SCLAMBF.
        OR A                       ; Clear carry without changing the index byte.
        RET                        ; The caller opens the new local scope.

; HL = metadata record for SCTMPPR, which must be an open procedure.  BC is
; preserved.  A closed index selects a scratch record so a stray lookup can
; never write over an open procedure's metadata.
SCPREC:
        PUSH BC
        LD A,(SCTMPPR)
        LD C,A                     ; C is the index being searched for.
        LD A,(SCPDEPTH)
        LD B,A                     ; B counts the open records still to test.
SCPRFIND:
        LD A,B
        OR A
        JR Z,SCPRSCR               ; No open record carries this index.
        DEC B                      ; Search from the innermost record outward.
        LD L,B
        LD H,0
        LD DE,SCPOPEN
        ADD HL,DE
        LD A,(HL)
        CP C
        JR NZ,SCPRFIND
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
        LD DE,SCPRECS              ; Add the open-record base address.
        ADD HL,DE                  ; Return the record address in HL.
        LD A,(SCTMPPR)             ; Callers may rely on A holding the index.
        RET                        ; The caller selects the field offset.
SCPRSCR:
        POP BC
        LD HL,SCPSCR
        LD A,(SCTMPPR)
        RET

; Save the formal slot number in the current descriptor and advance its arity.
SCPARAM:
        PUSH AF                    ; Preserve the slot number returned by SCNSLOT.
        CALL SCPREC                ; Locate the current descriptor metadata.
        INC HL                     ; Skip the body address low byte.
        INC HL                     ; Skip the body address high byte.
        LD A,(HL)                  ; Read the current formal count.
        CP 4                       ; Four fixed arguments keep descriptors compact.
        JR NC,SCPERR               ; Reject a fifth formal before table overflow.
        LD E,A                     ; E is the formal index within the record.
        INC A                      ; Publish the new arity.
        LD (HL),A                  ; The runtime uses this count during dispatch.
        LD A,E                     ; Reconstruct the slot field offset four plus index.
        INC HL                     ; Move to the capture mask at offset three.
        INC HL                     ; Move to the first formal slot at offset four.
        LD B,A                     ; The old arity is the number of slots to skip.
        LD A,B                     ; Keep the loop count in the DJNZ register.
        OR A                       ; Zero formals select the first slot directly.
        JR Z,SCPARMAT              ; Avoid a wrapped DJNZ count for arity zero.
SCPARMSK:
        INC HL                     ; Skip the low byte of one recorded formal.
        INC HL                     ; Skip its reserved high byte as well.
        DJNZ SCPARMSK              ; Stop at the slot for the new formal.
SCPARMAT:
        POP AF                     ; Recover the compiler-local slot number.
        LD (HL),A                  ; Runtime publication resolves its address later.
        INC HL                     ; The descriptor keeps a fixed two-byte slot field.
        XOR A                      ; The current compiler slot range fits in one byte.
        LD (HL),A                  ; Keep the high byte reserved and deterministic.
        OR A                       ; Carry clear reports a complete formal record.
        RET                        ; The lambda parser reads the next name.
SCPERR:
        POP AF                     ; Keep the compiler stack balanced on rejection.
        SCF                        ; The procedure arity is a checked capacity.
        RET                        ; The lambda error path restores its scope.

; Save the body address, emit the finished descriptor after the body, release
; its record and patch the jump over both.  Byte three, the shared slot
; extent, is only known at the end of the program; SCPDESC patches it.
SCPFIN:
        LD HL,(SCPBODY)            ; Recover the staged body start recorded above.
        CALL SCABS                 ; Convert the body pointer to a COM address.
        LD (SCPBODY),HL            ; Keep it for descriptor serialization.
        CALL SCPREC                ; Locate the descriptor metadata again.
        LD DE,(SCPBODY)            ; Write the generated body address at offset zero.
        LD (HL),E                  ; Store the low body byte.
        INC HL                     ; Advance to the high body byte.
        LD (HL),D                  ; Complete the body address field.
        INC HL
        LD C,(HL)                  ; C is the published arity byte.
        INC HL
        XOR A
        LD (HL),A                  ; Byte three is patched once the extent is known.
        LD A,(SCTMPPR)             ; Record where this descriptor is emitted.
        LD L,A
        LD H,0
        LD DE,SCPARITY
        ADD HL,DE
        LD (HL),C                  ; The final patch rewrites arity with the extent.
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCPADDR
        ADD HL,DE
        LD E,(HL)                  ; DE is the closure-creation placeholder.
        INC HL
        LD D,(HL)
        PUSH DE
        LD DE,(SCPC)               ; The descriptor starts at the current cursor.
        LD (HL),D                  ; Keep its address for the final extent patch.
        DEC HL
        LD (HL),E
        POP HL
        CALL SINKPTCH              ; Point the closure creation at the descriptor.
        RET C
        CALL SCPREC                ; Body, arity, extent and formal fields.
        LD A,SCOWNOF
        CALL SCPFEMB
        RET C
        CALL SCPREC                ; The masks are only as wide as needed.
        CALL SCPFWID
        LD (SCPWID),A
        CALL SINKBYTE
        RET C
        CALL SCPREC
        LD DE,SCOWNOF
        ADD HL,DE
        LD A,(SCPWID)
        CALL SCPFEMB               ; The owned mask.
        RET C
        CALL SCPREC
        LD DE,SCCAPOF
        ADD HL,DE
        LD A,(SCPWID)
        CALL SCPFEMB               ; The capture mask.
        RET C
        LD A,(SCPDEPTH)            ; Release the innermost open record.
        DEC A
        LD (SCPDEPTH),A
        LD HL,(SCPC)               ; The skip target follows the descriptor.
        CALL SCABS                 ; Convert the target to a COM address.
        EX DE,HL                   ; SCPATCH takes the patch address in HL.
        LD HL,(SCSKIP)             ; Recover the jump-over patch location.
        JP SINKPTCH                 ; Patch the closure creation jump.

; Emit A bytes from HL.  Carry reports staged-output exhaustion.
SCPFEMB:
        OR A
        RET Z
        LD B,A
.BYTE:
        LD A,(HL)
        PUSH HL
        CALL SINKBYTE              ; SINKBYTE preserves BC.
        POP HL
        RET C
        INC HL
        DJNZ .BYTE
        OR A
        RET

; HL = metadata record: return in A the number of mask bytes up to the last
; nonzero byte of either the owned or the capture mask.
SCPFWID:
        LD DE,SCOWNOF+SCMASKB-1    ; The last owned-mask byte.
        ADD HL,DE
        LD B,SCMASKB
.SCAN:
        LD A,(HL)
        PUSH HL
        LD DE,SCCAPOF-SCOWNOF
        ADD HL,DE
        OR (HL)                    ; The matching capture-mask byte.
        POP HL
        JR NZ,.FOUND
        DEC HL
        DJNZ .SCAN
.FOUND:
        LD A,B
        RET

SCPWID: DB 0                       ; Mask width of the descriptor being emitted.

; Compile set!, preserving the selected slot while the value expression runs.
SCSETF:
        CALL SCNEXT                ; Read the target binding name.
        RET C                      ; Preserve source failure.
        CP 5                       ; A mutation target must be an identifier.
        JP NZ,SCDESTSY              ; Reject a literal or nested list target.
        LD (SCID),HL               ; Preserve the target identity across lookup.
        CALL SCDEST                 ; Select the local or global storage slot.
        RET C                      ; An unknown or full binding table is terminal.
        LD A,(SCSLOT)              ; Save the selected slot while compiling the value.
        PUSH AF                    ; A nested set! must not replace this slot.
        LD A,(SCDESTK)              ; Preserve the local/global destination kind too.
        PUSH AF                    ; The value expression may recurse through set!.
        XOR A                      ; The new value is evaluated before the store.
        LD (SCTCTX),A              ; A mutation target never receives tail position.
        CALL SCEXPR                ; Compile the new value.
        JR C,SCSETERR              ; Balance the destination frame on failure.
        POP AF                     ; Recover the selected destination kind.
        LD (SCDESTK),A             ; Restore local or global storage selection.
        POP AF                     ; Recover the selected destination slot.
        LD (SCSLOT),A              ; Restore the slot after nested compilation.
        LD L,A                     ; SCSTORE takes the slot number in L.
        LD A,1
        LD (SCMUT),A           ; Select a checked mutation store.
        LD A,(SCDESTK)             ; Recover local or global destination kind.
        CALL SCSTORE               ; Emit the checked mutation update.
        JR C,SCMUTERR          ; Balance the mode before reporting failure.
        XOR A
        LD (SCMUT),A           ; Definitions resume the initializing path.
        JP SCEXPECT                ; Require exactly one closing parenthesis.
SCMUTERR:
        XOR A
        LD (SCMUT),A           ; The compiler is terminating after this error.
        SCF
        RET C                      ; Preserve output or fixup exhaustion.
SCSETERR:
        POP AF                     ; Discard the saved destination kind.
        POP AF                     ; Discard the saved destination slot.
        SCF                       ; Preserve the nested expression diagnostic.
        RET

; Resolve a mutation target without emitting a load.  SCDESTK records its kind.
SCDEST:
        CALL SCLOCF                ; Prefer an active local binding.
        JR C,SCDESTL               ; Carry identifies the local path.
        CALL SCGGET                ; Global references allocate their slot here.
        RET C                      ; Preserve the global-capacity diagnostic.
        LD (SCSLOT),A              ; Store the selected global slot.
        XOR A                      ; Kind zero denotes a package-global slot.
        LD (SCDESTK),A             ; Remember it for the later SCSTORE.
        OR A                       ; Clear carry after a complete lookup.
        RET                        ; Return with the slot in SCSLOT.
SCDESTL:
        LD (SCSLOT),A              ; Store the selected local slot.
        LD A,1                     ; Kind one denotes a local slot.
        LD (SCDESTK),A             ; Remember it for the later SCSTORE.
        OR A                       ; Clear carry without changing the slot byte.
        RET                        ; Return to SCSETF before its value expression.
SCDESTSY:
        LD HL,SCDESTT
        LD (SCERRPTR),HL
        JP SCSYN
