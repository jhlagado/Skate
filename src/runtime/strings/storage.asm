; Managed string allocation, leaf marking and address validation.
; STR_NEW may collect; source values must remain rooted by its caller.
; STR_CHK checks an address after the caller selects the managed-string tag.

; Allocate one rounded class block and publish its start and string marker.
; Carry set means the managed pool could not satisfy the request after GC.
STR_NEW:
        CALL .SIZE
        CALL SLAB_NEW
        JR NC,.GOT
        CALL GC
        CALL .SIZE              ; Collection may reuse the sizing scratch.
        CALL SLAB_NEW
        RET C
.GOT:
        LD (STR_DST),HL
        LD (FRM_CLOS),HL
        CALL GC_OBJON               ; Record the exact block start for validation.
        CALL STR_SETM             ; Set the adjacent string marker bit.
        LD HL,(STR_DST)
        LD A,6
        OR A
        RET
; Calculate the rounded closure class for a length-prefixed string.
.SIZE:
        LD A,(STR_LEN)
        INC A
        JR NZ,.SMALL              ; Lengths below 255 fit in one byte here.
        LD HL,0100H                 ; 255 data bytes plus the length byte fit one page.
        JR .CLASS
.SMALL:
        LD L,A
        LD H,0
        LD DE,3
        ADD HL,DE
        LD A,L
        AND 0FCH
        LD L,A
.CLASS:
        LD (CL_SIZE),HL
        SRL H
        RR L
        SRL H
        RR L
        DEC L
        LD A,L
        LD (CL_CLASS),A
        RET

; Mark a managed string as a live leaf during collection.
STR_MARK:
        LD (CL_OBJ),HL
        CALL STR_CHK
        RET C
        CALL GC_SEEN
        RET NZ
        CALL GC_VISIT
        RET

; Test the string marker adjacent to an exact closure allocation start.
; Z means the object is not a managed string.
STR_TEST:
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,CL_MAP
        ADD HL,DE
        LD A,(HL)
        AND C
        RET Z
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        AND C
        RET

; Set the string marker for the object in FRM_CLOS.
STR_SETM:
        LD HL,(FRM_CLOS)
        LD (CL_OBJ),HL
        CALL GC_OBJAT
        LD C,A
        LD DE,CL_MAP
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Clear the string marker before a dead block returns to a closure free list.
STR_CLRM:
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,CL_MAP
        ADD HL,DE
        LD A,C
        ADD A,A
        LD C,A
        LD A,C
        CPL
        LD B,A
        LD A,(HL)
        AND B
        LD (HL),A
        RET

; Validate a managed string's start, class extent and length byte.
STR_CHK:
        LD (CL_OBJ),HL
        LD DE,RT_HEAP
        OR A
        SBC HL,DE
        JP C,.BAD
        LD HL,(CL_OBJ)
        LD A,L
        AND 3
        JP NZ,.BAD
        LD DE,(HEAP_LIM)
        OR A
        SBC HL,DE
        JP NC,.BAD
        CALL STR_TEST
        JP Z,.BAD
        LD HL,(CL_OBJ)
        LD (CL_BASE),HL
        CALL SLAB_AT
        LD A,(CL_PAGE)
        CP 80H
        JP NC,.BAD
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,(HL)
        CP 1
        JP C,.BAD
        CP 41H
        JP NC,.BAD               ; Strings use only the one-page classes.
        DEC A
        LD (CL_CLASS),A
        CALL SLAB_GET
        LD HL,(CL_OBJ)
        LD DE,(CL_PBASE)
        OR A
        SBC HL,DE
        JP C,.BAD
        LD A,H
        OR A
        JP NZ,.BAD
        LD A,L
        LD (STR_OFF),A
        LD A,(CL_CLASS)
        INC A
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD (CL_SIZE),HL
        LD A,(STR_OFF)
        LD E,A
        LD D,0
        ADD HL,DE
        LD A,H
        OR A
        JP Z,.FITS
        CP 1
        JP NZ,.BAD
        LD A,L
        OR A
        JP NZ,.BAD
.FITS:
        LD HL,(CL_OBJ)
        LD A,(HL)
        LD L,A
        LD H,0
        INC HL
        LD DE,(CL_SIZE)
        OR A
        SBC HL,DE
        JP C,.GOOD
        JP Z,.GOOD
.BAD:
        SCF
        RET
.GOOD:
        LD HL,(CL_OBJ)
        OR A
        RET
