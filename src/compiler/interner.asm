; Permanent symbol and string interner.
; SYM_INIT: IX -> 14-byte context; success A=0/carry clear, failure A=2/carry set.
; SYM_ID: IX -> ready context, HL -> source bytes, BC = length; success HL is a
; stable ID, failure A=1 capacity, 2 bounds/data or 3 not-ready with carry set.
; IX+0/+2 descriptor base/capacity, +4/+6 byte-pool base/capacity,
; +8 entry count, +10 used pool bytes, +12 kind (0 symbol, 1 string), +13 ready.
; Configure these
; extents before SYM_INIT and keep them stable and disjoint from source and each
; other. Symbols use 3-byte descriptors and 1..31 ASCII bytes; strings use
; 4-byte descriptors and 0..255 arbitrary bytes. IX/IY are preserved; context,
; source, descriptors and pool remain unchanged on failure. Static scratch is
; non-reentrant.

SYM_INIT:               ; Validate configuration, then publish an empty ready context.
        CALL SYM_CTX       ; Check all 14 context bytes before indexed reads.
        RET C           ; Propagate the bounds error without touching persistent state.
        LD A,(IX+12)    ; Kind determines both length rules and descriptor stride.
        CP 2            ; Unsigned kinds zero and one are the only valid configurations.
        JP NC,SYM_BAD
        ADD A,3         ; Symbol stride 3; string stride 4.
        LD (SYM_STEP),A
        LD L,(IX+2)     ; Entry capacity is limited by the 13-bit public identity.
        LD H,(IX+3)
        LD DE,2001H
        OR A
        SBC HL,DE       ; Borrow means capacity is strictly below 8193.
        JP NC,SYM_BAD     ; 8193 and above cannot produce valid identities.
        ADD HL,DE       ; Recover capacity after the comparison subtraction.
        LD D,H
        LD E,L          ; Keep one copy for the three-byte case.
        ADD HL,HL       ; Two bytes per descriptor so far.
        LD A,(SYM_STEP)
        CP 3
        JR Z,.SYMBOL
        ADD HL,HL       ; String descriptor capacity in bytes: four times count.
        JR .SPAN
.SYMBOL:                  ; HL holds twice the capacity; DE holds one capacity.
        ADD HL,DE       ; Symbol descriptor capacity in bytes: three times count.
.SPAN:                    ; Both stride paths join with HL holding descriptor bytes.
        LD B,H
        LD C,L          ; BC now spans the complete descriptor capacity.
        LD L,(IX+0)
        LD H,(IX+1)     ; HL is its caller-supplied base address.
        CALL SYM_SPAN
        RET C           ; Propagate the bounds error without touching persistent state.
        LD L,(IX+4)     ; Validate the complete pool capacity independently.
        LD H,(IX+5)
        LD C,(IX+6)
        LD B,(IX+7)
        CALL SYM_SPAN
        RET C           ; Propagate the bounds error without touching persistent state.
        XOR A           ; All validation is complete; publish an empty table.
        LD (IX+8),A
        LD (IX+9),A
        LD (IX+10),A
        LD (IX+11),A
        INC A
        LD (IX+13),A    ; Ready is published after both counters.
        XOR A
        RET

SYM_ID:                 ; Validate a borrowed byte sequence before searching or writing.
        LD (SYM_SRC),HL  ; Preserve source registers across context validation.
        LD (SYM_LEN),BC
        CALL SYM_CTX
        RET C           ; Propagate the bounds error without touching persistent state.
        LD A,(IX+13)
        CP 1            ; Ready must match the value published by SYM_INIT.
        JP NZ,SYM_IDLE
        LD BC,(SYM_LEN)
        LD A,B          ; Every supported literal length fits a byte.
        OR A
        JP NZ,SYM_BAD
        LD A,(IX+12)
        ADD A,3
        LD (SYM_STEP),A  ; Recompute stride when switching between contexts.
        LD A,(IX+12)
        OR A
        JR NZ,.LEN_OK
        LD A,C          ; Symbols cannot be empty or exceed 31 bytes.
        OR A
        JP Z,SYM_BAD
        CP 32
        JP NC,SYM_BAD
.LEN_OK:                  ; Length fits the selected kind; source bounds remain unchecked.
        LD HL,(SYM_SRC)
        CALL SYM_SPAN      ; Prove the entire source extent before reading bytes.
        RET C           ; Propagate the bounds error without touching persistent state.
        LD A,(IX+12)
        OR A
        JR NZ,.SEARCH
        LD HL,(SYM_SRC)
        LD A,(SYM_LEN)
        LD B,A          ; Symbol length is nonzero, so DJNZ cannot wrap from zero.
.ASCII:                   ; HL scans the symbol, B counts its remaining nonzero bytes.
        BIT 7,(HL)      ; Every identifier byte must be seven-bit ASCII.
        JP NZ,SYM_BAD
        INC HL
        DJNZ .ASCII
.SEARCH:                 ; All input validation is complete; search before checking space.
        LD HL,0
        LD (SYM_IDX),HL   ; Search in insertion order for stable zero-based IDs.
        LD L,(IX+0)
        LD H,(IX+1)
        LD (SYM_DESC),HL
.NEXT:                     ; SYM_IDX/SYM_DESC identify the next occupied descriptor to inspect.
        LD HL,(SYM_IDX)
        LD E,(IX+8)
        LD D,(IX+9)
        OR A
        SBC HL,DE       ; Z means candidate ID reached the occupied-entry count.
        JR Z,.INSERT    ; All existing entries were compared before capacity checks.
        LD HL,(SYM_DESC)
        LD E,(HL)       ; Descriptor offset points into the packed byte pool.
        INC HL
        LD D,(HL)
        INC HL
        LD A,(SYM_LEN)
        CP (HL)         ; Compare byte values/lengths; NZ rejects this candidate.
        JR NZ,.ADVANCE  ; Different lengths cannot denote identical byte strings.
        OR A
        JP Z,.FOUND       ; Two empty strings need no source or pool reads.
        LD B,A
        LD L,(IX+4)
        LD H,(IX+5)
        ADD HL,DE       ; HL now addresses the candidate's pool bytes.
        LD DE,(SYM_SRC)
.COMPARE:               ; HL candidate, DE source, B remaining bytes of equal-length data.
        LD A,(DE)       ; Compare one source byte with the corresponding pool byte.
        CP (HL)         ; Compare byte values/lengths; NZ rejects this candidate.
        JR NZ,.ADVANCE
        INC DE
        INC HL
        DJNZ .COMPARE
        JP .FOUND
.ADVANCE:               ; A mismatch discards byte cursors and advances the descriptor.
        LD HL,(SYM_DESC)
        LD A,(SYM_STEP)
        LD E,A
        LD D,0
        ADD HL,DE       ; Move by exactly one descriptor, never by its byte length.
        LD (SYM_DESC),HL
        LD HL,(SYM_IDX)
        INC HL
        LD (SYM_IDX),HL
        JR .NEXT
.INSERT:                ; No equal entry exists; SYM_IDX equals count and SYM_DESC is free.
        LD L,(IX+8)
        LD H,(IX+9)
        LD E,(IX+2)
        LD D,(IX+3)
        OR A
        SBC HL,DE       ; No borrow means count is at or above descriptor capacity.
        JR NC,SYM_FULL     ; A new identity requires an unused descriptor.
        LD L,(IX+10)
        LD H,(IX+11)
        LD BC,(SYM_LEN)
        ADD HL,BC       ; Compute the prospective used-byte count before writing.
        JR C,SYM_FULL
        LD (SYM_USED),HL
        LD E,(IX+6)
        LD D,(IX+7)
        OR A
        SBC HL,DE       ; Compare prospective occupancy with configured pool capacity.
        JR C,.COMMIT    ; Borrow proves the insertion leaves unused pool bytes.
        JR NZ,SYM_FULL     ; Equality is allowed: the insertion may fill the pool.
.COMMIT:                ; Descriptor and pool checks passed; no error exit follows.
        LD HL,(SYM_DESC)
        LD E,(IX+10)
        LD D,(IX+11)    ; Old used-byte count is the new descriptor's offset.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SYM_LEN)
        LD (HL),A
        LD A,(IX+12)
        OR A
        JR Z,.COPY
        INC HL
        LD (HL),0       ; String lengths occupy a word; their high byte is zero.
.COPY:                     ; DE still holds the new entry offset from the descriptor stores.
        LD L,(IX+4)
        LD H,(IX+5)
        ADD HL,DE       ; Destination follows the last occupied pool byte.
        EX DE,HL
        LD HL,(SYM_SRC)
        LD BC,(SYM_LEN)
        LD A,B
        OR C
        JR Z,.PUBLISH   ; LDIR with zero would copy 65536 bytes, not zero bytes.
        LDIR            ; Bounds and disjoint source/destination were established.
.PUBLISH:               ; Descriptor and byte copy are complete; make the entry visible.
        LD HL,(SYM_USED)
        LD (IX+10),L
        LD (IX+11),H
        LD HL,(SYM_IDX)
        INC HL
        LD (IX+8),L
        LD (IX+9),H     ; Publish the new entry count after its descriptor and bytes.
.FOUND:                   ; Search hit and successful insertion share the same ID result.
        LD HL,(SYM_IDX)   ; The caller receives identity, never a pool address.
        XOR A
        RET

; Context validation uses its final byte, allowing a context ending at 65536.
SYM_CTX:                   ; Only address arithmetic occurs before proving the context extent.
        PUSH IX
        POP HL
        LD DE,13
        ADD HL,DE
        JR C,SYM_BAD
        OR A
        RET
; HL base + BC extent may wrap only to zero, the exact 65536 endpoint.
SYM_SPAN:                  ; C after ADD denotes crossing the 16-bit address boundary.
        ADD HL,BC       ; Compute the exclusive endpoint; carry alone is not an error.
        JR NC,.OK       ; No carry means the endpoint remains below 65536.
        LD A,H          ; With carry set, only a zero wrapped result means exact fit.
        OR L            ; Test both endpoint bytes; this instruction clears carry.
        JR NZ,SYM_BAD     ; A nonzero wrapped endpoint exceeds the address space.
.OK:                    ; Accept no wrap or the exact endpoint, then normalize success flags.
        XOR A
        RET
SYM_FULL:                  ; No caller-owned table bytes have changed on capacity failures.
        LD A,1          ; Descriptor or byte capacity has been exhausted.
        SCF
        RET
SYM_BAD:                  ; Bounds/type validation also precedes every persistent write.
        LD A,2          ; Input/configuration cannot fit the published representation.
        SCF
        RET
SYM_IDLE:                ; Only an initialized context provides meaningful table geometry.
        LD A,3          ; A valid context must be initialized before interning.
        SCF
        RET
.CODE_END:
.WORK:
SYM_SRC: DW 0            ; Borrowed address of the incoming literal bytes.
SYM_LEN: DW 0            ; Incoming byte count, validated to 0..255.
SYM_IDX: DW 0             ; Identity of the current comparison/insertion candidate.
SYM_DESC: DW 0           ; Address of that candidate's packed descriptor.
SYM_USED: DW 0          ; Prospective pool occupancy, published only after validation.
SYM_STEP: DB 0           ; Current context's descriptor width, 3 or 4 bytes.
.WORK_END:
