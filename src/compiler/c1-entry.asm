;=============================================================================
;  C1 direct compiler command
;=============================================================================
;
;  The C1 entry owns the first production parser in src/.  It reads one flat
;  arithmetic form from the CP/M FCB, retains only the two operand values and
;  asks the shared ABI-2 numeric services for the result.  N4-prefixed storage
;  and publication routines are preserved contracts from the prototype; C1's
;  parser and command state use the C1-prefixed control labels below.
;=============================================================================

C1MAIN:
        LD HL,(6)                 ; CP/M reports the top of transient memory.
        LD DE,8000H               ; Keep the upper half for the native stack.
        OR A
        SBC HL,DE
        JP C,N4MEMERR             ; Refuse to run without the documented guard.
        LD SP,8000H               ; Reader and emitter calls share this stack.
        CALL C1PARSE              ; Read, validate and evaluate the source form.
        JP C,N4FAIL               ; No output is opened before success.
        CALL N4EMIT               ; Patch and stream NOBJ, then the COM image.
        JP C,N4FAIL               ; Failed output has no complete COMMIT.
        LD DE,N4OKTXT             ; Report a successfully staged generation.
        JP N4PRINT

; Read exactly one (+|-|*|/) expression with two numeric operands.
C1PARSE:
        LD HL,005CH               ; CCP places the source FCB here.
        CALL CSOPEN
        JR NC,C1PSOPEN
        LD A,2
        LD (N4CODE),A
        SCF
        RET
C1PSOPEN:
        LD A,1
        LD (N4OPEN),A
        LD IX,N4SYMCXT
        CALL IINIT
        JP C,C1PREAD
        LD IX,N4STRCXT
        CALL IINIT
        JP C,C1PREAD
        LD HL,CSBYTE
        LD DE,N4SYMCXT
        LD BC,N4STRCXT
        CALL RINIT
        JP C,C1PREAD

        CALL RNEXT                  ; The form must start with an open list.
        JP C,C1PREAD
        CP 1
        JP NZ,C1PSYNT
        CALL RNEXT                  ; Read the operator symbol.
        JP C,C1PREAD
        CP 5
        JP NZ,C1PSYNT
        LD A,(LBUFLEN)
        CP 1
        JP NZ,C1PSYNT
        LD A,(LBUFFER)
        CP '+'
        JR Z,C1OPGOOD
        CP '-'
        JR Z,C1OPGOOD
        CP '*'
        JR Z,C1OPGOOD
        CP '/'
        JP NZ,C1PSYNT
C1OPGOOD:
        LD (N4OP),A

        CALL RNEXT                  ; First operand is a numeric value.
        JP C,C1PREAD
        CP 7
        JP NZ,C1PSYNT
        LD A,(RTAG)
        CP 3
        JR Z,C1LEFTOK
        OR A
        JP NZ,C1PSYNT
C1LEFTOK:
        LD (N4LTAG),A
        LD (N4LVAL),HL

        CALL RNEXT                  ; The second operand follows immediately.
        JP C,C1PREAD
        CP 7
        JP NZ,C1PSYNT
        LD A,(RTAG)
        CP 3
        JR Z,C1ROK
        OR A
        JP NZ,C1PSYNT
C1ROK:
        LD (N4RTAG),A
        LD (N4RVAL),HL

        LD A,(N4OP)
        CP '+'
        JR Z,C1DOADD
        CP '-'
        JR Z,C1DOSUB
        CP '*'
        JR Z,C1DOMUL
C1DODIV:
        CALL C1ARGS
        CALL NDIV
        JP C1NUMRET
C1DOADD:
        CALL C1ARGS
        CALL NADD
        JP C1NUMRET
C1DOSUB:
        CALL C1ARGS
        CALL NSUB
        JP C1NUMRET
C1DOMUL:
        CALL C1ARGS
        CALL NMUL
        JP C1NUMRET
C1ARGS:
        LD HL,(N4LVAL)
        LD DE,(N4RVAL)
        LD A,(N4RTAG)
        LD B,A                      ; B carries the right representation tag.
        LD A,(N4LTAG)               ; A carries the left representation tag.
        RET

; Numeric dispatch validates the literal operands during compilation.  The
; result is deliberately discarded: N4PATCH embeds the operands and the
; generated COM/NOBJ image performs this operation when it runs.
C1NUMRET:
        JR C,C1PNUM
        CALL RNEXT                  ; Close the arithmetic list.
        JP C,C1PREAD
        CP 2
        JP NZ,C1PSYNT
        CALL RNEXT                  ; No second top-level datum is permitted.
        JP C,C1PREAD
        OR A
        JP NZ,C1PSYNT              ; RNEXT kind zero is the only valid EOF.
        CALL CSCLOSE
        JR C,C1PIO
        XOR A
        LD (N4OPEN),A
        RET

C1PNUM:
        LD A,3
        LD (N4CODE),A
        SCF
        RET
C1PREAD:
        LD A,1
        LD (N4CODE),A
        SCF
        RET
C1PSYNT EQU C1PREAD               ; Reader and syntax failures share one path.
C1PIO:
        LD A,2
        LD (N4CODE),A
        SCF
        RET
