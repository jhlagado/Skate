; Scope compiler driver and expression dispatch.
;
; This module owns startup, source-package handling, scalar values and
; symbol resolution before named forms take over.

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

; The compiler keeps a bounded replay window in the old image band.  Generated
; addresses are logical COM addresses and are streamed to the ASO stage.
SCSTAGE EQU 05800H               ; Replay window leaves a full page after compiler code.
SCIMG   EQU SCSTAGE              ; Window storage is reused by the materializer.
SCCODE  EQU 0100H+SRTLEN         ; Generated program follows the runtime image.
SCEND   EQU 09980H               ; Replay window ends before compiler tables.
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
        CALL SCPRECOV              ; Recover stale stages before opening the spool.
        JR C,SCREFAIL              ; A recovery failure has no source location.
        CALL SCSETUP              ; Clear tables and load the checked runtime provider.
        JP C,SCFAIL               ; Refuse to parse when the provider was not loaded.
        CALL SCPACK               ; Read the source package and emit native code.
        JP C,SCFAIL               ; No output is opened until parsing succeeds.
        LD A,1                    ; Subsequent failures are finalisation/publication.
        LD (SCPHASE),A            ; Do not mislabel generated-image errors as source.
        CALL SCFIN                ; Resolve slots and append the complete image.
        JP C,SCFAIL               ; Reject an image that crosses a measured bound.
        CALL SCOUT                ; Publish checked COM and ASO files.
        JP C,SCFAIL               ; Report a transport or publication failure.
        LD DE,SCOKTXT             ; Successful compilation message.
        JP SCPRINT                ; Print it and return to CP/M.
SCREFAIL:
        LD A,1                     ; Recovery failure has no source location.
        LD (SCPHASE),A             ; Force the plain output diagnostic path.
        CALL SCPRECER               ; Select OUTPUT ERROR and close any stream.
        JP SCFAIL                   ; Do not start a new transaction after uncertainty.
SCFAIL:
        JP SCDIAG                  ; Close input and print the selected diagnostic.
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
        LD (SCROLLF),A            ; No publication rollback is active at setup.
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
        LD A,1
        LD (CSPEND),A              ; No source cursor exists before CSOPEN.
        XOR A
        LD (SCPHASE),A            ; Parse phase remains active through SCPACK.
        LD A,0FFH                 ; Top-level locals have no procedure owner.
        LD (SCCURPR),A            ; Nested lambdas replace this while compiling.
        LD HL,0100H               ; The ASO image starts at the CP/M load origin.
        LD (SCPC),HL              ; The cursor is a logical output address.
        XOR A
        LD (SCPCET),A             ; The cursor begins below the 17-bit endpoint.
        CALL SINKOPEN              ; Open SPL before the runtime and source streams.
        RET C                      ; A failed spool setup is a setup failure.
        CALL SCLOADRT              ; Stream the provider into the ASO image records.
        RET C                      ; A short, missing or unreadable provider is fatal.
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
