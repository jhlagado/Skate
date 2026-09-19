;=============================================================================
;  I3 native macro persistent state
;=============================================================================
;
;  This source part follows native-macro.asm so the code and its fixed state
;  retain one contiguous address range.  NMINIT clears NMREND..NMWEND before
;  the companion scope workspace is reset by NMHINIT.
;=============================================================================

NMREND:

NMBASE:   DW 0
NMSIZE:   DW 0
NMEND:    DW 0
NMTRBASE: DW 0
NMCAPPTR: DW 0
NMCAPMRK: DW 0
NMSAVPTR: DW 0
NMSAVCNT: DW 0
NMSAVSCP: DB 0
NMPTR:    DW 0
NMROOT:   DW 0
NMRTAIL:  DW 0
NMCOUNT:  DW 0
NMREWCT:  DW 0
NMTRROOT: DW 0
NMTRSP:   DW 0
NMTRHI:   DW 0
NMEOF:    DB 0
NMEV:     DB 0
NMTAG:    DB 0
NMVAL:    DW 0
NMOFF:    DW 0
NMLINE:   DW 0
NMCOL:    DW 0
NMTEMP:   DW 0
NMCHILD:  DW 0
NMATOMN:  DW 0
NMLITP:   DW 0
NMLITN:   DB 0
NMBINDN:  DB 0
NMMDEP:   DB 0
NMHAVE:   DB 0
NMFLAG:   DB 0
NMRESTOK: DB 0
NMHEAD:   DW 0
NMPAT:    DW 0
NMINP:    DW 0
NMSYMP:   DW 0
NMSYMI:   DW 0
NMNAME:   DW 0
NMNHI:    DB 0
NMINROOT: DW 0
NMRPAT:   DW 0
NMREPPT:  DW 0
NMRDOT:   DW 0
NMRSTART: DW 0
NMRCNT:   DW 0
NMREPLIT: DB 0
NMREPBS:  DB 0
NMREPCN:  DB 0
NMREPDP:  DB 0
NMREPCAR: DB 0
NMREPTP:  DW 0
NMPATHN:  DB 0
NMPTHREM: DB 0
NMPTHPTR: DW 0
NMPTHCUR: DW 0
NMREPLFT: DB 0
NMREPMOD: DB 0
NMREPSAV: DB 0
NMREPIDX: DW 0
NMSELIDX: DW 0
NMREPSRC: DW 0
NMRSCAN:  DW 0
NMRDESC:  DW 0
NMRLIST:  DW 0
NMRDEST:  DW 0
NMRAW:    DB 0
NMRAWSAV: DB 0
NMREPDST: DW 0
NMREPPAR: DW 0
NMRIT:    DW 0
NMRSTOP:  DW 0
NMLNODE:  DW 0
NMMVALP:  DW 0
NMIVAL:   DW 0
NMVTAG:   DB 0
NMVPAY:   DW 0
NMBINDS:  DS NMMAXB*4
NMREPTBL: DS NMMAXB*4*NMRMAXD
NMPATH:   DS NMPTHMX*2
NMSRCN:   DW 0
NMDSTN:   DW 0
NMSRCH:   DW 0
NMOUT:    DW 0
NMSCOPE:  DB 0
NMGENSCP: DB 0
NMDEFSCP: DB 0
NMMACN:   DB 0
NMMACI:   DB 0
NMMACS:   DS NMMAXM*NMMACW
NMMACP:   DW 0
NMLOOKN:  DW 0
NMACNAM:  DW 0
NMMACPAT: DW 0
NMMACTMP: DW 0
NMMACLIT: DW 0
NMBODY:   DW 0
NMCLAUSE: DW 0
NMCLNUM:  DB 0
NMCUR:    DW 0
NMOUTN:   DW 0
NMOUTRT:  DW 0
NMOTAIL:  DW 0
NMPUSHN:  DW 0
NMTOPFR:  DW 0
NMTOPNO:  DW 0
NMTOPST:  DB 0
NMPREV:   DW 0
NMCAND:   DW 0
NMFRAME:  DW 0
NMWORK:   DS 32
NMWEND:

; The underscore in a syntax-rules pattern is an anonymous wildcard.  Keep
; the spelling check here separate from literal matching so it never enters
; the bounded binding table.
NMWILD:
        PUSH HL
        PUSH DE
        LD DE,NMWILT
        LD B,1
        CALL NMSPNAM
        POP DE
        POP HL
        RET

NMWILT:  DB "_"

; Expand macro calls below each top-level root.  The walker rewrites child
; links in place, preserves sibling links across a replacement, and treats
; quoted data as opaque.  Its return path uses the native call stack only for
; the bounded syntax tree; arena and rewrite limits remain the hard guards.
NMDROOT:  DW 0
NMDLINK:  DW 0
NMDNEXT:  DW 0
NMDDEP:   DB 0

NMDEEP:
        LD A,(NMDDEP)
        CP NMTRN
        JR NC,NMDDF
        INC A
        LD (NMDDEP),A
NMDTRY:
        CALL NMEXPMAC
        JR C,NMDDC
        OR A
        JR Z,NMDSUB
        JR NMDTRY
NMDSUB:
        CALL NMDSCAN
        JR C,NMDDC
NMDDR:
        LD A,(NMDDEP)
        DEC A
        LD (NMDDEP),A
        XOR A
        RET
NMDDC:
        LD A,(NMDDEP)
        DEC A
        LD (NMDDEP),A
        SCF
        RET
NMDDF:
        SCF
        RET

NMDSCAN:
        LD A,(HL)
        CP NMKQUOT
        JP Z,NMDOK
        CP NMKLIST
        JP NZ,NMDOK
        PUSH HL
        LD DE,2
        ADD HL,DE
NMDLOOP:
        PUSH HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,NMDTAIL
        PUSH DE
        EX DE,HL
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        PUSH DE
        POP DE
        POP HL
        PUSH HL
        PUSH DE
        CALL NMDEEP
        JR C,NMDERR
        LD (NMDROOT),HL
        POP DE
        POP BC
        POP HL
        LD (NMDNEXT),DE
        LD (NMDLINK),HL
        LD HL,(NMDROOT)
        LD DE,4
        ADD HL,DE
        LD DE,(NMDNEXT)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(NMDLINK)
        LD DE,(NMDROOT)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(NMDROOT)
        LD DE,4
        ADD HL,DE
        JR NMDLOOP
NMDTAIL:
        POP DE
        POP HL
        PUSH HL
        LD DE,6
        ADD HL,DE
        PUSH HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,NMDTNUL
        PUSH DE
        POP HL
        PUSH HL
        CALL NMDEEP
        JR C,NMDTERR
        LD (NMDROOT),HL
        POP DE
        POP HL
        LD DE,(NMDROOT)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(NMDROOT)
        LD DE,4
        ADD HL,DE
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
NMDTDONE:
        POP HL
        XOR A
        RET
NMDTNUL:
        POP DE
        POP HL
        XOR A
        RET
NMDERR:
        POP DE
        POP DE
        POP DE
        POP HL
        SCF
        RET
NMDTERR:
        POP DE
        POP HL
        POP HL
        SCF
        RET
NMDOK:
        XOR A
        RET

; Record the highest traversal-stack watermark after a successful push.
NMTRACK:
        LD DE,(NMTRHI)
        OR A
        SBC HL,DE
        JR C,.done
        LD HL,(NMTRSP)
        LD (NMTRHI),HL
.done:
        XOR A
        RET

; Validate the arena watermarks before the lowerer can publish a package.
NMPLAN:
        LD HL,(NMPTR)
        LD DE,(NMCAPPTR)
        OR A
        SBC HL,DE
        JR C,.nodes
        JR Z,.nodes
        SCF
        RET
.nodes:
        LD HL,(NMTRHI)
        LD DE,(NMEND)
        OR A
        SBC HL,DE
        JR C,.ok
        JR Z,.ok
        SCF
        RET
.ok:
        XOR A
        RET
