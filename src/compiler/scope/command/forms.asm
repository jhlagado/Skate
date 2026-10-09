; Scope compiler form dispatch and arithmetic applications.
;
; The dispatcher selects language forms; application and binary arithmetic
; keep their parser state here.

; Read the operator symbol following an opening parenthesis and dispatch it.
CMD_FORM:
        LD HL,0                    ; Refuse a form that would leave less than
        ADD HL,SP                  ; 256 bytes of stack above the replay area.
        LD DE,W_REPEND+256
        OR A
        SBC HL,DE
        JP C,ERR_CAP
        LD A,(ST_ALLOW)            ; Save whether define is legal at this level.
        LD (ST_ATTOP),A            ; Nested forms clear the permission below.
        XOR A                      ; No nested definition may be accepted.
        LD (ST_ALLOW),A            ; Only the package loop grants this permission.
        CALL REC_NEXT              ; Every supported form begins with a symbol.
        RET C                      ; Propagate a reader source failure.
        CP 1                       ; A list operator is a computed procedure value.
        JP Z,.COMPUTED             ; Compile it before reading application arguments.
        CP 5                       ; Event kind five is an interned symbol.
        JP NZ,ERR_OP               ; Scalar literals cannot be operators.
        LD (ST_OPID),HL            ; Preserve the complete identity for fallback.
        LD A,(ST_BDEF)              ; Save whether this body still accepts definitions.
        LD (ST_BDSAV),A
        XOR A                       ; Nested forms must not inherit that permission.
        LD (ST_BDEF),A
        XOR A                       ; Clear the per-expression definition marker.
        LD (ST_ISDEF),A
        LD DE,K_DEFINE             ; Compare the spelling with the define keyword.
        CALL CMD_SAME              ; The lexer buffer remains valid until RD_NEXT.
        JP Z,.DEFINE               ; Select a package or leading internal definition.
        LD DE,K_IF                 ; Compare with the conditional form.
        CALL CMD_SAME              ; Match only complete identifier spellings.
        JP Z,IF_FORM               ; Emit the branch skeleton and both arms.
        LD DE,K_BEGIN              ; Compare with the sequencing form.
        CALL CMD_SAME              ; Begin consumes every expression to its close.
        JP Z,CMD_SEQ               ; Emit the last value of the sequence.
        LD DE,K_LET                ; Compare with parallel local bindings.
        CALL CMD_SAME              ; The body gets a fresh lexical slot region.
        JP Z,LET_FORM              ; Compile the binding list and body.
        LD DE,K_LETSEQ           ; Compare with sequential local bindings.
        CALL CMD_SAME              ; Each initializer sees the earlier bindings.
        JP Z,LET_STAR              ; Compile let* with the same slot discipline.
        LD DE,K_LETREC             ; Compare with mutually recursive bindings.
        CALL CMD_SAME              ; All letrec names share one initialized scope.
        JP Z,LET_REC               ; Compile letrec with forward local slots.
        LD DE,K_COND               ; Compare with the multi-clause conditional form.
        CALL CMD_SAME              ; cond clauses are tested from left to right.
        JP Z,IF_COND               ; Compile each clause and its fall-through.
        LD DE,K_WHEN               ; when, unless and case are derived forms
        CALL CMD_SAME              ; compiled directly rather than rewritten.
        JP Z,IF_WHEN
        LD DE,K_UNLESS
        CALL CMD_SAME
        JP Z,IF_NOT
        LD DE,K_CASE
        CALL CMD_SAME
        JP Z,IF_CASE
        LD DE,K_DO                 ; do is rewritten to a named let.
        CALL CMD_SAME
        JP Z,DO_FORM
        LD DE,K_INCL               ; Includes are read only before the first
        CALL CMD_SAME              ; ordinary form; a later one is an error,
        JP Z,ERR_BAD               ; not a call to an unbound name.
        LD DE,K_AND                ; Compare with the short-circuit conjunction.
        CALL CMD_SAME              ; The two operands are evaluated left to right.
        JP Z,IF_AND                ; Preserve the first false value.
        LD DE,K_OR                 ; Compare with the short-circuit disjunction.
        CALL CMD_SAME              ; The two operands are evaluated left to right.
        JP Z,IF_OR                 ; Preserve the first true value.
        LD DE,K_LAMBDA             ; Compare with lambda.
        CALL CMD_SAME              ; Lambda creates a fixed procedure descriptor.
        JP Z,LAM_FORM              ; Compile its formal list and body.
        LD DE,K_SET                ; Compare with set!.
        CALL CMD_SAME              ; Mutation updates an existing slot.
        JP Z,BIND_SET              ; Compile the target and new value.
        LD DE,K_QUOTE              ; Compare with the explicit quote form.
        CALL CMD_SAME              ; Quote consumes one datum without evaluation.
        JP Z,QUO_FORM
        LD DE,K_CALLEC             ; Compare with the bounded escape form.
        CALL CMD_SAME              ; call/ec receives one procedure expression.
        JP Z,CALL_EC
        JR .NAMED                  ; Other names are ordinary procedure values.

; Compile a computed operator list and continue with its argument sequence.
.COMPUTED:
        LD A,(ST_TAIL)             ; The computed operator still has arguments to read.
        PUSH AF                    ; Save the surrounding tail context for the caller.
        XOR A                      ; Operator evaluation is always non-tail position.
        LD (ST_TAIL),A
        LD A,1                     ; CMD_FORM reached this path with an opening-list event.
        CALL CMD_EXPR              ; Compile the computed operator in value position.
        JR C,.OP_FAIL             ; Restore the tail context after a nested failure.
        POP AF                     ; Recover the enclosing application's tail context.
        LD (ST_TAIL),A
        CALL EM_PUSH               ; Keep the computed callee below its arguments.
        RET C
        XOR A                      ; A computed operator uses the ordinary call path.
        LD (ST_ROUTE),A            ; Do not inherit a surrounding primitive marker.
        JP CALL_ARG               ; The outer form supplies the arguments.
.OP_FAIL:
        POP AF                     ; Remove the saved context before reporting failure.
        LD (ST_TAIL),A
        SCF                        ; Preserve the nested operator diagnostic.
        RET

; Load a named procedure value and compile its application arguments.
.NAMED:
        LD HL,(ST_OPID)            ; Restore the operator's interned identity.
        LD (ST_SYMID),HL           ; The primitive check uses the common identity word.
        CALL BIND_HAS              ; A local name must retain the ordinary path.
        JR C,.GENERAL              ; Local bindings shadow predefined procedures.
        CALL GLB_HAS               ; An explicit global binding must remain dynamic.
        JR C,.BOUND                ; Existing globals use the normal marker path.
        CALL GLB_PRIM              ; Unbound primitives use a reserved immediate.
        OR A
        JR Z,.GENERAL              ; Ordinary names still use a full value record.
        LD (ST_GCALL),A            ; Mode three keeps the kind in the slot byte.
        LD A,3
        LD (ST_ROUTE),A            ; The call names the primitive directly.
        JP CALL_ARG
.BOUND:
        LD (ST_GCALL),A            ; Preserve the existing global slot for EM_HOLD.
        CALL EM_HOLD               ; Read the bound value before evaluating arguments.
        RET C
        LD A,1
        LD (ST_ROUTE),A            ; CALL_ARG now emits the compact call entry.
        JP CALL_ARG
.GENERAL:
        XOR A
        LD (ST_ROUTE),A            ; The general path carries a complete callee value.
        LD HL,(ST_OPID)            ; Restore the operator's interned identity.
        CALL CMD_REF               ; Resolve the value before reading arguments.
        RET C
        CALL EM_PUSH               ; Keep the named callee below its arguments.
        RET C
        JP CALL_ARG                ; CMD_REF leaves the generated value in A:HL.

; Select a package definition or a leading definition inside a procedure body.
.DEFINE:
        LD A,(ST_ATTOP)            ; Package-level permission is saved per form.
        OR A
        JP NZ,DEF_TOP              ; Top-level definitions retain global storage.
        LD A,(ST_BDSAV)            ; A body may accept definitions only at its head.
        OR A
        JP NZ,DEF_BODY             ; Internal definitions use recursive local slots.
        JP ERR_DEF                 ; Definitions in an expression are malformed.
