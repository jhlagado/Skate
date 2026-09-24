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
SCSTAGE EQU 04EC0H               ; Leave a 256-byte guard before staged output.
SCIMG   EQU SCSTAGE+79           ; NOBJ image payload begins after its header.
SCCODE  EQU SCIMG+SRTLEN         ; Generated program follows the runtime image.
SCEND   EQU 09980H               ; The staged image ends exactly before compiler tables.
SCGENEND EQU SCEND-32             ; Leave room for the fixed NOBJ tail and CRC.
SCRECFR  EQU 0CE00H               ; Nested binding-list replay frames.
SCRECFSZ EQU 16                   ; One saved replay scope record.
SCRECEND EQU 0D820H               ; Replay workspace ends above the stack guard.

SCGKEYS  EQU 09980H              ; Two-byte interner IDs for package globals.
SCGSLOTS EQU 09B80H              ; One-byte slot number for each global ID.
SCLOCIDS EQU 09C80H              ; Two-byte IDs for active local bindings.
SCLOCSLT EQU 09D80H              ; Active local binding slot numbers.
SCBINDID EQU 09E00H              ; Two-byte IDs for pending let bindings.
SCBINDSL EQU 09F00H              ; Pending let binding slot numbers.
SCFIXTAB EQU 09F80H              ; Four-byte address/kind/slot fixup records.
SCNAMEDS EQU 0A480H              ; Symbol descriptor table for the reader.
SCNAMEPL EQU 0A840H              ; 4,800-byte symbol spelling pool.
SCSTRDS  EQU 0BB00H              ; String descriptor table required by RINIT.
SCSTRPL  EQU 0BC00H              ; String pool leaves room below procedure tables.
SCPMETA  EQU 0C000H              ; Procedure records stay outside reader tables.
SCLOCOWN EQU 0C400H              ; Owner procedure for each reusable local slot.
SCRECBND EQU 0C500H              ; Declaration flags for the active letrec range.
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
SCCNPT   EQU 0CC00H              ; End-jump patches for cond clauses.
SCNBASE  EQU 0CD00H              ; Saved cond patch-table bases by nesting depth.
SCNTOPS  EQU 0CD20H              ; Saved cond patch counts by nesting depth.
; Literal records and bytes use the compiler-only band below the private stack.
SCLITREC EQU 0D140H               ; Four bytes per copied symbol or string.
SCLITPL EQU 0D240H              ; One kilobyte of literal spelling storage.
SCLITOUT EQU 0D640H               ; Staged output address for each literal record.
SCLITPSZ EQU SCLITOUT-SCLITPL    ; Capacity check for copied literal spellings.
SCLITEND EQU 0D740H               ; End of the fixed compiler workspace.
SCWEND   EQU SCRECEND             ; Replay workspace ends at the guarded-stack floor.

; Compiler entry and terminal paths.
SCMAIN:
        LD HL,(6)                ; CP/M reports the transient-memory ceiling.
        LD DE,0E020H              ; Keep the compiler stack below CP/M's upper guard.
        OR A                      ; Clear carry before the ceiling comparison.
        SBC HL,DE                 ; Check the qualified TPA has the required guard.
        JP C,SCMEM                ; Refuse an installation with too little memory.
        LD SP,0E020H              ; Parser and emitter calls share this stack.
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
        LD (SCRECMOD),A           ; No recursive binding scope is active.
        LD (SCRECPHS),A           ; No recursive initializer is being read.
        LD (SCRECST),A            ; No recursive slot range has been opened.
        LD (SCRECPND),A           ; No deferred recursive initializer is pending.
        LD (SCREP),A              ; The source reader is not in replay mode.
        LD (SCRECFD),A            ; No retained binding scope is active.
        LD (SCRECAUT),A           ; No replay will switch back to a source stream.
        LD (SCBDEFIN),A           ; Package entry is not an internal-definition body.
        LD (SCISDEF),A            ; The current expression is not a definition.
        LD (SCCDTOP),A            ; No cond end jumps are pending.
        LD (SCCNDEP),A             ; No cond patch frame is active.
        LD (SCCNBASE),A            ; The first cond owns the start of the table.
        LD (SCIDMODE),A            ; Internal definitions use local procedure cells.
        LD HL,SCLOCEV              ; Clear escape flags from the previous source run.
        LD B,0                    ; DJNZ with zero performs all 256 byte writes.
SCSETEV:
        LD (HL),A
        INC HL
        DJNZ SCSETEV
        LD HL,SCRECBND             ; Clear recursive-binding declaration flags.
        LD B,0
SCSETREC:
        LD (HL),A
        INC HL
        DJNZ SCSETREC
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
        CALL IINIT                ; Prepare the string-literal interner used by RINIT.
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
        CALL SCNEXT                ; Read the next complete top-level event.
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
        CP 87H                     ; Binary16 source numerics carry a replay marker.
        JP Z,FNUM                  ; Emit their tag-zero payload unchanged.
        CP 5                       ; Symbol events carry an interned reference.
        JR Z,SCREF                 ; Resolve a local or package-global slot.
        CP 8                       ; String events become copied immutable literals.
        JP Z,SCSTRLIT
        CP 3                       ; Quote prefixes introduce literal data.
        JP Z,SCQSHRT              ; Read and emit the following quoted datum.
        CP 1                       ; An open parenthesis introduces a form.
        JP Z,SCFORM                ; Read the form's operator symbol and operands.
        JP SCSYN                   ; Strings, quote prefixes and bare punctuation fail.

; Read one fresh expression event from the reader.
SCEXPR:
        CALL SCNEXT                ; The caller has not consumed this expression.
        RET C                      ; Preserve the reader's latched error code.
        JP SCEXPE                  ; Dispatch the returned event.

SCNUM:
        LD A,(RTAG)                ; Reader tag zero is the boolean scalar form.
        OR A                       ; A zero tag selects the boolean emitter.
        JR NZ,SCNUMTAG              ; Exact integers carry their own logical tag.
        LD A,H                      ; Character scalars retain FFxx in their payload.
        CP 0FFH                     ; The lexer uses this reserved byte-character range.
        JP Z,SCCHAR                 ; Preserve the complete character value.
        JR SCBOOLV                  ; Remaining source scalars are booleans.
SCNUMTAG:
        CP 3                       ; Tag 3 is the exact signed-integer form.
        JP NZ,SCUNSUP              ; Other scalar tags are outside this increment.
        JP SCLIT                   ; Emit the integer payload and its tag.
SCSTRLIT:
        LD A,5                     ; Runtime tag five identifies string literals.
        JP SCLITADD
SCBOOLV:
        LD A,L                     ; Reader booleans arrive as zero or one.
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
        JP SCRRFWD                  ; Reserve recursive forward names or use globals.
SCRRFWD:
        LD A,(SCRECMOD)             ; Only a recursive initializer may reserve a cell.
        OR A
        JR Z,SCGGETP                ; Ordinary unresolved names become globals.
        LD A,(SCRECPHS)
        OR A
        JR Z,SCGGETP                ; The recursive body has a closed binding range.
        CALL SCRECREF                ; Reserve a bounded forward local cell.
        RET C
        LD L,A
        LD A,1
        JP SCLOAD                    ; Read the cell through the local path.
SCGGETP:
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
        CALL SCNEXT                ; Every supported form begins with a symbol.
        RET C                      ; Propagate a reader source failure.
        CP 1                       ; A list operator is a computed procedure value.
        JP Z,SCAPLIST              ; Compile it before reading application arguments.
        CP 5                       ; Event kind five is an interned symbol.
        JP NZ,SCOPRSYN             ; Scalar literals cannot be operators.
        LD (SCOPID),HL             ; Preserve the complete identity for fallback.
        LD A,(SCBDEFIN)             ; Save whether this body still accepts definitions.
        LD (SCBDSAV),A
        XOR A                       ; Nested forms must not inherit that permission.
        LD (SCBDEFIN),A
        XOR A                       ; Clear the per-expression definition marker.
        LD (SCISDEF),A
        LD DE,SCDEF                ; Compare the spelling with the define keyword.
        CALL SCMATCH               ; The lexer buffer remains valid until RNEXT.
        JP Z,SCDEFSEL              ; Select a package or leading internal definition.
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
        LD DE,SCLETREC             ; Compare with mutually recursive bindings.
        CALL SCMATCH               ; All letrec names share one initialized scope.
        JP Z,SCLETRF               ; Compile letrec with forward local slots.
        LD DE,SCCOND               ; Compare with the multi-clause conditional form.
        CALL SCMATCH               ; cond clauses are tested from left to right.
        JP Z,SCCONDF               ; Compile each clause and its fall-through.
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
        LD DE,SCCALEC              ; Compare with the bounded escape form.
        CALL SCMATCH               ; call/ec receives one procedure expression.
        JP Z,SCCALEF
        JP SCAPNAME                ; Other names are ordinary procedure values.

; Compile a computed operator list and continue with its argument sequence.
SCAPLIST:
        LD A,(SCTCTX)              ; The computed operator still has arguments to read.
        PUSH AF                    ; Save the surrounding tail context for the caller.
        XOR A                      ; Operator evaluation is always non-tail position.
        LD (SCTCTX),A
        LD A,1                     ; SCFORM reached this path with an opening-list event.
        CALL SCEXPE                ; Compile the computed operator in value position.
        JR C,SCAPLSTE             ; Restore the tail context after a nested failure.
        POP AF                     ; Recover the enclosing application's tail context.
        LD (SCTCTX),A
        CALL SCPUSH                ; Keep the computed callee below its arguments.
        RET C
        XOR A                      ; A computed operator uses the ordinary call path.
        LD (SCAPMODE),A            ; Do not inherit a surrounding primitive marker.
        JP SCAPARGS               ; The outer form supplies the arguments.
SCAPLSTE:
        POP AF                     ; Remove the saved context before reporting failure.
        LD (SCTCTX),A
        SCF                        ; Preserve the nested operator diagnostic.
        RET

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

; Select a package definition or a leading definition inside a procedure body.
SCDEFSEL:
        LD A,(SCTOP)               ; Package-level permission is saved per form.
        OR A
        JP NZ,SCDEFINE             ; Top-level definitions retain global storage.
        LD A,(SCBDSAV)             ; A body may accept definitions only at its head.
        OR A
        JP NZ,SCIDEF               ; Internal definitions use recursive local slots.
        JP SCDEFSYN                ; Definitions in an expression are malformed.

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
        CALL SCNEXT                ; A close means the optional alternative is absent.
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

; Compile a sequence of cond clauses.  Each ordinary clause branches to the
; next test when false and records one end jump for the common result address.
SCCONDF:
        LD A,(SCTCTX)              ; Clauses inherit the surrounding tail state.
        PUSH AF                    ; Keep it below all nested expression frames.
        CALL SCCNOPEN              ; Give this cond a private patch-table frame.
        JP C,SCNOPEN                ; Reject a nesting depth beyond the patch bound.
SCCNCLA:
        CALL SCNEXT                ; Read a clause or the outer closing parenthesis.
        JP C,SCCNERR
        CP 2
        JP Z,SCCNEMP               ; No matching clause yields unspecified.
        CP 1
        JP NZ,SCCNERR              ; Every clause is a parenthesised list.
        CALL SCNEXT                ; The first item is either a test or else.
        JP C,SCCNERR
        LD (SCBEV),A               ; Save the event while checking the else spelling.
        LD (SCBVAL),HL
        LD A,(RTAG)
        LD (SCBTAG),A
        LD A,(SCBEV)
        CP 5
        JP NZ,SCCNTEST             ; Non-symbol events are ordinary test expressions.
        LD DE,SCELSE
        CALL SCMATCH
        JP Z,SCCNELSE              ; Else is accepted only as the final clause.
SCCNTEST:
        CALL SCCNCTX               ; Restore the enclosing tail state for this clause.
        XOR A                      ; The test itself is never in tail position.
        LD (SCTCTX),A
        LD A,(SCBTAG)
        LD (RTAG),A
        LD A,(SCBEV)
        LD HL,(SCBVAL)
        CALL SCEXPE                ; Compile the test expression already read.
        JP C,SCCNERR
        LD HL,SRTFAL
        CALL SCCALL                ; Z means that the test value is #f.
        CALL SCJZ                  ; Save the false path until this clause closes.
        JP C,SCCNERR
        CALL SCBRPUSH
        JP C,SCCNERR
        CALL SCCNCTX               ; Clause results inherit the cond tail state.
        CALL SCBODY                ; Read result expressions through the clause close.
        JP C,SCCNERR
        CALL SCJP                  ; A selected clause skips the remaining tests.
        JP C,SCCNERR
        CALL SCCNADD               ; Save the common-end patch address.
        JP C,SCCNERR
        LD HL,(SCPC)               ; The next clause begins at this output address.
        CALL SCABS
        CALL SCBRPAT               ; Resolve the false path to the next test.
        JP C,SCCNERR
        JP SCCNCLA

; Compile the final else clause and require the outer cond close immediately.
SCCNELSE:
        CALL SCCNCTX               ; Else result expressions inherit tail state.
        CALL SCBODY
        JP C,SCCNERR
        CALL SCNEXT
        JP C,SCCNERR
        CP 2
        JP NZ,SCCNERR              ; Else must be the final clause.
        JP SCCNDONE

SCCNEMP:
        CALL SCUNS                  ; No clause matched, including an empty cond.
SCCNDONE:
        LD HL,(SCPC)
        CALL SCABS
        CALL SCCNPTCH              ; Point every selected clause at the result.
        POP AF                     ; Restore the surrounding tail context.
        LD (SCTCTX),A
        XOR A
        RET

; Restore the saved cond tail context without consuming its stack word.
SCCNCTX:
        POP DE                    ; Move the helper return below the saved context.
        POP AF                    ; Read the enclosing cond tail context.
        LD (SCTCTX),A
        PUSH AF                   ; Leave the saved context for the cond's final restore.
        PUSH DE                   ; Restore the helper continuation above it.
        RET

; Open a nested cond patch frame while retaining every outer frame's records.
SCCNOPEN:
        LD A,(SCCNDEP)
        CP 32
        JP NC,SCCAP
        LD L,A
        LD H,0
        LD DE,SCNBASE
        ADD HL,DE
        LD A,(SCCNBASE)
        LD (HL),A
        LD A,(SCCNDEP)
        LD L,A
        LD H,0
        LD DE,SCNTOPS
        ADD HL,DE
        LD A,(SCCDTOP)
        LD (HL),A
        LD A,(SCCNBASE)
        LD B,A
        LD A,(SCCDTOP)
        ADD A,B
        CP 64
        JP NC,SCCAP
        LD (SCCNBASE),A
        XOR A
        LD (SCCDTOP),A
        LD A,(SCCNDEP)
        INC A
        LD (SCCNDEP),A
        RET

; Restore the enclosing cond frame after a syntax or capacity failure.
SCNABORT:
        LD A,(SCCNDEP)
        DEC A
        LD (SCCNDEP),A
        LD L,A
        LD H,0
        LD DE,SCNBASE
        ADD HL,DE
        LD A,(HL)
        LD (SCCNBASE),A
        LD A,(SCCNDEP)
        LD L,A
        LD H,0
        LD DE,SCNTOPS
        ADD HL,DE
        LD A,(HL)
        LD (SCCDTOP),A
        RET

; Save one unconditional end-jump patch in the bounded cond table.
SCCNADD:
        LD (SCBPTMP),HL
        LD A,(SCCDTOP)
        CP 64
        JP NC,SCCAP
        LD C,A
        LD A,(SCCNBASE)
        ADD A,C
        CP 64
        JP NC,SCCAP
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCCNPT
        ADD HL,DE
        LD DE,(SCBPTMP)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(SCCDTOP)
        INC A
        LD (SCCDTOP),A
        OR A
        RET

; Patch all recorded cond end jumps to the absolute address in HL.
SCCNPTCH:
        LD (SCBTARG),HL
        LD A,(SCCDTOP)
        LD B,A
SCCNPLP:
        LD A,B
        OR A
        JP Z,SCCNPDN
        DEC B
        LD A,B
        LD C,A
        LD A,(SCCNBASE)
        ADD A,C
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SCCNPT
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD DE,(SCBTARG)
        CALL SCPATCH
        JP SCCNPLP
SCCNPDN:
        LD A,(SCCNDEP)
        DEC A
        LD (SCCNDEP),A
        LD L,A
        LD H,0
        LD DE,SCNBASE
        ADD HL,DE
        LD A,(HL)
        LD (SCCNBASE),A
        LD A,(SCCNDEP)
        LD L,A
        LD H,0
        LD DE,SCNTOPS
        ADD HL,DE
        LD A,(HL)
        LD (SCCDTOP),A
        XOR A
        RET

SCCNERR:
        CALL SCNABORT
        POP AF                     ; Restore the caller's tail context on failure.
        LD (SCTCTX),A
        SCF
        RET

SCNOPEN:
        POP AF                     ; Restore the caller's tail context.
        LD (SCTCTX),A
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
        LD A,(SCRECST)             ; Preserve any enclosing recursive slot range.
        PUSH AF
        LD A,(SCRECLIM)            ; Preserve its recursive range limit.
        PUSH AF
        LD A,(SCRECPR)             ; Preserve its owning procedure.
        PUSH AF
        LD A,(SCRECPND)            ; Preserve its deferred-record marker.
        PUSH AF
        LD A,(SCRECPHS)            ; Preserve its initializer phase.
        PUSH AF
        LD A,(SCRECMOD)            ; Preserve its recursive-scope mode.
        PUSH AF
        LD A,(SCBDEFIN)            ; Preserve the enclosing definition permission.
        PUSH AF
        PUSH DE                    ; Restore the caller return above the frame.
        LD A,(SCTCTX)              ; The incoming context belongs to this body.
        LD (SCBTAIL),A             ; Only a final expression keeps this flag.
        LD A,(SCBISOL)             ; Record whether this body owns a private list.
        LD (SCBMODE),A
        XOR A                      ; Nested begin and let bodies share their list.
        LD (SCBISOL),A
        LD A,(SCRECMOD)             ; Keep a recursive initializer phase through lambdas.
        OR A
        JR NZ,SCBKEEPR              ; letrec/internal-definition lambdas need forwards.
        XOR A                      ; Ordinary bodies close the outer initializer phase.
        LD (SCRECPHS),A             ; No forward cells are created after initialization.
SCBKEEPR:
        LD A,(SCBMODE)              ; Only a procedure-owned body accepts defines.
        LD (SCBDEFIN),A             ; Nested begin and cond bodies leave it clear.
        LD A,(SCBMODE)
        CP 1
        JR NZ,SCBKEEP              ; Shared and let bodies retain outer candidates.
        XOR A                      ; A procedure body starts a private candidate list.
        LD (SCTTOP),A
SCBKEEP:
        XOR A                      ; Start with no expressions in this body.
        LD (SCBODYN),A             ; Empty bodies remain a syntax error.
        LD A,(SCBMODE)             ; Procedure bodies may begin with definitions.
        OR A
        JR Z,SCBDEFNO
        CALL SCDEFCAP              ; Install the leading names before replay.
        JP C,SCBFAIL
SCBDEFNO:
SCBREAD:
        CALL SCNEXT                ; Read one body expression or its closing parenthesis.
        JR NC,SCBRDOK
        JP SCBFAIL                 ; Restore the frame after a reader failure.
SCBRDOK:
        CP 2                       ; A close before an expression is invalid.
        JR NZ,SCBRNCL
        JP SCBFAIL                 ; Report an empty body after balanced cleanup.
SCBRNCL:
        OR A                       ; EOF cannot close an open body.
        JR NZ,SCBRNEOF
        JP SCBFAIL                 ; Report an incomplete body after cleanup.
SCBRNEOF:
        LD (SCBEV),A               ; Preserve the event until SCEXPE dispatches it.
        LD (SCBVAL),HL             ; Preserve the event payload.
        LD A,(RTAG)                ; Preserve its scalar tag.
        LD (SCBTAG),A              ; Structural events ignore this field.
SCBEXPR:
        XOR A                      ; A definition marker belongs only to SCIDEF.
        LD (SCISDEF),A
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
        LD A,(SCISDEF)              ; Definitions do not count as body expressions.
        OR A
        JP NZ,SCBDEFOK
        XOR A                      ; The first ordinary expression seals definitions.
        LD (SCBDEFIN),A
        LD (SCRESV),HL             ; Save the expression result before reading ahead.
        LD (SCREST),A              ; Preserve its tag across the reader call.
        LD A,(SCBODYN)             ; Count the completed body expression.
        INC A
        LD (SCBODYN),A
        CALL SCNEXT                ; The next event distinguishes final from non-final.
        JR NC,SCBNXOK
        JP SCBFAIL                 ; The expression result is discarded on source failure.
SCBNXOK:
        CP 2                       ; A close leaves the preceding expression final.
        JP Z,SCBFINAL              ; Leave tail wrappers intact for the final value.
        OR A                       ; EOF cannot terminate a body.
        JR NZ,SCBNXEOF
        JP SCBFAIL                 ; Reject an incomplete body.
SCBNXEOF:
        LD (SCBEV),A               ; Save the next expression while rewriting candidates.
        LD (SCBVAL),HL             ; Preserve its payload across SCTFIX.
        LD A,(RTAG)                ; Preserve its logical scalar tag.
        LD (SCBTAG),A
        CALL SCTFIX                ; Non-final tail calls become ordinary calls.
        JR NC,SCBTFOK
        JP SCBFAIL
SCBTFOK:
        JP SCBEXPR                ; Compile the saved next event without rereading.
SCBDEFOK:
        JP SCBREAD                 ; Continue through the leading definition region.
SCBFINAL:
        LD HL,(SCRESV)             ; Recover the final expression payload.
        LD A,(SCREST)              ; Recover its final expression tag.
        CALL SCBREST               ; Restore caller scratch and the continuation.
        LD HL,(SCRESV)             ; Restore the body value after frame cleanup.
        LD A,(SCREST)              ; Restore the body tag after frame cleanup.
        OR A                       ; Return carry clear with the final value.
        RET
SCBFAIL:
        LD A,(SCRECAUT)             ; An unfinished definition replay owns a frame.
        OR A
        JR Z,SCBFAILR
        CALL SCRECPOP
SCBFAILR:
        CALL SCBREST               ; Restore all body fields and the continuation.
        SCF                        ; Preserve the reader or expression failure.
        RET                        ; No partially compiled body is accepted.

; Restore one saved body frame.  The helper is called with its frame on top.
SCBREST:
        POP BC                     ; Save the continuation after this helper call.
        POP DE                     ; Recover the caller continuation below the frame.
        POP AF                     ; Restore leading-definition permission.
        LD (SCBDEFIN),A
        POP AF                     ; Restore the enclosing recursive mode.
        LD (SCRECMOD),A
        POP AF                     ; Restore the enclosing recursive phase.
        LD (SCRECPHS),A
        POP AF                     ; Restore the enclosing deferred-record marker.
        LD (SCRECPND),A
        POP AF                     ; Restore the enclosing owning procedure.
        LD (SCRECPR),A
        POP AF                     ; Restore the enclosing recursive range limit.
        LD (SCRECLIM),A
        POP AF                     ; Restore the enclosing recursive-range start.
        LD (SCRECST),A
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
        CP 1
        JR NZ,SCBKEEPT
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
