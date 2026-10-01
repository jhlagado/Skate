; Scope compiler internal-definition and procedure construction.
; Entry points: SCDEFUSE, SCIDEF and SCIDPROC.
; initializer so later definitions can refer back to it.
; The prepass has already claimed the current-range cell, so a definition
; reuses that claim instead of being mistaken for a duplicate declaration.
SCDEFUSE:
        CALL SCLOCF
        JP NC,SCRECDEC
        LD B,A
        LD A,(SCRECST)
        CP B
        JR Z,SCDEFOK
        JP NC,SCRECDEC
        LD A,(SCRECLIM)
        CP B
        JP C,SCRECDEC
        JP Z,SCRECDEC
SCDEFOK:
        LD A,B
        OR A
        RET

SCIDEF:
        XOR A
        LD (SCIDMODE),A            ; Internal definitions use local procedure cells.
        LD A,(SCRECPHS)
        OR A
        JR NZ,SCIDREAD
        LD A,(SCLNEXT)
        LD (SCRECST),A
        LD (SCRECLIM),A
        LD A,(SCCURPR)
        LD (SCRECPR),A
        LD A,1
        LD (SCRECMOD),A
        LD (SCRECPHS),A
SCIDREAD:
        CALL SCNEXT                ; A name is either a variable or a header list.
        JP C,SCSYN
        CP 1
        JP Z,SCIDPROC              ; Procedure-definition shorthand.
        CP 5
        JP NZ,SCDEFNSY
        LD (SCID),HL
        LD A,(SCBMODE)
        CP 1
        JR NZ,SCIDFOK              ; A let body may shadow an enclosing formal.
        CALL SCPFORM               ; A procedure body cannot redeclare a formal.
        JR NC,SCIDFOK
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP C,SCIDERR
SCIDFOK:
        CALL SCDEFUSE
        RET C
        LD (SCSLOT),A
        LD A,(SCSLOT)
        PUSH AF
        CALL SCINIT                ; Initializers run before the body expression.
        JP C,SCIDIERR
        POP AF
        LD (SCSLOT),A
        LD A,(SCSLOT)
        LD L,A
        LD A,1
        CALL SCSTORE
        RET C
        CALL SCEXPECT
        RET C
        LD A,1
        LD (SCISDEF),A
        LD (SCBDEFIN),A
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
        JP NZ,SCDEFNSY
        LD (SCID),HL
        LD A,(SCBMODE)
        CP 1
        JR NZ,SCIDPFOK             ; A let body may shadow an enclosing formal.
        CALL SCPFORM               ; A procedure body cannot reuse a formal.
        JR NC,SCIDPFOK
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP SCIDERR
SCIDPFOK:
        LD A,(SCIDMODE)
        OR A
        JR NZ,SCIDGLOB              ; Package shorthand uses a global procedure cell.
        CALL SCDEFUSE               ; The name is a recursive local definition.
        JP C,SCIDERR
        JR SCIDCELL
SCIDGLOB:
        CALL SCGGET                 ; Allocate the package cell before its body.
        JP C,SCIDERR
SCIDCELL:
        LD (SCDEFSL),A              ; Preserve its slot while formals are parsed.
        CALL SCLOPEN                ; Enter the procedure's local activation scope.
        JP C,SCIDERR
        CALL SCPNEW                 ; Reserve its descriptor metadata record.
        JP C,SCIDUNW
        LD (SCCURPR),A              ; Formal slots belong to this descriptor.
SCIDPAR:
        CALL SCNEXT                 ; Read a formal name or the list close.
        JP C,SCIDUNW
        CP 2
        JR Z,SCIDPEND
        CP 4
        JR Z,SCIDPDOT               ; A dot introduces the single rest formal.
        CP 5
        JP NZ,SCIDUNW
        LD (SCID),HL
        CALL SCPDUP                 ; Reject duplicate formals in this procedure.
        JR NC,SCIDPNEW
        LD HL,SCDUPTXT
        LD (SCERRPTR),HL
        JP SCIDUNW
SCIDPNEW:
        CALL SCNSLOT
        JP C,SCIDUNW
        LD (SCSLOT),A
        CALL SCADDLOC
        JP C,SCIDUNW
        LD A,(SCSLOT)
        CALL SCPARAM
        JP C,SCIDUNW
        JR SCIDPAR
SCIDPDOT:
        CALL SCNEXT                 ; Read the dotted rest name.
        JP C,SCIDUNW
        CP 5
        JP NZ,SCIDUNW
        LD (SCID),HL
        CALL SCRADD                 ; Add the rest binding after fixed formals.
        JP C,SCIDUNW
        CALL SCNEXT                 ; The rest name must be followed by the close.
        JP C,SCIDUNW
        CP 2
        JP NZ,SCIDUNW
        JR SCIDPEND
SCIDPEND:
        CALL SCRMETA                ; Publish the rest policy and its local slot.
        JP C,SCIDUNW
        CALL SCMAKE                 ; Build the closure without a body jump yet.
        JP C,SCIDUNW
        LD A,(SCDEFSL)              ; Store the closure in the definition's cell.
        LD L,A
        LD A,(SCIDMODE)
        OR A
        JR Z,SCIDLOC
        XOR A                       ; Kind zero denotes a package-global cell.
        CALL SCSTORE
        JP C,SCIDUNW
        JR SCIDSTOK
SCIDLOC:
        LD A,1                      ; Kind one denotes an enclosing local cell.
        CALL SCSTORE
        JP C,SCIDUNW
SCIDSTOK:
        CALL SCJP                   ; Skip the procedure body during definition.
        JP C,SCIDUNW
        LD (SCSKIP),HL
        LD HL,(SCPC)
        LD (SCPBODY),HL
        LD A,1
        LD (SCTCTX),A
        LD A,(SCBISOL)
        PUSH AF
        LD A,1
        LD (SCBISOL),A
        CALL SCBODY
        JP C,SCIDBERR
        POP AF
        LD (SCBISOL),A
        CALL SCRET
        JP C,SCIDUNW
        CALL SCPFIN
        JP C,SCIDUNW
        CALL SCUNWIND
        JP C,SCIDERR
        LD A,1
        LD (SCISDEF),A
        LD (SCBDEFIN),A
        XOR A
        LD (SCIDMODE),A
        RET
SCIDBERR:
        POP AF                     ; Restore the enclosing body isolation flag.
        LD (SCBISOL),A
SCIDUNW:
        CALL SCUNWIND
SCIDERR:
        XOR A
        LD (SCIDMODE),A
        SCF
        RET

; Compile named let. The procedure is created before its initializers, then
