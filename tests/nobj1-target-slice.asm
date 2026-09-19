;=============================================================================
;  Bounded NOBJ 1.0 target proof slice
;=============================================================================
;
; PUBLIC ENTRY
;
; N1LINK
;   HL points to one serialized object; BC gives its byte length (1..512).
;   Success validates the stream and publishes one linked section.
;
; SUPPORTED SUBSET
;
;   One fixed REGION: z80.cpu / cpm.ram at 4000H, capacity 256 bytes.
;   One initialized, fixed SECTION of at most 32 bytes.
;   At most four IMAGE records, four local symbols and four relocations.
;   Relocations are ABS16_RUN control transfers or data pointers.
;   Imports, contracts, ranges, patches, metadata, banks and allocation fail.
;
; RESULTS AND OWNERSHIP
;
;   Success: A = 0; carry clear. Failure: carry set; A identifies the error.
;     1  truncated input
;     2  malformed or unsupported record
;     3  object or table capacity
;     4  CRC mismatch
;     5  extent, overlapping site or relocation address error
;   The output section is staged; target memory is unchanged on failure.
;   IX/IY are preserved; AF/BC/DE/HL are clobbered; SP is balanced.
;   Static scratch makes this proof module non-reentrant. NOALLOC.
;   Keep input, code/workspace, staging, target and stack disjoint.
;
; This is a measured feasibility prototype, not a production NOBJ linker.
;=============================================================================

N1MAXO EQU 0200H
N1MAXB EQU 32
N1MAXI EQU 4
N1MAXS EQU 4
N1MAXR EQU 4
N1BASE EQU 4000H
N1CAP  EQU 0100H

ORG 0100H
N1CODE:
; Validate one bounded object, then publish the staged initialized section.
N1LINK:
        LD (N1IN),HL         ; Retain the object-spool start address.
        LD (N1LEFT),BC       ; Retain its exact byte length.
        XOR A                ; Start at BEGIN with empty declaration counts.
        LD (N1PHASE),A       ; Record order is tracked as one bounded state.
        LD (N1IMGC),A        ; No IMAGE payload has been staged yet.
        LD (N1SYMC),A        ; The local symbol table starts empty.
        LD (N1RELC),A        ; No relocation site has been claimed.
        LD (N1LAYM),A        ; Retain module mode for the COMMIT check.
        LD HL,0              ; Clear record and previous-record counters.
        LD (N1RECS),HL       ; COMMIT must repeat the final record count.
        LD (N1IMGE),HL       ; The first IMAGE may begin at offset zero.
        LD (N1SYMP),HL       ; Remember the last ID for ordered checks.
        LD HL,0FFFFH         ; CRC-16/CCITT-FALSE starts at FFFFH.
        LD (N1CRCW),HL       ; Include every byte through COMMIT's entry ID.
        LD HL,(N1LEFT)       ; Empty input cannot contain a complete BEGIN.
        LD A,H
        OR L
        JP Z,N1EIO
        LD DE,N1MAXO         ; Compare input length with the 512-byte limit.
        OR A
        SBC HL,DE
        JP C,N1SIZEOK        ; A shorter object fits the limit.
        JP Z,N1SIZEOK        ; Exactly 512 bytes also fits.
        JP N1ECAP            ; Reject before reading or writing target memory.
; Reject a source extent that wraps around the 16-bit address space.
N1SIZEOK:
        LD HL,(N1IN)         ; Rebuild the half-open source end.
        LD DE,(N1LEFT)
        ADD HL,DE
        JP NC,N1LOOP         ; A nonwrapped endpoint is a valid memory extent.
        LD A,H               ; A wrapped zero is the permitted endpoint 65536.
        OR L
        JP NZ,N1EADDR        ; Other wrapped extents exceed target memory.

; Read the next record header and dispatch only the supported NOBJ1 subset.
N1LOOP:
        CALL N1RCRC          ; Record kind contributes to the CRC.
        JP C,N1EIO           ; A short spool cannot contain another record.
        LD (N1KIND),A        ; Retain kind across length decoding.
        CALL N1R16           ; Read the little-endian payload length.
        JP C,N1EIO
        LD (N1PLEN),HL       ; Hand the bounded payload size to its decoder.
        LD HL,(N1RECS)       ; Count this header, including COMMIT.
        INC HL
        LD (N1RECS),HL
        LD A,(N1KIND)
        CP 1
        JP Z,N1BEGIN         ; BEGIN must lead the stream.
        CP 3
        JP Z,N1REG           ; REGION selects the single fixed target view.
        CP 4
        JP Z,N1SECT          ; SECTION declares the staged output extent.
        CP 6
        JP Z,N1IMG           ; IMAGE bytes are copied into private staging.
        CP 8
        JP Z,N1SYM           ; Only local definitions fit this proof table.
        CP 9
        JP Z,N1REL           ; Resolve one supported ABS16_RUN site at a time.
        CP 11
        JP Z,N1LAY           ; LAYOUT names the local executable entry.
        CP 12
        JP Z,N1COM           ; COMMIT checks count, layout, CRC and EOF.
        JP N1EFMT            ; Reject kinds outside this proof subset.

; BEGIN is the exact NOBJ 1.0 Z80-target marker, not a legacy NOBJ version.
N1BEGIN:
        LD A,(N1PHASE)
        OR A
        JP NZ,N1EFMT         ; A second or misplaced BEGIN is invalid.
        LD HL,(N1RECS)
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; BEGIN must be the first record.
        LD DE,9              ; NOBJ1 BEGIN has a nine-byte payload.
        CALL N1LEN
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 4EH               ; First magic byte is ASCII N.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 4FH               ; Second magic byte is ASCII O.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 42H               ; Third magic byte is ASCII B.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 4AH               ; Fourth magic byte is ASCII J.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 1                 ; Only major version 1 is supported.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; This proof implements minor version zero.
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; Target ID one names the 16-bit Z80.
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; Reserved BEGIN flags must be zero.
        LD A,1
        LD (N1PHASE),A       ; REGION is the only next declaration class.
        JP N1LOOP

; REGION must match the one physical view provided by this target profile.
N1REG:
        LD A,(N1PHASE)
        CP 1
        JP NZ,N1EFMT
        LD DE,27             ; Both canonical keys are seven ASCII bytes.
        CALL N1LEN
        JP NZ,N1EFMT
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; The single accepted region has object ID one.
        CALL N1RCRC
        JP C,N1EIO
        CP 7
        JP NZ,N1EFMT         ; Address-space key length is exactly seven.
        CALL N1RCRC
        JP C,N1EIO
        CP 7AH               ; Match z80.cpu byte by byte.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 38H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 30H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 2EH
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 63H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 70H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 75H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 7                 ; Storage-key length is also seven.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 63H               ; Match cpm.ram byte by byte.
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 70H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 6DH
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 2EH
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 72H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 61H
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        CP 6DH
        JP NZ,N1EFMT
        CALL N1R16
        JP C,N1EIO
        LD DE,N1BASE
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; The fixed memory window begins at 4000H.
        CALL N1R32            ; The capacity is a u32 in the wire format.
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1ECAP         ; Profile capacity fits one word.
        LD HL,(N1VLO)
        LD DE,N1CAP
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; REGION must match profile capacity.
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; The selected image fill is zero.
        CALL N1RCRC
        JP C,N1EIO
        CP 7
        JP NZ,N1EFMT         ; This view permits read, write and execute.
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; This target profile is not banked.
        LD A,2
        LD (N1PHASE),A       ; SECTION declarations now follow REGION.
        JP N1LOOP

; SECTION selects one small initialized extent with identical LOAD and RUN.
N1SECT:
        LD A,(N1PHASE)
        CP 2
        JP NZ,N1EFMT
        LD DE,25             ; Initialized SECTION carries eight extra bytes.
        CALL N1LEN
        JP NZ,N1EFMT
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; The proof accepts one section with ID one.
        CALL N1RCRC
        JP C,N1EIO
        CP 1
        JP NZ,N1EFMT         ; Storage kind one means initialized bytes.
        CALL N1RCRC
        JP C,N1EIO
        CP 5
        JP NZ,N1EFMT         ; Require readable executable storage.
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; Alignment one needs no rounding.
        CALL N1R32            ; Decode the declared section length.
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1ECAP         ; The proof's section length is at most 32 bytes.
        LD HL,(N1VLO)
        LD A,H
        OR A
        JP NZ,N1ECAP
        LD A,L
        OR A
        JP Z,N1EFMT          ; NOBJ sections cannot be empty.
        CP N1MAXB+1
        JP NC,N1ECAP         ; Refuse a section larger than the stage buffer.
        LD (N1SLEN),HL       ; Retain the proven nonzero section length.
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; RUN region one is the only supported region.
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; This proof requires a fixed RUN placement.
        CALL N1R32            ; Read fixed RUN offset from region base.
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1EADDR        ; Address offsets must fit a Z80 word.
        LD HL,(N1VLO)
        LD (N1SOFF),HL       ; Retain the offset for bounds and final address.
        LD DE,(N1SLEN)
        ADD HL,DE            ; Compute the section's exclusive region end.
        JP C,N1EADDR
        LD DE,N1CAP+1        ; End 256 is valid; end 257 is not.
        OR A
        SBC HL,DE
        JP NC,N1EADDR
        LD DE,(N1SOFF)       ; Recover the validated section-relative offset.
        LD HL,N1BASE         ; Translate the relative offset to RUN address.
        ADD HL,DE
        JP C,N1EADDR
        LD (N1RUN),HL        ; Retain the section's absolute RUN address.
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; LOAD placement zero means identical to RUN.
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; The same region supplies LOAD and RUN.
        CALL N1R32            ; Same placement requires a zero load offset.
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1EFMT
        LD HL,(N1VLO)
        LD A,H
        OR L
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        LD (N1FILL),A        ; SECTION fill seeds bytes not supplied by IMAGE.
        LD HL,N1STAG
        LD BC,(N1SLEN)
        LD B,C               ; Section length is one byte and never zero here.
        LD A,(N1FILL)
N1SFILL:
        LD (HL),A            ; Initialize one private staged byte.
        INC HL
        DJNZ N1SFILL         ; Finish fill before applying any IMAGE record.
        LD A,3
        LD (N1PHASE),A       ; IMAGE, SYMBOL or later declarations may follow.
        JP N1LOOP

; IMAGE ranges are copied only into the bounded private staging area.
N1IMG:
        LD A,(N1PHASE)
        CP 3
        JP Z,N1IGPH          ; No IMAGE has been accepted since SECTION.
        CP 4
        JP NZ,N1EFMT         ; IMAGE records cannot follow SYMBOL or RELOC.
N1IGPH:
        LD A,(N1IMGC)
        CP N1MAXI
        JP NC,N1ECAP         ; Retain at most four ordered IMAGE records.
        LD HL,(N1PLEN)
        LD DE,7
        OR A
        SBC HL,DE
        JP C,N1EFMT          ; The IMAGE payload needs an ID, offset and byte.
        LD HL,(N1PLEN)
        LD DE,39
        OR A
        SBC HL,DE
        JP NC,N1ECAP         ; One IMAGE record carries at most 32 data bytes.
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; IMAGE belongs to section one.
        CALL N1R32
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1EADDR        ; The proof stage uses 16-bit section offsets.
        LD HL,(N1VLO)
        LD (N1IMGS),HL       ; Remember the first byte's section offset.
        LD DE,(N1IMGE)
        OR A
        SBC HL,DE
        JP C,N1EFMT          ; IMAGE ranges increase and cannot overlap.
        LD HL,(N1PLEN)
        LD DE,6
        OR A
        SBC HL,DE             ; Remove section ID and the four-byte offset.
        LD (N1DATA),HL       ; The remainder is the number of image bytes.
        LD HL,(N1IMGS)
        LD DE,(N1DATA)
        ADD HL,DE            ; Compute the IMAGE range's exclusive end.
        JP C,N1EADDR
        LD (N1IMGE),HL       ; Retain the end for the next ordered IMAGE.
        LD DE,(N1SLEN)
        OR A
        SBC HL,DE
        JP C,N1IGOK          ; An end below SECTION.length is valid.
        JP Z,N1IGOK          ; Exact equality is also a valid exclusive end.
        JP N1EADDR
N1IGOK:
        LD HL,N1STAG
        LD DE,(N1IMGS)
        ADD HL,DE
        LD (N1DST),HL        ; Save the destination across CRC-byte reads.
N1IGCOPY:
        CALL N1RCRC
        JP C,N1EIO
        LD HL,(N1DST)
        LD (HL),A            ; Replace the staged fill with this IMAGE byte.
        INC HL
        LD (N1DST),HL
        LD HL,(N1DATA)
        DEC HL
        LD (N1DATA),HL
        LD A,H
        OR L
        JP NZ,N1IGCOPY       ; Copy exactly the record's declared data length.
        LD A,(N1IMGC)
        INC A
        LD (N1IMGC),A
        LD A,4
        LD (N1PHASE),A       ; More IMAGE records may follow before symbols.
        JP N1LOOP

; SYMBOL records add bounded local definitions to a compact five-byte table.
N1SYM:
        LD A,(N1PHASE)
        CP 3
        JP Z,N1SYMPH         ; A module may omit all IMAGE records.
        CP 4
        JP Z,N1SYMPH
        CP 5
        JP NZ,N1EFMT         ; Symbols follow all IMAGE bytes, before RELOC.
N1SYMPH:
        LD A,(N1SYMC)
        CP N1MAXS
        JP NC,N1ECAP         ; Four entries bound the target lookup table.
        LD DE,10
        CALL N1LEN
        JP NZ,N1EFMT         ; Local definitions have a ten-byte payload.
        CALL N1R16
        JP C,N1EIO
        LD (N1NEWID),HL      ; IDs are local to this one bounded object.
        LD A,H
        OR L
        JP Z,N1EFMT          ; Symbol ID zero is reserved.
        LD DE,(N1SYMP)
        OR A
        SBC HL,DE             ; IDs must be strictly increasing and unique.
        JP C,N1EFMT
        JP Z,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; Binding zero is a local definition.
        CALL N1RCRC
        JP C,N1EIO
        CP 1
        JP C,N1EFMT
        CP 4
        JP NC,N1EFMT         ; Value kind is CODE, ADDRESS or BOUNDARY.
        LD (N1KNEW),A        ; Retain kind while the offset is decoded.
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; This slice has one initialized section.
        CALL N1R32
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1EADDR        ; Definition offsets fit the bounded section.
        LD HL,(N1VLO)
        LD (N1SVAL),HL       ; Retain the section-relative value.
        LD DE,(N1SLEN)
        OR A
        SBC HL,DE
        JP C,N1SVOK          ; Every value below the end is in-section.
        JP NZ,N1EADDR        ; A greater value is never a valid definition.
        LD A,(N1KNEW)
        CP 3
        JP NZ,N1EADDR        ; Only BOUNDARY may name the exclusive end.
N1SVOK:
        LD A,(N1SYMC)        ; Convert the symbol index to a five-byte offset.
        LD L,A
        LD H,0
        LD D,H
        LD E,L               ; Keep one copy while HL is multiplied by five.
        ADD HL,HL            ; Two bytes per symbol index.
        ADD HL,HL            ; Four bytes per symbol index.
        ADD HL,DE            ; Five bytes per symbol index.
        LD DE,N1STAB
        ADD HL,DE
        LD (N1DST),HL        ; Save this entry's table address.
        LD HL,(N1DST)
        LD DE,(N1NEWID)
        LD (HL),E            ; Store the local ID, low byte first.
        INC HL
        LD (HL),D
        INC HL
        LD DE,(N1SVAL)
        LD (HL),E            ; Store the section-relative offset.
        INC HL
        LD (HL),D
        INC HL
        LD A,(N1KNEW)
        LD (HL),A            ; Store CODE, ADDRESS or BOUNDARY kind.
        LD HL,(N1NEWID)
        LD (N1SYMP),HL       ; Retain the last ID for the next ordering check.
        LD A,(N1SYMC)
        INC A
        LD (N1SYMC),A
        LD A,5
        LD (N1PHASE),A       ; Symbols, relocations or layout may follow.
        JP N1LOOP

; RELOC resolves one local ABS16_RUN reference into staged bytes.
N1REL:
        LD A,(N1PHASE)
        CP 5
        JP Z,N1RELPH         ; At least one definition must precede RELOC.
        CP 6
        JP NZ,N1EFMT         ; RELOC records follow all symbols.
N1RELPH:
        LD A,(N1SYMC)
        OR A
        JP Z,N1EFMT
        LD A,(N1RELC)
        CP N1MAXR
        JP NC,N1ECAP         ; Four entries bound the overlap-check table.
        LD DE,14
        CALL N1LEN
        JP NZ,N1EFMT         ; RELOC payload length is fourteen bytes.
        CALL N1R16
        JP C,N1EIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; This proof has one relocation source section.
        CALL N1R32
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1EADDR        ; Site offsets fit the 32-byte staging buffer.
        LD HL,(N1VLO)
        LD (N1SITE),HL       ; Retain the operand's first byte.
        INC HL
        INC HL
        JP C,N1EADDR
        LD DE,(N1SLEN)
        OR A
        SBC HL,DE
        JP C,N1RSOK          ; The complete word site is within the section.
        JP Z,N1RSOK
        JP N1EADDR
N1RSOK:
        CALL N1RCRC
        JP C,N1EIO
        CP 1
        JP NZ,N1EFMT         ; Relocation kind one is ABS16_RUN.
        CALL N1RCRC
        JP C,N1EIO
        CP 1
        JP Z,N1USEOK         ; Control transfer requires a CODE target.
        CP 2
        JP NZ,N1EFMT         ; Use two is an ordinary data pointer.
N1USEOK:
        LD (N1USE),A
        CALL N1R16
        JP C,N1EIO
        LD (N1TID),HL        ; Resolve only against this object's local table.
        LD A,H
        OR L
        JP Z,N1EFMT
        CALL N1R32            ; Read the signed i32 byte addend.
        JP C,N1EIO
        LD HL,(N1VLO)
        LD (N1ADLO),HL
        LD HL,(N1VHI)
        LD (N1ADHI),HL
        CALL N1FIND
        JP C,N1EFMT          ; Imports and undefined IDs are unsupported.
        LD A,(N1USE)
        CP 1
        JP NZ,N1RDATA
        LD A,(N1FKND)
        CP 1
        JP NZ,N1EFMT         ; Direct control transfers require CODE.
        JP N1RADD
N1RDATA:
        LD A,(N1FKND)
        CP 2
        JP Z,N1RADD          ; ADDRESS symbols are valid data pointers.
        CP 3
        JP NZ,N1EFMT         ; BOUNDARY is the other valid pointer kind.
N1RADD:
        LD HL,(N1ADHI)
        LD DE,0
        OR A
        SBC HL,DE
        JP Z,N1RPOS          ; Positive i32 addends have a zero high word.
        LD HL,(N1ADHI)
        LD DE,0FFFFH
        OR A
        SBC HL,DE
        JP Z,N1RNEG          ; Negative i32 addends have an FFFFH high word.
        JP N1EADDR            ; Larger addends cannot fit this section.
N1RPOS:
        LD HL,(N1FOFF)
        LD DE,(N1ADLO)
        ADD HL,DE
        JP C,N1EADDR         ; Reject arithmetic wrap before checking the end.
        JP N1RADJ
N1RNEG:
        LD HL,(N1ADLO)
        LD A,H
        OR L
        JP Z,N1EADDR         ; FFFF:0000 is -65536, outside this section.
        LD HL,0
        LD DE,(N1ADLO)
        OR A
        SBC HL,DE            ; Negate the low word to obtain the magnitude.
        LD DE,(N1FOFF)
        EX DE,HL             ; HL=offset; DE=negative magnitude.
        OR A
        SBC HL,DE
        JP C,N1EADDR         ; The adjusted offset cannot be negative.
N1RADJ:
        LD (N1ADJ),HL        ; Retain symbol offset plus the signed addend.
        LD DE,(N1SLEN)
        OR A
        SBC HL,DE
        JP C,N1RADOK         ; Any value below the end names a section byte.
        JP Z,N1RADEND        ; Equality is allowed only for BOUNDARY symbols.
        JP N1EADDR
N1RADEND:
        LD A,(N1FKND)
        CP 3
        JP NZ,N1EADDR
N1RADOK:
        LD HL,(N1RUN)        ; Add the checked offset to the RUN base.
        LD DE,(N1ADJ)
        ADD HL,DE
        JP C,N1EADDR         ; Address 65536 cannot be encoded in ABS16.
        LD (N1ABS),HL        ; Retain the final little-endian operand.
        CALL N1OVLAP         ; Two-byte sites must not overlap one another.
        JP C,N1EADDR
        LD HL,N1STAG         ; Apply the operand to the private image.
        LD DE,(N1SITE)
        ADD HL,DE
        LD DE,(N1ABS)
        LD (HL),E
        INC HL
        LD (HL),D
        CALL N1RSAVE         ; Remember this site for later overlap checks.
        LD A,(N1RELC)
        INC A
        LD (N1RELC),A
        LD A,6
        LD (N1PHASE),A
        JP N1LOOP

; Find the local definition named by N1TID; return its kind and offset.
N1FIND:
        LD A,(N1SYMC)
        OR A
        JP Z,N1FNMISS        ; An empty table cannot resolve an ID.
        LD B,A               ; Bound the linear search to four entries.
        LD HL,N1STAB
        LD (N1SCAN),HL       ; Begin with symbol ID one in the packed table.
N1FLOOP:
        LD HL,(N1SCAN)
        LD A,(N1TID)
        CP (HL)
        JP NZ,N1FNEXT
        INC HL
        LD A,(N1TID+1)
        CP (HL)
        JP NZ,N1FNEXT
        INC HL
        LD A,(HL)
        LD (N1FOFF),A
        INC HL
        LD A,(HL)
        LD (N1FOFF+1),A
        INC HL
        LD A,(HL)
        LD (N1FKND),A
        OR A
        RET                  ; Return the definition with carry clear.
N1FNEXT:
        LD HL,(N1SCAN)
        LD DE,5
        ADD HL,DE            ; Each compact table entry occupies five bytes.
        LD (N1SCAN),HL
        DJNZ N1FLOOP         ; Inspect no more than the declared symbol count.
N1FNMISS:
        SCF
        RET                  ; Carry reports an undefined or unsupported ID.

; Compare a record's declared payload length with DE.
N1LEN:
        LD HL,(N1PLEN)
        OR A
        SBC HL,DE
        RET

; Decode one little-endian u16 through the CRC-accounted byte reader.
N1R16:
        CALL N1RCRC
        RET C
        LD E,A               ; Save the byte across CRC shifts.
        CALL N1RCRC
        RET C
        LD H,A               ; Assemble high then low into the returned word.
        LD L,E
        RET

; Decode two little-endian u16 values into N1VLO and N1VHI.
N1R32:
        CALL N1R16
        RET C
        LD (N1VLO),HL
        CALL N1R16
        RET C
        LD (N1VHI),HL
        RET

; Read one byte and update CRC-16/CCITT-FALSE with polynomial 1021H.
N1RCRC:
        CALL N1GET
        RET C
        LD C,A               ; Preserve the byte during CRC shifts.
        LD HL,(N1CRCW)
        XOR H
        LD H,A
        LD B,8               ; Shift input bits, most significant first.
N1CRCLP:
        ADD HL,HL
        JR NC,N1CRCNX        ; A shifted-out one selects the polynomial XOR.
        LD A,H
        XOR 10H
        LD H,A
        LD A,L
        XOR 21H
        LD L,A
N1CRCNX:
        DJNZ N1CRCLP
        LD (N1CRCW),HL
        LD A,C
        OR A                 ; Return the byte while clearing carry.
        RET

; Read one byte from the bounded in-memory object spool.
N1GET:
        LD HL,(N1LEFT)
        LD A,H
        OR L
        JP Z,N1GEOF          ; No read may pass the caller's exact extent.
        DEC HL
        LD (N1LEFT),HL
        LD HL,(N1IN)
        LD A,(HL)
        INC HL
        LD (N1IN),HL
        OR A                 ; Zero is valid; carry still indicates success.
        RET
N1GEOF:
        LD A,1
        SCF
        RET                  ; Carry identifies a truncated record or stream.

; Reject any previously claimed two-byte site that intersects this site.
N1OVLAP:
        LD A,(N1RELC)
        OR A
        JR Z,N1OVOK          ; The first relocation has nothing to compare.
        LD B,A
        LD HL,N1RTAB
N1OVLP:
        LD A,(N1SITE)
        CP (HL)
        JR Z,N1OVBAD         ; Identical starts always overlap.
        JR C,N1OVLO          ; Reverse subtraction for a positive distance.
        SUB (HL)
        CP 2
        JR C,N1OVBAD         ; Starts one byte apart share an operand byte.
        JR N1OVNX
N1OVLO:
        LD A,(N1SITE)
        LD C,A
        LD A,(HL)
        SUB C
        CP 2
        JR C,N1OVBAD
N1OVNX:
        INC HL
        INC HL               ; Advance past this two-byte site.
        DJNZ N1OVLP
N1OVOK:
        OR A
        RET                  ; Clear carry after every site is disjoint.
N1OVBAD:
        SCF
        RET

; Append the current site to the four-entry overlap table.
N1RSAVE:
        LD A,(N1RELC)
        LD L,A
        LD H,0
        ADD HL,HL            ; Each retained site is two bytes.
        LD DE,N1RTAB
        ADD HL,DE
        LD A,(N1SITE)
        LD (HL),A
        INC HL
        LD A,(N1SITE+1)
        LD (HL),A
        RET

; LAYOUT must name a local CODE definition and agree with COMMIT.
N1LAY:
        LD A,(N1PHASE)
        CP 5
        JP Z,N1LYPH          ; LAYOUT follows definitions and optional relocs.
        CP 6
        JP NZ,N1EFMT
N1LYPH:
        LD A,(N1SYMC)
        OR A
        JP Z,N1EFMT
        LD DE,4
        CALL N1LEN
        JP NZ,N1EFMT
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; Layout mode zero means an unlinked module.
        LD (N1LAYM),A
        CALL N1RCRC
        JP C,N1EIO
        OR A
        JP NZ,N1EFMT         ; LAYOUT flags are reserved and must be zero.
        CALL N1R16
        JP C,N1EIO
        LD (N1ENTR),HL       ; Save the entry for COMMIT's repeated fields.
        LD A,H
        OR L
        JP Z,N1EFMT          ; A runnable proof object needs a nonzero entry.
        LD (N1TID),HL
        CALL N1FIND
        JP C,N1EFMT
        LD A,(N1FKND)
        CP 1
        JP NZ,N1EFMT         ; The module entry must be CODE.
        LD A,7
        LD (N1PHASE),A       ; Only the terminal COMMIT may follow LAYOUT.
        JP N1LOOP

; COMMIT closes the object; publish only after count, CRC and EOF checks pass.
N1COM:
        LD A,(N1PHASE)
        CP 7
        JP NZ,N1EFMT
        LD DE,9
        CALL N1LEN
        JP NZ,N1EFMT
        CALL N1R32            ; COMMIT record count is a u32.
        JP C,N1EIO
        LD HL,(N1VHI)
        LD A,H
        OR L
        JP NZ,N1EFMT         ; This bounded stream count fits one word.
        LD HL,(N1VLO)
        LD DE,(N1RECS)
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; Count includes the terminal COMMIT record.
        CALL N1RCRC
        JP C,N1EIO
        LD B,A
        LD A,(N1LAYM)
        CP B
        JP NZ,N1EFMT         ; COMMIT repeats LAYOUT mode exactly.
        CALL N1R16
        JP C,N1EIO
        LD DE,(N1ENTR)
        OR A
        SBC HL,DE
        JP NZ,N1EFMT         ; COMMIT repeats the selected entry ID.
        CALL N1GET
        JP C,N1EIO
        LD E,A               ; Read the stored CRC without folding it again.
        CALL N1GET
        JP C,N1EIO
        LD D,A
        LD HL,(N1CRCW)
        OR A
        SBC HL,DE
        JP NZ,N1ECRC         ; CRC covers BEGIN through COMMIT entrySymbolId.
        LD HL,(N1LEFT)
        LD A,H
        OR L
        JP NZ,N1EFMT         ; COMMIT must be the final record and end at EOF.
        JP N1PUBL

; Copy the verified and relocated section into its requested target address.
N1PUBL:
        LD HL,N1STAG
        LD DE,(N1RUN)
        LD BC,(N1SLEN)
        LDIR                 ; Publish only after complete validation.
        XOR A
        RET                  ; Success is A=0 with carry clear.

; Failure codes are stable; staged output is not published.
N1EIO:
        LD A,1               ; Input ended before its declared record bytes.
        SCF
        RET
N1EFMT:
        LD A,2               ; The record is malformed or outside the subset.
        SCF
        RET
N1ECAP:
        LD A,3               ; Object, section or table exceeds its budget.
        SCF
        RET
N1ECRC:
        LD A,4               ; Terminal checksum does not match the stream.
        SCF
        RET
N1EADDR:
        LD A,5               ; Invalid extent, overlap or final address.
        SCF
        RET
N1CEND:

; Fixed-size workspace: four five-byte symbols and four two-byte sites.
N1WORK:
N1IN:    DW 0                 ; Next input byte in the caller-owned spool.
N1LEFT:  DW 0                 ; Input bytes not yet consumed.
N1PLEN:  DW 0                 ; Declared payload byte count for this record.
N1RECS:  DW 0                 ; Record count, including the current header.
N1CRCW:  DW 0                 ; Running CRC-16/CCITT-FALSE.
N1VLO:   DW 0                 ; Low word of the most recently decoded u32.
N1VHI:   DW 0                 ; High word of the most recently decoded u32.
N1SOFF:  DW 0                 ; Fixed section offset from REGION base.
N1SLEN:  DW 0                 ; Initialized section length, at most 32 bytes.
N1RUN:   DW 0                 ; Absolute RUN and LOAD start of the section.
N1IMGE:  DW 0                 ; End of the previous IMAGE range.
N1IMGS:  DW 0                 ; Start offset of the current IMAGE range.
N1DATA:  DW 0                 ; IMAGE payload bytes not yet copied.
N1DST:   DW 0                 ; Current staging or table destination.
N1SYMP:  DW 0                 ; Previous SYMBOL ID for ordered uniqueness.
N1NEWID: DW 0                 ; SYMBOL ID currently being validated.
N1SVAL:  DW 0                 ; Current SYMBOL section-relative offset.
N1TID:   DW 0                 ; Symbol ID requested by entry or relocation.
N1FOFF:  DW 0                 ; Resolved local symbol section-relative offset.
N1ADLO:  DW 0                 ; Low word of the signed relocation addend.
N1ADHI:  DW 0                 ; High word of the signed relocation addend.
N1ADJ:   DW 0                 ; Checked symbol offset plus addend.
N1SITE:  DW 0                 ; First byte of the current relocation operand.
N1ABS:   DW 0                 ; Final 16-bit RUN address written at the site.
N1SCAN:  DW 0                 ; Current symbol-table entry during lookup.
N1KIND:  DB 0                 ; Current record kind.
N1PHASE: DB 0                 ; Highest record phase accepted so far.
N1IMGC:  DB 0                 ; Number of ordered IMAGE records, at most four.
N1SYMC:  DB 0                 ; Number of local symbols, at most four.
N1RELC:  DB 0                 ; Number of relocation sites, at most four.
N1LAYM:  DB 0                 ; LAYOUT mode repeated by COMMIT.
N1ENTR:  DW 0                 ; LAYOUT entry SYMBOL ID repeated by COMMIT.
N1FILL:  DB 0                 ; SECTION fill for bytes missing from IMAGE.
N1USE:   DB 0                 ; Relocation use: control or data pointer.
N1FKND:  DB 0                 ; Resolved kind: CODE, ADDRESS or BOUNDARY.
N1KNEW:  DB 0                 ; Kind of the SYMBOL currently being decoded.
N1STAB:  DS 20                ; Four entries: ID, offset and value kind.
N1RTAB:  DS 8                 ; Four two-byte relocation-site offsets.
N1WEND:
N1STAG:  DS 32                ; Private image, committed after validation.
N1SEND:
N1END:
