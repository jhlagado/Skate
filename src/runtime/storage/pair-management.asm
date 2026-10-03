; Manage pair slab free chains and validate tagged pair addresses.
;
; The allocator owns one three-byte descriptor per possible page.  Its page
; byte is zero after a wholly dead slab is returned to the page manager; the
; remaining descriptor fields are then available for reuse by .ADD_PAGE.

; Rebuild every free-record chain and the available-slab list after a sweep.
; The collector has already cleared dead states, so this pass can link only
; records whose allocation bit is clear.  It also returns empty slabs to the
; page allocator and keeps partially occupied slabs available.
PAIR_GC:
        XOR A
        LD (PS_HEAD),A              ; Rebuild the slab list from an empty head.
        LD A,(PS_COUNT)
        OR A
        RET Z
        LD B,A                      ; B counts the assigned slab-table entries.
        LD A,1
        LD (PS_INDEX),A             ; The available list stores one-based indices.
        LD HL,PS_TABLE
PAIR_ONE:
        LD (PS_DESC),HL            ; Preserve this descriptor for its result fields.
        LD DE,3
        ADD HL,DE
        LD (PS_SAVE),HL             ; Preserve the following descriptor.
        LD HL,(PS_DESC)
        LD A,(HL)                   ; A zero page byte denotes a released descriptor.
        OR A
        JP Z,PAIR_END               ; Keep holes out of all class lists and scans.
        LD D,A                      ; Read the page number; its low address byte is zero.
        LD E,0
        LD (PS_BASE),DE             ; Keep the current slab across record scans.
        XOR A
        LD (PS_FIRST),A             ; No free record has been found yet.
        LD (PS_FIRST+1),A
        LD (PS_LAST),A              ; No predecessor exists before the first free record.
        LD (PS_LAST+1),A
        LD (PS_LIVE),A              ; Count live records to identify an empty slab.
        LD (PS_RECP),DE              ; Begin with record zero in this slab.
        LD C,PAIR_CAP               ; Inspect all complete eight-byte records.
.REC_LOOP:
        LD HL,(PS_RECP)
        LD DE,CAR_TAG
        ADD HL,DE                   ; Read the packed allocation state.
        LD A,(HL)
        AND 40H
        JR Z,.FREE                  ; An unallocated record enters the free chain.
        LD A,(PS_LIVE)
        INC A
        LD (PS_LIVE),A              ; Live records keep this slab assigned.
        JR .REC_NEXT
.FREE:
        LD HL,(PS_RECP)             ; Recover the free record's start address.
        LD DE,(PS_FIRST)
        LD A,D
        OR E
        JR NZ,.LINK                 ; Link this record after the previous free one.
        LD (PS_FIRST),HL            ; This is the first free record in the slab.
        LD (PS_LAST),HL             ; It is also the predecessor for the next one.
        JR .REC_NEXT
.LINK:
        LD DE,(PS_LAST)              ; Store the current offset in the predecessor.
        LD A,L                      ; All records in one page share the high byte.
        LD (DE),A
        INC DE
        XOR A
        LD (DE),A
        LD (PS_LAST),HL             ; The current record becomes the predecessor.
.REC_NEXT:
        LD HL,(PS_RECP)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (PS_RECP),HL
        DEC C
        JR NZ,.REC_LOOP
        LD A,(PS_LIVE)
        OR A
        JR Z,PAIR_REL                ; No live record lets the page return to the pool.
        LD HL,(PS_FIRST)
        LD A,H
        OR L
        JR Z,PAIR_OFF                ; A live full slab leaves no available record.
PAIR_PUT:
        LD HL,(PS_FIRST)
        LD A,L                      ; Publish the first free offset in descriptor byte two.
        LD HL,(PS_DESC)
        LD DE,2
        ADD HL,DE
        LD (HL),A
        LD DE,(PS_LAST)              ; Terminate the rebuilt free chain.
        LD A,0FFH
        LD (DE),A
        INC DE
        XOR A
        LD (DE),A
        LD HL,(PS_DESC)             ; Link this available slab to the old head.
        LD DE,1
        ADD HL,DE
        LD A,(PS_HEAD)
        LD (HL),A
        LD A,(PS_INDEX)
        LD (PS_HEAD),A              ; The current slab becomes the new list head.
        JR PAIR_END
PAIR_REL:
        PUSH BC                     ; The page release helper uses BC internally.
        LD HL,(PS_BASE)
        LD DE,1
        CALL PAGE_REL               ; Return an entirely dead slab to the page pool.
        POP BC
        JR C,PAIR_PUT              ; Keep the slab available if release is unavailable.
        LD HL,(PS_DESC)
        XOR A
        LD (HL),A                   ; Zero page byte marks the descriptor as reusable.
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        JR PAIR_END
PAIR_OFF:
        LD HL,(PS_DESC)
        LD DE,1
        ADD HL,DE
        XOR A
        LD (HL),A                   ; Full slabs have no available-list successor.
        INC HL
        LD A,0FFH
        LD (HL),A                   ; Keep full slabs out of future allocation.
PAIR_END:
        LD A,(PS_INDEX)
        INC A
        LD (PS_INDEX),A
        LD HL,(PS_SAVE)
        DEC B
        JP NZ,PAIR_ONE
        RET

; Check A:HL and return carry clear only for a live pair pointer.  Pair pages
; are allocated on 256-byte boundaries and records are eight-byte aligned, so
; the descriptor scan only has to establish that the page is assigned.  The
; old check walked every record on every page; using the candidate's slot here
; keeps the same interior/free-record safety with a bounded descriptor scan.
PAIR_CHK:
        CP 1                        ; Only the public pair tag can name a record.
        JR NZ,.BAD                  ; Other values are never valid pair pointers.
        LD (PS_PAIR),HL             ; Preserve the candidate during page checks.
        LD A,L
        AND 7
        JR NZ,.BAD                  ; Interior and unaligned addresses are invalid.
        LD A,L
        CP 0F9H
        JR NC,.BAD                  ; The final valid slot starts at F8H.
        LD A,(PS_COUNT)             ; An empty class has no valid pair address.
        OR A
        JR Z,.BAD
        LD B,A                      ; B counts slab entries in the class table.
        LD DE,PS_TABLE              ; DE walks the three-byte slab descriptors.
.PAGE:
        LD A,(DE)                   ; Read the slab page number.
        OR A
        JR Z,.SKIP                  ; Released descriptors still consume a slot.
        CP H                        ; The candidate high byte names its page.
        JR Z,.FOUND
.SKIP:
        LD A,E
        ADD A,3
        LD E,A
        JR NC,.NEXT
        INC D
.NEXT:
        DJNZ .PAGE
        JR .BAD                     ; No assigned slab owns the candidate page.
.FOUND:
        LD HL,(PS_PAIR)             ; Recover the validated page-and-slot address.
        LD DE,CAR_TAG               ; The CAR metadata follows its payload.
        ADD HL,DE
        LD A,(HL)                   ; Read allocation and mark bits.
        AND 40H                     ; A live allocation is required for validity.
        JR Z,.BAD
        LD HL,(PS_PAIR)             ; Return the original pair pointer unchanged.
        XOR A                       ; Carry clear identifies a live pair.
        RET
.BAD:
        SCF                         ; A non-pair or free record is rejected.
        RET
