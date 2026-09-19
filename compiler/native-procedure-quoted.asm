;=============================================================================
;  N8 quoted data and publication-side pair values
;=============================================================================
;
;  This source part follows native-procedure.asm.  It owns quoted data,
;  pair construction and the persistent value state used by the N8 slice.
;  Keeping the seam explicit leaves both ATOM source parts comfortably below
;  the 65,535-byte limit without changing the assembled order or ABI.
;=============================================================================

;-------------------------------------------------------------------------
;  N8 quoted data and bounded pair values
;-------------------------------------------------------------------------

; Quote is a syntax form: evaluate its datum construction without invoking it.
N8QFORM:
        CALL N6NEXT
        RET C
        CALL N8QDAT
        RET C
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        CALL N6NEXT
        RET C
        CP 2
        JP NZ,N6BAD
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        OR A
        RET

; Apostrophe has already supplied event kind three; its datum has no close.
N8QUOTE:
        CALL N6NEXT
        RET C
        JP N8QDAT

; Convert one spooled datum into a persistent compiler value.
N8QDAT:
        CP 1
        JP Z,N8QLIST
        CP 3
        JP Z,N8QSH
        CP 5
        JP Z,N8QSYM
        CP 7
        JR Z,N8QVAL
        CP 8
        JR Z,N8QVAL
        SCF
        RET
N8QVAL:
        LD A,(N6TAG)
        OR A
        RET
N8QSYM:
        LD A,H
        OR 20H
        LD H,A
        LD A,1
        OR A
        RET

; Nested apostrophe is represented by the ordinary (quote datum) pair list.
N8QSH:
        CALL N6NEXT
        RET C
        CALL N8QDAT
        RET C
        JP N8QMAKE

; Construct the two cells needed for (quote datum), interning quote on demand.
N8QMAKE:
        LD (N8QDTAG),A
        LD (N8QDVAL),HL
        LD HL,(N8QID)
        LD A,H
        OR L
        JR NZ,N8QHAVE
        LD IX,(RSYMCTX)
        LD HL,N8QTEXT
        LD BC,5
        CALL INTERN
        RET C
        LD A,H
        OR 20H
        LD H,A
        LD (N8QID),HL
N8QHAVE:
        LD A,(N8QDTAG)
        LD (N8CATAG),A
        LD HL,(N8QDVAL)
        LD (N8CAVAL),HL
        XOR A
        LD (N8CDTAG),A
        LD HL,0FE02H
        LD (N8CDVAL),HL
        CALL N8NEWPR
        RET C
        LD (N8NEWID),HL
        LD A,1
        LD (N8CATAG),A
        LD HL,(N8QID)
        LD (N8CAVAL),HL
        LD (N8CDTAG),A
        LD HL,(N8NEWID)
        LD (N8CDVAL),HL
        JP N8NEWPR

; Read one quoted proper or dotted list left to right and link its cells.
N8QLIST:
        LD HL,0
        LD (N8QHEAD),HL
        LD (N8QTAIL),HL
N8QLP:
        CALL N6NEXT
        RET C
        CP 2
        JP Z,N8QDONE
        CP 4
        JP Z,N8QDOT
        LD (N8QEV),A
        LD (N8QDVAL),HL
        LD HL,(N8QHEAD)
        PUSH HL
        LD HL,(N8QTAIL)
        PUSH HL
        LD A,(N8QEV)
        LD HL,(N8QDVAL)
        CALL N8QDAT
        JP C,N8QERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP HL
        LD (N8QTAIL),HL
        POP HL
        LD (N8QHEAD),HL
        LD A,(N8QRTAG)
        LD (N8CATAG),A
        LD HL,(N8QRVAL)
        LD (N8CAVAL),HL
        XOR A
        LD (N8CDTAG),A
        LD HL,0FE02H
        LD (N8CDVAL),HL
        CALL N8NEWPR
        JP C,N8QFAIL
        LD (N8QNEW),HL
        LD HL,(N8QHEAD)
        LD A,H
        OR L
        JR Z,N8QFIRST
        LD A,1
        LD (N8CDTAG),A
        LD HL,(N8QNEW)
        LD (N8CDVAL),HL
        LD HL,(N8QTAIL)
        CALL N8SETCDR
        JP C,N8QFAIL
        JR N8QLINK
N8QFIRST:
        LD HL,(N8QNEW)
        LD (N8QHEAD),HL
N8QLINK:
        LD HL,(N8QNEW)
        LD (N8QTAIL),HL
        JP N8QLP
N8QDONE:
        LD HL,(N8QHEAD)
        LD A,H
        OR L
        JR Z,N8QNIL
        LD A,1
        OR A
        RET
N8QNIL:
        LD A,0
        LD HL,0FE02H
        OR A
        RET
N8QDOT:
        LD HL,(N8QHEAD)
        LD A,H
        OR L
        JP Z,N8QFAIL
        CALL N6NEXT
        JP C,N8QFAIL
        LD (N8QEV),A
        LD (N8QDVAL),HL
        LD HL,(N8QHEAD)
        PUSH HL
        LD HL,(N8QTAIL)
        PUSH HL
        LD A,(N8QEV)
        LD HL,(N8QDVAL)
        CALL N8QDAT
        JP C,N8QERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP HL
        LD (N8QTAIL),HL
        POP HL
        LD (N8QHEAD),HL
        CALL N6NEXT
        JP C,N8QFAIL
        CP 2
        JP NZ,N8QFAIL
        LD A,(N8QRTAG)
        LD (N8CDTAG),A
        LD HL,(N8QRVAL)
        LD (N8CDVAL),HL
        LD HL,(N8QTAIL)
        CALL N8SETCDR
        JP C,N8QFAIL
        LD A,1
        LD HL,(N8QHEAD)
        OR A
        RET
N8QERR:
        POP HL
        POP HL
N8QFAIL:
        SCF
        RET

; Pair allocation uses the same logical reference tag and subtype zero as M9.
N8NEWPR:
        LD HL,(N8PCOUNT)
        INC HL
        LD DE,513
        OR A
        SBC HL,DE
        JP NC,N8PERR
        ADD HL,DE
        LD (N8PCOUNT),HL
        LD (N8NEWID),HL
        DEC HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD DE,N8PAIRS
        ADD HL,DE
        LD A,(N8CATAG)
        LD (HL),A
        INC HL
        LD DE,(N8CAVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),0
        INC HL
        LD A,(N8CDTAG)
        LD (HL),A
        INC HL
        LD DE,(N8CDVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (HL),0
        LD HL,(N8NEWID)
        LD A,1
        OR A
        RET
N8PERR:
        SCF
        RET

; Convert a nonzero pair identity to its eight-byte arena record address.
N8PAIRAD:
        LD A,H
        OR L
        JR Z,N8PERR
        LD (N8NEWID),HL
        LD DE,(N8PCOUNT)
        OR A
        SBC HL,DE
        JR C,N8PAOK
        LD A,H
        OR L
        JR Z,N8PAOK
        JP N8PERR
N8PAOK:
        LD HL,(N8NEWID)
        DEC HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD DE,N8PAIRS
        ADD HL,DE
        XOR A
        RET

; Replace one pair's CDR with the tagged value in N8CDTAG:N8CDVAL.
N8SETCDR:
        LD (N8NEWID),HL
        CALL N8PAIRAD
        RET C
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(N8CDTAG)
        LD (HL),A
        INC HL
        LD DE,(N8CDVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        XOR A
        RET

; Return the tagged CAR or CDR from a validated pair reference in A:HL.
N8GETCAR:
        CP 1
        JP NZ,N8PERR
        LD A,H
        AND 0E0H
        JP NZ,N8PERR
        CALL N8PAIRAD
        RET C
        LD A,(HL)
        LD (N8QRTAG),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD A,(N8QRTAG)
        OR A
        RET
N8GETCDR:
        CP 1
        JP NZ,N8PERR
        LD A,H
        AND 0E0H
        JP NZ,N8PERR
        CALL N8PAIRAD
        RET C
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (N8QRTAG),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD A,(N8QRTAG)
        OR A
        RET

;-------------------------------------------------------------------------
;  N8 pair primitives and predicates
;-------------------------------------------------------------------------

N8CONS:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6NEXT
        JP C,N8CERR
        CALL N6EV
        JP C,N8CERR
        LD (N8CATAG),A
        LD (N8CAVAL),HL
        CALL N6NEXT
        JP C,N8CERR
        CALL N6EV
        JP C,N8CERR
        LD (N8CDTAG),A
        LD (N8CDVAL),HL
        CALL N6NEXT
        JP C,N8CERR
        CP 2
        JP NZ,N8CERR
        CALL N8NEWPR
        JP C,N8CERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP AF
        LD (N6TCTX),A
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        OR A
        RET
N8CERR:
        POP AF
        LD (N6TCTX),A
        SCF
        RET

N8CAR:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6NEXT
        JP C,N8OERR
        CALL N6EV
        JP C,N8OERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        CALL N6NEXT
        JP C,N8OERR
        CP 2
        JP NZ,N8OERR
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        CALL N8GETCAR
        JP C,N8OERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP AF
        LD (N6TCTX),A
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        OR A
        RET
N8CDR:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6NEXT
        JP C,N8OERR
        CALL N6EV
        JP C,N8OERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        CALL N6NEXT
        JP C,N8OERR
        CP 2
        JP NZ,N8OERR
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        CALL N8GETCDR
        JP C,N8OERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP AF
        LD (N6TCTX),A
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        OR A
        RET
N8OERR:
        POP AF
        LD (N6TCTX),A
        SCF
        RET

; Build a proper list from zero or more evaluated arguments.
N8LIST:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        LD HL,0
        LD (N8LHEAD),HL
        LD (N8LTAIL),HL
N8LLP:
        CALL N6NEXT
        JP C,N8LERR
        CP 2
        JR Z,N8LDONE
        LD (N8LEV),A
        PUSH HL
        LD HL,(N8LHEAD)
        PUSH HL
        LD HL,(N8LTAIL)
        PUSH HL
        POP DE
        POP BC
        POP HL
        PUSH BC
        PUSH DE
        LD A,(N8LEV)
        CALL N6EV
        JP C,N8LPERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP HL
        LD (N8LTAIL),HL
        POP HL
        LD (N8LHEAD),HL
        LD A,(N8QRTAG)
        LD (N8CATAG),A
        LD HL,(N8QRVAL)
        LD (N8CAVAL),HL
        XOR A
        LD (N8CDTAG),A
        LD HL,0FE02H
        LD (N8CDVAL),HL
        CALL N8NEWPR
        JP C,N8LERR
        LD (N8LNEW),HL
        LD HL,(N8LHEAD)
        LD A,H
        OR L
        JR Z,N8LFIRST
        LD A,1
        LD (N8CDTAG),A
        LD HL,(N8LNEW)
        LD (N8CDVAL),HL
        LD HL,(N8LTAIL)
        CALL N8SETCDR
        JP C,N8LERR
        JR N8LLINK
N8LFIRST:
        LD HL,(N8LNEW)
        LD (N8LHEAD),HL
N8LLINK:
        LD HL,(N8LNEW)
        LD (N8LTAIL),HL
        JP N8LLP
N8LDONE:
        LD HL,(N8LHEAD)
        LD A,H
        OR L
        JR Z,N8LNIL
        LD A,1
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP AF
        LD (N6TCTX),A
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        OR A
        RET
N8LNIL:
        LD A,0
        LD HL,0FE02H
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        POP AF
        LD (N6TCTX),A
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        OR A
        RET
N8LPERR:
        POP HL
        POP HL
N8LERR:
        POP AF
        LD (N6TCTX),A
        SCF
        RET

; Equality and shape predicates inspect the same tagged-value identity.
N8EQ:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6NEXT
        JP C,N8QERR2
        CALL N6EV
        JP C,N8QERR2
        LD (N8EQTAG),A
        LD (N8EQVAL),HL
        CALL N6NEXT
        JP C,N8QERR2
        CALL N6EV
        JP C,N8QERR2
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        CALL N6NEXT
        JP C,N8QERR2
        CP 2
        JP NZ,N8QERR2
        LD A,(N8EQTAG)
        LD B,A
        LD A,(N8QRTAG)
        CP B
        JR NZ,N8EQNO
        LD HL,(N8EQVAL)
        LD DE,(N8QRVAL)
        OR A
        SBC HL,DE
        JR NZ,N8EQNO
        JR N8EQYES
N8EQNO:
        POP AF
        LD (N6TCTX),A
        JP N8FALSE
N8EQYES:
        POP AF
        LD (N6TCTX),A
        JP N8TRUE
N8PAIRP:
        CALL N8ONEVAL
        RET C
        CP 1
        JP NZ,N8FALSE
        LD A,H
        AND 0E0H
        JP NZ,N8FALSE
        CALL N8PAIRAD
        JP C,N8FALSE
        JR N8TRUE
N8NULL:
        CALL N8ONEVAL
        RET C
        OR A
        JR NZ,N8FALSE
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR NZ,N8FALSE
        JR N8TRUE
N8SYMP:
        CALL N8ONEVAL
        RET C
        CP 1
        JP NZ,N8FALSE
        LD A,H
        AND 0E0H
        CP 20H
        JR NZ,N8FALSE
        JR N8TRUE
N8STRP:
        CALL N8ONEVAL
        RET C
        CP 1
        JP NZ,N8FALSE
        LD A,H
        AND 0E0H
        CP 80H
        JR NZ,N8FALSE
        JR N8TRUE
N8CHARP:
        CALL N8ONEVAL
        RET C
        OR A
        JR NZ,N8FALSE
        LD A,H
        CP 0FFH
        JR NZ,N8FALSE
        JR N8TRUE
N8FALSE:
        LD A,0
        LD HL,0FE00H
        OR A
        RET
N8TRUE:
        LD A,0
        LD HL,0FE01H
        OR A
        RET

; Evaluate one operand and require the primitive's closing parenthesis.
N8ONEVAL:
        LD A,(N6TCTX)
        PUSH AF
        XOR A
        LD (N6TCTX),A
        CALL N6NEXT
        JR C,N8ONEERR
        CALL N6EV
        JR C,N8ONEERR
        LD (N8QRTAG),A
        LD (N8QRVAL),HL
        CALL N6NEXT
        JR C,N8ONEERR
        CP 2
        JR NZ,N8ONEERR
        LD A,(N8QRTAG)
        LD HL,(N8QRVAL)
        LD (N8EQTAG),A
        LD (N8EQVAL),HL
        POP AF
        LD (N6TCTX),A
        LD A,(N8EQTAG)
        LD HL,(N8EQVAL)
        OR A
        RET
N8ONEERR:
        POP AF
        LD (N6TCTX),A
        SCF
        RET
N8QERR2:
        POP AF
        LD (N6TCTX),A
        SCF
        RET

;-------------------------------------------------------------------------
;  N8 literal recipe serialization
;-------------------------------------------------------------------------
;
;  N8SERIAL writes one pair graph in the shared postfix recipe shape:
;  tagged values are three bytes ($80|tag, payload low, payload high),
;  and each pair operation is one zero byte.  The serializer is deliberately
;  bounded and keeps its output in a separate 2,048-byte staging buffer.
;
;  Input:  HL = one-based compiler pair identity.
;  Output: N8RECBUF contains the recipe and N8OUTLEN its byte length.
;          Carry signals an invalid identity, depth overflow or full buffer.
;-------------------------------------------------------------------------

N8SERIAL:
        LD (N8SADDR),HL
        LD HL,N8RECBUF
        LD (N8OUTPTR),HL
        LD HL,0
        LD (N8OUTLEN),HL
        XOR A
        LD (N8SERDEP),A
        LD HL,(N8SADDR)
        LD A,1
        CALL N8SERVAL
        RET C
        XOR A
        RET

; Serialize A:HL as one value, recursively expanding ordinary pair refs.
N8SERVAL:
        LD (N8STAG),A
        LD (N8SVAL),HL
        CP 1
        JP NZ,N8SATOM
        LD A,H
        AND 0E0H
        JR NZ,N8SATOM
        LD HL,(N8SVAL)
        LD A,H
        OR L
        JP Z,N8SERERR
        LD DE,(N8PCOUNT)
        OR A
        SBC HL,DE
        JR C,N8SPAIR
        JR Z,N8SPAIR
        JP N8SERERR

N8SPAIR:
        LD A,(N8SERDEP)
        INC A
        CP 64
        JP NC,N8SERERR
        LD (N8SERDEP),A
        LD HL,(N8SVAL)
        CALL N8PAIRAD
        JP C,N8SERERR
        LD (N8SADDR),HL

        LD A,(HL)
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL N8SERVAL
        JP C,N8SERERR

        LD HL,(N8SADDR)
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL N8SERVAL
        JP C,N8SERERR

        XOR A
        CALL N8SBYTE
        JP C,N8SERERR
        LD A,(N8SERDEP)
        DEC A
        LD (N8SERDEP),A
        XOR A
        RET

; Serialize a scalar, closure or other non-pair tagged value verbatim.
N8SATOM:
        LD A,(N8STAG)
        OR 80H
        CALL N8SBYTE
        RET C
        LD HL,(N8SVAL)
        JP N8SWORD

; Append one byte to the bounded recipe buffer.
N8SBYTE:
        PUSH AF
        LD HL,(N8OUTLEN)
        LD A,H
        CP 8
        JR NC,N8SBERR
        LD HL,(N8OUTPTR)
        POP AF
        LD (HL),A
        INC HL
        LD (N8OUTPTR),HL
        LD HL,(N8OUTLEN)
        INC HL
        LD (N8OUTLEN),HL
        OR A
        RET
N8SBERR:
        POP AF
        SCF
        RET

; Append the little-endian payload word in HL.
N8SWORD:
        PUSH HL
        LD A,L
        CALL N8SBYTE
        JR C,N8SWFAIL
        POP HL
        LD A,H
        JP N8SBYTE
N8SWFAIL:
        POP HL
        SCF
        RET

N8SERERR:
        LD A,0
        SCF
        RET

;-------------------------------------------------------------------------
;  N8 literal recipe publication
;-------------------------------------------------------------------------
;
;  N8EMIT publishes a variable result section, a second initialized NOBJ
;  recipe section and the first lowered-program value stub.  The launch stub
;  remains fixed, but its result count and both section/image lengths are
;  checked and patched before publication.
;-------------------------------------------------------------------------

; Serialize the result and patch the section/image lengths and data prefix.
N8PATCH:
        LD A,(N4RTAG)
        CP 1
        JR Z,N8PPAIR
        LD HL,0
        LD (N8OUTLEN),HL
        JR N8PLEN
N8PPAIR:
        LD HL,(N4RVAL)
        CALL N8SERIAL
        RET C
N8PLEN:
        LD HL,(N8OUTLEN)
        LD (N8RHEAD),HL
        ; Section 3 contains the two-byte recipe length followed by bytes.
        LD HL,(N8OUTLEN)
        LD DE,2
        ADD HL,DE
        PUSH HL
        LD DE,N8RSOFF
        CALL N8OBJADR
        EX DE,HL
        POP HL
        CALL N8PUTW
        ; IMAGE length includes the six-byte section/offset prefix.
        LD HL,(N8OUTLEN)
        LD DE,8
        ADD HL,DE
        PUSH HL
        LD DE,N8RPOFF
        CALL N8OBJADR
        EX DE,HL
        POP HL
        CALL N8PUTW
        CALL N8CODE
        XOR A
        RET

; Emit the first lowered-program code slice.  A flat arithmetic form is small
; enough to carry its two ABI-2 operands directly in the reserved slot.  All
; other numeric results retain the classifier stub; references retain the
; neutral return path.  The service-call relocation is retargeted only after
; the shape has been recognized, so every emitted call still has one checked
; NOBJ relocation site.
N8CODE:
        XOR A
        LD (N8CLENW),A
        LD (N8CLENW+1),A
        LD (N8CMODE),A
        LD DE,N8CODOF
        CALL N8OBJADR
        ; Clear the complete reserved slot before selecting the lowered value.
        LD B,N8COLEN
        XOR A
N8CZ:
        LD (HL),A
        INC HL
        DJNZ N8CZ
        LD DE,N8CODOF
        CALL N8OBJADR
        LD A,2
        LD (N8GSVC),A
        CALL N8LOWER
N8CSIM:
        XOR A
        LD (N8CMODE),A
        CALL N8CSVC
        LD DE,N8CODOF
        CALL N8OBJADR
        LD A,(N8GARGC)
        CP 1
        JR Z,N8CUN
        ; Binary lowering places CALL at offset 203, rather than 198.
        LD DE,N8RELSI
        CALL N8OBJADR
        LD (HL),203
        INC HL
        XOR A
        LD (HL),A
        LD DE,N8CODOF
        CALL N8OBJADR
        ; Binary arithmetic: LD A,tag; LD HL,value; LD B,tag;
        ; LD DE,value; CALL service; RET.
        LD (HL),$3E
        INC HL
        LD A,(N8G1TAG)
        LD (HL),A
        INC HL
        LD (HL),$21
        INC HL
        LD A,(N8G1VAL)
        LD (HL),A
        INC HL
        LD A,(N8G1VAL+1)
        LD (HL),A
        INC HL
        LD (HL),$06
        INC HL
        LD A,(N8G2TAG)
        LD (HL),A
        INC HL
        LD (HL),$11
        INC HL
        LD A,(N8G2VAL)
        LD (HL),A
        INC HL
        LD A,(N8G2VAL+1)
        LD (HL),A
        INC HL
        LD (HL),$CD
        INC HL
        INC HL
        INC HL
        LD (HL),$C9
        JP N8CLEN
N8CUN:
        ; Unary negation: LD A,tag; LD HL,value; CALL service; RET.
        LD (HL),$3E
        INC HL
        LD A,(N8G1TAG)
        LD (HL),A
        INC HL
        LD (HL),$21
        INC HL
        LD A,(N8G1VAL)
        LD (HL),A
        INC HL
        LD A,(N8G1VAL+1)
        LD (HL),A
        INC HL
        LD (HL),$CD
        INC HL
        INC HL
        INC HL
        LD (HL),$C9
        JP N8CLEN
N8CPAIR:
        LD A,1
        LD (N8CMODE),A
        ; Enter the pair body in the reserved tail of the code slot.  Keeping
        ; its service/data relocations away from the arithmetic stub means
        ; every emitted NOBJ has one disjoint relocation set, even when the
        ; pair body is unreachable for a numeric result.
        LD DE,N8CODOF
        CALL N8OBJADR
        LD (HL),$18
        INC HL
        LD (HL),14
        INC HL
        LD DE,14
        ADD HL,DE
        ; Construct one rooted packet, fill its two integer arguments, and
        ; call the provider's pairs.cons service.  The packet-new, root-base
        ; and pair-service operands are fixed NOBJ relocation sites.
        LD (HL),$01
        INC HL
        LD (HL),$02
        INC HL
        LD (HL),$00
        INC HL
        LD (HL),$CD
        INC HL
        INC HL
        INC HL
        LD (HL),$21
        INC HL
        INC HL
        INC HL
        LD (HL),$36
        INC HL
        LD (HL),$03
        INC HL
        LD (HL),$23
        INC HL
        LD (HL),$11
        INC HL
        LD A,(N8G1VAL)
        LD (HL),A
        INC HL
        LD A,(N8G1VAL+1)
        LD (HL),A
        INC HL
        LD (HL),$73
        INC HL
        LD (HL),$23
        INC HL
        LD (HL),$72
        INC HL
        LD (HL),$23
        INC HL
        LD (HL),$36
        INC HL
        LD (HL),$00
        INC HL
        LD (HL),$23
        INC HL
        LD (HL),$36
        INC HL
        LD (HL),$03
        INC HL
        LD (HL),$23
        INC HL
        LD (HL),$11
        INC HL
        LD A,(N8G2VAL)
        LD (HL),A
        INC HL
        LD A,(N8G2VAL+1)
        LD (HL),A
        INC HL
        LD (HL),$73
        INC HL
        LD (HL),$23
        INC HL
        LD (HL),$72
        INC HL
        LD (HL),$23
        INC HL
        LD (HL),$36
        INC HL
        LD (HL),$00
        INC HL
        LD (HL),$11
        INC HL
        INC HL
        INC HL
        LD (HL),$01
        INC HL
        LD (HL),$02
        INC HL
        LD (HL),$00
        INC HL
        LD (HL),$CD
        INC HL
        INC HL
        INC HL
        LD (HL),$C9
        JP N8CLEN
N8CFALL:
        LD A,2
        LD (N8CMODE),A
        CALL N8CSVC
        LD DE,N8CODOF
        CALL N8OBJADR
        LD A,(N4RTAG)
        CP 0
        JR Z,N8CNUM
        CP 3
        JR Z,N8CNUM
        LD A,$C9
        LD (HL),A
        INC HL
        ; Leave the service-call relocation at offsets 198/199, but make it
        ; unreachable for a reference result until the runtime owns it.
        LD DE,4
        ADD HL,DE
        LD (HL),$CD
        INC HL
        INC HL
        JP N8CLEN
N8CNUM:
        LD A,$3E
        LD (HL),A
        INC HL
        LD A,(N4RTAG)
        LD (HL),A
        INC HL
        LD A,$21
        LD (HL),A
        INC HL
        LD A,(N4RVAL)
        LD (HL),A
        INC HL
        LD A,(N4RVAL+1)
        LD (HL),A
        INC HL
        LD (HL),$CD
        INC HL
        INC HL
        INC HL
        LD (HL),$C9
        JP N8CLEN

; Check every dynamic field before N8CRC emits the final checksum.  The
; result message must remain in its reserved 128-byte gap, the recipe must
; remain within its independent spool, and the recorded recipe length must
; agree with the bytes that N8SERIAL produced.
N8VALID:
        LD HL,(N8MLEN)
        LD DE,N4MSGLN
        OR A
        SBC HL,DE
        JR C,N8VMSGOK
        JR Z,N8VMSGOK
        JR N8VFAIL
N8VMSGOK:
        LD HL,(N8CLENW)
        LD DE,N8COLEN
        OR A
        SBC HL,DE
        JR C,N8VCOK
        JR Z,N8VCOK
        JR N8VFAIL
N8VCOK:
        LD HL,(N8OUTLEN)
        LD DE,N8RECMAX
        OR A
        SBC HL,DE
        JR C,N8VRECOK
        JR Z,N8VRECOK
        JR N8VFAIL
N8VRECOK:
        LD HL,(N8RHEAD)
        LD DE,(N8OUTLEN)
        OR A
        SBC HL,DE
        JR NZ,N8VFAIL
        XOR A
        RET
N8VFAIL:
        SCF
        RET

; Patch the result section after N8PRT has produced its bounded byte stream.
; Section 2 follows the 512-byte initialized image at run offset $0200.  The
; NOBJ image record carries the checked result length; the standalone COM
; compatibility image has its own count word in N4COM.
N8MSET:
        LD HL,(N8MLEN)
        PUSH HL
        LD DE,N8MSOFF
        CALL N8OBJADR
        EX DE,HL
        POP HL
        CALL N8PUTW
        LD HL,(N8MLEN)
        LD DE,6
        ADD HL,DE
        PUSH HL
        LD DE,N8MPOFF
        CALL N8OBJADR
        EX DE,HL
        POP HL
        CALL N8PUTW
        LD HL,(N8MLEN)
        LD DE,N4COMMSG
        JP N8PUTW

; Convert a byte offset in DE to an address inside the NOBJ skeleton.
N8OBJADR:
        LD HL,N4OBJ
        ADD HL,DE
        RET

; Write the little-endian word in HL at the address in DE.
N8PUTW:
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        RET

N8WRITE:
N8DISP:
        CALL N8ONEVAL
        RET C
        JP N6UNSP
N8NEWLN:
        CALL N6NEXT
        RET C
        CP 2
        JP NZ,N6BAD
        JP N6UNSP

; N6's first primitive predicate is zero?.  It keeps the numeric check at the
; same boundary as arithmetic, then compares exact integers without conversion.
N6PRED:
        CALL N6NEXT
        RET C
        CALL N6EV
        RET C
        LD (N6ATAG),A
        LD (N6AVAL),HL
        CALL N6NEXT
        RET C
        CP 2
        JP NZ,N6BAD
        LD A,(N6ATAG)
        LD HL,(N6AVAL)
        CALL NCLASS
        JP C,N6BAD
        LD A,(N6ATAG)
        CP 3
        JR Z,N6PINT
        LD HL,(N6AVAL)
        LD A,H
        OR L
        JR NZ,N6PFALSE
N6PTRUE:
        LD A,0
        LD HL,0FE01H
        OR A
        RET
N6PFALSE:
        LD A,0
        LD HL,0FE00H
        OR A
        RET
N6PINT:
        LD HL,(N6AVAL)
        LD A,H
        OR L
        JR Z,N6PTRUE
        JR N6PFALSE

; Skip one already-read datum, including nested lists, without evaluating it.
N6SKIP:
        CP 1
        JR Z,N6SKLIST
        CP 3
        JR Z,N6SKQ
        CP 2
        JP Z,N6BAD
        CP 4
        JP Z,N6BAD
        OR A
        RET
N6SKQ:
        CALL N6NEXT
        RET C
        JR N6SKIP
N6SKLIST:
        CALL N6NEXT
        RET C
        CP 2
        JR Z,N6SKDONE
        CALL N6SKIP
        RET C
        JR N6SKLIST
N6SKDONE:
        XOR A
        RET

;-------------------------------------------------------------------------
;  Evaluator state and bounded work areas
;-------------------------------------------------------------------------

N6PC:       DW 0
N6SPLEN:    DW 0
N6SPPTR:    DW 0
N6SPK:      DB 0
N6KIND:     DB 0
N6TAG:      DB 0
N6HEADK:    DB 0
N6HEADID:   DW 0
N6BRK:      DB 0
N6OP:       DB 0
N6ATAG:     DB 0
N6RTAG:     DB 0
N6TTAG:     DB 0
N6CTAG:     DB 0
N6NARITY:   DB 0
N6SCNST:    DB 0
N6CCOUNT:   DB 0
N6DEPTH:    DB 0
N6ARGC:     DB 0
N6FCNT:     DB 0
N6TMPI:     DB 0
N6HASRES:   DB 0
N6REST:     DB 0
N6TCTX:     DB 0
N6TF:       DB 0
N6CALLT:    DB 0
N6BEK:      DB 0
N6AVAL:     DW 0
N6RVAL:     DW 0
N6TVAL:     DW 0
N6CVAL:     DW 0
N6LOOKID:   DW 0
N6FP:       DW 0
N6FRCUR: DW N6FRAMES
N6CURC:     DW 0
N6BEND:     DW 0
N6CENV:     DW 0
N6RESV:     DW 0
N6CLOSP:    DW N6CLOS
N6PARMP:    DW N6PARAM
N6TMPD:     DW 0
N6TMPP:     DW 0
N6TMPB:     DW 0
N6TMPF:     DW 0
N6TMPE:     DW 0
N6TMPENV:   DW 0
N6CHKEND:   DW 0
N6CHKID:    DW 0
N6CURPC:    DW 0
N6BEPTR:    DW 0
N6ARGTP:    DW 0
N6ARGVP:    DW 0
N6ASDEP:    DB 0
N6ASCNT:    DS 16
N6ASTP:     DW 0
N6ASVP:     DW 0
N6ASRVL:    DW 0
N6ASRET:    DW 0
N6SPOOLB:   DS 4096
N6CLOS:     DS 160
N6PARAM:    DS 256
N6FRAMES:   DS 640
N6ARGTAG:   DS 8
N6ARGVAL:   DS 16
N8CATAG:    DB 0
N8CDTAG:    DB 0
N8QRTAG:    DB 0
N8QDTAG:    DB 0
N8EQTAG:    DB 0
N8QEV:      DB 0
N8LEV:      DB 0
N8LHEAD:    DW 0
N8LTAIL:    DW 0
N8QHEAD:    DW 0
N8QTAIL:    DW 0
N8QNEW:     DW 0
N8LNEW:     DW 0
N8CAVAL:    DW 0
N8CDVAL:    DW 0
N8QRVAL:    DW 0
N8QDVAL:    DW 0
N8EQVAL:    DW 0
N8NEWID:    DW 0
N8PCOUNT: DW 0
N8QID:   DW 0
N8OUTPTR:   DW 0
N8OUTLEN:   DW 0
N8STAG:     DB 0
N8SVAL:     DW 0
N8SADDR:    DW 0
N8SERDEP:   DB 0
N8MLEN:     DW 0
N8PMODE:    DB 1
N8PVAL:     DW 0
N8PID:      DW 0
N8PPTR:     DW 0
N8PLEFT:    DW 0
N8PPREC:    DW 0
N8PCART:    DB 0
N8PCARV:    DW 0
N8PCDRT:    DB 0
N8PCDRV:    DW 0
N8PFLAG:    DB 0
N8RHEAD:    DW 0
N8CLENW:    DW 0
N8MSGBUF:   DS 128
; Shares the post-evaluation event-spool storage; see N8LOWER.
N8RECBUF EQU N6SPOOLB
N7ENVFOR:   DS 32
N7ENVSP:    DW N7ENVS
N7ENVS:     DS 736
N8QTEXT:    DB "quote"
N8EOFTXT:   DB "#<eof>"
N8UNSTXT:   DB "#<unspecified>"
N8MRKTXT:   DB "#<>"
; The compiler's transient pair graph is an overlay above the native stack.
; It is written only during compilation, so keeping it out of the COM image
; removes the old N8a four-kilobyte reservation without changing values.
N8PAIRS EQU 0B000H
N8PEND EQU 0C000H
