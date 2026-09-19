;=============================================================================
;  N5 native control-flow evaluator
;=============================================================================
;
;  This front end reuses native-emitter.asm.  It evaluates the bounded event
;  stream directly: no AST and no branch table are retained.  A separate skip
;  walker consumes an unselected IF arm, so an overflowing expression there is
;  never passed to the numeric runtime.
;
;  Supported forms add nested + - * /, if, begin, zero?, not, number? and
;  boolean?.  Values are the reader's exact signed16/binary16 pair.  The
;  result is handed to the same committed NOBJ/COM template as N4.
;=============================================================================

N5MAIN:
        LD HL,(6)                 ; Reserve the upper 32K for the native stack.
        LD DE,8000H
        OR A
        SBC HL,DE
        JP C,N4MEMERR
        LD SP,8000H
        CALL N5PARSE
        JP C,N4FAIL
        CALL N4EMIT
        JP C,N4FAIL
        LD DE,N4OKTXT
        JP N4PRINT

;-------------------------------------------------------------------------
;  Source setup and one top-level expression
;-------------------------------------------------------------------------

N5PARSE:
        LD HL,005CH
        CALL CSOPEN
        JP C,N5IO
        LD A,1
        LD (N4OPEN),A
        LD IX,N4SYMCXT
        CALL IINIT
        JP C,N5READ
        LD IX,N4STRCXT
        CALL IINIT
        JP C,N5READ
        LD HL,CSBYTE
        LD DE,N4SYMCXT
        LD BC,N4STRCXT
        CALL RINIT
        JP C,N5READ
        CALL N5EXPR
        JP C,N5READ
        LD (N4RTAG),A
        LD (N4RVAL),HL
        CALL RNEXT
        JP C,N5READ
        OR A
        JP NZ,N5SYNT
        CALL CSCLOSE
        JP C,N5IO
        XOR A
        LD (N4OPEN),A
        RET

N5IO:
        LD A,2
        LD (N4CODE),A
        SCF
        RET
N5READ:
N5SYNT:
        LD A,1
        LD (N4CODE),A
        SCF
        RET

;-------------------------------------------------------------------------
;  Event evaluator
;-------------------------------------------------------------------------

; Read one event and dispatch it as the start of a datum.
N5EXPR:
        CALL RNEXT
        RET C
        JP N5EXEV

; A = already-read event kind; value events retain RTAG:HL.
N5EXEV:
        CP 7
        JR Z,N5VALUE
        CP 1
        JR Z,N5LIST
        SCF
        RET
N5VALUE:
        LD A,(RTAG)
        OR A
        RET

; A list must begin with a symbol naming one of the bounded forms.
N5LIST:
        CALL RNEXT
        RET C
        CP 5
        JP NZ,N5BAD
        LD A,(LBUFLEN)
        CP 1
        JR Z,N5ONE
        CP 2
        JR Z,N5IFNAME
        CP 3
        JR Z,N5NOTNM
        CP 5
        JR Z,N5LONG
        CP 7
        JP Z,N5NUMNM
        CP 8
        JP Z,N5BNM
        JP N5BAD

; One-character arithmetic operators and zero-argument defaults.
N5ONE:
        LD A,(LBUFFER)
        CP '+'
        JP Z,N5ARITH
        CP '-'
        JP Z,N5ARITH
        CP '*'
        JP Z,N5ARITH
        CP '/'
        JP NZ,N5BAD
        JP N5ARITH

N5IFNAME:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'i'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'f'
        JP NZ,N5BAD
        JP N5IF

N5NOTNM:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'n'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 't'
        JP NZ,N5BAD
        JP N5NOT

; Five-byte names are begin and zero?.
N5LONG:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'b'
        JP Z,N5BEGIN
        CP 'z'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP '?'
        JP NZ,N5BAD
        JP N5ZERO

N5NUMNM:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'n'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'u'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'm'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'b'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'r'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP '?'
        JP NZ,N5BAD
        JP N5NUMP

N5BNM:
        LD HL,LBUFFER
        LD A,(HL)
        CP 'b'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'o'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'l'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'e'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'a'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP 'n'
        JP NZ,N5BAD
        INC HL
        LD A,(HL)
        CP '?'
        JP NZ,N5BAD
        JP N5BOOL

N5BAD:
        SCF
        RET

;-------------------------------------------------------------------------
;  Nested arithmetic
;-------------------------------------------------------------------------

N5ARITH:
        LD (N5OP),A
        CALL RNEXT
        RET C
        CP 2
        JP Z,N5ARZERO
        CALL N5EXEV
        RET C
        LD (N5ATAG),A
        LD (N5AVAL),HL
        LD A,1
        LD (N5CTAG),A               ; One operand selects unary - only.
N5ARLOOP:
        CALL RNEXT
        RET C
        CP 2
        JR Z,N5ARFIN
        ; Keep the accumulator on the machine stack while a nested right
        ; expression runs.  The evaluator's fixed slots are deliberately
        ; small; this pair makes nested arithmetic compositional without an
        ; AST or a second set of static work words.
        LD C,A                      ; Preserve the already-read event kind.
        LD A,(N5CTAG)
        PUSH AF                     ; Nested forms may overwrite the count.
        LD (N5RVAL),HL              ; RNEXT's payload must survive the save.
        LD HL,(N5AVAL)
        PUSH HL
        LD A,(N5ATAG)
        PUSH AF
        LD A,(N5OP)
        PUSH AF                     ; Nested forms may use their own operator.
        LD A,C
        LD HL,(N5RVAL)
        CALL N5EXEV
        JP C,N5ARF2
        LD (N5RTAG),A
        LD (N5RVAL),HL
        POP AF
        LD (N5OP),A
        POP AF
        LD (N5ATAG),A
        POP HL
        LD (N5AVAL),HL
        POP AF
        LD (N5CTAG),A
        LD A,2
        LD (N5CTAG),A
        CALL N5NCALL
        RET C
        LD (N5ATAG),A
        LD (N5AVAL),HL
        JR N5ARLOOP
N5ARFIN:
        LD A,(N5OP)
        CP '-'
        JR Z,N5NEGCHK
        CP '/'
        JP Z,N5BAD
        LD A,(N5ATAG)
        LD HL,(N5AVAL)
        OR A
        RET
N5NEGCHK:
        LD A,(N5CTAG)
        CP 1
        JP NZ,N5ARRET
N5NEG1:
        LD A,(N5ATAG)
        LD HL,(N5AVAL)
        CALL NNEG
        RET
N5ARRET:
        LD A,(N5ATAG)
        LD HL,(N5AVAL)
        OR A
        RET

N5ARZERO:
        LD A,(N5OP)
        CP '+'
        JR Z,N5ZRES
        CP '*'
        JR Z,N5ONERES
        SCF
        RET
N5ZRES:
        LD A,3
        LD HL,0
        RET
N5ONERES:
        LD A,3
        LD HL,1
        RET

; A/HL holds the left accumulator, N5RTAG:N5RVAL the right result.
N5NCALL:
        LD HL,(N5AVAL)
        LD DE,(N5RVAL)
        LD A,(N5RTAG)
        LD B,A
        LD A,(N5OP)
        LD C,A
        CP '+'
        JR Z,N5ADD
        CP '-'
        JR Z,N5SUB
        CP '*'
        JR Z,N5MUL
        LD A,(N5ATAG)
        CALL NDIV
        RET
N5ADD:
        LD A,(N5ATAG)
        CALL NADD
        RET
N5SUB:
        LD A,(N5ATAG)
        CALL NSUB
        RET
N5MUL:
        LD A,(N5ATAG)
        CALL NMUL
        RET
N5ARF2:
        POP AF
        POP AF
        POP HL
        POP AF
        SCF
        RET

;-------------------------------------------------------------------------
;  IF and bounded skip walker
;-------------------------------------------------------------------------

N5IF:
        CALL N5EXPR
        RET C
        LD (N5TTAG),A
        LD (N5TVAL),HL
        CALL RNEXT
        RET C
        LD (N5CTAG),A               ; Keep the branch event while testing.
        LD (N5RVAL),HL              ; Preserve a value branch while testing.
        LD A,(N5TTAG)
        OR A
        JR NZ,N5IFTRUE
        LD HL,(N5TVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JR Z,N5IFNO
N5IFTRUE:
        ; A nested branch may itself evaluate an IF.  Preserve the outer
        ; predicate across that call so the alternate arm decision remains
        ; tied to the original test.
        LD HL,(N5TVAL)
        PUSH HL
        LD A,(N5CTAG)
        LD C,A
        LD A,(N5TTAG)
        PUSH AF
        LD A,C
        LD HL,(N5RVAL)
        CALL N5EXEV
        JP C,N5IFERRP
        LD (N5ATAG),A
        LD (N5AVAL),HL
        POP AF
        LD (N5TTAG),A
        POP HL
        LD (N5TVAL),HL
        JR N5IFNEXT
N5IFNO:
        LD A,(N5CTAG)
        CALL N5SKIPK
        JR C,N5IFERR
N5IFNEXT:
        CALL RNEXT
        RET C
        LD (N5CTAG),A               ; Preserve the alternative event kind.
        LD (N5RVAL),HL
        CP 2
        JR Z,N5IFNONE
        LD A,(N5TTAG)
        OR A
        JR NZ,N5SKALT
        LD HL,(N5TVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JR NZ,N5SKALT
N5IFALT:
        LD HL,(N5TVAL)
        PUSH HL
        LD A,(N5CTAG)
        LD C,A
        LD A,(N5TTAG)
        PUSH AF
        LD A,C
        LD HL,(N5RVAL)
        CALL N5EXEV
        JR C,N5IFERRP
        LD (N5ATAG),A
        LD (N5AVAL),HL
        POP AF
        LD (N5TTAG),A
        POP HL
        LD (N5TVAL),HL
        JR N5ALTOK
N5SKALT:
        LD A,(N5CTAG)
        CALL N5SKIPK
N5ALTOK:
        RET C
        CALL RNEXT
        RET C
        CP 2
        JP NZ,N5IFERR
        RET C
        LD A,(N5ATAG)
        LD HL,(N5AVAL)
        OR A
        RET
N5IFUNSP:
        LD A,0
        LD HL,0FE04H
        OR A
        RET
N5IFNONE:
        ; With no alternative, a true test keeps its selected consequent;
        ; only #f takes the unspecified value.
        LD A,(N5TTAG)
        OR A
        JR NZ,N5IFRET
        LD HL,(N5TVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JR NZ,N5IFRET
        JR N5IFUNSP
N5IFRET:
        LD A,(N5ATAG)
        LD HL,(N5AVAL)
        OR A
        RET
N5IFERR:
        SCF
        RET
N5IFERRP:
        POP AF
        POP HL
        JR N5IFERR

; Skip one already-read datum without invoking numeric semantics.
N5SKIPK:
        CP 1
        JR Z,N5SKLIST
        CP 3
        JR Z,N5SQUOTE
        CP 2
        JP Z,N5BAD
        CP 4
        JP Z,N5BAD
        OR A
        RET
N5SQUOTE:
        CALL RNEXT
        RET C
        JR N5SKIPK
N5SKLIST:
        CALL RNEXT
        RET C
        CP 2
        JR Z,N5SKDONE
        CP 4
        JR Z,N5SDOT
        CALL N5SKIPK
        RET C
        JR N5SKLIST
N5SDOT:
        CALL RNEXT
        RET C
        CALL N5SKIPK
        RET C
        CALL RNEXT
        RET C
        CP 2
        JP NZ,N5BAD
        XOR A
        RET
N5SKDONE:
        OR A
        RET

;-------------------------------------------------------------------------
;  BEGIN and predicates
;-------------------------------------------------------------------------

N5BEGIN:
        CALL RNEXT
        RET C
        CP 2
        JR Z,N5UNSP
N5BELOOP:
        CALL N5EXEV
        RET C
        LD (N5ATAG),A
        LD (N5AVAL),HL
        CALL RNEXT
        RET C
        CP 2
        JR NZ,N5BELOOP
        LD A,(N5ATAG)
        LD HL,(N5AVAL)
        OR A
        RET

N5CLOSE:
        CP 2
        JR Z,N5CLOK
        SCF
        RET
N5CLOK:
        OR A
        RET
N5UNSP:
        LD A,0
        LD HL,0FE04H
        OR A
        RET

N5ZERO:
        CALL N5EXPR
        RET C
        LD (N5ATAG),A
        LD (N5AVAL),HL
        CALL RNEXT
        RET C
        CP 2
        JP NZ,N5BAD
        LD HL,(N5AVAL)
        LD A,H
        OR L
        JR NZ,N5BOOLF
        LD A,(N5ATAG)
        CP 3
        JR Z,N5BOOLT
        OR A
        JR Z,N5BOOLT
        JR N5BOOLF

N5NOT:
        CALL N5EXPR
        RET C
        LD (N5ATAG),A
        LD (N5AVAL),HL
        CALL RNEXT
        RET C
        CP 2
        JP NZ,N5BAD
        LD A,(N5ATAG)
        OR A
        JR NZ,N5BOOLF
        LD HL,(N5AVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JR Z,N5BOOLT
N5BOOLF:
        LD A,0
        LD HL,0FE00H
        OR A
        RET
N5BOOLT:
        LD A,0
        LD HL,0FE01H
        OR A
        RET

N5NUMP:
        CALL N5EXPR
        RET C
        LD (N5ATAG),A
        LD (N5AVAL),HL
        CALL RNEXT
        RET C
        CP 2
        JP NZ,N5BAD
        LD HL,(N5AVAL)
        LD A,(N5ATAG)
        CALL NCLASS
        JR C,N5BOOLF
        JR N5BOOLT

N5BOOL:
        CALL N5EXPR
        RET C
        LD (N5ATAG),A
        LD (N5AVAL),HL
        CALL RNEXT
        RET C
        CP 2
        JP NZ,N5BAD
        LD A,(N5ATAG)
        OR A
        JR NZ,N5BOOLF
        LD HL,(N5AVAL)
        LD A,H
        CP 0FEH
        JR NZ,N5BOOLF
        LD A,L
        CP 0
        JR Z,N5BOOLT
        CP 1
        JR Z,N5BOOLT
        JR N5BOOLF

; Per-evaluation state.  These words are separate from the N4 emitter's
; result slots so a nested result cannot overwrite the arithmetic accumulator.
N5OP:    DB 0
N5ATAG:  DB 0
N5RTAG:  DB 0
N5TTAG:  DB 0
N5CTAG:  DB 0
N5AVAL:  DW 0
N5RVAL:  DW 0
N5TVAL:  DW 0
