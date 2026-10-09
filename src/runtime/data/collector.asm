; Pair marking, root scanning and collector passes.
; Entry points: GC, ROOT_ALL, GC_MARK and GC_DRAIN.
; Included in runtime order by ../data.asm.

; Stop-the-world mark-and-sweep for every eight-byte pair slab.  Root discovery
; is exact: compiler-patched static records, active value stacks, frames and
; construction scratch are visited by type rather than by byte pattern.
GC:
        LD HL,(CNT_GC)             ; Count a complete stop-the-world cycle.
        INC HL
        LD (CNT_GC),HL
        CALL GC_CLEAR               ; Clear only mark bits from the last cycle.
        CALL GC_RESET               ; Start this collection with an empty mark map.
        LD HL,RT_GCLO               ; Restart the bounded pair worklist.
        LD (GC_QTOP),HL             ; The next mark is written at its base.
        XOR A
        LD (GC_OVER),A              ; No queue overflow has occurred yet.
        LD (GC_FOUND),A             ; Clear the fallback pass indicator.
        CALL ROOT_ALL               ; Visit only declared live value locations.
        CALL GC_DRAIN               ; Process every queued object before overflow checks.
        LD A,(GC_OVER)
        OR A
        JR Z,.SWEEP                 ; A complete queue has visited every reachable edge.
.FALLBACK:
        XOR A
        LD (GC_FOUND),A             ; Report only marks created by this fallback pass.
        CALL GC_PAIRS               ; Visit every marked pair to recover missed edges.
        CALL GC_OBJS                ; Visit every marked closure without recursion.
        CALL GC_DRAIN               ; Process entries found by the fallback scan.
        LD A,(GC_FOUND)
        OR A
        JR NZ,.FALLBACK             ; Continue until a fixed point is reached.
.SWEEP:
        CALL GC_CELLS               ; Reclaim dead four-byte bindings.
        CALL SLAB_GC                ; Reclaim dead rounded closure blocks.
        CALL GC_SWEEP              ; Rebuild free records and clear surviving marks.
        LD A,1                     ; An allocation that still finds no room may
        LD (PAGE_HRD),A           ; now take a page past the soft line.
        RET

; Mark the two typed inputs held across an allocation retry.  These roots use
; their own storage because the ordinary pair tracing scratch is overwritten
; while a queued pair is being inspected.
GC_CONS:
        LD A,(GC_HOLD)
        OR A
        RET Z
        LD A,(GC_CTAG)
        LD HL,(GC_CAR)
        CALL GC_VALUE
.CDR:
        LD A,(GC_DTAG)
        LD HL,(GC_CDR)
        JP GC_VALUE

; Clear mark bits in every allocated or free record before tracing.
GC_CLEAR:
        LD A,(PS_COUNT)
        OR A
        RET Z
        LD B,A                      ; B counts the pair slabs.
        LD HL,PS_TABLE
.SLAB:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,.SKIP                  ; Skip holes without scanning address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (PS_SAVE),HL
        LD (PS_BASE),DE
        LD (PS_RECP),DE
        LD C,PAIR_CAP               ; Each page contains 32 eight-byte records.
.RECORD:
        LD HL,(PS_RECP)
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 7FH                     ; Preserve tags and allocation, clear marking.
        LD (HL),A
        LD HL,(PS_RECP)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (PS_RECP),HL
        DEC C
        JR NZ,.RECORD
        LD HL,(PS_SAVE)
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
        LD A,(PS_COUNT)
        OR A
        RET Z
        LD B,A
        LD HL,PS_TABLE
.SLAB:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,.SKIP                  ; Skip holes without sweeping address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (PS_SAVE),HL
        LD (PS_BASE),DE
        LD (PS_RECP),DE
        LD C,PAIR_CAP
.RECORD:
        LD HL,(PS_RECP)
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
        LD HL,(PS_RECP)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (PS_RECP),HL
        DEC C
        JR NZ,.RECORD
        LD HL,(PS_SAVE)
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
        LD HL,(GC_QTOP)
        LD DE,RT_GCLO
        OR A
        SBC HL,DE
        RET Z
        LD HL,(GC_QTOP)
        LD DE,2
        OR A
        SBC HL,DE
        LD (GC_QTOP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        ; The shared pool no longer assigns closures a fixed address band.
        ; Consult the exact closure-start map instead of guessing from H.
        LD (CL_OBJ),HL
        PUSH HL
        CALL GC_ISOBJ
        POP HL
        JR Z,.PAIR
        XOR A
        CALL VEC_HOOK
        JR GC_DRAIN
.PAIR:
        LD A,1
        CALL GC_EDGES
        JR GC_DRAIN

; Scan every marked pair after the bounded queue has overflowed.  Repeated
; passes compute the same fixed point as an unbounded worklist.
GC_PAIRS:
        LD A,(PS_COUNT)
        OR A
        RET Z
        LD B,A
        LD HL,PS_TABLE
.SLAB:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,.SKIP                 ; Skip holes without scanning address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (PS_SAVE),HL
        LD (PS_BASE),DE
        LD (PS_RECP),DE
        LD C,PAIR_CAP
.RECORD:
        LD HL,(PS_RECP)
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 80H                     ; Only marked records need another visit.
        JR Z,.NEXT
        LD DE,(PS_SAVE)             ; Preserve the fallback cursor across validation.
        LD (GC_FDESC),DE
        LD DE,(PS_BASE)
        LD (GC_FBASE),DE
        LD DE,(PS_RECP)
        LD (GC_FREC),DE
        PUSH BC                     ; Preserve both slab and record counters.
        PUSH HL                     ; Preserve the record address across tracing.
        LD HL,(PS_RECP)
        CALL GC_EDGES               ; The queued value is the record start.
        POP HL
        POP BC
        LD DE,(GC_FDESC)            ; Restore the slab cursor changed by PAIR_CHK.
        LD (PS_SAVE),DE
        LD DE,(GC_FBASE)
        LD (PS_BASE),DE
        LD DE,(GC_FREC)
        LD (PS_RECP),DE
.NEXT:
        LD HL,(PS_RECP)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (PS_RECP),HL
        DEC C
        JR NZ,.RECORD
        LD HL,(PS_SAVE)
        DJNZ .SLAB
        RET
.SKIP:
        LD DE,3                     ; Advance over a released descriptor slot.
        ADD HL,DE
        DJNZ .SLAB
        RET

; Mark one pair and queue it for child scanning.
GC_MARK:
        LD A,1                      ; Validate the candidate as a pair value.
        CALL PAIR_CHK
        RET C
        LD HL,(PS_PAIR)             ; Recover the validated record address.
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
        LD (GC_FOUND),A            ; This object must be visited by the trace.
        LD HL,(PS_PAIR)             ; Queue the record address, not its state byte.
        LD DE,(GC_QTOP)
        LD A,D
        CP RT_GCHI/256
        JR NC,.FULL                ; Preserve the mark and defer its children.
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
        LD (GC_OVER),A             ; The fallback scanner will revisit marked pairs.
        RET

; Trace the CAR and CDR pair edges of one queued record.
GC_EDGES:
        LD (GC_QPAIR),HL
        LD A,1
        CALL PAIR_CHK
        RET C
        ; Copy both payloads before marking either edge; GC_MARK may use HL/DE.
        LD HL,(GC_QPAIR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (QT_CAR),DE
        LD HL,(GC_QPAIR)
        LD DE,CDR_LO
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (QT_CDR),DE
        LD HL,(GC_QPAIR)
        LD DE,CAR_TAG
        ADD HL,DE
        LD A,(HL)
        LD (QT_FLAGS),A
        AND 0FH                     ; The CAR tag occupies its cell metadata nibble.
        LD (QT_CTAG),A
        LD HL,(GC_QPAIR)
        LD DE,CDR_TAG
        ADD HL,DE
        LD A,(HL)
        AND 0FH                     ; The CDR tag occupies its cell metadata nibble.
        LD (QT_DTAG),A
        LD A,(QT_CTAG)
        LD HL,(QT_CAR)
        CALL GC_VALUE                ; Trace pair or closure CAR values.
.CDR:
        LD A,(QT_DTAG)
        LD HL,(QT_CDR)
        JP GC_VALUE

; Write a value using CP/M function two, including nested pair structure.
