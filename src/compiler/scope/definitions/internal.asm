; Scope compiler internal-definition and procedure construction.
; Entry points: DEF_CELL, DEF_BODY and DEF_PROC.
; initializer so later definitions can refer back to it.
; The prepass has already claimed the current-range cell, so a definition
; reuses that claim instead of being mistaken for a duplicate declaration.
DEF_CELL:
        CALL BIND_HAS
        JP NC,LET_DECL
        LD B,A
        LD A,(ST_RBASE)
        CP B
        JR Z,.CLAIMED
        JP NC,LET_DECL
        LD A,(ST_RTOP)
        CP B
        JP C,LET_DECL
        JP Z,LET_DECL
.CLAIMED:
        LD A,B
        OR A
        RET

DEF_BODY:
        XOR A
        LD (ST_INPKG),A            ; Internal definitions use local procedure cells.
        LD A,(ST_RINIT)
        OR A
        JR NZ,.READ
        LD A,(ST_LNEXT)
        LD (ST_RBASE),A
        LD (ST_RTOP),A
        LD A,(ST_PROC)
        LD (ST_RPROC),A
        LD A,1
        LD (ST_RMODE),A
        LD (ST_RINIT),A
.READ:
        CALL REC_NEXT              ; A name is either a variable or a header list.
        JP C,ERR_BAD
        CP 1
        JP Z,DEF_PROC              ; Procedure-definition shorthand.
        CP 5
        JP NZ,ERR_NAME
        LD (ST_SYMID),HL
        LD A,(ST_BMODE)
        CP 1
        JR NZ,.SLOT                ; A let body may shadow an enclosing formal.
        CALL CAP_FORM              ; A procedure body cannot redeclare a formal.
        JR NC,.SLOT
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP C,DEF_FAIL
.SLOT:
        CALL DEF_CELL
        RET C
        LD (ST_SLOT),A
        LD A,(ST_SLOT)
        PUSH AF
        CALL LET_INIT              ; Initializers run before the body expression.
        JP C,.INIT_BAD
        POP AF
        LD (ST_SLOT),A
        LD A,(ST_SLOT)
        LD L,A
        LD A,1
        CALL EM_STORE
        RET C
        CALL CMD_END
        RET C
        LD A,1
        LD (ST_ISDEF),A
        LD (ST_BDEF),A
        XOR A
        RET
.INIT_BAD:
        POP AF
        JP DEF_FAIL

; Compile (define (name arg ...) body ...) inside a procedure body. The
; function cell is allocated in the enclosing scope, then the generated code
; creates its closure before jumping over the procedure body.
DEF_PROC:
        CALL REC_NEXT              ; The header starts with the procedure name.
        JP C,DEF_FAIL
        CP 5
        JP NZ,ERR_NAME
        LD (ST_SYMID),HL
        LD A,(ST_BMODE)
        CP 1
        JR NZ,.PICK                ; A let body may shadow an enclosing formal.
        CALL CAP_FORM              ; A procedure body cannot reuse a formal.
        JR NC,.PICK
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP DEF_FAIL
.PICK:
        LD A,(ST_INPKG)
        OR A
        JR NZ,.GLOBAL               ; Package shorthand uses a global procedure cell.
        CALL DEF_CELL               ; The name is a recursive local definition.
        JP C,DEF_FAIL
        JR .CELL
.GLOBAL:
        CALL GLB_GET                ; Allocate the package cell before its body.
        JP C,DEF_FAIL
.CELL:
        LD (ST_DSLOT),A             ; Preserve its slot while formals are parsed.
        CALL LAM_OPEN               ; Enter the procedure's local activation scope.
        JP C,DEF_FAIL
        CALL PROC_NEW               ; Reserve its descriptor metadata record.
        JP C,.UNWIND
        LD (ST_PROC),A              ; Formal slots belong to this descriptor.
.FORMAL:
        CALL REC_NEXT               ; Read a formal name or the list close.
        JP C,.UNWIND
        CP 2
        JR Z,.CLOSURE
        CP 4
        JR Z,.REST                  ; A dot introduces the single rest formal.
        CP 5
        JP NZ,.UNWIND
        LD (ST_SYMID),HL
        CALL CAP_DUP                ; Reject duplicate formals in this procedure.
        JR NC,.NEW_ARG
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP .UNWIND
.NEW_ARG:
        CALL BIND_NEW
        JP C,.UNWIND
        LD (ST_SLOT),A
        CALL BIND_ADD
        JP C,.UNWIND
        LD A,(ST_SLOT)
        CALL PROC_ARG
        JP C,.UNWIND
        JR .FORMAL
.REST:
        CALL REC_NEXT               ; Read the dotted rest name.
        JP C,.UNWIND
        CP 5
        JP NZ,.UNWIND
        LD (ST_SYMID),HL
        CALL CAP_REST               ; Add the rest binding after fixed formals.
        JP C,.UNWIND
        CALL REC_NEXT               ; The rest name must be followed by the close.
        JP C,.UNWIND
        CP 2
        JP NZ,.UNWIND
.CLOSURE:
        CALL CAP_META               ; Publish the rest policy and its local slot.
        JP C,.UNWIND
        CALL LAM_MAKE               ; Build the closure without a body jump yet.
        JP C,.UNWIND
        LD A,(ST_DSLOT)             ; Store the closure in the definition's cell.
        LD L,A
        LD A,(ST_INPKG)
        OR A
        JR Z,.LOCAL
        XOR A                       ; Kind zero denotes a package-global cell.
        CALL EM_STORE
        JP C,.UNWIND
        JR .STORED
.LOCAL:
        LD A,1                      ; Kind one denotes an enclosing local cell.
        CALL EM_STORE
        JP C,.UNWIND
.STORED:
        CALL EM_JP                  ; Skip the procedure body during definition.
        JP C,.UNWIND
        LD (ST_SKIP),HL
        LD HL,(ST_PC)
        LD (ST_PBODY),HL
        LD A,1
        LD (ST_TAIL),A
        LD A,(ST_ALONE)
        PUSH AF
        LD A,1
        LD (ST_ALONE),A
        CALL CMD_BODY
        JP C,.BODY_BAD
        POP AF
        LD (ST_ALONE),A
        CALL EM_RET
        JP C,.UNWIND
        CALL PROC_END
        JP C,.UNWIND
        CALL CAP_POP
        JP C,DEF_FAIL
        LD A,1
        LD (ST_ISDEF),A
        LD (ST_BDEF),A
        XOR A
        LD (ST_INPKG),A
        RET
.BODY_BAD:
        POP AF                     ; Restore the enclosing body isolation flag.
        LD (ST_ALONE),A
.UNWIND:
        CALL CAP_POP
DEF_FAIL:
        XOR A
        LD (ST_INPKG),A
        SCF
        RET

; Compile named let. The procedure is created before its initializers, then
