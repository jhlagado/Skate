;=============================================================================
;  I3 native macro expansion and hygiene
;=============================================================================
;
;  This source part follows native-macro.asm.  It owns template cloning,
;  hygiene marking, and the bounded expansion traversal.  Keeping this phase
;  separate leaves the matcher/parser source part below ATOM's 65,535-byte
;  source-part limit without changing the assembled order or ABI.
;=============================================================================

;-------------------------------------------------------------------------
; Bounded template cloning
;-------------------------------------------------------------------------

; Clone a matched template into the same arena.  Pattern variables are
; replaced by their bound nodes; other identifiers receive this expansion's
; scope mark while retaining their authored spelling and source position.
NMEXPAND:
        PUSH HL
        LD HL,(NMPTR)
        LD (NMSAVPTR),HL
        LD HL,(NMCOUNT)
        LD (NMSAVCNT),HL
        LD A,(NMSCOPE)
        LD (NMSAVSCP),A
        LD A,(NMSCOPE)
        INC A
        JR NZ,.scope
        INC A
.scope:
        LD (NMSCOPE),A
        XOR A
        LD (NMPATHN),A
        POP HL
        CALL NMCLONE
        JR C,.fail
        LD (NMOUT),HL
        LD A,(NMSCOPE)
        LD (NMGENSCP),A
        LD HL,(NMMACP)
        LD A,H
        OR L
        JR Z,.nodef
        LD DE,8
        ADD HL,DE
        LD A,(HL)
        LD (NMDEFSCP),A
        JR .scopeok
.nodef:
        LD A,(NMSCOPE)
        LD (NMDEFSCP),A
.scopeok:
        LD HL,(NMOUT)
        CALL NMHGENP
        JR C,.fail
        LD HL,(NMCAPMRK)
        LD (NMCAPPTR),HL
        LD HL,(NMOUT)
        XOR A
        LD (NMPATHN),A
        XOR A
        RET
.fail:
        XOR A
        LD (NMPATHN),A
        LD HL,(NMCAPMRK)
        LD (NMCAPPTR),HL
        LD HL,(NMSAVPTR)
        LD (NMPTR),HL
        LD HL,(NMSAVCNT)
        LD (NMCOUNT),HL
        LD A,(NMSAVSCP)
        LD (NMSCOPE),A
        XOR A
        LD (NMLXN),A
        LD (NMHDEP),A
        XOR A
        LD (NMBINDN),A
        SCF
        RET

; Clone one node.  The caller-supplied arena remains the only storage owner.
NMCLONE:
        LD (NMSRCN),HL
        LD A,(NMRAW)
        OR A
        JR NZ,.alloc
        LD A,(HL)
        CP NMKSYM
        JR NZ,.alloc
        CALL NMLOOK
        OR A
        JR Z,.alloc
        LD HL,(NMMVALP)
        LD A,(HL)
        CP NMKREP
        JR Z,.repbind
        LD HL,(NMMVALP)
        JR .rawbind
.repbind:
        LD A,(NMREPMOD)
        OR A
        JR Z,.badbind
        CALL NMREPSEL
        JR C,.badbind
.rawbind:
        LD A,(NMRAW)
        LD (NMRAWSAV),A
        LD A,1
        LD (NMRAW),A
        CALL NMCLONE
        LD A,(NMRAWSAV)
        LD (NMRAW),A
        RET
.badbind:
        SCF
        RET
.alloc:
        CALL NMALLOC
        RET C
        LD (NMDSTN),HL
        CALL NMCOPY
        LD HL,(NMSRCN)
        LD A,(HL)
        CP NMKSYM
        JR Z,.symbol
        CP NMKQUOT
        JR Z,.quote
        CP NMKLIST
        JR Z,.list
        LD HL,(NMDSTN)
        XOR A
        RET
.symbol:
        LD A,(NMRAW)
        OR A
        JR NZ,.rawsym
        LD HL,(NMDSTN)
        LD A,(NMSCOPE)
        LD DE,NMSCOP
        ADD HL,DE
        LD (HL),A
.rawsym:
        LD HL,(NMDSTN)
        XOR A
        RET
.quote:
        LD HL,(NMSRCN)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(NMDSTN)
        PUSH HL
        LD H,D
        LD L,E
        LD A,(NMRAW)
        PUSH AF
        LD A,1
        LD (NMRAW),A
        CALL NMCLONE
        JR C,.qrawbad
        POP AF
        LD (NMRAW),A
        POP DE
        LD (NMDSTN),DE
        LD A,L
        INC DE
        INC DE
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        LD HL,(NMDSTN)
        XOR A
        RET
.qrawbad:
        POP AF
        LD (NMRAW),A
.qbad:
        POP DE
        LD (NMDSTN),DE
        SCF
        RET
.list:
        LD HL,(NMDSTN)
        XOR A
        LD DE,2
        ADD HL,DE
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        LD DE,2
        ADD HL,DE
        LD (HL),A
        INC HL
        LD (HL),A
        LD HL,(NMSRCN)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMSRCH),DE
.children:
        LD HL,(NMSRCH)
        LD A,H
        OR L
        JP Z,.tail
        LD A,(NMRAW)
        OR A
        JR NZ,.ordinary
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.ordinary
        LD (NMRDOT),DE
        PUSH DE
        LD H,D
        LD L,E
        CALL NMDOT
        POP DE
        JR C,.ordinary
        LD HL,(NMRDOT)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR NZ,.cbad
        LD HL,(NMSRCH)
        LD DE,(NMDSTN)
        CALL NMREPTMP
        JR C,.rbad
        LD HL,(NMRDOT)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMSRCH),DE
        JP .children
.rbad:
        SCF
        RET
.ordinary:
        LD HL,(NMDSTN)
        PUSH HL
        LD HL,(NMSRCN)
        PUSH HL
        LD HL,(NMSRCH)
        PUSH HL
        CALL NMCLONE
        JR C,.cbad
        LD (NMTEMP),HL
        POP HL
        LD (NMSRCH),HL
        POP HL
        LD (NMSRCN),HL
        POP DE
        LD (NMDSTN),DE
        LD HL,(NMTEMP)
        LD DE,(NMDSTN)
        CALL NMAPPEND
        LD HL,(NMSRCH)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMSRCH),DE
        JP .children
.cbad:
        POP DE
        POP DE
        POP DE
        SCF
        RET
.tail:
        LD HL,(NMSRCN)
        INC HL
        LD A,(HL)
        AND 1
        JP Z,.good
        LD HL,(NMSRCN)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMRDOT),DE
        LD A,(NMRAW)
        OR A
        JR NZ,.tailcl
        LD A,(DE)
        CP NMKSYM
        JR NZ,.tailcl
        PUSH DE
        LD H,D
        LD L,E
        CALL NMLOOK
        POP DE
        OR A
        JR Z,.tailcl
        LD HL,(NMMVALP)
        LD A,(HL)
        CP NMKREP
        JR NZ,.tailcl
        CALL NMALLOC
        JR C,.tbad0
        LD (NMRLIST),HL
        LD (HL),NMKLIST
        LD HL,(NMDSTN)
        LD (NMRDEST),HL
        LD DE,(NMRLIST)
        LD HL,(NMRDOT)
        CALL NMREPTMP
        JR C,.tbad0
        LD HL,(NMRDEST)
        LD (NMDSTN),HL
        LD DE,6
        ADD HL,DE
        LD DE,(NMRLIST)
        LD (HL),E
        INC HL
        LD (HL),D
        JP .good
.tailcl:
        LD DE,(NMRDOT)
        LD HL,(NMDSTN)
        PUSH HL
        LD H,D
        LD L,E
        CALL NMCLONE
        JR C,.tbad
        LD (NMTEMP),HL
        POP DE
        PUSH DE
        POP HL
        LD BC,6
        ADD HL,BC
        LD DE,(NMTEMP)
        LD (HL),E
        INC HL
        LD (HL),D
.good:
        LD HL,(NMDSTN)
        XOR A
        RET
.tbad0:
        SCF
        RET
.tbad:
        POP DE
        SCF
        RET

; Find a repeated binding anywhere in one template body.  Compound bodies
; need the same descriptor selection as a direct repeated symbol.
NMREPREF:
        LD (NMREPSRC),HL
        LD A,(HL)
        CP NMKSYM
        JR Z,.symbol
        CP NMKQUOT
        JR Z,.quote
        CP NMKLIST
        JR Z,.list
.none:
        XOR A
        RET
.symbol:
        CALL NMLOOK
        OR A
        JR Z,.none
        LD HL,(NMMVALP)
        LD A,(HL)
        CP NMKREP
        JR NZ,.none
        LD (NMRDESC),HL
        CALL NMREPCTX
        RET C
        LD (NMRDESC),HL
        LD A,(HL)
        CP NMKREP
        JR NZ,.none
        LD A,1
        RET
.quote:
        LD HL,(NMREPSRC)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.none
        LD H,D
        LD L,E
        JP NMREPREF
.list:
        LD HL,(NMREPSRC)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMRSCAN),DE
.children:
        LD HL,(NMRSCAN)
        LD A,H
        OR L
        JR Z,.tail
        PUSH HL
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMRSCAN),DE
        POP HL
        PUSH DE
        CALL NMREPREF
        POP DE
        OR A
        JR NZ,.found
        LD (NMRSCAN),DE
        JR .children
.tail:
        LD HL,(NMREPSRC)
        INC HL
        LD A,(HL)
        AND 1
        JR Z,.none
        LD HL,(NMREPSRC)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.none
        LD H,D
        LD L,E
        JP NMREPREF
.found:
        LD A,1
        RET

; Select one capture cell by its zero-based word index.
NMREPONE:
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
.loop:
        LD A,D
        OR E
        JP Z,.bad
        LD A,B
        OR C
        JP Z,.value
        LD HL,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        DEC BC
        JP .loop
.value:
        LD HL,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        XOR A
        RET
.bad:
        SCF
        RET

; Follow the active template path through nested repetition roots.
NMREPCTX:
        LD A,(NMPATHN)
        OR A
        RET Z
        LD (NMPTHREM),A
        LD HL,NMPATH
        LD (NMPTHPTR),HL
        LD HL,(NMRDESC)
        LD (NMPTHCUR),HL
.loop:
        LD HL,(NMPTHPTR)
        LD C,(HL)
        INC HL
        LD B,(HL)
        INC HL
        LD (NMPTHPTR),HL
        LD HL,(NMPTHCUR)
        CALL NMREPONE
        JP C,.bad
        LD (NMPTHCUR),HL
        LD A,(NMPTHREM)
        DEC A
        LD (NMPTHREM),A
        JP Z,.done
        LD A,(HL)
        CP NMKREP
        JP NZ,.bad
        JP .loop
.done:
        LD HL,(NMPTHCUR)
        XOR A
        RET
.bad:
        SCF
        RET

; Push and pop the current repetition index on the bounded template path.
NMPTHPSH:
        LD A,(NMPATHN)
        CP NMPTHMX
        JP NC,.bad
        LD C,A
        LD B,0
        LD HL,NMPATH
        ADD HL,BC
        ADD HL,BC
        LD DE,(NMREPIDX)
        LD (HL),E
        INC HL
        LD (HL),D
        INC A
        LD (NMPATHN),A
        XOR A
        RET
.bad:
        SCF
        RET

NMPTHPOP:
        LD A,(NMPATHN)
        OR A
        JP Z,.bad
        DEC A
        LD (NMPATHN),A
        XOR A
        RET
.bad:
        SCF
        RET

; Select the value at the active nested template path.
NMREPSEL:
        LD (NMRDESC),HL
        LD A,(NMPATHN)
        OR A
        JP Z,.bad
        JP NMREPCTX
.bad:
        SCF
        RET

; Append the nodes captured by one repeated template body.  A repetition
; descriptor stores linked capture cells and a count; NMREPREF permits the
; body to contain several bound variables.
NMREPTMP:
        LD (NMREPDST),DE
        LD DE,(NMSRCN)
        LD (NMREPPAR),DE
        LD (NMRPAT),HL
        CALL NMREPREF
        JP C,.bad
        OR A
        JP Z,.bad
        LD HL,(NMRDESC)
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMRCNT),DE
        LD A,(NMREPMOD)
        LD (NMREPSAV),A
        LD A,1
        LD (NMREPMOD),A
        XOR A
        LD (NMREPIDX),A
        LD (NMREPIDX+1),A
.rloop:
        LD HL,(NMRCNT)
        LD A,H
        OR L
        JP Z,.done
        LD HL,(NMREPDST)
        PUSH HL
        LD HL,(NMRPAT)
        PUSH HL
        LD HL,(NMREPPAR)
        PUSH HL
        LD HL,(NMRCNT)
        PUSH HL
        LD HL,(NMREPIDX)
        PUSH HL
        LD A,(NMREPSAV)
        PUSH AF
        CALL NMPTHPSH
        JP C,.pathbad
        LD HL,(NMRPAT)
        CALL NMCLONE
        LD A,0
        JP NC,.cstat
        LD A,1
.cstat:
        LD (NMREPCAR),A
        LD A,(NMREPCAR)
        OR A
        JP NZ,.cclean
        LD (NMTEMP),HL
.cclean:
        CALL NMPTHPOP
        POP AF
        LD (NMREPSAV),A
        POP HL
        LD (NMREPIDX),HL
        POP HL
        LD (NMRCNT),HL
        POP HL
        LD (NMREPPAR),HL
        POP HL
        LD (NMRPAT),HL
        POP HL
        LD (NMREPDST),HL
        LD A,(NMREPCAR)
        OR A
        JP NZ,.clonebad
        LD HL,(NMTEMP)
        LD DE,(NMREPDST)
        CALL NMAPPEND
        LD HL,(NMREPIDX)
        INC HL
        LD (NMREPIDX),HL
        LD HL,(NMRCNT)
        DEC HL
        LD (NMRCNT),HL
        JP .rloop
.pathbad:
        POP AF
        LD (NMREPSAV),A
        POP HL
        LD (NMREPIDX),HL
        POP HL
        LD (NMRCNT),HL
        POP HL
        LD (NMREPPAR),HL
        POP HL
        LD (NMRPAT),HL
        POP HL
        LD (NMREPDST),HL
        LD A,(NMREPSAV)
        LD (NMREPMOD),A
        JP .bad
.done:
        LD A,(NMREPSAV)
        LD (NMREPMOD),A
        LD DE,(NMREPPAR)
        LD (NMSRCN),DE
        LD DE,(NMREPDST)
        LD (NMDSTN),DE
        XOR A
        RET
.clonebad:
        LD A,(NMREPSAV)
        LD (NMREPMOD),A
.bad:
        SCF
        RET

; Copy one complete node record from NMSRCN to NMDSTN.
NMCOPY:
        LD HL,(NMSRCN)
        LD DE,(NMDSTN)
        LD B,NMNODEW
.loop:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ .loop
        RET

;-------------------------------------------------------------------------
; Ordered macro-clause registry
;-------------------------------------------------------------------------

; Register one bounded macro clause.  The compiler's declaration reader will
; map define-syntax clauses to this interface; keeping registration separate
; makes table-capacity failures atomic and preserves source order.
;
; CALL: HL=name symbol node, DE=pattern root, BC=template root, IX=literal list.
NMREG:
        LD (NMACNAM),HL
        LD (NMMACPAT),DE
        LD (NMMACTMP),BC
        PUSH IX
        POP HL
        LD (NMMACLIT),HL
        LD HL,(NMMACPAT)
        LD A,H
        OR L
        JP Z,.bad
        LD HL,(NMMACTMP)
        LD A,H
        OR L
        JP Z,.bad
        LD HL,(NMACNAM)
        LD A,(HL)
        CP NMKSYM
        JP NZ,.bad
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD HL,NMMACS
        LD A,(NMMACN)
        LD B,A
.scan:
        LD A,B
        OR A
        JR Z,.space
        LD DE,(NMNAME)
        LD A,(HL)
        CP E
        JR NZ,.next
        INC HL
        LD A,(HL)
        CP D
        JR Z,.same
        DEC HL
        JR .next
.same:
        DEC HL
.next:
        LD DE,NMMACW
        ADD HL,DE
        DJNZ .scan
.space:
        LD A,(NMMACN)
        CP NMMAXM
        JP NC,.bad
        LD HL,NMMACS
        LD C,A
        LD B,0
        LD DE,NMMACW
.slot:
        LD A,B
        OR C
        JR Z,.store
        ADD HL,DE
        DEC C
        JR .slot
.store:
        LD DE,(NMNAME)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(NMMACPAT)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(NMMACTMP)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(NMMACLIT)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        PUSH HL
        LD HL,(NMACNAM)
        LD DE,17
        ADD HL,DE
        LD A,(HL)
        POP HL
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        LD A,(NMMACN)
        INC A
        LD (NMMACN),A
        XOR A
        RET
.bad:
        SCF
        RET

; Look up the first clause whose name is the first symbol in list HL.  A=1
; selects the record, records its index and installs its literal list.
NMLOOKM:
        LD (NMIVAL),HL
        LD A,(HL)
        CP NMKLIST
        JR NZ,.none
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD A,H
        OR L
        JR Z,.none
        LD (NMLOOKN),HL
        LD A,(HL)
        CP NMKSYM
        JR NZ,.none
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD HL,NMMACS
        LD A,(NMMACN)
        LD B,A
        XOR A
        LD (NMMACI),A
.scan:
        LD A,B
        OR A
        JR Z,.none
        LD DE,(NMNAME)
        LD A,(HL)
        CP E
        JR NZ,.next
        INC HL
        LD A,(HL)
        CP D
        JR NZ,.nextp
        DEC HL
        LD (NMMACP),HL
        PUSH HL
        LD DE,8
        ADD HL,DE
        LD A,(HL)
        LD HL,(NMLOOKN)
        LD DE,17
        ADD HL,DE
        CP (HL)
        POP HL
        JR NZ,.next
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMLITP),DE
        LD A,1
        RET
.nextp:
        DEC HL
.next:
        LD DE,NMMACW
        ADD HL,DE
        LD A,(NMMACI)
        INC A
        LD (NMMACI),A
        DJNZ .scan
.none:
        XOR A
        RET

; Expand the first matching ordered clause at input root HL.  A=1 means a
; macro was selected; A=0 returns the original root unchanged; carry means a
; named macro existed but no clause matched.
NMEXPMAC:
        LD (NMINROOT),HL
        CALL NMLOOKM
        OR A
        JP Z,.ordinary
.try:
        LD HL,(NMMACP)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        PUSH HL
        LD HL,(NMINROOT)
        EX DE,HL
        POP HL
        CALL NMMATCH
        JP NC,.matched
        LD A,(NMMACI)
        INC A
        LD (NMMACI),A
        LD B,A
        LD A,(NMMACN)
        CP B
        JR Z,.badmatch
        LD HL,(NMMACP)
        LD DE,NMMACW
        ADD HL,DE
        LD (NMMACP),HL
        LD DE,(NMINROOT)
        LD HL,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD HL,(NMMACP)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(NMNAME)
        LD A,E
        CP L
        JR NZ,.badmatch
        LD A,D
        CP H
        JR NZ,.badmatch
        LD HL,(NMMACP)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMLITP),DE
        JR .try
.matched:
        LD HL,(NMMACP)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        CALL NMSTEP
        RET C
        CALL NMEXPAND
        RET C
        LD A,1
        RET
.badmatch:
        SCF
        RET
.ordinary:
        LD HL,(NMINROOT)
        XOR A
        RET

; Count one macro rewrite before matching or cloning it.  A package may use
; the full 16-bit published rewrite budget, but the next rewrite is rejected
; before it can allocate or publish any generated syntax.
NMSTEP:
        PUSH HL
        LD HL,(NMREWCT)
        INC HL
        LD A,H
        OR L
        JR Z,.bad
        LD (NMREWCT),HL
        POP HL
        XOR A
        RET
.bad:
        POP HL
        SCF
        RET

; Recognise one define-syntax form and register all syntax-rules clauses.
; A=1 means a definition was consumed; A=0 means an ordinary form; carry
; means a malformed definition or a registry failure.
NMDECL:
        LD (NMSRCN),HL
        LD A,(HL)
        CP NMKLIST
        JP NZ,.ordinary
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD A,H
        OR L
        JP Z,.ordinary
        CALL NMSPDEF
        OR A
        JP Z,.ordinary
        LD HL,(NMSYMP)
        LD (NMACNAM),HL
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,.badform
        LD H,D
        LD L,E
        LD (NMACNAM),HL
        LD A,(HL)
        CP NMKSYM
        JP NZ,.badform
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,.badform
        LD H,D
        LD L,E
        LD (NMMACTMP),HL
        LD A,(HL)
        CP NMKLIST
        JP NZ,.badform
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD A,H
        OR L
        JP Z,.badform
        CALL NMSPSYN
        JP C,.badform
        LD HL,(NMMACTMP)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,.badform
        LD (NMMACLIT),DE
        LD H,D
        LD L,E
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,.badform
        LD (NMBODY),DE
        LD H,D
        LD L,E
        LD A,(HL)
        CP NMKLIST
        JP NZ,.badform
        LD (NMCLAUSE),DE
        XOR A
        LD (NMCLNUM),A
.count:
        LD HL,(NMCLAUSE)
        LD A,H
        OR L
        JP Z,.ctdone
        LD A,(HL)
        CP NMKLIST
        JP NZ,.badform
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,.badform
        LD H,D
        LD L,E
        LD A,(HL)
        CP NMKLIST
        JP NZ,.badform
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,.badform
        LD A,(NMCLNUM)
        INC A
        LD (NMCLNUM),A
        CP NMMAXM
        JR C,.ctnext
        JR Z,.ctnext
        JP .badform
.ctnext:
        LD HL,(NMCLAUSE)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMCLAUSE),DE
        JR .count
.ctdone:
        LD A,(NMCLNUM)
        OR A
        JP Z,.badform
        LD A,(NMMACN)
        LD B,A
        LD A,(NMCLNUM)
        ADD A,B
        CP NMMAXM
        JR C,.capacity
        JR Z,.capacity
        JP .badform
.capacity:
        ; A second top-level declaration may not append clauses to an
        ; already-defined macro. Clauses within this declaration are still
        ; registered below as one atomic group, so check the name once before
        ; the first slot is published.
        LD HL,(NMACNAM)
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD HL,NMMACS
        LD A,(NMMACN)
        LD B,A
.dup:
        LD A,B
        OR A
        JR Z,.newdef
        LD DE,(NMNAME)
        LD A,(HL)
        CP E
        JR NZ,.dupnext
        INC HL
        LD A,(HL)
        CP D
        JR Z,.badform
        DEC HL
.dupnext:
        LD DE,NMMACW
        ADD HL,DE
        DJNZ .dup
.newdef:
        LD DE,(NMBODY)
        LD (NMCLAUSE),DE
.register:
        LD HL,(NMCLAUSE)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMMACPAT),DE
        LD A,D
        OR E
        JP Z,.badform
        LD H,D
        LD L,E
        LD A,(HL)
        CP NMKLIST
        JP NZ,.badform
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMMACTMP),DE
        LD A,D
        OR E
        JP Z,.badform
        LD HL,(NMACNAM)
        LD DE,(NMMACPAT)
        LD BC,(NMMACTMP)
        LD IX,(NMMACLIT)
        CALL NMREG
        RET C
        LD HL,(NMCLAUSE)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMCLAUSE),DE
        LD A,D
        OR E
        JR NZ,.register
        LD A,1
        RET
.badform:
        SCF
        RET
.ordinary:
        LD HL,(NMSRCN)
        XOR A
        RET

; Expand the parsed top-level stream in source order.  Definitions are
; registered and removed from the output; ordinary roots are preserved and
; selected ordered-clause macro roots are cloned before output publication.
NMEXPALL:
        LD HL,(NMROOT)
        LD (NMCUR),HL
        XOR A
        LD (NMMACN),A
        LD (NMDDEP),A
        LD (NMOUTRT),A
        LD (NMOUTRT+1),A
        LD (NMOTAIL),A
        LD (NMOTAIL+1),A
.loop:
        LD HL,(NMCUR)
        LD A,H
        OR L
        JR Z,.done
        LD (NMTEMP),HL
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMCUR),DE
        LD HL,(NMTEMP)
        CALL NMDECL
        JP C,.fail
        OR A
        JR NZ,.loop
        XOR A
        LD (NMLXN),A
        LD (NMSCOPE),A
        LD (NMHDEP),A
        LD HL,(NMTEMP)
        CALL NMHMARK
        JP C,.fail
        ; Scope marking walks past a symbol node, so restore the root before
        ; macro lookup and output publication.
        LD HL,(NMTEMP)
        CALL NMDEEP
        JP C,.fail
        CALL NMOUTA
        JR .loop
.done:
        XOR A
        RET
.fail:
        SCF
        RET

; Link one generated or ordinary root into the private output chain.
NMOUTA:
        LD (NMOUTN),HL
        LD HL,(NMOUTRT)
        LD A,H
        OR L
        JR NZ,.append
        LD HL,(NMOUTN)
        LD (NMOUTRT),HL
        LD (NMOTAIL),HL
        RET
.append:
        LD HL,(NMOTAIL)
        LD DE,4
        ADD HL,DE
        LD DE,(NMOUTN)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(NMOUTN)
        LD (NMOTAIL),HL
        RET

; Select the expanded top-level chain for the existing event cursor.
NMOUTRW:
        LD HL,(NMOUTRT)
        LD (NMTRROOT),HL
        LD HL,(NMTRBASE)
        LD (NMTRSP),HL
        XOR A
        LD (NMEOF),A
        RET

; Compare one symbol node with an authored ASCII spelling.  The helper uses
; the existing interner spelling path, so declaration recognition does not
; depend on insertion order or an identity assigned by the reader.
NMSPNAM:
        LD A,(HL)
        CP NMKSYM
        JR NZ,.no
        LD (NMSYMP),HL
        LD (NMIVAL),DE
        LD A,B
        LD (NMLITN),A
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        CALL NMLOADS
        LD A,(LBUFLEN)
        LD C,A
        LD A,(NMLITN)
        CP C
        JR NZ,.no
        LD HL,LBUFFER
        LD DE,(NMIVAL)
        LD A,(NMLITN)
        LD B,A
.loop:
        LD A,(DE)
        LD C,A
        LD A,(HL)
        CP C
        JR NZ,.no
        INC DE
        INC HL
        DJNZ .loop
        XOR A
        RET
.no:
        SCF
        RET

NMSPDEF:
        LD DE,NMDEFT
        LD B,13
        CALL NMSPNAM
        JR C,.ordinary
        LD A,1
        RET
.ordinary:
        XOR A
        RET

NMSPSYN:
        LD DE,NMSYNT
        LD B,12
        JP NMSPNAM

NMDOT:
        LD A,(HL)
        CP NMKSYM
        JR NZ,.no
        LD DE,NMDOTT
        LD B,3
        JP NMSPNAM
.no:
        SCF
        RET

NMDEFT:  DB "define-syntax"
NMSYNT:  DB "syntax-rules"
NMDOTT:  DB "..."

; Find a binding for the symbol node in HL.  A=1 returns its node in
; NMMVALP; A=0 means the template identifier is introduced or free.
NMLOOK:
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD HL,NMBINDS
        LD A,(NMBINDN)
        LD B,A
.scan:
        LD A,B
        OR A
        JR Z,.none
        LD A,(HL)
        LD C,A
        INC HL
        LD A,(HL)
        LD (NMNHI),A
        INC HL
        LD E,(HL)
        INC HL
        LD A,(HL)
        LD D,A
        ; The value's low byte was loaded above; reload its high byte after
        ; advancing past the first value byte.
        INC HL
        LD A,(NMNAME)
        CP C
        JR NZ,.next
        LD A,(NMNAME+1)
        LD C,A
        LD A,(NMNHI)
        CP C
        JR NZ,.next
        LD (NMMVALP),DE
        LD A,1
        RET
.next:
        DJNZ .scan
.none:
        XOR A
        RET

; Return one syntax-stream event.  The current cursor traverses the parsed
; roots; the public macro cursor will select cloned expansion roots before
; this callback is connected to the native lowerer.
NMNEXT:
        LD A,(NMEOF)
        OR A
        JR NZ,.eof
.again:
        LD HL,(NMTRSP)
        LD DE,(NMTRBASE)
        OR A
        SBC HL,DE
        JR NZ,.frame
        LD HL,(NMTRROOT)
        LD A,H
        OR L
        JR NZ,.pushroot
        LD A,1
        LD (NMEOF),A
.eof:
        XOR A
        RET
.pushroot:
        LD (NMPUSHN),HL
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMTRROOT),DE
        LD HL,(NMPUSHN)
        CALL NMTPUSH
        JP C,.err
.frame:
        CALL NMTOP
        LD (NMTOPFR),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMTOPNO),DE
        CALL NMGETST
        LD DE,(NMTOPNO)
        LD A,(DE)
        CP NMKSYM
        JR Z,.atom
        CP NMKVAL
        JR Z,.atom
        CP NMKSTR
        JR Z,.atom
        CP NMKQUOT
        JR Z,.quote
        CP NMKLIST
        JR Z,.list
.err:
        SCF
        RET
.atom:
        CALL NMTEVAT
        PUSH AF
        PUSH HL
        CALL NMTPop
        POP HL
        POP AF
        RET
.quote:
        LD A,(NMTOPST)
        OR A
        JR NZ,.qdone
        LD A,1
        CALL NMSETST           ; State one waits for its child to finish.
        LD HL,(NMTOPNO)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        CALL NMTPUSH
        JP C,.err
        CALL NMSETLOC
        LD A,3
        OR A
        RET
.qdone:
        CALL NMTPop
        JP .again
.list:
        LD A,(NMTOPST)
        OR A
        JR Z,.lopen
        CP 1
        JR Z,.lc
        CP 2
        JR Z,.ltail
        ; State three emits the closing parenthesis and removes the frame.
        CALL NMSETLOC
        CALL NMTPop
        LD A,2
        OR A
        RET
.lopen:
        LD A,1
        CALL NMSETST
        LD HL,(NMTOPNO)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD (NMTEMP),HL
        LD HL,(NMTOPFR)
        LD DE,2
        ADD HL,DE
        LD DE,(NMTEMP)
        LD (HL),E
        INC HL
        LD (HL),D
        CALL NMSETLOC
        LD A,1
        OR A
        RET
.lc:
        LD HL,(NMTOPFR)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD A,H
        OR L
        JR NZ,.lchild
        LD HL,(NMTOPNO)
        INC HL
        LD A,(HL)
        AND 1
        JR Z,.lclose
        LD A,2
        CALL NMSETST
        CALL NMSETLOC
        LD A,4
        OR A
        RET
.lchild:
        LD (NMPUSHN),HL        ; Keep this child while finding its sibling.
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(NMTOPFR)
        PUSH HL
        LD BC,2
        ADD HL,BC
        LD (HL),E
        INC HL
        LD (HL),D
        POP HL
        LD HL,(NMPUSHN)
        CALL NMTPUSH
        JP C,.err
        JP .again
.ltail:
        LD A,3
        CALL NMSETST
        LD HL,(NMTOPNO)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        CALL NMTPUSH
        JP C,.err
        JP .again
.lclose:
        LD A,3
        CALL NMSETST
        CALL NMSETLOC
        CALL NMTPop
        LD A,2
        OR A
        RET

; Return atom event data from the node whose pointer is in NMTOPNO.
NMTEVAT:
        LD HL,(NMTOPNO)
        CALL NMSETLOC
        LD HL,(NMTOPNO)
        LD A,(HL)
        CP NMKSYM
        JR NZ,.plain
        LD A,5
        LD (NMEV),A
        JR .data
.plain:
        CP NMKSTR
        JR NZ,.scalar
        LD A,8
        LD (NMEV),A
        JR .data
.scalar:
        LD A,7
        LD (NMEV),A
.data:
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (RTAG),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD A,(NMEV)
        CP 5
        CALL Z,NMLOADS
        LD A,(NMEV)
        OR A
        RET

; Push a node pointer into the persistent traversal frame stack.
; Copy the parser's source location into one node.  HL is preserved.
NMSAVLOC:
        PUSH HL
        PUSH IX
        PUSH HL
        POP IX
        LD HL,(NMOFF)
        LD (IX+NMOFFS),L
        LD (IX+NMOFFS+1),H
        LD HL,(NMLINE)
        LD (IX+NMLINS),L
        LD (IX+NMLINS+1),H
        LD HL,(NMCOL)
        LD (IX+NMCOLS),L
        LD (IX+NMCOLS+1),H
        POP IX
        POP HL
        RET

; Restore a node's source location for a generated event or diagnostic.
NMSETLOC:
        PUSH IX
        LD IX,(NMTOPNO)
        LD L,(IX+NMOFFS)
        LD H,(IX+NMOFFS+1)
        LD (LTOKOFF),HL
        LD L,(IX+NMLINS)
        LD H,(IX+NMLINS+1)
        LD (LTOKLIN),HL
        LD L,(IX+NMCOLS)
        LD H,(IX+NMCOLS+1)
        LD (LTOKCOL),HL
        POP IX
        RET

NMTPUSH:
        LD (NMPUSHN),HL
        LD HL,(NMTRSP)
        LD (NMFRAME),HL
        LD DE,NMTRW
        ADD HL,DE
        LD DE,(NMEND)
        OR A
        SBC HL,DE
        JR C,.space
        JR Z,.space
        SCF
        RET
.space:
        LD HL,(NMFRAME)
        LD DE,NMPUSHN
        LD A,(DE)
        LD (HL),A
        INC HL
        INC DE
        LD A,(DE)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        LD HL,(NMFRAME)
        LD DE,NMTRW
        ADD HL,DE
        LD (NMTRSP),HL
        CALL NMTRACK
        RET

; HL returns the address of the top frame without changing the stack pointer.
NMTOP:
        LD HL,(NMTRSP)
        LD DE,NMTRW
        OR A
        SBC HL,DE
        RET

; Read or write the state byte in the top traversal frame.
NMGETST:
        LD HL,(NMTRSP)
        LD DE,NMTRW
        OR A
        SBC HL,DE
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        LD (NMTOPST),A
        RET

NMSETST:
        LD (NMTOPST),A
        LD HL,(NMTRSP)
        LD DE,NMTRW
        OR A
        SBC HL,DE
        LD DE,4
        ADD HL,DE
        LD (HL),A
        RET

; Remove the top six-byte frame.
NMTPop:
        LD HL,(NMTRSP)
        LD DE,NMTRW
        OR A
        SBC HL,DE
        LD (NMTRSP),HL
        RET

; Restore LBUFFER from the reader's symbol context for lowerer dispatch.
; Preserve the encoded symbol identity in HL for the event ABI.
NMLOADS:
        PUSH HL
        PUSH IX
        LD IX,(RSYMCTX)
        LD A,H
        AND 1FH
        LD H,A
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,DE              ; HL = identity * 3.
        LD E,(IX+0)
        LD D,(IX+1)
        ADD HL,DE
        INC HL
        INC HL
        LD A,(HL)
        LD (LBUFLEN),A
        DEC HL
        LD D,(HL)
        DEC HL
        LD E,(HL)
        LD L,(IX+4)
        LD H,(IX+5)
        ADD HL,DE
        LD DE,LBUFFER
        LD B,0
        LD C,A
        OR A
        JR Z,.done
        LDIR
.done:
        POP IX
        POP HL
        RET

;-------------------------------------------------------------------------
; The fixed compiler state follows in native-macro-state.asm.  The caller
; owns the arena; those words remain outside the 18-byte syntax records.
;-------------------------------------------------------------------------
