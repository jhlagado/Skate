; Scope compiler internal-definition and procedure construction.
; Entry points: SCDEFUSE, SCIDEF and SCIDPROC.
; initializer so later definitions can refer back to it.
; The prepass has already claimed the current-range cell, so a definition
; reuses that claim instead of being mistaken for a duplicate declaration.
SCDEFUSE:
        CALL SCLOCF
        JP NC,SCRECDEC
        LD B,A
        LD A,(ST_RBASE)
        CP B
        JR Z,SCDEFOK
        JP NC,SCRECDEC
        LD A,(ST_RTOP)
        CP B
        JP C,SCRECDEC
        JP Z,SCRECDEC
SCDEFOK:
        LD A,B
        OR A
        RET

SCIDEF:
        XOR A
        LD (ST_INPKG),A            ; Internal definitions use local procedure cells.
        LD A,(ST_RINIT)
        OR A
        JR NZ,SCIDREAD
        LD A,(ST_LNEXT)
        LD (ST_RBASE),A
        LD (ST_RTOP),A
        LD A,(ST_PROC)
        LD (ST_RPROC),A
        LD A,1
        LD (ST_RMODE),A
        LD (ST_RINIT),A
SCIDREAD:
        CALL SCNEXT                ; A name is either a variable or a header list.
        JP C,ERR_BAD
        CP 1
        JP Z,SCIDPROC              ; Procedure-definition shorthand.
        CP 5
        JP NZ,ERR_NAME
        LD (ST_SYMID),HL
        LD A,(ST_BMODE)
        CP 1
        JR NZ,SCIDFOK              ; A let body may shadow an enclosing formal.
        CALL SCPFORM               ; A procedure body cannot redeclare a formal.
        JR NC,SCIDFOK
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP C,SCIDERR
SCIDFOK:
        CALL SCDEFUSE
        RET C
        LD (ST_SLOT),A
        LD A,(ST_SLOT)
        PUSH AF
        CALL SCINIT                ; Initializers run before the body expression.
        JP C,SCIDIERR
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
SCIDIERR:
        POP AF
        JP SCIDERR

; Compile (define (name arg ...) body ...) inside a procedure body. The
; function cell is allocated in the enclosing scope, then the generated code
; creates its closure before jumping over the procedure body.
SCIDPROC:
        CALL SCNEXT                ; The header starts with the procedure name.
        JP C,SCIDERR
        CP 5
        JP NZ,ERR_NAME
        LD (ST_SYMID),HL
        LD A,(ST_BMODE)
        CP 1
        JR NZ,SCIDPFOK             ; A let body may shadow an enclosing formal.
        CALL SCPFORM               ; A procedure body cannot reuse a formal.
        JR NC,SCIDPFOK
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP SCIDERR
SCIDPFOK:
        LD A,(ST_INPKG)
        OR A
        JR NZ,SCIDGLOB              ; Package shorthand uses a global procedure cell.
        CALL SCDEFUSE               ; The name is a recursive local definition.
        JP C,SCIDERR
        JR SCIDCELL
SCIDGLOB:
        CALL SCGGET                 ; Allocate the package cell before its body.
        JP C,SCIDERR
SCIDCELL:
        LD (ST_DSLOT),A             ; Preserve its slot while formals are parsed.
        CALL SCLOPEN                ; Enter the procedure's local activation scope.
        JP C,SCIDERR
        CALL SCPNEW                 ; Reserve its descriptor metadata record.
        JP C,SCIDUNW
        LD (ST_PROC),A              ; Formal slots belong to this descriptor.
SCIDPAR:
        CALL SCNEXT                 ; Read a formal name or the list close.
        JP C,SCIDUNW
        CP 2
        JR Z,SCIDPEND
        CP 4
        JR Z,SCIDPDOT               ; A dot introduces the single rest formal.
        CP 5
        JP NZ,SCIDUNW
        LD (ST_SYMID),HL
        CALL SCPDUP                 ; Reject duplicate formals in this procedure.
        JR NC,SCIDPNEW
        LD HL,M_DUP
        LD (ST_ERROR),HL
        JP SCIDUNW
SCIDPNEW:
        CALL SCNSLOT
        JP C,SCIDUNW
        LD (ST_SLOT),A
        CALL SCADDLOC
        JP C,SCIDUNW
        LD A,(ST_SLOT)
        CALL SCPARAM
        JP C,SCIDUNW
        JR SCIDPAR
SCIDPDOT:
        CALL SCNEXT                 ; Read the dotted rest name.
        JP C,SCIDUNW
        CP 5
        JP NZ,SCIDUNW
        LD (ST_SYMID),HL
        CALL SCRADD                 ; Add the rest binding after fixed formals.
        JP C,SCIDUNW
        CALL SCNEXT                 ; The rest name must be followed by the close.
        JP C,SCIDUNW
        CP 2
        JP NZ,SCIDUNW
SCIDPEND:
        CALL SCRMETA                ; Publish the rest policy and its local slot.
        JP C,SCIDUNW
        CALL SCMAKE                 ; Build the closure without a body jump yet.
        JP C,SCIDUNW
        LD A,(ST_DSLOT)             ; Store the closure in the definition's cell.
        LD L,A
        LD A,(ST_INPKG)
        OR A
        JR Z,SCIDLOC
        XOR A                       ; Kind zero denotes a package-global cell.
        CALL EM_STORE
        JP C,SCIDUNW
        JR SCIDSTOK
SCIDLOC:
        LD A,1                      ; Kind one denotes an enclosing local cell.
        CALL EM_STORE
        JP C,SCIDUNW
SCIDSTOK:
        CALL EM_JP                  ; Skip the procedure body during definition.
        JP C,SCIDUNW
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
        JP C,SCIDBERR
        POP AF
        LD (ST_ALONE),A
        CALL EM_RET
        JP C,SCIDUNW
        CALL SCPFIN
        JP C,SCIDUNW
        CALL SCUNWIND
        JP C,SCIDERR
        LD A,1
        LD (ST_ISDEF),A
        LD (ST_BDEF),A
        XOR A
        LD (ST_INPKG),A
        RET
SCIDBERR:
        POP AF                     ; Restore the enclosing body isolation flag.
        LD (ST_ALONE),A
SCIDUNW:
        CALL SCUNWIND
SCIDERR:
        XOR A
        LD (ST_INPKG),A
        SCF
        RET

; Compile named let. The procedure is created before its initializers, then
