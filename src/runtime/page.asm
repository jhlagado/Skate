; Page-domain management for the Skate runtime.
;
; This module is deliberately independent of pair and closure allocation.
; It owns whole 256-byte pages in two explicit extents: the gap between the
; published image end and 9000H, followed by the managed B800H..C000H high
; extent.  The exact-root table and allocation maps occupy the fixed 9000H
; through B800H work band, so neither their bytes nor their pages enter the pool.
;
; Entry contracts:
;   SRTGPINI  HL = final loaded image end, returns A=0 or carry and A=2.
;   SRTGPALL  HL = page count, returns HL = page address or carry/A error.
;   SRTGPREL  HL = page address, DE = page count, returns carry/A error.
; A=1 means capacity, A=2 means an invalid request, and A=3 means that the
; page domain has not been initialised.  Successful calls clear carry and A.

; Initialise the page domain after the compiler has published the complete
; image extent.  The image end is rounded upward before page arithmetic.
SRTGPINI:
        XOR A                      ; Invalidate any previous domain before checks.
        LD (SRTPGOK),A             ; A failed reinitialisation must not leave it live.
        LD (SRTPGIMG),HL           ; Retain the exact unrounded image end.
        LD HL,(SRTHEAPP)           ; The caller may select a lower managed ceiling.
        LD DE,SRTMPEND             ; It must still include the first high page.
        OR A                       ; Clear carry before the lower-bound check.
        SBC HL,DE
        JP C,SRTGPIF               ; A ceiling inside the protected map band fails.
        LD A,L                     ; The ceiling must end on a page boundary.
        OR A
        JP NZ,SRTGPIF
        LD HL,(SRTHEAPP)           ; Check the configured ceiling against the TPA map.
        LD DE,SRTHEPEN
        OR A
        SBC HL,DE
        JR C,.TOPOK
        JR Z,.TOPOK
        JP SRTGPIF                 ; A ceiling above the qualified TPA is invalid.
.TOPOK:
        LD HL,(SRTHEAPP)           ; Derive the number of pages after the map band.
        LD DE,SRTMPEND
        OR A
        SBC HL,DE
        LD A,H                     ; The high byte is the count of 256-byte pages.
        LD L,A
        XOR A
        LD H,A
        LD (SRTPGHIG),HL           ; Keep the selected high extent in the domain.
        LD HL,(SRTPGIMG)           ; Recover the image end for the low-gap check.
        LD DE,SRTLOEND            ; The low extent ends at the upper band.
        OR A                       ; Clear carry before comparing the extent.
        SBC HL,DE                  ; A carry-free result would overlap the heap.
        JP NC,SRTGPIF              ; Reject an image at or beyond the closure base.
        LD HL,(SRTPGIMG)           ; Recover the published image end.
        LD A,L                     ; Test the low byte for page alignment.
        OR A                       ; A zero low byte is already aligned.
        JR Z,.AL                    ; Keep the aligned address unchanged.
        XOR A                      ; Clear the low byte before rounding upward.
        LD L,A                     ; The first free page begins at the next boundary.
        INC H                       ; Advance the page number after rounding.
        JP Z,SRTGPIF               ; A wrapped address cannot describe the gap.
.AL:
        PUSH HL                    ; Preserve the rounded image page while comparing.
        LD DE,SRTHEAP              ; Collector maps cover the pool from 3000H.
        OR A                      ; Clear carry before testing the rounded base.
        SBC HL,DE                 ; Keep the first page at or above the map base.
        POP HL                    ; Restore the rounded page for the normal case.
        JR NC,.BASE               ; The image already leaves a valid map origin.
        LD HL,SRTHEAP             ; Do not hand out pages below the map coverage.
.BASE:
        LD (SRTPGBAS),HL           ; Save the first page in the managed domain.
        LD A,090H                  ; 9000H ends the low managed extent.
        SUB H                      ; The high-byte difference is the page count.
        JP Z,SRTGPIF               ; A zero-page gap cannot hold management state.
        LD L,A                     ; Store the count in the low byte.
        XOR A                      ; The domain never contains 256 pages here.
        LD H,A                     ; Keep the count as a normal unsigned word.
        LD (SRTPGLOW),HL           ; Keep the low extent length for address mapping.
        LD DE,(SRTPGHIG)           ; Add the configured pages after the map band.
        ADD HL,DE
        LD (SRTPGCNT),HL           ; Record both explicit extents as one index space.
        LD A,L                     ; Begin bitmap-byte calculation from the count.
        ADD A,7                     ; Round a partial bitmap byte upward.
        SRL A                      ; Divide the rounded count by two.
        SRL A                      ; Divide by four.
        SRL A                      ; Divide by eight to obtain bitmap bytes.
        LD L,A                     ; Widen the byte count to a word.
        XOR A                      ; The bitmap-byte count has no high byte.
        LD H,A                     ; Store the widened bitmap extent.
        LD (SRTPGBYT),HL           ; The directory follows this bitmap.
        LD DE,(SRTPGCNT)           ; Add one directory byte per managed page.
        ADD HL,DE                  ; HL now contains all management bytes.
        LD BC,255                  ; Round those bytes up to whole pages.
        ADD HL,BC                  ; The high byte is the number of metadata pages.
        LD A,H                     ; Read the rounded metadata-page count.
        LD L,A                     ; Keep it as a normal unsigned word.
        XOR A                      ; Metadata pages are below 256 for this domain.
        LD H,A                     ; Clear the high byte before storing the count.
        LD (SRTPGMET),HL           ; Reserve these pages before setting free bits.
        LD DE,(SRTPGLOW)           ; Metadata must fit in the low physical extent.
        LD A,L                     ; Compare the only nonzero count byte.
        CP E                       ; Metadata must fit inside the managed interval.
        JR C,.MOK                  ; A smaller metadata extent is valid.
        JR Z,.MOK                  ; Equal extents are valid but leave no free page.
        JP SRTGPIF                 ; A larger metadata extent is impossible.
.MOK:
        LD HL,(SRTPGCNT)           ; Calculate the pages left for future classes.
        LD DE,(SRTPGMET)           ; Remove the reserved management pages.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; The result is the initially free page count.
        LD DE,SRTMHIGH              ; Reserve the fixed upper metadata pages.
        SBC HL,DE                  ; Account for the reserved upper band.
        JP C,SRTGPIF               ; A domain without object capacity is invalid.
        LD (SRTPGFRE),HL           ; Publish that capacity after validation.
        LD HL,(SRTPGBAS)           ; The bitmap starts at the first page.
        LD (SRTPGBMA),HL           ; Save the bitmap address for bit operations.
        LD HL,(SRTPGBAS)           ; Derive the directory address from the base.
        LD DE,(SRTPGBYT)           ; The bitmap occupies its calculated byte extent.
        ADD HL,DE                  ; The directory begins after those bitmap bytes.
        LD (SRTPGDIR),HL           ; Save the directory address for run checks.
        LD A,(SRTPGMET)            ; Metadata pages advance the low extent base.
        LD E,A                     ; Keep the count while comparing its boundary.
        LD A,(SRTPGLOW)            ; A full low extent has no low free page.
        CP E                        ; Equality means the first free page is high.
        JR Z,.FRHIGH                ; Use the physical high extent in that case.
        LD HL,(SRTPGBAS)            ; Derive the first free low page otherwise.
        LD A,E                      ; Recover the reserved page count.
        ADD A,H                     ; Add it to the base page number.
        LD H,A                      ; The low byte remains zero for an aligned page.
        LD L,0                      ; Set the first free page address exactly.
        JR .FRSET                   ; Publish the low-extent boundary.
.FRHIGH:
        LD HL,SRTMPEND              ; Skip the protected map band to the high pool.
.FRSET:
        LD (SRTPGFRB),HL           ; Keep the lower boundary for release checks.
        LD HL,(SRTPGBMA)           ; Clear the complete bitmap before setting bits.
        LD BC,(SRTPGBYT)           ; BC counts every bitmap byte, including padding.
        XOR A                      ; Zero means allocated or reserved in the bitmap.
.BCB:
        XOR A                      ; Keep every cleared bitmap byte at zero.
        LD (HL),A                  ; Start with no page marked free.
        INC HL                     ; Advance to the following bitmap byte.
        DEC BC                     ; Consume one byte from the bounded extent.
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero count ends the clearing loop.
        JR NZ,.BCB                 ; Continue until every bitmap byte is clear.
        LD HL,(SRTPGDIR)           ; Clear the per-page state directory.
        LD BC,(SRTPGCNT)           ; One byte describes every page in the domain.
        XOR A                      ; Zero denotes a free page in the directory.
.PDC:
        XOR A                      ; Keep every cleared directory byte at zero.
        LD (HL),A                  ; Clear the state before publishing readiness.
        INC HL                     ; Advance to the next directory byte.
        DEC BC                     ; Consume one page entry.
        LD A,B                     ; Check whether all directory entries are clear.
        OR C                       ; Z means the directory has been initialised.
        JR NZ,.PDC                 ; Continue through the complete page domain.
        LD HL,(SRTPGDIR)           ; Mark the reserved management entries.
        LD BC,(SRTPGMET)           ; BC counts the metadata pages at the front.
        LD A,2                     ; Directory state two means reserved metadata.
.PMR:
        LD A,2                     ; Restore the reserved state after the counter test.
        LD (HL),A                  ; Keep reserved pages out of allocation scans.
        INC HL                     ; Advance to the next reserved page entry.
        DEC BC                     ; Consume one metadata page.
        LD A,B                     ; Test whether all reserved entries were marked.
        OR C                       ; Zero ends the metadata reservation loop.
        JR NZ,.PMR                 ; Continue while metadata pages remain.
        LD HL,(SRTPGMET)           ; Begin setting free bits after reserved pages.
        LD (SRTPGIDX),HL           ; The bit helper reads this page index.
.PFS:
        LD HL,(SRTPGIDX)           ; Recover the next candidate page index.
        LD DE,(SRTPGCNT)           ; Compare it with the total page count.
        OR A                       ; Clear carry before the upper-bound compare.
        SBC HL,DE                  ; A carry-free result means the loop is done.
        JR NC,.PFD                 ; Do not set bitmap padding or reserved bits.
        CALL SRTGPSET              ; Mark this page free in the bitmap.
        LD HL,(SRTPGIDX)           ; Recover the index after the bit operation.
        INC HL                     ; Advance to the following page.
        LD (SRTPGIDX),HL           ; Publish the next initialization index.
        JR .PFS                    ; Continue through every usable page.
.PFD:
        LD HL,(SRTPGLOW)           ; The upper extent starts after the low pages.
        LD (SRTPGIDX),HL           ; Select its first virtual page for reservation.
        LD BC,SRTMHIGH              ; Reserve the fixed exact-root metadata band.
        LD A,B                     ; A zero count means the runtime image owns no band.
        OR C
        JR Z,.PREADY                ; Do not enter the reservation loop at zero.
.PHR:
        CALL SRTGPCLR              ; Remove the upper metadata page from the bitmap.
        LD HL,(SRTPGDIR)           ; Locate the matching directory state.
        LD DE,(SRTPGIDX)           ; Add the virtual upper-page index.
        ADD HL,DE                  ; HL names the reserved directory entry.
        LD A,2                     ; State two is reserved metadata.
        LD (HL),A                  ; Keep the page out of future allocation scans.
        LD HL,(SRTPGIDX)           ; Advance to the following upper page.
        INC HL
        LD (SRTPGIDX),HL
        DEC BC                     ; Consume one reserved upper page.
        LD A,B
        OR C
        JP NZ,.PHR                 ; Continue through all fixed metadata pages.
.PREADY:
        LD A,1                     ; Mark the state as ready for allocation calls.
        LD (SRTPGOK),A             ; A nonzero flag distinguishes a valid domain.
        XOR A                      ; Successful initialisation returns A=0.
        RET                        ; Carry remains clear from the final comparison.

; Allocate a contiguous run of whole pages using the directory as the exact
; ownership record.  A failed search does not change either representation.
SRTGPALL:
        CALL SRTGPRDY              ; Reject use before a successful init.
        RET C                      ; Preserve the uninitialised status code.
        LD (SRTPGREQ),HL           ; Retain the requested run length.
        LD A,H                     ; The current domain cannot contain 256 pages.
        OR A                       ; A nonzero high byte is outside its capacity.
        JP NZ,SRTXERR              ; Report a capacity failure without writing.
        LD A,L                     ; Test the low byte for a zero-page request.
        OR A                       ; Zero cannot describe a meaningful allocation.
        JP Z,SRTGPIV               ; Report a malformed allocation request.
        LD HL,(SRTPGCNT)           ; Check the request against total pages.
        LD DE,(SRTPGREQ)           ; DE carries the requested run length.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; A carry means that the request is too large.
        JP C,SRTXERR               ; Leave the current bitmap and directory intact.
        XOR A                      ; Start the search at page index zero.
        LD H,A                     ; The page index is kept as a word for arithmetic.
        LD L,A                     ; The first candidate is the domain base.
        LD (SRTPGIDX),HL           ; Publish the candidate for the scan helper.
.AS:
        LD HL,(SRTPGIDX)           ; Read the candidate start index.
        LD DE,(SRTPGCNT)           ; Stop after the final domain page.
        OR A                       ; Clear carry before the comparison.
        SBC HL,DE                  ; A nonnegative result has no possible run.
        JP NC,SRTXERR              ; Report exhaustion without changing ownership.
        LD HL,(SRTPGIDX)           ; Re-read the candidate for an end-bound check.
        LD DE,(SRTPGREQ)           ; Add the complete requested run length.
        ADD HL,DE                  ; HL is the exclusive candidate end index.
        LD (SRTPGEND),HL           ; Keep it while checking the extent boundary.
        LD DE,(SRTPGLOW)           ; The low extent cannot run into the closure gap.
        OR A                       ; Clear carry before the extent comparison.
        SBC HL,DE                  ; A carry or zero keeps the run in the low extent.
        JR C,.ARUN                 ; The run ends before the second extent.
        JR Z,.ARUN                 ; The run ends exactly at the low extent boundary.
        LD HL,(SRTPGIDX)           ; A candidate in the high extent is also valid.
        LD DE,(SRTPGLOW)           ; Compare its start with the extent boundary.
        OR A                       ; Clear carry before the start comparison.
        SBC HL,DE                  ; A nonnegative start belongs to the high extent.
        JR NC,.ARUN                ; High-extent runs must still fit the total count.
        LD HL,(SRTPGIDX)           ; A low run crossing the reserved gap is invalid.
        INC HL                     ; Try the next virtual page index.
        LD (SRTPGIDX),HL           ; Keep the search moving through both extents.
        JR .AS                     ; Recheck the next candidate without writes.
.ARUN:
        LD HL,(SRTPGEND)           ; Recover the checked exclusive candidate end.
        LD DE,(SRTPGCNT)           ; Compare that end with the domain boundary.
        OR A                       ; Clear carry before the upper-bound compare.
        SBC HL,DE                  ; Carry or zero means the run remains in range.
        JR C,.ARUNOK               ; A run ending below the boundary is valid.
        JR Z,.ARUNOK               ; An equal end is the exact final run.
        JP SRTXERR                 ; Later starts cannot fit once this one cannot.
.ARUNOK:
        LD HL,(SRTPGDIR)           ; Begin at the directory entry for this start.
        LD DE,(SRTPGIDX)           ; Add the candidate index to the directory base.
        ADD HL,DE                  ; HL now names the first entry in the run.
        LD BC,(SRTPGREQ)           ; BC counts the entries that must be free.
.AC:
        LD A,B                     ; Test the remaining run length.
        OR C                       ; Zero means every entry in this candidate is free.
        JR Z,.AOK                  ; Reserve this candidate run atomically below.
        LD A,(HL)                  ; Read the exact directory ownership state.
        OR A                       ; Only zero entries can be allocated.
        JR NZ,.AN                  ; A reserved or used page rejects this start.
        INC HL                     ; Advance to the next page entry.
        DEC BC                     ; Consume one free-entry check.
        JR .AC                     ; Continue until the candidate is disproved.
.AN:
        LD HL,(SRTPGIDX)           ; Recover the candidate that just failed.
        INC HL                     ; Try the next page as a new run start.
        LD (SRTPGIDX),HL           ; Keep the search bounded by the domain count.
        JR .AS                     ; Recheck the next candidate from its first page.
.AOK:
        LD HL,(SRTPGIDX)           ; Save the successful start before marking it.
        LD (SRTPGSTR),HL           ; The returned address is based on this index.
        LD BC,(SRTPGREQ)           ; Mark exactly the requested number of entries.
.AM:
        LD A,B                     ; Test the remaining commit count.
        OR C                       ; Zero means every page is now allocated.
        JR Z,.AD                   ; Finish the atomic ownership transition.
        CALL SRTGPCLR              ; Clear this page's free bit.
        LD HL,(SRTPGDIR)           ; Locate the matching directory entry.
        LD DE,(SRTPGIDX)           ; Add the current page index to its base.
        ADD HL,DE                  ; HL names the entry being allocated.
        LD A,1                     ; State one denotes an allocated page.
        LD (HL),A                  ; Publish the owner state after clearing its bit.
        LD HL,(SRTPGIDX)           ; Advance the allocation index.
        INC HL                     ; Move to the next page in the requested run.
        LD (SRTPGIDX),HL           ; Keep the commit cursor in the state block.
        DEC BC                     ; Consume one committed page.
        JR .AM                    ; Continue until the complete run is marked.
.AD:
        LD HL,(SRTPGFRE)           ; Remove the run from the free-page count.
        LD DE,(SRTPGREQ)           ; DE carries the exact committed length.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; The preflight check proves this cannot wrap.
        LD (SRTPGFRE),HL           ; Publish the remaining free-page count.
        LD HL,(SRTPGSTR)           ; Map the virtual start index to a physical page.
        LD (SRTPGIDX),HL           ; The mapping helper reads the shared index slot.
        CALL SRTGPMAP              ; Low and high extents have different bases.
        XOR A                      ; Successful allocation returns A=0 and carry clear.
        RET                        ; The caller receives the first page in HL.

; Convert a virtual page index to the physical page address in HL.
SRTGPMAP:
        LD HL,(SRTPGIDX)           ; Read the candidate or committed page index.
        LD DE,(SRTPGLOW)           ; The first high-extent index follows the low gap.
        OR A                       ; Clear carry before selecting an extent.
        SBC HL,DE                  ; A carry means that the index is in the low gap.
        JR C,.LOW                  ; Low pages are based at the rounded image end.
        LD A,L                     ; High-extent offsets fit in the low byte.
        ADD A,0B8H                 ; The managed high band starts at B800H.
        LD H,A                     ; Return a page-aligned address in the high extent.
        LD L,0                     ; Every managed page address ends at byte zero.
        RET                        ; The caller receives the mapped high page.
.LOW:
        LD HL,(SRTPGIDX)           ; Recover the original low-extent index.
        LD A,L                     ; Low-extent indices are below the page count.
        LD DE,(SRTPGBAS)           ; Add the rounded image base page.
        ADD A,D                    ; Construct the physical low-extent page number.
        LD H,A                     ; Preserve page alignment in the returned address.
        LD L,0                     ; Every managed page address ends at byte zero.
        RET                        ; The caller receives the mapped low page.

; Release a previously allocated contiguous run.  Validation completes before
; any entry or bit changes, so invalid and double frees are atomic failures.
SRTGPREL:
        CALL SRTGPRDY              ; Reject use before a successful init.
        RET C                      ; Preserve the uninitialised status code.
        LD (SRTPGADR),HL           ; Save the address while checking its range.
        LD (SRTPGREQ),DE           ; Save the requested release length.
        LD A,D                     ; A high count byte cannot fit this domain.
        OR A                       ; Reject a wrapped or oversized release.
        JP NZ,SRTGPIV              ; Leave all ownership state unchanged.
        LD A,E                     ; Test the low count byte for zero.
        OR A                       ; A zero-length release is malformed.
        JP Z,SRTGPIV               ; Report the invalid request without writes.
        LD A,L                     ; Every page address must be 256-byte aligned.
        OR A                       ; A nonzero low byte names an interior address.
        JP NZ,SRTGPIV              ; Reject it before touching the directory.
        LD HL,(SRTPGADR)           ; Select the low or high physical extent.
        LD DE,SRTLOEND            ; Addresses below 9000H belong to the low gap.
        OR A                       ; Clear carry before the extent comparison.
        SBC HL,DE                  ; A carry selects the low physical extent.
        JR C,.LOWADDR              ; Validate and map a page in the low gap.
        LD HL,(SRTPGADR)           ; Reject addresses in the protected upper region.
        LD DE,(SRTHEAPP)           ; The selected ceiling bounds managed pages.
        OR A                       ; Clear carry before the upper-bound comparison.
        SBC HL,DE                  ; A nonnegative value lies at or above C000.
        JP NC,SRTGPIV              ; Neither the stack nor page zero is managed.
        LD HL,(SRTPGADR)           ; Check the lower bound of the high extent.
        LD DE,SRTMPEND             ; The managed high extent begins after the maps.
        OR A                       ; Clear carry before the high-extent comparison.
        SBC HL,DE                  ; A carry lies in the protected closure gap.
        JP C,SRTGPIV               ; Do not release an address between the extents.
        LD A,H                     ; The high-byte difference is the high offset.
        LD L,A                     ; Widen that offset to a virtual page index.
        XOR A                      ; The high extent offset has no high byte.
        LD H,A                     ; Add the low-extent page count below.
        LD DE,(SRTPGLOW)           ; High virtual indices follow every low page.
        ADD HL,DE                  ; Map B800H to the first high-extent index.
        JR .INDEX                  ; Validate the mapped run below.
.LOWADDR:
        LD HL,(SRTPGADR)           ; Convert the low page address to an index.
        LD DE,(SRTPGBAS)           ; Subtract the rounded image base.
        OR A                       ; Clear carry before the low address subtraction.
        SBC HL,DE                  ; A carry means the address is below the image.
        JP C,SRTGPIV               ; Leave the current bitmap unchanged.
        LD A,L                     ; The difference must be page aligned.
        OR A                       ; Nonzero low bits identify an interior address.
        JP NZ,SRTGPIV              ; Reject that address without modifying state.
        LD A,H                     ; The high byte is the low virtual page index.
        LD L,A                     ; Widen that index to a normal word.
        XOR A                      ; The index cannot exceed the 8-bit page domain.
        LD H,A                     ; Store the exact page index for validation.
.INDEX:
        LD (SRTPGIDX),HL           ; Keep the release start in the state block.
        LD DE,(SRTPGMET)           ; Reject a run that begins inside metadata.
        OR A                       ; Clear carry before the reserved-range compare.
        SBC HL,DE                  ; A carry means the index is reserved.
        JP C,SRTGPIV               ; No directory or bitmap writes occur on failure.
        LD HL,(SRTPGIDX)           ; Reject the fixed upper metadata band as well.
        LD DE,(SRTPGLOW)           ; The band begins at the first upper page.
        OR A                       ; Clear carry before the upper-band compare.
        SBC HL,DE
        JR C,.NPH                  ; A low-extent index is not in that band.
        LD DE,SRTMHIGH             ; Compare the offset with the reserved count.
        OR A                       ; Clear carry before subtracting the count.
        SBC HL,DE
        JP C,SRTGPIV               ; A release starting in metadata is invalid.
.NPH:
        LD HL,(SRTPGIDX)           ; Add the requested run length to its start.
        LD DE,(SRTPGREQ)           ; DE carries the complete release length.
        ADD HL,DE                  ; The result is the exclusive ending index.
        LD (SRTPGEND),HL           ; Preserve the end while checking the extents.
        LD DE,(SRTPGLOW)           ; The low extent cannot cross the closure gap.
        OR A                       ; Clear carry before the extent comparison.
        SBC HL,DE                  ; A carry or zero keeps the run in the low extent.
        JR C,.RERUN                ; The run ends before the second extent.
        JR Z,.RERUN                ; The run ends exactly at the low extent boundary.
        LD HL,(SRTPGIDX)           ; A high-extent run may continue to its end.
        LD DE,(SRTPGLOW)           ; Compare its virtual start with the boundary.
        OR A                       ; Clear carry before the start comparison.
        SBC HL,DE                  ; A nonnegative start belongs to the high extent.
        JR NC,.RERUN               ; High runs still need the total-bound check.
        JP SRTGPIV                 ; A low run crossing the gap is invalid.
.RERUN:
        LD HL,(SRTPGEND)           ; Recover the checked exclusive run end.
        LD DE,(SRTPGCNT)           ; Compare it with the complete virtual domain.
        OR A                       ; Clear carry before the upper-bound comparison.
        SBC HL,DE                  ; Carry or zero means that the run remains inside.
        JR C,.RE                   ; A carry means the run ends below the boundary.
        JR Z,.RE                   ; An equal end address is the exact boundary.
        JP SRTGPIV                 ; A positive result would cross the end.
.RE:
        LD HL,(SRTPGDIR)           ; Begin validating the exact directory states.
        LD DE,(SRTPGIDX)           ; Add the release start to the directory base.
        ADD HL,DE                  ; HL names the first state being released.
        LD BC,(SRTPGREQ)           ; BC counts every entry that must be allocated.
.RC:
        LD A,B                     ; Test the remaining validation count.
        OR C                       ; Zero means all entries are allocated as expected.
        JR Z,.RM                   ; Commit the release only after this validation.
        LD A,(HL)                  ; Read the directory ownership state.
        CP 1                       ; Only an allocated entry may be released.
        JP NZ,SRTGPIV              ; This also catches a double free atomically.
        INC HL                     ; Advance to the next state in the requested run.
        DEC BC                     ; Consume one validated allocated page.
        JR .RC                     ; Continue until the complete run is checked.
.RM:
        LD BC,(SRTPGREQ)           ; Commit exactly the validated run length.
.RL:
        LD A,B                     ; Test the remaining release count.
        OR C                       ; Zero means all pages have been returned.
        JR Z,.RD                   ; Finish the free-count update below.
        CALL SRTGPSET              ; Set this page's free bit in the bitmap.
        LD HL,(SRTPGDIR)           ; Locate the corresponding directory entry.
        LD DE,(SRTPGIDX)           ; Add the current index to its base address.
        ADD HL,DE                  ; HL names the entry being released.
        XOR A                      ; State zero denotes a free page.
        LD (HL),A                  ; Publish the free state after setting its bit.
        LD HL,(SRTPGIDX)           ; Advance to the following page index.
        INC HL                     ; Move through the validated contiguous run.
        LD (SRTPGIDX),HL           ; Keep the release cursor in the state block.
        DEC BC                     ; Consume one returned page.
        JR .RL                    ; Continue until every page is free again.
.RD:
        LD HL,(SRTPGFRE)           ; Add the returned run to the free-page count.
        LD DE,(SRTPGREQ)           ; DE carries the exact number of released pages.
        ADD HL,DE                  ; The validation proves the count cannot overflow.
        LD (SRTPGFRE),HL           ; Publish the restored free-page capacity.
        XOR A                      ; Successful release returns A=0 and carry clear.
        RET                        ; The caller's page state is now fully consistent.

; Return carry and status three when no successful page initialisation exists.
SRTGPRDY:
        LD A,(SRTPGOK)             ; Read the explicit page-domain readiness flag.
        OR A                       ; A zero state rejects allocation and release calls.
        RET NZ                      ; The caller continues with a ready domain.
        LD A,3                     ; Status three denotes an uninitialised domain.
        SCF                        ; Carry distinguishes the failure from success.
        RET                        ; No page memory has been touched on this path.

; Common capacity and invalid-request returns keep failure codes consistent.
SRTXERR:
        LD A,1                     ; Status one denotes exhausted or oversized capacity.
        SCF                        ; Carry reports that no state was committed.
        RET                        ; The caller can distinguish capacity from syntax.
SRTGPIV:
        LD A,2                     ; Status two denotes an invalid page request.
        SCF                        ; Carry reports the atomic validation failure.
        RET                        ; Existing page ownership remains unchanged.
SRTGPIF:
        LD A,2                     ; An image that leaves no valid domain is invalid.
        SCF                        ; Startup failure occurs before metadata writes.
        RET                        ; The caller can reject this runtime layout.

; Locate the bitmap byte and mask for the index in SRTPGIDX.
SRTGPBIT:
        LD HL,(SRTPGIDX)           ; Read the page index being changed or tested.
        LD A,L                     ; The domain has fewer than 256 pages.
        AND 7                       ; Keep the bit position within its bitmap byte.
        LD E,A                     ; Use that position as the mask-table offset.
        LD D,0                     ; The table contains one byte per bit position.
        LD HL,SRTGMASK             ; Begin at the first power-of-two mask.
        ADD HL,DE                  ; Select the mask for this page's bit.
        LD A,(HL)                  ; Read the selected bit mask.
        LD (SRTBITM),A             ; Preserve it while locating the byte.
        LD HL,(SRTPGIDX)           ; Recover the original index for division.
        LD A,L                     ; The bitmap byte index begins with the low byte.
        SRL A                      ; Divide the page index by two.
        SRL A                      ; Divide by four.
        SRL A                      ; Divide by eight to select a bitmap byte.
        LD L,A                     ; Widen the byte index to a word.
        LD H,0                     ; The bitmap byte index has no high byte here.
        LD DE,(SRTPGBMA)           ; Add the bitmap base to the byte index.
        ADD HL,DE                  ; Return HL as the exact bitmap-byte address.
        RET                        ; SRTBITM supplies the corresponding bit mask.

; Set the free bit for the current page index.
SRTGPSET:
        CALL SRTGPBIT              ; Locate the bitmap byte and selected mask.
        LD A,(HL)                  ; Read the current bitmap ownership bits.
        LD D,A                     ; Preserve those neighboring bits across the lookup.
        LD A,(SRTBITM)             ; Recover the selected free-bit mask.
        OR D                       ; Set one page free without changing neighbors.
        LD (HL),A                  ; Publish the free bit in the bitmap byte.
        RET                        ; The caller's BC counter remains untouched.

; Clear the free bit for the current page index.
SRTGPCLR:
        CALL SRTGPBIT              ; Locate the bitmap byte and selected mask.
        LD A,(SRTBITM)             ; Recover the bit that denotes this page.
        CPL                         ; Invert it to form an AND clearing mask.
        LD E,A                     ; Preserve the inverted mask across the read.
        LD A,(HL)                  ; Read the current bitmap ownership bits.
        AND E                       ; Clear one page while preserving its neighbors.
        LD (HL),A                  ; Publish the allocated bit in the bitmap byte.
        RET                        ; The caller's BC counter remains untouched.

; Page-domain state and the eight one-bit masks used by SRTGPBIT.
SRTPGIMG: DW 0                     ; Exact final loaded image end supplied by SCFIN.
SRTPGBAS: DW 0                     ; First aligned page in the low managed extent.
SRTPGLOW: DW 0                     ; Number of pages before the B800 extent.
SRTPGHIG: DW 0                     ; Number of pages in the selected high extent.
SRTPGCNT: DW 0                     ; Total virtual pages in both explicit extents.
SRTPGMET: DW 0                     ; Whole pages reserved for bitmap and directory.
SRTPGFRE: DW 0                     ; Currently free object pages.
SRTPGBYT: DW 0                     ; Bitmap byte extent, including trailing padding.
SRTPGBMA: DW 0                     ; Runtime address of the free-page bitmap.
SRTPGDIR: DW 0                     ; Runtime address of the per-page directory.
SRTPGFRB: DW 0                     ; First page address available to callers.
SRTPGIDX: DW 0                     ; Scratch page index for scans and bit updates.
SRTPGREQ: DW 0                     ; Scratch requested run length.
SRTPGSTR: DW 0                     ; Successful run start index for address output.
SRTPGADR: DW 0                     ; Scratch release address.
SRTPGEND: DW 0                     ; Scratch exclusive end for extent checks.
SRTPGOK:  DB 0                     ; Nonzero after a successful page-domain init.
SRTBITM:  DB 0                     ; Selected bit mask for the current page.
SRTGMASK: DB 1,2,4,8,16,32,64,128 ; Bit masks for one bitmap byte.
