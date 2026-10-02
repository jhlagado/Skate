; Managed value tracing, closure maps and capture scanning.
; Entry points: SRTBMARK, SRTMVALU, SRTCLENQ and SRTMCLOS.
; Included in runtime order by ../roots.asm.

; Trace a binding cell reached from an active environment or closure.  Its
; explicit mark bit prevents closure/binding cycles from recursing forever.
SRTBMARK:
        LD A,H
        OR L
        RET Z
        LD (SRTBADDR),HL
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        JR C,SRTBFAIL
        LD HL,(SRTBADDR)
        LD DE,SRTCELW
        ADD HL,DE
        JR C,SRTBFAIL              ; A wrapped binding extent is invalid.
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,SRTBOK
        JR Z,SRTBOK
        JR SRTBFAIL
SRTBOK:
        CALL SRTBSTA
        JR Z,SRTBFAIL
        LD HL,(SRTBADDR)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTBFLG),A
        AND 20H
        RET Z
        LD A,(SRTBFLG)
        AND 40H
        JR NZ,SRTBMDON
        LD A,(SRTBFLG)
        OR 40H
        LD (HL),A
        LD A,(SRTBFLG)
        AND 8
        RET Z
        LD HL,(SRTBADDR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        AND 7
        EX DE,HL
        JP SRTMVALU
SRTBMDON:
        RET
SRTBFAIL:
        RET

; Trace a tagged managed value.  Pair validation and closure validation remain
; separate so a binding's full value is never decoded as a pair record.
SRTMVALU:
        CP 1
        JP Z,SRTMARK
        CP 2
        JP Z,SRTCLENQ
        CP 6
        JP Z,SRTSMARK
        CP 7
        JP NZ,SRTMVR
        LD A,H                       ; Pair-stored escape tokens are scalar leaves.
        CP SRTETOH
        JR NC,SRTMVR
        LD A,1
        JP SRTVHOOK
SRTMVR:
        RET

; Return carry clear only for an allocated closure start with a complete
; descriptor and environment extent.  The start bitmap rejects pointers into
; an object's payload or into a binding cell that happens to look similar.
SRTCLVLD:
        LD HL,(SRTCLOBJ)
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        JR C,SRTCLBAD
        LD HL,(SRTCLOBJ)
        LD A,L                     ; Closure starts occupy even map units only.
        AND 3                      ; An address 2 mod 4 names a string-marker bit.
        JR NZ,SRTCLBAD             ; Require four-byte alignment before the map test.
        LD DE,2
        ADD HL,DE
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,SRTCLHDR
        JR Z,SRTCLHDR
        JR SRTCLBAD
SRTCLHDR:
        LD HL,(SRTCLOBJ)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTCLDSC),DE
        LD HL,(SRTCLDSC)
        LD DE,0100H
        OR A
        SBC HL,DE
        JR C,SRTCLBAD
        LD HL,(SRTCLDSC)
        LD DE,SRTCAPOF+SRTMASKB
        ADD HL,DE
        JR C,SRTCLBAD              ; The descriptor extent must fit in 16 bits.
        LD DE,(SRTIMGE)
        OR A
        SBC HL,DE
        JR C,SRTCLDM
        JR Z,SRTCLDM
        JR SRTCLBAD
SRTCLDM:
        LD HL,(SRTCLDSC)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTCLN),A
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,2
        ADD HL,DE
        LD DE,(SRTCLOBJ)
        ADD HL,DE
        JR C,SRTCLBAD              ; A wrapped closure extent is invalid.
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,SRTCLGOD
        JR Z,SRTCLGOD
SRTCLBAD:
        SCF
        RET
SRTCLGOD:
        CALL SRTCLSTA
        JR Z,SRTCLBAD
        OR A
        RET

; Compute the byte index and single-bit mask for an even closure address.
; The address is measured in two-byte units from SRTHEAP.
SRTCLPOS:
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        SRL H
        RR L
        LD A,L
        AND 7
        LD C,A
        SRL H
        RR L
        SRL H
        RR L
        SRL H
        RR L
        LD A,C
        OR A
        JR Z,SRTCLPZ
        LD A,1
SRTCLPS:
        ADD A,A
        DEC C
        RET Z
        JR SRTCLPS
SRTCLPZ:
        LD A,1
        RET

; Test whether SRTCLOBJ is a recorded closure allocation start.
SRTCLSTA:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Test whether SRTCLOBJ has already entered this collection's worklist.
SRTCLSEE:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Set the current collection's closure mark bit.
SRTCLSET:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,(HL)
        OR C
        LD (HL),A
        LD A,1
        LD (SRTMNEW),A             ; Fallback passes must revisit new closures.
        RET

; Publish a newly allocated closure start for later exact validation.
SRTCLNEW:
        LD HL,(SRTOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Clear all closure marks at the beginning of a collection.
SRTCLCLR:
        LD HL,SRTCLMK
        LD BC,0900H
SRTCLCLP:
        LD A,(HL)
        AND 0AAH                   ; Preserve odd vector-type marker bits.
        LD (HL),A
        INC HL
        DEC BC
        LD A,B
        OR C
        JR NZ,SRTCLCLP
        XOR A
        LD (SRTCLER),A
        RET

; Queue a validated closure without entering its capture graph recursively.
SRTCLENQ:
        LD (SRTCLOBJ),HL
        CALL SRTCLVLD
        RET C
        CALL SRTCLSEE
        RET NZ
        CALL SRTCLSET
        LD DE,(SRTMSTK)
        LD A,D
        CP 0D4H
        JR NC,SRTCLFUL
        LD HL,(SRTCLOBJ)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (SRTMSTK),DE
        RET
SRTCLFUL:
        LD A,1
        LD (SRTMOVER),A            ; The closure scan will trace this marked object.
        LD (SRTCLER),A             ; Retain the diagnostic overflow indication.
        RET

; Trace one queued closure through the descriptor capture mask.  Every
; capture is only read after the descriptor has bounded the declared slots.
SRTMCLOS:
        CALL SRTCLVLD
        RET C
        LD HL,(SRTCLDSC)
        LD DE,SRTCAPOF
        ADD HL,DE
        LD (SRTCLMP),HL
        XOR A
        LD (SRTCLSLT),A
        LD B,SRTMASKB
SRTCLMSK:
        LD HL,(SRTCLMP)
        LD A,(HL)
        INC HL
        LD (SRTCLMP),HL
        LD (SRTCLMV),A
        LD C,8
SRTCLBIT:
        LD A,(SRTCLMV)
        AND 1
        JR Z,SRTCLNX
        LD A,(SRTCLN)
        LD E,A
        LD A,(SRTCLSLT)
        CP E
        JR NC,SRTCLNX
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,2
        ADD HL,DE
        LD DE,(SRTCLOBJ)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (SRTCLPTR),HL
        PUSH BC
        LD HL,(SRTCLMP)
        PUSH HL
        LD HL,(SRTCLOBJ)
        PUSH HL
        LD HL,(SRTCLDSC)
        PUSH HL
        LD A,(SRTCLN)
        PUSH AF
        LD A,(SRTCLSLT)
        PUSH AF
        LD A,(SRTCLMV)
        PUSH AF
        LD HL,(SRTCLPTR)
        CALL SRTBMARK
        POP AF
        LD (SRTCLMV),A
        POP AF
        LD (SRTCLSLT),A
        POP AF
        LD (SRTCLN),A
        POP HL
        LD (SRTCLDSC),HL
        POP HL
        LD (SRTCLOBJ),HL
        POP HL
        LD (SRTCLMP),HL
        POP BC
SRTCLNX:
        LD A,(SRTCLMV)
        SRL A
        LD (SRTCLMV),A
        LD A,(SRTCLSLT)
        INC A
        LD (SRTCLSLT),A
        DEC C
        JR NZ,SRTCLBIT
        DJNZ SRTCLMSK
        RET

; Trace every marked closure after a bounded queue overflow.  The start and
; mark maps make this a finite pass over the two-byte address units in the
; closure extent.  Repeating the pass reaches captures discovered later in
; the scan without recursing through the native stack.
SRTCLSCR:
        LD HL,(SRTHEAPP)           ; Scan only the configured managed address span.
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        SRL H
        RR L
        LD B,H                     ; Each visit tests one even closure address.
        LD C,L
        LD HL,SRTHEAP
        LD (SRTCLSCN),HL
SRTCSLP:
        LD HL,(SRTCLSCN)
        LD (SRTCLOBJ),HL
        PUSH BC
        CALL SRTCLSTA
        JR Z,SRTCPOP
        CALL SRTCLSEE
        JR Z,SRTCPOP
        CALL SRTSSTA
        JR NZ,SRTCPOP
        LD HL,(SRTCLOBJ)           ; Restore the scanned object after string classification.
        XOR A
        CALL SRTVHOOK
SRTCPOP:
        POP BC
        LD HL,(SRTCLSCN)
        INC HL
        INC HL
        LD (SRTCLSCN),HL
        DEC BC
        LD A,B
        OR C
        JP NZ,SRTCSLP
        RET
