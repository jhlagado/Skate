;=============================================================================
;  N6 native fixed-arity procedure evaluator
;=============================================================================
;
;  N6 keeps the reader and NOBJ emitter contracts from N4/N5 but adds one
;  bounded intermediate: a four-byte event spool.  Lambda descriptors retain
;  event ranges and parameter identities; calls copy arguments into a fixed
;  activation frame and evaluate the body from that range.  No AST or heap is
;  required. N7 adds a bounded whole-environment snapshot for escaped closures.
;
;  EVENT RECORD: kind, operator-code/tag, payload low, payload high.
;  OPERATOR CODES: + 1, - 2, * 3, / 4, if 5, begin 6, lambda 7, zero? 8,
;                  set! 9.
;  VALUE TAG 2 is the private procedure value used only during compilation.
;
;=============================================================================
;  N8a quoted-data semantic slice
;=============================================================================
;
;  N8a keeps quoted values in a bounded compiler arena so the evaluator can
;  serve as a semantic oracle while the target literal recipe path is built.
;  Pair records are eight bytes: CAR tag, CAR payload, CDR tag, CDR payload.
;  Pair identities are one-based and use logical value tag one.  N8b will
;  replace this arena with initialized NOBJ recipes and runtime pair services.
;=============================================================================

N6MAIN:
        LD HL,(6)                 ; CP/M reports the top of transient memory.
        LD DE,N8PEND
        OR A
        SBC HL,DE                 ; N8's transient pair overlay ends at $C000.
        JP C,N4MEMERR
        LD SP,0A000H
        CALL N6PARSE
        JP C,N4FAIL
        CALL N8EMIT
        JP C,N4FAIL
        LD DE,N4OKTXT
        JP N4PRINT

;-------------------------------------------------------------------------
;  Source setup, event spool and cursor
;-------------------------------------------------------------------------

N6PARSE:
        LD HL,005CH
        CALL CSOPEN
        JR C,N6IO
        LD A,1
        LD (N4OPEN),A
        LD IX,N4SYMCXT
        CALL IINIT
        JR C,N6READ
        LD IX,N4STRCXT
        CALL IINIT
        JR C,N6READ
        LD HL,CSBYTE
        LD DE,N4SYMCXT
        LD BC,N4STRCXT
        CALL RINIT
        JR C,N6READ
        ; The macro phase owns the high transient overlay.  Derive its size
        ; from CP/M's TPA ceiling so a short profile rejects the package
        ; during NMINIT instead of writing beyond available memory.
        LD HL,(6)
        LD DE,N8PEND
        OR A
        SBC HL,DE
        LD B,H
        LD C,L
        LD HL,N8PEND
        CALL NMINIT
        JR C,N6READ
        CALL NMPARSE
        JR C,N6READ
        CALL NMREW
        JR C,N6READ
        CALL NMEXPALL
        JR C,N6READ
        CALL NMOUTRW
        JR C,N6READ
        CALL N6PLANM
        JR C,N6READ
        CALL NMOUTRW
        CALL N6RESET
        CALL N6SPOOLM
        JR C,N6READ
        CALL N9RESV
        JR C,N6READ
        CALL N9TOP
        JR C,N6READ
        CALL CSCLOSE
        JR C,N6IO
        XOR A
        LD (N4OPEN),A
        RET
N6IO:
        LD A,2
        LD (N4CODE),A
        SCF
        RET
N6READ:
        LD A,1
        LD (N4CODE),A
        SCF
        RET
N6SYNT:
        JR N6READ
N6BAD:
        SCF
        RET
N6CAP:
        SCF
        RET

N6RESET:
        XOR A
        LD (N6PC),A
        LD (N6PC+1),A
        LD (N6KIND),A
        LD (N6TAG),A
        LD (N6HEADK),A
        LD (N6HEADID),A
        LD (N6HEADID+1),A
        LD (N6CCOUNT),A
        LD (N6DEPTH),A
        LD (N6FCNT),A
        LD (N6HASRES),A
        LD (N6TCTX),A
        LD (N6TF),A
        LD HL,0
        LD (N6CENV),HL
        LD (N6FP),HL
        LD (N6CURC),HL
        LD HL,N6CLOS
        LD (N6CLOSP),HL
        LD HL,N6PARAM
        LD (N6PARMP),HL
        LD HL,N6FRAMES
        LD (N6FRCUR),HL
        LD HL,N7ENVFOR
        LD DE,N7ENVFOR+1
        LD BC,31
        LD (HL),0
        LDIR
        LD HL,N7ENVS
        LD (N7ENVSP),HL
        LD HL,0
        LD (N8PCOUNT),HL
        LD (N8QID),HL
        LD (N8OUTPTR),HL
        LD (N8OUTLEN),HL
        XOR A
        LD (N6ASDEP),A
        RET

; Read all bounded events once.  The event payload is already interned by the
; reader, so later procedure calls can revisit a body without reopening CP/M.
N6SPOOL:
        LD HL,N6SPOOLB
        LD (N6SPPTR),HL
N6SPLP:
        LD HL,(N6SPPTR)
        LD DE,N6SPOOLB
        OR A
        SBC HL,DE
        LD DE,4092
        OR A
        SBC HL,DE
        JP NC,N6CAP
        LD HL,(N6SPPTR)
        CALL RNEXT
        RET C
        LD (N6SPK),A
        EX DE,HL                   ; Hold RNEXT's payload while writing a record.
        LD HL,(N6SPPTR)
        LD (HL),A
        INC HL
        LD A,(N6SPK)
        CP 5
        JR Z,N6SPSYM
        CP 7
        JR Z,N6SPVAL
        CP 8
        JR Z,N6SPVAL
        XOR A
        JR N6SPTAG
N6SPSYM:
        PUSH DE
        PUSH HL
        CALL N6SCODE
        POP HL
        POP DE
        JR N6SPTAG
N6SPVAL:
        LD A,(RTAG)
N6SPTAG:
        LD (HL),A
        INC HL
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        INC HL
        LD (N6SPPTR),HL
        LD A,(N6SPK)
        OR A
        JR Z,N6SPDONE
        JR N6SPLP
N6SPDONE:
        LD HL,(N6SPPTR)
        LD DE,N6SPOOLB
        OR A
        SBC HL,DE
        LD (N6SPLEN),HL
        XOR A
        RET

; A = event kind; N6TAG = code/tag; HL = payload.
N6NEXT:
        LD HL,(N6PC)
        LD DE,(N6SPLEN)
        OR A
        SBC HL,DE
        JP NC,N6BAD
        LD HL,N6SPOOLB
        LD DE,(N6PC)
        ADD HL,DE
        LD A,(HL)
        LD (N6KIND),A
        INC HL
        LD A,(HL)
        LD (N6TAG),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD DE,(N6PC)
        INC DE
        INC DE
        INC DE
        INC DE
        LD (N6PC),DE
        LD A,(N6KIND)
        RET

;-------------------------------------------------------------------------
;  Expression dispatch and applications
;-------------------------------------------------------------------------

N6EXPR:
        CALL N6NEXT
        RET C
        JR N6EV
N6EV:
        CP 7
        JR Z,N6VALUE
        CP 1
        JR Z,N6LIST
        CP 3
        JP Z,N8QUOTE
        CP 8
        JR Z,N6VALUE
        CP 5
        JR Z,N6SYM
        SCF
        RET
N6VALUE:
        LD A,(N6TAG)
        OR A
        RET
N6SYM:
        JP N9SYM

N6LIST:
        CALL N6NEXT
        RET C
        LD (N6HEADK),A
        LD (N6HEADID),HL
        CP 5
        JP NZ,N6APHEAD
        LD A,(N6TAG)
        CALL N9OVR
        JP NC,N6APHEAD
        LD A,(N6TAG)
        CP 7
        JP Z,N6LAMB
        CP 5
        JP Z,N6IF
        CP 6
        JP Z,N6BEGIN
        CP 8
        JP Z,N6PRED
        CP 9
        JP Z,N6SET
        CP 10
        JP Z,N8QFORM
        CP 11
        JP Z,N8CONS
        CP 12
        JP Z,N8CAR
        CP 13
        JP Z,N8CDR
        CP 14
        JP Z,N8EQ
        CP 15
        JP Z,N8NULL
        CP 16
        JP Z,N8PAIRP
        CP 17
        JP Z,N8WRITE
        CP 18
        JP Z,N8DISP
        CP 19
        JP Z,N8SYMP
        CP 20
        JP Z,N8STRP
        CP 21
        JP Z,N8CHARP
        CP 22
        JP Z,N8NEWLN
        CP 23
        JP Z,N9DEF
        CP 24
        JP Z,N9CMPH
        CP 25
        JP Z,N9CMPH
        CP 26
        JP Z,N9CMPH
        CP 27
        JP Z,N9CMPH
        CP 28
        JP Z,N9CMPH
        CP 29
        JP Z,N9NUMP
        CP 30
        JP Z,N9BOOLP
        CP 31
        JP Z,N9PROCP
        CP 32
        JP Z,N9READ
        CP 33
        JP Z,N9EOFP
        CP 34
        JP Z,N9AND
        CP 35
        JP Z,N9OR
        CP 36
        JP Z,N9LET
        CP 37
        JP Z,N9COND
        CP 38
        JP Z,N9NOT
        CP 40
        JP Z,N8LIST
        CP 1
        JP C,N6APHEAD
        CP 5
        JP C,N6ARITH
N6APHEAD:
        LD A,(N6HEADK)
        LD (N6BEK),A
        LD HL,(N6HEADID)
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        LD A,(N6BEK)
        CALL N6EV
        JR C,N6APERR
        LD (N6RTAG),A
        LD (N6RVAL),HL
        POP AF
        LD (N6TCTX),A
        LD A,(N6RTAG)
        LD HL,(N6RVAL)
        JR N6APPLY
N6APERR:
        POP AF
        SCF
        RET

; Evaluate a general application after its operator expression has returned.
N6APPLY:
        OR A
        JP Z,N9PRIMA
        CP 2
        JP NZ,N6BAD
        LD (N6CTAG),A
        LD (N6CVAL),HL
        LD A,(N6TCTX)
        LD (N6CALLT),A
        XOR A
        LD (N6TCTX),A
        LD HL,N6ARGTAG
        LD (N6ARGTP),HL
        LD HL,N6ARGVAL
        LD (N6ARGVP),HL
        XOR A
        LD (N6ARGC),A
N6APLOOP:
        CALL N6NEXT
        RET C
        CP 2
        JR Z,N6APDONE
        LD (N6BEK),A
        LD (N6RVAL),HL
        CALL N6APSAVE
        JP C,N6BAD
        LD A,(N6BEK)
        LD HL,(N6RVAL)
        CALL N6EV
        JR C,N6APFAIL
        LD (N6RTAG),A
        LD (N6RVAL),HL
        CALL N6APREST
        JP C,N6BAD
        XOR A
        LD (N6TCTX),A
        LD A,(N6RTAG)
        LD HL,(N6RVAL)
        LD A,(N6ARGC)
        CP 8
        JP NC,N6BAD
        LD DE,(N6ARGTP)
        LD A,(N6RTAG)
        LD (DE),A
        INC DE
        LD (N6ARGTP),DE
        LD DE,(N6ARGVP)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (N6ARGVP),DE
        LD A,(N6ARGC)
        INC A
        LD (N6ARGC),A
        JR N6APLOOP
N6APFAIL:
        CALL N6APREST
        JP N6BAD
N6APDONE:
        LD A,(N6CTAG)
        LD HL,(N6CVAL)
        LD A,(N6CALLT)
        OR A
        JR NZ,N6TINV
        LD A,(N6CTAG)
        LD HL,(N6CVAL)
        JP N6INVOKE

; Re-enter a procedure in the current activation.  The caller's continuation
; remains on the machine stack; N6TF tells each enclosing evaluator helper
; to return directly to N6BODY, which then starts the replacement body.
N6TINV:
        LD (N6CVAL),HL
        LD A,(N6ARGC)
        LD B,A
        LD HL,(N6CVAL)
        LD DE,6
        ADD HL,DE
        LD A,(HL)
        CP B
        JP NZ,N6BAD
        LD HL,(N6FP)
        LD A,H
        OR L
        JP Z,N6BAD
        CALL N7CLRMAP
        CALL N6FRAME
        RET C
        LD HL,(N6CVAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N6PC),HL
        LD HL,(N6CVAL)
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N6BEND),HL
        LD HL,(N6CVAL)
        LD (N6CURC),HL
        LD HL,(N6CVAL)
        LD DE,8
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N6CENV),HL
        LD A,1
        LD (N6TF),A
        XOR A
        RET

; Save one application context while a nested argument expression runs.
; Arguments use one eight-byte value slice and one sixteen-byte payload slice;
; nested applications borrow a deeper copy so an outer call keeps its earlier
; arguments intact.
N6APSAVE:
        LD A,(N6ASDEP)
        CP 16
        JP NC,N6CAP
        POP HL
        LD (N6ASRET),HL
        INC A
        LD (N6ASDEP),A
        DEC A
        LD E,A
        LD D,0
        LD HL,N6ASCNT
        ADD HL,DE
        LD A,(N6ARGC)
        LD (HL),A
        LD A,(N6CTAG)
        PUSH AF
        LD HL,(N6CVAL)
        PUSH HL
        LD A,(N6CALLT)
        PUSH AF
        LD A,(N6ARGC)
        PUSH AF
        OR A
        JR Z,N6ASDONE
        LD B,A
        LD HL,N6ARGTAG
        LD (N6ASTP),HL
        LD HL,N6ARGVAL
        LD (N6ASVP),HL
N6ASSAVE:
        LD HL,(N6ASTP)
        LD A,(HL)
        PUSH AF
        INC HL
        LD (N6ASTP),HL
        LD HL,(N6ASVP)
        LD E,(HL)
        INC HL
        LD D,(HL)
        PUSH DE
        INC HL
        LD (N6ASVP),HL
        DJNZ N6ASSAVE
N6ASDONE:
        LD HL,(N6ASRET)
        PUSH HL
        XOR A
        RET

; Restore the application context saved by N6APSAVE and recompute write
; cursors from its argument count. All saved words are consumed on success
; and on the evaluator's carry path.
N6APREST:
        LD A,(N6ASDEP)
        OR A
        JR Z,N6ASRERR
        POP HL
        LD (N6ASRET),HL
        DEC A
        LD E,A
        LD D,0
        LD HL,N6ASCNT
        ADD HL,DE
        LD B,(HL)
N6ASRLP:
        LD A,B
        OR A
        JR Z,N6ASHEAD
        POP DE
        EX DE,HL
        LD (N6ASRVL),HL
        POP AF
        DEC B
        LD C,B
        LD HL,N6ARGTAG
        LD E,C
        LD D,0
        ADD HL,DE
        LD (HL),A
        LD A,C
        ADD A,A
        LD E,A
        LD D,0
        LD HL,N6ARGVAL
        ADD HL,DE
        LD DE,(N6ASRVL)
        LD (HL),E
        INC HL
        LD (HL),D
        JR N6ASRLP
N6ASHEAD:
        POP AF
        LD (N6ARGC),A
        POP AF
        LD (N6CALLT),A
        POP HL
        LD (N6CVAL),HL
        POP AF
        LD (N6CTAG),A
        LD A,(N6ASDEP)
        DEC A
        LD (N6ASDEP),A
        LD A,(N6ARGC)
        LD C,A
        LD HL,N6ARGTAG
        LD E,C
        LD D,0
        ADD HL,DE
        LD (N6ARGTP),HL
        LD A,C
        ADD A,A
        LD E,A
        LD D,0
        LD HL,N6ARGVAL
        ADD HL,DE
        LD (N6ARGVP),HL
        LD HL,(N6ASRET)
        PUSH HL
        XOR A
        RET
N6ASRERR:
        SCF
        RET


;-------------------------------------------------------------------------
;  Lambda descriptors and activation frames
;-------------------------------------------------------------------------

; Descriptor: body-start, body-end, parameter-base, arity byte, environment.
N6LAMB:
        LD A,(N6CCOUNT)
        CP 16
        JP NC,N6CAP
        LD HL,(N6CLOSP)
        LD (N6TMPD),HL
        LD HL,(N6PARMP)
        LD (N6TMPP),HL
        LD (N6TMPB),HL
        XOR A
        LD (N6NARITY),A
        CALL N6NEXT
        RET C
        CP 1
        JP NZ,N6BAD
N6PARLP:
        CALL N6NEXT
        RET C
        CP 2
        JR Z,N6PDONE
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
        JR N6PARLP
N6PDONE:
        LD HL,(N6TMPD)
        LD DE,6
        ADD HL,DE
        LD A,(N6NARITY)
        LD (HL),A
        LD HL,(N6TMPD)
        LD DE,4
        ADD HL,DE
        LD DE,(N6TMPB)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        LD HL,(N6TMPD)
        LD DE,(N6PC)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        LD A,0
        LD (N6SCNST),A
N6SCAN:
        CALL N6NEXT
        RET C
        CP 1
        JR Z,N6SCOPEN
        CP 2
        JR Z,N6SCLOS
        JR N6SCAN
N6SCOPEN:
        LD A,(N6SCNST)
        INC A
        LD (N6SCNST),A
        JR N6SCAN
N6SCLOS:
        LD A,(N6SCNST)
        OR A
        JR Z,N6SCEND
        DEC A
        LD (N6SCNST),A
        JR N6SCAN
N6SCEND:
        LD HL,(N6PC)
        LD DE,4
        OR A
        SBC HL,DE
        LD (N6CHKEND),HL
        LD DE,(N6TMPD)
        INC DE
        INC DE
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        CALL N6MAKEV
        RET C
        LD (N6TMPENV),HL
        LD HL,(N6TMPD)
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
        LD HL,(N6TMPD)
        OR A
        RET

; Copy the current activation into one shared environment block. Every lambda
; created in this activation reuses its block, so sibling closures share set!.
; A block is [parent word, frame count, defining depth, defining frame,
; frame records], with each record retaining the five bytes used by the local
; activation lookup.
N6MAKEV:
        LD A,(N6DEPTH)
        OR A
        JP Z,N6NOENV
        DEC A
        ADD A,A
        LD E,A
        LD D,0
        LD HL,N7ENVFOR
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,N6ENVNEW
        EX DE,HL
        XOR A
        RET
N6ENVNEW:
        LD HL,(N7ENVSP)
        LD (N6TMPENV),HL
        LD DE,46
        ADD HL,DE
        JP C,N6CAP
        LD (N7ENVSP),HL

        ; Publish the block pointer in the map for this activation depth.
        LD HL,N7ENVFOR
        LD A,(N6DEPTH)
        DEC A
        ADD A,A
        LD E,A
        LD D,0
        ADD HL,DE
        LD DE,(N6TMPENV)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        JR N6EVWR

; Refresh an existing environment block in place.  Tail LET reuses its
; descriptor's private snapshot so repeated derived calls do not consume the
; bounded environment arena.
N6ENVREF:
        LD (N6TMPENV),HL

        ; Write the parent link, frame count, defining depth and frame pointer.
N6EVWR:
        LD HL,(N6TMPENV)
        LD DE,(N6CENV)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        INC HL
        LD A,(N6FCNT)
        LD (HL),A
        INC HL
        LD A,(N6DEPTH)
        LD (HL),A
        INC HL
        LD DE,(N6FP)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        INC HL
        LD (N6TMPE),HL
        LD HL,(N6FP)
        LD (N6TMPF),HL
        LD A,(N6FCNT)
        LD (N6TMPI),A
N6ENCOPY:
        LD A,(N6TMPI)
        OR A
        JR Z,N6ENVRET
        LD HL,(N6TMPF)
        LD DE,(N6TMPE)
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        LD (N6TMPF),HL
        LD (N6TMPE),DE
        LD A,(N6TMPI)
        DEC A
        LD (N6TMPI),A
        JR N6ENCOPY
N6NOENV:
        LD HL,0
        XOR A
        RET
N6ENVRET:
        LD HL,(N6TMPENV)
        XOR A
        RET

; Build one activation, run the selected body range, and restore the caller.
N6INVOKE:
        LD (N6CVAL),HL
        LD A,(N6ARGC)
        LD B,A
        LD HL,(N6CVAL)
        LD DE,6
        ADD HL,DE
        LD A,(HL)
        CP B
        JP NZ,N6BAD
        LD A,(N6DEPTH)
        CP 16
        JP NC,N6CAP
        LD HL,(N6FP)
        PUSH HL
        LD HL,(N6PC)
        PUSH HL
        LD HL,(N6CURC)
        PUSH HL
        LD HL,(N6BEND)
        PUSH HL
        LD HL,(N6CENV)
        PUSH HL
        LD A,(N6FCNT)
        PUSH AF
        LD A,(N6DEPTH)
        PUSH AF
        LD A,(N6TCTX)
        PUSH AF
        LD A,(N6DEPTH)
        INC A
        LD (N6DEPTH),A
        LD HL,(N6FRCUR)
        LD (N6FP),HL
        LD DE,40
        ADD HL,DE
        LD (N6FRCUR),HL
        CALL N7CLRMAP
        CALL N6FRAME
        JR C,N6UNWERR
        LD HL,(N6CVAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N6PC),HL
        LD HL,(N6CVAL)
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N6BEND),HL
        LD HL,(N6CVAL)
        LD (N6CURC),HL
        LD HL,(N6CVAL)
        LD DE,8
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (N6CENV),HL
        XOR A
        LD (N6TCTX),A
        LD (N6TF),A
        CALL N6BODY
        JR C,N6UNWERR
        LD (N6RESV),HL
        LD (N6REST),A
        LD A,(N6TF)
        OR A
        JR NZ,N6UNWERR
        CALL N7CLRMAP
        LD HL,(N6FRCUR)
        LD DE,40
        OR A
        SBC HL,DE
        LD (N6FRCUR),HL
        POP AF
        LD (N6TCTX),A
        POP AF
        LD (N6DEPTH),A
        POP AF
        LD (N6FCNT),A
        POP HL
        LD (N6CENV),HL
        POP HL
        LD (N6BEND),HL
        POP HL
        LD (N6CURC),HL
        POP HL
        LD (N6PC),HL
        POP HL
        LD (N6FP),HL
        LD A,(N6REST)
        LD HL,(N6RESV)
        OR A
        RET
N6UNWERR:
        CALL N7CLRMAP
        LD HL,(N6FRCUR)
        LD DE,40
        OR A
        SBC HL,DE
        LD (N6FRCUR),HL
        POP AF
        LD (N6TCTX),A
        POP AF
        LD (N6DEPTH),A
        POP AF
        LD (N6FCNT),A
        POP HL
        LD (N6CENV),HL
        POP HL
        LD (N6BEND),HL
        POP HL
        LD (N6CURC),HL
        POP HL
        LD (N6PC),HL
        POP HL
        LD (N6FP),HL
        SCF
        RET

; Copy parameter IDs and evaluated argument values into the current frame.
N6FRAME:
        LD HL,(N6CVAL)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (N6TMPP),DE
        LD HL,(N6FP)
        LD (N6TMPF),HL
        LD A,(N6ARGC)
        LD (N6FCNT),A
        XOR A
        LD (N6TMPI),A
N6FRLOOP:
        LD A,(N6TMPI)
        LD C,A
        LD A,(N6FCNT)
        CP C
        JR Z,N6FRDONE
        LD HL,(N6TMPP)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (N6TMPP),HL
        LD HL,(N6TMPF)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        INC HL
        LD A,(N6TMPI)
        LD HL,N6ARGTAG
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        LD HL,(N6TMPF)
        INC HL
        INC HL
        LD (HL),A
        LD HL,N6ARGVAL
        LD A,(N6TMPI)
        ADD A,A
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        LD DE,(N6TMPF)
        INC DE
        INC DE
        INC DE
        LD (DE),A
        INC HL
        INC DE
        LD A,(HL)
        LD (DE),A
        LD HL,(N6TMPF)
        LD DE,5
        ADD HL,DE
        LD (N6TMPF),HL
        LD A,(N6TMPI)
        INC A
        LD (N6TMPI),A
        JR N6FRLOOP
N6FRDONE:
        XOR A
        RET

; Evaluate sequential body expressions through the descriptor's end offset.
N6BODY:
        LD A,0
        LD (N6HASRES),A
N6BODYLP:
        LD HL,(N6PC)
        LD DE,(N6BEND)
        OR A
        SBC HL,DE
        JR Z,N6BODYOK
        LD HL,(N6PC)
        LD (N6CURPC),HL
        CALL N6NEXT
        RET C
        LD (N6BEK),A
        LD HL,(N6PC)
        LD (N6BEPTR),HL
        CALL N6SKIP
        RET C
        LD HL,(N6PC)
        LD DE,(N6BEND)
        OR A
        SBC HL,DE
        LD A,0
        JR NZ,N6BNOT
        INC A
N6BNOT:
        LD (N6TCTX),A
        LD HL,(N6CURPC)
        LD (N6PC),HL
        CALL N6EXPR
        RET C
        LD (N6RESV),HL
        LD (N6REST),A
        LD A,(N6TF)
        OR A
        JR NZ,N6BTAIL
        LD A,1
        LD (N6HASRES),A
        JR N6BODYLP
N6BTAIL:
        XOR A
        LD (N6TF),A
        JR N6BODY
N6BODYOK:
        LD A,(N6HASRES)
        OR A
        JP Z,N6BAD
        LD A,(N6REST)
        LD HL,(N6RESV)
        LD B,A
        XOR A
        LD (N6TCTX),A
        LD A,B
        OR A
        RET

; Look up a symbol in the current frame, then walk captured environments.
N6LOOK:
        LD (N6LOOKID),HL
        LD A,(N6FCNT)
        OR A
        JR Z,N7LOOK
        LD B,A
        LD HL,(N6FP)
N6LOOKLP:
        LD A,(HL)
        LD E,A
        INC HL
        LD A,(HL)
        LD D,A
        LD A,(N6LOOKID)
        CP E
        JR NZ,N6LNEXT
        LD A,(N6LOOKID+1)
        CP D
        JR NZ,N6LNEXT
        INC HL
        LD A,(HL)
        LD C,A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD A,C
        OR A
        RET
N6LNEXT:
        LD DE,4
        ADD HL,DE
        DJNZ N6LOOKLP
        JR N7LOOK

; Walk the linked environment snapshots captured by a closure. The current
; environment is searched before its parent, preserving lexical shadowing.
N7LOOK:
        LD HL,(N6CENV)
N7ENVLP:
        LD A,H
        OR L
        JP Z,N6BAD
        LD (N6TMPENV),HL
        INC HL
        INC HL
        LD A,(HL)
        OR A
        JR Z,N7ENVP
        LD B,A
        INC HL
        INC HL
        INC HL
        INC HL
N7ENVC:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,(N6LOOKID)
        CP E
        JR NZ,N7ENVN
        LD A,(N6LOOKID+1)
        CP D
        JR NZ,N7ENVN
        INC HL
        LD A,(HL)
        LD C,A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD A,C
        OR A
        RET
N7ENVN:
        LD DE,4
        ADD HL,DE
        DJNZ N7ENVC
N7ENVP:
        LD HL,(N6TMPENV)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JR N7ENVLP

; Return the environment block associated with the current activation depth.
N7CURMAP:
        LD A,(N6DEPTH)
        OR A
        JR Z,N7CMZERO
        DEC A
        ADD A,A
        LD E,A
        LD D,0
        LD HL,N7ENVFOR
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        RET
N7CMZERO:
        LD HL,0
        RET

; Clear the environment map slot for the current activation depth. A normal
; call creates a new slot; a tail call replaces the existing frame in place.
N7CLRMAP:
        CALL N7CURMAP
        LD A,H
        OR L
        RET Z
        ; N7CURMAP returned the old block, so recompute the slot address.
        LD A,(N6DEPTH)
        DEC A
        ADD A,A
        LD E,A
        LD D,0
        LD HL,N7ENVFOR
        ADD HL,DE
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        RET

; Update one environment chain. N6LOOKID, N6RTAG and N6RVAL hold the target
; binding and new value. Carry means that the binding was not present.
N7SETENV:
        LD A,H
        OR L
        JP Z,N7SMISS
        LD (N6TMPENV),HL
        INC HL
        INC HL
        LD A,(HL)
        OR A
        JP Z,N7SETP
        LD B,A
        INC HL
        INC HL
        INC HL
        INC HL
N7SETCL:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,(N6LOOKID)
        CP E
        JR NZ,N7SETN
        LD A,(N6LOOKID+1)
        CP D
        JR NZ,N7SETN
        INC HL
        LD A,(N6RTAG)
        LD (HL),A
        INC HL
        LD DE,(N6RVAL)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        CALL N7SYNCOR
        XOR A
        RET

; If the defining activation is still live, mirror a captured mutation into
; its frame. The map slot is an activity marker; once a call unwinds, the slot
; is cleared and an escaped closure updates only its persistent snapshot.
N7SYNCOR:
        LD HL,(N6TMPENV)
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        OR A
        RET Z
        DEC A
        ADD A,A
        LD E,A
        LD D,0
        LD HL,N7ENVFOR
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(N6TMPENV)
        OR A
        SBC HL,DE
        JR NZ,N7SYRET
        LD HL,(N6TMPENV)
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (N6TMPF),DE
        LD HL,(N6TMPENV)
        INC HL
        INC HL
        LD A,(HL)
        OR A
        RET Z
        LD B,A
        LD HL,(N6TMPF)
N7SYCL:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,(N6LOOKID)
        CP E
        JR NZ,N7SYN
        LD A,(N6LOOKID+1)
        CP D
        JR NZ,N7SYN
        INC HL
        LD A,(N6RTAG)
        LD (HL),A
        INC HL
        LD DE,(N6RVAL)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        RET
N7SYN:
        LD DE,4
        ADD HL,DE
        DJNZ N7SYCL
N7SYRET:
        RET
N7SETN:
        LD DE,4
        ADD HL,DE
        DEC B
        JP NZ,N7SETCL
N7SETP:
        LD HL,(N6TMPENV)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP N7SETENV
N7SMISS:
        SCF
        RET

; Find a binding in the current frame and update its mirrored environment.
; If it is not local, update the captured chain instead.
N7SETCUR:
        LD A,(N6FCNT)
        OR A
        JR Z,N7SETCAP
        LD B,A
        LD HL,(N6FP)
N7SETLP:
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,(N6LOOKID)
        CP E
        JR NZ,N7SNEXT
        LD A,(N6LOOKID+1)
        CP D
        JR NZ,N7SNEXT
        INC HL
        LD A,(N6RTAG)
        LD (HL),A
        INC HL
        LD DE,(N6RVAL)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        CALL N7CURMAP
        CALL N7SETENV
        XOR A
        RET
N7SNEXT:
        LD DE,4
        ADD HL,DE
        DJNZ N7SETLP
N7SETCAP:
        LD HL,(N6CENV)
        JP N7SETENV

; Scheme's set! returns the unspecified value after updating a lexical cell.
N6SET:
        CALL N6NEXT
        RET C
        CP 5
        JP NZ,N6BAD
        LD A,(N6TAG)
        OR A
        JP NZ,N6BAD
        LD (N6CHKID),HL
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6NEXT
        JR C,N6SETER
        CALL N6EV
        JR C,N6SETER
        LD (N6RTAG),A
        LD (N6RVAL),HL
        CALL N6NEXT
        JR C,N6SETER
        CP 2
        JR NZ,N6SETER
        POP AF
        LD (N6TCTX),A
        LD HL,(N6CHKID)
        LD (N6LOOKID),HL
        CALL N7SETCUR
        JP NC,N6UNSP
        LD HL,(N6CHKID)
        CALL N9GSETV
        RET C
        JP N6UNSP
N6SETER:
        POP AF
        LD (N6TCTX),A
        SCF
        RET

;-------------------------------------------------------------------------
;  Bounded arithmetic used by procedure bodies
;-------------------------------------------------------------------------

N6ARITH:
        LD (N6OP),A
        CALL N6NEXT
        RET C
        CP 2
        JP Z,N6ARZERO
        LD C,A
        XOR A
        LD (N6TCTX),A
        LD A,(N6OP)
        PUSH AF
        LD A,C
        CALL N6EV
        JR C,N6ARONE
        LD (N6ATAG),A
        LD (N6AVAL),HL
        POP AF
        LD (N6OP),A
        LD A,1
        LD (N6CTAG),A
N6ARLOOP:
        CALL N6NEXT
        RET C
        CP 2
        JR Z,N6ARFIN
        LD C,A
        LD A,(N6CTAG)
        PUSH AF
        LD (N6RVAL),HL
        LD HL,(N6AVAL)
        PUSH HL
        LD A,(N6ATAG)
        PUSH AF
        LD A,(N6OP)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        LD A,C
        LD HL,(N6RVAL)
        CALL N6EV
        JP C,N6ARERR
        LD (N6RTAG),A
        LD (N6RVAL),HL
        POP AF
        LD (N6OP),A
        POP AF
        LD (N6ATAG),A
        POP HL
        LD (N6AVAL),HL
        POP AF
        LD (N6CTAG),A
        LD A,2
        LD (N6CTAG),A
        CALL N6NCALL
        RET C
        LD (N6ATAG),A
        LD (N6AVAL),HL
        JR N6ARLOOP
N6ARONE:
        POP AF
        SCF
        RET
N6ARFIN:
        LD A,(N6OP)
        CP 2
        JR Z,N6NEG
        LD A,(N6ATAG)
        LD HL,(N6AVAL)
        OR A
        RET
N6NEG:
        LD A,(N6CTAG)
        CP 1
        JR NZ,N6ARRET
        LD A,(N6ATAG)
        LD HL,(N6AVAL)
        JP NNEG
N6ARRET:
        LD A,(N6ATAG)
        LD HL,(N6AVAL)
        OR A
        RET
N6ARZERO:
        LD A,(N6OP)
        CP 1
        JR Z,N6ZRES
        CP 3
        JR Z,N6ORES
        JP N6BAD
N6ZRES:
        LD A,3
        LD HL,0
        RET
N6ORES:
        LD A,3
        LD HL,1
        RET
N6NCALL:
        LD HL,(N6AVAL)
        LD DE,(N6RVAL)
        LD A,(N6RTAG)
        LD B,A
        LD A,(N6OP)
        CP 1
        JR Z,N6ADD
        CP 2
        JR Z,N6SUB
        CP 3
        JR Z,N6MUL
        LD A,(N6ATAG)
        JP NDIV
N6ADD:
        LD A,(N6ATAG)
        JP NADD
N6SUB:
        LD A,(N6ATAG)
        JP NSUB
N6MUL:
        LD A,(N6ATAG)
        JP NMUL
N6ARERR:
        POP AF
        POP AF
        POP HL
        POP AF
        SCF
        RET

;-------------------------------------------------------------------------
;  Control forms and skipped event ranges
;-------------------------------------------------------------------------

N6IF:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6EXPR
        JP C,N6IEP
        LD (N6TTAG),A
        LD (N6TVAL),HL
        CALL N6NEXT
        JP C,N6IEP
        LD (N6BRK),A
        LD (N6RVAL),HL
        LD A,(N6TTAG)
        OR A
        JR NZ,N6IFTRUE
        LD HL,(N6TVAL)
        LD DE,0FE00H
        OR A
        SBC HL,DE
        JR Z,N6IFNO
N6IFTRUE:
        LD A,(N6BRK)
        LD C,A
        LD HL,(N6TVAL)
        LD A,(N6TTAG)
        POP AF
        PUSH AF
        LD (N6TCTX),A
        LD A,C
        LD HL,(N6RVAL)
        CALL N6EV
        JP C,N6IEP
        LD (N6ATAG),A
        LD (N6AVAL),HL
        LD A,(N6TF)
        OR A
        JR NZ,N6ITP
        POP AF
        LD (N6TCTX),A
        CALL N6NEXT
        JR C,N6IE
        LD (N6BRK),A
        LD (N6RVAL),HL
        CP 2
        JR Z,N6IFRES
        LD A,(N6BRK)
        CALL N6SKIP
        JR C,N6IE
        CALL N6NEXT
        JR C,N6IE
        CP 2
        JR NZ,N6IE
N6IFRES:
        LD A,(N6ATAG)
        LD HL,(N6AVAL)
        OR A
        RET
N6IFNO:
        LD A,(N6BRK)
        CALL N6SKIP
        JR C,N6IEP
        CALL N6NEXT
        JR C,N6IEP
        LD (N6BRK),A
        LD (N6RVAL),HL
        CP 2
        JR Z,N6IFNONE
        POP AF
        LD (N6TCTX),A
        LD A,(N6BRK)
        LD C,A
        LD A,C
        LD HL,(N6RVAL)
        CALL N6EV
        JR C,N6IE
        LD (N6ATAG),A
        LD (N6AVAL),HL
        LD A,(N6TF)
        OR A
        JR NZ,N6IT
        CALL N6NEXT
        JR C,N6IE
        CP 2
        JR NZ,N6IE
N6IFALT:
        LD A,(N6ATAG)
        LD HL,(N6AVAL)
        OR A
        RET
N6IFNONE:
        POP AF
        LD (N6TCTX),A
        LD A,0
        LD HL,0FE04H
        OR A
        RET
N6ITP:
        POP AF
        XOR A
        RET
N6IT:
        XOR A
        RET
N6IEP:
        POP AF
        SCF
        RET
N6IE:
        SCF
        RET

N6BEGIN:
        LD A,(N6TCTX)
        PUSH AF
        CALL N6NEXT
        JP C,N6BEP
        LD (N6RVAL),HL
        CP 2
        JR Z,N6BEEMP
        LD (N6BEK),A
N6BELOOP:
        LD HL,(N6PC)
        LD (N6BEPTR),HL
        LD A,(N6BEK)
        CALL N6SKIP
        JR C,N6BEP
        LD HL,(N6PC)
        LD DE,(N6SPLEN)
        OR A
        SBC HL,DE
        JR NC,N6BEP
        LD HL,N6SPOOLB
        LD DE,(N6PC)
        ADD HL,DE
        LD A,(HL)
        CP 2
        LD A,0
        JR NZ,N6BENOT
        LD A,(N6DEPTH)
        OR A
        JR Z,N6BENOT
        LD A,1
N6BENOT:
        LD (N6TCTX),A
        LD HL,(N6BEPTR)
        LD (N6PC),HL
        LD A,(N6BEK)
        LD HL,(N6RVAL)
        CALL N6EV
        JR C,N6BEP
        LD (N6ATAG),A
        LD (N6AVAL),HL
        LD A,(N6TF)
        OR A
        JR NZ,N6BETAIL
        CALL N6NEXT
        JR C,N6BEP
        LD (N6RVAL),HL
        CP 2
        JR Z,N6BEDONE
        LD (N6BEK),A
        JR N6BELOOP
N6BEDONE:
        POP AF
        LD (N6TCTX),A
        LD A,(N6ATAG)
        LD HL,(N6AVAL)
        OR A
        RET
N6BEEMP:
        POP AF
        LD (N6TCTX),A
N6UNSP:
        LD A,0
        LD HL,0FE04H
        OR A
        RET
N6BETAIL:
        POP AF
        XOR A
        RET
N6BEP:
        POP AF
        SCF
        RET
