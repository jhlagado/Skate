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
        LD C,SRPPCAP                ; Inspect all complete eight-byte records.
SRTPSRBR:
        LD HL,(SRTPSCAN)
        LD DE,SRPCCARM
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
        LD DE,SRTPW
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

; Check A:HL and return carry clear only for a live pair pointer.  Pair pages
; are allocated on 256-byte boundaries and records are eight-byte aligned, so
; the descriptor scan only has to establish that the page is assigned.  The
; old check walked every record on every page; using the candidate's slot here
; keeps the same interior/free-record safety with a bounded descriptor scan.
SRTPCHK:
        CP 1                        ; Only the public pair tag can name a record.
        JR NZ,SRTNPAIR              ; Other values are never valid pair pointers.
        LD (SRTPSAD),HL             ; Preserve the candidate during page checks.
        LD A,L
        AND 7
        JR NZ,SRTNPAIR              ; Interior and unaligned addresses are invalid.
        LD A,L
        CP 0F9H
        JR NC,SRTNPAIR              ; The final valid slot starts at F8H.
        LD A,(SRTPSLBN)             ; An empty class has no valid pair address.
        OR A
        JR Z,SRTNPAIR
        LD B,A                      ; B counts slab entries in the class table.
        LD DE,SRTPSLT               ; DE walks the three-byte slab descriptors.
SRTPCPG:
        LD A,(DE)                   ; Read the slab page number.
        OR A
        JR Z,SRTPCAD                ; Released descriptors still consume a slot.
        CP H                        ; The candidate high byte names its page.
        JR Z,SRTPCFN
SRTPCAD:
        LD A,E
        ADD A,3
        LD E,A
        JR NC,SRTPCNX
        INC D
SRTPCNX:
        DJNZ SRTPCPG
        JR SRTNPAIR                 ; No assigned slab owns the candidate page.
SRTPCFN:
        LD HL,(SRTPSAD)             ; Recover the validated page-and-slot address.
        LD DE,SRPCCARM              ; The CAR metadata follows its payload.
        ADD HL,DE
        LD A,(HL)                   ; Read allocation and mark bits.
        AND 40H                     ; A live allocation is required for validity.
        JR Z,SRTNPAIR
        LD HL,(SRTPSAD)             ; Return the original pair pointer unchanged.
        XOR A                       ; Carry clear identifies a live pair.
        RET
SRTNPAIR:
        SCF                         ; A non-pair or free record is rejected.
        RET
