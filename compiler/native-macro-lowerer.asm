;=============================================================================
;  Native macro to N6 lowerer handoff
;=============================================================================
;
;  N6SPOOLM consumes the macro expander's RNEXT-compatible event stream and
;  writes the existing four-byte N6 evaluator records.  The macro phase owns
;  syntax and expansion state; the lowerer owns evaluator semantics.  This
;  adapter is deliberately format-free: it translates one event at a time and
;  refuses to consume an event that would exceed the bounded spool.
;
;  CALL
;    The macro cursor must be ready through NMOUTRW.
;
;  SUCCESS
;    A = 0; N6SPOOLB contains the lowerer stream and N6SPLEN its byte length.
;
;  FAILURE
;    Carry set for a macro error or a full N6 spool.
;=============================================================================

; Count the complete expanded event stream before the lowerer writes its first
; record. The macro cursor is reset by the caller after this preflight, so a
; failed package cannot leave a partial evaluator spool or reach publication.
; N6SPLEN is only a temporary count here; N6RESET owns its normal meaning.
N6PLANM:
        CALL NMPLAN
        JR C,N6PLBAD
        XOR A
        LD (N6SPLEN),A
        LD (N6SPLEN+1),A
N6PLP:
        CALL NMNEXT
        RET C
        OR A
        JR Z,N6PLOK
        LD HL,(N6SPLEN)
        INC HL
        LD (N6SPLEN),HL
        LD DE,1024
        OR A
        SBC HL,DE
        JR NC,N6PLBAD
        JR N6PLP
N6PLOK:
        XOR A
        RET
N6PLBAD:
        SCF
        RET

N6SPOOLM:
        LD HL,N6SPOOLB
        LD (N6SPPTR),HL
N6MSPLP:
        LD HL,(N6SPPTR)
        LD DE,N6SPOOLB
        OR A
        SBC HL,DE
        LD DE,4092
        OR A
        SBC HL,DE
        JP NC,N6CAP
        LD HL,(N6SPPTR)
        CALL NMNEXT
        RET C
        LD (N6SPK),A
        EX DE,HL
        LD HL,(N6SPPTR)
        LD (HL),A
        INC HL
        LD A,(N6SPK)
        CP 5
        JR Z,N6MSPSYM
        CP 7
        JR Z,N6MSPVAL
        CP 8
        JR Z,N6MSPVAL
        XOR A
        JR N6MSPTAG
N6MSPSYM:
        PUSH DE
        PUSH HL
        CALL N6SCODE
        POP HL
        POP DE
        JR N6MSPTAG
N6MSPVAL:
        LD A,(RTAG)
N6MSPTAG:
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
        JR Z,N6MSPDN
        JR N6MSPLP
N6MSPDN:
        LD HL,(N6SPPTR)
        LD DE,N6SPOOLB
        OR A
        SBC HL,DE
        LD (N6SPLEN),HL
        XOR A
        RET
