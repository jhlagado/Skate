; Runtime page-domain initialisation and managed extents.
; PAGE_INI: HL = loaded image end; returns A=0/carry clear or A=2/carry set.
; PAGE_NEW: HL = page count; returns HL = page address or A=1 capacity,
; A=2 invalid request or A=3 uninitialised, with carry set.
; PAGE_REL: HL = page address, DE = count; returns A=0 or A=2 invalid request
; or A=3 uninitialised, with carry set. The pool owns the gap from the image
; to RT_LOEND (A500H); maps and exact roots occupy A500H..C000H.  The high
; extent starts at RT_HIGH, which is now C000H, so it holds no pages.

PAGE_INI:
        XOR A                      ; Invalidate any previous domain before checks.
        LD (PAGE_OK),A             ; A failed reinitialisation must not leave it live.
        LD (PAGE_IMG),HL           ; Retain the exact unrounded image end.
        LD HL,(HEAP_LIM)           ; The caller may select a lower managed ceiling.
        LD DE,RT_HIGH              ; It must still include the first high page.
        OR A                       ; Clear carry before the lower-bound check.
        SBC HL,DE
        JP C,PAGE_ERR              ; A ceiling inside the protected map band fails.
        LD A,L                     ; The ceiling must end on a page boundary.
        OR A
        JP NZ,PAGE_ERR
        LD HL,(HEAP_LIM)           ; Check the configured ceiling against the TPA map.
        LD DE,RT_HIEND
        OR A
        SBC HL,DE
        JR C,.TOP_OK
        JR Z,.TOP_OK
        JP PAGE_ERR                ; A ceiling above the qualified TPA is invalid.
.TOP_OK:
        LD HL,(HEAP_LIM)           ; Derive the number of pages after the map band.
        LD DE,RT_HIGH
        OR A
        SBC HL,DE
        LD A,H                     ; The high byte is the count of 256-byte pages.
        LD L,A
        XOR A
        LD H,A
        LD (PAGE_HI),HL            ; Keep the selected high extent in the domain.
        LD HL,(PAGE_IMG)           ; Recover the image end for the low-gap check.
        LD DE,RT_LOEND            ; The low extent ends at the upper band.
        OR A                       ; Clear carry before comparing the extent.
        SBC HL,DE                  ; A carry-free result would overlap the heap.
        JP NC,PAGE_ERR             ; Reject an image at or beyond the closure base.
        LD HL,(PAGE_IMG)           ; Recover the published image end.
        LD A,L                     ; Test the low byte for page alignment.
        OR A                       ; A zero low byte is already aligned.
        JR Z,.ALIGNED               ; Keep the aligned address unchanged.
        XOR A                      ; Clear the low byte before rounding upward.
        LD L,A                     ; The first free page begins at the next boundary.
        INC H                       ; Advance the page number after rounding.
        JP Z,PAGE_ERR              ; A wrapped address cannot describe the gap.
.ALIGNED:
        PUSH HL                    ; Preserve the rounded image page while comparing.
        LD DE,RT_HEAP              ; Collector maps cover the pool from 3000H.
        OR A                      ; Clear carry before testing the rounded base.
        SBC HL,DE                 ; Keep the first page at or above the map base.
        POP HL                    ; Restore the rounded page for the normal case.
        JR NC,.BASE               ; The image already leaves a valid map origin.
        LD HL,RT_HEAP             ; Do not hand out pages below the map coverage.
.BASE:
        LD (PAGE_ORG),HL           ; Save the first page in the managed domain.
        LD A,RT_LOEND/256          ; RT_LOEND ends the low managed extent.
        SUB H                      ; The high-byte difference is the page count.
        JP Z,PAGE_ERR              ; A zero-page gap cannot hold management state.
        LD L,A                     ; Store the count in the low byte.
        XOR A                      ; The domain never contains 256 pages here.
        LD H,A                     ; Keep the count as a normal unsigned word.
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
        JR Z,.FIRST_HI              ; Use the physical high extent in that case.
        LD HL,(PAGE_ORG)            ; Derive the first free low page otherwise.
        LD A,E                      ; Recover the reserved page count.
        ADD A,H                     ; Add it to the base page number.
        LD H,A                      ; The low byte remains zero for an aligned page.
        LD L,0                      ; Set the first free page address exactly.
        JR .FIRST                   ; Publish the low-extent boundary.
.FIRST_HI:
        LD HL,RT_HIGH               ; Skip the protected map band to the high pool.
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
