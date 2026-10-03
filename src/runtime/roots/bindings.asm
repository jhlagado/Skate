; Binding start maps, page scanning and binding sweep.
; Entry points: GC_VARAT, GC_VARON and GC_CELLS.
; Included in runtime order by ../roots.asm.

; Convert an aligned binding byte address to its bitmap byte and bit mask.
; The map holds one bit per four-byte cell from RT_HEAP.
GC_VARAT:
        LD HL,(SRTBADDR)
        LD DE,RT_HEAP
        OR A
        SBC HL,DE
        JR C,.BAD
        LD A,H
        CP 90H
        JR NC,.BAD
        LD A,L
        AND 3
        JR NZ,.BAD
        SRL H                      ; Count in four-byte cells: one bit per cell.
        RR L
        SRL H
        RR L
        LD A,L
        AND 7
        LD C,A
        JR Z,.ZERO
        LD A,1
.SHIFT:
        ADD A,A
        DEC C
        JR NZ,.SHIFT
        JR .MASK
.ZERO:
        LD A,1
.MASK:
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
.BAD:
        XOR A
        SCF
        RET

; Return nonzero only when SRTBADDR is a recorded binding allocation start.
GC_ISVAR:
        CALL GC_VARAT
        RET C
        LD A,(HL)
        AND C
        RET

; Record the binding start most recently allocated by HEAP_NEW.  HL returns
; the cell address in both cases; carry set means it has no start-map bit.
GC_VARON:
        LD HL,(SRTCELLP)
        LD (SRTBADDR),HL
        CALL GC_VARAT
        JR C,.DONE                 ; An unmapped cell cannot be published.
        LD A,(HL)
        OR C
        LD (HL),A
.DONE:
        LD HL,(SRTCELLP)           ; Restore the cell address; LD keeps carry.
        RET

; Clear one allocation-start bit in the closure-start map.
GC_DROP:
        LD HL,(SRTCLOBJ)
        CALL GC_OBJAT
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
GC_UNSEE:
        LD HL,(SRTCLOBJ)
        CALL GC_OBJAT
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
GC_CELLS:
        LD HL,0
        LD (SRTBHEAD),HL
        LD HL,(SRTBPGBA)
        LD (SRTBPGC),HL             ; Save the current page across the scan.
        XOR A
        LD (SRTBPGI),A
.PAGE:
        LD A,(SRTBPGI)
        LD D,A
        LD A,(SRTBPGN)
        CP D
        JP C,.DONE
        JP Z,.DONE
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
        LD A,HEAP_CAP
        LD (SRTCLPGQ),A
.CELL:
        LD A,(SRTCLPGQ)
        OR A
        JP Z,.PAGE_END
        LD HL,(SRTBSCAN)
        LD (SRTBADDR),HL
        CALL GC_VARAT
        JR C,.NEXT
        LD (SRTBMAP),HL
        LD A,C
        LD (SRTBMSK),A
        LD A,(HL)
        AND C
        JR Z,.FREE                  ; A clear bitmap bit is never a live cell.
        LD HL,(SRTBADDR)
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (SRTBFLG),A
        LD A,(SRTBFLG)
        AND BND_MARK
        JR NZ,.LIVE
.FREE:
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
        JR NZ,.HEAD
        LD HL,(SRTBADDR)
        LD (SRTBPLST),HL
.HEAD:
        LD HL,(SRTBADDR)
        LD (SRTBPFRE),HL
        INC HL
        INC HL
        INC HL
        XOR A
        LD (HL),A                  ; A reclaimed cell is no longer allocated.
        JR .CLEAR
.LIVE:
        LD HL,(SRTBMAP)
        LD A,(HL)
        OR C
        LD (HL),A                  ; Restore the allocation bit for a live cell.
        LD HL,(SRTBADDR)
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND 0FFH-BND_MARK
        LD (HL),A                  ; Surviving cells lose only their mark bit.
        LD A,(SRTBPLIV)
        INC A
        LD (SRTBPLIV),A
        JR .NEXT
.CLEAR:
        LD HL,(SRTBMAP)
        LD A,(SRTBMSK)
        CPL
        LD D,A
        LD A,(HL)
        AND D
        LD (HL),A
.NEXT:
        LD HL,(SRTBSCAN)
        LD DE,CELL_SZ
        ADD HL,DE
        LD (SRTBSCAN),HL
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JP .CELL
.PAGE_END:
        LD A,(SRTBPLIV)
        OR A
        JR NZ,.JOIN
        LD HL,(SRTBPGBA)
        LD DE,1
        CALL PAGE_REL
        JR C,.JOIN                ; Keep the descriptor if release was rejected.
        LD A,(SRTBPGN)
        DEC A
        LD (SRTBPGN),A
        LD D,A
        LD A,(SRTBPGI)
        CP D
        JP NC,.PAGE                ; The removed page was the final entry.
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
        JP .PAGE
.JOIN:
        LD HL,(SRTBPFRE)
        LD A,H
        OR L
        JR Z,.ADVANCE
        LD DE,(SRTBHEAD)
        LD HL,(SRTBPLST)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(SRTBPFRE)
        LD (SRTBHEAD),HL
.ADVANCE:
        LD A,(SRTBPGI)
        INC A
        LD (SRTBPGI),A
        JP .PAGE
.DONE:
        LD HL,(SRTBPGC)
        LD A,H
        OR L
        JR Z,.EMPTY
        LD A,(SRTBPGN)
        LD (SRTCLPGQ),A
        XOR A
        LD (SRTBPGI),A
.FIND:
        LD A,(SRTCLPGQ)
        OR A
        JR Z,.EMPTY
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
        JR Z,.FOUND
        LD A,(SRTBPGI)
        INC A
        LD (SRTBPGI),A
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JR .FIND
.FOUND:
        LD HL,(SRTBPGC)
        LD (SRTBPGBA),HL
        LD HL,(SRTBPGED)
        LD (SRTBPGP),HL            ; All slots are on the rebuilt free chain.
        LD (SRTBEND),HL
        RET
.EMPTY:
        LD HL,0
        LD (SRTBPGBA),HL
        LD (SRTBPGP),HL
        LD (SRTBPGED),HL
        LD (SRTBEND),HL
        RET
