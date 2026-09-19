;=============================================================================
;  Skate M2 cell allocator
;=============================================================================

;  PURPOSE
;  -------
;  Manage checked arena geometry and the cell-reservation protocol.

;  PUBLIC INTERFACE
;  ----------------
;

;+---------------------------------------------------------------------------+
;|  HINIT - Validate the arena and build its free list.                      |
;|                                                                           |
;|  CALL                                                                     |
;|    HL = arena base.                                                       |
;|    BC = physical cell count (2..8192).                                    |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  HRES - Open a reservation for the requested cells.                       |
;|                                                                           |
;|  CALL                                                                     |
;|    BC = number of cells to reserve.                                       |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  HPOP - Take the next cell from the active reservation.                   |
;|                                                                           |
;|  RETURNS                                                                  |
;|    HL = cell index; DE = cell address.                                    |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  HDONE - Close a fully consumed reservation.                              |
;|                                                                           |
;|  CALL                                                                     |
;|    Call after the caller publishes the reserved cells.                    |
;+---------------------------------------------------------------------------+

;  SHARED RESULTS AND OWNERSHIP
;  ----------------------------
;
;  SUCCESS    A = 0; carry clear.
;  ERROR 1    Capacity.
;  ERROR 2    Range.
;  ERROR 3    Protocol.
;  FAILURE    Allocator state and heap bytes remain unchanged.
;  REGISTERS  AF/BC/DE/HL are clobbered except for stated results.
;             IX/IY are preserved; SP is balanced.
;  REENTRY    Static state makes the allocator non-reentrant.
;  LIMITS     No GC, callbacks, constructors or interrupt-time entry.
;  MEMORY     Keep the arena disjoint from code, allocator state and stack.
;=============================================================================

; Validate the arena before committing any state or heap write.
HINIT:
    LD A,(HACTIVE)         ; Read the construction lock before considering reinitialization.
    OR A                   ; Test whether a reservation is still active.
    JP NZ,HPROTERR           ; Reject reinitialization during construction.
    ; Physical count is in [2,8192]; validate without changing state.
    LD A,B                 ; Check the high byte of the physical cell count.
    CP 20H                 ; 8192 cells have high byte 20H and low byte zero.
    JP C,HINITLOW            ; A smaller high byte needs the lower-bound check.
    JP NZ,HRANGEER           ; A larger high byte exceeds the index space.
    LD A,C                 ; At exactly high byte 20H, inspect the low byte.
    OR A                   ; Only a zero low byte gives exactly 8192.
    JP NZ,HRANGEER           ; Reject counts above 8192.
    JP HINITEND            ; The maximum count is valid; check its arena endpoint.
; Check the minimum after the upper-bound comparison.
HINITLOW:
    OR A                   ; B is still in A; a nonzero high byte implies at least 256 cells.
    JP NZ,HINITEND         ; Counts of 256 or more already satisfy the minimum.
    LD A,C                 ; For smaller counts, the low byte is the whole count.
    CP 2                   ; Require cell zero plus at least one usable cell.
    JP C,HRANGEER            ; Reject counts zero and one.
; Validate base + 4*count, allowing an exclusive endpoint of 65536.
HINITEND:
    EX DE,HL               ; Keep the arena base in DE while HL computes its extent.
    LD H,B                 ; Copy the physical count's high byte into HL.
    LD L,C                 ; HL now holds the physical cell count.
    ADD HL,HL              ; Convert the count to a two-byte extent.
    ADD HL,HL              ; HL now holds the four-byte-cell arena size.
    ADD HL,DE              ; Add the base to obtain the exclusive arena endpoint.
    JP NC,HINITCOM         ; Without wraparound, the endpoint is within memory.
    ; A carry is allowed only for the exact mathematical end 65536.
    LD A,H                 ; Inspect the wrapped endpoint's high byte.
    OR L                   ; A wrapped result of zero means the endpoint was exactly 65536.
    JP NZ,HRANGEER           ; Any other wrapped endpoint extends beyond memory.
; Commit the validated geometry and build the free list.
HINITCOM:
    ; All rejecting checks are complete. Cell zero is never written.
    LD (HBASE),DE          ; Publish the validated arena base.
    LD (HCOUNT),BC         ; Record the physical count, including cell zero.
    LD H,B                 ; Copy the physical count for the usable-cell calculation.
    LD L,C                 ; HL now holds the physical count.
    DEC HL                 ; Exclude reserved cell zero.
    LD (HFCOUNT),HL        ; Initially every usable cell is free.
    LD HL,1                ; The first usable cell starts the free list.
    LD (HHEAD),HL          ; Publish free-list head index one.
    LD HL,0                ; No reservation exists after initialization.
    LD (HLEFT),HL          ; Clear the remaining-pop count.
    XOR A                  ; Prepare a zero state byte.
    LD (HACTIVE),A         ; Clear the construction lock.
    DEC BC                 ; BC becomes the number of cells still to initialize.
    LD HL,(HBASE)          ; Start from the arena base.
    LD DE,4                ; Each cell occupies four bytes.
    ADD HL,DE              ; Skip reserved cell zero without writing it.
    LD DE,2                ; Cell one's next link is initially index two.
; HL addresses the current cell; BC counts cells left; DE is its successor.
HINITLOP:
    LD A,B                 ; Inspect the high byte of the remaining-cell count.
    OR A                   ; A nonzero high byte means this cannot be the last cell.
    JP NZ,HINITWR         ; Write a normal successor link while more than one cell remains.
    LD A,C                 ; With B zero, C is the remaining-cell count.
    CP 1                   ; Check for the final usable cell.
    JP NZ,HINITWR         ; Earlier cells retain their successor index in DE.
    LD DE,0                ; Terminate the final cell's link with index zero.
; Store one free cell as [next index, zero word].
HINITWR:
    LD (HL),E              ; Write the low byte of the next free index.
    INC HL                 ; Advance to the link's high byte.
    LD (HL),D              ; Write the high byte of the next free index.
    INC HL                 ; Advance to the cell's second word.
    XOR A                  ; Prepare zero for the unused second word.
    LD (HL),A              ; Clear the second word's low byte.
    INC HL                 ; Advance to its high byte.
    LD (HL),A              ; Clear the second word's high byte.
    INC HL                 ; Advance to the next cell's first byte.
    INC DE                 ; Prepare the successor index for the next cell.
    DEC BC                 ; One fewer cell remains to initialize.
    LD A,B                 ; Test the remaining count's high byte.
    OR C                   ; Combine both bytes to detect completion.
    JP NZ,HINITLOP          ; Continue until every usable cell is linked.
    LD A,1                 ; Prepare the initialized-state flag.
    LD (HREADY),A          ; Publish readiness only after the entire list exists.
    JP HSUCCESS                 ; Return success with carry clear.

; Reserve capacity atomically; actual removal is deferred to HPOP.
HRES:
    LD A,(HREADY)          ; Read the initialization flag.
    OR A                   ; Test whether an arena has been initialized.
    JP Z,HPROTERR            ; A reservation needs an initialized free list.
    LD A,(HACTIVE)         ; Read the construction lock.
    OR A                   ; Test whether another reservation owns it.
    JP NZ,HPROTERR           ; Reject nested reservations.
    LD HL,(HCOUNT)         ; Load the arena's physical cell count.
    DEC HL                 ; Exclude cell zero to get maximum possible capacity.
    OR A                   ; Clear carry before the unsigned subtraction.
    SBC HL,BC              ; Compare total usable capacity against requested BC cells.
    JP C,HRANGEER            ; A borrow means the request can never fit this arena.
    LD HL,(HFCOUNT)        ; Load the number of cells currently free.
    OR A                   ; Clear carry for a fresh unsigned comparison.
    SBC HL,BC              ; Compare available capacity against the request.
    JP C,HCAPERR              ; A borrow means collection may be needed before reserving.
    ; Reservation commits only its protocol state; no cells are removed yet.
    LD (HLEFT),BC          ; Record how many pops this reservation permits.
    LD A,1                 ; Prepare the construction-lock value.
    LD (HACTIVE),A         ; Begin the reservation, including a zero-cell reservation.
    JP HSUCCESS                 ; Return success without removing any cells.

; Consume one reserved cell and erase its free-list representation.
HPOP:
    LD A,(HREADY)          ; Read the initialization flag.
    OR A                   ; Test whether initialization has completed.
    JP Z,HPROTERR            ; Reject a pop before initialization.
    LD A,(HACTIVE)         ; Read the reservation lock.
    OR A                   ; Test whether construction owns a reservation.
    JP Z,HPROTERR            ; Reject an unreserved pop.
    LD HL,(HLEFT)          ; Load the number of pops still permitted.
    LD A,H                 ; Test the remaining count's high byte.
    OR L                   ; Combine both bytes to detect an exhausted reservation.
    JP Z,HPROTERR            ; Reject an extra pop after the reservation is consumed.
    ; A successful reservation guarantees a valid nonzero free head.
    LD HL,(HHEAD)          ; Fetch the free head's cell index.
    LD B,H                 ; Save the index's high byte for the return value.
    LD C,L                 ; BC now preserves the returned cell index.
    ADD HL,HL              ; Begin converting the cell index to a byte offset.
    ADD HL,HL              ; HL now holds four times the index.
    LD DE,(HBASE)          ; Load the arena base.
    ADD HL,DE              ; HL now addresses the first byte of the free cell.
    LD E,(HL)              ; Read the successor index's low byte.
    INC HL                 ; Advance to the successor's high byte.
    LD D,(HL)              ; Read the successor index's high byte into DE.
    DEC HL                 ; Restore HL to the cell's first byte.
    LD (HHEAD),DE          ; Unlink this cell by publishing its successor as the head.
    ; Remove all free-list data before handing the cell to its constructor.
    XOR A                  ; Prepare zero for all four returned bytes.
    LD (HL),A              ; Clear the old link's low byte.
    INC HL                 ; Advance to byte one.
    LD (HL),A              ; Clear the old link's high byte.
    INC HL                 ; Advance to byte two.
    LD (HL),A              ; Clear the second word's low byte.
    INC HL                 ; Advance to byte three.
    LD (HL),A              ; Clear the second word's high byte.
    DEC HL                 ; Step back toward the cell's start.
    DEC HL                 ; Step back to byte one.
    DEC HL                 ; HL again addresses the cell's first byte.
    EX DE,HL               ; Keep the returned cell address in DE while updating counts.
    LD HL,(HFCOUNT)        ; Load the total free-cell count.
    DEC HL                 ; Account for the removed cell.
    LD (HFCOUNT),HL        ; Publish the reduced free count.
    LD HL,(HLEFT)          ; Load the reservation's remaining-pop count.
    DEC HL                 ; Consume one permitted pop.
    LD (HLEFT),HL          ; Publish the remainder; the reservation stays active even at zero.
    LD H,B                 ; Restore the saved cell index's high byte.
    LD L,C                 ; HL now holds the returned index; DE holds its address.
    JP HSUCCESS                 ; Return success without disturbing HL or DE.

; End construction only after all reserved cells have been consumed.
HDONE:
    LD A,(HREADY)          ; Read the initialization flag.
    OR A                   ; Test whether an arena exists.
    JP Z,HPROTERR            ; Reject closing before initialization.
    LD A,(HACTIVE)         ; Read the construction lock.
    OR A                   ; Test whether there is a reservation to close.
    JP Z,HPROTERR            ; Reject closing an inactive reservation.
    LD HL,(HLEFT)          ; Load the number of cells still promised to this constructor.
    LD A,H                 ; Test the remaining count's high byte.
    OR L                   ; Combine both bytes to detect an unfinished reservation.
    JP NZ,HPROTERR           ; Reject closing until every promised cell has been popped.
    XOR A                  ; Prepare a cleared construction lock.
    LD (HACTIVE),A         ; Release the reservation after caller publication.
; Shared success return; keep any HL/DE result intact.
HSUCCESS:
    XOR A                  ; Return A=0 and clear carry without altering result registers.
    RET                    ; Return through the caller's existing stack frame.
; Capacity failure can be handled by the collector retry wrapper.
HCAPERR:
    LD A,1                 ; Report insufficient free capacity.
    SCF                    ; Set the shared error indicator.
    RET                    ; Return without changing heap or allocator state.
; The supplied geometry or request exceeds the allocator range.
HRANGEER:
    LD A,2                 ; Report an invalid size or arena endpoint.
    SCF                    ; Set the shared error indicator.
    RET                    ; Return without changing heap or allocator state.
; The call violates the initialization/reservation protocol.
HPROTERR:
    LD A,3                 ; Report an invalid reservation or initialization state.
    SCF                    ; Set the shared error indicator.
    RET                    ; Return without changing heap or allocator state.

HEND:                      ; Exclusive end of allocator instructions.
HWORK:                     ; Start of the twelve-byte allocator state.
HBASE: DW 0                ; Arena base address.
HCOUNT: DW 0               ; Physical cells, including reserved cell zero.
HHEAD: DW 0                ; First free cell index; zero means no free cells.
HFCOUNT: DW 0              ; Number of cells on the free list.
HLEFT: DW 0                ; Pops still permitted by the active reservation.
HACTIVE: DB 0              ; Construction lock: one from successful HRES until HDONE.
HREADY: DB 0               ; One once HINIT has finished building the free list.
HWEND:                     ; Exclusive end of allocator state.
