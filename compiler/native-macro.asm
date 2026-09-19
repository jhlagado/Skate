;=============================================================================
;  I3 native syntax arena and lossless event stream
;=============================================================================
;
;  PURPOSE
;  -------
;  Retain one bounded source package as syntax nodes between the reader and
;  the native macro/lowering phases.  The arena is caller supplied: the code
;  image contains no fixed AST and the caller can release the overlay before
;  entering the evaluator.
;
;  The I3 slices retain quote, dotted lists, strings, scalar values and nested
;  structure in a bounded target arena without changing RNEXT's value ABI.
;  Ordered clause matching, terminal repetitions and dotted rest capture build
;  on these records before the remaining hygienic forms reach the lowerer.
;
;  PUBLIC INTERFACE
;  ----------------
;  NMINIT  HL=arena base, BC=arena bytes.  Reserves a 64-frame traversal stack.
;  NMPARSE Consumes RNEXT until EOF and builds linked top-level nodes.
;  NMREW   Rewinds the event cursor to the first top-level node.
;  NMNEXT  Returns one RNEXT-compatible event, or A=0 at stable EOF.
;
;  NODE (18 bytes)
;    +0 kind: 1 symbol, 2 scalar, 3 string, 4 list, 5 quote.
;    +1 flags: bit zero means the list has a dotted tail.
;    +2 first child pointer; +4 next sibling pointer; +6 dotted tail pointer.
;    +8 logical value tag; +9 two-byte logical value payload.
;    +11 source byte offset; +13 source line; +15 source column.
;    +17 one-byte scope mark; every node begins on an eighteen-byte step.
;
;  The parser preserves symbol identity and the reader's logical tag/payload.
;  NMNEXT restores a symbol's spelling to LBUFFER before returning it, because
;  the native lowerer uses that existing token buffer for operator dispatch.
;
;  ERROR
;  -----
;  Carry set means the source or arena could not be represented.  The parser
;  never publishes a partial root on failure.  A traversal stack overflow is
;  also terminal for the current arena until NMINIT is called again.
;
;  ATOM source; public names stay within eight characters.
;=============================================================================

NMNODEW EQU 18
NMTRW   EQU 6
NMTRN   EQU 64
NMTRBY  EQU NMTRW*NMTRN

NMKSYM  EQU 1
NMKVAL  EQU 2
NMKSTR  EQU 3
NMKLIST EQU 4
NMKQUOT EQU 5
NMKREP  EQU 6
NMKCAP  EQU 7
NMCAPW  EQU 6
NMOFFS  EQU 11
NMLINS  EQU 13
NMCOLS  EQU 15
NMSCOP  EQU 17

NMMAXB  EQU 16
NMMAXM  EQU 8
NMMACW  EQU 10
NMRMAXD EQU 8
NMPTHMX EQU 8
NMLXMAX EQU 32

;-------------------------------------------------------------------------
; Arena lifecycle
;-------------------------------------------------------------------------

; Configure the node area and reserve the traversal frames at its upper end.
NMINIT:
        LD (NMBASE),HL          ; Keep the caller's lower arena boundary.
        LD (NMSIZE),BC          ; Retain the configured extent for diagnostics.
        PUSH HL                 ; Compute the exclusive physical endpoint.
        ADD HL,BC
        JR C,.bad                ; A wrapped arena cannot be addressed safely.
        LD (NMEND),HL
        POP HL
        LD DE,NMTRBY
        LD HL,(NMEND)
        OR A
        SBC HL,DE               ; HL becomes the exclusive node-area endpoint.
        JR C,.bad               ; Require room for the complete frame stack.
        LD (NMTRBASE),HL
        LD (NMCAPPTR),HL
        LD (NMTRHI),HL
        LD HL,(NMBASE)
        LD (NMPTR),HL
        XOR A
        LD (NMROOT),A
        LD (NMROOT+1),A
        LD (NMRTAIL),A
        LD (NMRTAIL+1),A
        LD (NMCOUNT),A
        LD (NMCOUNT+1),A
        LD (NMREWCT),A
        LD (NMREWCT+1),A
        LD (NMTRSP),HL          ; Replaced by NMTRBASE in NMREW; clear now.
        LD (NMEOF),A
        LD HL,NMEOF
        LD DE,NMWEND
.clear:
        LD (HL),A
        INC HL
        PUSH HL
        OR A
        SBC HL,DE
        POP HL
        JR C,.clear
        JP NMHINIT
.bad:
        SCF
        RET

; Parse all top-level datums.  The reader remains the source of syntax errors.
NMPARSE:
        LD HL,(NMROOT)
        LD A,H
        OR L
        JR Z,.empty
        SCF                     ; A second parse would alias old nodes.
        RET
.empty:
        XOR A
        LD (NMEOF),A
.loop:
        CALL NMPONE
        RET C
        OR A
        JR Z,.done               ; RNEXT EOF is the only zero-kind result.
        CALL NMROOTA
        JR .loop
.done:
        XOR A
        RET

; Reset the persistent traversal cursor after a successful parse.
NMREW:
        LD HL,(NMROOT)
        LD (NMTRROOT),HL
        LD HL,(NMTRBASE)
        LD (NMTRSP),HL
        XOR A
        LD (NMEOF),A
        RET

;-------------------------------------------------------------------------
; Reader-to-node parser
;-------------------------------------------------------------------------

; Parse one datum.  A=0 means EOF; A=1 with HL=node means success.
NMPONE:
        CALL RNEXT
        RET C
        OR A
        JR Z,.eof
        LD (NMEV),A
        LD (NMVAL),HL
        LD A,(RTAG)
        LD (NMTAG),A
        LD HL,(LTOKOFF)
        LD (NMOFF),HL
        LD HL,(LTOKLIN)
        LD (NMLINE),HL
        LD HL,(LTOKCOL)
        LD (NMCOL),HL
        CALL NMPEVT
        RET C
        LD A,1
        RET
.eof:
        XOR A
        RET

; Interpret the already-read event in NMEV/NMVAL/NMTAG.
NMPEVT:
        LD A,(NMEV)
        CP 1
        JP Z,NMLIST
        CP 3
        JP Z,NMQUOT
        CP 5
        JP Z,NMATOM
        CP 7
        JP Z,NMATOM
        CP 8
        JP Z,NMATOM
        SCF                     ; Close, dot and unknown events are not datums.
        RET

; Build a quote node and its one child.
NMQUOT:
        CALL NMALLOC
        RET C
        PUSH HL                 ; Keep the quote node over recursive parsing.
        LD (HL),NMKQUOT
        CALL NMSAVLOC
        CALL NMPONE
        JR C,.fail
        OR A
        JR Z,.fail              ; Quote cannot be followed by EOF.
        POP DE
        LD (NMTEMP),DE          ; Keep the quote node while storing its child.
        PUSH IX
        PUSH DE
        POP IX
        LD (IX+2),L
        LD (IX+3),H
        POP IX
        LD HL,(NMTEMP)          ; Return the quote node, not its child.
        RET
.fail:
        POP HL
        SCF
        RET

; Build a list, recursively parsing children until its close event.
NMLIST:
        CALL NMALLOC
        RET C
        LD (HL),NMKLIST
        CALL NMSAVLOC
        PUSH HL                 ; Current list survives nested list calls.
.loop:
        CALL RNEXT
        JR C,.failpop
        OR A
        JR Z,.failpop           ; Reader should report unfinished lists first.
        CP 2
        JR Z,.close
        CP 4
        JR Z,.dot
        LD (NMEV),A
        LD (NMVAL),HL
        LD A,(RTAG)
        LD (NMTAG),A
        LD HL,(LTOKOFF)
        LD (NMOFF),HL
        LD HL,(LTOKLIN)
        LD (NMLINE),HL
        LD HL,(LTOKCOL)
        LD (NMCOL),HL
        CALL NMPEVT
        JR C,.failpop
        POP DE                  ; DE=current list, HL=child.
        CALL NMAPPEND
        PUSH DE
        JR .loop
.dot:
        POP DE                  ; DE=current list while the tail is parsed.
        PUSH DE
        CALL NMLFIRST           ; A=0 means no ordinary element preceded dot.
        JR Z,.failpop
        CALL NMPONE
        JR C,.failpop
        OR A
        JR Z,.failpop
        LD (NMTEMP),HL          ; Preserve the dotted tail over RNEXT close.
        CALL RNEXT
        JR C,.failpop
        CP 2
        JR NZ,.failpop
        POP DE                  ; Finish the list after consuming its close.
        LD HL,(NMTEMP)
        PUSH IX
        PUSH DE
        POP IX
        LD (IX+6),L
        LD (IX+7),H
        LD A,(IX+1)
        OR 1
        LD (IX+1),A
        POP IX
        EX DE,HL
        RET
.close:
        POP HL
        RET
.failpop:
        POP HL
        SCF
        RET

; A=0 when the list has no ordinary child yet.
NMLFIRST:
        PUSH IX
        PUSH DE
        POP IX
        LD A,(IX+2)
        OR (IX+3)
        POP IX
        RET

; Append HL as an ordinary child of list DE.  Return DE unchanged.
NMAPPEND:
        LD (NMCHILD),HL
        PUSH DE
        LD DE,4
        ADD HL,DE
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        POP DE
        PUSH IX
        PUSH DE
        POP IX
        LD A,(IX+2)
        OR (IX+3)
        JR NZ,.have
        LD HL,(NMCHILD)
        LD (IX+2),L
        LD (IX+3),H
        LD (IX+9),L           ; List payload is the last ordinary child pointer.
        LD (IX+10),H
        POP IX
        RET
.have:
        LD L,(IX+9)
        LD H,(IX+10)
        LD (NMPREV),HL
        LD HL,(NMCHILD)
        PUSH IX
        LD IX,(NMPREV)
        LD (IX+4),L           ; Previous last child's next pointer.
        LD (IX+5),H
        POP IX
        LD (IX+9),L
        LD (IX+10),H
        POP IX
        RET

; Store the current atom event in a fresh node.
NMATOM:
        CALL NMALLOC
        RET C
        LD (NMATOMN),HL
        LD A,(NMEV)
        CP 5
        JR Z,.sym
        CP 8
        JR Z,.str
        LD A,NMKVAL
        JR .kind
.sym:
        LD A,NMKSYM
        JR .kind
.str:
        LD A,NMKSTR
.kind:
        LD HL,(NMATOMN)
        LD (HL),A
        INC HL
        LD (HL),0
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL
        INC HL                 ; HL now points to +8 logical tag.
        INC HL
        LD A,(NMTAG)
        LD (HL),A
        INC HL
        LD DE,(NMVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(NMATOMN)
        CALL NMSAVLOC
        LD HL,(NMATOMN)
        XOR A
        RET

; Allocate and clear one node.  HL returns its address.
NMALLOC:
        LD HL,(NMPTR)
        LD (NMATOMN),HL
        LD DE,NMNODEW
        ADD HL,DE
        LD (NMCAND),HL
        LD DE,(NMCAPPTR)
        OR A
        SBC HL,DE
        JR C,.ok
        JR Z,.ok
        SCF
        RET
.ok:
        LD HL,(NMCAND)
        LD (NMPTR),HL
        LD HL,(NMATOMN)
        LD B,NMNODEW
        XOR A
.clear:
        LD (HL),A
        INC HL
        DJNZ .clear
        LD HL,(NMATOMN)
        LD HL,(NMCOUNT)
        INC HL
        LD (NMCOUNT),HL
        LD HL,(NMATOMN)
        XOR A
        RET

; Allocate one six-byte capture cell below the syntax-node arena.
; The cell stores a captured syntax pointer and a linked successor.
NMCAP:
        LD HL,(NMCAPPTR)
        LD DE,NMCAPW
        OR A
        SBC HL,DE
        JR C,.bad
        LD (NMCAND),HL
        LD DE,(NMPTR)
        OR A
        SBC HL,DE
        JR C,.bad
        LD HL,(NMCAND)
        LD (NMCAPPTR),HL
        LD (HL),NMKCAP
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        LD HL,(NMCAND)
        XOR A
        RET
.bad:
        SCF
        RET

; Allocate an eleven-byte repetition root in the capture overlay.  The count
; is a word at offset nine, so the high byte occupies offset ten.
NMCAPREP:
        LD HL,(NMCAPPTR)
        LD DE,11
        OR A
        SBC HL,DE
        JR C,.bad
        LD (NMCAND),HL
        LD DE,(NMPTR)
        OR A
        SBC HL,DE
        JR C,.bad
        LD HL,(NMCAND)
        LD (NMCAPPTR),HL
        LD B,11
        XOR A
.clear:
        LD (HL),A
        INC HL
        DJNZ .clear
        LD HL,(NMCAND)
        LD (HL),NMKREP
        XOR A
        RET
.bad:
        SCF
        RET

; Link one top-level node without changing its existing sibling pointer.
NMROOTA:
        LD (NMCHILD),HL
        LD HL,(NMROOT)
        LD A,H
        OR L
        JR NZ,.have
        LD HL,(NMCHILD)
        LD (NMROOT),HL
        LD (NMRTAIL),HL
        RET
.have:
        LD HL,(NMRTAIL)
        LD (NMPREV),HL
        LD HL,(NMCHILD)
        PUSH IX
        LD IX,(NMPREV)
        LD (IX+4),L
        LD (IX+5),H
        POP IX
        LD (NMRTAIL),HL
        RET

;-------------------------------------------------------------------------
; Lossless node traversal
;-------------------------------------------------------------------------

;-------------------------------------------------------------------------
; Bounded pattern matching
;-------------------------------------------------------------------------

; Install a list of literal symbol nodes.  The first symbol in the pattern
; root is always literal as well; the list supplies additional literals.
NMSETLIT:
        LD (NMLITP),HL
        XOR A
        LD (NMLITN),A
        RET

; Match HL (pattern) against DE (input).  A successful match leaves the
; bounded pattern-variable table available to a later template expansion.
NMMATCH:
        LD (NMPAT),HL
        LD (NMINP),DE
        LD DE,(NMCAPPTR)
        LD (NMCAPMRK),DE
        XOR A
        LD (NMBINDN),A
        LD (NMMDEP),A
        LD (NMHAVE),A
        LD (NMHEAD),A
        LD (NMHEAD+1),A
        LD (NMRESTOK),A
        LD A,(HL)
        CP NMKLIST
        JR NZ,.match
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.match
        LD H,D
        LD L,E
        LD A,(HL)
        CP NMKSYM
        JR NZ,.match
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMHEAD),DE
        LD A,1
        LD (NMHAVE),A
.match:
        LD HL,(NMPAT)
        LD DE,(NMINP)
        CALL NMMAT
        JR C,.fail
        XOR A
        RET
.fail:
        LD HL,(NMCAPMRK)
        LD (NMCAPPTR),HL
        XOR A
        LD (NMBINDN),A
        SCF
        RET

; One bounded recursive comparison.  NMMDEP protects the native stack from a
; malformed or deliberately deep pattern before any binding is published.
NMMAT:
        CALL NMDEPIN
        JP C,NMMFAIL
        LD A,(HL)
        CP NMKSYM
        JP Z,.sym
        LD C,A
        LD A,(DE)
        CP C
        JP NZ,NMMFAIL
        LD A,C
        CP NMKLIST
        JP Z,NMLSTM
        CP NMKQUOT
        JP Z,.quote
        CP NMKVAL
        JP Z,.value
        CP NMKSTR
        JP Z,.value
        JP NMMFAIL
.sym:
        LD (NMSYMP),HL
        LD (NMIVAL),DE
        CALL NMWILD
        JP NC,NMMDONE
        LD (NMIVAL),DE
        CALL NMISLIT
        OR A
        JR Z,.bind
        LD HL,(NMSYMP)
        LD DE,(NMIVAL)
        LD A,(DE)
        CP NMKSYM
        JP NZ,NMMFAIL
        PUSH DE
        PUSH HL
        CALL NMSCOPEQ
        POP HL
        POP DE
        JP NZ,NMMFAIL
        CALL NMSYMEQ
        JP NZ,NMMFAIL
        JP NMMDONE
.bind:
        LD HL,(NMSYMP)
        LD DE,(NMIVAL)
        CALL NMBIND
        JP C,NMMFAIL
        JP NMMDONE
.quote:
        LD BC,2
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD H,B
        LD L,C
        EX DE,HL
        LD BC,2
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD H,B
        LD L,C
        EX DE,HL
        CALL NMMAT
        JP C,NMMFAIL
        JP NMMDONE
.value:
        LD (NMIVAL),DE
        LD BC,8
        ADD HL,BC
        LD A,(HL)
        LD (NMVTAG),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMVPAY),DE
        LD HL,(NMIVAL)
        LD BC,8
        ADD HL,BC
        LD A,(NMVTAG)
        CP (HL)
        JP NZ,NMMFAIL
        INC HL
        LD A,(NMVPAY)
        CP (HL)
        JP NZ,NMMFAIL
        INC HL
        LD A,(NMVPAY+1)
        CP (HL)
        JP NZ,NMMFAIL
        JP NMMDONE

; Compare the two symbol payload words prepared by NMMAT.
NMSYMEQ:
        LD (NMSYMP),HL
        LD (NMSYMI),DE
        LD BC,9
        ADD HL,BC
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD HL,(NMSYMI)
        LD BC,9
        ADD HL,BC
        LD A,(NMNAME)
        CP (HL)
        RET NZ
        INC HL
        LD A,(NMNAME+1)
        CP (HL)
        RET

; Determine whether the symbol at HL is a literal.  The root head symbol is
; implicit; NMSETLIT's list supplies the explicit literal identifiers.
NMISLIT:
        LD (NMSYMP),HL
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        LD A,(NMHAVE)
        OR A
        JR Z,.table
        LD HL,(NMHEAD)
        LD DE,(NMNAME)
        LD A,E
        CP L
        JR NZ,.table
        LD A,D
        CP H
        JR Z,.yes
.table:
        LD HL,(NMLITP)
        LD A,H
        OR L
        JR Z,.no
        LD BC,2
        ADD HL,BC
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD A,H
        OR L
        JR Z,.no
.loop:
        LD (NMLNODE),HL
        LD A,(HL)
        CP NMKSYM
        JR NZ,.next
        LD DE,9
        ADD HL,DE
        LD A,(NMNAME)
        CP (HL)
        JR NZ,.nextp
        INC HL
        LD A,(NMNAME+1)
        CP (HL)
        JR Z,.yes
.nextp:
.next:
        LD HL,(NMLNODE)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD A,H
        OR L
        JR NZ,.loop
.no:
        XOR A
        RET
.yes:
        LD A,1
        RET

; Bind one pattern identifier to one input node, or check a repeated binding.
NMBIND:
        LD (NMMVALP),DE
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
        JR Z,.new
        LD A,(HL)
        LD C,A
        INC HL
        LD A,(HL)
        LD (NMNHI),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(NMNAME)
        CP C
        JR NZ,.next
        LD A,(NMNAME+1)
        LD C,A
        LD A,(NMNHI)
        CP C
        JR NZ,.next
        LD HL,(NMMVALP)
        LD A,E
        CP L
        JR NZ,.conflict
        LD A,D
        CP H
        JR NZ,.conflict
        XOR A
        RET
.next:
        DJNZ .scan
.new:
        LD A,(NMBINDN)
        CP NMMAXB
        JR NC,.bad
        LD HL,NMBINDS
        LD C,A
        LD B,0
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        LD DE,(NMNAME)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(NMMVALP)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(NMBINDN)
        INC A
        LD (NMBINDN),A
        XOR A
        RET
.conflict:
.bad:
        SCF
        RET

; Compare ordinary list children.  Dotted tails are checked by NMLSTM.
NMSEQ:
.loop:
        LD A,H
        OR L
        JR Z,.pend
        LD (NMRPAT),HL
        LD BC,4
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD H,B
        LD L,C
        LD A,H
        OR L
        JR Z,.ordinary
        LD (NMRDOT),HL
        PUSH DE
        CALL NMDOT
        POP DE
        JR C,.ordinary
        LD HL,(NMRDOT)
        LD BC,4
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD A,B
        OR C
        JP NZ,.bad
        LD HL,(NMRPAT)
        CALL NMREPEAT
        JR C,.bad
        LD DE,0
        LD HL,0
        JR .loop
.ordinary:
        LD HL,(NMRPAT)
        LD A,D
        OR E
        JP Z,.bad
        LD A,(NMRESTOK)
        PUSH AF
        PUSH HL
        PUSH DE
        CALL NMMAT
        JR C,.childbad
        POP DE
        POP HL
        POP AF
        LD (NMRESTOK),A
        LD BC,4
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        PUSH BC
        PUSH DE
        POP HL
        LD BC,4
        ADD HL,BC
        LD E,(HL)
        INC HL
        LD D,(HL)
        POP HL
        JR .loop
.childbad:
        POP DE
        POP HL
        POP AF
        LD (NMRESTOK),A
.bad:
        SCF
        RET
.pend:
        LD A,(NMRESTOK)
        OR A
        JR NZ,.ok
        LD A,D
        OR E
        JR NZ,.bad
.ok:
        XOR A
        RET

; Match one trailing pattern item followed by ellipsis.  Each iteration gets
; a private binding suffix; the suffixes are then collected into one bounded
; repetition descriptor per variable.  This preserves compound item bindings
; without copying the input syntax nodes.
NMREPEAT:
        LD (NMRPAT),HL
        LD (NMREPPT),HL
        LD A,(NMREPDP)
        CP NMRMAXD
        JP NC,.depthbad
        INC A
        LD (NMREPDP),A
        DEC A
        ; Each repetition depth owns one NMMAXB*4-byte descriptor partition.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD BC,NMREPTBL
        ADD HL,BC
        LD (NMREPTP),HL
        LD (NMRSTART),DE
        LD A,(NMBINDN)
        LD (NMREPBS),A
        XOR A
        LD (NMRCNT),A
        LD (NMRCNT+1),A
        LD (NMREPCN),A
        LD HL,(NMREPPT)
        PUSH DE
        CALL NMREPINI
        POP DE
        JP C,.bad
.rloop:
        LD A,D
        OR E
        JR Z,.finish
        LD A,(NMREPBS)
        LD (NMBINDN),A
        PUSH DE
        LD HL,(NMREPPT)
        PUSH HL
        LD A,(NMREPBS)
        PUSH AF
        LD A,(NMREPCN)
        PUSH AF
        LD HL,(NMRCNT)
        PUSH HL
        LD A,(NMREPDP)
        PUSH AF
        LD HL,(NMREPTP)
        PUSH HL
        LD HL,(NMREPPT)
        CALL NMMAT
        JP NC,.mokay
        LD A,1
        JP .mstat
.mokay:
        XOR A
.mstat:
        LD (NMREPCAR),A
        POP HL
        LD (NMREPTP),HL
        POP AF
        LD (NMREPDP),A
        POP HL
        LD (NMRCNT),HL
        POP AF
        LD (NMREPCN),A
        POP AF
        LD (NMREPBS),A
        POP HL
        LD (NMREPPT),HL
        POP DE
        LD A,(NMREPCAR)
        OR A
        JP NZ,.bad
        PUSH DE
        CALL NMREPACC
        POP DE
        JR C,.bad
        LD HL,(NMRCNT)
        INC HL
        LD (NMRCNT),HL
        ; The published repetition limit is 510 (0x01FE); reject 511.
        LD A,H
        CP 1
        JR C,.countok
        JR NZ,.bad
        LD A,L
        CP 255
        JR NC,.bad
.countok:
        LD HL,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        JR .rloop
.finish:
        LD A,(NMREPBS)
        LD (NMBINDN),A
        LD HL,(NMREPTP)
        LD A,(NMREPCN)
        LD B,A
.bind:
        LD A,B
        OR A
        JR Z,.ok
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (NMNAME),DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (NMRDESC),DE
        PUSH HL
        PUSH BC
        CALL NMREPBND
        POP BC
        POP HL
        JR C,.bad
        DJNZ .bind
.ok:
        LD A,(NMREPDP)
        DEC A
        LD (NMREPDP),A
        XOR A
        RET
.bad:
        LD A,(NMREPDP)
        DEC A
        LD (NMREPDP),A
        SCF
        RET
.depthbad:
        SCF
        RET

; Predeclare every variable in one repeated pattern item.  This creates an
; empty descriptor before matching, so a compound repetition can expand to
; zero items without a special template case.
NMREPINI:
        LD (NMREPSRC),HL
        LD A,(HL)
        CP NMKSYM
        JR Z,.symbol
        CP NMKLIST
        JP NZ,.done
        LD HL,(NMREPSRC)
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
.children:
        PUSH DE
        LD H,D
        LD L,E
        CALL NMDOT
        POP DE
        JP NC,.tail
        LD A,D
        OR E
        JP Z,.tail
        PUSH DE
        LD H,D
        LD L,E
        CALL NMREPINI
        POP DE
        JP C,.bad
        LD H,D
        LD L,E
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        JP .children
.tail:
        LD HL,(NMREPSRC)
        INC HL
        LD A,(HL)
        AND 1
        JP Z,.done
        LD HL,(NMREPSRC)
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,.done
        LD H,D
        LD L,E
        JP NMREPINI
.symbol:
        PUSH HL
        CALL NMDOT
        POP HL
        JP NC,.done
        PUSH HL
        CALL NMISLIT
        POP HL
        OR A
        JP NZ,.done
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (NMNAME),DE
        JP NMREPGET
.done:
        XOR A
        RET
.bad:
        SCF
        RET

; Collect the bindings created by the current repetition into NMREPACC.
NMREPACC:
        LD A,(NMREPBS)
        LD C,A
        LD B,0
        LD HL,NMBINDS
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        LD A,(NMBINDN)
        SUB C
        LD (NMREPLFT),A
.loop:
        LD A,(NMREPLFT)
        OR A
        JR Z,.done
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (NMNAME),DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (NMMVALP),DE
        LD (NMRSCAN),HL
        CALL NMREPGET
        JR C,.bad
        LD DE,(NMMVALP)
        CALL NMCAPADD
        JR C,.bad
        LD HL,(NMRSCAN)
        LD A,(NMREPLFT)
        DEC A
        LD (NMREPLFT),A
        JR .loop
.done:
        LD A,(NMREPBS)
        LD (NMBINDN),A
        XOR A
        RET
.bad:
        SCF
        RET

; Find or create the accumulator descriptor for NMNAME.
NMREPGET:
        LD HL,(NMREPTP)
        LD A,(NMREPCN)
        LD B,A
.scan:
        LD A,B
        OR A
        JR Z,.new
        LD DE,(NMNAME)
        LD A,(HL)
        CP E
        JR NZ,.next
        INC HL
        LD A,(HL)
        CP D
        JR NZ,.prev
        DEC HL
        LD DE,2
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        XOR A
        RET
.prev:
        DEC HL
.next:
        LD DE,4
        ADD HL,DE
        DJNZ .scan
.new:
        LD A,(NMREPCN)
        CP NMMAXB
        JR NC,.bad
        LD C,A
        LD B,0
        LD HL,(NMREPTP)
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        PUSH HL
        CALL NMCAPREP
        JR C,.badpop
        LD (NMRDESC),HL
        POP DE
        LD HL,(NMNAME)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD HL,(NMRDESC)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        LD A,(NMREPCN)
        INC A
        LD (NMREPCN),A
        LD HL,(NMRDESC)
        XOR A
        RET
.badpop:
        POP DE
.bad:
        SCF
        RET

; Publish one accumulated name/descriptor pair in the normal binding table.
NMREPBND:
        LD A,(NMBINDN)
        CP NMMAXB
        JR NC,.bad
        LD C,A
        LD B,0
        LD HL,NMBINDS
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        ADD HL,BC
        LD DE,(NMNAME)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD DE,(NMRDESC)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(NMBINDN)
        INC A
        LD (NMBINDN),A
        XOR A
        RET
.bad:
        SCF
        RET

; Append one captured syntax pointer to a repetition descriptor.
NMCAPADD:
        LD (NMRDESC),HL
        LD (NMMVALP),DE
        CALL NMCAP
        JR C,.bad
        LD (NMTEMP),HL
        LD HL,(NMTEMP)
        LD DE,2
        ADD HL,DE
        LD DE,(NMMVALP)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(NMRDESC)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.first
        LD (NMPREV),DE
        LD HL,(NMPREV)
        LD DE,4
        ADD HL,DE
        LD DE,(NMTEMP)
        LD (HL),E
        INC HL
        LD (HL),D
        JR .last
.first:
        LD HL,(NMRDESC)
        LD DE,2
        ADD HL,DE
        LD DE,(NMTEMP)
        LD (HL),E
        INC HL
        LD (HL),D
.last:
        LD HL,(NMRDESC)
        LD DE,4
        ADD HL,DE
        LD DE,(NMTEMP)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(NMRDESC)
        LD DE,9
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC DE
        LD (HL),D
        DEC HL
        LD (HL),E
        XOR A
        RET
.bad:
        SCF
        RET

; Match list shape, ordinary children and (when present) dotted tails.
NMLSTM:
        PUSH HL
        PUSH DE
        INC HL
        LD A,(HL)
        AND 1
        LD (NMFLAG),A
        INC DE
        LD A,(DE)
        AND 1
        LD C,A
        LD A,(NMFLAG)
        CP C
        JR Z,.sameflg
        OR A
        JP Z,.badpop
        LD A,1
        LD (NMRESTOK),A
        JR .flgdone
.sameflg:
        XOR A
        LD (NMRESTOK),A
.flgdone:
        POP DE
        POP HL
        PUSH HL
        PUSH DE
        LD BC,2
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD H,B
        LD L,C
        EX DE,HL
        LD BC,2
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD H,B
        LD L,C
        EX DE,HL
        CALL NMSEQ
        JP C,.badpop
        LD (NMRSTART),DE
        POP DE
        POP HL
        LD A,(NMRESTOK)
        OR A
        JR Z,.tailok
        PUSH HL
        CALL NMHASREP
        POP HL
        OR A
        JP NZ,NMMFAIL
        LD BC,6
        ADD HL,BC
        LD C,(HL)
        INC HL
        LD B,(HL)
        LD H,B
        LD L,C
        LD (NMRPAT),HL
        LD A,(HL)
        CP NMKSYM
        JP NZ,NMMFAIL
        LD DE,(NMRSTART)
        PUSH DE
        CALL NMISLIT
        POP DE
        OR A
        JP NZ,NMMFAIL
        LD HL,(NMRPAT)
        CALL NMREPEAT
        JP C,NMMFAIL
        JP NMMDONE
.tailok:
        LD A,(NMFLAG)
        OR A
        JP Z,NMMDONE
        PUSH DE
        LD DE,6
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD H,D
        LD L,E
        LD (NMRPAT),HL
        POP DE
        LD H,D
        LD L,E
        LD BC,6
        ADD HL,BC
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(NMRPAT)
        CALL NMMAT
        JP C,NMMFAIL
        JP NMMDONE
.badpop:
        POP DE
        POP HL
        JP NMMFAIL

NMDEPIN:
        LD A,(NMMDEP)
        INC A
        CP 32
        JR NC,.bad
        LD (NMMDEP),A
        XOR A
        RET
.bad:
        SCF
        RET

NMMFAIL:
        LD A,(NMMDEP)
        DEC A
        LD (NMMDEP),A
        SCF
        RET

NMMDONE:
        LD A,(NMMDEP)
        DEC A
        LD (NMMDEP),A
        XOR A
        RET
