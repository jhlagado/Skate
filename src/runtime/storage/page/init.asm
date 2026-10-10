; Runtime page-domain initialisation and the collector maps' layout.
; PAGE_INI: HL = loaded image end; returns A=0/carry clear or A=2/carry set.
; PAGE_NEW: HL = page count; returns HL = page address or A=1 capacity,
; A=2 invalid request or A=3 uninitialised, with carry set.
; PAGE_REL: HL = page address, DE = count; returns A=0 or A=2 invalid request
; or A=3 uninitialised, with carry set.
;
; The heap starts at the first page after the image and ends at HEAP_LIM,
; where the stack starts.  The three collector maps cover exactly those
; pages, 40 bytes for each.  They go above the fixed bands, from RT_TOP to
; the BDOS, as far as they fit there, and below RT_OPLO otherwise; HEAP_LIM
; is the highest page that leaves room for those below.

PAGE_INI:
        XOR A                      ; Invalidate any previous domain before checks.
        LD (PAGE_OK),A             ; A failed reinitialisation must not leave it live.
        LD (PAGE_IMG),HL           ; Retain the exact unrounded image end.
        LD A,L                     ; The heap starts at the next page boundary.
        OR A
        JR Z,.ALIGNED
        INC H
.ALIGNED:
        LD L,0
        LD (PAGE_ORG),HL
        LD E,0                     ; E: whole pages free above the fixed bands.
        LD A,(0005H)
        CP 0C3H
        JR NZ,.ROOM                ; A bare provider host has no BDOS.
        LD A,(0007H)
        SUB RT_TOP/256
        JR C,.ROOM
        LD E,A
.ROOM:
        LD A,E
        ADD A,RT_TOP/256
        LD H,A
        LD L,0
        LD (MAP_HTOP),HL
        LD D,RT_OPLO/256           ; D: the candidate end page of the heap.
.TRY:
        LD A,(PAGE_ORG+1)
        LD B,A
        LD A,D
        SUB B
        JP C,PAGE_ERR
        CP 4                       ; Keep at least a few pages to work with.
        JP C,PAGE_ERR
        LD (MAP_PGS),A
        LD L,A                     ; Each page needs 16 bytes in CL_MAP and in
        LD H,0                     ; GC_MARKS, and 8 in BND_MAP.
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD (MAP_LEN),HL
        LD (MAP_SZ),HL
        LD HL,RT_TOP
        LD (MAP_HCUR),HL
        LD H,D
        LD L,0
        LD (HEAP_LIM),HL
        LD (MAP_LCUR),HL
        PUSH DE
        LD HL,CL_MAP
        CALL .PLACE
        LD HL,GC_MARKS
        CALL .PLACE
        LD HL,(MAP_SZ)
        SRL H
        RR L
        LD (MAP_SZ),HL
        LD HL,BND_MAP
        CALL .PLACE
        POP DE
        LD HL,(MAP_LCUR)           ; The maps below the bands must end by
        LD BC,RT_OPLO+1            ; RT_OPLO, or the heap gives up a page.
        OR A
        SBC HL,BC
        JR C,.CLEAR
        DEC D
        JR .TRY
.CLEAR:
        LD HL,(CL_MAP)
        LD BC,(MAP_LEN)
        CALL .WIPE
        LD HL,(GC_MARKS)
        LD BC,(MAP_LEN)
        CALL .WIPE
        LD HL,(BND_MAP)
        LD BC,(MAP_SZ)
        CALL .WIPE
        XOR A
        LD (PAGE_HI),A             ; There is no second extent.
        LD (PAGE_HI+1),A
        LD H,A
        LD A,(MAP_PGS)
        LD L,A
        LD (PAGE_LO),HL            ; Keep the low extent length for address mapping.
        LD DE,(PAGE_HI)            ; Add the configured pages after the map band.
        ADD HL,DE
        LD (PAGE_CNT),HL           ; Record both explicit extents as one index space.
        LD A,L                     ; Begin bitmap-byte calculation from the count.
        ADD A,7                     ; Round a partial bitmap byte upward.
        SRL A                      ; Divide the rounded count by two.
        SRL A                      ; Divide by four.
        SRL A                      ; Divide by eight to obtain bitmap bytes.
        LD L,A                     ; Widen the byte count to a word.
        XOR A                      ; The bitmap-byte count has no high byte.
        LD H,A                     ; Store the widened bitmap extent.
        LD (PAGE_LEN),HL           ; The directory follows this bitmap.
        LD DE,(PAGE_CNT)           ; Add one directory byte per managed page.
        ADD HL,DE                  ; HL now contains all management bytes.
        LD BC,255                  ; Round those bytes up to whole pages.
        ADD HL,BC                  ; The high byte is the number of metadata pages.
        LD A,H                     ; Read the rounded metadata-page count.
        LD L,A                     ; Keep it as a normal unsigned word.
        XOR A                      ; Metadata pages are below 256 for this domain.
        LD H,A                     ; Clear the high byte before storing the count.
        LD (PAGE_SYS),HL           ; Reserve these pages before setting free bits.
        LD DE,(PAGE_LO)            ; Metadata must fit in the low physical extent.
        LD A,L                     ; Compare the only nonzero count byte.
        CP E                       ; Metadata must fit inside the managed interval.
        JR C,.META_OK              ; A smaller metadata extent is valid.
        JR Z,.META_OK              ; Equal extents are valid but leave no free page.
        JP PAGE_ERR                ; A larger metadata extent is impossible.
.META_OK:
        LD HL,(PAGE_CNT)           ; Calculate the pages left for future classes.
        LD DE,(PAGE_SYS)           ; Remove the reserved management pages.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; The result is the initially free page count.
        LD DE,RT_EXTRA              ; Reserve the fixed upper metadata pages.
        SBC HL,DE                  ; Account for the reserved upper band.
        JP C,PAGE_ERR              ; A domain without object capacity is invalid.
        LD (PAGE_CAP),HL           ; Publish that capacity after validation.
        LD HL,(PAGE_ORG)           ; The bitmap starts at the first page.
        LD (PAGE_MAP),HL           ; Save the bitmap address for bit operations.
        LD HL,(PAGE_ORG)           ; Derive the directory address from the base.
        LD DE,(PAGE_LEN)           ; The bitmap occupies its calculated byte extent.
        ADD HL,DE                  ; The directory begins after those bitmap bytes.
        LD (PAGE_DIR),HL           ; Save the directory address for run checks.
        LD A,(PAGE_SYS)            ; Metadata pages advance the low extent base.
        LD E,A                     ; Keep the count while comparing its boundary.
        LD A,(PAGE_LO)             ; A full low extent has no low free page.
        CP E                        ; Equality means the first free page is high.
        JP Z,PAGE_ERR               ; No page is left for objects.
        LD HL,(PAGE_ORG)            ; Derive the first free low page otherwise.
        LD A,E                      ; Recover the reserved page count.
        ADD A,H                     ; Add it to the base page number.
        LD H,A                      ; The low byte remains zero for an aligned page.
        LD L,0                      ; Set the first free page address exactly.
        JR .FIRST                   ; Publish the low-extent boundary.
.FIRST:
        LD (PAGE_MIN),HL           ; Keep the lower boundary for release checks.
        LD HL,(PAGE_MAP)           ; Clear the complete bitmap before setting bits.
        LD BC,(PAGE_LEN)           ; BC counts every bitmap byte, including padding.
        XOR A                      ; Zero means allocated or reserved in the bitmap.
.CLR_MAP:
        XOR A                      ; Keep every cleared bitmap byte at zero.
        LD (HL),A                  ; Start with no page marked free.
        INC HL                     ; Advance to the following bitmap byte.
        DEC BC                     ; Consume one byte from the bounded extent.
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero count ends the clearing loop.
        JR NZ,.CLR_MAP             ; Continue until every bitmap byte is clear.
        LD HL,(PAGE_DIR)           ; Clear the per-page state directory.
        LD BC,(PAGE_CNT)           ; One byte describes every page in the domain.
        XOR A                      ; Zero denotes a free page in the directory.
.CLR_DIR:
        XOR A                      ; Keep every cleared directory byte at zero.
        LD (HL),A                  ; Clear the state before publishing readiness.
        INC HL                     ; Advance to the next directory byte.
        DEC BC                     ; Consume one page entry.
        LD A,B                     ; Check whether all directory entries are clear.
        OR C                       ; Z means the directory has been initialised.
        JR NZ,.CLR_DIR             ; Continue through the complete page domain.
        LD HL,(PAGE_DIR)           ; Mark the reserved management entries.
        LD BC,(PAGE_SYS)           ; BC counts the metadata pages at the front.
        LD A,2                     ; Directory state two means reserved metadata.
.RESERVE:
        LD A,2                     ; Restore the reserved state after the counter test.
        LD (HL),A                  ; Keep reserved pages out of allocation scans.
        INC HL                     ; Advance to the next reserved page entry.
        DEC BC                     ; Consume one metadata page.
        LD A,B                     ; Test whether all reserved entries were marked.
        OR C                       ; Zero ends the metadata reservation loop.
        JR NZ,.RESERVE             ; Continue while metadata pages remain.
        LD HL,(PAGE_SYS)           ; Begin setting free bits after reserved pages.
        LD (PAGE_IDX),HL           ; The bit helper reads this page index.
.FREE:
        LD HL,(PAGE_IDX)           ; Recover the next candidate page index.
        LD DE,(PAGE_CNT)           ; Compare it with the total page count.
        OR A                       ; Clear carry before the upper-bound compare.
        SBC HL,DE                  ; A carry-free result means the loop is done.
        JR NC,.UPPER               ; Do not set bitmap padding or reserved bits.
        CALL PAGE_SET              ; Mark this page free in the bitmap.
        LD HL,(PAGE_IDX)           ; Recover the index after the bit operation.
        INC HL                     ; Advance to the following page.
        LD (PAGE_IDX),HL           ; Publish the next initialization index.
        JR .FREE                   ; Continue through every usable page.
.UPPER:
        LD HL,(PAGE_LO)            ; The upper extent starts after the low pages.
        LD (PAGE_IDX),HL           ; Select its first virtual page for reservation.
        LD BC,RT_EXTRA              ; Reserve the fixed exact-root metadata band.
        LD A,B                     ; A zero count means the runtime image owns no band.
        OR C
        JR Z,.READY                 ; Do not enter the reservation loop at zero.
.UP_LOOP:
        CALL PAGE_CLR              ; Remove the upper metadata page from the bitmap.
        LD HL,(PAGE_DIR)           ; Locate the matching directory state.
        LD DE,(PAGE_IDX)           ; Add the virtual upper-page index.
        ADD HL,DE                  ; HL names the reserved directory entry.
        LD A,2                     ; State two is reserved metadata.
        LD (HL),A                  ; Keep the page out of future allocation scans.
        LD HL,(PAGE_IDX)           ; Advance to the following upper page.
        INC HL
        LD (PAGE_IDX),HL
        DEC BC                     ; Consume one reserved upper page.
        LD A,B
        OR C
        JP NZ,.UP_LOOP             ; Continue through all fixed metadata pages.
.READY:
        LD A,1                     ; Mark the state as ready for allocation calls.
        LD (PAGE_OK),A             ; A nonzero flag distinguishes a valid domain.
        XOR A                      ; Successful initialisation returns A=0.
        RET                        ; Carry remains clear from the final comparison.

; Place the map whose address variable is at HL, MAP_SZ bytes long, above
; the bands when it fits there, or else below them.
.PLACE:
        PUSH HL
        LD HL,(MAP_HCUR)
        LD DE,(MAP_SZ)
        ADD HL,DE
        EX DE,HL
        LD HL,(MAP_HTOP)
        OR A
        SBC HL,DE
        LD HL,MAP_HCUR
        JR NC,.PUT
        LD HL,MAP_LCUR
.PUT:
        LD E,(HL)                  ; DE: the chosen cursor.
        INC HL
        LD D,(HL)
        EX (SP),HL
        LD (HL),E                  ; The map starts there.
        INC HL
        LD (HL),D
        POP HL
        EX DE,HL
        LD BC,(MAP_SZ)
        ADD HL,BC
        EX DE,HL
        LD (HL),D                  ; Advance the cursor past the map.
        DEC HL
        LD (HL),E
        RET

; Clear BC bytes from HL; BC is at least 2.
.WIPE:
        LD (HL),0
        LD D,H
        LD E,L
        INC DE
        DEC BC
        LDIR
        RET
