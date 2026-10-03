; Closure page allocation for the complete runtime pool.
;
; The page manager owns physical pages.  This module adds the closure class
; and object state needed after a page has been claimed.  The owner directory
; keeps tracing layout outside live objects; the base directory maps its
; logical page index to the physical page returned by PAGE_NEW.

; Allocate a page for a small closure class and build its free-object chain.
SLAB_ADD:
        LD A,(SRTCLIDX)
        CP 40H
        JP Z,SLAB_RUN             ; The 260-byte class needs two pages.
        CALL SLAB_ONE             ; The page manager supplies one free page.
        RET C
        LD A,(SRTCLIDX)
        LD L,A
        LD H,0
        LD DE,SRTCLCAP
        ADD HL,DE
        LD A,(HL)
        LD (SRTCLPGN),A           ; Capacity determines the chain length.
        LD HL,(SRTCLPGA)
        LD (SRTCLPGF),HL          ; Begin with the first object in the page.
.LINK:
        LD A,(SRTCLPGN)
        DEC A
        LD (SRTCLPGN),A
        JR Z,.LAST                ; The final object links to the old head.
        LD HL,(SRTCLPGF)
        LD DE,(SRTCLSZ)
        ADD HL,DE
        LD (SRTCLPGL),HL          ; Preserve the next object address.
        LD DE,(SRTCLPGF)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A                 ; A free object stores a two-byte link.
        LD HL,(SRTCLPGL)
        LD (SRTCLPGF),HL
        JR .LINK
.LAST:
        LD DE,(SRTCLPGF)
        XOR A
        LD (DE),A
        INC DE
        LD (DE),A
        LD HL,(SRTCLFP)
        LD DE,(SRTCLPGA)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A                 ; Publish the page head for SLAB_NEW.
        RET

; Find an unused logical closure-page entry and claim one physical page.
SLAB_ONE:
        XOR A
        LD (SRTCLPGI),A
.LOOP:
        LD A,(SRTCLPGI)
        CP 80H
        JR NC,SLAB_ERR
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,.NEXT
        LD HL,1
        CALL PAGE_NEW
        RET C
        LD (SRTCLPGA),HL
        CALL SLAB_PUT
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(SRTCLIDX)
        INC A
        LD (HL),A                 ; Record this page's tracing class.
        CALL SLAB_TOP             ; Retain the largest physical end for reports.
        LD HL,(SRTCLPGA)
        XOR A
        RET
.NEXT:
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A
        JR .LOOP
SLAB_ERR:
        SCF
        RET

; Allocate the two-page class used by a 128-slot closure (260 bytes).
SLAB_RUN:
        XOR A
        LD (SRTCLPGI),A
.LOOP:
        LD A,(SRTCLPGI)
        CP 7FH
        JR NC,SLAB_ERR
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
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
        LD (SRTCLPGA),HL
        CALL SLAB_PUT
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,41H                  ; Class 40H occupies this page and next.
        LD (HL),A
        INC HL
        LD A,0FFH
        LD (HL),A
        CALL SLAB_TOP
        LD HL,(SRTCLPGA)
        XOR A
        RET
.NEXT:
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A
        JR .LOOP

; Save the physical high byte for the current logical page entry.
SLAB_PUT:
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLPBA
        ADD HL,DE
        EX DE,HL
        LD HL,(SRTCLPGA)
        LD A,H
        LD (DE),A
        RET

; Recover the physical base for the current logical page entry.
SLAB_GET:
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLPBA
        ADD HL,DE
        LD A,(HL)
        LD H,A
        LD L,0
        LD (SRTCLPGA),HL
        RET

; Extend the diagnostic high-water boundary when a new page lies above it.
SLAB_TOP:
        LD HL,(SRTCLPGA)
        LD A,(SRTCLIDX)
        CP 40H
        JR NZ,.ONE_PAGE
        LD DE,200H                ; The largest class occupies two pages.
        JR .EXTEND
.ONE_PAGE:
        LD DE,100H
.EXTEND:
        ADD HL,DE
        LD (SRTCLPGE),HL
        LD DE,(SRTCLCUR)
        OR A
        SBC HL,DE
        RET C
        LD HL,(SRTCLPGE)
        LD (SRTCLCUR),HL
        RET

; Find the owned logical page entry containing the current closure address.
; Carry clear returns its index in SRTCLPGI.  Carry set reports a miss and
; leaves SRTCLPGI at 80H, which the vector and string validators also reject.
SLAB_AT:
        LD HL,(SRTCLBAS)           ; The page high byte identifies the slab.
        LD A,H
        LD (SRTCLPGH),A            ; Keep it while the directory is scanned.
        XOR A
        LD (SRTCLPGI),A            ; Start with the first logical entry.
.LOOP:
        LD A,(SRTCLPGI)
        CP 80H                     ; Carry is set while entries remain.
        CCF                        ; Carry now reports an exhausted directory.
        RET C                      ; No owned page contains this address.
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)                  ; Only an owned head entry has a live base.
        OR A
        JR Z,.NEXT                 ; A free entry's base byte is not authoritative.
        INC A
        JR Z,.NEXT                 ; FFH continues a two-page run and has no base.
        LD A,(SRTCLPGI)            ; Address the same entry's physical base.
        LD L,A
        LD H,0
        LD DE,SRTCLPBA
        ADD HL,DE
        LD A,(SRTCLPGH)            ; Compare the page high bytes.
        CP (HL)
        RET Z                      ; Equal also leaves carry clear for a hit.
.NEXT:
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A            ; Continue with the next logical entry.
        JR .LOOP

; Count one live allocation in the page containing SRTCLBAS.  Carry set means
; the address belongs to no owned page and no counter was changed.
SLAB_INC:
        CALL SLAB_AT
        RET C                      ; Never count a miss into a neighbouring table.
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        LD A,(HL)
        INC A
        LD (HL),A
        RET

; Sweep closure pages, release empty slabs and rebuild every class free list.
SLAB_GC:
        LD HL,SRTCFREE
        LD DE,SRTCFREE+1
        LD BC,129
        XOR A
        LD (HL),A
        LDIR
        XOR A
        LD (SRTCLPGI),A
.LOOP:
        LD A,(SRTCLPGI)
        CP 80H
        RET NC
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
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
        LD (SRTCLPGN),A
        CALL .PAGE
.NEXT:
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A
        JR .LOOP

; Sweep one single-page class and then rebuild its free links.
.PAGE:
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        XOR A
        LD (HL),A                 ; Recount only closures that survived.
        LD A,(SRTCLPGN)
        LD L,A
        LD H,0
        LD DE,SRTCLCAP
        ADD HL,DE
        LD A,(HL)
        LD (SRTCLPGQ),A
        LD A,(SRTCLPGN)
        INC A
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD (SRTCLSTR),HL
        CALL SLAB_GET
        LD HL,(SRTCLPGA)
        LD (SRTCLPGL),HL
.OBJ_LOOP:
        LD A,(SRTCLPGQ)
        OR A
        JR Z,.PAGE_END
        LD HL,(SRTCLPGL)
        LD (SRTCLOBJ),HL
        CALL SRTCLSTA
        JR Z,.OBJ_NEXT
        CALL SRTCLSEE
        JR Z,.DEAD
        CALL SRTCLCLM
        CALL SLAB_USE
        JR .OBJ_NEXT
.DEAD:
        CALL STR_CLRM
        CALL SRTCLCLM              ; Clear the mark and leave its map byte in HL.
        LD A,C                     ; Recover the allocation's even start mask.
        ADD A,A                    ; Select the adjacent odd vector marker.
        CPL                         ; Form the marker clearing mask.
        LD B,A                     ; Preserve the mask across the map read.
        LD A,(HL)                  ; Read the persistent type and mark bits.
        AND B                      ; Clear only this object's vector marker.
        LD (HL),A                  ; Retain neighboring allocation metadata.
        CALL SRTCLCLB
.OBJ_NEXT:
        LD HL,(SRTCLPGL)
        LD DE,(SRTCLSTR)
        ADD HL,DE
        LD (SRTCLPGL),HL
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JR .OBJ_LOOP
.PAGE_END:
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,SLAB_FIX
        CALL SLAB_REL
        RET C
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        XOR A
        LD (HL),A                 ; An empty slab returns its page.
        RET

; Release the physical page belonging to the current logical entry.
SLAB_REL:
        LD HL,(SRTCLPGA)
        LD DE,1
        CALL PAGE_REL
        RET C
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLPBA
        ADD HL,DE
        XOR A
        LD (HL),A                 ; A released entry keeps no physical base.
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        XOR A
        LD (HL),A
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        XOR A
        LD (HL),A
        RET

; Rebuild one class's available-object chain from its surviving page.
SLAB_FIX:
        LD A,(SRTCLPGN)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SRTCFREE
        ADD HL,DE
        LD (SRTCLFP),HL
        LD A,(SRTCLPGN)
        LD L,A
        LD H,0
        LD DE,SRTCLCAP
        ADD HL,DE
        LD A,(HL)
        LD (SRTCLPGQ),A
        CALL SLAB_GET
        LD HL,(SRTCLPGA)
        LD (SRTCLPGL),HL
.LOOP:
        LD A,(SRTCLPGQ)
        OR A
        RET Z
        LD HL,(SRTCLPGL)
        LD (SRTCLOBJ),HL
        CALL SRTCLSTA
        JR NZ,.NEXT
        LD HL,(SRTCLFP)           ; Address of the class-head word.
        LD E,(HL)                 ; Link to the previous free object.
        INC HL
        LD D,(HL)
        LD HL,(SRTCLOBJ)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
        LD HL,(SRTCLFP)
        LD DE,(SRTCLOBJ)
        LD A,E
        LD (HL),A
        INC HL
        LD A,D
        LD (HL),A
.NEXT:
        LD HL,(SRTCLPGL)
        LD DE,(SRTCLSTR)
        ADD HL,DE
        LD (SRTCLPGL),HL
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JR .LOOP

; Sweep a 260-byte two-page closure run.  There is one object and no free list.
SLAB_GC2:
        CALL SLAB_GET
        LD HL,(SRTCLPGA)
        LD (SRTCLOBJ),HL
        CALL SRTCLSTA
        JR Z,.FREE
        CALL SRTCLSEE
        JR Z,.FREE
        CALL SRTCLCLM
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        LD A,1
        LD (HL),A
        RET
.FREE:
        LD HL,(SRTCLOBJ)
        CALL SRTCLCLM              ; Clear the mark and leave its map byte in HL.
        LD A,C                     ; Recover the two-page object's even mask.
        ADD A,A                    ; Select the adjacent odd vector marker.
        CPL                         ; Form the marker clearing mask.
        LD B,A                     ; Preserve the mask across the map read.
        LD A,(HL)                  ; Read the persistent type and mark bits.
        AND B                      ; Clear only this object's vector marker.
        LD (HL),A                  ; Retain neighboring allocation metadata.
        CALL SRTCLCLB
        LD HL,(SRTCLPGA)
        LD DE,2
        CALL PAGE_REL
        RET C
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A                 ; Release both pages atomically.
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLPBA
        ADD HL,DE
        XOR A
        LD (HL),A                 ; The head entry keeps no physical base.
        INC HL
        LD (HL),A                 ; Nor does the FFH continuation entry.
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        XOR A
        LD (HL),A                 ; Zero the head page's usage count.
        RET

; Increment the live-object count for the page in SRTCLPGI.
SLAB_USE:
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        LD A,(HL)
        INC A
        LD (HL),A
        RET
