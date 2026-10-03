; Runtime activation-slot addressing and inline load/store paths.
; SLOT_AT: A = slot index, returns HL = slot address. SLOT_GET reads a slot;
; SLOT_PUT and SLOT_SET write A:HL; SLOT_CLR clears one slot. SLOT_BOX may
; allocate and collect before publishing a captured value. MAP_ENV copies captures.
; Slots use the cell layout: payload in bytes 0 and 1, byte 2 clear, and byte
; 3 holding the tag in its low nibble with CELL_VAL (initialized) and SLOT_PTR
; (promoted) above it.  Until promotion a slot holds its value inline; after
; it, the payload points to a managed binding. SRTENV is the active-map base and SLOT_GC scans each slot.

SLOT_PTR EQU 20H                   ; Active-slot bit meaning payload is a pointer.

; Return the active four-byte slot address for the zero-based index in A.
SLOT_AT:
        LD L,A                     ; Widen the slot number before scaling it.
        LD H,0
        ADD HL,HL                   ; Two bytes cover the first half of the slot.
        ADD HL,HL                   ; Four bytes cover the complete slot.
        LD DE,(SRTENV)              ; The active map is the address-space base.
        ADD HL,DE
        RET                        ; HL names the slot's first byte.

; Clear the complete active map before captured pointers are expanded.
SLOT_INI:
        LD HL,(SRTENV)              ; The map base is the first byte to clear.
        LD BC,(SRTMAPB)             ; The map extent is four bytes per slot.
        LD A,B
        OR C
        RET Z                       ; A zero-slot procedure has no map bytes.
        XOR A
        LD (HL),A                   ; Seed the overlapping zero-fill copy.
        LD D,H                      ; Copy the seed address to the destination pair.
        LD E,L
        INC DE
        DEC BC                      ; One byte was already written directly.
        LD A,B
        OR C
        RET Z                       ; A one-byte extent needs no LDIR.
        LDIR                        ; Copy the zero seed through the whole map.
        RET

; Load an unpromoted value from the active slot address in HL.
SLOT_RD:
        LD E,(HL)                   ; Recover the payload low byte.
        INC HL
        LD D,(HL)                   ; Recover the payload high byte.
        INC HL
        INC HL                      ; Skip the extension byte.
        LD A,(HL)                   ; CELL_VAL records inline initialization.
        AND CELL_VAL
        JP Z,SRTUNBD                ; Preserve the established unbound error.
        LD A,(HL)
        AND 0FH                     ; Return the inline tag in A.
        LD (SRTSVTAG),A
        EX DE,HL                    ; Return the payload in HL.
        RET

; Store A:HL in the inline slot addressed by DE and publish initialization last.
SLOT_WR:
        LD (SRTSVTAG),A             ; Save the tag while writing both payload bytes.
        LD (SRTSVAL),HL             ; Save the payload for the final return.
        LD A,L
        LD (DE),A                   ; Publish the payload low byte first.
        INC DE
        LD A,H
        LD (DE),A                   ; Publish the complete payload.
        INC DE
        XOR A
        LD (DE),A                   ; The extension byte stays clear.
        INC DE
        LD A,(DE)                   ; Preserve the promotion and reserved flags.
        AND 0E0H
        LD L,A
        LD A,(SRTSVTAG)
        OR CELL_VAL                 ; The value is initialized after all fields.
        OR L
        LD (DE),A
        LD A,(SRTSVTAG)
        LD HL,(SRTSVAL)
        RET

; Resolve an active slot index in B and return its representation flags in A.
; The common address calculation keeps the three write paths identical.
SLOT_REF:
        LD A,B
        CALL SLOT_AT
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        RET

; Load a value from active slot index A.
SLOT_GET:
        CALL SLOT_AT                ; Convert the index to the four-byte slot.
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)                   ; Inspect the representation flag.
        LD (SRTSFLG),A
        AND SLOT_PTR
        JR NZ,.HEAP                 ; Promoted slots delegate to the heap cell.
        LD HL,(SRTSADR)
        JP SLOT_RD
.HEAP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,SRTUNBD                ; A published promoted slot must have a cell.
        EX DE,HL
        JP HEAP_GET

; Store A:HL through active slot index B.
SLOT_PUT:
        LD (SRTSVTAG),A             ; Save the value while finding the slot.
        LD (SRTSVAL),HL
        CALL SLOT_REF
        AND SLOT_PTR
        JR NZ,.HEAP
        LD DE,(SRTSADR)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP SLOT_WR
.HEAP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP HEAP_PUT

; Store A:HL through active slot index B, requiring prior initialization.
SLOT_SET:
        LD (SRTSVTAG),A
        LD (SRTSVAL),HL
        CALL SLOT_REF
        AND SLOT_PTR
        JR NZ,.HEAP
        LD A,(SRTSFLG)
        AND CELL_VAL
        JP Z,SRTUNBD
        LD DE,(SRTSADR)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP SLOT_WR
.HEAP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP HEAP_SET

; Clear an active recursive slot while retaining its representation state.
SLOT_CLR:
        CALL SLOT_REF
        AND SLOT_PTR
        JR NZ,.HEAP
        LD A,(SRTSFLG)
        AND 0FFH-CELL_VAL
        LD HL,(SRTSADR)
        LD DE,3
        ADD HL,DE
        LD (HL),A
        RET
.HEAP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP RT_EMPTY

; Promote active slot A.  The inline slot remains the root until publication.
