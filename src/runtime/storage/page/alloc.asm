; Runtime page allocation, release, mapping and bitmap operations.
; Entry points: PAGE_NEW, .MAP, PAGE_REL, PAGE_SET and PAGE_CLR.
; Allocate a contiguous run of whole pages using the directory as the exact
; ownership record.  A failed search does not change either representation.
PAGE_NEW:
        CALL PAGE_CHK              ; Reject use before a successful init.
        RET C                      ; Preserve the uninitialised status code.
        LD (PAGE_RUN),HL           ; Retain the requested run length.
        LD A,H                     ; The current domain cannot contain 256 pages.
        OR A                       ; A nonzero high byte is outside its capacity.
        JP NZ,PAGE_OUT             ; Report a capacity failure without writing.
        LD A,L                     ; Test the low byte for a zero-page request.
        OR A                       ; Zero cannot describe a meaningful allocation.
        JP Z,PAGE_BAD              ; Report a malformed allocation request.
        LD HL,(PAGE_CNT)           ; Check the request against total pages.
        LD DE,(PAGE_RUN)           ; DE carries the requested run length.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; A carry means that the request is too large.
        JP C,PAGE_OUT              ; Leave the current bitmap and directory intact.
        XOR A                      ; Start the search at page index zero.
        LD H,A                     ; The page index is kept as a word for arithmetic.
        LD L,A                     ; The first candidate is the domain base.
        LD (PAGE_IDX),HL           ; Publish the candidate for the scan helper.
.SCAN:
        LD HL,(PAGE_IDX)           ; Read the candidate start index.
        LD DE,(PAGE_CNT)           ; Stop after the final domain page.
        OR A                       ; Clear carry before the comparison.
        SBC HL,DE                  ; A nonnegative result has no possible run.
        JP NC,PAGE_OUT             ; Report exhaustion without changing ownership.
        LD HL,(PAGE_IDX)           ; Re-read the candidate for an end-bound check.
        LD DE,(PAGE_RUN)           ; Add the complete requested run length.
        ADD HL,DE                  ; HL is the exclusive candidate end index.
        LD (PAGE_END),HL           ; Keep it while checking the extent boundary.
        LD DE,(PAGE_LO)            ; The low extent cannot run into the closure gap.
        OR A                       ; Clear carry before the extent comparison.
        SBC HL,DE                  ; A carry or zero keeps the run in the low extent.
        JR C,.RUN                  ; The run ends before the second extent.
        JR Z,.RUN                  ; The run ends exactly at the low extent boundary.
        LD HL,(PAGE_IDX)           ; A candidate in the high extent is also valid.
        LD DE,(PAGE_LO)            ; Compare its start with the extent boundary.
        OR A                       ; Clear carry before the start comparison.
        SBC HL,DE                  ; A nonnegative start belongs to the high extent.
        JR NC,.RUN                 ; High-extent runs must still fit the total count.
        LD HL,(PAGE_IDX)           ; A low run crossing the reserved gap is invalid.
        INC HL                     ; Try the next virtual page index.
        LD (PAGE_IDX),HL           ; Keep the search moving through both extents.
        JR .SCAN                   ; Recheck the next candidate without writes.
.RUN:
        LD HL,(PAGE_END)           ; Recover the checked exclusive candidate end.
        LD DE,(PAGE_CNT)           ; Compare that end with the domain boundary.
        OR A                       ; Clear carry before the upper-bound compare.
        SBC HL,DE                  ; Carry or zero means the run remains in range.
        JR C,.RUN_OK               ; A run ending below the boundary is valid.
        JR Z,.RUN_OK               ; An equal end is the exact final run.
        JP PAGE_OUT                ; Later starts cannot fit once this one cannot.
.RUN_OK:
        LD HL,(PAGE_DIR)           ; Begin at the directory entry for this start.
        LD DE,(PAGE_IDX)           ; Add the candidate index to the directory base.
        ADD HL,DE                  ; HL now names the first entry in the run.
        LD BC,(PAGE_RUN)           ; BC counts the entries that must be free.
.CHECK:
        LD A,B                     ; Test the remaining run length.
        OR C                       ; Zero means every entry in this candidate is free.
        JR Z,.FOUND                ; Reserve this candidate run atomically below.
        LD A,(HL)                  ; Read the exact directory ownership state.
        OR A                       ; Only zero entries can be allocated.
        JR NZ,.SKIP                ; A reserved or used page rejects this start.
        INC HL                     ; Advance to the next page entry.
        DEC BC                     ; Consume one free-entry check.
        JR .CHECK                  ; Continue until the candidate is disproved.
.SKIP:
        LD HL,(PAGE_IDX)           ; Recover the candidate that just failed.
        INC HL                     ; Try the next page as a new run start.
        LD (PAGE_IDX),HL           ; Keep the search bounded by the domain count.
        JR .SCAN                   ; Recheck the next candidate from its first page.
.FOUND:
        LD HL,(PAGE_IDX)           ; Save the successful start before marking it.
        LD (PAGE_POS),HL           ; The returned address is based on this index.
        LD BC,(PAGE_RUN)           ; Mark exactly the requested number of entries.
.MARK:
        LD A,B                     ; Test the remaining commit count.
        OR C                       ; Zero means every page is now allocated.
        JR Z,.DONE                 ; Finish the atomic ownership transition.
        CALL PAGE_CLR              ; Clear this page's free bit.
        LD HL,(PAGE_DIR)           ; Locate the matching directory entry.
        LD DE,(PAGE_IDX)           ; Add the current page index to its base.
        ADD HL,DE                  ; HL names the entry being allocated.
        LD A,1                     ; State one denotes an allocated page.
        LD (HL),A                  ; Publish the owner state after clearing its bit.
        LD HL,(PAGE_IDX)           ; Advance the allocation index.
        INC HL                     ; Move to the next page in the requested run.
        LD (PAGE_IDX),HL           ; Keep the commit cursor in the state block.
        DEC BC                     ; Consume one committed page.
        JR .MARK                  ; Continue until the complete run is marked.
.DONE:
        LD HL,(PAGE_CAP)           ; Remove the run from the free-page count.
        LD DE,(PAGE_RUN)           ; DE carries the exact committed length.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; The preflight check proves this cannot wrap.
        LD (PAGE_CAP),HL           ; Publish the remaining free-page count.
        LD HL,(PAGE_POS)           ; Map the virtual start index to a physical page.
        LD (PAGE_IDX),HL           ; The mapping helper reads the shared index slot.
        CALL .MAP                  ; Low and high extents have different bases.
        XOR A                      ; Successful allocation returns A=0 and carry clear.
        RET                        ; The caller receives the first page in HL.

; Convert a virtual page index to the physical page address in HL.
.MAP:
        LD HL,(PAGE_IDX)           ; Read the candidate or committed page index.
        LD DE,(PAGE_LO)            ; The first high-extent index follows the low gap.
        OR A                       ; Clear carry before selecting an extent.
        SBC HL,DE                  ; A carry means that the index is in the low gap.
        JR C,.LOW                  ; Low pages are based at the rounded image end.
        LD A,L                     ; High-extent offsets fit in the low byte.
        ADD A,SRTMPENH             ; The managed high band starts at SRTMPEND.
        LD H,A                     ; Return a page-aligned address in the high extent.
        LD L,0                     ; Every managed page address ends at byte zero.
        RET                        ; The caller receives the mapped high page.
.LOW:
        LD HL,(PAGE_IDX)           ; Recover the original low-extent index.
        LD A,L                     ; Low-extent indices are below the page count.
        LD DE,(PAGE_ORG)           ; Add the rounded image base page.
        ADD A,D                    ; Construct the physical low-extent page number.
        LD H,A                     ; Preserve page alignment in the returned address.
        LD L,0                     ; Every managed page address ends at byte zero.
        RET                        ; The caller receives the mapped low page.

; Release a previously allocated contiguous run.  Validation completes before
; any entry or bit changes, so invalid and double frees are atomic failures.
PAGE_REL:
        CALL PAGE_CHK              ; Reject use before a successful init.
        RET C                      ; Preserve the uninitialised status code.
        LD (PAGE_PTR),HL           ; Save the address while checking its range.
        LD (PAGE_RUN),DE           ; Save the requested release length.
        LD A,D                     ; A high count byte cannot fit this domain.
        OR A                       ; Reject a wrapped or oversized release.
        JP NZ,PAGE_BAD             ; Leave all ownership state unchanged.
        LD A,E                     ; Test the low count byte for zero.
        OR A                       ; A zero-length release is malformed.
        JP Z,PAGE_BAD              ; Report the invalid request without writes.
        LD A,L                     ; Every page address must be 256-byte aligned.
        OR A                       ; A nonzero low byte names an interior address.
        JP NZ,PAGE_BAD             ; Reject it before touching the directory.
        LD HL,(PAGE_PTR)           ; Select the low or high physical extent.
        LD DE,SRTLOEND            ; Addresses below 9000H belong to the low gap.
        OR A                       ; Clear carry before the extent comparison.
        SBC HL,DE                  ; A carry selects the low physical extent.
        JR C,.LOW_ADDR             ; Validate and map a page in the low gap.
        LD HL,(PAGE_PTR)           ; Reject addresses in the protected upper region.
        LD DE,(SRTHEAPP)           ; The selected ceiling bounds managed pages.
        OR A                       ; Clear carry before the upper-bound comparison.
        SBC HL,DE                  ; A nonnegative value lies at or above C000.
        JP NC,PAGE_BAD             ; Neither the stack nor page zero is managed.
        LD HL,(PAGE_PTR)           ; Check the lower bound of the high extent.
        LD DE,SRTMPEND             ; The managed high extent begins after the maps.
        OR A                       ; Clear carry before the high-extent comparison.
        SBC HL,DE                  ; A carry lies in the protected closure gap.
        JP C,PAGE_BAD              ; Do not release an address between the extents.
        LD A,H                     ; The high-byte difference is the high offset.
        LD L,A                     ; Widen that offset to a virtual page index.
        XOR A                      ; The high extent offset has no high byte.
        LD H,A                     ; Add the low-extent page count below.
        LD DE,(PAGE_LO)            ; High virtual indices follow every low page.
        ADD HL,DE                  ; Map SRTMPEND to the first high-extent index.
        JR .INDEX                  ; Validate the mapped run below.
.LOW_ADDR:
        LD HL,(PAGE_PTR)           ; Convert the low page address to an index.
        LD DE,(PAGE_ORG)           ; Subtract the rounded image base.
        OR A                       ; Clear carry before the low address subtraction.
        SBC HL,DE                  ; A carry means the address is below the image.
        JP C,PAGE_BAD              ; Leave the current bitmap unchanged.
        LD A,L                     ; The difference must be page aligned.
        OR A                       ; Nonzero low bits identify an interior address.
        JP NZ,PAGE_BAD             ; Reject that address without modifying state.
        LD A,H                     ; The high byte is the low virtual page index.
        LD L,A                     ; Widen that index to a normal word.
        XOR A                      ; The index cannot exceed the 8-bit page domain.
        LD H,A                     ; Store the exact page index for validation.
.INDEX:
        LD (PAGE_IDX),HL           ; Keep the release start in the state block.
        LD DE,(PAGE_SYS)           ; Reject a run that begins inside metadata.
        OR A                       ; Clear carry before the reserved-range compare.
        SBC HL,DE                  ; A carry means the index is reserved.
        JP C,PAGE_BAD              ; No directory or bitmap writes occur on failure.
        LD HL,(PAGE_IDX)           ; Reject the fixed upper metadata band as well.
        LD DE,(PAGE_LO)            ; The band begins at the first upper page.
        OR A                       ; Clear carry before the upper-band compare.
        SBC HL,DE
        JR C,.NOT_META             ; A low-extent index is not in that band.
        LD DE,SRTMHIGH             ; Compare the offset with the reserved count.
        OR A                       ; Clear carry before subtracting the count.
        SBC HL,DE
        JP C,PAGE_BAD              ; A release starting in metadata is invalid.
.NOT_META:
        LD HL,(PAGE_IDX)           ; Add the requested run length to its start.
        LD DE,(PAGE_RUN)           ; DE carries the complete release length.
        ADD HL,DE                  ; The result is the exclusive ending index.
        LD (PAGE_END),HL           ; Preserve the end while checking the extents.
        LD DE,(PAGE_LO)            ; The low extent cannot cross the closure gap.
        OR A                       ; Clear carry before the extent comparison.
        SBC HL,DE                  ; A carry or zero keeps the run in the low extent.
        JR C,.RUN                  ; The run ends before the second extent.
        JR Z,.RUN                  ; The run ends exactly at the low extent boundary.
        LD HL,(PAGE_IDX)           ; A high-extent run may continue to its end.
        LD DE,(PAGE_LO)            ; Compare its virtual start with the boundary.
        OR A                       ; Clear carry before the start comparison.
        SBC HL,DE                  ; A nonnegative start belongs to the high extent.
        JR NC,.RUN                 ; High runs still need the total-bound check.
        JP PAGE_BAD                ; A low run crossing the gap is invalid.
.RUN:
        LD HL,(PAGE_END)           ; Recover the checked exclusive run end.
        LD DE,(PAGE_CNT)           ; Compare it with the complete virtual domain.
        OR A                       ; Clear carry before the upper-bound comparison.
        SBC HL,DE                  ; Carry or zero means that the run remains inside.
        JR C,.RUN_OK               ; A carry means the run ends below the boundary.
        JR Z,.RUN_OK               ; An equal end address is the exact boundary.
        JP PAGE_BAD                ; A positive result would cross the end.
.RUN_OK:
        LD HL,(PAGE_DIR)           ; Begin validating the exact directory states.
        LD DE,(PAGE_IDX)           ; Add the release start to the directory base.
        ADD HL,DE                  ; HL names the first state being released.
        LD BC,(PAGE_RUN)           ; BC counts every entry that must be allocated.
.CHECK:
        LD A,B                     ; Test the remaining validation count.
        OR C                       ; Zero means all entries are allocated as expected.
        JR Z,.COMMIT               ; Commit the release only after this validation.
        LD A,(HL)                  ; Read the directory ownership state.
        CP 1                       ; Only an allocated entry may be released.
        JP NZ,PAGE_BAD             ; This also catches a double free atomically.
        INC HL                     ; Advance to the next state in the requested run.
        DEC BC                     ; Consume one validated allocated page.
        JR .CHECK                  ; Continue until the complete run is checked.
.COMMIT:
        LD BC,(PAGE_RUN)           ; Commit exactly the validated run length.
.FREE:
        LD A,B                     ; Test the remaining release count.
        OR C                       ; Zero means all pages have been returned.
        JR Z,.DONE                 ; Finish the free-count update below.
        CALL PAGE_SET              ; Set this page's free bit in the bitmap.
        LD HL,(PAGE_DIR)           ; Locate the corresponding directory entry.
        LD DE,(PAGE_IDX)           ; Add the current index to its base address.
        ADD HL,DE                  ; HL names the entry being released.
        XOR A                      ; State zero denotes a free page.
        LD (HL),A                  ; Publish the free state after setting its bit.
        LD HL,(PAGE_IDX)           ; Advance to the following page index.
        INC HL                     ; Move through the validated contiguous run.
        LD (PAGE_IDX),HL           ; Keep the release cursor in the state block.
        DEC BC                     ; Consume one returned page.
        JR .FREE                  ; Continue until every page is free again.
.DONE:
        LD HL,(PAGE_CAP)           ; Add the returned run to the free-page count.
        LD DE,(PAGE_RUN)           ; DE carries the exact number of released pages.
        ADD HL,DE                  ; The validation proves the count cannot overflow.
        LD (PAGE_CAP),HL           ; Publish the restored free-page capacity.
        XOR A                      ; Successful release returns A=0 and carry clear.
        RET                        ; The caller's page state is now fully consistent.

; Return carry and status three when no successful page initialisation exists.
PAGE_CHK:
        LD A,(PAGE_OK)             ; Read the explicit page-domain readiness flag.
        OR A                       ; A zero state rejects allocation and release calls.
        RET NZ                      ; The caller continues with a ready domain.
        LD A,3                     ; Status three denotes an uninitialised domain.
        SCF                        ; Carry distinguishes the failure from success.
        RET                        ; No page memory has been touched on this path.

; Common capacity and invalid-request returns keep failure codes consistent.
PAGE_OUT:
        LD A,1                     ; Status one denotes exhausted or oversized capacity.
        SCF                        ; Carry reports that no state was committed.
        RET                        ; The caller can distinguish capacity from syntax.
PAGE_BAD:
        LD A,2                     ; Status two denotes an invalid page request.
        SCF                        ; Carry reports the atomic validation failure.
        RET                        ; Existing page ownership remains unchanged.
PAGE_ERR:
        LD A,2                     ; An image that leaves no valid domain is invalid.
        SCF                        ; Startup failure occurs before metadata writes.
        RET                        ; The caller can reject this runtime layout.

; Locate the bitmap byte and mask for the index in PAGE_IDX.
PAGE_AT:
        LD HL,(PAGE_IDX)           ; Read the page index being changed or tested.
        LD A,L                     ; The domain has fewer than 256 pages.
        AND 7                       ; Keep the bit position within its bitmap byte.
        LD E,A                     ; Use that position as the mask-table offset.
        LD D,0                     ; The table contains one byte per bit position.
        LD HL,PAGE_POW             ; Begin at the first power-of-two mask.
        ADD HL,DE                  ; Select the mask for this page's bit.
        LD A,(HL)                  ; Read the selected bit mask.
        LD (PAGE_BIT),A            ; Preserve it while locating the byte.
        LD HL,(PAGE_IDX)           ; Recover the original index for division.
        LD A,L                     ; The bitmap byte index begins with the low byte.
        SRL A                      ; Divide the page index by two.
        SRL A                      ; Divide by four.
        SRL A                      ; Divide by eight to select a bitmap byte.
        LD L,A                     ; Widen the byte index to a word.
        LD H,0                     ; The bitmap byte index has no high byte here.
        LD DE,(PAGE_MAP)           ; Add the bitmap base to the byte index.
        ADD HL,DE                  ; Return HL as the exact bitmap-byte address.
        RET                        ; PAGE_BIT supplies the corresponding bit mask.

; Set the free bit for the current page index.
PAGE_SET:
        CALL PAGE_AT               ; Locate the bitmap byte and selected mask.
        LD A,(HL)                  ; Read the current bitmap ownership bits.
        LD D,A                     ; Preserve those neighboring bits across the lookup.
        LD A,(PAGE_BIT)            ; Recover the selected free-bit mask.
        OR D                       ; Set one page free without changing neighbors.
        LD (HL),A                  ; Publish the free bit in the bitmap byte.
        RET                        ; The caller's BC counter remains untouched.

; Clear the free bit for the current page index.
PAGE_CLR:
        CALL PAGE_AT               ; Locate the bitmap byte and selected mask.
        LD A,(PAGE_BIT)            ; Recover the bit that denotes this page.
        CPL                         ; Invert it to form an AND clearing mask.
        LD E,A                     ; Preserve the inverted mask across the read.
        LD A,(HL)                  ; Read the current bitmap ownership bits.
        AND E                       ; Clear one page while preserving its neighbors.
        LD (HL),A                  ; Publish the allocated bit in the bitmap byte.
        RET                        ; The caller's BC counter remains untouched.

; Page-domain state and the eight one-bit masks used by PAGE_AT.
