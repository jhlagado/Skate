; Managed value tracing, closure maps and capture scanning.
; Entry points: GC_VAR, GC_VALUE, GC_QUEUE and GC_CAPS.
; Included in runtime order by ../roots.asm.

; Trace a binding cell reached from an active environment or closure.  Its
; explicit mark bit prevents closure/binding cycles from recursing forever.
GC_VAR:
        LD A,H
        OR L
        RET Z
        LD (BND_CELL),HL
        LD DE,(PAGE_ORG)
        OR A
        SBC HL,DE
        JR C,.BAD
        LD HL,(BND_CELL)
        LD DE,CELL_SZ
        ADD HL,DE
        JR C,.BAD                  ; A wrapped binding extent is invalid.
        LD DE,(HEAP_LIM)
        OR A
        SBC HL,DE
        JR C,.IN_HEAP
        JR Z,.IN_HEAP
        JR .BAD
.IN_HEAP:
        CALL GC_ISVAR
        JR Z,.BAD
        LD HL,(BND_CELL)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (BND_FLAG),A
        AND BND_USED
        RET Z
        LD A,(BND_FLAG)
        AND BND_MARK
        JR NZ,.MARKED
        LD A,(BND_FLAG)
        OR BND_MARK
        LD (HL),A
        LD A,(BND_FLAG)
        AND BND_INIT
        RET Z
        LD HL,(BND_CELL)
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
        LD HL,(CL_OBJ)
        LD DE,(PAGE_ORG)
        OR A
        SBC HL,DE
        JR C,.BAD
        LD HL,(CL_OBJ)
        LD A,L                     ; Closure starts occupy even map units only.
        AND 3                      ; An address 2 mod 4 names a string-marker bit.
        JR NZ,.BAD                 ; Require four-byte alignment before the map test.
        LD DE,2
        ADD HL,DE
        LD DE,(HEAP_LIM)
        OR A
        SBC HL,DE
        JR C,.HEADER
        JR Z,.HEADER
        JR .BAD
.HEADER:
        LD HL,(CL_OBJ)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (CL_DESC),DE
        LD HL,(CL_DESC)
        LD DE,0100H
        OR A
        SBC HL,DE
        JR C,.BAD
        LD HL,(CL_DESC)
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
        LD DE,(RT_LIMIT)
        OR A
        SBC HL,DE
        JR C,.EXTENT
        JR Z,.EXTENT
        JR .BAD
.EXTENT:
        LD HL,(CL_DESC)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (CL_COUNT),A
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,2
        ADD HL,DE
        LD DE,(CL_OBJ)
        ADD HL,DE
        JR C,.BAD                  ; A wrapped closure extent is invalid.
        LD DE,(HEAP_LIM)
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
; The address is measured in two-byte units from PAGE_ORG.
GC_OBJAT:
        LD DE,(PAGE_ORG)
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

; Test whether CL_OBJ is a recorded closure allocation start.
GC_ISOBJ:
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,(CL_MAP)
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Test whether CL_OBJ has already entered this collection's worklist.
GC_SEEN:
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,(GC_MARKS)
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Set the current collection's closure mark bit.
GC_VISIT:
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,(GC_MARKS)
        ADD HL,DE
        LD A,(HL)
        OR C
        LD (HL),A
        LD A,1
        LD (GC_FOUND),A            ; Fallback passes must revisit new closures.
        RET

; Publish a newly allocated closure start for later exact validation.
GC_OBJON:
        LD HL,(FRM_CLOS)
        CALL GC_OBJAT
        LD C,A
        LD DE,(CL_MAP)
        ADD HL,DE
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Clear all closure marks at the beginning of a collection.
GC_RESET:
        LD HL,(GC_MARKS)
        LD BC,(MAP_LEN)
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
        LD (CL_FULL),A
        RET

; Queue a validated closure without entering its capture graph recursively.
GC_QUEUE:
        LD (CL_OBJ),HL
        CALL GC_OBJOK
        RET C
        CALL GC_SEEN
        RET NZ
        CALL GC_VISIT
        LD DE,(GC_QTOP)
        LD A,D
        CP RT_GCHI/256
        JR NC,.FULL
        LD HL,(CL_OBJ)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (GC_QTOP),DE
        RET
.FULL:
        LD A,1
        LD (GC_OVER),A             ; The closure scan will trace this marked object.
        LD (CL_FULL),A             ; Retain the diagnostic overflow indication.
        RET

; Trace one queued closure through the descriptor capture mask.  Every
; capture is only read after the descriptor has bounded the declared slots.
GC_CAPS:
        CALL GC_OBJOK
        RET C
        LD HL,(CL_DESC)
        CALL DESC_CAP
        LD (CL_MASKP),HL
        OR A
        RET Z                      ; Nothing is captured.
        LD B,A
        XOR A
        LD (CL_SLOT),A
.BYTE:
        LD HL,(CL_MASKP)
        LD A,(HL)
        INC HL
        LD (CL_MASKP),HL
        LD (CL_MASK),A
        LD C,8
.BIT:
        LD A,(CL_MASK)
        AND 1
        JR Z,.NEXT
        LD A,(CL_COUNT)
        LD E,A
        LD A,(CL_SLOT)
        CP E
        JR NC,.NEXT
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,2
        ADD HL,DE
        LD DE,(CL_OBJ)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (GC_BIND),HL
        PUSH BC
        LD HL,(CL_MASKP)
        PUSH HL
        LD HL,(CL_OBJ)
        PUSH HL
        LD HL,(CL_DESC)
        PUSH HL
        LD A,(CL_COUNT)
        PUSH AF
        LD A,(CL_SLOT)
        PUSH AF
        LD A,(CL_MASK)
        PUSH AF
        LD HL,(GC_BIND)
        CALL GC_VAR
        POP AF
        LD (CL_MASK),A
        POP AF
        LD (CL_SLOT),A
        POP AF
        LD (CL_COUNT),A
        POP HL
        LD (CL_DESC),HL
        POP HL
        LD (CL_OBJ),HL
        POP HL
        LD (CL_MASKP),HL
        POP BC
.NEXT:
        LD A,(CL_MASK)
        SRL A
        LD (CL_MASK),A
        LD A,(CL_SLOT)
        INC A
        LD (CL_SLOT),A
        DEC C
        JR NZ,.BIT
        DJNZ .BYTE
        RET

; Trace every marked closure after a bounded queue overflow.  The start and
; mark maps make this a finite pass over the two-byte address units in the
; closure extent.  Repeating the pass reaches captures discovered later in
; the scan without recursing through the native stack.
GC_OBJS:
        LD HL,(HEAP_LIM)           ; Scan only the configured managed address span.
        LD DE,(PAGE_ORG)
        OR A
        SBC HL,DE
        SRL H
        RR L
        LD B,H                     ; Each visit tests one even closure address.
        LD C,L
        LD HL,(PAGE_ORG)
        LD (CL_SCANP),HL
.LOOP:
        LD HL,(CL_SCANP)
        LD (CL_OBJ),HL
        PUSH BC
        CALL GC_ISOBJ
        JR Z,.NEXT
        CALL GC_SEEN
        JR Z,.NEXT
        CALL STR_TEST
        JR NZ,.NEXT
        LD HL,(CL_OBJ)             ; Restore the scanned object after string classification.
        XOR A
        CALL VEC_HOOK
.NEXT:
        POP BC
        LD HL,(CL_SCANP)
        INC HL
        INC HL
        LD (CL_SCANP),HL
        DEC BC
        LD A,B
        OR C
        JP NZ,.LOOP
        RET
