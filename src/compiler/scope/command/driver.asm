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
W_STAGE EQU 05800H               ; Replay window leaves a full page after compiler code.
W_IMAGE   EQU W_STAGE            ; Window storage is reused by the materializer.
W_GLB_SZ  EQU 1024               ; Four bytes for each of the 256 global slots.
; The global area follows the loaded runtime, whose length .SCAN selects, so
; its base is ST_GBASE rather than a constant; generated code follows it.
W_IMGEND   EQU 09980H            ; Replay window ends before compiler tables.
W_REPLAY  EQU 0CE00H              ; Nested binding-list replay frames.
W_REP_SZ EQU 16                   ; One saved replay scope record.
W_REPEND EQU 0D820H               ; Replay workspace ends above the stack guard.
W_GKEYS  EQU 09980H              ; Two-byte interner IDs for package globals.
W_GSLOTS EQU 09B80H              ; One-byte slot number for each global ID.
W_LKEYS EQU 09C80H               ; Two-byte IDs for active local bindings.
W_LSLOTS EQU 09D80H              ; Active local binding slot numbers.
W_BKEYS EQU 09E00H               ; Two-byte IDs for pending let bindings.
W_BSLOTS EQU 09F00H              ; Pending let binding slot numbers.
W_FIXUPS EQU 09F80H              ; Four-byte address/kind/slot fixup records.
W_SYMTAB EQU 0A480H              ; Symbol descriptor table for the reader.
W_SYMBUF EQU 0A840H              ; 4,800-byte symbol spelling pool.
W_STRTAB  EQU 0BB00H             ; String descriptor table required by RD_INIT.
W_STRBUF  EQU 0BC00H             ; String pool leaves room below procedure tables.
W_PBASE  EQU 0C000H              ; Procedure tables stay outside reader tables.
W_PDESC  EQU 0C000H              ; Emitted descriptor address for each procedure.
W_PARITY EQU 0C100H              ; Published arity byte for each procedure.
W_POPEN  EQU 0C180H              ; Procedure index of each open metadata record.
W_PRECS  EQU 0C190H              ; Metadata records for the open procedures.
W_PTMP   EQU 0C3CCH              ; Scratch record for a lookup of a closed index.
W_PROC_N  EQU 128                ; Procedures per program.
W_OPEN_N  EQU 13                 ; Procedures open at once (nesting depth).
W_LOWNER EQU 0C400H              ; Owner procedure for each reusable local slot.
W_DECLS EQU 0C500H               ; Declaration flags for the active letrec range.
W_PRECSZ   EQU 44                ; Body, arity, slots and two 128-bit masks.
W_OWNOFF  EQU 12                 ; Owned-slot mask begins after four formals.
W_CAPOFF  EQU 28                 ; Captured-slot mask follows the owned mask.
W_MASKSZ  EQU 16                 ; One mask covers the 128 local slots.
W_ESCAPE  EQU 0C600H             ; One escape flag belongs to each local slot.
W_BODY EQU 0C700H                ; Nested body lookahead records use this area.
W_BODYSZ   EQU 9                 ; Cursors, owner and procedure patch state.
W_BODY_N  EQU 28                 ; 28 records of W_BODYSZ bytes end below W_GPRIM.
W_GPRIM  EQU 0C800H              ; One predefined-primitive kind per global slot.
W_BRANCH EQU 0C900H              ; Generic short-circuit branch patch stack.
W_IFALSE EQU 0CA00H              ; False-branch patch words for nested if forms.
W_IFEND  EQU 0CA80H              ; End-branch patch words for nested if forms.
W_TCALLS EQU 0CB00H              ; Tail-call target words awaiting body closure.
W_TAILOP  EQU 0CB80H             ; One flag records a saved side-stack operator.
W_TAIL_N   EQU 64                 ; Tail candidates per body expression scope.
W_CONDS   EQU 0CC00H             ; End-jump patches for cond clauses.
W_CBASES  EQU 0CD00H             ; Saved cond patch-table bases by nesting depth.
W_CTOPS  EQU 0CD20H              ; Saved cond patch counts by nesting depth.
; Literal records and bytes use the compiler-only band below the private stack.
W_LITREC EQU 0D140H               ; Four bytes per copied symbol or string.
W_LITBUF EQU 0D240H             ; One kilobyte of literal spelling storage.
W_LITOUT EQU 0D640H               ; Staged output address for each literal record.
W_LITCAP EQU W_LITOUT-W_LITBUF   ; Capacity check for copied literal spellings.
W_LITEND EQU 0D740H               ; End of the fixed compiler workspace.
W_END   EQU W_REPEND              ; Replay workspace ends at the guarded-stack floor.

; Compiler entry and terminal paths.
CMD_MAIN:
        LD HL,(6)                ; CP/M reports the transient-memory ceiling.
        LD DE,0E020H              ; Keep the compiler stack below CP/M's upper guard.
        OR A                      ; Clear carry before the ceiling comparison.
        SBC HL,DE                 ; Check the qualified TPA has the required guard.
        JP C,.MEMORY              ; Refuse an installation with too little memory.
        LD SP,0E020H              ; Parser and emitter calls share this stack.
        CALL SCPRECOV              ; Recover stale stages before opening the spool.
        JR C,.RECOVERY             ; A recovery failure has no source location.
        CALL CMD_INIT             ; Clear tables and load the checked runtime provider.
        JP C,.FAIL                ; Refuse to parse when the provider was not loaded.
        CALL CMD_PASS             ; Read the source package and emit native code.
        JP C,.FAIL                ; No output is opened until parsing succeeds.
        LD A,1                    ; Subsequent failures are finalisation/publication.
        LD (ST_PHASE),A           ; Do not mislabel generated-image errors as source.
        CALL SCFIN                ; Resolve slots and append the complete image.
        JP C,.FAIL                ; Reject an image that crosses a measured bound.
        CALL SCOUT                ; Publish checked COM and ASO files.
        JP C,.FAIL                ; Report a transport or publication failure.
        LD DE,M_OK                ; Successful compilation message.
        JP CMD_QUIT               ; Print it and return to CP/M.
.RECOVERY:
        LD A,1                     ; Recovery failure has no source location.
        LD (ST_PHASE),A            ; Force the plain output diagnostic path.
        CALL SCPRECER               ; Select OUTPUT ERROR and close any stream.
.FAIL:
        JP DIAG_OUT                ; Close input and print the selected diagnostic.
.MEMORY:
        LD DE,M_MEMORY             ; Memory guard failure is distinct to the user.

CMD_QUIT:
        LD C,9                     ; CP/M function 9 prints a dollar-terminated string.
        CALL 5                     ; Use the platform BDOS vector.
        JP 0                       ; Warm start after either result.

; Initialise reader contexts, compiler tables and the staged runtime image.
CMD_INIT:
        XOR A                     ; Reset global and local allocation cursors.
        LD (ST_GLOBS),A           ; Low byte of the 16-bit global count.
        LD (ST_GLOBS+1),A         ; High byte remains zero until all 256 slots exist.
        LD (ST_LTOP),A            ; No local binding is active at package entry.
        LD (ST_LNEXT),A           ; Local slot zero is the first available slot.
        LD (ST_LMAX),A            ; No local data extent has been observed yet.
        LD (ST_FORMS),A           ; No package-level result exists at setup.
        LD (ST_FORMS+1),A         ; The form count is a complete little-endian word.
        LD (ST_FIXES),A           ; No address fixups have been recorded.
        LD (ST_FIXES+1),A         ; The count is wide enough for the global target.
        LD (ST_BRTOP),A           ; No short-circuit branch is pending.
        LD (ST_IFTOP),A           ; No if form is being compiled.
        LD (ST_BINDS),A          ; No pending let binding is retained.
        LD (ST_PROCS),A           ; No procedure descriptor has been allocated.
        LD (ST_PNEST),A           ; No procedure metadata record is open.
        LD (ST_DESC),A            ; No descriptor is awaiting its body address.
        LD (ST_ARGS),A            ; No generic application argument is pending.
        LD (ST_ROUTE),A           ; No compact global-call marker is active.
        LD (SCROLLF),A            ; No publication rollback is active at setup.
        LD (ST_TAIL),A            ; Top-level expressions are not tail calls.
        LD (ST_CHECK),A       ; Stores initialize bindings until set! selects checks.
        LD (ST_TAILS),A           ; No pending tail-call target words exist.
        LD (SCLITN),A             ; No copied symbol or string literals exist yet.
        LD (SCLITUSE),A           ; The literal byte pool starts empty.
        LD (SCLITUSE+1),A
        LD (SCQCNT),A             ; No quoted-list cache cells are reserved yet.
        LD (SCQCOUNT),A            ; No quoted-list elements are pending.
        LD (SCQENC),A              ; No quoted list is being encoded.
        LD (SCQDOT),A              ; No dotted-list marker is active.
        LD (ST_BNEST),A           ; No compiler lambda frame is active.
        LD (ST_BMODE),A           ; No body is isolating its tail candidates.
        LD (ST_ALONE),A           ; Nested body forms propagate candidates by default.
        LD (ST_RMODE),A           ; No recursive binding scope is active.
        LD (ST_RINIT),A           ; No recursive initializer is being read.
        LD (ST_RBASE),A           ; No recursive slot range has been opened.
        LD (ST_RPEND),A           ; No deferred recursive initializer is pending.
        LD (ST_PLAY),A            ; The source reader is not in replay mode.
        LD (ST_PLAYN),A           ; No retained binding scope is active.
        LD (ST_BACK),A            ; No replay will switch back to a source stream.
        LD (ST_BDEF),A            ; Package entry is not an internal-definition body.
        LD (ST_ISDEF),A           ; The current expression is not a definition.
        LD (ST_CONDS),A           ; No cond end jumps are pending.
        LD (ST_CNEST),A            ; No cond patch frame is active.
        LD (ST_CBASE),A            ; The first cond owns the start of the table.
        LD (ST_INPKG),A            ; Internal definitions use local procedure cells.
        LD HL,W_ESCAPE             ; Clear escape flags from the previous source run.
        LD B,0                    ; DJNZ with zero performs all 256 byte writes.
.ESCAPES:
        LD (HL),A
        INC HL
        DJNZ .ESCAPES
        LD HL,W_DECLS              ; Clear recursive-binding declaration flags.
        LD B,0
.DECLS:
        LD (HL),A
        INC HL
        DJNZ .DECLS
        LD HL,W_GPRIM              ; Clear predefined-primitive marks as well.
        LD B,0
.PRIMS:
        LD (HL),A
        INC HL
        DJNZ .PRIMS
        LD HL,M_ERROR             ; Use the ordinary diagnostic by default.
        LD (ST_ERROR),HL          ; Body diagnostics may replace this pointer.
        LD A,1
        LD (SRC_PEND),A            ; No source cursor exists before SRC_OPEN.
        XOR A
        LD (ST_PHASE),A           ; Parse phase remains active through CMD_PASS.
        LD A,0FFH                 ; Top-level locals have no procedure owner.
        LD (ST_PROC),A            ; Nested lambdas replace this while compiling.
        LD HL,0100H               ; The ASO image starts at the CP/M load origin.
        LD (ST_PC),HL             ; The cursor is a logical output address.
        XOR A
        LD (ST_PCHI),A            ; The cursor begins below the 17-bit endpoint.
        CALL SINKOPEN              ; Open SPL before the runtime and source streams.
        RET C                      ; A failed spool setup is a setup failure.
        LD IX,ST_SYMS             ; Select the symbol interner context.
        CALL SYM_INIT             ; Validate and clear its descriptor counters.
        RET C                     ; A bad high-memory table is a setup failure.
        LD IX,ST_STRS             ; Select the string context required by RD_INIT.
        CALL SYM_INIT             ; The current language rejects string events.
        RET C                     ; Preserve the reader's ordinary setup diagnostic.
        CALL .SCAN                 ; Choose how much of the runtime to load.
        CALL RT_COPY               ; Stream the provider into the ASO image records.
        RET C                      ; A short, missing or unreadable provider is fatal.
        LD HL,(ST_RTLEN)           ; The global area follows the loaded runtime.
        LD DE,0100H
        ADD HL,DE
        LD (ST_GBASE),HL
        LD BC,W_GLB_SZ             ; Reserve the global area before any code, so
.GLOBALS:                          ; every global address is a constant.
        XOR A                      ; Unused and ordinary slots stay unbound.
        CALL SINKBYTE              ; SINKBYTE preserves BC.
        RET C
        DEC BC
        LD A,B
        OR C
        JR NZ,.GLOBALS
        RET                       ; Return with all compiler state initialised.

; Read the whole source once before compiling it and choose the runtime prefix
; to load: the core alone, the core and the standard-procedure module, or the
; whole runtime with the I/O module.  A standard procedure or case needs the
; standard module; read or a file opener needs the I/O module, which follows
; it.  A source or syntax error selects the whole runtime; the compiling pass
; reports the error.  Symbols interned here are found again by that pass.
.SCAN:
        LD HL,SRTLCORE
        LD (ST_RTLEN),HL
        LD HL,005CH                ; The same source the compiling pass opens.
        CALL SRC_OPEN
        JR C,.FULL
        LD HL,SRC_BYTE
        LD DE,ST_SYMS
        LD BC,ST_STRS
        CALL RD_INIT
        JR C,.FULL
.NEXT:
        CALL RD_NEXT
        JR C,.FULL
        OR A
        JR Z,.DONE                 ; The end of the source.
        CP 5
        JR NZ,.NEXT                ; Only symbols name procedures.
        LD (ST_SYMID),HL
        LD DE,K_CASE               ; case compares with STD_CASE.
        CALL CMD_SAME
        JR Z,.STD
        CALL SCPLOOK               ; A is the primitive kind, or zero.
        CP 61
        JR NC,.STD                 ; Kinds 61 and up are standard procedures.
        CP 54
        JR Z,.FULL                 ; read.
        CP 56
        JR C,.NEXT
        CP 60
        JR NC,.NEXT
.FULL:
        LD HL,SRTLEN               ; Kinds 56..59 open files.
        LD (ST_RTLEN),HL
        JR .DONE
.STD:
        LD HL,SRTLSTD
        LD (ST_RTLEN),HL
        JR .NEXT                   ; Keep looking for the I/O module.
.DONE:
        CALL SRC_END               ; The compiling pass opens the source again.
        LD HL,M_ERROR              ; A scan error must not select a diagnostic.
        LD (ST_ERROR),HL
        RET

; Open the source FCB, attach the production reader and consume top-level forms.
CMD_PASS:
        LD HL,005CH               ; CCP places the command-tail FCB here.
        CALL SRC_OPEN             ; Install the source stream callback.
        JR NC,.OPENED             ; Continue only when the source opened cleanly.
        SCF                       ; Preserve the source-I/O failure for .FAIL.
        RET                       ; No generated output exists yet.
.OPENED:
        LD HL,SRC_BYTE             ; Reader callback returns one source byte.
        LD DE,ST_SYMS              ; Reader owns the symbol context.
        LD BC,ST_STRS              ; Reader owns the string context.
        CALL RD_INIT               ; Reset lexer and structural reader state.
        RET C                      ; Treat a reader setup fault as a parse failure.
.LOOP:
        CALL SCNEXT                ; Read the next complete top-level event.
        RET C                      ; The reader latches its source diagnostic.
        OR A                       ; Event zero is the only valid package terminator.
        JR Z,.FINISH               ; The caller closes the source before output.
        LD B,A                     ; Preserve the event kind across the top flag.
        LD A,1                     ; Definitions are legal only at package level.
        LD (ST_ALLOW),A            ; CMD_FORM consumes and clears this permission.
        LD A,B                     ; Recover the top-level event kind.
        CALL CMD_EXPR              ; Compile the event and leave its value in A/HL.
        JP NC,.COUNT                ; Continue after a complete top-level form.
        RET                        ; Stop at the first syntax or capacity error.
.COUNT:
        LD HL,(ST_FORMS)           ; Count successful top-level forms as a word.
        INC HL                     ; An empty package has no value to return.
        LD (ST_FORMS),HL           ; Do not wrap after 256 definitions.
        JR .LOOP                 ; Continue until the reader returns EOF.

; Finish a nonempty package with the return instruction used by RT_CALL.
.FINISH:
        CALL SRC_END               ; A missing, unreadable or bad part is an error.
        RET C                      ; DIAG_OUT selects the source diagnostic.
        LD HL,(ST_FORMS)           ; Reject an empty source before publication.
        LD A,H                     ; Test both bytes of the form count.
        OR L                       ; A zero count has no result for OUT_SHOW.
        JP Z,ERR_END               ; Report the same syntax error as other empties.
        JP EM_RET                  ; Append RET and return to the command driver.

; Parse one event already returned in A; literal payloads remain in RD_TAG:HL.
CMD_EXPR:
        CP 7                       ; Numeric events use the scalar payload contract.
        JR Z,CMD_NUM               ; Emit an exact integer literal.
        CP 87H                     ; Binary16 source numerics carry a replay marker.
        JP Z,EM_FLOAT              ; Emit their tag-zero payload unchanged.
        CP 5                       ; Symbol events carry an interned reference.
        JR Z,CMD_REF               ; Resolve a local or package-global slot.
        CP 8                       ; String events become copied immutable literals.
        JP Z,CMD_STR
        CP 3                       ; Quote prefixes introduce literal data.
        JP Z,SCQSHRT              ; Read and emit the following quoted datum.
        CP 1                       ; An open parenthesis introduces a form.
        JP Z,CMD_FORM              ; Read the form's operator symbol and operands.
        JP ERR_BAD                 ; Strings, quote prefixes and bare punctuation fail.

; Read one fresh expression event from the reader.
CMD_NEXT:
        CALL SCNEXT                ; The caller has not consumed this expression.
        RET C                      ; Preserve the reader's latched error code.
        JP CMD_EXPR                ; Dispatch the returned event.

CMD_NUM:
        LD A,(RD_TAG)              ; Reader tag zero is the boolean scalar form.
        OR A                       ; A zero tag selects the boolean emitter.
        JR NZ,.TAGGED               ; Exact integers carry their own logical tag.
        LD A,H                      ; Character scalars retain FFxx in their payload.
        CP 0FFH                     ; The lexer uses this reserved byte-character range.
        JP Z,EM_CHAR                ; Preserve the complete character value.
        JR CMD_BOOL                 ; Remaining source scalars are booleans.
.TAGGED:
        CP 3                       ; Tag 3 is the exact signed-integer form.
        JP NZ,ERR_TODO             ; Other scalar tags are outside this increment.
        JP EM_INT                  ; Emit the integer payload and its tag.
CMD_STR:
        LD A,5                     ; Runtime tag five identifies string literals.
        JP SCLITADD
CMD_BOOL:
        LD A,L                     ; Reader booleans arrive as zero or one.
        JP EM_BOOL                 ; Emit the checked boolean representation.

; Resolve a symbol reference, preferring the innermost active local binding.
CMD_REF:
        LD (ST_SYMID),HL           ; Save the full interner ID across table searches.
        CALL SCLOCF                ; Search active locals before global classification.
        JR C,.LOCAL                ; A local slot shadows every global or primitive.
        CALL SCGHAS                 ; An explicit global binding takes precedence.
        JR C,.GLOBAL                ; Existing globals use the ordinary slot path.
        CALL SCPLOOK                ; Unbound primitive names can stay immediate.
        OR A
        JP NZ,EM_PRIM               ; Emit the predefined value without a slot.
        LD A,(ST_RMODE)             ; Only a recursive initializer may reserve a cell.
        OR A
        JR Z,.UNBOUND               ; Ordinary unresolved names become globals.
        LD A,(ST_RINIT)
        OR A
        JR Z,.UNBOUND               ; The recursive body has a closed binding range.
        LD A,(ST_PROC)              ; Inside a procedure body the name cannot be a
        INC A                       ; later binding of this scope: every recursive
        JR NZ,.UNBOUND              ; name is predeclared, so it is a global.
        CALL SCRECREF                ; Reserve a bounded forward local cell.
        RET C
        LD L,A
        LD A,1
        JP EM_LOAD                   ; Read the cell through the local path.
.UNBOUND:
        CALL SCGGET                ; Allocate a global slot on the first reference.
        RET C                      ; The 256-slot capacity is a compile diagnostic.
        LD L,A                     ; The emitter takes the slot number in L.
        XOR A                      ; Kind zero denotes a package-global slot.
        JP EM_LOAD                 ; Emit the checked runtime load and its fixup.
.GLOBAL:
        LD L,A                     ; SCGHAS returns the existing global slot in A.
        XOR A                      ; Kind zero denotes a package-global slot.
        JP EM_LOAD                 ; Emit the checked runtime load and its fixup.
.LOCAL:
        LD L,A                     ; SCLOCF returns the matching local slot number.
        LD A,1                     ; Kind one denotes a local slot.
        JP EM_LOAD                 ; Emit the checked runtime load and its fixup.
