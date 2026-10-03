; Closure page allocation for the complete runtime pool.
;
; The page manager owns physical pages.  This module adds the closure class
; and object state needed after a page has been claimed.  The owner directory
; keeps tracing layout outside live objects; the base directory maps its
; logical page index to the physical page returned by PAGE_NEW.

; Allocate a page for a small closure class and build its free-object chain.
SLAB_ADD:
        LD A,(CL_CLASS)
        CP 40H
        JP Z,SLAB_RUN             ; The 260-byte class needs two pages.
        CALL SLAB_ONE             ; The page manager supplies one free page.
        RET C
        LD A,(CL_CLASS)
        LD L,A
        LD H,0
        LD DE,CL_CAP
        ADD HL,DE
        LD A,(HL)
        LD (CL_LEFT),A            ; Capacity determines the chain length.
        LD HL,(CL_PBASE)
        LD (CL_CUR),HL            ; Begin with the first object in the page.
.LINK:
        LD A,(CL_LEFT)
        DEC A
        LD (CL_LEFT),A
        JR Z,.LAST                ; The final object links to the old head.
        LD HL,(CL_CUR)
        LD DE,(CL_SIZE)
        ADD HL,DE
        LD (CL_NEXT),HL           ; Preserve the next object address.
        LD DE,(CL_CUR)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A                 ; A free object stores a two-byte link.
        LD HL,(CL_NEXT)
        LD (CL_CUR),HL
        JR .LINK
.LAST:
        LD DE,(CL_CUR)
        XOR A
        LD (DE),A
        INC DE
        LD (DE),A
        LD HL,(CL_HEAD)
        LD DE,(CL_PBASE)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A                 ; Publish the page head for SLAB_NEW.
        RET

; Find an unused logical closure-page entry and claim one physical page.
SLAB_ONE:
        XOR A
        LD (CL_PAGE),A
.LOOP:
        LD A,(CL_PAGE)
        CP 80H
        JR NC,SLAB_ERR
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,.NEXT
        LD HL,1
        CALL PAGE_NEW
        RET C
        LD (CL_PBASE),HL
        CALL SLAB_PUT
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,(CL_CLASS)
        INC A
        LD (HL),A                 ; Record this page's tracing class.
        CALL SLAB_TOP             ; Retain the largest physical end for reports.
        LD HL,(CL_PBASE)
        XOR A
        RET
.NEXT:
        LD A,(CL_PAGE)
        INC A
        LD (CL_PAGE),A
        JR .LOOP
SLAB_ERR:
        SCF
        RET

; Allocate the two-page class used by a 128-slot closure (260 bytes).
SLAB_RUN:
        XOR A
        LD (CL_PAGE),A
.LOOP:
        LD A,(CL_PAGE)
        CP 7FH
        JR NC,SLAB_ERR
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,.NEXT
        INC HL
        LD A,(HL)
        OR A
        JR NZ,.NEXT
        LD HL,2
        CALL PAGE_NEW
        RET C
        LD (CL_PBASE),HL
        CALL SLAB_PUT
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,41H                  ; Class 40H occupies this page and next.
        LD (HL),A
        INC HL
        LD A,0FFH
        LD (HL),A
        CALL SLAB_TOP
        LD HL,(CL_PBASE)
        XOR A
        RET
.NEXT:
        LD A,(CL_PAGE)
        INC A
        LD (CL_PAGE),A
        JR .LOOP

; Save the physical high byte for the current logical page entry.
SLAB_PUT:
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_PHYS
        ADD HL,DE
        EX DE,HL
        LD HL,(CL_PBASE)
        LD A,H
        LD (DE),A
        RET

; Recover the physical base for the current logical page entry.
SLAB_GET:
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_PHYS
        ADD HL,DE
        LD A,(HL)
        LD H,A
        LD L,0
        LD (CL_PBASE),HL
        RET

; Extend the diagnostic high-water boundary when a new page lies above it.
SLAB_TOP:
        LD HL,(CL_PBASE)
        LD A,(CL_CLASS)
        CP 40H
        JR NZ,.ONE_PAGE
        LD DE,200H                ; The largest class occupies two pages.
        JR .EXTEND
.ONE_PAGE:
        LD DE,100H
.EXTEND:
        ADD HL,DE
        LD (CL_STOP),HL
        LD DE,(CL_TOP)
        OR A
        SBC HL,DE
        RET C
        LD HL,(CL_STOP)
        LD (CL_TOP),HL
        RET

; Find the owned logical page entry containing the current closure address.
; Carry clear returns its index in CL_PAGE.  Carry set reports a miss and
; leaves CL_PAGE at 80H, which the vector and string validators also reject.
SLAB_AT:
        LD HL,(CL_BASE)            ; The page high byte identifies the slab.
        LD A,H
        LD (CL_HIGH),A             ; Keep it while the directory is scanned.
        XOR A
        LD (CL_PAGE),A             ; Start with the first logical entry.
.LOOP:
        LD A,(CL_PAGE)
        CP 80H                     ; Carry is set while entries remain.
        CCF                        ; Carry now reports an exhausted directory.
        RET C                      ; No owned page contains this address.
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,(HL)                  ; Only an owned head entry has a live base.
        OR A
        JR Z,.NEXT                 ; A free entry's base byte is not authoritative.
        INC A
        JR Z,.NEXT                 ; FFH continues a two-page run and has no base.
        LD A,(CL_PAGE)             ; Address the same entry's physical base.
        LD L,A
        LD H,0
        LD DE,CL_PHYS
        ADD HL,DE
        LD A,(CL_HIGH)             ; Compare the page high bytes.
        CP (HL)
        RET Z                      ; Equal also leaves carry clear for a hit.
.NEXT:
        LD A,(CL_PAGE)
        INC A
        LD (CL_PAGE),A             ; Continue with the next logical entry.
        JR .LOOP

; Count one live allocation in the page containing CL_BASE.  Carry set means
; the address belongs to no owned page and no counter was changed.
SLAB_INC:
        CALL SLAB_AT
        RET C                      ; Never count a miss into a neighbouring table.
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_LIVE
        ADD HL,DE
        LD A,(HL)
        INC A
        LD (HL),A
        RET

; Sweep closure pages, release empty slabs and rebuild every class free list.
SLAB_GC:
        LD HL,CL_FREE
        LD DE,CL_FREE+1
        LD BC,129
        XOR A
        LD (HL),A
        LDIR
        XOR A
        LD (CL_PAGE),A
.LOOP:
        LD A,(CL_PAGE)
        CP 80H
        RET NC
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,(HL)
        OR A
        JR Z,.NEXT
        CP 0FFH
        JR Z,.NEXT
        CP 41H
        JR NZ,.ONE
        CALL SLAB_GC2
        JR .NEXT
.ONE:
        DEC A
        LD (CL_LEFT),A
        CALL .PAGE
.NEXT:
        LD A,(CL_PAGE)
        INC A
        LD (CL_PAGE),A
        JR .LOOP

; Sweep one single-page class and then rebuild its free links.
.PAGE:
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_LIVE
        ADD HL,DE
        XOR A
        LD (HL),A                 ; Recount only closures that survived.
        LD A,(CL_LEFT)
        LD L,A
        LD H,0
        LD DE,CL_CAP
        ADD HL,DE
        LD A,(HL)
        LD (CL_TODO),A
        LD A,(CL_LEFT)
        INC A
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD (CL_STEP),HL
        CALL SLAB_GET
        LD HL,(CL_PBASE)
        LD (CL_NEXT),HL
.OBJ_LOOP:
        LD A,(CL_TODO)
        OR A
        JR Z,.PAGE_END
        LD HL,(CL_NEXT)
        LD (CL_OBJ),HL
        CALL GC_ISOBJ
        JR Z,.OBJ_NEXT
        CALL GC_SEEN
        JR Z,.DEAD
        CALL GC_UNSEE
        CALL SLAB_USE
        JR .OBJ_NEXT
.DEAD:
        CALL STR_CLRM
        CALL GC_UNSEE              ; Clear the mark and leave its map byte in HL.
        LD A,C                     ; Recover the allocation's even start mask.
        ADD A,A                    ; Select the adjacent odd vector marker.
        CPL                         ; Form the marker clearing mask.
        LD B,A                     ; Preserve the mask across the map read.
        LD A,(HL)                  ; Read the persistent type and mark bits.
        AND B                      ; Clear only this object's vector marker.
        LD (HL),A                  ; Retain neighboring allocation metadata.
        CALL GC_DROP
.OBJ_NEXT:
        LD HL,(CL_NEXT)
        LD DE,(CL_STEP)
        ADD HL,DE
        LD (CL_NEXT),HL
        LD A,(CL_TODO)
        DEC A
        LD (CL_TODO),A
        JR .OBJ_LOOP
.PAGE_END:
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_LIVE
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,SLAB_FIX
        CALL SLAB_REL
        RET C
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        XOR A
        LD (HL),A                 ; An empty slab returns its page.
        RET

; Release the physical page belonging to the current logical entry.
SLAB_REL:
        LD HL,(CL_PBASE)
        LD DE,1
        CALL PAGE_REL
        RET C
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_PHYS
        ADD HL,DE
        XOR A
        LD (HL),A                 ; A released entry keeps no physical base.
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        XOR A
        LD (HL),A
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_LIVE
        ADD HL,DE
        XOR A
        LD (HL),A
        RET

; Rebuild one class's available-object chain from its surviving page.
SLAB_FIX:
        LD A,(CL_LEFT)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,CL_FREE
        ADD HL,DE
        LD (CL_HEAD),HL
        LD A,(CL_LEFT)
        LD L,A
        LD H,0
        LD DE,CL_CAP
        ADD HL,DE
        LD A,(HL)
        LD (CL_TODO),A
        CALL SLAB_GET
        LD HL,(CL_PBASE)
        LD (CL_NEXT),HL
.LOOP:
        LD A,(CL_TODO)
        OR A
        RET Z
        LD HL,(CL_NEXT)
        LD (CL_OBJ),HL
        CALL GC_ISOBJ
        JR NZ,.NEXT
        LD HL,(CL_HEAD)           ; Address of the class-head word.
        LD E,(HL)                 ; Link to the previous free object.
        INC HL
        LD D,(HL)
        LD HL,(CL_OBJ)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        LD HL,(CL_HEAD)
        LD DE,(CL_OBJ)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
.NEXT:
        LD HL,(CL_NEXT)
        LD DE,(CL_STEP)
        ADD HL,DE
        LD (CL_NEXT),HL
        LD A,(CL_TODO)
        DEC A
        LD (CL_TODO),A
        JR .LOOP

; Sweep a 260-byte two-page closure run.  There is one object and no free list.
SLAB_GC2:
        CALL SLAB_GET
        LD HL,(CL_PBASE)
        LD (CL_OBJ),HL
        CALL GC_ISOBJ
        JR Z,.FREE
        CALL GC_SEEN
        JR Z,.FREE
        CALL GC_UNSEE
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_LIVE
        ADD HL,DE
        LD A,1
        LD (HL),A
        RET
.FREE:
        LD HL,(CL_OBJ)
        CALL GC_UNSEE              ; Clear the mark and leave its map byte in HL.
        LD A,C                     ; Recover the two-page object's even mask.
        ADD A,A                    ; Select the adjacent odd vector marker.
        CPL                         ; Form the marker clearing mask.
        LD B,A                     ; Preserve the mask across the map read.
        LD A,(HL)                  ; Read the persistent type and mark bits.
        AND B                      ; Clear only this object's vector marker.
        LD (HL),A                  ; Retain neighboring allocation metadata.
        CALL GC_DROP
        LD HL,(CL_PBASE)
        LD DE,2
        CALL PAGE_REL
        RET C
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A                 ; Release both pages atomically.
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_PHYS
        ADD HL,DE
        XOR A
        LD (HL),A                 ; The head entry keeps no physical base.
        INC HL
        LD (HL),A                 ; Nor does the FFH continuation entry.
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_LIVE
        ADD HL,DE
        XOR A
        LD (HL),A                 ; Zero the head page's usage count.
        RET

; Increment the live-object count for the page in CL_PAGE.
SLAB_USE:
        LD A,(CL_PAGE)
        LD L,A
        LD H,0
        LD DE,CL_LIVE
        ADD HL,DE
        LD A,(HL)
        INC A
        LD (HL),A
        RET
