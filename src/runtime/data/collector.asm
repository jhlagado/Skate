; Pair marking, root scanning and collector passes.
; Entry points: GC, ROOT_ALL, GC_MARK and GC_DRAIN.
; Included in runtime order by ../data.asm.

; Stop-the-world mark-and-sweep for every eight-byte pair slab.  Root discovery
; is exact: compiler-patched static records, active value stacks, frames and
; construction scratch are visited by type rather than by byte pattern.
GC:
        LD HL,(SRTGCNT)            ; Count a complete stop-the-world cycle.
        INC HL
        LD (SRTGCNT),HL
        CALL GC_CLEAR               ; Clear only mark bits from the last cycle.
        CALL GC_RESET               ; Start this collection with an empty mark map.
        LD HL,RT_GCLO               ; Restart the bounded pair worklist.
        LD (SRTMSTK),HL             ; The next mark is written at its base.
        XOR A
        LD (SRTMOVER),A             ; No queue overflow has occurred yet.
        LD (SRTMNEW),A              ; Clear the fallback pass indicator.
        CALL ROOT_ALL               ; Visit only declared live value locations.
        CALL GC_DRAIN               ; Process every queued object before overflow checks.
        LD A,(SRTMOVER)
        OR A
        JR Z,.SWEEP                 ; A complete queue has visited every reachable edge.
.FALLBACK:
        XOR A
        LD (SRTMNEW),A              ; Report only marks created by this fallback pass.
        CALL GC_PAIRS               ; Visit every marked pair to recover missed edges.
        CALL GC_OBJS                ; Visit every marked closure without recursion.
        CALL GC_DRAIN               ; Process entries found by the fallback scan.
        LD A,(SRTMNEW)
        OR A
        JR NZ,.FALLBACK             ; Continue until a fixed point is reached.
.SWEEP:
        CALL GC_CELLS               ; Reclaim dead four-byte bindings.
        CALL SLAB_GC                ; Reclaim dead rounded closure blocks.
        CALL GC_SWEEP              ; Rebuild free records and clear surviving marks.
        RET

; Mark the two typed inputs held across an allocation retry.  These roots use
; their own storage because the ordinary pair tracing scratch is overwritten
; while a queued pair is being inspected.
GC_CONS:
        LD A,(SRTCRON)
        OR A
        RET Z
        LD A,(SRTCRCTA)
        LD HL,(SRTCRCAR)
        CALL GC_VALUE
.CDR:
        LD A,(SRTCRDTA)
        LD HL,(SRTCRCDR)
        JP GC_VALUE

; Clear mark bits in every allocated or free record before tracing.
GC_CLEAR:
        LD A,(SRTPSLBN)
        OR A
        RET Z
        LD B,A                      ; B counts the pair slabs.
        LD HL,SRTPSLT
.SLAB:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,.SKIP                  ; Skip holes without scanning address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (SRTPSST),HL
        LD (SRTPSBA),DE
        LD (SRTPSCAN),DE
        LD C,PAIR_CAP               ; Each page contains 32 eight-byte records.
.RECORD:
        LD HL,(SRTPSCAN)
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 7FH                     ; Preserve tags and allocation, clear marking.
        LD (HL),A
        LD HL,(SRTPSCAN)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (SRTPSCAN),HL
        DEC C
        JR NZ,.RECORD
        LD HL,(SRTPSST)
        DJNZ .SLAB
        RET
.SKIP:
        LD DE,3                     ; Advance over a released descriptor slot.
        ADD HL,DE
        DJNZ .SLAB
        RET

; Sweep all pair slabs.  Dead records become zero-state cells; live records
; retain their tags and allocation bit but lose the mark bit.
GC_SWEEP:
        LD A,(SRTPSLBN)
        OR A
        RET Z
        LD B,A
        LD HL,SRTPSLT
.SLAB:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,.SKIP                  ; Skip holes without sweeping address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (SRTPSST),HL
        LD (SRTPSBA),DE
        LD (SRTPSCAN),DE
        LD C,PAIR_CAP
.RECORD:
        LD HL,(SRTPSCAN)
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 40H                     ; An unallocated record is already dead.
        JR Z,.DEAD
        LD A,(HL)
        AND 80H                     ; A marked allocation remains reachable.
        JR NZ,.LIVE
.DEAD:
        XOR A                       ; Clear the CAR tag and both ownership bits.
        LD (HL),A
        INC HL
        INC HL
        INC HL
        INC HL                       ; Reach the CDR metadata byte.
        LD (HL),A                   ; A dead pair carries no CDR tag.
        JR .NEXT
.LIVE:
        LD A,(HL)
        AND 7FH                     ; Keep the live record allocated for reuse.
        LD (HL),A
.NEXT:
        LD HL,(SRTPSCAN)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (SRTPSCAN),HL
        DEC C
        JR NZ,.RECORD
        LD HL,(SRTPSST)
        DJNZ .SLAB
        CALL PAIR_GC                ; Rebuild links after dead records were cleared.
        RET
.SKIP:
        LD DE,3                     ; Advance over a released descriptor slot.
        ADD HL,DE
        DJNZ .SLAB
        CALL PAIR_GC
        RET

; Drain the bounded worklist.  A full queue is handled by the fallback scan.
GC_DRAIN:
        LD HL,(SRTMSTK)
        LD DE,RT_GCLO
        OR A
        SBC HL,DE
        RET Z
        LD HL,(SRTMSTK)
        LD DE,2
        OR A
        SBC HL,DE
        LD (SRTMSTK),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        ; The shared pool no longer assigns closures a fixed address band.
        ; Consult the exact closure-start map instead of guessing from H.
        LD (SRTCLOBJ),HL
        PUSH HL
        CALL GC_ISOBJ
        POP HL
        JR Z,.PAIR
        XOR A
        CALL SRTVHOOK
        JR GC_DRAIN
.PAIR:
        LD A,1
        CALL GC_EDGES
        JR GC_DRAIN

; Scan every marked pair after the bounded queue has overflowed.  Repeated
; passes compute the same fixed point as an unbounded worklist.
GC_PAIRS:
        LD A,(SRTPSLBN)
        OR A
        RET Z
        LD B,A
        LD HL,SRTPSLT
.SLAB:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,.SKIP                 ; Skip holes without scanning address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (SRTPSST),HL
        LD (SRTPSBA),DE
        LD (SRTPSCAN),DE
        LD C,PAIR_CAP
.RECORD:
        LD HL,(SRTPSCAN)
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 80H                     ; Only marked records need another visit.
        JR Z,.NEXT
        LD DE,(SRTPSST)             ; Preserve the fallback cursor across validation.
        LD (SRTFSST),DE
        LD DE,(SRTPSBA)
        LD (SRTFSBA),DE
        LD DE,(SRTPSCAN)
        LD (SRTFSCAN),DE
        PUSH BC                     ; Preserve both slab and record counters.
        PUSH HL                     ; Preserve the record address across tracing.
        LD HL,(SRTPSCAN)
        CALL GC_EDGES               ; The queued value is the record start.
        POP HL
        POP BC
        LD DE,(SRTFSST)             ; Restore the slab cursor changed by PAIR_CHK.
        LD (SRTPSST),DE
        LD DE,(SRTFSBA)
        LD (SRTPSBA),DE
        LD DE,(SRTFSCAN)
        LD (SRTPSCAN),DE
.NEXT:
        LD HL,(SRTPSCAN)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (SRTPSCAN),HL
        DEC C
        JR NZ,.RECORD
        LD HL,(SRTPSST)
        DJNZ .SLAB
        RET
.SKIP:
        LD DE,3                     ; Advance over a released descriptor slot.
        ADD HL,DE
        DJNZ .SLAB
        RET

; Scan a half-open byte range for the three-byte pattern payload,tag-one.
; The cursor may stop at end-3, but never at either of the two positions
; whose payload or tag byte would lie beyond the declared range.
GC_SCAN:
        LD (SRTSCP),HL
        LD (SRTSCE),DE
.LOOP:
        LD HL,(SRTSCP)
        LD DE,(SRTSCE)
        LD BC,2
        ADD HL,BC
        OR A
        SBC HL,DE
        JR NC,.DONE
        LD HL,(SRTSCP)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        CP 1
        JR NZ,.NEXT
        EX DE,HL
        CALL GC_MARK
.NEXT:
        LD HL,(SRTSCP)
        INC HL
        LD (SRTSCP),HL
        JR .LOOP
.DONE:
        RET

; Mark one pair and queue it for child scanning.
GC_MARK:
        LD A,1                      ; Validate the candidate as a pair value.
        CALL PAIR_CHK
        RET C
        LD HL,(SRTPSAD)             ; Recover the validated record address.
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 40H                     ; A swept or never-published record is ignored.
        RET Z
        LD A,(HL)
        AND 80H                     ; Already marked records are already queued.
        RET NZ
        LD A,(HL)
        OR 80H                      ; Set the mark bit without changing tags/allocation.
        LD (HL),A
        LD A,1
        LD (SRTMNEW),A             ; This object must be visited by the trace.
        LD HL,(SRTPSAD)             ; Queue the record address, not its state byte.
        LD DE,(SRTMSTK)
        LD A,D
        CP 0D4H
        JR NC,.FULL                ; Preserve the mark and defer its children.
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
        LD (SRTMOVER),A            ; The fallback scanner will revisit marked pairs.
        RET

; Trace the CAR and CDR pair edges of one queued record.
GC_EDGES:
        LD (SRTMVAL),HL
        LD A,1
        CALL PAIR_CHK
        RET C
        ; Copy both payloads before marking either edge; GC_MARK may use HL/DE.
        LD HL,(SRTMVAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTQCAR),DE
        LD HL,(SRTMVAL)
        LD DE,CDR_LO
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTQCDR),DE
        LD HL,(SRTMVAL)
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        LD (SRTQFLG),A
        AND 0FH                     ; The CAR tag occupies its cell metadata nibble.
        LD (SRTQCTAG),A
        LD HL,(SRTMVAL)
        LD DE,CDR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 0FH                     ; The CDR tag occupies its cell metadata nibble.
        LD (SRTQDTAG),A
        LD A,(SRTQCTAG)
        LD HL,(SRTQCAR)
        CALL GC_VALUE                ; Trace pair or closure CAR values.
.CDR:
        LD A,(SRTQDTAG)
        LD HL,(SRTQCDR)
        JP GC_VALUE

; Write a value using CP/M function two, including nested pair structure.
