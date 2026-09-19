;=============================================================================
;  Skate M3 precise, non-moving collector
;=============================================================================

;  PURPOSE
;  -------
;  Trace explicit roots and return unreachable cells to the allocator.

;  PUBLIC INTERFACE
;  ----------------
;

;+---------------------------------------------------------------------------+
;|  GCSET - Install a checked mark-bitmap configuration.                     |
;|                                                                           |
;|  CALL                                                                     |
;|    HL = bitmap base.                                                      |
;|    BC = exact capacity: ceil(HCOUNT / 8) bytes.                           |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  GCCOLL - Trace roots and reclaim unreachable cells.                      |
;|                                                                           |
;|  CALL                                                                     |
;|    HL = root-descriptor base; BC = descriptor count.                      |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    HL = number of free cells.                                             |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  GRES - Reserve cells described by caller-supplied roots.                 |
;|                                                                           |
;|  CALL                                                                     |
;|    BC = requested cell count.                                             |
;|    HL = root-descriptor base; DE = descriptor count.                      |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    Reservation opens for the caller to populate and publish.              |
;+---------------------------------------------------------------------------+

;  SHARED RESULTS AND STATE
;  ------------------------
;
;  PRESERVES  IX, IY and SP in every entry.
;  CLOBBERS   AF, BC, DE and HL except for stated results.
;  SUCCESS    A = 0; carry clear.
;  ERRORS     Carry set; A identifies the cause:
;              1 capacity; 2 bounds; 3 protocol/configuration;
;              4 reachable-encoding invariant.
;
;  LIMITS     No interrupt-time entry; static scratch is non-reentrant.
;  WRITES     Marking changes bitmap/scratch; sweep alone changes the arena.
;  MEMORY     Keep code, state, heap, bitmap, roots and stack disjoint.
;  DETAILS    Full calling and memory-map contracts are in docs/collector.md.
;=============================================================================

; Install the bitmap: HL=base, BC=exact ceil(HCOUNT/8) byte capacity.
; Validate first; only GCCOMMIT changes the durable configuration.
; A carry from the exclusive-end sum is valid only if the result is zero.
GCSET:
    LD (GCCANDTB),HL          ; Save candidate bitmap base.
    LD (GCCANDSZ),BC          ; Save candidate bitmap capacity.
    CALL GCPROTCK             ; Check allocator protocol before any tracing.
    RET C                   ; Return a protocol failure without installing configuration.
    LD HL,(HCOUNT)          ; Load physical arena cell count, including cell zero.
    LD DE,7                 ; Round the cell count up before division by eight.
    ADD HL,DE               ; HL=HCOUNT+7; the maximum HCOUNT is 8192.
    SRL H                   ; Shift the high half of the bitmap-size numerator.
    RR L                    ; Carry the high-half bit into the low half.
    SRL H                   ; Shift the high half of the bitmap-size numerator.
    RR L                    ; Carry the high-half bit into the low half.
    SRL H                   ; Shift the high half of the bitmap-size numerator.
    RR L                    ; Carry the high-half bit into the low half.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,BC               ; Compare required bitmap bytes with supplied capacity.
    JP NZ,GCRANGE            ; Reject both undersized and oversized bitmaps.
    LD HL,(GCCANDTB)          ; Load candidate bitmap base.
    ADD HL,BC               ; Form the exclusive bitmap end; carry means 64 KiB wrap.
    JP NC,GCCOMMIT             ; An unwrapped exclusive end fits.
    LD A,H
    OR L                    ; A wrapped end is valid only when both bytes are zero.
    JP NZ,GCRANGE            ; Reject a bitmap extending beyond address 65535.

; Commit the checked bitmap and the arena geometry it describes.
GCCOMMIT:
    LD HL,(GCCANDTB)          ; Load candidate bitmap base.
    LD (GCMBASE),HL           ; Save installed bitmap base address.
    LD HL,(GCCANDSZ)          ; Load candidate bitmap capacity.
    LD (GCMSIZE),HL          ; Save installed bitmap byte count.
    LD HL,(HBASE)           ; Load arena base address.
    LD (GCHBASE),HL           ; Save arena base recorded at configuration.
    LD HL,(HCOUNT)          ; Load physical arena cell count, including cell zero.
    LD (GCHCOUNT),HL           ; Save arena cell count recorded at configuration.
    LD A,1                  ; Mark the checked configuration as installed.
    LD (GCCONFIG),A          ; Save collector configuration installed flag.
    JP GCOKAY

; Shared protocol guard. Collection and configuration require an initialized
; allocator with no open reservation. BC, DE and HL survive this helper.
GCPROTCK:
    LD A,(HREADY)           ; Load allocator initialization flag.
    OR A                    ; Test whether allocator initialization is missing.
    JP Z,GCPROTO
    LD A,(HACTIVE)          ; Load active reservation flag.
    OR A                    ; Test whether a reservation is still open.
    JP NZ,GCPROTO
    JP GCOKAY

; Collect from BC six-byte descriptors at HL. Success returns HL=free cells.
; Validate roots and trace the reachable graph before changing any heap byte.
; Errors may leave bitmap/scratch changes, but sweep has not begun.
GCCOLL:
    LD (GCDSPTR),HL           ; Save next root descriptor address.
    LD (GCDLEFT),BC          ; Save root descriptors remaining.
    CALL GCPROTCK             ; Check allocator protocol before any tracing.
    RET C                   ; Propagate the error before sweep can alter heap cells.
    LD A,(GCCONFIG)          ; Load collector configuration installed flag.
    OR A                    ; Test whether bitmap configuration is installed.
    JP Z,GCPROTO
    LD HL,(HBASE)           ; Load arena base address.
    LD DE,(GCHBASE)           ; Load arena base recorded at configuration.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,DE               ; Require the configured arena base to match HBASE.
    JP NZ,GCPROTO
    LD HL,(HCOUNT)          ; Load physical arena cell count, including cell zero.
    LD DE,(GCHCOUNT)           ; Load arena cell count recorded at configuration.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,DE               ; Require the configured cell count to match HCOUNT.
    JP NZ,GCPROTO
    ; Validate the complete descriptor extent before reading any metadata.
    LD HL,(GCDLEFT)          ; Load root descriptors remaining.
    LD A,H
    OR L                    ; Test whether the descriptor count is zero.
    JP Z,GCDVALID
    LD DE,10923             ; Six bytes each: 10923 descriptors exceed 64 KiB.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,DE               ; Compare the descriptor count with the first excessive count.
    JP NC,GCRANGE
    LD HL,(GCDLEFT)          ; Load root descriptors remaining.
    ADD HL,HL               ; HL=2*n descriptor bytes.
    LD D,H                  ; Save the high byte of 2*n.
    LD E,L                  ; Save the low byte of 2*n.
    ADD HL,HL               ; HL=4*n; DE still holds 2*n.
    ADD HL,DE               ; HL=6*n, the complete descriptor byte count.
    LD DE,(GCDSPTR)           ; Load next root descriptor address.
    ADD HL,DE               ; Add the descriptor base to form the exclusive end.
    JP NC,GCDVALID           ; The descriptor extent fits without wrapping.
    LD A,H
    OR L                    ; A wrapped exclusive end must be exactly zero.
    JP NZ,GCRANGE

; The complete descriptor array fits. Reset tracing state before reading roots.
GCDVALID:
    CALL GCCLEAR             ; Clear every configured bitmap byte.
    LD HL,0                 ; Start with no pending work and no fallback passes.
    LD (GCQCOUNT),HL           ; Save pending worklist entry count.
    LD (GCPASSES),HL         ; Save fallback pass count.
    XOR A                   ; Clear both overflow and fallback mode.
    LD (GCQOVFL),A            ; Save worklist overflow flag.
    LD (GCFALLBK),A            ; Save fallback mode flag.

; Read one descriptor: slot address, slot count, stride (little-endian words).
; GCDSPTR may wrap after the final descriptor, because GCDLEFT then reaches zero.
GCDLOOP:
    LD HL,(GCDLEFT)          ; Load root descriptors remaining.
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCQDRAIN
    LD HL,(GCDSPTR)           ; Load next root descriptor address.
    LD DE,5                 ; The final descriptor byte is five bytes past its base.
    ADD HL,DE               ; Check the last descriptor byte before its first read.
    JP C,GCRANGE
    LD HL,(GCDSPTR)           ; Load next root descriptor address.
    LD E,(HL)               ; Read the slot-base low byte.
    INC HL                  ; Advance to the next byte of the six-byte descriptor.
    LD D,(HL)               ; Read the slot-base high byte.
    INC HL                  ; Advance to the next byte of the six-byte descriptor.
    LD (GCRSPTR),DE           ; Save current root slot address.
    LD E,(HL)               ; Read the slot-count low byte.
    INC HL                  ; Advance to the next byte of the six-byte descriptor.
    LD D,(HL)               ; Read the slot-count high byte.
    INC HL                  ; Advance to the next byte of the six-byte descriptor.
    LD (GCRLEFT),DE          ; Save root slots remaining.
    LD E,(HL)               ; Read the stride low byte.
    INC HL                  ; Advance to the next byte of the six-byte descriptor.
    LD D,(HL)               ; Read the stride high byte.
    INC HL                  ; Advance to the next byte of the six-byte descriptor.
    LD (GCRSTRID),DE         ; Save bytes between root slots.
    LD (GCDSPTR),HL           ; Save next root descriptor address.
    LD HL,(GCDLEFT)          ; Load root descriptors remaining.
    DEC HL                  ; Account for the descriptor just decoded.
    LD (GCDLEFT),HL          ; Save root descriptors remaining.
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCDESCOK             ; The final descriptor may leave a wrapped next pointer.
    LD HL,(GCDSPTR)           ; Load next root descriptor address.
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCRANGE             ; A wrapped pointer cannot address a further descriptor.

; An empty root span ignores both its slot pointer and stride. For a nonempty
; span, prove the entire extent before reading the first logical value.
GCDESCOK:
    LD HL,(GCRLEFT)          ; Load root slots remaining.
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCDLOOP
    LD HL,(GCRSTRID)         ; Load bytes between root slots.
    LD DE,4                 ; A root slot occupies four bytes.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,DE               ; Compare the slot stride with its four-byte minimum.
    JP C,GCRANGE             ; Reject overlapping or undersized slot strides.
    ; Bound all strided slots before interpreting the first tag. The maximum
    ; count follows from four-byte minimum slots in a 65536-byte address space.
    LD HL,(GCRLEFT)          ; Load root slots remaining.
    LD DE,16385             ; At most 16384 four-byte slots fit in 64 KiB.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,DE               ; Compare slot count with the first excessive count.
    JP NC,GCRANGE            ; Reject a count above the address-space maximum.
    LD BC,(GCRLEFT)          ; Load root slots remaining.
    DEC BC                  ; The first slot needs no stride advance.
    LD HL,(GCRSPTR)           ; Load current root slot address.
    LD DE,(GCRSTRID)         ; Load bytes between root slots.

; HL is the candidate last-slot address; BC counts remaining stride advances.
; Checked repeated addition avoids a wider multiply and catches every wrap.
GCRSLBND:
    LD A,B
    OR C                    ; Set Z only if the complete BC count is zero.
    JP Z,GCRSLEND
    ADD HL,DE               ; Advance the candidate last address by one stride.
    JP C,GCRANGE             ; Reject a span that crosses the address-space end.
    DEC BC                  ; One fewer stride advance remains.
    JP GCRSLBND

; HL now addresses the last slot. Its padding byte at HL+3 must also fit.
GCRSLEND:
    LD DE,3                 ; Include the final slot padding byte.
    ADD HL,DE               ; Form the final byte address, not the exclusive end.
    JP C,GCRANGE             ; That actual byte address must not wrap.

; A root slot is [tag, payload low, payload high, zero padding].
; Check padding, then pass the logical value in A:HL to the edge decoder.
GCRSLOOP:
    LD HL,(GCRSPTR)           ; Load current root slot address.
    LD DE,3                 ; Padding is the fourth byte of the root slot.
    ADD HL,DE               ; Locate padding before interpreting the tag.
    JP C,GCRANGE
    LD A,(HL)               ; Read the mandatory zero padding byte.
    OR A                    ; Require a zero root-slot padding byte.
    JP NZ,GCINVAR            ; A root slot must have zero padding.
    LD HL,(GCRSPTR)           ; Load current root slot address.
    LD A,(HL)               ; Read the logical value tag.
    INC HL                  ; Advance from the tag to payload low byte.
    LD E,(HL)               ; Read payload low byte.
    INC HL                  ; Advance to payload high byte.
    LD D,(HL)               ; Read payload high byte.
    EX DE,HL                ; Pass the assembled payload in HL, retaining tag A.
    CALL GCVALUE             ; Decode the logical value and mark any heap edge.
    RET C                   ; Propagate the error before sweep can alter heap cells.
    LD HL,(GCRLEFT)          ; Load root slots remaining.
    DEC HL                  ; Consume the slot just traced.
    LD (GCRLEFT),HL          ; Save root slots remaining.
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCDLOOP             ; A final slot needs no next-address calculation.
    LD HL,(GCRSPTR)           ; Load current root slot address.
    LD DE,(GCRSTRID)         ; Load bytes between root slots.
    ADD HL,DE               ; Advance from this slot base by the configured stride.
    JP C,GCRANGE
    LD (GCRSPTR),HL           ; Save current root slot address.
    JP GCRSLOOP

; Drain the worklist as a LIFO stack. Entries were marked before insertion,
; so a cycle cannot continually enqueue the same cell.
GCQDRAIN:
    LD HL,(GCQCOUNT)           ; Load pending worklist entry count.
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCQDONE
    DEC HL                  ; Pop the last occupied entry, numbered count-1.
    LD (GCQCOUNT),HL           ; Save pending worklist entry count.
    ADD HL,HL               ; Each worklist index occupies two bytes.
    LD DE,GCQUEUE            ; Use the fixed worklist buffer base.
    ADD HL,DE               ; Address the popped index.
    LD E,(HL)               ; Read the pending index low byte.
    INC HL                  ; Advance to the pending index high byte.
    LD D,(HL)               ; Read the pending index high byte.
    EX DE,HL                ; Pass the pending cell index to GCSCANCL.
    CALL GCSCANCL              ; Trace the outgoing edges of this marked cell.
    RET C                   ; Propagate the error before sweep can alter heap cells.
    JP GCQDRAIN

; Every queued cell has been scanned. A dropped queue entry still has its
; mark bit; overflow therefore requires full marked-cell passes before sweep.
GCQDONE:
    LD A,(GCQOVFL)            ; Load worklist overflow flag.
    OR A                    ; Test whether any pending entry was dropped.
    JP Z,GCSWEEP             ; No dropped entries: queued tracing was complete.
    LD A,1                  ; Enable scans that add marks without queue insertion.
    LD (GCFALLBK),A            ; Save fallback mode flag.

; Fallback computes reachability to a fixed point. Each pass scans marked
; cells in increasing index order. A newly marked lower index is scanned on
; a later pass; termination requires a whole pass with no new marks.
GCFBPASS:
    LD HL,(GCPASSES)         ; Load fallback pass count.
    INC HL                  ; Count this fallback pass, including the final unchanged one.
    LD (GCPASSES),HL         ; Save fallback pass count.
    XOR A                   ; No new mark has yet been added during this pass.
    LD (GCCHANGE),A          ; Save new-mark flag for this pass.
    LD HL,1                 ; Start at the first usable cell, skipping reserved zero.
    LD (GCINDEX),HL           ; Save current arena index.

; Test this cell in the bitmap and scan its outgoing edges only if marked.
GCFBLOOP:
    LD HL,(GCINDEX)           ; Load current arena index.
    CALL GCBITMSK               ; Get the bitmap byte address and bit mask for this index.
    LD A,(HL)
    AND B                   ; Test this cell's mark bit.
    JP Z,GCFBNEXT             ; Skip cells not marked yet.
    LD HL,(GCINDEX)           ; Load current arena index.
    CALL GCSCANCL              ; Trace the outgoing edges of this marked cell.
    RET C                   ; Propagate the error before sweep can alter heap cells.

; Advance through usable cells 1..HCOUNT-1, then test whether marks changed.
GCFBNEXT:
    LD HL,(GCINDEX)           ; Load current arena index.
    INC HL                  ; Advance to the next physical index.
    LD (GCINDEX),HL           ; Save current arena index.
    LD DE,(HCOUNT)          ; Load physical arena cell count, including cell zero.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,DE               ; Compare next index with the exclusive arena bound.
    JP NZ,GCFBLOOP
    LD A,(GCCHANGE)          ; Load new-mark flag for this pass.
    OR A                    ; Test whether this pass added any marks.
    JP NZ,GCFBPASS             ; New marks require another complete scan.

; Tracing completed successfully. Rebuild the free list from all unmarked
; cells, walking downwards so prepending produces increasing index order.
; This is the only phase that writes arena bytes; live cells remain untouched.
GCSWEEP:
    LD HL,0                 ; Start a new empty free list.
    LD (HHEAD),HL           ; Save free-list head index.
    LD (HFCOUNT),HL         ; Save free cell count.
    LD HL,(HCOUNT)          ; Load physical arena cell count, including cell zero.
    DEC HL                  ; Start from the highest usable index.
    LD (GCINDEX),HL           ; Save current arena index.

; A set bitmap bit protects all four bytes of this cell. An unmarked cell
; becomes [next free index, zero word] regardless of its previous encoding.
GCSWLOOP:
    LD HL,(GCINDEX)           ; Load current arena index.
    CALL GCBITMSK               ; Get the bitmap byte address and bit mask for this index.
    LD A,(HL)
    AND B                   ; Test whether this cell is reachable.
    JP NZ,GCSWNEXT           ; Preserve all bytes of a live cell.
    LD HL,(GCINDEX)           ; Load current arena index.
    CALL GCELLADR              ; Convert the cell index to its arena byte address.
    LD DE,(HHEAD)           ; Load free-list head index.
    LD (HL),E               ; Write the old free head into word zero, low byte.
    INC HL                  ; Advance to the next-index high byte.
    LD (HL),D               ; Write the old free head high byte.
    INC HL                  ; Advance to the second word low byte.
    XOR A                   ; Free cells have a zero second word.
    LD (HL),A               ; Clear this byte of the free-cell second word.
    INC HL                  ; Advance to the second word high byte.
    LD (HL),A               ; Clear this byte of the free-cell second word.
    LD HL,(GCINDEX)           ; Load current arena index.
    LD (HHEAD),HL           ; Save free-list head index.
    LD HL,(HFCOUNT)         ; Load free cell count.
    INC HL                  ; Count the newly reclaimed cell.
    LD (HFCOUNT),HL         ; Save free cell count.

; Stop at index zero: the reserved cell is never part of the free list.
GCSWNEXT:
    LD HL,(GCINDEX)           ; Load current arena index.
    DEC HL                  ; Move to the preceding cell index.
    LD (GCINDEX),HL           ; Save current arena index.
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP NZ,GCSWLOOP           ; Continue while the index is nonzero.
    CALL GCCLEAR             ; Clear every configured bitmap byte.
    LD HL,(HFCOUNT)         ; Load free cell count.
    JP GCOKAY

; Decode A=logical tag, HL=payload. Scalars and exact integers have no edges,
; even when their bits resemble a reference. Permanent symbols and strings
; also have no arena edge. Pair, closure and environment references do.
GCVALUE:
    OR A                    ; Test for logical tag zero (scalar).
    JP Z,GCOKAY                ; A scalar payload has no heap edge.
    CP 3                    ; Exact-integer logical tag.
    JP Z,GCOKAY                ; An exact-integer payload has no heap edge.
    CP 1                    ; All remaining valid logical values must be references.
    JP NZ,GCINVAR            ; Reject all other logical tags.
    LD A,H
    AND 0E0H                ; Extract the three-bit reference subtype.
    CP 20H                  ; Subtype 1: permanent symbol table.
    JP Z,GCOKAY                ; A permanent symbol has no arena edge.
    CP 80H                  ; Subtype 4: permanent string table.
    JP Z,GCOKAY                ; A permanent string has no arena edge.
    CP 40H                  ; Subtype 2: heap closure.
    JP Z,GCHEAPV
    CP 60H                  ; Subtype 3: heap environment.
    JP Z,GCHEAPV
    OR A                    ; Test for the remaining valid subtype zero (pair).
    JP NZ,GCINVAR            ; Only subtype zero (pair) remains valid here.

; Remove the three subtype bits, leaving a mandatory nonzero heap index.
GCHEAPV:
    LD A,H
    AND 1FH                 ; Keep only payload index bits 12..8.
    LD H,A                  ; Recombine the thirteen-bit index in HL.
    JP GCMARK

; An internal link may be zero (end of chain); a logical reference may not.
GCLINK:
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCOKAY                ; Zero terminates an internal cell chain.

; Validate and mark HL=index. Marking precedes queue insertion, so sharing
; and cycles cannot duplicate work. A full queue drops only the entry, never
; its mark; fallback later scans all marked cells.
GCMARK:
    LD A,H
    OR L                    ; Set Z only if the complete HL value is zero.
    JP Z,GCINVAR             ; A heap reference may not target reserved index zero.
    LD (GCMARKIX),HL           ; Save index being marked.
    LD DE,(HCOUNT)          ; Load physical arena cell count, including cell zero.
    OR A                    ; Clear carry so SBC compares without an incoming borrow.
    SBC HL,DE               ; Compare the candidate index against HCOUNT.
    JP NC,GCINVAR            ; Indices must be strictly below HCOUNT.
    LD HL,(GCMARKIX)           ; Load index being marked.
    CALL GCBITMSK               ; Get the bitmap byte address and bit mask for this index.
    LD A,(HL)
    AND B                   ; Test whether this cell has already been marked.
    JP NZ,GCOKAY               ; Already marked: no new mark or queue entry needed.
    LD A,(HL)
    OR B                    ; Set this cell's bit while preserving adjacent marks.
    LD (HL),A               ; Publish the mark before attempting to enqueue.
    LD A,1                  ; Record that reachability grew.
    LD (GCCHANGE),A          ; Save new-mark flag for this pass.
    LD A,(GCFALLBK)            ; Load fallback mode flag.
    OR A                    ; Test whether fallback scanning is active.
    JP NZ,GCOKAY               ; Fallback scans marked cells directly, without queue insertion.
    LD HL,(GCQCOUNT)           ; Load pending worklist entry count.
    LD A,L                  ; Queue length is bounded by 128, so its low byte suffices.
    CP 128                  ; All 128 pending-entry slots may already be occupied.
    JP Z,GCQFULL             ; Retain the mark and flag overflow when the queue is full.
    INC HL                  ; Reserve one pending-entry slot.
    LD (GCQCOUNT),HL           ; Save pending worklist entry count.
    DEC HL                  ; Recover its zero-based slot number.
    ADD HL,HL               ; Convert entry number to two-byte offset.
    LD DE,GCQUEUE            ; Base address of the pending-entry buffer.
    ADD HL,DE               ; Locate the newly reserved entry.
    LD DE,(GCMARKIX)           ; Load index being marked.
    LD (HL),E               ; Store the marked index low byte.
    INC HL                  ; Advance to the queued index high byte.
    LD (HL),D               ; Store the marked index high byte.
    JP GCOKAY

; Record overflow without losing the new mark or reporting an allocation error.
GCQFULL:
    LD A,1                  ; A full marked-cell scan will be required after draining.
    LD (GCQOVFL),A            ; Save worklist overflow flag.
    JP GCOKAY

; Map HL=cell index to HL=bitmap byte address and B=one-bit mask.
; The low three index bits select the bit; the remaining bits select the byte.
GCBITMSK:
    LD A,L                  ; Bit position depends only on the low index byte.
    AND 7                   ; Index modulo eight selects the bit within its byte.
    LD B,1                  ; Begin with the mask for bit zero.

; Shift the initial mask left by the bit position held in A.
GCBITSHF:
    OR A                    ; Test whether all requested mask shifts are complete.
    JP Z,GCBITADR             ; The mask has reached its requested bit position.
    SLA B                   ; Move the one-bit mask to the next position.
    DEC A                   ; One fewer mask shift remains.
    JP GCBITSHF

; Divide the full 16-bit index by eight; each SRL H / RR L pair is one
; unsigned right shift, with carry transferring H bit zero into L bit seven.
GCBITADR:
    SRL H                   ; Shift the high byte of the unsigned index.
    RR L                    ; Carry the high-byte bit into the low byte.
    SRL H                   ; Shift the high byte of the unsigned index.
    RR L                    ; Carry the high-byte bit into the low byte.
    SRL H                   ; Shift the high byte of the unsigned index.
    RR L                    ; Carry the high-byte bit into the low byte.
    LD DE,(GCMBASE)           ; Load installed bitmap base address.
    ADD HL,DE               ; Add the bitmap base to index divided by eight.
    RET

; Map a previously validated cell index in HL to arena base + 4*index.
GCELLADR:
    ADD HL,HL               ; HL=2*index.
    ADD HL,HL               ; HL=4*index, the byte offset of this cell.
    LD DE,(HBASE)           ; Load arena base address.
    ADD HL,DE               ; Add the arena base to the byte offset.
    RET

; Scan HL=marked cell index. Save payload and physical tag because edge
; marking clobbers the working registers. Marking never calls GCSCANCL itself,
; so these saved fields survive each edge call.
GCSCANCL:
    CALL GCELLADR              ; Convert the cell index to its arena byte address.
    LD E,(HL)               ; Read this cell word's low byte.
    INC HL                  ; Advance to word zero high byte.
    LD D,(HL)               ; Read this cell word's high byte.
    INC HL                  ; Advance to physical word one low byte.
    LD (GCCARVAL),DE            ; Save cell word zero / CAR payload.
    LD E,(HL)               ; Read this cell word's low byte.
    INC HL                  ; Advance to physical word one high byte.
    LD D,(HL)               ; Read this cell word's high byte.
    LD A,D                  ; Inspect the high byte of physical word one.
    AND 0E0H                ; Separate its physical tag from the link index.
    LD (GCPHYTAG),A            ; Save physical tag in bits 7..5.
    CP 0C0H                 ; Physical tag 6: auxiliary, scanned through its anchor.
    JP Z,GCOKAY                ; The auxiliary has no independently traced edges.
    CP 80H                  ; Physical tag 4 is invalid.
    JP Z,GCINVAR
    CP 0A0H                 ; Physical tag 5 is invalid.
    JP Z,GCINVAR
    LD A,D                  ; Inspect the high byte of physical word one.
    AND 1FH                 ; Extract the high five bits of the internal link.
    LD D,A                  ; DE now contains the thirteen-bit link index.
    EX DE,HL                ; Pass that link or auxiliary index in HL.
    LD A,(GCPHYTAG)            ; Load physical tag in bits 7..5.
    CP 0E0H                 ; Physical tag 7 requires escaped-pair decoding.
    JP Z,GCESCAPE               ; Decode both logical values through the auxiliary.
    CALL GCLINK              ; Trace the internal link, permitting zero as an end marker.
    RET C                   ; Propagate the error before sweep can alter heap cells.
    LD A,(GCPHYTAG)            ; Load physical tag in bits 7..5.
    CP 20H                  ; Physical tag 1 means word zero is a reference.
    JP NZ,GCOKAY               ; Scalar, raw-word and integer CAR payloads are data.
    LD HL,(GCCARVAL)            ; Load saved cell word zero / CAR payload.
    LD A,1                  ; Decode saved word zero as a logical reference.
    JP GCVALUE

; An escaped pair stores its CDR and both logical tags in an auxiliary cell.
; Mark that cell, validate its tag/reserved bits, then trace CAR and CDR.
; The auxiliary scanner itself has no edges; the anchor supplies their meaning.
GCESCAPE:
    LD (GCAUXIDX),HL            ; Save escaped auxiliary index.
    CALL GCMARK              ; Validate and mark the nonzero cell index.
    RET C                   ; Propagate the error before sweep can alter heap cells.
    LD HL,(GCAUXIDX)            ; Load escaped auxiliary index.
    CALL GCELLADR              ; Convert the cell index to its arena byte address.
    LD E,(HL)               ; Read the auxiliary word low byte.
    INC HL                  ; Advance to CDR payload high byte.
    LD D,(HL)               ; Read the auxiliary word high byte.
    INC HL                  ; Advance to auxiliary metadata low byte.
    LD (GCCDRVAL),DE            ; Save escaped CDR payload.
    LD E,(HL)               ; Read the auxiliary word low byte.
    INC HL                  ; Advance to auxiliary metadata high byte.
    LD D,(HL)               ; Read the auxiliary word high byte.
    LD A,D                  ; Validate the metadata high byte exactly.
    CP 0C0H                 ; Require auxiliary tag 6 and reserved bits 12..8 zero.
    JP NZ,GCINVAR
    LD A,E                  ; Use the metadata low byte containing both logical tags.
    AND 0C0H                ; Reserved metadata bits 7..6 must also be zero.
    JP NZ,GCINVAR
    LD A,E                  ; Use the metadata low byte containing both logical tags.
    AND 7                   ; Isolate the three-bit CDR logical tag.
    LD (GCCDRTAG),A            ; Save escaped CDR logical tag.
    LD A,E                  ; Use the metadata low byte containing both logical tags.
    SRL A                   ; Shift CAR tag bits 5..3 towards bits 2..0.
    SRL A                   ; Shift CAR tag bits 5..3 towards bits 2..0.
    SRL A                   ; Shift CAR tag bits 5..3 towards bits 2..0.
    AND 7                   ; Isolate the three-bit CAR logical tag.
    LD (GCCARTAG),A            ; Save escaped CAR logical tag.
    LD HL,(GCCARVAL)            ; Load saved cell word zero / CAR payload.
    LD A,(GCCARTAG)            ; Load escaped CAR logical tag.
    CALL GCVALUE             ; Decode the logical value and mark any heap edge.
    RET C                   ; Propagate the error before sweep can alter heap cells.
    LD HL,(GCCDRVAL)            ; Load saved escaped CDR payload.
    LD A,(GCCDRTAG)            ; Load escaped CDR logical tag.
    JP GCVALUE

; Clear the complete configured bitmap, including unused final-byte bits.
; GCSET guarantees a nonzero byte count because HCOUNT is at least two.
GCCLEAR:
    LD HL,(GCMBASE)           ; Load installed bitmap base address.
    LD BC,(GCMSIZE)          ; Load installed bitmap byte count.

; Write one bitmap byte and use BC as the remaining byte count.
GCCLLOOP:
    LD (HL),0               ; Clear eight cell marks at this bitmap address.
    INC HL                  ; Advance to the next bitmap byte.
    DEC BC                  ; Consume one byte from the configured extent.
    LD A,B                  ; Combine both count bytes for the termination test.
    OR C                    ; Set Z only when the full sixteen-bit count is zero.
    JP NZ,GCCLLOOP           ; Continue until the entire bitmap is clear.
    RET

; Reserve BC cells, using HL=descriptor base and DE=descriptor count if
; collection is needed. Only capacity failure permits one collection/retry.
; No cells are popped here, including when the final reservation fails.
GRES:
    LD (GCORIGCT),BC             ; Save original reservation cell count.
    LD (GCSAVDSC),HL          ; Save root descriptor base for retry.
    LD (GCSAVCNT),DE         ; Save descriptor count for retry.
    CALL HRES               ; Attempt the allocator reservation.
    RET NC                  ; An immediate reservation needs no collection.
    CP 1                    ; Only the capacity error permits collection.
    JP NZ,GCRESERR           ; Return all other HRES errors without collecting.
    LD HL,(GCSAVDSC)          ; Load saved root descriptor base for retry.
    LD BC,(GCSAVCNT)         ; Load saved descriptor count for retry.
    CALL GCCOLL             ; Reclaim unreachable cells using the saved root descriptors.
    RET C                   ; Return collection failure without retrying the reservation.
    LD BC,(GCORIGCT)             ; Load original reservation cell count.
    JP HRES                 ; Tail-call the single retry with the original cell count.

; CP changed carry while testing the HRES error code; restore failure carry
; while retaining that original error code in A.
GCRESERR:
    SCF                     ; Restore the failure flag destroyed by CP 1.
    RET

; Common success return: A=0, carry clear; preserve the result in HL.
GCOKAY:
    XOR A                   ; Return success code zero and clear carry together.
    RET

; Bounds/capacity encoding error: A=2, carry set.
GCRANGE:
    LD A,2
    SCF                     ; Carry marks this return as an error.
    RET

; Allocator protocol or missing/stale configuration: A=3, carry set.
GCPROTO:
    LD A,3
    SCF                     ; Carry marks this return as an error.
    RET

; Reachable root/cell encoding invariant failure: A=4, carry set.
GCINVAR:
    LD A,4
    SCF                     ; Carry marks this return as an error.
    RET
GCCODEND:

; Durable configuration first, then non-reentrant scratch and the worklist.
; Error returns may change scratch; the caller keeps this region disjoint
; from arena, bitmap, roots, code and native stack.
GCWORK:
GCMBASE: DW 0                 ; installed bitmap base address.
GCMSIZE: DW 0                ; installed bitmap byte count.
GCHBASE: DW 0                 ; arena base recorded at configuration.
GCHCOUNT: DW 0                 ; arena cell count recorded at configuration.
GCCONFIG: DB 0               ; collector configuration installed flag.
GCCANDTB: DW 0                ; candidate bitmap base.
GCCANDSZ: DW 0                ; candidate bitmap capacity.
GCDSPTR: DW 0                 ; next root descriptor address.
GCDLEFT: DW 0                ; root descriptors remaining.
GCRSPTR: DW 0                 ; current root slot address.
GCRLEFT: DW 0                ; root slots remaining.
GCRSTRID: DW 0               ; bytes between root slots.
GCQCOUNT: DW 0                 ; pending worklist entry count.
GCPASSES: DW 0               ; fallback pass count.
GCQOVFL: DB 0                 ; worklist overflow flag.
GCFALLBK: DB 0                 ; fallback mode flag.
GCCHANGE: DB 0               ; new-mark flag for this pass.
GCINDEX: DW 0                 ; current arena index.
GCMARKIX: DW 0                 ; index being marked.
GCCARVAL: DW 0                  ; saved cell word zero / CAR payload.
GCCDRVAL: DW 0                  ; saved escaped CDR payload.
GCAUXIDX: DW 0                  ; escaped auxiliary index.
GCPHYTAG: DB 0                 ; physical tag in bits 7..5.
GCCARTAG: DB 0                 ; escaped CAR logical tag.
GCCDRTAG: DB 0                 ; escaped CDR logical tag.
GCORIGCT: DW 0                   ; original reservation cell count.
GCSAVDSC: DW 0                ; saved root descriptor base for retry.
GCSAVCNT: DW 0               ; saved descriptor count for retry.
GCQUEUE: DS 256              ; 128 two-byte pending cell indices.
GCWEND:
