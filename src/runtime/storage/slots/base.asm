; Runtime activation-slot addressing and inline load/store paths.
; SRTSADDR: A = slot index, returns HL = slot address. SRTSLOAD reads a slot;
; SRTSSTOR and SRTSASET write A:HL; SRTSCLR clears one slot. SRTPROM may
; allocate and collect before publishing a captured value. SRTCLSC copies captures.
; Slots hold payload, tag and flags inline until promotion, then point to a
; managed binding. SRTENV is the active-map base and SRTSROOT scans each slot.

SRTSPROM EQU 2                     ; Active-slot bit meaning payload is a pointer.

; Return the active four-byte slot address for the zero-based index in A.
SRTSADDR:
        LD L,A                     ; Widen the slot number before scaling it.
        LD H,0
        ADD HL,HL                   ; Two bytes cover the first half of the slot.
        ADD HL,HL                   ; Four bytes cover the complete slot.
        LD DE,(SRTENV)              ; The active map is the address-space base.
        ADD HL,DE
        RET                        ; HL names the slot's first byte.

; Clear the complete active map before captured pointers are expanded.
SRTMAPC:
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
SRTLINLD:
        LD E,(HL)                   ; Recover the payload low byte.
        INC HL
        LD D,(HL)                   ; Recover the payload high byte.
        INC HL
        LD A,(HL)                   ; Recover the inline value tag.
        LD (SRTSVTAG),A
        INC HL
        LD A,(HL)                   ; Bit zero records inline initialization.
        AND 1
        JP Z,SRTUNBD                ; Preserve the established unbound error.
        EX DE,HL                    ; Return the payload in HL.
        LD A,(SRTSVTAG)             ; Return the inline tag in A.
        RET

; Store A:HL in the inline slot addressed by DE and publish initialization last.
SRTLINST:
        LD (SRTSVTAG),A             ; Save the tag while writing both payload bytes.
        LD (SRTSVAL),HL             ; Save the payload for the final return.
        LD A,L
        LD (DE),A                   ; Publish the payload low byte first.
        INC DE
        LD A,H
        LD (DE),A                   ; Publish the complete payload.
        INC DE
        LD A,(SRTSVTAG)
        LD (DE),A                   ; Publish the inline tag.
        INC DE
        LD A,(DE)                   ; Preserve reserved inline flag bits.
        AND 0FEH
        OR 1                        ; The value is initialized after all fields.
        LD (DE),A
        LD A,(SRTSVTAG)
        LD HL,(SRTSVAL)
        RET

; Resolve an active slot index in B and return its representation flags in A.
; The common address calculation keeps the three write paths identical.
SRTSBASE:
        LD A,B
        CALL SRTSADDR
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTSFLG),A
        RET

; Load a value from active slot index A.
SRTSLOAD:
        CALL SRTSADDR               ; Convert the index to the four-byte slot.
        LD (SRTSADR),HL
        LD DE,3
        ADD HL,DE
        LD A,(HL)                   ; Inspect the representation flag.
        LD (SRTSFLG),A
        AND SRTSPROM
        JR NZ,SRTSLDP               ; Promoted slots delegate to the heap cell.
        LD HL,(SRTSADR)
        JP SRTLINLD
SRTSLDP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JP Z,SRTUNBD                ; A published promoted slot must have a cell.
        EX DE,HL
        JP SRTBLOAD

; Store A:HL through active slot index B.
SRTSSTOR:
        LD (SRTSVTAG),A             ; Save the value while finding the slot.
        LD (SRTSVAL),HL
        CALL SRTSBASE
        AND SRTSPROM
        JR NZ,SRTSSTP
        LD DE,(SRTSADR)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP SRTLINST
SRTSSTP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP SRTBSTOR

; Store A:HL through active slot index B, requiring prior initialization.
SRTSASET:
        LD (SRTSVTAG),A
        LD (SRTSVAL),HL
        CALL SRTSBASE
        AND SRTSPROM
        JR NZ,SRTSASTP
        LD A,(SRTSFLG)
        AND 1
        JP Z,SRTUNBD
        LD DE,(SRTSADR)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP SRTLINST
SRTSASTP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(SRTSVAL)
        LD A,(SRTSVTAG)
        JP SRTBSET

; Clear an active recursive slot while retaining its representation state.
SRTSCLR:
        CALL SRTSBASE
        AND SRTSPROM
        JR NZ,SRTSCLRP
        LD A,(SRTSFLG)
        AND 0FEH
        LD HL,(SRTSADR)
        LD DE,3
        ADD HL,DE
        LD (HL),A
        RET
SRTSCLRP:
        LD HL,(SRTSADR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP SRTCLRC

; Promote active slot A.  The inline slot remains the root until publication.
