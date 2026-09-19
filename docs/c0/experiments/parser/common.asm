;=============================================================================
;  C0 parser fixture adapter and action sink
;=============================================================================
;
;  PURPOSE
;  -------
;  Supply preclassified token bytes and record the action stream for either
;  native parser candidate.  This file is deliberately shared so the two
;  parser measurements differ only in their prediction engine.
;
;  PUBLIC INTERFACE
;  ----------------
;
;  ADRESET  Reset the monotonic input cursor and parenthesis counter.
;
;+---------------------------------------------------------------------------+
;| CALL                                                                      |
;|   No register inputs.  ADBASE..ADLIM and SKBASE..SKLIM are fixture-owned.  |
;|                                                                           |
;| SUCCESS                                                                   |
;|   A=0, carry clear.  No input byte is read.                               |
;+---------------------------------------------------------------------------+
;
;  ADPEEK   Fetch the current token once, or return its cached value.
;
;+---------------------------------------------------------------------------+
;| SUCCESS                                                                   |
;|   A = current token ordinal; carry clear.  ADTOKIX is its token index.    |
;|                                                                           |
;| NOTES                                                                     |
;|   EOF is synthesized at ADLIM and has index equal to the non-EOF count.   |
;|   A zero byte inside the fixture extent is returned as 255 (syntax).      |
;+---------------------------------------------------------------------------+
;
;  ADTAKE   Consume the current non-EOF token.
;
;+---------------------------------------------------------------------------+
;| SUCCESS                                                                   |
;|   A = consumed token; carry clear.  The monotonic cursor advances.        |
;                                                                           |
;| FAILURE                                                                   |
;|   A=129, carry set when a 33rd OPEN would exceed the common bound.        |
;+---------------------------------------------------------------------------+
;
;  SKACT    Append one three-byte action record.
;
;+---------------------------------------------------------------------------+
;| CALL                                                                      |
;|   A = action ordinal.  ADPEEK must have established the current token.    |
;                                                                           |
;| SUCCESS                                                                   |
;|   A=0, carry clear.  Record is ordinal, index low, index high.             |
;                                                                           |
;| FAILURE                                                                   |
;|   A=129, carry set for output exhaustion; A=130 for injected sink error.  |
;|   No bytes are written on either failure.                                 |
;+---------------------------------------------------------------------------+
;
;  REGISTER AND MEMORY CONTRACT
;  ----------------------------
;  IX and IY are untouched.  AF/BC/DE/HL are scratch.  Static state is
;  non-reentrant.  Input, output, this state, parser work and the hardware
;  stack are disjoint fixture regions.  The parenthesis check occurs before
;  the OPEN token is consumed, so its failure index is the OPEN index.
;=============================================================================

; Token ordinals are also the terminal symbols used by the table candidate.
EOF     EQU 0
OPEN    EQU 1
CLOSE   EQU 2
ATOM    EQU 3
IFTOK   EQU 4
BEGIN   EQU 5
LAMBDA  EQU 6
NAME    EQU 7

CSTART:
ADRESET:
        LD HL,(ADBASE)          ; Start at the fixture's first token byte.
        LD (ADPTR),HL           ; ADPTR advances only after ADTAKE succeeds.
        XOR A
        LD (ADHAVE),A           ; No current token is cached after reset.
        LD (ADCUR),A            ; Zero is a real EOF only when ADHAVE is set.
        LD (ADDEPTH),A          ; The common OPEN/CLOSE depth starts empty.
        LD (ADIDX),A            ; Clear the low index byte before its high byte.
        LD (ADIDX+1),A
        LD (ADFETCH),A           ; Real non-EOF fetch counter.
        LD (ADFETCH+1),A
        LD (ADLOOK),A            ; Lookahead fills, including the one EOF fill.
        LD (ADLOOK+1),A
        LD (ADCONS),A            ; Successfully consumed non-EOF tokens.
        LD (ADCONS+1),A
        LD (ADTOKIX),A           ; Current token index is reset for diagnostics.
        LD (ADTOKIX+1),A
        XOR A
        RET

; Fetch once when the parser has no current lookahead.  ADIDX is the next
; non-EOF token index; ADTOKIX remains stable while an action observes it.
ADPEEK:
        LD A,(ADHAVE)
        OR A
        JR Z,ADFILL                ; Empty cache needs one native fill.
        LD A,(ADCUR)
        OR A                       ; Return the cached token, not the cache flag.
        RET
ADFILL:
        LD HL,(ADPTR)
        LD DE,(ADLIM)
        OR A
        SBC HL,DE                 ; Equality means the exclusive input end.
        JR Z,ADMAKEOF
        LD HL,(ADPTR)
        LD A,(HL)                 ; Native input read; the host never supplies A.
        OR A
        JR NZ,ADREAL              ; Zero is reserved for synthesized EOF here.
        LD A,255                  ; Embedded zero is an ordinary syntax error.
ADREAL: LD (ADCUR),A              ; Preserve even an unknown ordinal for the parser.
        LD HL,(ADIDX)
        LD (ADTOKIX),HL           ; Every current token carries its source index.
        LD HL,(ADLOOK)
        INC HL
        LD (ADLOOK),HL            ; Count this one native lookahead fill.
        LD HL,(ADFETCH)
        INC HL
        LD (ADFETCH),HL           ; Exactly one count for this non-EOF byte.
        LD A,1
        LD (ADHAVE),A
        LD A,(ADCUR)
        OR A                       ; Return a successful token with carry clear.
        RET

; EOF is available at exactly the input extent and is never read from memory.
ADMAKEOF:
        LD HL,(ADIDX)
        LD (ADTOKIX),HL
        LD HL,(ADLOOK)
        INC HL
        LD (ADLOOK),HL            ; The EOF lookahead is itself observable.
        XOR A
        LD (ADCUR),A
        INC A
        LD (ADHAVE),A
        XOR A                      ; EOF is a successful adapter result.
        RET

; Consume the cached token after the parser has checked its grammar role.
ADTAKE:
        LD A,(ADCUR)
        CP OPEN
        JR NZ,ADNOTOP
        LD A,(ADDEPTH)
        CP 32
        JR C,ADOPENOK
        LD A,129                   ; Bound check precedes the input write/cursor.
        SCF
        RET
ADOPENOK:
        INC A
        LD (ADDEPTH),A
        JR ADTAKEM
ADNOTOP:
        CP CLOSE
        JR NZ,ADTAKEM
        LD A,(ADDEPTH)
        DEC A                      ; Grammar guarantees a matching open here.
        LD (ADDEPTH),A
ADTAKEM:
        LD HL,(ADPTR)
        INC HL
        LD (ADPTR),HL             ; One monotonic input byte is now consumed.
        LD HL,(ADIDX)
        INC HL
        LD (ADIDX),HL             ; The next byte gets the next token index.
        LD HL,(ADCONS)
        INC HL
        LD (ADCONS),HL
        XOR A
        LD (ADHAVE),A             ; Force a fresh fill on the next peek.
        LD A,(ADCUR)
        OR A
        RET

; Append an action only after both injection and the three-byte capacity check.
SKACT:
        LD B,A                    ; Keep the ordinal while checking the sink.
        LD A,(SKINJ)
        OR A
        JR NZ,SKINJECT
        LD A,(SKDISC)
        OR A
        JR NZ,SKOBSERV            ; Count the observation without output storage.
        JR SKSPACE
SKINJECT:
        LD A,130                  ; Deliberate sink failure is distinct.
        SCF
        RET
SKSPACE:
        LD HL,(SKPTR)
        LD DE,3
        ADD HL,DE                 ; HL is the exclusive end of the next record.
        JR C,SKFULL               ; A wrapped end cannot fit any output extent.
        LD DE,(SKLIM)
        OR A
        SBC HL,DE
        JR C,SKWRITE              ; A strictly smaller end still fits.
        JR Z,SKWRITE              ; Exact output exhaustion is accepted.
SKFULL: LD A,129
        SCF
        RET
SKWRITE:
        LD HL,(SKPTR)
        LD A,B
        LD (HL),A                 ; First byte is the fixed action ordinal.
        INC HL
        LD A,(ADTOKIX)
        LD (HL),A                 ; Low source token index follows the ordinal.
        INC HL
        LD A,(ADTOKIX+1)
        LD (HL),A                 ; High source token index completes the record.
        INC HL
        LD (SKPTR),HL
        LD HL,(SKUSED)
        LD DE,3
        ADD HL,DE
        LD (SKUSED),HL
        XOR A
        RET
SKOBSERV:
        LD HL,(SKUSED)
        LD DE,3
        ADD HL,DE
        LD (SKUSED),HL
        XOR A
        RET

; Candidate parsers call this small reset entry through their own PPARSE.
SKRESET:
        LD HL,(SKBASE)
        LD (SKPTR),HL
        XOR A
        LD (SKUSED),A
        LD (SKUSED+1),A
        XOR A
        RET

; Fixture configuration and counters.  ADWORK owns adapter state; SKWORK owns
; output state.  The TypeScript guard permits only these intervals to be native
; write targets, plus the explicitly configured input, output and hardware stack.
CCODEEND:
ADGUARD: DS 4
ADWORK:
ADPTR:  DW 0                     ; Next unread fixture byte.
ADBASE: DW 0                     ; Inclusive input base configured by the harness.
ADLIM:  DW 0                     ; Exclusive input end; no read reaches this byte.
ADIDX:  DW 0                     ; Number of non-EOF bytes already consumed.
ADTOKIX: DW 0                    ; Index associated with ADCUR for sink records.
ADFETCH: DW 0                    ; Native non-EOF lookahead fills.
ADLOOK: DW 0                     ; All fills, including synthesized EOF.
ADCONS: DW 0                     ; Non-EOF tokens passed through ADTAKE.
ADHAVE: DB 0                     ; One means ADCUR is the current lookahead.
ADCUR:  DB 0                     ; Token ordinal; 255 marks embedded zero.
ADDEPTH: DB 0                    ; Open-parenthesis count, bounded at 32.
ADWEND:
ADTAIL: DS 4

SKGUARD: DS 4
SKWORK:
SKPTR:  DW 0                     ; Next output record address.
SKBASE: DW 0                     ; Inclusive output base configured by harness.
SKLIM:  DW 0                     ; Exclusive output limit.
SKUSED: DW 0                     ; Bytes committed to successful records.
SKINJ:  DB 0                     ; Nonzero injects one deterministic sink error.
SKDISC: DB 0                     ; Nonzero observes actions without trace writes.
SKWEND:
SKTAIL: DS 4
CEND:
