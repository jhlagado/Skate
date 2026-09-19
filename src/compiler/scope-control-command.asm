;=============================================================================
;  Scope and control compiler command
;=============================================================================
;
;  This compiler reads a package once, resolves global and local names into
;  bounded slot records, and emits native integer code into a staged image.
;  Supported forms in this increment are integer values, variable references,
;  define, begin, if, let, let* and the two-operand arithmetic operators.
;  Calls, closures, pairs and strings remain later language work.
;=============================================================================

; The generated image and compiler tables occupy disjoint high TPA regions.
SCSTAGE EQU 06000H               ; Object staging, including the image payload.
SCIMG   EQU SCSTAGE+79           ; NOBJ image payload begins after its header.
SCCODE  EQU SCIMG+SRTLEN         ; Generated program follows the runtime image.
SCEND   EQU 07B80H               ; Keep the bounded staged image below the gap.
SCGENEND EQU SCEND-32             ; Leave room for the fixed NOBJ tail and CRC.

SCGKEYS  EQU 09000H              ; Two-byte interner IDs for package globals.
SCGSLOTS EQU 09200H              ; One-byte slot number for each global ID.
SCLOCIDS EQU 09300H              ; Two-byte IDs for active local bindings.
SCLOCSLT EQU 09400H              ; Active local binding slot numbers.
SCBINDID EQU 09480H              ; Two-byte IDs for pending let bindings.
SCBINDSL EQU 09580H              ; Pending let binding slot numbers.
SCFIXTAB EQU 09600H              ; Four-byte address/kind/slot fixup records.
SCNAMEDS EQU 09C00H              ; Symbol descriptor table for the reader.
SCNAMEPL EQU 0A000H              ; 5,120-byte symbol spelling pool.
SCSTRDS  EQU 0B400H              ; String descriptor table required by RINIT.
SCSTRPL  EQU 0B500H              ; Small string pool; strings are rejected here.
SCBRANCH EQU 0B700H              ; Generic short-circuit branch patch stack.
SCIFALSE EQU 0B800H              ; False-branch patch words for nested if forms.
SCIFEND  EQU 0B880H              ; End-branch patch words for nested if forms.
SCWEND   EQU 0B900H              ; End of all fixed high-memory compiler tables.

; Compiler entry and terminal paths.
SCMAIN:
        LD HL,(6)                ; CP/M reports the transient-memory ceiling.
        LD DE,0E000H              ; Reserve the upper 512 bytes for the stack.
        OR A                      ; Clear carry before the ceiling comparison.
        SBC HL,DE                 ; Check the qualified TPA has the required guard.
        JP C,SCMEM                ; Refuse an installation with too little memory.
        LD SP,0E000H              ; Parser and emitter calls share this stack.
        CALL SCSETUP              ; Clear tables and copy the checked runtime image.
        CALL SCPACK               ; Read the source package and emit native code.
        JP C,SCFAIL               ; No output is opened until parsing succeeds.
        CALL SCFIN                ; Resolve slots, append data and build the object.
        JP C,SCFAIL               ; Reject an image that crosses a measured bound.
        CALL SCOUT                ; Publish checked NOBJ and COM files.
        JP C,SCFAIL               ; Report a transport or publication failure.
        LD DE,SCOKTXT             ; Successful compilation message.
        JP SCPRINT                ; Print it and return to CP/M.

SCFAIL:
        CALL CTCLOSER              ; Close a source left open by a parse failure.
        LD DE,SCERRTXT             ; All rejected forms remain unpublished.
        JP SCPRINT                ; Print the diagnostic and warm-start CP/M.
SCMEM:
        LD DE,SCMEMTXT             ; Memory guard failure is distinct to the user.
        JP SCPRINT                ; Print the diagnostic and return to CP/M.

SCPRINT:
        LD C,9                     ; CP/M function 9 prints a dollar-terminated string.
        CALL 5                     ; Use the platform BDOS vector.
        JP 0                       ; Warm start after either result.

; Initialise reader contexts, compiler tables and the staged runtime image.
SCSETUP:
        LD A,0FFH                 ; Unknown global names carry the FF marker.
        XOR A                     ; Reset global and local allocation cursors.
        LD (SCGCOUNT),A           ; Low byte of the 16-bit global count.
        LD (SCGCOUNT+1),A         ; High byte remains zero until all 256 slots exist.
        LD (SCLOCTOP),A           ; No local binding is active at package entry.
        LD (SCLNEXT),A            ; Local slot zero is the first available slot.
        LD (SCLOCMAX),A           ; No local data extent has been observed yet.
        LD (SCFORMN),A            ; No package-level result exists at setup.
        LD (SCFORMN+1),A          ; The form count is a complete little-endian word.
        LD (SCFIXN),A             ; No address fixups have been recorded.
        LD (SCFIXN+1),A           ; The count is wide enough for the global target.
        LD (SCBRTOP),A            ; No short-circuit branch is pending.
        LD (SCIFTOP),A            ; No if form is being compiled.
        LD (SCBNDTOP),A          ; No pending let binding is retained.
        LD HL,SRTIMAGE            ; Source address of the checked runtime bytes.
        LD DE,SCIMG               ; Destination address in the staged object.
        LD BC,SRTLEN              ; Copy exactly the serialized runtime image.
        LDIR                      ; The output program will execute at $0100.
        LD HL,SCCODE              ; Generated code starts after the runtime image.
        LD (SCPC),HL              ; Publish the first code-generation cursor.
        LD IX,SCNCTX              ; Select the symbol interner context.
        CALL IINIT                ; Validate and clear its descriptor counters.
        RET C                     ; A bad high-memory table is a setup failure.
        LD IX,SCSCTX              ; Select the string context required by RINIT.
        CALL IINIT                ; The current language rejects string events.
        RET C                     ; Preserve the reader's ordinary setup diagnostic.
        RET                       ; Return with all compiler state initialised.

; Open the source FCB, attach the production reader and consume top-level forms.
SCPACK:
        LD HL,005CH               ; CCP places the command-tail FCB here.
        CALL CSOPEN               ; Install the source stream callback.
        JR NC,SCOPENOK            ; Continue only when the source opened cleanly.
        SCF                       ; Preserve the source-I/O failure for SCFAIL.
        RET                       ; No generated output exists yet.
SCOPENOK:
        LD HL,CSBYTE               ; Reader callback returns one source byte.
        LD DE,SCNCTX               ; Reader owns the symbol context.
        LD BC,SCSCTX               ; Reader owns the string context.
        CALL RINIT                 ; Reset lexer and structural reader state.
        RET C                      ; Treat a reader setup fault as a parse failure.
SCTOPLP:
        CALL RNEXT                 ; Read the next complete top-level event.
        RET C                      ; The reader latches its source diagnostic.
        OR A                       ; Event zero is the only valid package terminator.
        JR Z,SCENDPK               ; The caller closes the source before output.
        LD B,A                     ; Preserve the event kind across the top flag.
        LD A,1                     ; Definitions are legal only at package level.
        LD (SCALLOW),A             ; SCFORM consumes and clears this permission.
        LD A,B                     ; Recover the top-level event kind.
        CALL SCEXPE                ; Compile the event and leave its value in A/HL.
        JP NC,SCEVGOOD              ; Continue after a complete top-level form.
        RET                        ; Stop at the first syntax or capacity error.
SCEVGOOD:
        LD HL,(SCFORMN)            ; Count successful top-level forms as a word.
        INC HL                     ; An empty package has no value to return.
        LD (SCFORMN),HL            ; Do not wrap after 256 definitions.
        JR SCTOPLP               ; Continue until the reader returns EOF.

; Finish a nonempty package with the return instruction used by SRTCALL.
SCENDPK:
        LD HL,(SCFORMN)            ; Reject an empty source before publication.
        LD A,H                     ; Test both bytes of the form count.
        OR L                       ; A zero count has no result for SRTPRINT.
        JP Z,SCSYN                 ; Report the same syntax error as other empties.
        JP SCRET                   ; Append RET and return to the command driver.

; Parse one event already returned in A; literal payloads remain in RTAG:HL.
SCEXPE:
        CP 7                       ; Numeric events use the scalar payload contract.
        JR Z,SCNUM                 ; Emit an exact integer literal.
        CP 5                       ; Symbol events carry an interned reference.
        JR Z,SCREF                 ; Resolve a local or package-global slot.
        CP 1                       ; An open parenthesis introduces a form.
        JR Z,SCFORM                ; Read the form's operator symbol and operands.
        JP SCSYN                   ; Strings, quote prefixes and bare punctuation fail.

; Read one fresh expression event from the reader.
SCEXPR:
        CALL RNEXT                 ; The caller has not consumed this expression.
        RET C                      ; Preserve the reader's latched error code.
        JP SCEXPE                  ; Dispatch the returned event.

SCNUM:
        LD A,(RTAG)                ; Reader tag zero is the boolean scalar form.
        OR A                       ; A zero tag selects the boolean emitter.
        JR Z,SCBOOLV               ; Preserve #f/#t as a scalar runtime value.
        CP 3                       ; Tag 3 is the exact signed-integer form.
        JP NZ,SCUNSUP              ; Other scalar tags are outside this increment.
        JP SCLIT                   ; Emit the integer payload and its tag.
SCBOOLV:
        LD A,L                     ; Boolean payloads are zero or one in the low byte.
        JP SCBOOL                  ; Emit the checked boolean representation.

; Resolve a symbol reference, preferring the innermost active local binding.
SCREF:
        LD (SCID),HL               ; Save the full interner ID across table searches.
        CALL SCLOCF                ; Search active locals from the current scope.
        JR C,SCRLOCAL              ; A local slot shadows every global slot.
        CALL SCGGET                ; Allocate a global slot on the first reference.
        RET C                      ; The 256-slot capacity is a compile diagnostic.
        LD L,A                     ; The emitter takes the slot number in L.
        XOR A                      ; Kind zero denotes a package-global slot.
        JP SCLOAD                  ; Emit the checked runtime load and its fixup.
SCRLOCAL:
        LD L,A                     ; SCLOCF returns the matching local slot number.
        LD A,1                     ; Kind one denotes a local slot.
        JP SCLOAD                  ; Emit the checked runtime load and its fixup.

; Read the operator symbol following an opening parenthesis and dispatch it.
SCFORM:
        LD A,(SCALLOW)             ; Save whether define is legal at this level.
        LD (SCTOP),A               ; Nested forms clear the permission below.
        XOR A                      ; No nested definition may be accepted.
        LD (SCALLOW),A             ; Only the package loop grants this permission.
        CALL RNEXT                 ; Every supported form begins with a symbol.
        RET C                      ; Propagate a reader source failure.
        CP 5                       ; Event kind five is an interned symbol.
        JP NZ,SCSYN                ; Lists and scalar literals cannot be operators.
        LD DE,SCDEF                ; Compare the spelling with the define keyword.
        CALL SCMATCH               ; The lexer buffer remains valid until RNEXT.
        JR Z,SCDEFINE              ; Definitions use the saved package-level flag.
        LD DE,SCIF                 ; Compare with the conditional form.
        CALL SCMATCH               ; Match only complete identifier spellings.
        JP Z,SCIFORM               ; Emit the branch skeleton and both arms.
        LD DE,SCBEGIN              ; Compare with the sequencing form.
        CALL SCMATCH               ; Begin consumes every expression to its close.
        JP Z,SCBEGINF              ; Emit the last value of the sequence.
        LD DE,SCLET                ; Compare with parallel local bindings.
        CALL SCMATCH               ; The body gets a fresh lexical slot region.
        JP Z,SCLETF                ; Compile the binding list and body.
        LD DE,SCLETST            ; Compare with sequential local bindings.
        CALL SCMATCH               ; Each initializer sees the earlier bindings.
        JP Z,SCLETSF               ; Compile let* with the same slot discipline.
        LD DE,SCAND                ; Compare with the short-circuit conjunction.
        CALL SCMATCH               ; The two operands are evaluated left to right.
        JP Z,SCANDF                ; Preserve the first false value.
        LD DE,SCOR                 ; Compare with the short-circuit disjunction.
        CALL SCMATCH               ; The two operands are evaluated left to right.
        JP Z,SCORF                 ; Preserve the first true value.
        LD DE,SCPADD               ; Compare with the two-operand addition form.
        CALL SCMATCH               ; Numeric dispatch remains a runtime operation.
        JP Z,SCADDF                 ; Emit a checked addition call.
        LD DE,SCPMIN               ; Compare with subtraction.
        CALL SCMATCH               ; The current form accepts exactly two operands.
        JP Z,SCSUBF                ; Emit a checked subtraction call.
        LD DE,SCPMUL               ; Compare with multiplication.
        CALL SCMATCH               ; Overflow remains a runtime diagnostic.
        JP Z,SCMULF                ; Emit a checked multiplication call.
        JP SCSYN                   ; Implicit procedure calls are not supported.

SCDEFINE:
        LD A,(SCTOP)               ; Nested define is outside this increment.
        OR A                       ; Nonzero is the package-level permission.
        JP Z,SCSYN                 ; Reject definitions inside an expression body.
        CALL RNEXT                 ; Read the new global's symbol name.
        RET C                      ; Propagate source failure before allocation.
        CP 5                       ; Definitions require one identifier.
        JP NZ,SCSYN                ; A list or literal is not a binding name.
        LD (SCID),HL               ; Preserve the full identity across the initializer.
        CALL SCGGET                ; Forward references use this same slot.
        RET C                      ; Reject the 257th distinct package name.
        LD (SCDEFSL),A           ; The store below targets this global slot.
        CALL SCEXPR                ; Compile the initializer before publishing it.
        RET C                      ; A failed initializer leaves no output file.
        LD A,(SCDEFSL)             ; Recover the selected global slot.
        LD L,A                     ; Pass the slot number to SCSTORE.
        XOR A                      ; Kind zero denotes a package-global slot.
        CALL SCSTORE               ; Emit the initialized flag update at runtime.
        RET C                      ; A fixup-capacity error is terminal.
        CALL SCEXPECT              ; Require the definition's closing parenthesis.
        RET                        ; The stored value remains the form result.

; Compile a two-operand numeric form selected by SCOP and close its list.
SCBIN:
        CALL SCEXPR                ; Compile the left operand first.
        RET C                      ; Preserve the first operand's diagnostic.
        CALL SCPUSH                ; Save its tag and payload on the generated stack.
        CALL SCEXPR                ; Compile the right operand second.
        RET C                      ; Preserve a nested syntax or capacity error.
        CALL SCPUSH                ; Push the right value above the left value.
        CALL SCEXPECT              ; Exactly two operands are accepted here.
        RET C                      ; A third operand or missing close is syntax.
        LD A,(SCOP)                ; Select the checked runtime operation.
        OR A                       ; Addition uses the zero selector.
        JR Z,SCADD                 ; Call the runtime helper for addition.
        CP 1                       ; Subtraction uses selector one.
        JR Z,SCSUB                 ; Call the runtime helper for subtraction.
        LD HL,SRTMUL               ; The remaining selector is multiplication.
        JP SCCALL                  ; Emit the checked runtime call.
SCADD:
        LD HL,SRTADD               ; Address of the checked addition helper.
        JP SCCALL                  ; Emit the call and return to the form parser.
SCSUB:
        LD HL,SRTSUB               ; Address of the checked subtraction helper.
        JP SCCALL                  ; Emit the call and return to the form parser.

SCADDF:
        XOR A                      ; Addition selector zero.
        LD (SCOP),A                ; Save it while SCBIN reads both operands.
        JP SCBIN                   ; Compile the common binary form.
SCSUBF:
        LD A,1                      ; Subtraction selector one.
        LD (SCOP),A                ; Save it while SCBIN reads both operands.
        JP SCBIN                   ; Compile the common binary form.
SCMULF:
        LD A,2                      ; Multiplication selector two.
        LD (SCOP),A                ; Save it while SCBIN reads both operands.
        JP SCBIN                   ; Compile the common binary form.

; Compile if, placing a false-arm branch before the consequent and a jump over
; the alternative after it.  Nested forms use the separate IF patch stacks.
SCIFORM:
        CALL SCEXPR                ; Compile the test value.
        RET C                      ; Preserve a test-expression diagnostic.
        LD HL,SRTFAL               ; Runtime helper returns Z only for #f.
        CALL SCCALL                ; Check the test without changing its value.
        CALL SCJZ                  ; Emit JP Z,zero and return its patch address.
        CALL SCIFPUSH              ; Save the false-arm patch for this depth.
        CALL SCEXPR                ; Compile the consequent expression.
        RET C                      ; A broken consequent aborts the whole form.
        CALL SCJP                  ; Skip the alternative after a true arm.
        CALL SCIFENDP              ; Save the end-jump patch for this depth.
        LD HL,(SCPC)               ; The alternative starts at this code address.
        CALL SCABS                 ; Convert its staged address to output address.
        CALL SCIFPATF            ; Patch the false branch before reading the arm.
        CALL RNEXT                 ; A close means the optional alternative is absent.
        RET C                      ; Preserve a reader error after the consequent.
        CP 2                       ; Closing now selects an unspecified false value.
        JR Z,SCIFNONE              ; Emit #f and finish the branch skeleton.
        CALL SCEXPE                ; The already-read event is the alternative.
        RET C                      ; Propagate an alternative expression failure.
        CALL SCEXPECT              ; The alternative must close the original list.
        JR SCIFDONE                ; Patch the end jump after its last byte.
SCIFNONE:
        XOR A                      ; Select #f for an omitted alternative.
        CALL SCBOOL                ; The false arm returns a stable scalar value.
SCIFDONE:
        LD HL,(SCPC)               ; Both arms now end at this generated address.
        CALL SCABS                 ; Convert it to the output's absolute address.
        CALL SCIFPATE            ; Patch the unconditional end jump.
        JP SCIFPOP                 ; Release this nested if patch record.

; Compile a begin body, preserving the value produced by its final expression.
SCBEGINF:
        CALL SCBODY                ; SCBODY consumes the matching close.
        RET                        ; The last emitted value remains in registers.

; Compile the two short-circuit operands of and.
SCANDF:
        CALL SCEXPR                ; Compile the first operand.
        RET C                      ; Preserve the first operand's diagnostic.
        LD HL,SRTFAL               ; Test the value while retaining its registers.
        CALL SCCALL                ; Z means the first operand is #f.
        CALL SCJZ                  ; Branch to the first operand's final-value path.
        CALL SCBRPUSH              ; Save the patch in the nested branch stack.
        CALL SCEXPR                ; Compile the second operand only when needed.
        RET C                      ; Preserve a nested syntax or capacity error.
        CALL SCEXPECT              ; And is exactly two operands in this increment.
        RET C                      ; A missing or extra operand is syntax.
        LD HL,(SCPC)               ; The second operand is the true path's result.
        CALL SCABS                 ; Convert its end address for the branch target.
        JP SCBRPAT                 ; Patch the pending branch to this target.

; Compile the two short-circuit operands of or.
SCORF:
        CALL SCEXPR                ; Compile the first operand.
        RET C                      ; Preserve the first operand's diagnostic.
        LD HL,SRTFAL               ; Test the value while retaining its registers.
        CALL SCCALL                ; Z means the first operand is false.
        CALL SCJNZ                 ; A true first operand skips the second.
        CALL SCBRPUSH              ; Save the patch in the nested branch stack.
        CALL SCEXPR                ; Compile the second operand only when needed.
        RET C                      ; Preserve a nested syntax or capacity error.
        CALL SCEXPECT              ; Or is exactly two operands in this increment.
        RET C                      ; A missing or extra operand is syntax.
        LD HL,(SCPC)               ; The second operand is the false path's result.
        CALL SCABS                 ; Convert its end address for the branch target.
        JP SCBRPAT                 ; Patch the pending branch to this target.

; Consume a body until its close.  The already-read closing event is not lost.
SCBODY:
        XOR A                      ; No body expression has been seen yet.
        LD (SCBODYN),A             ; Track the nonempty-body requirement.
SCBODYLP:
        CALL RNEXT                 ; Read the next body expression or close.
        RET C                      ; Preserve source failure.
        CP 2                       ; A close terminates the body.
        JR Z,SCBODYED             ; The final expression remains in registers.
        CP 0                       ; EOF cannot close a form.
        JP Z,SCSYN                 ; Reject an incomplete body.
        CALL SCEXPE                ; Compile the already-read expression event.
        RET C                      ; Propagate its diagnostic.
        LD A,(SCBODYN)             ; Count this completed body expression.
        INC A                      ; Body sequences may contain multiple forms.
        LD (SCBODYN),A             ; Publish the count before reading the next.
        JR SCBODYLP              ; Continue until the matching close arrives.
SCBODYED:
        LD A,(SCBODYN)             ; Empty bodies are not accepted here.
        OR A                       ; Z denotes no body expression.
        JP Z,SCSYN                 ; Keep the source contract explicit.
        XOR A                      ; Return carry clear after a complete body.
        RET                        ; The last body's value is still in A/HL.

; Report a bounded table or nesting failure.
SCCAP:
        SCF                       ; Carry distinguishes capacity from syntax.
        RET                        ; No partial output is published after this return.

SCSYN:
        SCF                       ; The caller reports a compile-error diagnostic.
        RET                        ; Reader state remains terminal until the next run.
SCUNSUP:
        SCF                       ; Binary16 and unsupported forms are explicit errors.
        RET                        ; The public command does not publish a partial file.
SCREAD:
        SCF                       ; Reader errors are reported through SCFAIL.
        RET                        ; The reader itself retains the original code.

; Compiler state and reader-owned contexts.  Descriptor and spelling storage
; lives in the high TPA regions above; these small records remain in the image.
SCPC:       DW 0                   ; Staged generated-code cursor.
SCWTMP:     DW 0                   ; Temporary word for opcode emission.
SCVTMP:     DW 0                   ; Temporary literal payload.
SCFPTR:     DW 0                   ; Staged address retained by SCFIX.
SCPTMP:     DW 0                   ; Absolute target retained by SCPATCH.
SCFKIND:    DB 0                   ; Pending slot kind for SCFIX.
SCFSLOT:    DB 0                   ; Pending slot number for SCFIX.
SCBTMP:     DB 0                   ; Temporary boolean payload.
SCID:       DW 0                   ; Current full interner symbol identity.
SCSLOT:     DB 0                   ; Current local or global slot number.
SCGSLOT:    DB 0                   ; Global slot returned by SCGGET.
SCGIDX:     DB 0                   ; Candidate global slot during a key scan.
SCDEFSL:  DB 0                   ; Definition initializer's global slot.
SCOP:       DB 0                   ; Selected binary operation 0, 1 or 2.
SCALLOW:    DB 0                   ; Package-level permission for define.
SCTOP:      DB 0                   ; Saved define permission for SCFORM.
SCBODYN:    DB 0                   ; Body expression count.
SCFORMN:    DW 0                   ; Number of complete package-level forms.
SCGCOUNT:   DW 0                   ; Number of allocated package-global slots.
SCLOCTOP:   DB 0                   ; Number of active local binding records.
SCLNEXT:    DB 0                   ; Next reusable local slot number.
SCLOCMAX:   DB 0                   ; Maximum simultaneous local slot count.
SCBNDTOP:  DB 0                   ; Pending binding-record stack top.
SCMARK:     DB 0                   ; Pending-record cursor during SCBIND.
SCBEND:     DB 0                   ; Pending-record limit for the current let.
SCFIXN:     DW 0                   ; Number of recorded slot-address fixups.
SCBRTOP:    DB 0                   ; Generic branch patch stack top.
SCIFTOP:    DB 0                   ; Nested if patch stack top.
SCBPTMP:    DW 0                   ; Temporary staged branch patch address.
SCBTARG:    DW 0                   ; Temporary absolute branch target.
SCFOUND:    DB 0                   ; Last matching local slot.
SCFOUNDK:   DB 0                   ; Nonzero after a local match.
SCERR:      DB 0                   ; Reserved diagnostic selector.
SCNCTX:     DW SCNAMEDS,320,SCNAMEPL,5120,0,0
            DB 0,0                  ; Symbol context kind and ready flag.
SCSCTX:     DW SCSTRDS,64,SCSTRPL,512,0,0
            DB 1,0                  ; String context kind and ready flag.

; Length-prefixed operator names.  Keeping these strings beside the parser
; makes the accepted surface obvious without adding a keyword table to output.
SCDEF:      DB 6,"define"
SCIF:       DB 2,"if"
SCBEGIN:    DB 5,"begin"
SCLET:      DB 3,"let"
SCLETST:  DB 4,"let*"
SCAND:      DB 3,"and"
SCOR:       DB 2,"or"
SCPADD:     DB 1,"+"
SCPMIN:     DB 1,"-"
SCPMUL:     DB 1,"*"
SCOKTXT:    DB "COMPILED",13,10,"$"
SCERRTXT:   DB "COMPILE ERROR",13,10,"$"
SCMEMTXT:   DB "INSUFFICIENT MEMORY",13,10,"$"
