;=============================================================================
;  N9 native globals, derived forms and primitive values
;=============================================================================
;
;  The native front end evaluates its bounded event spool directly.  N9 adds
;  a small top-level binding table, so definitions are reserved before any
;  expression runs and a closure can refer forward to a later definition.
;  Global entries are six bytes: symbol identity, tag, payload and padding.
;  An uninitialised entry contains the private scalar FE05 and is never a
;  valid source value.
;
;  Derived forms stay evaluator operations.  LET builds a temporary procedure
;  descriptor over the same event range used by LAMBDA; AND, OR and COND walk
;  the spool and skip unselected forms without evaluating them.
;=============================================================================

; Translate a symbol token to a compact operator code.  Unknown names retain
; code zero and their interned payload for lexical lookup.
N6SCODE:
        LD A,(LBUFLEN)
        CP 3
        JP Z,N8SC3
        CP 1
        JP Z,N6SC1
        CP 2
        JP Z,N6SC2
        CP 4
        JP Z,N6SC4
        CP 5
        JP Z,N6SC5
        CP 6
        JP Z,N6SC6
        CP 7
        JP Z,N8SC7
        CP 8
        JP Z,N9SC8
        CP 9
        JP Z,N9SC9
        CP 10
        JP Z,N9SC10
        CP 11
        JP Z,N9SC11
        XOR A
        RET
N6SC1:
        LD A,(LBUFFER)
        CP '+'
        LD A,1
        RET Z
        LD A,(LBUFFER)
        CP '-'
        LD A,2
        RET Z
        LD A,(LBUFFER)
        CP '*'
        LD A,3
        RET Z
        LD A,(LBUFFER)
        CP '/'
        LD A,4
        RET Z
        LD A,(LBUFFER)
        CP '='
        LD A,24
        RET Z
        LD A,(LBUFFER)
        CP '<'
        LD A,25
        RET Z
        LD A,(LBUFFER)
        CP '>'
        LD A,26
        RET Z
        XOR A
        RET
N6SC2:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'i'
        JR Z,N6SCIF2
        CP 'o'
        JR Z,N6SCOR2
        CP '<'
        JR Z,N9LEQ2
        CP '>'
        JR Z,N9GEQ2
        JR N6SC0
N6SCIF2:
        INC HL
        LD A,(HL)
        CP 'f'
        LD A,5
        RET Z
        JR N6SC0
N6SCOR2:
        INC HL
        LD A,(HL)
        CP 'r'
        LD A,35
        RET Z
        JR N6SC0
N9LEQ2:
        INC HL
        LD A,(HL)
        CP '='
        LD A,27
        RET Z
        JR N6SC0
N9GEQ2:
        INC HL
        LD A,(HL)
        CP '='
        LD A,28
        RET Z
N6SC0:
        XOR A
        RET
N6SC4:
        LD HL,LBUFFER
        LD A,(HL)
        CP 's'
        JP NZ,N8SC4
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 't'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP '!'
        LD A,9
        RET Z
        JP N8SC4
N6SC5:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'z'
        JR Z,N6SCZ
        CP 'b'
        JP NZ,N8SC5
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N8SC5
        INC HL
        LD A,(HL)
        CP 'g'
        JP NZ,N8SC5
        INC HL
        LD A,(HL)
        CP 'i'
        JP NZ,N8SC5
        INC HL
        LD A,(HL)
        CP 'n'
        LD A,6
        RET Z
        JP N8SC5
N6SCZ:
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP '?'
        LD A,8
        RET Z
        JP N8SC5
; N8 data and console operator names. Unknown names retain code zero.
N8SC3:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'a'
        JP Z,N9AND3
        CP 'l'
        JP Z,N9LET3
        CP 'n'
        JP Z,N9NOT3
        CP 'c'
        JR NZ,N8SCEQ
        INC HL
        LD A,(HL)
        CP 'a'
        JR Z,N8SCAR
        CP 'd'
        JR Z,N8SCCD
        XOR A
        RET
N8SCAR:
        INC HL
        LD A,(HL)
        CP 'r'
        LD A,12
        RET Z
        XOR A
        RET
N8SCCD:
        INC HL
        LD A,(HL)
        CP 'r'
        LD A,13
        RET Z
        XOR A
        RET
N8SCEQ:
        LD A,(LBUFFER)
        CP 'e'
        JR NZ,N8SCUNK
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'q'
        JR NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP '?'
        LD A,14
        RET Z
N8SCUNK:
        XOR A
        RET
N9AND3:
        INC HL
        LD A,(HL)
        CP 'n'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'd'
        LD A,34
        RET Z
        JP N8SCUNK
N9LET3:
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 't'
        LD A,36
        RET Z
        JP N8SCUNK
N9NOT3:
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 't'
        LD A,38
        RET Z
        JP N8SCUNK
N8SC4:
        LD A,(LBUFFER)
        CP 'c'
        JR Z,N8SCCON
        CP 'e'
        JR Z,N9ELSE4
        CP 'l'
        JP NZ,N8SCUNK
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'i'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 's'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 't'
        LD A,40
        RET Z
        JP N8SCUNK
N8SCCON:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'o'
        JR Z,N8SCCONS
        CP 'n'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'd'
        LD A,37
        RET Z
        JP N8SCUNK
N8SCCONS:
        INC HL
        LD A,(HL)
        CP 'n'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 's'
        JR Z,N8SCONSL
        CP 'd'
        LD A,37
        RET Z
        JP N8SCUNK
N8SCONSL:
        LD A,11
        RET
N9ELSE4:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'l'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 's'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'e'
        LD A,39
        RET Z
        JP N8SCUNK
N8SC5:
        LD A,(LBUFFER)
        CP 'q'
        JR Z,N8SCQ
        CP 'w'
        JR Z,N8SCW
        CP 'n'
        JR Z,N8SCN
        CP 'p'
        JR Z,N8SCP
        CP 'c'
        JP Z,ZCHAR8
        JP N8SCUNK
N8SCQ:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'u'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 't'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'e'
        LD A,10
        RET Z
        JP N8SCUNK
N8SCW:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'r'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'i'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 't'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'e'
        LD A,17
        RET Z
        JP N8SCUNK
N8SCN:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'u'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'l'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'l'
        LD A,15
        RET Z
        JP N8SCUNK
N8SCP:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'a'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'i'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP '?'
        LD A,16
        RET Z
        JP N8SCUNK
ZCHAR8:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'h'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'a'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'r'
        LD A,21
        RET Z
        JP N8SCUNK
N8SC7:
        LD A,(LBUFFER)
        CP 'd'
        JR Z,N8SCD
        CP 's'
        JR Z,N8SCS
        CP 'n'
        JR Z,N9NUM7
        JP N8SCUNK
N8SCD:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'i'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 's'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'p'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'l'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'a'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'y'
        LD A,18
        RET Z
        JP N8SCUNK
N8SCS:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'y'
        JR Z,N8SCSP
        CP 't'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'i'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'n'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'g'
        LD A,20
        RET Z
        JP N8SCUNK
N8SCSP:
        INC HL
        LD A,(HL)
        CP 'm'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'b'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'l'
        LD A,19
        RET Z
        JP N8SCUNK
N9NUM7:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'u'
        JP NZ,N8SCNL
        INC HL
        LD A,(HL)
        CP 'm'
        JP NZ,N8SCNL
        INC HL
        LD A,(HL)
        CP 'b'
        JP NZ,N8SCNL
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N8SCNL
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N8SCNL
        INC HL
        LD A,(HL)
        CP '?'
        LD A,29
        RET Z
        JP N8SCNL
N8SCNL:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'e'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'w'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'l'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'i'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'n'
        JP NZ,N8SCUNK
        INC HL
        LD A,(HL)
        CP 'e'
        LD A,22
        RET Z
        JP N8SCUNK
N6SC6:
        LD A,(LBUFFER)
        CP 'd'
        JR Z,N9DEF6
        CP 'l'
        JP NZ,N6SC0
        LD HL,LBUFFER
        LD A,(HL)
        INC HL
        LD A,(HL)
        CP 'a'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'm'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'b'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'd'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'a'
        LD A,7
        RET Z
        XOR A
        RET
N9DEF6:
        LD HL,LBUFFER+1
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'f'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'i'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'n'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'e'
        LD A,23
        RET Z
        JP N6SC0

N9SC8:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'b'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'l'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'a'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'n'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP '?'
        LD A,30
        RET Z
        JP N6SC0

N9SC9:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'r'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'a'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'd'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP '-'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'c'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'h'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'a'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'r'
        LD A,32
        RET Z
        JP N6SC0

N9SC10:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'p'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'c'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'd'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'u'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP '?'
        LD A,31
        RET Z
        JP N6SC0

N9SC11:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'f'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP '-'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'b'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'j'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 'c'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP 't'
        JP NZ,N6SC0
        INC HL
        LD A,(HL)
        CP '?'
        LD A,33
        RET Z
        JP N6SC0


;-------------------------------------------------------------------------
;  Reserve every definition before evaluating the first top-level form.
;-------------------------------------------------------------------------

N9RESV:
        XOR A
        LD (N9GCOUNT),A
        LD HL,N6SPOOLB
        LD (N9SCANP),HL
        LD HL,(N6SPLEN)
        LD (N9SCANL),HL
N9RLOOP:
        LD HL,(N9SCANL)
        LD A,H
        OR L
        JP Z,N9RINIT
        LD HL,(N9SCANP)
        LD A,(HL)
        CP 1
        JP NZ,N9RNEXT
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        CP 5
        JP NZ,N9RNEXT
        INC HL
        LD A,(HL)
        CP 23
        JP NZ,N9RNEXT
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        CP 5
        JP Z,N9RVAR
        CP 1
        JP NZ,N9RNEXT
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        CP 5
        JP NZ,N9RNEXT
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL N9GADD
        RET C
        JP N9RNEXT
N9RVAR:
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL N9GADD
        RET C
N9RNEXT:
        LD HL,(N9SCANP)
        LD DE,4
        ADD HL,DE
        LD (N9SCANP),HL
        LD HL,(N9SCANL)
        LD DE,4
        OR A
        SBC HL,DE
        LD (N9SCANL),HL
        JP N9RLOOP

; Fill the reserved slots with the private uninitialised marker.
N9RINIT:
        LD A,(N9GCOUNT)
        OR A
        JP Z,N9RGOOD
        LD B,A
        LD HL,N9GBASE
N9RILP:
        INC HL
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD (HL),5
        INC HL
        LD (HL),0FEH
        INC HL
        LD (HL),0
        INC HL
        DJNZ N9RILP
N9RGOOD:
        XOR A
        RET

; Add a symbol identity in HL unless it is already reserved.
N9GADD:
        LD (N9GID),HL
        LD A,(N9GCOUNT)
        OR A
        JR Z,N9GNEW
        LD B,A
        LD DE,N9GBASE
N9GSCAN:
        LD HL,(N9GID)
        LD A,(DE)
        CP L
        JR NZ,N9GNEXT
        INC DE
        LD A,(DE)
        DEC DE
        CP H
        RET Z
N9GNEXT:
        LD HL,6
        ADD HL,DE
        EX DE,HL
        DJNZ N9GSCAN
N9GNEW:
        LD A,(N9GCOUNT)
        CP 64
        JP NC,N6CAP
        LD E,A
        LD D,0
        LD H,0
        LD L,A
        ADD HL,HL
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,DE
        LD DE,N9GBASE
        ADD HL,DE
        LD DE,(N9GID)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD (HL),5
        INC HL
        LD (HL),0FEH
        INC HL
        LD (HL),A
        LD A,(N9GCOUNT)
        INC A
        LD (N9GCOUNT),A
        XOR A
        RET

; Find a reserved global.  Carry means absent or still uninitialised;
; N9FOUND distinguishes those cases for symbol resolution.
N9GLOOK:
        LD (N9GID),HL
        XOR A
        LD (N9FOUND),A
        LD A,(N9GCOUNT)
        LD B,A
        LD A,B
        OR A
        JP Z,N9GMISS
        LD DE,N9GBASE
N9GLP:
        LD HL,(N9GID)
        LD A,(DE)
        CP L
        JR NZ,N9GLNEXT
        INC DE
        LD A,(DE)
        DEC DE
        CP H
        JP Z,N9GFND
N9GLNEXT:
        LD HL,6
        ADD HL,DE
        EX DE,HL
        DJNZ N9GLP
N9GMISS:
        SCF
        RET
N9GFND:
        LD A,1
        LD (N9FOUND),A
        INC DE
        INC DE
        LD A,(DE)
        LD (N9GTAG),A
        INC DE
        LD A,(DE)
        LD L,A
        INC DE
        LD A,(DE)
        LD H,A
        LD A,(N9GTAG)
        OR A
        JR NZ,N9GGOOD
        LD A,H
        CP 0FEH
        JR NZ,N9GGOOD
        LD A,L
        CP 5
        JP Z,N9GMISS
N9GGOOD:
        LD A,(N9GTAG)
        OR A
        RET

; Store N6RTAG:N6RVAL in the global named by HL.  Define may replace an
; existing value; set! requires that the slot has already been initialised.
N9GDEFV:
        XOR A
        LD (N9GMODE),A
        JP N9GPUT
N9GSETV:
        LD A,1
        LD (N9GMODE),A
N9GPUT:
        LD (N9GID),HL
        LD A,(N9GCOUNT)
        LD B,A
        LD A,B
        OR A
        JP Z,N9GPMISS
        LD DE,N9GBASE
N9GPLP:
        LD HL,(N9GID)
        LD A,(DE)
        CP L
        JR NZ,N9GPNEXT
        INC DE
        LD A,(DE)
        DEC DE
        CP H
        JP Z,N9GPFND
N9GPNEXT:
        LD HL,6
        ADD HL,DE
        EX DE,HL
        DJNZ N9GPLP
N9GPMISS:
        SCF
        RET
N9GPFND:
        LD A,(N9GMODE)
        OR A
        JP Z,N9GPWRT
        INC DE
        INC DE
        LD A,(DE)
        OR A
        JR NZ,N9GPWR
        INC DE
        LD A,(DE)
        LD L,A
        INC DE
        LD A,(DE)
        LD H,A
        LD A,H
        CP 0FEH
        JR NZ,N9GPBACK
        LD A,L
        CP 5
        JP Z,N9GPMISS
N9GPBACK:
        DEC DE
        DEC DE
        JR N9GPWR
N9GPWRT:
        INC DE
        INC DE
N9GPWR:
        LD A,(N6RTAG)
        LD (DE),A
        INC DE
        LD HL,(N6RVAL)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        XOR A
        LD (DE),A
        OR A
        RET

;-------------------------------------------------------------------------
;  Top-level sequencing and global definitions
;-------------------------------------------------------------------------

N9TOP:
        XOR A
        LD (N9TOPS),A
        LD HL,0
        LD (N6PC),HL
N9TOPLP:
        LD HL,(N6PC)
        LD DE,(N6SPLEN)
        OR A
        SBC HL,DE
        JP NC,N6BAD
        LD HL,N6SPOOLB
        LD DE,(N6PC)
        ADD HL,DE
        LD A,(HL)
        OR A
        JP Z,N9TOPDN
        CALL N6EXPR
        RET C
        LD (N4RTAG),A
        LD (N4RVAL),HL
        LD A,1
        LD (N9TOPS),A
        JP N9TOPLP
N9TOPDN:
        LD A,(N9TOPS)
        OR A
        JP Z,N6BAD
        LD A,(N4RTAG)
        LD HL,(N4RVAL)
        OR A
        RET

N9DEF:
        LD A,(N6DEPTH)
        OR A
        JP NZ,N6BAD
        CALL N6NEXT
        RET C
        CP 5
        JP Z,N9DEFVAR
        CP 1
        JP Z,N9DPROC
        JP N6BAD
N9DEFVAR:
        LD (N9DID),HL
        CALL N6NEXT
        RET C
        LD (N9KIND),A
        LD (N9DVAL),HL
        LD A,(N9KIND)
        LD HL,(N9DVAL)
        CALL N6EV
        RET C
        LD (N6RTAG),A
        LD (N6RVAL),HL
        CALL N6NEXT
        RET C
        CP 2
        JP NZ,N6BAD
        LD HL,(N9DID)
        CALL N9GDEFV
        RET C
        JP N6UNSP

N9DPROC:
        CALL N6NEXT
        RET C
        CP 5
        JP NZ,N6BAD
        LD (N9DID),HL
        CALL N9PROC
        RET C
        LD (N6RTAG),A
        LD (N6RVAL),HL
        LD HL,(N9DID)
        CALL N9GDEFV
        RET C
        JP N6UNSP

; Build a procedure descriptor for the shorthand (define (name args) body).
N9PROC:
        LD A,(N6CCOUNT)
        CP 16
        JP NC,N6CAP
        LD HL,(N6CLOSP)
        LD (N9LTDESC),HL
        LD HL,(N6PARMP)
        LD (N9LTPARM),HL
        LD (N6TMPP),HL
        XOR A
        LD (N6NARITY),A
N9PRLP:
        CALL N6NEXT
        RET C
        CP 2
        JR Z,N9PREND
        CP 5
        JP NZ,N6BAD
        LD DE,(N6TMPP)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (N6TMPP),DE
        LD A,(N6NARITY)
        INC A
        CP 9
        JP NC,N6BAD
        LD (N6NARITY),A
        JP N9PRLP
N9PREND:
        LD HL,(N9LTDESC)
        LD DE,6
        ADD HL,DE
        LD A,(N6NARITY)
        LD (HL),A
        LD HL,(N9LTDESC)
        LD DE,4
        ADD HL,DE
        LD DE,(N9LTPARM)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        LD HL,(N9LTDESC)
        LD DE,(N6PC)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        XOR A
        LD (N6SCNST),A
N9PRSCAN:
        CALL N6NEXT
        RET C
        CP 1
        JR Z,N9PROPN
        CP 2
        JR Z,N9PRCLS
        JP N9PRSCAN
N9PROPN:
        LD A,(N6SCNST)
        INC A
        LD (N6SCNST),A
        JP N9PRSCAN
N9PRCLS:
        LD A,(N6SCNST)
        OR A
        JR Z,N9PRDONE
        DEC A
        LD (N6SCNST),A
        JP N9PRSCAN
N9PRDONE:
        LD HL,(N6PC)
        LD DE,4
        OR A
        SBC HL,DE
        LD (N6CHKEND),HL
        LD HL,(N9LTDESC)
        INC HL
        INC HL
        LD DE,(N6CHKEND)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        CALL N6MAKEV
        RET C
        LD (N6TMPENV),HL
        LD HL,(N9LTDESC)
        LD DE,8
        ADD HL,DE
        LD DE,(N6TMPENV)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        LD HL,(N6CLOSP)
        LD DE,10
        ADD HL,DE
        LD (N6CLOSP),HL
        LD HL,(N6PARMP)
        LD DE,16
        ADD HL,DE
        LD (N6PARMP),HL
        LD A,(N6CCOUNT)
        INC A
        LD (N6CCOUNT),A
        LD A,2
        LD HL,(N9LTDESC)
        OR A
        RET

;-------------------------------------------------------------------------
;  Symbol values and primitive shadowing
;-------------------------------------------------------------------------

N9SYM:
        LD (N6LOOKID),HL
        CALL N9LOCAL
        JR NC,N9SYMRET
        LD HL,(N6LOOKID)
        CALL N9GLOOK
        JR NC,N9SYMRET
        LD A,(N9FOUND)
        OR A
        JP NZ,N6BAD
        LD A,(N6TAG)
        JP N9PRIMV
N9SYMRET:
        OR A
        RET

; Search only lexical frames.  Global fallback belongs to N9SYM, so the
; front-end can tell a local shadow from an intrinsic primitive.
N9LOCAL:
        LD A,(N6FCNT)
        OR A
        JR Z,N9LENV
        LD B,A
        LD HL,(N6FP)
N9LFRAME:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,(N6LOOKID)
        CP E
        JR NZ,N9LFNEXT
        LD A,(N6LOOKID+1)
        CP D
        JR Z,N9LFND
N9LFNEXT:
        LD DE,4
        ADD HL,DE
        DJNZ N9LFRAME
N9LENV:
        LD HL,(N6CENV)
N9LENVLP:
        LD A,H
        OR L
        JP Z,N9LMISS
        LD (N9ENV),HL
        INC HL
        INC HL
        LD A,(HL)
        OR A
        JR Z,N9LENVN
        LD B,A
        INC HL
        INC HL
        INC HL
        INC HL
N9LENVC:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,(N6LOOKID)
        CP E
        JR NZ,N9LENVN
        LD A,(N6LOOKID+1)
        CP D
        JR Z,N9LEFND
N9LENVN:
        LD DE,4
        ADD HL,DE
        DJNZ N9LENVC
N9LENVP:
        LD HL,(N9ENV)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP N9LENVLP
N9LFND:
        INC HL
        LD A,(HL)
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        OR A
        RET
N9LEFND:
        INC HL
        LD A,(HL)
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        OR A
        RET
N9LMISS:
        SCF
        RET

; A code and HL identity name a primitive head.  Carry says that the
; intrinsic dispatch remains valid; clear means local/global application wins.
N9OVR:
        LD (N9CODE),A
        LD (N6LOOKID),HL
        LD E,A
        LD D,0
        LD HL,N9PIDS
        ADD HL,DE
        LD A,(HL)
        CP 0FFH
        JP Z,N9OVNO
        LD HL,(N6HEADID)
        CALL N9LOCAL
        JP NC,N9OVYES
        LD HL,(N6HEADID)
        CALL N9GLOOK
        JP NC,N9OVYES
        LD A,(N9FOUND)
        OR A
        JP NZ,N9OVYES
N9OVNO:
        SCF
        RET
N9OVYES:
        OR A
        RET

; Translate an operator code to a first-class primitive value.
N9PRIMV:
        LD E,A
        LD D,0
        LD HL,N9PIDS
        ADD HL,DE
        LD A,(HL)
        CP 0FFH
        JP Z,N6BAD
        ADD A,20H
        LD L,A
        LD H,0FEH
        XOR A
        RET

;-------------------------------------------------------------------------
;  Primitive-value application and numeric comparisons
;-------------------------------------------------------------------------

N9PRIMA:
        LD A,H
        CP 0FEH
        JP NZ,N6BAD
        LD A,L
        CP 20H
        JP C,N6BAD
        CP 3CH
        JP NC,N6BAD
        SUB 20H
        LD (N9PID),A
        CP 4
        JR C,N9PARITH
        CP 9
        JP C,N9CMP
        CP 9
        JP Z,N8CONS
        CP 10
        JP Z,N8CAR
        CP 11
        JP Z,N8CDR
        CP 12
        JP Z,N8NULL
        CP 13
        JP Z,N8PAIRP
        CP 14
        JP Z,N8LIST
        CP 15
        JP Z,N8EQ
        CP 16
        JP Z,N9NOT
        CP 17
        JP Z,N9NUMP
        CP 18
        JP Z,N9BOOLP
        CP 19
        JP Z,N8SYMP
        CP 20
        JP Z,N9PROCP
        CP 21
        JP Z,N8STRP
        CP 22
        JP Z,N8CHARP
        CP 23
        JP Z,N8DISP
        CP 24
        JP Z,N8WRITE
        CP 25
        JP Z,N8NEWLN
        CP 26
        JP Z,N9READ
        CP 27
        JP Z,N9EOFP
        JP N6BAD
N9PARITH:
        INC A
        JP N6ARITH

N9CMPH:
        LD A,(N6TAG)
        LD E,A
        LD D,0
        LD HL,N9PIDS
        ADD HL,DE
        LD A,(HL)
        LD (N9PID),A
        JP N9CMP

N9CMP:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6NEXT
        JP C,N9CMERR
        LD (N9KIND),A
        LD (N9DVAL),HL
        LD A,(N9KIND)
        LD HL,(N9DVAL)
        CALL N6EV
        JP C,N9CMERR
        LD (N9LTAG),A
        LD (N9LVAL),HL
        CALL N6NEXT
        JP C,N9CMERR
        LD (N9KIND),A
        LD (N9DVAL),HL
        LD A,(N9KIND)
        LD HL,(N9DVAL)
        CALL N6EV
        JP C,N9CMERR
        LD (N9RTAG),A
        LD (N9RVAL),HL
        CALL N6NEXT
        JP C,N9CMERR
        CP 2
        JP NZ,N9CMERR
        LD A,(N9RTAG)
        LD B,A
        LD A,(N9LTAG)
        LD HL,(N9LVAL)
        LD DE,(N9RVAL)
        CALL NCMP
        JP C,N9CMERR
        LD (N9CCODE),HL
        LD A,(N9PID)
        CP 4
        JR Z,N9CMEQ
        CP 5
        JR Z,N9CMLT
        CP 6
        JR Z,N9CMGT
        CP 7
        JR Z,N9CMLE
        CP 8
        JR Z,N9CMGE
        JP N9CMERR
N9CMEQ:
        LD HL,(N9CCODE)
        LD A,H
        OR L
        JR Z,N9CMTRUE
        JR N9CMFALS
N9CMLT:
        LD HL,(N9CCODE)
        INC HL
        LD A,H
        OR L
        JR Z,N9CMTRUE
        JR N9CMFALS
N9CMGT:
        LD HL,(N9CCODE)
        DEC HL
        LD A,H
        OR L
        JR Z,N9CMTRUE
        JR N9CMFALS
N9CMLE:
        LD HL,(N9CCODE)
        INC HL
        LD A,H
        OR L
        JR Z,N9CMTRUE
        LD HL,(N9CCODE)
        LD A,H
        OR L
        JR Z,N9CMTRUE
        JR N9CMFALS
N9CMGE:
        LD HL,(N9CCODE)
        DEC HL
        LD A,H
        OR L
        JR Z,N9CMTRUE
        LD HL,(N9CCODE)
        LD A,H
        OR L
        JR Z,N9CMTRUE
N9CMFALS:
        POP AF
        LD (N6TCTX),A
        JP N8FALSE
N9CMTRUE:
        POP AF
        LD (N6TCTX),A
        JP N8TRUE
N9CMERR:
        POP AF
        LD (N6TCTX),A
        SCF
        RET

;-------------------------------------------------------------------------
;  Predicates and derived forms
;-------------------------------------------------------------------------

N9NUMP:
        CALL N8ONEVAL
        RET C
        CALL NCLASS
        JP C,N8FALSE
        JP N8TRUE

N9BOOLP:
        CALL N8ONEVAL
        RET C
        OR A
        JP NZ,N8FALSE
        LD A,H
        CP 0FEH
        JP NZ,N8FALSE
        LD A,L
        CP 0
        JP Z,N8TRUE
        CP 1
        JP Z,N8TRUE
        JP N8FALSE

N9PROCP:
        CALL N8ONEVAL
        RET C
        CP 2
        JP Z,N8TRUE
        OR A
        JP NZ,N8FALSE
        LD A,H
        CP 0FEH
        JP NZ,N8FALSE
        LD A,L
        CP 20H
        JP C,N8FALSE
        CP 3CH
        JP NC,N8FALSE
        JP N8TRUE

N9EOFP:
        CALL N8ONEVAL
        RET C
        OR A
        JP NZ,N8FALSE
        LD DE,0FE03H
        OR A
        SBC HL,DE
        JP Z,N8TRUE
        JP N8FALSE

N9NOT:
        CALL N8ONEVAL
        RET C
        OR A
        JP NZ,N8FALSE
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JP Z,N8TRUE
        JP N8FALSE

N9READ:
        CALL N6NEXT
        RET C
        CP 2
        JP NZ,N6BAD
        LD A,0
        LD HL,0FE03H
        OR A
        RET

; Skip the remaining elements of the current derived form.
N9SKREST:
        CALL N6NEXT
        RET C
        CP 2
        JR Z,N9SKDONE
        CALL N6SKIP
        JR N9SKREST
N9SKDONE:
        XOR A
        RET

; Evaluate AND and OR left-to-right, skipping after the first decisive value.
N9AND:
        XOR A
        LD (N9AFLAG),A
        LD A,1
        LD (N9AOP),A
        JP N9AOR
N9OR:
        XOR A
        LD (N9AFLAG),A
        LD (N9AOP),A
N9AOR:
        LD A,(N6TCTX)
        LD (N9ATCTX),A
        PUSH AF
        XOR A
        LD (N6TCTX),A
N9ALP:
        CALL N6NEXT
        JP C,N9AERR
        CP 2
        JP Z,N9AEMPTY
        LD (N9KIND),A
        LD (N9DVAL),HL
        CALL N9LAST
        JP C,N9AERR
        OR A
        JR Z,N9ANOT
        LD A,(N9ATCTX)
        JR N9ASET
N9ANOT:
        XOR A
N9ASET:
        LD (N6TCTX),A
        LD A,(N9KIND)
        LD HL,(N9DVAL)
        CALL N6EV
        JP C,N9AERR
        LD (N9ATAG),A
        LD (N9AVAL),HL
        LD A,(N6TF)
        OR A
        JP NZ,N9ATAIL
        LD A,1
        LD (N9AFLAG),A
        LD A,(N9AOP)
        OR A
        JR Z,N9AORCHK
        LD A,(N9ATAG)
        OR A
        JR NZ,N9ANEXT
        LD HL,(N9AVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JP Z,N9ASHORT
N9ANEXT:
        CALL N9ANEXTQ
        JP Z,N9ALAST
        JP N9ALP
N9AORCHK:
        LD A,(N9ATAG)
        OR A
        JR NZ,N9ASHORT
        LD HL,(N9AVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JR Z,N9ANEXT
N9ASHORT:
        CALL N9SKREST
        JP C,N9AERR
        LD A,(N9ATAG)
        LD HL,(N9AVAL)
        POP BC
        LD A,B
        LD (N6TCTX),A
        LD A,(N9ATAG)
        LD HL,(N9AVAL)
        OR A
        RET
N9ALAST:
        CALL N6NEXT
        JP C,N9AERR
        CP 2
        JP NZ,N9AERR
        LD A,(N9ATAG)
        LD HL,(N9AVAL)
        POP BC
        LD A,B
        LD (N6TCTX),A
        LD A,(N9ATAG)
        LD HL,(N9AVAL)
        OR A
        RET
N9ANEXTQ:
        LD HL,N6SPOOLB
        LD DE,(N6PC)
        ADD HL,DE
        LD A,(HL)
        CP 2
        RET

; Return A=1 when the current datum is the final datum before a close.  The
; reader cursor is restored so the caller can evaluate the datum normally.
N9LAST:
        LD HL,(N6PC)
        LD (N9CBPC),HL
        LD A,(N6TAG)
        LD (N9CBTAG),A
        LD A,(N9KIND)
        CALL N6SKIP
        RET C
        LD HL,N6SPOOLB
        LD DE,(N6PC)
        ADD HL,DE
        LD A,(HL)
        CP 2
        JR Z,N9LASTY
        LD A,(N9CBTAG)
        LD (N6TAG),A
        LD HL,(N9CBPC)
        LD (N6PC),HL
        XOR A
        RET
N9LASTY:
        LD A,(N9CBTAG)
        LD (N6TAG),A
        LD HL,(N9CBPC)
        LD (N6PC),HL
        LD A,1
        RET
N9AEMPTY:
        POP BC
        LD A,B
        LD (N6TCTX),A
        LD A,(N9AOP)
        OR A
        JR Z,N9AEMPTO
        LD A,0
        LD HL,0FE01H
        OR A
        RET
N9AEMPTO:
        LD A,0
        LD HL,0FE00H
        OR A
        RET
N9AERR:
        POP AF
        SCF
        RET
N9ATAIL:
        POP AF
        LD (N6TCTX),A
        XOR A
        RET

; LET evaluates initialisers in the outer scope, then invokes a descriptor
; whose body is the remaining event range.  This also gives nested LET the
; same frame lookup and mutation behavior as an ordinary procedure.
N9LET:
        LD A,(N6TCTX)
        LD (N9LTCTX),A
        PUSH AF
        XOR A
        LD (N6TCTX),A
        LD A,(N6CCOUNT)
        LD (N9LTOLD),A
        CP 16
        JP NC,N9LERR
        LD HL,(N6CLOSP)
        LD (N9LTDESC),HL
        LD HL,(N6PARMP)
        LD (N9LTPARM),HL
        LD (N6TMPP),HL
        XOR A
        LD (N9LTCNT),A
        CALL N6NEXT
        JP C,N9LERR
        CP 1
        JP NZ,N9LERR
N9LTLP:
        CALL N6NEXT
        JP C,N9LERR
        CP 2
        JP Z,N9LTEND
        CP 1
        JP NZ,N9LERR
        CALL N6NEXT
        JP C,N9LERR
        CP 5
        JP NZ,N9LERR
        LD DE,(N6TMPP)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (N6TMPP),DE
        CALL N6NEXT
        JP C,N9LERR
        LD (N9KIND),A
        LD (N9DVAL),HL
        LD A,(N9KIND)
        LD HL,(N9DVAL)
        CALL N6EV
        JP C,N9LERR
        LD (N9ATAG),A
        LD (N9AVAL),HL
        CALL N6NEXT
        JP C,N9LERR
        CP 2
        JP NZ,N9LERR
        LD A,(N9LTCNT)
        CP 8
        JP NC,N9LERR
        LD E,A
        LD D,0
        LD HL,N6ARGTAG
        ADD HL,DE
        LD A,(N9ATAG)
        LD (HL),A
        LD A,(N9LTCNT)
        ADD A,A
        LD E,A
        LD D,0
        LD HL,N6ARGVAL
        ADD HL,DE
        LD DE,(N9AVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(N9LTCNT)
        INC A
        LD (N9LTCNT),A
        JP N9LTLP
N9LTEND:
        LD HL,(N9LTDESC)
        LD DE,(N6PC)
        LD (HL),E
        INC HL
        LD (HL),D
        XOR A
        LD (N6SCNST),A
N9LTSCAN:
        CALL N6NEXT
        JP C,N9LERR
        CP 1
        JR Z,N9LTOPEN
        CP 2
        JR Z,N9LTCLS
        JP N9LTSCAN
N9LTOPEN:
        LD A,(N6SCNST)
        INC A
        LD (N6SCNST),A
        JP N9LTSCAN
N9LTCLS:
        LD A,(N6SCNST)
        OR A
        JR Z,N9LTDONE
        DEC A
        LD (N6SCNST),A
        JP N9LTSCAN
N9LTDONE:
        LD HL,(N6PC)
        LD DE,4
        OR A
        SBC HL,DE
        LD (N6CHKEND),HL
        LD HL,(N9LTDESC)
        INC HL
        INC HL
        LD DE,(N6CHKEND)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(N9LTDESC)
        LD DE,4
        ADD HL,DE
        LD DE,(N9LTPARM)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(N9LTDESC)
        LD DE,6
        ADD HL,DE
        LD A,(N9LTCNT)
        LD (HL),A
        LD A,(N9LTCTX)
        OR A
        JR Z,N9LTMAKE
        ; A tail LET keeps its descriptor slot across iterations.  Rebuild the
        ; existing private environment in place instead of allocating another
        ; block on every trip around the loop.
        LD HL,(N9LTDESC)
        LD DE,8
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,N9LTMAKE
        EX DE,HL
        CALL N6ENVREF
        JP C,N9LERR
        JR N9LTENV
N9LTMAKE:
        CALL N6MAKEV
        JP C,N9LERR
N9LTENV:
        LD (N6TMPENV),HL
        LD HL,(N9LTDESC)
        LD DE,8
        ADD HL,DE
        LD DE,(N6TMPENV)
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(N6CCOUNT)
        INC A
        LD (N6CCOUNT),A
        LD HL,(N6CLOSP)
        LD DE,10
        ADD HL,DE
        LD (N6CLOSP),HL
        LD HL,(N6PARMP)
        LD DE,16
        ADD HL,DE
        LD (N6PARMP),HL
        LD A,(N9LTCNT)
        LD (N6ARGC),A
        LD HL,(N9LTDESC)
        LD (N6CVAL),HL
        LD A,(N9LTCTX)
        OR A
        JR Z,N9LINV
        CALL N9LTREW
        LD HL,(N9LTDESC)
        CALL N6TINV
        JP C,N9LIERR
        POP AF
        LD (N6TCTX),A
        XOR A
        RET
N9LINV:
        CALL N6INVOKE
        JP C,N9LIERR
        LD (N9LTAG),A
        LD (N9LVAL),HL
        POP BC
        LD A,B
        LD (N6TCTX),A
        LD A,(N9LTAG)
        LD HL,(N9LVAL)
        OR A
        RET
N9LIERR:
        POP AF
        SCF
        RET
N9LERR:
        POP AF
        SCF
        RET

; A tail LET reuses its descriptor slot on the next iteration.  The active
; invocation has already copied the descriptor and environment pointers.
N9LTREW:
        LD HL,(N9LTDESC)
        LD (N6CLOSP),HL
        LD HL,(N9LTPARM)
        LD (N6PARMP),HL
        LD A,(N9LTOLD)
        LD (N6CCOUNT),A
        RET

; COND evaluates tests in order and skips the rest of a clause or form when
; the selected branch is known.  Clause bodies may contain several forms.
N9COND:
        LD A,(N6TCTX)
        LD (N9CTCTX),A
        PUSH AF
        XOR A
        LD (N6TCTX),A
N9CLP:
        CALL N6NEXT
        JP C,N9CERR
        CP 2
        JP Z,N9CNONE
        CP 1
        JP NZ,N9CERR
        CALL N6NEXT
        JP C,N9CERR
        CP 5
        JP NZ,N9CTEST
        LD A,(N6TAG)
        CP 39
        JP Z,N9CELSE
N9CTEST:
        LD (N9KIND),A
        LD (N9DVAL),HL
        LD A,(N9KIND)
        LD HL,(N9DVAL)
        CALL N6EV
        JP C,N9CERR
        LD (N9ATAG),A
        LD (N9AVAL),HL
        LD A,(N9ATAG)
        OR A
        JR NZ,N9CTRUE
        LD HL,(N9AVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JR NZ,N9CTRUE
        CALL N9SKCL
        JP C,N9CERR
        JP N9CLP
N9CTRUE:
        CALL N9CBODY
        JP C,N9CERR
        LD A,(N6TF)
        OR A
        JR NZ,N9CTAIL
        CALL N6NEXT
        JP C,N9CERR
        CP 2
        JP NZ,N9CERR
        CALL N9SKREST
        JP C,N9CERR
        JP N9CRET
N9CELSE:
        CALL N9CBODY
        JP C,N9CERR
        LD A,(N6TF)
        OR A
        JR NZ,N9CTAIL
        CALL N6NEXT
        JP C,N9CERR
        CP 2
        JP NZ,N9CERR
        CALL N9SKREST
        JP C,N9CERR
        JP N9CRET
N9CNONE:
        LD A,0
        LD HL,0FE04H
        LD (N9ATAG),A
        LD (N9AVAL),HL
N9CRET:
        POP BC
        LD A,B
        LD (N6TCTX),A
        LD A,(N9ATAG)
        LD HL,(N9AVAL)
        OR A
        RET
N9CERR:
        POP AF
        SCF
        RET
N9CTAIL:
        POP AF
        XOR A
        RET

; Skip the body of one false clause through its closing parenthesis.
N9SKCL:
        CALL N6NEXT
        RET C
        CP 2
        RET Z
        CALL N6SKIP
        JR N9SKCL

; Evaluate one or more forms through the current clause close.
N9CBODY:
        CALL N6NEXT
        RET C
        CP 2
        JP Z,N6BAD
        LD (N9KIND),A
        LD (N9DVAL),HL
        JR N9CBLP
N9CBLP:
        CALL N9LAST
        RET C
        OR A
        JR Z,N9CBNOT
        LD A,(N9CTCTX)
        JR N9CBSET
N9CBNOT:
        XOR A
N9CBSET:
        LD (N6TCTX),A
        LD A,(N9KIND)
        LD HL,(N9DVAL)
        CALL N6EV
        RET C
        LD (N9ATAG),A
        LD (N9AVAL),HL
        LD A,(N6TF)
        OR A
        RET NZ
        LD HL,N6SPOOLB
        LD DE,(N6PC)
        ADD HL,DE
        LD A,(HL)
        CP 2
        JR Z,N9CBDONE
        CALL N6NEXT
        RET C
        LD (N9KIND),A
        LD (N9DVAL),HL
        JR N9CBLP
N9CBDONE:
        LD A,(N9ATAG)
        LD HL,(N9AVAL)
        OR A
        RET

; Primitive ID table indexed by native operator code.  FF marks syntax-only
; forms or names that cannot be used as first-class primitive values.
N9PIDS:
        DB 0FFH,0,1,2,3,0FFH,0FFH,0FFH,0FFH,0FFH
        DB 0FFH,9,10,11,15,12,13,24,23,19
        DB 21,22,25,0FFH,4,5,6,7,8,17
        DB 18,20,26,27,0FFH,0FFH,0FFH,0FFH,16
        DB 0FFH,14

;-------------------------------------------------------------------------
;  N9 private state and bounded global table
;-------------------------------------------------------------------------

N9GCOUNT:  DB 0
N9FOUND:   DB 0
N9GMODE:   DB 0
N9CODE:    DB 0
N9PID:     DB 0
N9TOPS: DB 0
N9SCANP:   DW 0
N9SCANL:   DW 0
N9GID:     DW 0
N9DID:     DW 0
N9GTAG:    DB 0
N9ENV:     DW 0
N9KIND:    DB 0
N9DVAL:    DW 0
N9LTDESC:  DW 0
N9LTPARM:  DW 0
N9LTCNT: DB 0
N9LTCTX: DB 0
N9LTOLD: DB 0
N9LTAG:    DB 0
N9RTAG:    DB 0
N9LVAL:    DW 0
N9RVAL:    DW 0
N9CCODE:   DW 0
N9AFLAG:   DB 0
N9AOP:     DB 0
N9ATCTX:   DB 0
N9CTCTX:   DB 0
N9CBPC:    DW 0
N9CBTAG:   DB 0
N9ATAG:    DB 0
N9AVAL:    DW 0
N9GBASE:   DS 384
