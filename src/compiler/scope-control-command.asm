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
SCEND   EQU 08F80H               ; Use the available gap before compiler tables.
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
SCPMETA  EQU 0C000H              ; Procedure records stay outside reader tables.
SCLOCOWN EQU 0C400H              ; Owner procedure for each reusable local slot.
SCPMASK  EQU 0C500H              ; Per-procedure masks follow the owner bytes.
SCPRSZ   EQU 44                  ; Body, arity, slots and two 128-bit masks.
SCOWNOF  EQU 12                  ; Owned-slot mask begins after four formals.
SCCAPOF  EQU 28                  ; Captured-slot mask follows the owned mask.
SCMASKB  EQU 16                  ; One mask covers the 128 local slots.
SCLOCEV  EQU 0C600H              ; One escape flag belongs to each local slot.
SCBFRAME EQU 0C700H              ; Nested body lookahead records use this area.
SCBFSZ   EQU 9                   ; Cursors, owner and procedure patch state.
SCGPRIM  EQU 0C800H              ; One predefined-primitive kind per global slot.
SCBRANCH EQU 0C900H              ; Generic short-circuit branch patch stack.
SCIFALSE EQU 0CA00H              ; False-branch patch words for nested if forms.
SCIFEND  EQU 0CA80H              ; End-branch patch words for nested if forms.
SCTAILPT EQU 0CB00H              ; Tail-call target words awaiting body closure.
SCTAILK  EQU 0CB80H              ; One flag records a saved side-stack operator.
SCTMAX   EQU 64                   ; Tail candidates per body expression scope.
; Literal records and bytes use the compiler-only band below the private stack.
SCLITREC EQU 0D000H               ; Four bytes per copied symbol or string.
SCLITPL EQU 0D100H              ; One kilobyte of literal spelling storage.
SCLITOUT EQU 0D500H               ; Staged output address for each literal record.
SCLITPSZ EQU SCLITOUT-SCLITPL    ; Capacity check for copied literal spellings.
SCLITEND EQU 0D600H               ; End of the fixed compiler workspace.
SCWEND   EQU SCLITEND             ; Budget accounting includes literal storage.

; Compiler entry and terminal paths.
SCMAIN:
        LD HL,(6)                ; CP/M reports the transient-memory ceiling.
        LD DE,0E000H              ; Reserve the upper 512 bytes for the stack.
        OR A                      ; Clear carry before the ceiling comparison.
        SBC HL,DE                 ; Check the qualified TPA has the required guard.
        JP C,SCMEM                ; Refuse an installation with too little memory.
        LD SP,0E000H              ; Parser and emitter calls share this stack.
        CALL SCSETUP              ; Clear tables and load the checked runtime provider.
        JP C,SCFAIL               ; Refuse to parse when the provider was not loaded.
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
        LD DE,(SCERRPTR)           ; All rejected forms remain unpublished.
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
        LD (SCPCOUNT),A           ; No procedure descriptor has been allocated.
        LD (SCTMPPR),A            ; No descriptor is awaiting its body address.
        LD (SCARGN),A             ; No generic application argument is pending.
        LD (SCAPMODE),A           ; No compact global-call marker is active.
        LD (SCTCTX),A             ; Top-level expressions are not tail calls.
        LD (SCMUT),A          ; Stores initialize bindings until set! selects checks.
        LD (SCIFTAIL),A           ; No branch context is active at package entry.
        LD (SCTTOP),A             ; No pending tail-call target words exist.
        LD (SCLITN),A             ; No copied symbol or string literals exist yet.
        LD (SCLITUSE),A           ; The literal byte pool starts empty.
        LD (SCLITUSE+1),A
        LD (SCQCNT),A             ; No quoted-list cache cells are reserved yet.
        LD (SCQCOUNT),A            ; No quoted-list elements are pending.
        LD (SCQDOT),A              ; No dotted-list marker is active.
        LD (SCBDEP),A             ; No compiler lambda frame is active.
        LD (SCBMODE),A            ; No body is isolating its tail candidates.
        LD (SCBISOL),A            ; Nested body forms propagate candidates by default.
        LD HL,SCLOCEV              ; Clear escape flags from the previous source run.
        LD B,0                    ; DJNZ with zero performs all 256 byte writes.
SCSETEV:
        LD (HL),A
        INC HL
        DJNZ SCSETEV
        LD HL,SCGPRIM              ; Clear predefined-primitive marks as well.
        LD B,0
SCSETPR:
        LD (HL),A
        INC HL
        DJNZ SCSETPR
        LD HL,SCERRTXT            ; Use the ordinary diagnostic by default.
        LD (SCERRPTR),HL          ; Body diagnostics may replace this pointer.
        LD A,0FFH                 ; Top-level locals have no procedure owner.
        LD (SCCURPR),A            ; Nested lambdas replace this while compiling.
        CALL SCLOADRT              ; Copy the provider into the staged output image.
        RET C                      ; A short, missing or unreadable provider is fatal.
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
        JP Z,SCENDSYN              ; Report the same syntax error as other empties.
        JP SCRET                   ; Append RET and return to the command driver.

; Parse one event already returned in A; literal payloads remain in RTAG:HL.
SCEXPE:
        CP 7                       ; Numeric events use the scalar payload contract.
        JR Z,SCNUM                 ; Emit an exact integer literal.
        CP 5                       ; Symbol events carry an interned reference.
        JR Z,SCREF                 ; Resolve a local or package-global slot.
        CP 8                       ; String events become copied immutable literals.
        JP Z,SCSTRLIT
        CP 3                       ; Quote prefixes introduce literal data.
        JP Z,SCQSHRT              ; Read and emit the following quoted datum.
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
SCSTRLIT:
        LD A,5                     ; Runtime tag five identifies string literals.
        JP SCLITADD
SCBOOLV:
        LD A,L                     ; Boolean payloads are zero or one in the low byte.
        JP SCBOOL                  ; Emit the checked boolean representation.

; Resolve a symbol reference, preferring the innermost active local binding.
SCREF:
        LD (SCID),HL               ; Save the full interner ID across table searches.
        CALL SCLOCF                ; Search active locals before global classification.
        JR C,SCRLOCAL              ; A local slot shadows every global or primitive.
        CALL SCGHAS                 ; An explicit global binding takes precedence.
        JR C,SCRGLOB                ; Existing globals use the ordinary slot path.
        CALL SCPLOOK                ; Unbound primitive names can stay immediate.
        OR A
        JR NZ,SCRPRIM               ; Emit the predefined value without a slot.
        CALL SCGGET                ; Allocate a global slot on the first reference.
        RET C                      ; The 256-slot capacity is a compile diagnostic.
        LD L,A                     ; The emitter takes the slot number in L.
        XOR A                      ; Kind zero denotes a package-global slot.
        JP SCLOAD                  ; Emit the checked runtime load and its fixup.
SCRGLOB:
        LD L,A                     ; SCGHAS returns the existing global slot in A.
        XOR A                      ; Kind zero denotes a package-global slot.
        JP SCLOAD                  ; Emit the checked runtime load and its fixup.
SCRPRIM:
        JP SCPRIM                  ; Emit a reserved primitive value directly.
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
        CP 1                       ; A list operator is a computed procedure value.
        JP Z,SCAPLIST              ; Compile it before reading application arguments.
        CP 5                       ; Event kind five is an interned symbol.
        JP NZ,SCOPRSYN             ; Scalar literals cannot be operators.
        LD (SCOPID),HL             ; Preserve the complete identity for fallback.
        LD DE,SCDEF                ; Compare the spelling with the define keyword.
        CALL SCMATCH               ; The lexer buffer remains valid until RNEXT.
        JP Z,SCDEFINE              ; Definitions use the saved package-level flag.
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
        LD DE,SCLAMBK              ; Compare with lambda.
        CALL SCMATCH               ; Lambda creates a fixed procedure descriptor.
        JP Z,SCLAMBF               ; Compile its formal list and body.
        LD DE,SCSETK               ; Compare with set!.
        CALL SCMATCH               ; Mutation updates an existing slot.
        JP Z,SCSETF                ; Compile the target and new value.
        LD DE,SCQUOTE              ; Compare with the explicit quote form.
        CALL SCMATCH               ; Quote consumes one datum without evaluation.
        JP Z,SCQUOTEF
        JP SCAPNAME                ; Other names are ordinary procedure values.

; Compile a computed operator list and continue with its argument sequence.
SCAPLIST:
        CALL SCEXPE                ; The opening list event remains in A.
        RET C                      ; Preserve the nested operator diagnostic.
        CALL SCPUSH                ; Keep the computed callee below its arguments.
        RET C
        XOR A                      ; A computed operator uses the ordinary call path.
        LD (SCAPMODE),A            ; Do not inherit a surrounding primitive marker.
        JP SCAPARGS               ; The outer form supplies the arguments.

; Load a named procedure value and compile its application arguments.
SCAPNAME:
        LD HL,(SCOPID)             ; Restore the operator's interned identity.
        LD (SCID),HL               ; The primitive check uses the common identity word.
        CALL SCLOCF                ; A local name must retain the ordinary path.
        JR C,SCAPGEN               ; Local bindings shadow predefined procedures.
        CALL SCGHAS                ; An explicit global binding must remain dynamic.
        JR C,SCAPBND               ; Existing globals use the normal marker path.
        CALL SCPLOOK               ; Unbound primitives use a reserved immediate.
        OR A
        JR Z,SCAPGEN               ; Ordinary names still use a full value record.
        LD (SCPKIND),A             ; Keep the primitive kind while emitting its marker.
        CALL SCPRIMV               ; Save the immediate operator on the side stack.
        RET C                      ; Preserve staged-output capacity failures.
        LD A,1
        LD (SCAPMODE),A            ; SCAPARGS now emits the compact call entry.
        JP SCAPARGS
SCAPBND:
        LD (SCAPGSL),A             ; Preserve the existing global slot for SCGMARK.
        CALL SCGMARK               ; Read the bound value before evaluating arguments.
        RET C
        LD A,1
        LD (SCAPMODE),A            ; SCAPARGS now emits the compact call entry.
        JP SCAPARGS
SCAPGEN:
        XOR A
        LD (SCAPMODE),A            ; The general path carries a complete callee value.
        LD HL,(SCOPID)             ; Restore the operator's interned identity.
        CALL SCREF                 ; Resolve the value before reading arguments.
        RET C
        CALL SCPUSH                ; Keep the named callee below its arguments.
        RET C
        JP SCAPARGS                ; SCREF leaves the generated value in A:HL.

SCDEFINE:
        LD A,(SCTOP)               ; Nested define is outside this increment.
        OR A                       ; Nonzero is the package-level permission.
        JP Z,SCDEFSYN               ; Reject definitions inside an expression body.
        CALL RNEXT                 ; Read the new global's symbol name.
        RET C                      ; Propagate source failure before allocation.
        CP 5                       ; Definitions require one identifier.
        JP NZ,SCDEFNSY              ; A list or literal is not a binding name.
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
        LD A,(SCOP)                ; Preserve the operator across recursive operands.
        PUSH AF                    ; A nested binary form uses the same scratch byte.
        XOR A                      ; Binary operands are evaluated before the result.
        LD (SCTCTX),A              ; Neither operand is in tail position.
        CALL SCEXPR                ; Compile the left operand first.
        JR C,SCBINERR              ; Balance the saved operator on failure.
        CALL SCPUSH                ; Save its tag and payload on the generated stack.
        JR C,SCBINERR              ; Preserve output exhaustion with a balanced frame.
        XOR A                      ; The right operand also retains its continuation.
        LD (SCTCTX),A
        CALL SCEXPR                ; Compile the right operand second.
        JR C,SCBINERR              ; Balance the saved operator on failure.
        CALL SCPUSH                ; Push the right value above the left value.
        JR C,SCBINERR              ; Preserve output exhaustion with a balanced frame.
        CALL SCEXPECT              ; Exactly two operands are accepted here.
        JR C,SCBINERR              ; A third operand or missing close is syntax.
        POP AF                     ; Recover the operator after both operands finish.
        LD (SCOP),A                ; Restore the selector before dispatch.
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
SCBINERR:
        POP AF                     ; Remove the saved operator after a failure.
        SCF                       ; Preserve the nested expression diagnostic.
        RET

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
        LD A,(SCTCTX)              ; Save the surrounding tail position for both arms.
        LD (SCIFTAIL),A            ; The predicate itself is never a tail call.
        XOR A
        LD (SCTCTX),A              ; Test evaluation returns to the branch skeleton.
        CALL SCEXPR                ; Compile the test value.
        RET C                      ; Preserve a test-expression diagnostic.
        LD HL,SRTFAL               ; Runtime helper returns Z only for #f.
        CALL SCCALL                ; Check the test without changing its value.
        CALL SCJZ                  ; Emit JP Z,zero and return its patch address.
        CALL SCIFPUSH              ; Save the false-arm patch for this depth.
        LD A,(SCIFTAIL)            ; The consequent inherits the enclosing position.
        LD (SCTCTX),A
        CALL SCEXPR                ; Compile the consequent expression.
        RET C                      ; A broken consequent aborts the whole form.
        CALL SCJP                  ; Skip the alternative after a true arm.
        CALL SCIFENDP              ; Save the end-jump patch for this depth.
        LD HL,(SCPC)               ; The alternative starts at this code address.
        CALL SCABS                 ; Convert its staged address to output address.
        CALL SCIFPATF            ; Patch the false branch before reading the arm.
        LD A,(SCIFTAIL)            ; The alternative inherits the enclosing position.
        LD (SCTCTX),A
        CALL RNEXT                 ; A close means the optional alternative is absent.
        RET C                      ; Preserve a reader error after the consequent.
        CP 2                       ; Closing now selects the unspecified value.
        JR Z,SCIFNONE              ; Emit it and finish the branch skeleton.
        CALL SCEXPE                ; The already-read event is the alternative.
        RET C                      ; Propagate an alternative expression failure.
        CALL SCEXPECT              ; The alternative must close the original list.
        JR SCIFDONE                ; Patch the end jump after its last byte.
SCIFNONE:
        CALL SCUNS                 ; An omitted alternative returns UNSPECIFIED.
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
        LD A,(SCTCTX)              ; Save the surrounding tail position.
        PUSH AF                    ; The first operand itself is never tail code.
        XOR A
        LD (SCTCTX),A
        CALL SCEXPR                ; Compile the first operand.
        JR C,SCANDERR              ; Balance the saved context on failure.
        POP AF                     ; Recover the enclosing tail position.
        LD (SCTCTX),A              ; Only the second operand can inherit it.
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
SCANDERR:
        POP AF                     ; Remove the saved tail position after failure.
        SCF
        RET

; Compile the two short-circuit operands of or.
SCORF:
        LD A,(SCTCTX)              ; Save the surrounding tail position.
        PUSH AF                    ; The first operand itself is never tail code.
        XOR A
        LD (SCTCTX),A
        CALL SCEXPR                ; Compile the first operand.
        JR C,SCORERR               ; Balance the saved context on failure.
        POP AF                     ; Recover the enclosing tail position.
        LD (SCTCTX),A              ; Only the second operand can inherit it.
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
SCORERR:
        POP AF                     ; Remove the saved tail position after failure.
        SCF
        RET

; Compile each body expression immediately, then use the following reader
; event to decide whether its recorded tail calls need ordinary continuations.
SCBODY:
        POP DE                     ; Move the caller return below the body frame.
        LD A,(SCTMARK)             ; Nested bodies share this expression cursor.
        PUSH AF                    ; Restore it before the enclosing body resumes.
        LD A,(SCTCTX)              ; Save the caller's tail context.
        PUSH AF                    ; Frame word seven: previous tail context.
        LD A,(SCTTOP)              ; Save pending tail-call records from an outer body.
        PUSH AF                    ; Frame word six: previous tail-record top.
        LD A,(SCBMODE)             ; Save the enclosing body's candidate mode.
        PUSH AF                    ; Frame word five: previous candidate mode.
        LD A,(SCBISOL)             ; Save whether this body is isolated.
        PUSH AF                    ; Frame word four: requested isolation state.
        LD A,(SCBODYN)             ; Preserve the previous expression count.
        PUSH AF                    ; Frame word three: previous body count.
        LD A,(SCBTAIL)             ; Preserve the previous body tail flag.
        PUSH AF                    ; Frame word two: previous body tail flag.
        LD A,(SCBEV)               ; Preserve the previous current event.
        PUSH AF                    ; Frame word one: previous event kind.
        LD A,(SCBTAG)              ; Preserve the previous current tag.
        PUSH AF                    ; Frame word zero: previous scalar tag.
        LD HL,(SCBVAL)             ; Preserve the previous current payload.
        PUSH HL                    ; Body payload completes the saved frame.
        PUSH DE                    ; Restore the caller return above the frame.
        LD A,(SCTCTX)              ; The incoming context belongs to this body.
        LD (SCBTAIL),A             ; Only a final expression keeps this flag.
        LD A,(SCBISOL)             ; Record whether this body owns a private list.
        LD (SCBMODE),A
        XOR A                      ; Nested begin and let bodies share their list.
        LD (SCBISOL),A
        LD A,(SCBMODE)
        OR A
        JR Z,SCBKEEP               ; Shared bodies retain outer tail candidates.
        XOR A                      ; A procedure body starts a private candidate list.
        LD (SCTTOP),A
SCBKEEP:
        XOR A                      ; Start with no expressions in this body.
        LD (SCBODYN),A             ; Empty bodies remain a syntax error.
SCBREAD:
        CALL RNEXT                 ; Read one body expression or its closing parenthesis.
        JP C,SCBFAIL               ; Restore the frame after a reader failure.
        CP 2                       ; A close before an expression is invalid.
        JP Z,SCBFAIL               ; Report an empty body after balanced cleanup.
        OR A                       ; EOF cannot close an open body.
        JP Z,SCBFAIL               ; Report an incomplete body after cleanup.
        LD (SCBEV),A               ; Preserve the event until SCEXPE dispatches it.
        LD (SCBVAL),HL             ; Preserve the event payload.
        LD A,(RTAG)                ; Preserve its scalar tag.
        LD (SCBTAG),A              ; Structural events ignore this field.
SCBEXPR:
        LD A,(SCTTOP)              ; Remember tail records made by this expression.
        LD (SCTMARK),A             ; Non-final expressions will rewrite those calls.
        LD A,(SCBTAIL)             ; Give the expression the body's incoming context.
        LD (SCTCTX),A              ; Tail candidates use a wrapper until finality is known.
        LD A,(SCBTAG)              ; Restore the event's reader tag.
        LD (RTAG),A
        LD A,(SCBEV)               ; Restore the event kind for SCEXPE.
        LD HL,(SCBVAL)             ; Restore its payload for SCEXPE.
        CALL SCEXPE                ; Compile this complete expression immediately.
        JR NC,SCBEXPOK             ; Continue after a successful body expression.
        JP SCBFAIL                 ; No later event is consumed on expression failure.
SCBEXPOK:
        LD (SCRESV),HL             ; Save the expression result before reading ahead.
        LD (SCREST),A              ; Preserve its tag across the reader call.
        LD A,(SCBODYN)             ; Count the completed body expression.
        INC A
        LD (SCBODYN),A
        CALL RNEXT                 ; The next event distinguishes final from non-final.
        JP C,SCBFAIL               ; The expression result is discarded on source failure.
        CP 2                       ; A close leaves the preceding expression final.
        JP Z,SCBFINAL              ; Leave tail wrappers intact for the final value.
        OR A                       ; EOF cannot terminate a body.
        JP Z,SCBFAIL               ; Reject an incomplete body.
        LD (SCBEV),A               ; Save the next expression while rewriting candidates.
        LD (SCBVAL),HL             ; Preserve its payload across SCTFIX.
        LD A,(RTAG)                ; Preserve its logical scalar tag.
        LD (SCBTAG),A
        CALL SCTFIX                ; Non-final tail calls become ordinary calls.
        JP C,SCBFAIL
        JP SCBEXPR                ; Compile the saved next event without rereading.
SCBFINAL:
        LD HL,(SCRESV)             ; Recover the final expression payload.
        LD A,(SCREST)              ; Recover its final expression tag.
        CALL SCBREST               ; Restore caller scratch and the continuation.
        LD HL,(SCRESV)             ; Restore the body value after frame cleanup.
        LD A,(SCREST)              ; Restore the body tag after frame cleanup.
        OR A                       ; Return carry clear with the final value.
        RET
SCBFAIL:
        CALL SCBREST               ; Restore all body fields and the continuation.
        SCF                        ; Preserve the reader or expression failure.
        RET                        ; No partially compiled body is accepted.

; Restore one saved body frame.  The helper is called with its frame on top.
SCBREST:
        POP BC                     ; Save the continuation after this helper call.
        POP DE                     ; Recover the caller continuation below the frame.
        POP HL                     ; Restore the previous body payload.
        LD (SCBVAL),HL             ; Publish it before returning to the caller.
        POP AF                     ; Restore the previous scalar tag.
        LD (SCBTAG),A              ; Preserve it for another nested body.
        POP AF                     ; Restore the previous event kind.
        LD (SCBEV),A               ; Publish the old current event.
        POP AF                     ; Restore the previous incoming tail flag.
        LD (SCBTAIL),A             ; Publish the old body context.
        POP AF                     ; Restore the previous body count.
        LD (SCBODYN),A             ; Publish the old expression count.
        POP AF                     ; Restore the caller's isolation request.
        LD (SCBISOL),A
        LD A,(SCBMODE)             ; Private bodies restore their candidate top.
        OR A
        JR Z,SCBKEEPT
        POP AF                     ; Restore the enclosing body's candidate mode.
        LD (SCBMODE),A
        POP AF                     ; Restore the enclosing candidate top.
        LD (SCTTOP),A
        JR SCBMODDN
SCBKEEPT:
        POP AF                     ; Restore the enclosing body's candidate mode.
        LD (SCBMODE),A
        POP AF                     ; Discard the shared body's saved candidate top.
SCBMODDN:
        POP AF                     ; Restore the caller's tail context.
        LD (SCTCTX),A              ; Nested forms see their original context again.
        POP AF                     ; Restore the enclosing expression's tail cursor.
        LD (SCTMARK),A             ; A nested body must not change its caller's mark.
        PUSH DE                    ; Restore the caller continuation below the helper.
        PUSH BC                    ; Return to the success or failure continuation.
        RET                        ; The frame is balanced on every exit path.

; Report a bounded table or nesting failure.
SCCAP:
        LD HL,SCCAPTXT
        LD (SCERRPTR),HL
        SCF                       ; Carry distinguishes capacity from syntax.
        RET                        ; No partial output is published after this return.

SCSYN:
        SCF                       ; The caller reports a compile-error diagnostic.
        RET                        ; Reader state remains terminal until the next run.
SCEXERR:
        LD HL,SCEXTXT
        LD (SCERRPTR),HL
        JP SCSYN
SCENDSYN:
        LD HL,SCENDT
        LD (SCERRPTR),HL
        JP SCSYN
SCOPRSYN:
        LD HL,SCOPRT
        LD (SCERRPTR),HL
        JP SCSYN
SCDEFSYN:
        LD HL,SCDEFT
        LD (SCERRPTR),HL
        JP SCSYN
SCDEFNSY:
        LD HL,SCDEFNT
        LD (SCERRPTR),HL
        JP SCSYN
SCUNSUP:
        LD HL,SCUNSTXT
        LD (SCERRPTR),HL
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
SCPKIND:    DB 0                   ; Predefined primitive kind for the current name.
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
SCOPID:     DW 0                   ; Operator identity for generic applications.
SCPNADR:    DW 0                   ; Spelling address while classifying a primitive.
SCPNLEN:    DB 0                   ; Spelling length used by SCPMATCH.
SCPCOUNT:   DB 0                   ; Number of fixed procedure descriptors.
SCCURPR:    DB 0FFH                ; Active procedure, or FFH at package level.
SCTMPPR:    DB 0                   ; Descriptor being compiled.
SCARGN:     DB 0                   ; Generic application argument count.
SCTCTX:     DB 0                   ; Nonzero when the current expression is tail code.
SCIFTAIL:   DB 0                   ; Tail context saved while compiling an if.
SCTLSAV:    DB 0                   ; Saved tail context while evaluating arguments.
SCSKIP:     DW 0                   ; Lambda jump-over patch address.
SCPBODY:    DW 0                   ; Procedure body staged address during setup.
SCLOCVAL:   DB 0                   ; Temporary local slot for owner marking.
SCMSLOT:    DB 0                   ; Slot selected while setting a mask bit.
SCMPR:      DB 0                   ; Procedure index selected for mask writes.
SCMTADR:    DW 0                   ; Mask byte address during bit assembly.
SCDESTK:    DB 0                   ; Mutation destination kind.
SCMUT:  DB 0                   ; Nonzero selects the checked mutation store.
SCORIGPR:   DB 0                   ; Active procedure while capture masks are chained.
SCORIGTM:   DB 0                   ; Descriptor under construction during mask writes.
SCCAPOWN:   DB 0                   ; Procedure that owns the captured local slot.
SCCHAINN:   DB 0                   ; Remaining body frames in a capture chain.
SCAPEV:     DB 0                   ; Saved generic-argument event kind.
SCAPTAG:    DW 0                   ; Saved generic-argument scalar tag.
SCAPVAL:    DW 0                   ; Saved generic-argument payload.
SCAPMODE:   DB 0                   ; Nonzero selects the compact global-call marker.
SCAPGSL:    DB 0                   ; Global slot carried by the compact call marker.
SCRESV:     DW 0                   ; Procedure/body result payload during cleanup.
SCREST:     DB 0                   ; Procedure/body result tag during cleanup.
SCERRPTR:   DW 0                   ; Current compiler diagnostic string.
SCBDEP:     DB 0                   ; Nested body-frame depth.
SCBTAIL:    DB 0                   ; Incoming tail context for the current body.
SCBMODE:    DB 0                   ; Nonzero bodies keep tail candidates private.
SCBISOL:    DB 0                   ; Caller requests a private candidate scope.
SCBEV:      DB 0                   ; Current body-frame event kind.
SCBTAG:     DB 0                   ; Current body-frame scalar tag.
SCBVAL:     DW 0                   ; Current body-frame payload.
SCTTOP:     DB 0                   ; Number of tail-call target words in this body.
SCTMARK:    DB 0                   ; Start of the current expression's tail records.
SCTPTR:     DW 0                   ; Tail-call patch address during table writes.
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
SCLAMBK:    DB 6,"lambda"
SCSETK:     DB 4,"set!"
SCZEROK:    DB 5,"zero?"
SCPADD:     DB 1,"+"
SCPMIN:     DB 1,"-"
SCPMUL:     DB 1,"*"
SCOKTXT:    DB "COMPILED",13,10,"$"
SCERRTXT:   DB "COMPILE ERROR",13,10,"$"
SCCAPTXT:   DB "CAP",13,10,"$"
SCSYNTXT:   DB "SYN",13,10,"$"
SCUNSTXT:   DB "UNSUP",13,10,"$"
SCOUTTXT:   DB "OUTPUT ERROR",13,10,"$"
SCEXPTXT:   DB "EXPECT",13,10,"$"
SCEXTXT:    DB "EXPR",13,10,"$"
SCAPTXT:    DB "APPLY",13,10,"$"
SCDESTT:    DB "DEST",13,10,"$"
SCDUPTXT:   DB "DUP",13,10,"$"
SCENDT:     DB "END",13,10,"$"
SCOPRT:     DB "OP",13,10,"$"
SCDEFT:     DB "DEF",13,10,"$"
SCDEFNT:    DB "DEFNAME",13,10,"$"
SCMEMTXT:   DB "INSUFFICIENT MEMORY",13,10,"$"
SCQUOTE:    DB 5,"quote"
SCNPLUS:    DB 1,"+"
SCNSUB:     DB 1,"-"
SCNMUL:     DB 1,"*"
SCNZERO:    DB 5,"zero?"
SCNCONS:    DB 4,"cons"
SCNCAR:     DB 3,"car"
SCNCDR:     DB 3,"cdr"
SCNPAIR:    DB 5,"pair?"
SCNNULL:    DB 5,"null?"
SCNLIST:    DB 4,"list"
SCNEQ:      DB 3,"eq?"
SCNWRIT:    DB 5,"write"
SCNDISP:    DB 7,"display"
SCNNWL:     DB 7,"newline"
