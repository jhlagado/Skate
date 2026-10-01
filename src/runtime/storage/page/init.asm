; Runtime page-domain initialisation and managed extents.
; SRTGPINI: HL = loaded image end; returns A=0/carry clear or A=2/carry set.
; SRTGPALL: HL = page count; returns HL = page address or A=1 capacity,
; A=2 invalid request or A=3 uninitialised, with carry set.
; SRTGPREL: HL = page address, DE = count; returns A=0 or A=2 invalid request
; or A=3 uninitialised, with carry set. The pool owns the gap below 9000H and
; the B800H..C000H high extent; maps and exact roots occupy 9000H..B800H.

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
