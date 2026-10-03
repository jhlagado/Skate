; Binding start maps, page scanning and binding sweep.
; Entry points: GC_VARAT, GC_VARON and GC_CELLS.
; Included in runtime order by ../roots.asm.

; Convert an aligned binding byte address to its bitmap byte and bit mask.
; The map holds one bit per four-byte cell from RT_HEAP.
GC_VARAT:
        LD HL,(BND_CELL)
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
        LD DE,BND_MAP
        ADD HL,DE
        OR A
        RET
.BAD:
        XOR A
        SCF
        RET

; Return nonzero only when BND_CELL is a recorded binding allocation start.
GC_ISVAR:
        CALL GC_VARAT
        RET C
        LD A,(HL)
        AND C
        RET

; Record the binding start most recently allocated by HEAP_NEW.  HL returns
; the cell address in both cases; carry set means it has no start-map bit.
GC_VARON:
        LD HL,(HEAP_OBJ)
        LD (BND_CELL),HL
        CALL GC_VARAT
        JR C,.DONE                 ; An unmapped cell cannot be published.
        LD A,(HL)
        OR C
        LD (HL),A
.DONE:
        LD HL,(HEAP_OBJ)           ; Restore the cell address; LD keeps carry.
        RET

; Clear one allocation-start bit in the closure-start map.
GC_DROP:
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,CL_MAP
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
        LD HL,(CL_OBJ)
        CALL GC_OBJAT
        LD C,A
        LD DE,GC_MARKS
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
        LD (BND_FREE),HL
        LD HL,(BND_BASE)
        LD (BND_SAVE),HL            ; Save the current page across the scan.
        XOR A
        LD (BND_IDX),A
.PAGE:
        LD A,(BND_IDX)
        LD D,A
        LD A,(BND_CNT)
        CP D
        JP C,.DONE
        JP Z,.DONE
        LD A,D
        LD L,A
        LD H,0
        LD DE,BND_PHYS
        ADD HL,DE
        LD A,(HL)
        LD H,A
        LD L,0
        LD (BND_BASE),HL
        LD (BND_PTR),HL
        LD HL,0
        LD (BND_HEAD),HL
        LD (BND_TAIL),HL
        XOR A
        LD (BND_LIVE),A
        LD A,HEAP_CAP
        LD (CL_TODO),A
.CELL:
        LD A,(CL_TODO)
        OR A
        JP Z,.PAGE_END
        LD HL,(BND_PTR)
        LD (BND_CELL),HL
        CALL GC_VARAT
        JR C,.NEXT
        LD (BND_MAPP),HL
        LD A,C
        LD (BND_MASK),A
        LD A,(HL)
        AND C
        JR Z,.FREE                  ; A clear bitmap bit is never a live cell.
        LD HL,(BND_CELL)
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        LD (BND_FLAG),A
        LD A,(BND_FLAG)
        AND BND_MARK
        JR NZ,.LIVE
.FREE:
        ; Every unmarked cell is reusable.  This includes cells reclaimed by
        ; an earlier collection and virgin slots that were never allocated.
        ; A cell is live only when both its allocation bit and mark bit are
        ; set; this prevents stale payload bytes in virgin slots from pinning
        ; a page.
        LD HL,(BND_CELL)
        LD DE,(BND_HEAD)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(BND_HEAD)
        LD A,H
        OR L
        JR NZ,.HEAD
        LD HL,(BND_CELL)
        LD (BND_TAIL),HL
.HEAD:
        LD HL,(BND_CELL)
        LD (BND_HEAD),HL
        INC HL
        INC HL
        INC HL
        XOR A
        LD (HL),A                  ; A reclaimed cell is no longer allocated.
        JR .CLEAR
.LIVE:
        LD HL,(BND_MAPP)
        LD A,(HL)
        OR C
        LD (HL),A                  ; Restore the allocation bit for a live cell.
        LD HL,(BND_CELL)
        INC HL
        INC HL
        INC HL
        LD A,(HL)
        AND 0FFH-BND_MARK
        LD (HL),A                  ; Surviving cells lose only their mark bit.
        LD A,(BND_LIVE)
        INC A
        LD (BND_LIVE),A
        JR .NEXT
.CLEAR:
        LD HL,(BND_MAPP)
        LD A,(BND_MASK)
        CPL
        LD D,A
        LD A,(HL)
        AND D
        LD (HL),A
.NEXT:
        LD HL,(BND_PTR)
        LD DE,CELL_SZ
        ADD HL,DE
        LD (BND_PTR),HL
        LD A,(CL_TODO)
        DEC A
        LD (CL_TODO),A
        JP .CELL
.PAGE_END:
        LD A,(BND_LIVE)
        OR A
        JR NZ,.JOIN
        LD HL,(BND_BASE)
        LD DE,1
        CALL PAGE_REL
        JR C,.JOIN                ; Keep the descriptor if release was rejected.
        LD A,(BND_CNT)
        DEC A
        LD (BND_CNT),A
        LD D,A
        LD A,(BND_IDX)
        CP D
        JP NC,.PAGE                ; The removed page was the final entry.
        LD L,D
        LD H,0
        LD DE,BND_PHYS
        ADD HL,DE
        LD A,(HL)
        PUSH AF
        LD A,(BND_IDX)
        LD L,A
        LD H,0
        LD DE,BND_PHYS
        ADD HL,DE
        POP AF
        LD (HL),A                  ; Fill the hole with the former last entry.
        JP .PAGE
.JOIN:
        LD HL,(BND_HEAD)
        LD A,H
        OR L
        JR Z,.ADVANCE
        LD DE,(BND_FREE)
        LD HL,(BND_TAIL)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(BND_HEAD)
        LD (BND_FREE),HL
.ADVANCE:
        LD A,(BND_IDX)
        INC A
        LD (BND_IDX),A
        JP .PAGE
.DONE:
        LD HL,(BND_SAVE)
        LD A,H
        OR L
        JR Z,.EMPTY
        LD A,(BND_CNT)
        LD (CL_TODO),A
        XOR A
        LD (BND_IDX),A
.FIND:
        LD A,(CL_TODO)
        OR A
        JR Z,.EMPTY
        LD A,(BND_IDX)
        LD L,A
        LD H,0
        LD DE,BND_PHYS
        ADD HL,DE
        LD A,(HL)
        LD D,A
        LD HL,(BND_SAVE)
        LD A,H
        CP D
        JR Z,.FOUND
        LD A,(BND_IDX)
        INC A
        LD (BND_IDX),A
        LD A,(CL_TODO)
        DEC A
        LD (CL_TODO),A
        JR .FIND
.FOUND:
        LD HL,(BND_SAVE)
        LD (BND_BASE),HL
        LD HL,(BND_END)
        LD (BND_NEXT),HL           ; All slots are on the rebuilt free chain.
        LD (BND_TOP),HL
        RET
.EMPTY:
        LD HL,0
        LD (BND_BASE),HL
        LD (BND_NEXT),HL
        LD (BND_END),HL
        LD (BND_TOP),HL
        RET
