; Managed value tracing, closure maps and capture scanning.
; Entry points: GC_VAR, GC_VALUE, GC_QUEUE and GC_CAPS.
; Included in runtime order by ../roots.asm.

; Trace a binding cell reached from an active environment or closure.  Its
; explicit mark bit prevents closure/binding cycles from recursing forever.
GC_VAR:
        LD A,H
        OR L
        RET Z
        LD (SRTBADDR),HL
        LD DE,RT_HEAP
        OR A
        SBC HL,DE
        JR C,.BAD
        LD HL,(SRTBADDR)
        LD DE,CELL_SZ
        ADD HL,DE
        JR C,.BAD                  ; A wrapped binding extent is invalid.
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,.IN_HEAP
        JR Z,.IN_HEAP
        JR .BAD
.IN_HEAP:
        CALL GC_ISVAR
        JR Z,.BAD
        LD HL,(SRTBADDR)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTBFLG),A
        AND BND_USED
        RET Z
        LD A,(SRTBFLG)
        AND BND_MARK
        JR NZ,.MARKED
        LD A,(SRTBFLG)
        OR BND_MARK
        LD (HL),A
        LD A,(SRTBFLG)
        AND BND_INIT
        RET Z
        LD HL,(SRTBADDR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        AND 0FH
        EX DE,HL
        JP GC_VALUE
.MARKED:
        RET
.BAD:
        RET

; Trace a tagged managed value.  Pair validation and closure validation remain
; separate so a binding's full value is never decoded as a pair record.
GC_VALUE:
        CP 1
        JP Z,GC_MARK
        CP 2
        JP Z,GC_QUEUE
        CP 6
        JP Z,STR_MARK
        CP 7
        JP NZ,.LEAF
        LD A,H                       ; Pair-stored escape tokens are scalar leaves.
        CP RT_EPAGE
        JR NC,.LEAF
        LD A,1
        JP VEC_HOOK
.LEAF:
        RET

; Return carry clear only for an allocated closure start with a complete
; descriptor and environment extent.  The start bitmap rejects pointers into
; an object's payload or into a binding cell that happens to look similar.
GC_OBJOK:
        LD HL,(SRTCLOBJ)
        LD DE,RT_HEAP
        OR A
        SBC HL,DE
        JR C,.BAD
        LD HL,(SRTCLOBJ)
        LD A,L                     ; Closure starts occupy even map units only.
        AND 3                      ; An address 2 mod 4 names a string-marker bit.
        JR NZ,.BAD                 ; Require four-byte alignment before the map test.
        LD DE,2
        ADD HL,DE
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,.HEADER
        JR Z,.HEADER
        JR .BAD
.HEADER:
        LD HL,(SRTCLOBJ)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTCLDSC),DE
        LD HL,(SRTCLDSC)
        LD DE,0100H
        OR A
        SBC HL,DE
        JR C,.BAD
        LD HL,(SRTCLDSC)
        LD DE,DESC_MAP
        ADD HL,DE
        JR C,.BAD                  ; The descriptor extent must fit in 16 bits.
        DEC HL
        LD E,(HL)                  ; The mask width.
        INC HL
        LD D,0
        ADD HL,DE
        JR C,.BAD
        ADD HL,DE                  ; The end of both masks.
        JR C,.BAD
        LD DE,(SRTIMGE)
        OR A
        SBC HL,DE
        JR C,.EXTENT
        JR Z,.EXTENT
        JR .BAD
.EXTENT:
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
        JR C,.BAD                  ; A wrapped closure extent is invalid.
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,.GOOD
        JR Z,.GOOD
.BAD:
        SCF
        RET
.GOOD:
        CALL GC_ISOBJ
        JR Z,.BAD
        OR A
        RET

; Compute the byte index and single-bit mask for an even closure address.
; The address is measured in two-byte units from RT_HEAP.
GC_OBJAT:
        LD DE,RT_HEAP
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
        JR Z,.ZERO
        LD A,1
.SHIFT:
        ADD A,A
        DEC C
        RET Z
        JR .SHIFT
.ZERO:
        LD A,1
        RET

; Test whether SRTCLOBJ is a recorded closure allocation start.
GC_ISOBJ:
        LD HL,(SRTCLOBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Test whether SRTCLOBJ has already entered this collection's worklist.
GC_SEEN:
        LD HL,(SRTCLOBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Set the current collection's closure mark bit.
GC_VISIT:
        LD HL,(SRTCLOBJ)
        CALL GC_OBJAT
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
GC_OBJON:
        LD HL,(SRTOBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Clear all closure marks at the beginning of a collection.
GC_RESET:
        LD HL,SRTCLMK
        LD BC,0900H
.LOOP:
        LD A,(HL)
        AND 0AAH                   ; Preserve odd vector-type marker bits.
        LD (HL),A
        INC HL
        DEC BC
        LD A,B
        OR C
        JR NZ,.LOOP
        XOR A
        LD (SRTCLER),A
        RET

; Queue a validated closure without entering its capture graph recursively.
GC_QUEUE:
        LD (SRTCLOBJ),HL
        CALL GC_OBJOK
        RET C
        CALL GC_SEEN
        RET NZ
        CALL GC_VISIT
        LD DE,(SRTMSTK)
        LD A,D
        CP 0D4H
        JR NC,.FULL
        LD HL,(SRTCLOBJ)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (SRTMSTK),DE
        RET
.FULL:
        LD A,1
        LD (SRTMOVER),A            ; The closure scan will trace this marked object.
        LD (SRTCLER),A             ; Retain the diagnostic overflow indication.
        RET

; Trace one queued closure through the descriptor capture mask.  Every
; capture is only read after the descriptor has bounded the declared slots.
GC_CAPS:
        CALL GC_OBJOK
        RET C
        LD HL,(SRTCLDSC)
        CALL DESC_CAP
        LD (SRTCLMP),HL
        OR A
        RET Z                      ; Nothing is captured.
        LD B,A
        XOR A
        LD (SRTCLSLT),A
.BYTE:
        LD HL,(SRTCLMP)
        LD A,(HL)
        INC HL
        LD (SRTCLMP),HL
        LD (SRTCLMV),A
        LD C,8
.BIT:
        LD A,(SRTCLMV)
        AND 1
        JR Z,.NEXT
        LD A,(SRTCLN)
        LD E,A
        LD A,(SRTCLSLT)
        CP E
        JR NC,.NEXT
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
        CALL GC_VAR
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
.NEXT:
        LD A,(SRTCLMV)
        SRL A
        LD (SRTCLMV),A
        LD A,(SRTCLSLT)
        INC A
        LD (SRTCLSLT),A
        DEC C
        JR NZ,.BIT
        DJNZ .BYTE
        RET

; Trace every marked closure after a bounded queue overflow.  The start and
; mark maps make this a finite pass over the two-byte address units in the
; closure extent.  Repeating the pass reaches captures discovered later in
; the scan without recursing through the native stack.
GC_OBJS:
        LD HL,(SRTHEAPP)           ; Scan only the configured managed address span.
        LD DE,RT_HEAP
        OR A
        SBC HL,DE
        SRL H
        RR L
        LD B,H                     ; Each visit tests one even closure address.
        LD C,L
        LD HL,RT_HEAP
        LD (SRTCLSCN),HL
.LOOP:
        LD HL,(SRTCLSCN)
        LD (SRTCLOBJ),HL
        PUSH BC
        CALL GC_ISOBJ
        JR Z,.NEXT
        CALL GC_SEEN
        JR Z,.NEXT
        CALL STR_TEST
        JR NZ,.NEXT
        LD HL,(SRTCLOBJ)           ; Restore the scanned object after string classification.
        XOR A
        CALL VEC_HOOK
.NEXT:
        POP BC
        LD HL,(SRTCLSCN)
        INC HL
        INC HL
        LD (SRTCLSCN),HL
        DEC BC
        LD A,B
        OR C
        JP NZ,.LOOP
        RET
