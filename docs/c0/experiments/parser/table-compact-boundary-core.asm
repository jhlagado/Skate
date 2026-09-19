;=============================================================================
;  Table-driven predictive C0 parser
;=============================================================================
;
;  PURPOSE
;  -------
;  Interpret compact production rows with an explicit bounded prediction
;  stack.  The rows encode the same action positions as the handwritten
;  candidate; only native table lookup chooses the production.
;
;  PUBLIC INTERFACE
;  ----------------
;
;  PPARSE  Parse the fixture input from start to synthesized EOF.
;
;+---------------------------------------------------------------------------+
;| CALL                                                                      |
;|   ADBASE..ADLIM and SKBASE..SKLIM already describe fixture buffers.       |
;|   SKINJ is preserved as the optional injected-sink-failure selector.      |
;|                                                                           |
;| SUCCESS                                                                   |
;|   A=0, carry clear; IX, IY, SP and the caller return PC are preserved.    |
;|                                                                           |
;| FAILURE                                                                   |
;|   A=128 syntax, 129 capacity, or 130 sink; carry set.                    |
;+---------------------------------------------------------------------------+
;
;  SYMBOLS AND BOUNDS
;  ------------------
;  Terminals use their token ordinals (0..7), actions use 40H+ordinal,
;  nonterminals use 10H+, and repeating sequence markers use 20H+.  TSTACK is
;  exactly 256 bytes.  TPUSH checks TSP before every write, including a full
;  production row and all repeat iterations.  Repeating markers are popped
;  before their next item is pushed, so long flat input has constant storage.
;=============================================================================

NEXPR   EQU 10H
NLIST   EQU 11H
SLOOP   EQU 20H
SBODY   EQU 21H
SARGS   EQU 22H
SPARAM  EQU 23H
SALT    EQU 24H
ACTBASE EQU 40H
ENDROW  EQU 255

TSTART:
PPARSE:
        CALL ADRESET              ; Re-entry resets source and common depth.
        CALL SKRESET              ; Prior trace records cannot leak forward.
        LD HL,0
        LD (TSP),HL               ; Empty explicit prediction stack.
        LD (TMAX),HL              ; High-water stack usage starts at zero.
        LD A,SLOOP
        CALL TPUSH                 ; The loop marker drives the complete parse.
        RET C
        JP TLOOP

; Pop one symbol, execute it, and continue until SLOOP observes EOF.  The
; explicit stack contains only bounded grammar state, never a trace or source.
TLOOP:
        CALL TPOP
        RET C                     ; Defensive internal invariant failure.
        CP ACTBASE
        JP NC,TACT                ; Actions are 40H through 54H.
        CP 20H
        JP NC,TSPECIAL             ; Repeating sequence markers.
        CP 10H
        JP NC,TNONTERM             ; NEXPR and NLIST.
        JP TTERM                   ; Remaining symbols are token terminals.

; Actions always refresh lookahead so their index is the grammar position after
; the preceding token or expression.  The action ordinal itself survives ADPEEK.
TACT:
        SUB ACTBASE
        PUSH AF
        CALL ADPEEK
        POP AF
        CALL SKACT
        RET C
        JP TLOOP

; Match a terminal.  EOF is a lookahead-only terminal; all other terminals pass
; through ADTAKE, including the shared 33rd-OPEN check.
TTERM:
        LD B,A
        CALL ADPEEK
        CP B
        JP NZ,TSYNTAX
        LD A,B
        OR A
        JR Z,TLOOP                ; EOF remains available at its single index.
        CALL ADTAKE
        RET C
        JP TLOOP

; Select an expression row from XTAB.  The row itself is pushed bottom to top
; by TPROD, making table entries the sole prediction decision at this point.
TNEXPR:
        CALL TGETX
        RET C
        CALL TPROD
        RET C
        JP TLOOP

; Select the reserved list head or generic application from LTAB.
TNList:
        CALL TGETL
        RET C
        CALL TPROD
        RET C
        JP TLOOP

TNONTERM:
        CP NEXPR
        JP Z,TNEXPR
        CP NLIST
        JP Z,TNList
        JP TINTERN

; A loop marker sees CLOSE as its empty production.  Every nonempty iteration
; pushes the marker back before its action and expression, bounding flat input.
TSPECIAL:
        CP SLOOP
        JP Z,TSLOOP
        CP SBODY
        JP Z,TSBODY
        CP SARGS
        JP Z,TSARGS
        CP SPARAM
        JP Z,TSPARAM
        CP SALT
        JP Z,TSALT
        JP TINTERN

TSLOOP:
        CALL ADPEEK
        OR A
        JP Z,TPARSEOK              ; Top-level EOF is the accepting condition.
        LD HL,PROGROW
        CALL TPROD
        RET C
        JP TLOOP

TSBODY:
        CALL ADPEEK
        CP CLOSE
        JP Z,TLOOP                ; Empty begin sequence or completed lambda body.
        LD HL,BODYROW
        CALL TPROD
        RET C
        JP TLOOP

TSARGS:
        CALL ADPEEK
        CP CLOSE
        JP Z,TLOOP                ; Generic applications may have zero arguments.
        LD HL,ARGSROW
        CALL TPROD
        RET C
        JP TLOOP

TSPARAM:
        CALL ADPEEK
        CP CLOSE
        JP Z,TLOOP                ; Empty proper formal list.
        CP NAME
        JP NZ,TSYNTAX             ; A formal is exactly one NAME token.
        LD HL,PARMROW
        CALL TPROD
        RET C
        JP TLOOP

TSALT:
        CALL ADPEEK
        CP CLOSE
        JR Z,TSALTEMP
        LD HL,ALTROW
        CALL TPROD
        RET C
        JP TLOOP
TSALTEMP:
        LD HL,ABSROW
        CALL TPROD
        RET C
        JP TLOOP

; Return a row pointer from the token-indexed two-byte table in HL.  A null row
; is a syntax error, which also rejects all unknown ordinals and reserved values.
TGETX:
        CALL ADPEEK
        LD A,(ADCUR)
        CP 8
        JP NC,TSYNTAX
        LD E,A
        LD D,0
        LD HL,XTAB
        ADD HL,DE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,TSYNTAX
        EX DE,HL
        XOR A
        RET

TGETL:
        CALL ADPEEK
        LD A,(ADCUR)
        CP 8
        JR NC,TGETAPP             ; Unknown heads still execute APP_OPEN first.
        LD E,A
        LD D,0
        LD HL,LTAB
        ADD HL,DE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,TSYNTAX
        EX DE,HL
        XOR A
        RET
TGETAPP:
        LD HL,XAPP
        XOR A
        RET

; Push a complete immutable row.  HL is restored around each bounded TPUSH so
; a capacity failure still unwinds the native call stack correctly.
TPROD:
        LD A,(HL)
        INC HL
        CP ENDROW
        JR Z,TPRODOK
        PUSH HL
        CALL TPUSH
        POP HL
        RET C
        JR TPROD
TPRODOK:
        XOR A
        RET

; Every explicit stack write is checked before calculating its destination.
TPUSH:
        LD C,A
        LD HL,(TSP)
        LD A,H
        OR A
        JR NZ,TSTKERR             ; 0100H is the first unavailable slot.
        LD DE,TSTACK
        ADD HL,DE
        LD A,C
        LD (HL),A
        LD DE,(TSP)
        INC DE
        LD (TSP),DE
        LD HL,(TMAX)
        OR A
        SBC HL,DE                  ; Old max minus new depth.
        JR NC,TPUSHOK              ; Equal or smaller depth keeps the old max.
        LD (TMAX),DE               ; Carry means the new depth is larger.
TPUSHOK:
        XOR A
        RET
TSTKERR:
        LD A,129
        SCF
        RET

TPOP:
        LD HL,(TSP)
        LD A,H
        OR L
        JR Z,TINTERN
        DEC HL
        LD (TSP),HL
        LD DE,TSTACK
        ADD HL,DE
        LD A,(HL)
        OR A                       ; Return symbol with carry clear.
        RET

TPARSEOK:
        XOR A
        RET

TSYNTAX:
        LD A,128
        SCF
        RET

TINTERN:
        LD A,131                  ; Unreachable table/stack invariant marker.
        SCF
        RET

; Token-indexed prediction tables.  A null pointer is an intentional syntax
; entry.  The table rows remain immutable and are counted separately below.
TTABST:                         ; Zero-width table start boundary.
XTAB:   DW 0,XOPEN,0,XATOM,0,0,0,XNAME
LTAB:   DW XAPP,XAPP,XAPP,XAPP,XIF,XBEGIN,XLAMBDA,XAPP

; Rows list symbols in the order TPUSH must receive them (bottom to top).
XATOM:  DB ATOM,ACTBASE+1,ENDROW
XNAME:  DB NAME,ACTBASE+2,ENDROW
XOPEN:  DB NLIST,OPEN,ENDROW

XIF:    DB ACTBASE+9,CLOSE,SALT,ACTBASE+6,NEXPR,ACTBASE+5,NEXPR,ACTBASE+4,IFTOK,ENDROW
XBEGIN: DB ACTBASE+11,CLOSE,SBODY,ACTBASE+10,BEGIN,ENDROW
XLAMBDA: DB ACTBASE+16,CLOSE,SBODY,ACTBASE+15,NEXPR,ACTBASE+14,CLOSE,SPARAM,OPEN,ACTBASE+12,LAMBDA,ENDROW
XAPP:   DB ACTBASE+20,CLOSE,SARGS,ACTBASE+18,NEXPR,ACTBASE+17,ENDROW

PROGROW: DB SLOOP,ACTBASE+3,NEXPR,ENDROW
BODYROW: DB SBODY,ACTBASE+15,NEXPR,ENDROW
ARGSROW: DB SARGS,ACTBASE+19,NEXPR,ENDROW
PARMROW: DB SPARAM,NAME,ACTBASE+13,ENDROW
ALTROW:  DB ACTBASE+7,NEXPR,ENDROW
ABSROW:  DB ACTBASE+8,ENDROW

TTABEND:                        ; Zero-width table end boundary.

TCODEEND:
TGUARD: DS 4
TWORK:
TSP:    DW 0                     ; Current explicit prediction stack depth.
TMAX:   DW 0                     ; Measured high-water depth in bytes.
TSTACK: DS 256                   ; Contract maximum; TPUSH guards every write.
TWEND:
TTAIL: DS 4
