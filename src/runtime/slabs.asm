; Closure page allocation for the complete runtime pool.
;
; The page manager owns physical pages.  This module adds the closure class
; and object state needed after a page has been claimed.  The owner directory
; keeps tracing layout outside live objects; the base directory maps its
; logical page index to the physical page returned by SRTGPALL.

; Allocate a page for a small closure class and build its free-object chain.
SRTCLPNW:
        LD A,(SRTCLIDX)
        CP 40H
        JP Z,SRTCLPRN             ; The 260-byte class needs two pages.
        CALL SRTCLP1              ; The page manager supplies one free page.
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
SRTCLPBL:
        LD A,(SRTCLPGN)
        DEC A
        LD (SRTCLPGN),A
        JR Z,SRTCLPZE             ; The final object links to the old head.
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
        JR SRTCLPBL
SRTCLPZE:
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
        LD (HL),A                 ; Publish the page head for SRTCLALC.
        RET

; Find an unused logical closure-page entry and claim one physical page.
SRTCLP1:
        XOR A
        LD (SRTCLPGI),A
SRTCLP1L:
        LD A,(SRTCLPGI)
        CP 80H
        JR NC,SRTCLPFL
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,SRTCLP1N
        LD HL,1
        CALL SRTGPALL
        RET C
        LD (SRTCLPGA),HL
        CALL SRTCLPST
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(SRTCLIDX)
        INC A
        LD (HL),A                 ; Record this page's tracing class.
        CALL SRTCLPUP             ; Retain the largest physical end for reports.
        LD HL,(SRTCLPGA)
        XOR A
        RET
SRTCLP1N:
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A
        JR SRTCLP1L
SRTCLPFL:
        SCF
        RET

; Allocate the two-page class used by a 128-slot closure (260 bytes).
SRTCLPRN:
        XOR A
        LD (SRTCLPGI),A
SRTCLPRL:
        LD A,(SRTCLPGI)
        CP 7FH
        JR NC,SRTCLPFL
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,SRTCLPRX
        INC HL
        LD A,(HL)
        OR A
        JR NZ,SRTCLPRX
        LD HL,2
        CALL SRTGPALL
        RET C
        LD (SRTCLPGA),HL
        CALL SRTCLPST
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
        CALL SRTCLPUP
        LD HL,(SRTCLPGA)
        XOR A
        RET
SRTCLPRX:
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A
        JR SRTCLPRL

; Save the physical high byte for the current logical page entry.
SRTCLPST:
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
SRTCLGET:
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
SRTCLPUP:
        LD HL,(SRTCLPGA)
        LD A,(SRTCLIDX)
        CP 40H
        JR NZ,SRTCLP1E
        LD DE,200H                ; The largest class occupies two pages.
        JR SRTCLPUE
SRTCLP1E:
        LD DE,100H
SRTCLPUE:
        ADD HL,DE
        LD (SRTCLPGE),HL
        LD DE,(SRTCLCUR)
        OR A
        SBC HL,DE
        RET C
        LD HL,(SRTCLPGE)
        LD (SRTCLCUR),HL
        RET

; Find the logical page entry containing the current closure address.
SRTCLFND:
        LD HL,(SRTCLBAS)
        LD A,H
        LD (SRTCLPGH),A
        XOR A
        LD (SRTCLPGI),A
SRTCLFNL:
        LD A,(SRTCLPGI)
        CP 80H
        RET NC
        LD L,A
        LD H,0
        LD DE,SRTCLPBA
        ADD HL,DE
        LD A,(HL)
        LD D,A
        LD A,(SRTCLPGH)
        CP D
        RET Z
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A
        JR SRTCLFNL

; Count one live allocation in the page containing SRTCLBAS.
SRTCLINC:
        CALL SRTCLFND
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
SRTCLSW:
        LD HL,SRTCFREE
        LD DE,SRTCFREE+1
        LD BC,129
        XOR A
        LD (HL),A
        LDIR
        XOR A
        LD (SRTCLPGI),A
SRTCLSMP:
        LD A,(SRTCLPGI)
        CP 80H
        RET NC
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)
        OR A
        JR Z,SRTCLSNX
        CP 0FFH
        JR Z,SRTCLSNX
        CP 41H
        JR NZ,SRTCLONE
        CALL SRTCLR2
        JR SRTCLSNX
SRTCLONE:
        DEC A
        LD (SRTCLPGN),A
        CALL SRTCLPAG
SRTCLSNX:
        LD A,(SRTCLPGI)
        INC A
        LD (SRTCLPGI),A
        JR SRTCLSMP

; Sweep one single-page class and then rebuild its free links.
SRTCLPAG:
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
        CALL SRTCLGET
        LD HL,(SRTCLPGA)
        LD (SRTCLPGL),HL
SRTCLPLL:
        LD A,(SRTCLPGQ)
        OR A
        JR Z,SRTCLPDN
        LD HL,(SRTCLPGL)
        LD (SRTCLOBJ),HL
        CALL SRTCLSTA
        JR Z,SRTCLPNX
        CALL SRTCLSEE
        JR Z,SRTCLPDE
        CALL SRTCLCLM
        CALL SRTCLUIN
        JR SRTCLPNX
SRTCLPDE:
        CALL SRTSCL
        CALL SRTCLCLM              ; Clear the mark and leave its map byte in HL.
        LD A,C                     ; Recover the allocation's even start mask.
        ADD A,A                    ; Select the adjacent odd vector marker.
        CPL                         ; Form the marker clearing mask.
        LD B,A                     ; Preserve the mask across the map read.
        LD A,(HL)                  ; Read the persistent type and mark bits.
        AND B                      ; Clear only this object's vector marker.
        LD (HL),A                  ; Retain neighboring allocation metadata.
        CALL SRTCLCLB
SRTCLPNX:
        LD HL,(SRTCLPGL)
        LD DE,(SRTCLSTR)
        ADD HL,DE
        LD (SRTCLPGL),HL
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JR SRTCLPLL
SRTCLPDN:
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        LD A,(HL)
        OR A
        JR NZ,SRTCLPFR
        CALL SRTCLPRE
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
SRTCLPRE:
        LD HL,(SRTCLPGA)
        LD DE,1
        CALL SRTGPREL
        RET C
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
SRTCLPFR:
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
        CALL SRTCLGET
        LD HL,(SRTCLPGA)
        LD (SRTCLPGL),HL
SRTCLFLP:
        LD A,(SRTCLPGQ)
        OR A
        RET Z
        LD HL,(SRTCLPGL)
        LD (SRTCLOBJ),HL
        CALL SRTCLSTA
        JR NZ,SRTCLFLN
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
SRTCLFLN:
        LD HL,(SRTCLPGL)
        LD DE,(SRTCLSTR)
        ADD HL,DE
        LD (SRTCLPGL),HL
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JR SRTCLFLP

; Sweep a 260-byte two-page closure run.  There is one object and no free list.
SRTCLR2:
        CALL SRTCLGET
        LD HL,(SRTCLPGA)
        LD (SRTCLOBJ),HL
        CALL SRTCLSTA
        JR Z,SRTCLRLS
        CALL SRTCLSEE
        JR Z,SRTCLRLS
        CALL SRTCLCLM
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        LD A,1
        LD (HL),A
        RET
SRTCLRLS:
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
        CALL SRTGPREL
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
        LD DE,SRTCLUSE
        ADD HL,DE
        XOR A
        LD (HL),A                 ; Zero the head page's usage count.
        RET

; Increment the live-object count for the page in SRTCLPGI.
SRTCLUIN:
        LD A,(SRTCLPGI)
        LD L,A
        LD H,0
        LD DE,SRTCLUSE
        ADD HL,DE
        LD A,(HL)
        INC A
        LD (HL),A
        RET
