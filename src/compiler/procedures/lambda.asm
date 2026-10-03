; Compiler lambda parsing and nested scope frames.
; Entry points: SCLAMBF, SCLOPEN, SCLAMEND and SCUNWIND.
; Emit the fixed-arity lambda expression and its body.  The generated prefix
; constructs a static closure value and jumps over the body until invocation.
SCLAMBF:
        CALL SCLOPEN               ; Save the enclosing local directory and owner.
        RET C                      ; The compiler frame table has a fixed bound.
        CALL SCPNEW                ; Reserve one descriptor metadata record.
        JP C,SCLAMERR              ; Restore the enclosing scope on capacity failure.
        LD (ST_DESC),A             ; Keep the new descriptor while parsing params.
        LD (ST_PROC),A             ; Formal slots belong to this new descriptor.
        CALL SCNEXT                ; Lambda requires a parenthesised parameter list.
        JP C,SCLAMERR              ; Restore scope state on a reader failure.
        CP 1                       ; The parameter container must be an opening list.
        JR Z,SCLAMP                ; A list carries fixed and dotted formals.
        CP 5                       ; A scalar name denotes an all-rest formal list.
        JP NZ,SCLAMERR             ; Other parameter forms are malformed.
        LD (ST_SYMID),HL           ; Preserve the all-rest name for slot allocation.
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
        LD (ST_SYMID),HL           ; Preserve the parameter identity for SCADDLOC.
        CALL SCPDUP                ; A procedure cannot bind the same name twice.
        JR NC,SCLAMPNW            ; An outer binding may be shadowed legally.
        LD HL,M_DUP                ; Report duplicate formals as a source error.
        LD (ST_ERROR),HL
        JP SCLAMERR
SCLAMPNW:
        CALL SCNSLOT               ; Allocate its reusable activation slot.
        JP C,SCLAMERR              ; Reject the first local beyond the hard bound.
        LD (ST_SLOT),A             ; SCADDLOC reads the selected slot from here.
        CALL SCADDLOC              ; Make the parameter visible in the body.
        JP C,SCLAMERR              ; A full active directory is a compile error.
        LD A,(ST_SLOT)             ; SCADDLOC returns the active count in A.
        CALL SCPARAM               ; Record the slot in the descriptor metadata.
        JP C,SCLAMERR              ; Reject an arity above the descriptor capacity.
        JR SCLAMP                  ; Read the next formal name.
SCLAMDOT:
        CALL SCNEXT                ; A dotted formal must name one identifier.
        JP C,SCLAMERR              ; Preserve a reader failure before scope cleanup.
        CP 5                       ; Only a symbol can receive the surplus list.
        JP NZ,SCLAMERR             ; Reject a missing or non-symbol rest name.
        LD (ST_SYMID),HL           ; Preserve the rest name for duplicate checking.
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
        LD HL,(ST_PC)
        LD (ST_PBODY),HL           ; The body starts immediately after the prefix.
        JP C,SCLAMERR              ; Preserve an output or metadata failure.
        LD A,1                     ; A lambda body is always a tail context.
        LD (ST_TAIL),A             ; CMD_BODY passes this to its final expression.
        LD A,(ST_ALONE)            ; Preserve the enclosing body's isolation mode.
        PUSH AF                     ; The lambda request must not leak on return.
        LD A,1                     ; Its tail candidates belong to this procedure.
        LD (ST_ALONE),A            ; Ask CMD_BODY for a private candidate list.
        CALL CMD_BODY              ; Compile expressions through the lambda close.
        JP C,SCLAMBER              ; Restore isolation state before unwinding.
        POP AF                     ; Recover the enclosing body's isolation mode.
        LD (ST_ALONE),A            ; Restore it before compiling the outer form.
        CALL EM_RET                ; A normal body returns its final A:HL value.
        JP C,SCLAMERR              ; The return byte itself is bounded output.
        CALL SCPFIN                ; Save body address and patch the jump-over.
        JP C,SCLAMERR              ; Preserve the descriptor-layout failure.
        JP SCLAMEND                ; Restore the enclosing scope and return closure.

; Save local cursors and select the newly-created procedure as owner.
SCLOPEN:
        LD A,(ST_BNEST)            ; The compiler frame table is explicitly bounded.
        CP W_BODY_N                ; 28 nine-byte records fit below W_GPRIM.
        JP NC,ERR_CAP              ; Reject nesting beyond the reserved records.
        LD C,A                     ; C selects the current four-byte frame.
        INC A
        LD (ST_BNEST),A            ; Publish the nested body depth.
        LD L,C                     ; Widen the frame index before scaling it.
        LD H,0
        LD D,H                     ; Keep a second copy for the nine-byte scale.
        LD E,L
        ADD HL,HL                  ; Two bytes per partial record.
        ADD HL,HL                  ; Four bytes per saved lambda frame.
        ADD HL,HL                  ; Eight bytes per saved lambda frame.
        ADD HL,DE                  ; Add one byte for the complete record width.
        LD DE,W_BODY               ; Locate the saved cursor record.
        ADD HL,DE
        LD A,(ST_LTOP)             ; Preserve the active outer-binding count.
        LD (HL),A
        INC HL
        LD A,(ST_LNEXT)            ; Preserve the reusable local slot cursor.
        LD (HL),A
        INC HL
        LD A,(ST_PROC)             ; Preserve the enclosing procedure owner.
        LD (HL),A
        INC HL
        LD A,(ST_TAIL)             ; Preserve the enclosing tail-position state.
        LD (HL),A
        INC HL
        LD A,(ST_DESC)             ; Preserve the enclosing procedure descriptor.
        LD (HL),A
        INC HL
        LD DE,(ST_SKIP)            ; Preserve the enclosing jump-over patch.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(ST_PBODY)           ; Preserve the enclosing body cursor.
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(ST_DESC)             ; Select the new owner for formal slots.
        LD (ST_PROC),A             ; Captured outer names now point at this record.
        XOR A                      ; Carry clear reports a balanced scope opening.
        RET                        ; The parameter parser may allocate locals.

; Restore the enclosing local directory while retaining the closure result.
SCLAMEND:
        LD (ST_VALUE),HL           ; Preserve the body's result payload.
        LD (ST_VTAG),A             ; Preserve the closure tag while restoring state.
        CALL SCUNWIND                ; Restore the enclosing compiler frame.
        RET C                      ; A missing frame is an internal capacity error.
        LD HL,(ST_VALUE)           ; Restore the body's result value.
        LD A,(ST_VTAG)             ; Restore the closure or body result tag.
        OR A                        ; The lambda expression itself has no carry error.
        RET                        ; Return the descriptor pointer in A:HL.

SCLAMERR:
        CALL SCUNWIND                ; Balance the frame before reporting failure.
        SCF                        ; The caller reports a compile error.
        RET                        ; No partially generated file is published.

SCLAMBER:
        POP AF                     ; Remove the saved enclosing isolation mode.
        LD (ST_ALONE),A            ; Restore it before unwinding the scope frame.
        JP SCLAMERR                ; Share the ordinary lambda failure path.
