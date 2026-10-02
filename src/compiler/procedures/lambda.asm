; Compiler lambda parsing and nested scope frames.
; Entry points: SCLAMBF, SCLOPEN, SCLAMEND and SCUNWIND.
; Emit the fixed-arity lambda expression and its body.  The generated prefix
; constructs a static closure value and jumps over the body until invocation.
SCLAMBF:
        CALL SCLOPEN               ; Save the enclosing local directory and owner.
        RET C                      ; The compiler frame table has a fixed bound.
        CALL SCPNEW                ; Reserve one descriptor metadata record.
        JP C,SCLAMERR              ; Restore the enclosing scope on capacity failure.
        LD (SCTMPPR),A             ; Keep the new descriptor while parsing params.
        LD (SCCURPR),A             ; Formal slots belong to this new descriptor.
        CALL SCNEXT                ; Lambda requires a parenthesised parameter list.
        JP C,SCLAMERR              ; Restore scope state on a reader failure.
        CP 1                       ; The parameter container must be an opening list.
        JR Z,SCLAMP                ; A list carries fixed and dotted formals.
        CP 5                       ; A scalar name denotes an all-rest formal list.
        JP NZ,SCLAMERR             ; Other parameter forms are malformed.
        LD (SCID),HL               ; Preserve the all-rest name for slot allocation.
        CALL SCRADD             ; Add the name as the procedure's rest binding.
        JP C,SCLAMERR              ; Duplicate or exhausted locals are source errors.
        JP SCLAMPD                 ; The body follows the scalar rest name directly.
SCLAMP:
        CALL SCNEXT                ; Read a parameter name or the list close.
        JP C,SCLAMERR              ; Restore the enclosing scope before returning.
        CP 2                       ; A close completes the formal parameter list.
        JR Z,SCLAMPD               ; The body follows immediately after the list.
        CP 4                       ; A dot introduces the single rest formal.
        JR Z,SCLAMDOT              ; Parse the name and require the list close.
        CP 5                       ; Every formal is an interned identifier.
        JP NZ,SCLAMERR             ; Reject literals and nested lists as names.
        LD (SCID),HL               ; Preserve the parameter identity for SCADDLOC.
        CALL SCPDUP                ; A procedure cannot bind the same name twice.
        JR NC,SCLAMPNW            ; An outer binding may be shadowed legally.
        LD HL,SCDUPTXT             ; Report duplicate formals as a source error.
        LD (SCERRPTR),HL
        JP SCLAMERR
SCLAMPNW:
        CALL SCNSLOT               ; Allocate its reusable activation slot.
        JP C,SCLAMERR              ; Reject the first local beyond the hard bound.
        LD (SCSLOT),A              ; SCADDLOC reads the selected slot from here.
        CALL SCADDLOC              ; Make the parameter visible in the body.
        JP C,SCLAMERR              ; A full active directory is a compile error.
        LD A,(SCSLOT)              ; SCADDLOC returns the active count in A.
        CALL SCPARAM               ; Record the slot in the descriptor metadata.
        JP C,SCLAMERR              ; Reject an arity above the descriptor capacity.
        JR SCLAMP                  ; Read the next formal name.
SCLAMDOT:
        CALL SCNEXT                ; A dotted formal must name one identifier.
        JP C,SCLAMERR              ; Preserve a reader failure before scope cleanup.
        CP 5                       ; Only a symbol can receive the surplus list.
        JP NZ,SCLAMERR             ; Reject a missing or non-symbol rest name.
        LD (SCID),HL               ; Preserve the rest name for duplicate checking.
        CALL SCRADD             ; Add the rest binding after fixed formals.
        JP C,SCLAMERR              ; Duplicate or exhausted locals are source errors.
        CALL SCNEXT                ; The dotted name must be followed by the close.
        JP C,SCLAMERR              ; Preserve an incomplete parameter list error.
        CP 2                       ; Dotted formals contain exactly one tail name.
        JP NZ,SCLAMERR             ; Reject a second tail name or malformed close.
SCLAMPD:
        CALL SCRMETA             ; Mark the descriptor and record the rest slot.
        JP C,SCLAMERR              ; A malformed metadata record is a compiler error.
        CALL SCPREFX               ; Emit the closure value and jump-over branch.
        LD HL,(SCPC)
        LD (SCPBODY),HL            ; The body starts immediately after the prefix.
        JP C,SCLAMERR              ; Preserve an output or metadata failure.
        LD A,1                     ; A lambda body is always a tail context.
        LD (SCTCTX),A              ; SCBODY passes this to its final expression.
        LD A,(SCBISOL)             ; Preserve the enclosing body's isolation mode.
        PUSH AF                     ; The lambda request must not leak on return.
        LD A,1                     ; Its tail candidates belong to this procedure.
        LD (SCBISOL),A             ; Ask SCBODY for a private candidate list.
        CALL SCBODY                ; Compile expressions through the lambda close.
        JP C,SCLAMBER              ; Restore isolation state before unwinding.
        POP AF                     ; Recover the enclosing body's isolation mode.
        LD (SCBISOL),A             ; Restore it before compiling the outer form.
        CALL SCRET                 ; A normal body returns its final A:HL value.
        JP C,SCLAMERR              ; The return byte itself is bounded output.
        CALL SCPFIN                ; Save body address and patch the jump-over.
        JP C,SCLAMERR              ; Preserve the descriptor-layout failure.
        JP SCLAMEND                ; Restore the enclosing scope and return closure.

; Save local cursors and select the newly-created procedure as owner.
SCLOPEN:
        LD A,(SCBDEP)              ; The compiler frame table is explicitly bounded.
        CP SCBFMAX                 ; 28 nine-byte records fit below SCGPRIM.
        JP NC,SCCAP                ; Reject nesting beyond the reserved records.
        LD C,A                     ; C selects the current four-byte frame.
        INC A
        LD (SCBDEP),A              ; Publish the nested body depth.
        LD L,C                     ; Widen the frame index before scaling it.
        LD H,0
        LD D,H                     ; Keep a second copy for the nine-byte scale.
        LD E,L
        ADD HL,HL                  ; Two bytes per partial record.
        ADD HL,HL                  ; Four bytes per saved lambda frame.
        ADD HL,HL                  ; Eight bytes per saved lambda frame.
        ADD HL,DE                  ; Add one byte for the complete record width.
        LD DE,SCBFRAME             ; Locate the saved cursor record.
        ADD HL,DE
        LD A,(SCLOCTOP)            ; Preserve the active outer-binding count.
        LD (HL),A
        INC HL
        LD A,(SCLNEXT)             ; Preserve the reusable local slot cursor.
        LD (HL),A
        INC HL
        LD A,(SCCURPR)             ; Preserve the enclosing procedure owner.
        LD (HL),A
        INC HL
        LD A,(SCTCTX)              ; Preserve the enclosing tail-position state.
        LD (HL),A
        INC HL
        LD A,(SCTMPPR)             ; Preserve the enclosing procedure descriptor.
        LD (HL),A
        INC HL
        LD DE,(SCSKIP)             ; Preserve the enclosing jump-over patch.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(SCPBODY)            ; Preserve the enclosing body cursor.
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(SCTMPPR)             ; Select the new owner for formal slots.
        LD (SCCURPR),A             ; Captured outer names now point at this record.
        XOR A                      ; Carry clear reports a balanced scope opening.
        RET                        ; The parameter parser may allocate locals.

; Restore the enclosing local directory while retaining the closure result.
SCLAMEND:
        LD (SCRESV),HL             ; Preserve the body's result payload.
        LD (SCREST),A              ; Preserve the closure tag while restoring state.
        CALL SCUNWIND                ; Restore the enclosing compiler frame.
        RET C                      ; A missing frame is an internal capacity error.
        LD HL,(SCRESV)             ; Restore the body's result value.
        LD A,(SCREST)              ; Restore the closure or body result tag.
        OR A                        ; The lambda expression itself has no carry error.
        RET                        ; Return the descriptor pointer in A:HL.

SCLAMERR:
        CALL SCUNWIND                ; Balance the frame before reporting failure.
        SCF                        ; The caller reports a compile error.
        RET                        ; No partially generated file is published.

SCLAMBER:
        POP AF                     ; Remove the saved enclosing isolation mode.
        LD (SCBISOL),A             ; Restore it before unwinding the scope frame.
        JP SCLAMERR                ; Share the ordinary lambda failure path.
