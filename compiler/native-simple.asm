;=============================================================================
;  N8 native code-slot recognizer and service retargeting
;=============================================================================
;
;  This part is separate from the evaluator because ATOM keeps each native
;  source part within a 16-bit source-offset range.  It recognizes only the
;  bounded flat forms that fit the first generated-code slot.
;=============================================================================

; Recognize one flat arithmetic expression in the event spool.  The helper
; deliberately accepts only literal numeric operands and one closing list;
; nested calls and longer forms keep the conservative classifier stub.
N8SIMPLE:
        LD HL,(N6SPLEN)
        LD DE,24
        OR A
        SBC HL,DE
        JR Z,N8SBIN
        LD HL,(N6SPLEN)
        LD DE,20
        OR A
        SBC HL,DE
        JR Z,N8SUN
        JP N8SFAIL
N8SBIN:
        LD HL,N6SPOOLB
        LD A,(HL)
        CP 1
        JP NZ,N8SFAIL
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        CP 5
        JP NZ,N8SFAIL
        INC HL
        LD A,(HL)
        CP 1
        JP C,N8SFAIL
        CP 5
        JP NC,N8SFAIL
        DEC A
        ADD A,7
        LD (N8GSVC),A
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        CP 7
        JP NZ,N8SFAIL
        INC HL
        LD A,(HL)
        CALL N8GNUM
        JP C,N8SFAIL
        LD (N8G1TAG),A
        INC HL
        LD A,(HL)
        LD (N8G1VAL),A
        INC HL
        LD A,(HL)
        LD (N8G1VAL+1),A
        INC HL
        LD A,(HL)
        CP 7
        JP NZ,N8SFAIL
        INC HL
        LD A,(HL)
        CALL N8GNUM
        JP C,N8SFAIL
        LD (N8G2TAG),A
        INC HL
        LD A,(HL)
        LD (N8G2VAL),A
        INC HL
        LD A,(HL)
        LD (N8G2VAL+1),A
        INC HL
        LD A,(HL)
        CP 2
        JP NZ,N8SFAIL
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        OR A
        JP NZ,N8SFAIL
        LD A,2
        LD (N8GARGC),A
        XOR A
        RET
N8SUN:
        LD HL,N6SPOOLB
        LD A,(HL)
        CP 1
        JP NZ,N8SFAIL
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        CP 5
        JP NZ,N8SFAIL
        INC HL
        LD A,(HL)
        CP 2
        JP NZ,N8SFAIL
        LD A,11
        LD (N8GSVC),A
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        CP 7
        JP NZ,N8SFAIL
        INC HL
        LD A,(HL)
        CALL N8GNUM
        JP C,N8SFAIL
        LD (N8G1TAG),A
        INC HL
        LD A,(HL)
        LD (N8G1VAL),A
        INC HL
        LD A,(HL)
        LD (N8G1VAL+1),A
        INC HL
        LD A,(HL)
        CP 2
        JP NZ,N8SFAIL
        INC HL
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        OR A
        JP NZ,N8SFAIL
        LD A,1
        LD (N8GARGC),A
        XOR A
        RET
N8GNUM:
        CP 0
        RET Z
        CP 3
        JR Z,N8GNUMOK
        SCF
        RET
N8GNUMOK:
        OR A
        RET
N8SFAIL:
        SCF
        RET

; Recognize the first target pair shape.  N8SERIAL emits two tagged values
; followed by one pair action for a single `(cons value value)` result.  The
; native emitter keeps this gate deliberately narrow until the target recipe
; interpreter owns nested literals and longer pair graphs.
N8PAIR:
        LD HL,(N8OUTLEN)
        LD DE,7
        OR A
        SBC HL,DE
        JP NZ,N8SFAIL
        LD HL,N8RECBUF
        LD A,(HL)
        CP $83
        JP NZ,N8SFAIL
        INC HL
        LD A,(HL)
        LD (N8G1VAL),A
        INC HL
        LD A,(HL)
        LD (N8G1VAL+1),A
        INC HL
        LD A,(HL)
        CP $83
        JP NZ,N8SFAIL
        INC HL
        LD A,(HL)
        LD (N8G2VAL),A
        INC HL
        LD A,(HL)
        LD (N8G2VAL+1),A
        INC HL
        LD A,(HL)
        OR A
        JP NZ,N8SFAIL
        LD A,3
        LD (N8G1TAG),A
        LD (N8G2TAG),A
        XOR A
        RET

; Select the bounded lowerer after N6 has finished with its event spool.
; N8RECBUF overlays that spool, so pair results must be recognized from the
; serialized recipe before the ordinary numeric scanner is allowed to read
; the shared address.  A failed pair recognition falls through to the
; conservative reference/number stub in N8CFALL.  Pair and fallback paths
; discard N8CODE's continuation before tail-jumping to N8CLEN, whose return
; therefore goes directly back to the publication caller.
N8LOWER:
        CALL N8GEN
        JP NC,N8LGEND
        CALL N8GCLR
        LD A,(N4RTAG)
        CP 1
        JR NZ,N8DNUM
        CALL N8PAIR
        JR C,N8LFALL
        POP HL
        JP N8CPAIR
N8LFALL:
        POP HL
        JP N8CFALL
N8DNUM:
        CALL N8SIMPLE
        RET NC
        POP HL
        JP N8CFALL
N8LGEND:
        POP HL
        ; N8GBYTE keeps the next free address rather than the last byte
        ; written.  N8CLEN measures from the final byte, so back up once
        ; before handing it the generated body's end pointer.
        LD HL,(N8GOUT)
        DEC HL
        JP N8CLEN

; Discard a failed nested-generation attempt before the established lowerers
; write their own shape.  The length is still measured only by the successful
; lowerer, but stale bytes must not leak into its bounded image.
N8GCLR:
        LD DE,N8CODOF
        CALL N8OBJADR
        LD B,N8COLEN
        XOR A
N8GCLP:
        LD (HL),A
        INC HL
        DJNZ N8GCLP
        RET

; Lower a nested arithmetic expression into executable ABI-2 code.  This is
; deliberately a small, independent slice: numeric literals and the four
; arithmetic operators are supported, nested operands are evaluated in source
; order, and the generated calls are recorded for NOBJ relocation emission.
; Flat forms continue through N8SIMPLE so their established byte contract is
; unchanged.  The routine uses its own bounded parser cursor; it never reads
; the compiler's final value as a substitute for running the expression.
N8GEN:
        LD HL,N6SPOOLB
        LD (N8GPTR),HL
        LD HL,(N6SPLEN)
        LD DE,N6SPOOLB
        ADD HL,DE
        JP C,N8GFAIL
        LD (N8GEND),HL
        LD DE,N8CODOF
        CALL N8OBJADR
        LD (N8GOUT),HL
        LD DE,N8COLEN
        ADD HL,DE
        JP C,N8GFAIL
        LD (N8GLIM),HL
        LD HL,0
        LD (N8GOFF),HL
        XOR A
        LD (N8GDEP),A
        LD (N8GNEST),A
        LD (N8GOPDEP),A
        LD (N8GCALLN),A
        CALL N8GEXPR
        JP C,N8GFAIL
        ; N6 terminates every complete spool with a zero-kind sentinel.  It
        ; is outside the expression but still belongs to the bounded stream,
        ; so consume it before proving that the cursor reached the end.
        CALL N8GPEEK
        JP C,N8GFAIL
        OR A
        JP NZ,N8GFAIL
        CALL N8GADV
        JP C,N8GFAIL
        LD HL,(N8GPTR)
        LD DE,(N8GEND)
        OR A
        SBC HL,DE
        JP NZ,N8GFAIL
        LD A,(N8GNEST)
        OR A
        JP Z,N8GFAIL
        LD A,$C9
        CALL N8GBYTE
        JP C,N8GFAIL
        ; The generated body owns its dynamic service calls, but the fixed
        ; launch image still carries the ordinary 198-byte provider hook.
        ; Reset that site on every compilation so a prior flat binary shape
        ; cannot leave its 203-byte call offset in a reused object arena.
        CALL N8CSVC
        LD A,3
        LD (N8CMODE),A
        XOR A
        RET

; Parse one numeric expression and append its machine-code value producer.
N8GEXPR:
        CALL N8GPEEK
        RET C
        CP 7
        JP Z,N8GNUME
        CP 8
        JP Z,N8GNUME
        CP 1
        JP Z,N8GOPEN
        SCF
        RET
N8GNUME:
        LD HL,(N8GPTR)
        INC HL
        LD A,(HL)
        LD (N8GTAG),A
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (N8GPAY),DE
        INC HL
        LD (N8GPTR),HL
        LD A,$3E
        CALL N8GBYTE
        RET C
        LD A,(N8GTAG)
        CALL N8GBYTE
        RET C
        LD A,$21
        CALL N8GBYTE
        RET C
        LD HL,(N8GPAY)
        LD A,L
        CALL N8GBYTE
        RET C
        LD A,H
        JP N8GBYTE

; Parse an application.  The head must be an arithmetic operator; each later
; operand is evaluated after the previous result is saved on the generated
; machine stack, then the selected numeric service combines the two values.
N8GOPEN:
        LD A,(N8GDEP)
        OR A
        JP Z,N8GTOP
        LD A,1
        LD (N8GNEST),A
N8GTOP:
        LD A,(N8GDEP)
        INC A
        CP 9
        JP NC,N8GFAIL
        LD (N8GDEP),A
        CALL N8GADV
        RET C
        CALL N8GHEAD
        RET C
        CALL N8GEXPR
        RET C
N8GARGS:
        CALL N8GPEEK
        RET C
        CP 2
        JP Z,N8GONE
        LD A,(N8GOP)
        CP 1
        JP C,N8GFAIL
        CP 5
        JP NC,N8GFAIL
        CALL N8GOPUSH
        RET C
        ; Save the left ABI-2 value in the generated program's native stack.
        LD A,$F5
        CALL N8GBYTE
        JP C,N8GPERR
        LD A,$E5
        CALL N8GBYTE
        JP C,N8GPERR
        CALL N8GEXPR
        JP C,N8GPERR
        CALL N8GPOP
        JP C,N8GFAIL
        LD (N8GOP),A
        ; Move the right value to B:DE and restore the left A:HL value.
        LD A,$47
        CALL N8GBYTE
        JP C,N8GFAIL
        LD A,$54
        CALL N8GBYTE
        JP C,N8GFAIL
        LD A,$5D
        CALL N8GBYTE
        JP C,N8GFAIL
        LD A,$E1
        CALL N8GBYTE
        JP C,N8GFAIL
        LD A,$F1
        CALL N8GBYTE
        JP C,N8GFAIL
        LD A,(N8GOP)
        CALL N8GMAP
        JP C,N8GFAIL
        CALL N8GCALL
        JR C,N8GFAIL
        ; A binary application is complete when its next record is the
        ; closing marker.  The first-operand close path above is reserved for
        ; unary minus; after a combine, every binary operator may finish here.
        CALL N8GPEEK
        JP C,N8GFAIL
        CP 2
        JP Z,N8GBEND
        JP N8GARGS
N8GBEND:
        CALL N8GADV
        RET C
        JP N8GENDX
N8GONE:
        CALL N8GADV
        RET C
        LD A,(N8GOP)
        CP 2
        JP NZ,N8GFAIL
        LD A,11
        CALL N8GCALL
        JP C,N8GFAIL
N8GENDX:
        LD A,(N8GDEP)
        DEC A
        LD (N8GDEP),A
        XOR A
        RET
N8GPERR:
        CALL N8GPOP
N8GFAIL:
        SCF
        RET

; Read the operator symbol record and retain its compact N9 code.
N8GHEAD:
        LD HL,(N8GPTR)
        LD A,(HL)
        CP 5
        JP NZ,N8GFAIL
        INC HL
        LD A,(HL)
        LD (N8GOP),A
        INC HL
        INC HL
        INC HL
        LD (N8GPTR),HL
        XOR A
        RET

; Peek the next event kind without consuming it.
N8GPEEK:
        LD HL,(N8GPTR)
        LD DE,(N8GEND)
        OR A
        SBC HL,DE
        RET NC
        LD HL,(N8GPTR)
        LD A,(HL)
        OR A
        RET

; Consume one four-byte event record.
N8GADV:
        LD HL,(N8GPTR)
        LD DE,4
        ADD HL,DE
        JP C,N8GFAIL
        LD (N8GPTR),HL
        XOR A
        RET

; Append one byte while enforcing the fixed generated-code capacity.
N8GBYTE:
        PUSH AF
        LD HL,(N8GOUT)
        PUSH HL
        LD DE,(N8GLIM)
        OR A
        SBC HL,DE
        POP HL
        JP NC,N8GBAD
        POP AF
        LD (HL),A
        INC HL
        LD (N8GOUT),HL
        LD HL,(N8GOFF)
        INC HL
        LD (N8GOFF),HL
        XOR A
        RET
N8GBAD:
        POP AF
        SCF
        RET

; Save and restore the current operator across a recursively parsed operand.
N8GOPUSH:
        LD A,(N8GOPDEP)
        CP 8
        JP NC,N8GFAIL
        LD E,A
        LD D,0
        LD HL,N8GOPST
        ADD HL,DE
        LD A,(N8GOP)
        LD (HL),A
        LD A,(N8GOPDEP)
        INC A
        LD (N8GOPDEP),A
        XOR A
        RET
N8GPOP:
        LD A,(N8GOPDEP)
        OR A
        JP Z,N8GFAIL
        DEC A
        LD (N8GOPDEP),A
        LD E,A
        LD D,0
        LD HL,N8GOPST
        ADD HL,DE
        LD A,(HL)
        OR A
        RET

; Map N9's binary operator code to the corresponding runtime service id.
N8GMAP:
        CP 1
        JP Z,N8GADD
        CP 2
        JP Z,N8GSUB
        CP 3
        JP Z,N8GMUL
        CP 4
        JP Z,N8GDIV
        SCF
        RET
N8GADD:
        LD A,7
        RET
N8GSUB:
        LD A,8
        RET
N8GMUL:
        LD A,9
        RET
N8GDIV:
        LD A,10
        RET

; Record the ABS16 operand immediately after a service CALL, then emit
; CD 00 00.  NOBJ relocations patch the two-byte operand, not the opcode.
N8GCALL:
        PUSH AF
        LD A,(N8GCALLN)
        CP 8
        JR NC,N8GCREJ
        LD E,A
        LD D,0
        LD HL,N8GCTBL
        ADD HL,DE
        ADD HL,DE
        ADD HL,DE
        ADD HL,DE
        LD DE,(N8GOFF)
        INC DE
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        POP AF
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        LD A,(N8GCALLN)
        INC A
        LD (N8GCALLN),A
        LD A,$CD
        CALL N8GBYTE
        RET C
        XOR A
        CALL N8GBYTE
        RET C
        XOR A
        JP N8GBYTE
N8GCREJ:
        POP AF
        SCF
        RET

; Retarget the generated-code relocation to the service selected above.
N8CSVC:
        ; Unary, numeric and reference stubs call at image offset 198.
        ; N8CODE changes this field to 203 for the longer binary shape.
        LD DE,N8RELSI
        CALL N8OBJADR
        LD (HL),198
        INC HL
        XOR A
        LD (HL),A
        LD DE,N8RELTG
        CALL N8OBJADR
        LD A,(N8GSVC)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        RET


; Generated-code recognizer state.
N8GARGC:    DB 0
N8GSVC:     DB 0
N8CMODE:    DB 0
N8G1TAG:    DB 0
N8G1VAL:    DW 0
N8G2TAG:    DB 0
N8G2VAL:    DW 0
N8GPTR:     DW 0
N8GEND:     DW 0
N8GOUT:     DW 0
N8GLIM:     DW 0
N8GOFF:     DW 0
N8GPAY:     DW 0
N8GTAG:     DB 0
N8GOP:      DB 0
N8GDEP:     DB 0
N8GNEST:    DB 0
N8GOPDEP:   DB 0
N8GCALLN:   DB 0
N8GOPST:    DS 8
N8GCTBL:    DS 32

; Measure initialized bytes in the bounded generated-code slot.
N8CLEN:
        INC HL
        LD DE,N4OBJ
        OR A
        SBC HL,DE
        LD DE,N8CODOF
        OR A
        SBC HL,DE
        LD (N8CLENW),HL
        CALL N8CSET
        XOR A
        RET

; Patch the variable executable section and its IMAGE prefix.  The static
; GENCODE slot remains the compiler's staging area; section 5 receives only
; the measured bytes when N8STOBJ publishes the object.
N8CSET:
        LD HL,(N8CLENW)
        PUSH HL
        LD DE,N8CSOFF
        CALL N8OBJADR
        EX DE,HL
        POP HL
        CALL N8PUTW
        LD HL,(N8CLENW)
        LD DE,6
        ADD HL,DE
        PUSH HL
        LD DE,N8CPOFF
        CALL N8OBJADR
        EX DE,HL
        POP HL
        JP N8PUTW
