; Scope compiler form dispatch and arithmetic applications.
;
; The dispatcher selects language forms; application and binary arithmetic
; keep their parser state here.

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
        LD DE,SCWHEN               ; when, unless and case are derived forms
        CALL SCMATCH               ; compiled directly rather than rewritten.
        JP Z,SCWHENF
        LD DE,SCUNLESS
        CALL SCMATCH
        JP Z,SCUNLSF
        LD DE,SCCASE
        CALL SCMATCH
        JP Z,SCCASEF
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
        LD (SCAPGSL),A             ; Mode three keeps the kind in the slot byte.
        LD A,3
        LD (SCAPMODE),A            ; The call names the primitive directly.
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
