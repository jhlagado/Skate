; Manage pair slab free chains and validate tagged pair addresses.
;
; The allocator owns one three-byte descriptor per possible page.  Its page
; byte is zero after a wholly dead slab is returned to the page manager; the
; remaining descriptor fields are then available for reuse by SRTPSADD.

; Rebuild every free-record chain and the available-slab list after a sweep.
; The collector has already cleared dead states, so this pass can link only
; records whose allocation bit is clear.  It also returns empty slabs to the
; page allocator and keeps partially occupied slabs available.
SRTPSRB:
        XOR A
        LD (SRTPSLHD),A             ; Rebuild the slab list from an empty head.
        LD A,(SRTPSLBN)
        OR A
        RET Z
        LD B,A                      ; B counts the assigned slab-table entries.
        LD A,1
        LD (SRTPSIDX),A             ; The available list stores one-based indices.
        LD HL,SRTPSLT
SRTPSRBS:
        LD (SRTPSDP),HL            ; Preserve this descriptor for its result fields.
        LD DE,3
        ADD HL,DE
        LD (SRTPSST),HL             ; Preserve the following descriptor.
        LD HL,(SRTPSDP)
        LD A,(HL)                   ; A zero page byte denotes a released descriptor.
        OR A
        JP Z,SRTPSRBX               ; Keep holes out of all class lists and scans.
        LD D,A                      ; Read the page number; its low address byte is zero.
        LD E,0
        LD (SRTPSBA),DE             ; Keep the current slab across record scans.
        XOR A
        LD (SRTPSFST),A             ; No free record has been found yet.
        LD (SRTPSFST+1),A
        LD (SRTPSFLK),A             ; No predecessor exists before the first free record.
        LD (SRTPSFLK+1),A
        LD (SRTPSLV),A              ; Count live records to identify an empty slab.
        LD (SRTPSCAN),DE             ; Begin with record zero in this slab.
        LD C,51                     ; Inspect all complete five-byte records.
SRTPSRBR:
        LD HL,(SRTPSCAN)
        LD DE,4
        ADD HL,DE                   ; Read the packed allocation state.
        LD A,(HL)
        AND 40H
        JR Z,SRTPSRF                ; An unallocated record enters the free chain.
        LD A,(SRTPSLV)
        INC A
        LD (SRTPSLV),A              ; Live records keep this slab assigned.
        JR SRTPSRBN
SRTPSRF:
        LD HL,(SRTPSCAN)            ; Recover the free record's start address.
        LD DE,(SRTPSFST)
        LD A,D
        OR E
        JR NZ,SRTPSRBL              ; Link this record after the previous free one.
        LD (SRTPSFST),HL            ; This is the first free record in the slab.
        LD (SRTPSFLK),HL            ; It is also the predecessor for the next one.
        JR SRTPSRBN
SRTPSRBL:
        LD DE,(SRTPSFLK)             ; Store the current offset in the predecessor.
        LD A,L                      ; All records in one page share the high byte.
        LD (DE),A
        INC DE
        XOR A
        LD (DE),A
        LD (SRTPSFLK),HL            ; The current record becomes the predecessor.
SRTPSRBN:
        LD HL,(SRTPSCAN)
        LD DE,5
        ADD HL,DE
        LD (SRTPSCAN),HL
        DEC C
        JR NZ,SRTPSRBR
        LD A,(SRTPSLV)
        OR A
        JR Z,SRTPSREM                ; No live record lets the page return to the pool.
        LD HL,(SRTPSFST)
        LD A,H
        OR L
        JR Z,SRTPSRBF                ; A live full slab leaves no available record.
SRTPSRFA:
        LD HL,(SRTPSFST)
        LD A,L                      ; Publish the first free offset in descriptor byte two.
        LD HL,(SRTPSDP)
        LD DE,2
        ADD HL,DE
        LD (HL),A
        LD DE,(SRTPSFLK)             ; Terminate the rebuilt free chain.
        LD A,0FFH
        LD (DE),A
        INC DE
        XOR A
        LD (DE),A
        LD HL,(SRTPSDP)             ; Link this available slab to the old head.
        LD DE,1
        ADD HL,DE
        LD A,(SRTPSLHD)
        LD (HL),A
        LD A,(SRTPSIDX)
        LD (SRTPSLHD),A             ; The current slab becomes the new list head.
        JR SRTPSRBX
SRTPSREM:
        PUSH BC                     ; The page release helper uses BC internally.
        LD HL,(SRTPSBA)
        LD DE,1
        CALL SRTGPREL               ; Return an entirely dead slab to the page pool.
        POP BC
        JR C,SRTPSRFA              ; Keep the slab available if release is unavailable.
        LD HL,(SRTPSDP)
        XOR A
        LD (HL),A                   ; Zero page byte marks the descriptor as reusable.
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        JR SRTPSRBX
SRTPSRBF:
        LD HL,(SRTPSDP)
        LD DE,1
        ADD HL,DE
        XOR A
        LD (HL),A                   ; Full slabs have no available-list successor.
        INC HL
        LD A,0FFH
        LD (HL),A                   ; Keep full slabs out of future allocation.
SRTPSRBX:
        LD A,(SRTPSIDX)
        INC A
        LD (SRTPSIDX),A
        LD HL,(SRTPSST)
        DEC B
        JP NZ,SRTPSRBS
        RET

; Check A:HL and return carry clear only for a live pair pointer.
SRTPCHK:
        CP 1                        ; Only the public pair tag can name a record.
        JR NZ,SRTNPAIR              ; Other values are never valid pair pointers.
        LD (SRTPSAD),HL             ; Preserve the candidate during slab walking.
        LD A,(SRTPSLBN)             ; An empty class has no valid pair address.
        OR A
        JR Z,SRTNPAIR
        LD B,A                      ; B counts slab entries in the class table.
        LD DE,SRTPSLT               ; DE walks the three-byte slab descriptors.
SRTPCS:
        LD A,(DE)                   ; Read the slab page number.
        OR A
        JR Z,SRTPCSK                ; Released descriptors contain no records.
        LD H,A                      ; The low address byte is zero.
        LD L,0
        INC DE                      ; Skip the next-list and free-head fields.
        INC DE
        INC DE                      ; DE now names the following descriptor.
        LD (SRTPSST),DE             ; Keep the table cursor across comparisons.
        LD (SRTPSBA),HL             ; Preserve the base across record comparisons.
        LD (SRTPSCAN),HL            ; Begin at record zero in this slab.
        LD C,51                     ; Check every possible five-byte record.
SRTPCREC:
        LD HL,(SRTPSCAN)            ; Load the current record address.
        LD DE,(SRTPSAD)             ; Compare it with the candidate pointer.
        LD A,H                      ; Compare high bytes without changing the cursor.
        CP D                        ; A mismatch skips the state-byte read.
        JR NZ,SRTPCN                ; Continue with the next record.
        LD A,L                      ; Compare low bytes after the high byte matched.
        CP E                        ; A mismatch still leaves the candidate invalid.
        JR NZ,SRTPCN                ; Continue with the next record.
        LD DE,4                     ; The flags byte follows both payloads.
        ADD HL,DE                   ; HL now addresses the candidate state.
        LD A,(HL)                   ; Read allocation and mark bits.
        AND 40H                     ; An allocated bit is required for validity.
        JR NZ,SRTPCYES              ; The caller may safely read both fields.
SRTPCN:
        LD HL,(SRTPSCAN)            ; Recover the record start before advancing.
        LD DE,5                     ; Move to the next five-byte record.
        ADD HL,DE                   ; Advance by one complete five-byte record.
        LD (SRTPSCAN),HL            ; Preserve the cursor for the next iteration.
        DEC C                       ; Consume one position in this slab.
        JR NZ,SRTPCREC              ; Continue until every record was checked.
        LD DE,(SRTPSST)             ; Restore the next slab-table entry.
        DJNZ SRTPCS                 ; Search the next slab when this one misses.
        JR SRTNPAIR                 ; No allocated record has the requested address.
SRTPCSK:
        INC DE                      ; Skip the three bytes of a released descriptor.
        INC DE
        INC DE
        DJNZ SRTPCS
        JR SRTNPAIR
SRTPCYES:
        LD HL,(SRTPSAD)             ; Return the original pair pointer unchanged.
        XOR A                       ; Carry clear identifies a live pair.
        RET
SRTNPAIR:
        SCF                         ; A non-pair or free record is rejected.
        RET
