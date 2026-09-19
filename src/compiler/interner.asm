;=============================================================================
;  Permanent symbol and string interner
;=============================================================================

;  PURPOSE
;  -------
;  Store symbol and string bytes in caller-owned tables.
;  Return stable, zero-based IDs.
;
;  The reader checks identifier spelling. This module enforces storage limits.

;  PUBLIC INTERFACE
;  ----------------
;

;+---------------------------------------------------------------------------+
;|  IINIT - Validate the configuration and initialize an empty context.      |
;|                                                                           |
;|  CALL                                                                     |
;|    IX -> caller-owned 14-byte context.                                    |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    A = 0; carry clear; the empty context is ready.                        |
;|                                                                           |
;|  FAILURE                                                                  |
;|    A = 2; carry set; context and stored bytes are unchanged.              |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  INTERN - Reuse or append bytes and return their stable ID.               |
;|                                                                           |
;|  CALL                                                                     |
;|    IX -> ready context.                                                   |
;|    HL -> source bytes; BC = byte length.                                  |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    HL = stable zero-based ID; A = 0; carry clear.                         |
;|                                                                           |
;|  FAILURE                                                                  |
;|    A = 1 capacity; A = 2 bounds/data; A = 3 not ready; carry set.         |
;+---------------------------------------------------------------------------+

;  CONTEXT LAYOUT (IX)
;  ------------------
;
;  OFFSET  SIZE  MEANING
;  ------  ----  ----------------------------
;  +0      2     Descriptor-table base address.
;  +2      2     Entry capacity.
;  +4      2     Byte-pool base address.
;  +6      2     Byte-pool capacity.
;  +8      2     Current entry count.
;  +10     2     Used byte-pool length.
;  +12     1     Kind: 0 symbol, 1 string.
;  +13     1     Ready flag.
;
;  Configure before IINIT. Keep the configuration unchanged until reinit.

;  STORAGE LIMITS
;  --------------
;
;  ENTRIES    0..8192 per context.
;  BYTE POOL  0..65535 bytes.
;  SYMBOLS    Three-byte descriptor; 1..31 ASCII bytes.
;  STRINGS    Four-byte descriptor; 0..255 arbitrary bytes.

;  SHARED CALLING CONTRACT
;  -----------------------
;
;  PRESERVES  IX, IY.
;  CLOBBERS   AF, BC, DE, HL.
;  STACK      4 bytes below entry SP; 6 including caller return.
;  FAILURE    Context, descriptors and pool remain unchanged.
;  SCRATCH    Static; the module is non-reentrant.
;  MEMORY     Keep context, table, pool, source, code/workspace and stack
;             disjoint. Extents may end at 65536.
;  SOURCE     Must remain unchanged during INTERN.
;=============================================================================

IINIT:                  ; Validate configuration, then publish an empty ready context.
        CALL ICTXCHK       ; Check all 14 context bytes before indexed reads.
        RET C           ; Propagate the bounds error without touching persistent state.
        LD A,(IX+12)    ; Kind determines both length rules and descriptor stride.
        CP 2            ; Unsigned kinds zero and one are the only valid configurations.
        JP NC,IBOUNDER
        ADD A,3         ; Symbol stride 3; string stride 4.
        LD (IDESCWID),A
        LD L,(IX+2)     ; Entry capacity is limited by the 13-bit public identity.
        LD H,(IX+3)
        LD DE,2001H
        OR A
        SBC HL,DE       ; Borrow means capacity is strictly below 8193.
        JP NC,IBOUNDER    ; 8193 and above cannot produce valid identities.
        ADD HL,DE       ; Recover capacity after the comparison subtraction.
        LD D,H
        LD E,L          ; Keep one copy for the three-byte case.
        ADD HL,HL       ; Two bytes per descriptor so far.
        LD A,(IDESCWID)
        CP 3
        JR Z,ISTRIDE3
        ADD HL,HL       ; String descriptor capacity in bytes: four times count.
        JR IDSCSPAN
ISTRIDE3:                 ; HL holds twice the capacity; DE holds one capacity.
        ADD HL,DE       ; Symbol descriptor capacity in bytes: three times count.
IDSCSPAN:                 ; Both stride paths join with HL holding descriptor bytes.
        LD B,H
        LD C,L          ; BC now spans the complete descriptor capacity.
        LD L,(IX+0)
        LD H,(IX+1)     ; HL is its caller-supplied base address.
        CALL ISPANCHK
        RET C           ; Propagate the bounds error without touching persistent state.
        LD L,(IX+4)     ; Validate the complete pool capacity independently.
        LD H,(IX+5)
        LD C,(IX+6)
        LD B,(IX+7)
        CALL ISPANCHK
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

INTERN:                 ; Validate a borrowed byte sequence before searching or writing.
        LD (ISRCADDR),HL ; Preserve source registers across context validation.
        LD (ILENWORD),BC
        CALL ICTXCHK
        RET C           ; Propagate the bounds error without touching persistent state.
        LD A,(IX+13)
        CP 1            ; Ready must match the value published by IINIT.
        JP NZ,IUNREADY
        LD BC,(ILENWORD)
        LD A,B          ; Every supported literal length fits a byte.
        OR A
        JP NZ,IBOUNDER
        LD A,(IX+12)
        ADD A,3
        LD (IDESCWID),A  ; Recompute stride when switching between contexts.
        LD A,(IX+12)
        OR A
        JR NZ,ILENOKAY
        LD A,C          ; Symbols cannot be empty or exceed 31 bytes.
        OR A
        JP Z,IBOUNDER
        CP 32
        JP NC,IBOUNDER
ILENOKAY:                 ; Length fits the selected kind; source bounds remain unchecked.
        LD HL,(ISRCADDR)
        CALL ISPANCHK      ; Prove the entire source extent before reading bytes.
        RET C           ; Propagate the bounds error without touching persistent state.
        LD A,(IX+12)
        OR A
        JR NZ,IFINDTAB
        LD HL,(ISRCADDR)
        LD A,(ILENWORD)
        LD B,A          ; Symbol length is nonzero, so DJNZ cannot wrap from zero.
IASCLOOP:                 ; HL scans the symbol, B counts its remaining nonzero bytes.
        BIT 7,(HL)      ; Every identifier byte must be seven-bit ASCII.
        JP NZ,IBOUNDER
        INC HL
        DJNZ IASCLOOP
IFINDTAB:                ; All input validation is complete; search before checking space.
        LD HL,0
        LD (IINDEXID),HL  ; Search in insertion order for stable zero-based IDs.
        LD L,(IX+0)
        LD H,(IX+1)
        LD (ICURSADR),HL
INEXTDSC:                  ; IINDEXID/ICURSADR identify the next occupied descriptor to inspect.
        LD HL,(IINDEXID)
        LD E,(IX+8)
        LD D,(IX+9)
        OR A
        SBC HL,DE       ; Z means candidate ID reached the occupied-entry count.
        JR Z,IINSERT    ; All existing entries were compared before capacity checks.
        LD HL,(ICURSADR)
        LD E,(HL)       ; Descriptor offset points into the packed byte pool.
        INC HL
        LD D,(HL)
        INC HL
        LD A,(ILENWORD)
        CP (HL)         ; Compare byte values/lengths; NZ rejects this candidate.
        JR NZ,IADVANCE  ; Different lengths cannot denote identical byte strings.
        OR A
        JP Z,IFOUNDID     ; Two empty strings need no source or pool reads.
        LD B,A
        LD L,(IX+4)
        LD H,(IX+5)
        ADD HL,DE       ; HL now addresses the candidate's pool bytes.
        LD DE,(ISRCADDR)
ICOMPARE:               ; HL candidate, DE source, B remaining bytes of equal-length data.
        LD A,(DE)       ; Compare one source byte with the corresponding pool byte.
        CP (HL)         ; Compare byte values/lengths; NZ rejects this candidate.
        JR NZ,IADVANCE
        INC DE
        INC HL
        DJNZ ICOMPARE
        JP IFOUNDID
IADVANCE:               ; A mismatch discards byte cursors and advances the descriptor.
        LD HL,(ICURSADR)
        LD A,(IDESCWID)
        LD E,A
        LD D,0
        ADD HL,DE       ; Move by exactly one descriptor, never by its byte length.
        LD (ICURSADR),HL
        LD HL,(IINDEXID)
        INC HL
        LD (IINDEXID),HL
        JR INEXTDSC
IINSERT:                ; No equal entry exists; IINDEXID equals count and ICURSADR is free.
        LD L,(IX+8)
        LD H,(IX+9)
        LD E,(IX+2)
        LD D,(IX+3)
        OR A
        SBC HL,DE       ; No borrow means count is at or above descriptor capacity.
        JR NC,IFULLERR     ; A new identity requires an unused descriptor.
        LD L,(IX+10)
        LD H,(IX+11)
        LD BC,(ILENWORD)
        ADD HL,BC       ; Compute the prospective used-byte count before writing.
        JR C,IFULLERR
        LD (INEWUSED),HL
        LD E,(IX+6)
        LD D,(IX+7)
        OR A
        SBC HL,DE       ; Compare prospective occupancy with configured pool capacity.
        JR C,ICOMMIT    ; Borrow proves the insertion leaves unused pool bytes.
        JR NZ,IFULLERR     ; Equality is allowed: the insertion may fill the pool.
ICOMMIT:                ; Descriptor and pool checks passed; no error exit follows.
        LD HL,(ICURSADR)
        LD E,(IX+10)
        LD D,(IX+11)    ; Old used-byte count is the new descriptor's offset.
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(ILENWORD)
        LD (HL),A
        LD A,(IX+12)
        OR A
        JR Z,ICOPYBYT
        INC HL
        LD (HL),0       ; String lengths occupy a word; their high byte is zero.
ICOPYBYT:                  ; DE still holds the new entry offset from the descriptor stores.
        LD L,(IX+4)
        LD H,(IX+5)
        ADD HL,DE       ; Destination follows the last occupied pool byte.
        EX DE,HL
        LD HL,(ISRCADDR)
        LD BC,(ILENWORD)
        LD A,B
        OR C
        JR Z,IPUBLISH   ; LDIR with zero would copy 65536 bytes, not zero bytes.
        LDIR            ; Bounds and disjoint source/destination were established.
IPUBLISH:               ; Descriptor and byte copy are complete; make the entry visible.
        LD HL,(INEWUSED)
        LD (IX+10),L
        LD (IX+11),H
        LD HL,(IINDEXID)
        INC HL
        LD (IX+8),L
        LD (IX+9),H     ; Publish the new entry count after its descriptor and bytes.
IFOUNDID:                 ; Search hit and successful insertion share the same ID result.
        LD HL,(IINDEXID)  ; The caller receives identity, never a pool address.
        XOR A
        RET

; Context validation uses its final byte, allowing a context ending at 65536.
ICTXCHK:                   ; Only address arithmetic occurs before proving the context extent.
        PUSH IX
        POP HL
        LD DE,13
        ADD HL,DE
        JR C,IBOUNDER
        OR A
        RET
; HL base + BC extent may wrap only to zero, the exact 65536 endpoint.
ISPANCHK:                  ; C after ADD denotes crossing the 16-bit address boundary.
        ADD HL,BC       ; Compute the exclusive endpoint; carry alone is not an error.
        JR NC,ISPANOK   ; No carry means the endpoint remains below 65536.
        LD A,H          ; With carry set, only a zero wrapped result means exact fit.
        OR L            ; Test both endpoint bytes; this instruction clears carry.
        JR NZ,IBOUNDER    ; A nonzero wrapped endpoint exceeds the address space.
ISPANOK:                ; Accept no wrap or the exact endpoint, then normalize success flags.
        XOR A
        RET
IFULLERR:                  ; No caller-owned table bytes have changed on capacity failures.
        LD A,1          ; Descriptor or byte capacity has been exhausted.
        SCF
        RET
IBOUNDER:                 ; Bounds/type validation also precedes every persistent write.
        LD A,2          ; Input/configuration cannot fit the published representation.
        SCF
        RET
IUNREADY:                ; Only an initialized context provides meaningful table geometry.
        LD A,3          ; A valid context must be initialized before interning.
        SCF
        RET
IEND:
IWORK:
ISRCADDR: DW 0           ; Borrowed address of the incoming literal bytes.
ILENWORD: DW 0           ; Incoming byte count, validated to 0..255.
IINDEXID: DW 0            ; Identity of the current comparison/insertion candidate.
ICURSADR: DW 0           ; Address of that candidate's packed descriptor.
INEWUSED: DW 0          ; Prospective pool occupancy, published only after validation.
IDESCWID: DB 0           ; Current context's descriptor width, 3 or 4 bytes.
IWEND:
