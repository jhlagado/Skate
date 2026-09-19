;=============================================================================
;  N4 native arithmetic compiler command
;=============================================================================
;
;  SKATE reads one flat arithmetic form from the CP/M command-tail FCB, uses
;  the production reader and numeric ABI, and publishes a committed NOBJ plus
;  a runnable COM image.  The object image is a fixed bounded template: only
;  its result message and commit CRC are changed after the source succeeds.
;
;  PUBLIC ENTRY
;  N4MAIN -- command entry at 0100H.  It returns to the CCP through BDOS 0.
;
;  Supported form: (+|-|*|/) <number> <number>
;  Number values retain the reader's exact integer or binary16 tag.  Binary16
;  results print as F16:hhhh so a target transcript cannot hide a rounding.
;  The service relocation in the emitted object is deliberately unreachable
;  in this direct COM image; the host/target linker still validates it.
;
;  All mutable state is below the template and private tables.  IX, IY and
;  the caller stack contract of the imported modules remain unchanged.
;=============================================================================

N4MAIN:
        LD HL,(6)                 ; CP/M reports the top of the transient area.
        LD DE,8000H               ; Reserve the upper 32K for the native stack.
        OR A
        SBC HL,DE
        JP C,N4MEMERR             ; Refuse to run without the documented guard.
        LD SP,8000H               ; Reader and emitter calls share this stack.
        CALL N4PARSE              ; Read, validate and evaluate the source form.
        JP C,N4FAIL               ; No output is opened before this succeeds.
        CALL N4EMIT               ; Patch and stream NOBJ, then the COM image.
        JP C,N4FAIL               ; A failed output has no complete COMMIT.
        LD DE,N4OKTXT             ; Report a successful staged generation.
        JP N4PRINT

;-------------------------------------------------------------------------
;  Reader-driven expression compiler
;-------------------------------------------------------------------------

N4PARSE:
        LD HL,005CH                ; CCP places the first filename FCB here.
        CALL CSOPEN
        JR NC,N4PSOPEN
        LD A,2
        LD (N4CODE),A
        SCF
        RET
N4PSOPEN:
        LD A,1
        LD (N4OPEN),A
        LD IX,N4SYMCXT
        CALL IINIT
        JP C,N4PREAD
        LD IX,N4STRCXT
        CALL IINIT
        JP C,N4PREAD
        LD HL,CSBYTE
        LD DE,N4SYMCXT
        LD BC,N4STRCXT
        CALL RINIT
        JP C,N4PREAD

        CALL RNEXT                  ; The form must start with an open list.
        JP C,N4PREAD
        CP 1
        JP NZ,N4PSYNT
        CALL RNEXT                  ; Read the operator symbol.
        JP C,N4PREAD
        CP 5
        JP NZ,N4PSYNT
        LD A,(LBUFLEN)
        CP 1
        JP NZ,N4PSYNT
        LD A,(LBUFFER)
        CP '+'
        JR Z,N4OPGOOD
        CP '-'
        JR Z,N4OPGOOD
        CP '*'
        JR Z,N4OPGOOD
        CP '/'
        JP NZ,N4PSYNT
N4OPGOOD:
        LD (N4OP),A

        CALL RNEXT                  ; First operand is an exact numeric value.
        JP C,N4PREAD
        CP 7
        JP NZ,N4PSYNT
        LD A,(RTAG)
        CP 3
        JR Z,N4LEFTOK
        OR A
        JP NZ,N4PSYNT
N4LEFTOK:
        LD (N4LTAG),A
        LD (N4LVAL),HL

        CALL RNEXT                  ; The second operand follows immediately.
        JP C,N4PREAD
        CP 7
        JP NZ,N4PSYNT
        LD A,(RTAG)
        CP 3
        JR Z,N4ROK
        OR A
        JP NZ,N4PSYNT
N4ROK:
        LD (N4RTAG),A
        LD (N4RVAL),HL

        LD A,(N4OP)
        CP '+'
        JR Z,N4DOADD
        CP '-'
        JR Z,N4DOSUB
        CP '*'
        JR Z,N4DOMUL
N4DODIV:
        CALL N4ARGS
        CALL NDIV
        JP N4NUMRET
N4DOADD:
        CALL N4ARGS
        CALL NADD
        JP N4NUMRET
N4DOSUB:
        CALL N4ARGS
        CALL NSUB
        JP N4NUMRET
N4DOMUL:
        CALL N4ARGS
        CALL NMUL
        JP N4NUMRET
N4ARGS:
        LD HL,(N4LVAL)
        LD DE,(N4RVAL)
        LD A,(N4RTAG)
        LD B,A                      ; B carries the right representation tag.
        LD A,(N4LTAG)               ; A carries the left representation tag.
        RET

; Numeric dispatch returns the result tag in A and payload in HL, or carry.
N4NUMRET:
        JR C,N4PNUM
        LD (N4RTAG),A
        LD (N4RVAL),HL
        CALL RNEXT                  ; Close the arithmetic list.
        JP C,N4PREAD
        CP 2
        JP NZ,N4PSYNT
        CALL RNEXT                  ; No second top-level datum is permitted.
        JP C,N4PREAD
        OR A
        JP NZ,N4PSYNT              ; RNEXT kind zero is the only valid EOF.
        CALL CSCLOSE
        JR C,N4PIO
        XOR A
        LD (N4OPEN),A
        RET

N4PNUM:
        LD A,3
        LD (N4CODE),A
        SCF
        RET
N4PREAD:
        LD A,1
        LD (N4CODE),A
        SCF
        RET
N4PSYNT EQU N4PREAD       ; Syntax and reader failures share one terminal path.
N4PIO:
        LD A,2
        LD (N4CODE),A
        SCF
        RET
