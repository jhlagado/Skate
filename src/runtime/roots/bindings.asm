; Binding start maps, page scanning and binding sweep.
; Entry points: SRTBPOS, SRTBNEW and SRTBSW.
; Included in runtime order by ../roots.asm.

; Convert an aligned binding byte address to its bitmap byte and bit mask.
SRTBPOS:
        LD HL,(SRTBADDR)
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        JR C,SRTBPF
        LD A,H
        CP 90H
        JR NC,SRTBPF
        LD A,L
        AND 3
        JR NZ,SRTBPF
        LD A,L
        AND 7
        LD C,A
        LD A,C
        OR A
        JR Z,SRTBPSZ
        LD A,1
SRTBPSH:
        ADD A,A
        DEC C
        JR NZ,SRTBPSH
        JR SRTBPSD
SRTBPSZ:
        LD A,1
SRTBPSD:
        LD C,A
        SRL H
        RR L
        SRL H
        RR L
        SRL H
        RR L
        LD DE,SRTBMB
        ADD HL,DE
        OR A
        RET
SRTBPF:
        XOR A
        SCF
        RET

; Return nonzero only when SRTBADDR is a recorded binding allocation start.
SRTBSTA:
        CALL SRTBPOS
        RET C
        LD A,(HL)
        AND C
        RET

; Record the binding start most recently allocated by SRTCELL.
SRTBNEW:
        LD HL,(SRTCELLP)
        LD (SRTBADDR),HL
        CALL SRTBPOS
        RET C
        LD A,(HL)
        OR C
        LD (HL),A
        LD HL,(SRTCELLP)
        RET

; Clear one allocation-start bit in the closure-start map.
SRTCLCLB:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,C
        ADD A,A                    ; Include the string marker bit.
        OR C
        CPL                         ; Clear the start and string markers.
        LD B,A
        LD A,(HL)
        AND B
        LD (HL),A
        RET

; Clear one queued-mark bit in the closure mark map.
SRTCLCLM:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,C
        CPL
        LD B,A
        LD A,(HL)
        AND B
        LD (HL),A
        RET

; Sweep the four-byte binding pages.  A live page remains owned by the page
; manager; dead cells form a page-local free list before it is joined to the
; global list.  An empty page is returned immediately, so no stale free-list
; address can survive the page release.
SRTBSW:
        LD HL,0
        LD (SRTBHEAD),HL
        LD HL,(SRTBPGBA)
        LD (SRTBPGC),HL             ; Save the current page across the scan.
        XOR A
        LD (SRTBPGI),A
SRTBPGLO:
        LD A,(SRTBPGI)
        LD D,A
        LD A,(SRTBPGN)
        CP D
        JP C,SRTBPGDN
        JP Z,SRTBPGDN
        LD A,D
        LD L,A
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        LD A,(HL)
        LD H,A
        LD L,0
        LD (SRTBPGBA),HL
        LD (SRTBSCAN),HL
        LD HL,0
        LD (SRTBPFRE),HL
        LD (SRTBPLST),HL
        XOR A
        LD (SRTBPLIV),A
        LD A,SRTBCAP
        LD (SRTCLPGQ),A
SRTBPGSL:
        LD A,(SRTCLPGQ)
        OR A
        JP Z,SRTBPGST
        LD HL,(SRTBSCAN)
        LD (SRTBADDR),HL
        CALL SRTBPOS
        JR C,SRTBPGNX
        LD (SRTBMAP),HL
        LD A,C
        LD (SRTBMSK),A
        LD A,(HL)
        AND C
        JR Z,SRTBPGFR               ; A clear bitmap bit is never a live cell.
        LD HL,(SRTBADDR)
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (SRTBFLG),A
        LD A,(SRTBFLG)
        AND 40H
        JR NZ,SRTBPGLV
SRTBPGFR:
        ; Every unmarked cell is reusable.  This includes cells reclaimed by
        ; an earlier collection and virgin slots that were never allocated.
        ; A cell is live only when both its allocation bit and mark bit are
        ; set; this prevents stale payload bytes in virgin slots from pinning
        ; a page.
        LD HL,(SRTBADDR)
        LD DE,(SRTBPFRE)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(SRTBPFRE)
        LD A,H
        OR L
        JR NZ,SRTBPGHD
        LD HL,(SRTBADDR)
        LD (SRTBPLST),HL
SRTBPGHD:
        LD HL,(SRTBADDR)
        LD (SRTBPFRE),HL
        INC HL
        INC HL
        INC HL
        XOR A
        LD (HL),A                  ; A reclaimed cell is no longer allocated.
        JR SRTBPGCL
SRTBPGLV:
        LD HL,(SRTBMAP)
        LD A,(HL)
        OR C
        LD (HL),A                  ; Restore the allocation bit for a live cell.
        LD HL,(SRTBADDR)
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND 0BFH
        LD (HL),A                  ; Surviving cells lose only their mark bit.
        LD A,(SRTBPLIV)
        INC A
        LD (SRTBPLIV),A
        JR SRTBPGNX
SRTBPGCL:
        LD HL,(SRTBMAP)
        LD A,(SRTBMSK)
        CPL
        LD D,A
        LD A,(HL)
        AND D
        LD (HL),A
SRTBPGNX:
        LD HL,(SRTBSCAN)
        LD DE,SRTCELW
        ADD HL,DE
        LD (SRTBSCAN),HL
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JP SRTBPGSL
SRTBPGST:
        LD A,(SRTBPLIV)
        OR A
        JR NZ,SRTBPGLP
        LD HL,(SRTBPGBA)
        LD DE,1
        CALL SRTGPREL
        JR C,SRTBPGLP             ; Keep the descriptor if release was rejected.
        LD A,(SRTBPGN)
        DEC A
        LD (SRTBPGN),A
        LD D,A
        LD A,(SRTBPGI)
        CP D
        JP NC,SRTBPGLO             ; The removed page was the final entry.
        LD L,D
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        LD A,(HL)
        PUSH AF
        LD A,(SRTBPGI)
        LD L,A
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        POP AF
        LD (HL),A                  ; Fill the hole with the former last entry.
        JP SRTBPGLO
SRTBPGLP:
        LD HL,(SRTBPFRE)
        LD A,H
        OR L
        JR Z,SRTBPGIN
        LD DE,(SRTBHEAD)
        LD HL,(SRTBPLST)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(SRTBPFRE)
        LD (SRTBHEAD),HL
SRTBPGIN:
        LD A,(SRTBPGI)
        INC A
        LD (SRTBPGI),A
        JP SRTBPGLO
SRTBPGDN:
        LD HL,(SRTBPGC)
        LD A,H
        OR L
        JR Z,SRTBPGZE
        LD A,(SRTBPGN)
        LD (SRTCLPGQ),A
        XOR A
        LD (SRTBPGI),A
SRTBPGCK:
        LD A,(SRTCLPGQ)
        OR A
        JR Z,SRTBPGZE
        LD A,(SRTBPGI)
        LD L,A
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        LD A,(HL)
        LD D,A
        LD HL,(SRTBPGC)
        LD A,H
        CP D
        JR Z,SRTBPGOK
        LD A,(SRTBPGI)
        INC A
        LD (SRTBPGI),A
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JR SRTBPGCK
SRTBPGOK:
        LD HL,(SRTBPGC)
        LD (SRTBPGBA),HL
        LD HL,(SRTBPGED)
        LD (SRTBPGP),HL            ; All slots are on the rebuilt free chain.
        LD (SRTBEND),HL
        RET
SRTBPGZE:
        LD HL,0
        LD (SRTBPGBA),HL
        LD (SRTBPGP),HL
        LD (SRTBPGED),HL
        LD (SRTBEND),HL
        RET
