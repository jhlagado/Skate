;=============================================================================
;  Bounded NOBJ 1.0 target proof
;=============================================================================
;
; PUBLIC ENTRY
;
; TGLINK
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

TGMAXO EQU 0200H
TGMAXB EQU 32
TGMAXI EQU 4
TGMAXS EQU 4
TGMAXR EQU 4
TGBASE EQU 4000H
TGCAP  EQU 0100H

ORG 0100H
TGCODE:
; Validate one bounded object, then publish the staged initialized section.
TGLINK:
        LD (TGIN),HL         ; Retain the object-spool start address.
        LD (TGLEFT),BC       ; Retain its exact byte length.
        XOR A                ; Start at BEGIN with empty declaration counts.
        LD (TGPHASE),A       ; Record order is tracked as one bounded state.
        LD (TGIMGC),A        ; No IMAGE payload has been staged yet.
        LD (TGSYMC),A        ; The local symbol table starts empty.
        LD (TGRELC),A        ; No relocation site has been claimed.
        LD (TGLAYM),A        ; Retain module mode for the COMMIT check.
        LD HL,0              ; Clear record and previous-record counters.
        LD (TGRECS),HL       ; COMMIT must repeat the final record count.
        LD (TGIMGE),HL       ; The first IMAGE may begin at offset zero.
        LD (TGSYMP),HL       ; Remember the last ID for ordered checks.
        LD HL,0FFFFH         ; CRC-16/CCITT-FALSE starts at FFFFH.
        LD (TGCRCW),HL       ; Include every byte through COMMIT's entry ID.
        LD HL,(TGLEFT)       ; Empty input cannot contain a complete BEGIN.
        LD A,H
        OR L
        JP Z,TGEIO
        LD DE,TGMAXO         ; Compare input length with the 512-byte limit.
        OR A
        SBC HL,DE
        JP C,TGSIZEOK        ; A shorter object fits the limit.
        JP Z,TGSIZEOK        ; Exactly 512 bytes also fits.
        JP TGECAP            ; Reject before reading or writing target memory.
; Reject a source extent that wraps around the 16-bit address space.
TGSIZEOK:
        LD HL,(TGIN)         ; Rebuild the half-open source end.
        LD DE,(TGLEFT)
        ADD HL,DE
        JP NC,TGLOOP         ; A nonwrapped endpoint is a valid memory extent.
        LD A,H               ; A wrapped zero is the permitted endpoint 65536.
        OR L
        JP NZ,TGEADDR        ; Other wrapped extents exceed target memory.

; Read the next record header and dispatch only the supported NOBJ1 subset.
TGLOOP:
        CALL TGRCRC          ; Record kind contributes to the CRC.
        JP C,TGEIO           ; A short spool cannot contain another record.
        LD (TGKIND),A        ; Retain kind across length decoding.
        CALL TGR16           ; Read the little-endian payload length.
        JP C,TGEIO
        LD (TGPLEN),HL       ; Hand the bounded payload size to its decoder.
        LD HL,(TGRECS)       ; Count this header, including COMMIT.
        INC HL
        LD (TGRECS),HL
        LD A,(TGKIND)
        CP 1
        JP Z,TGBEGIN         ; BEGIN must lead the stream.
        CP 3
        JP Z,TGREG           ; REGION selects the single fixed target view.
        CP 4
        JP Z,TGSECT          ; SECTION declares the staged output extent.
        CP 6
        JP Z,TGIMG           ; IMAGE bytes are copied into private staging.
        CP 8
        JP Z,TGSYM           ; Only local definitions fit this proof table.
        CP 9
        JP Z,TGREL           ; Resolve one supported ABS16_RUN site at a time.
        CP 11
        JP Z,TGLAY           ; LAYOUT names the local executable entry.
        CP 12
        JP Z,TGCOM           ; COMMIT checks count, layout, CRC and EOF.
        JP TGEFMT            ; Reject kinds outside this proof subset.

; BEGIN is the exact NOBJ 1.0 Z80-target marker, not a legacy NOBJ version.
TGBEGIN:
        LD A,(TGPHASE)
        OR A
        JP NZ,TGEFMT         ; A second or misplaced BEGIN is invalid.
        LD HL,(TGRECS)
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; BEGIN must be the first record.
        LD DE,9              ; NOBJ1 BEGIN has a nine-byte payload.
        CALL TGLEN
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 4EH               ; First magic byte is ASCII N.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 4FH               ; Second magic byte is ASCII O.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 42H               ; Third magic byte is ASCII B.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 4AH               ; Fourth magic byte is ASCII J.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 1                 ; Only major version 1 is supported.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; This proof implements minor version zero.
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; Target ID one names the 16-bit Z80.
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; Reserved BEGIN flags must be zero.
        LD A,1
        LD (TGPHASE),A       ; REGION is the only next declaration class.
        JP TGLOOP

; REGION must match the one physical view provided by this target profile.
TGREG:
        LD A,(TGPHASE)
        CP 1
        JP NZ,TGEFMT
        LD DE,27             ; Both canonical keys are seven ASCII bytes.
        CALL TGLEN
        JP NZ,TGEFMT
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; The single accepted region has object ID one.
        CALL TGRCRC
        JP C,TGEIO
        CP 7
        JP NZ,TGEFMT         ; Address-space key length is exactly seven.
        CALL TGRCRC
        JP C,TGEIO
        CP 7AH               ; Match z80.cpu byte by byte.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 38H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 30H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 2EH
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 63H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 70H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 75H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 7                 ; Storage-key length is also seven.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 63H               ; Match cpm.ram byte by byte.
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 70H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 6DH
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 2EH
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 72H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 61H
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        CP 6DH
        JP NZ,TGEFMT
        CALL TGR16
        JP C,TGEIO
        LD DE,TGBASE
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; The fixed memory window begins at 4000H.
        CALL TGR32            ; The capacity is a u32 in the wire format.
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGECAP         ; Profile capacity fits one word.
        LD HL,(TGVLO)
        LD DE,TGCAP
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; REGION must match profile capacity.
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; The selected image fill is zero.
        CALL TGRCRC
        JP C,TGEIO
        CP 7
        JP NZ,TGEFMT         ; This view permits read, write and execute.
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; This target profile is not banked.
        LD A,2
        LD (TGPHASE),A       ; SECTION declarations now follow REGION.
        JP TGLOOP

; SECTION selects one small initialized extent with identical LOAD and RUN.
TGSECT:
        LD A,(TGPHASE)
        CP 2
        JP NZ,TGEFMT
        LD DE,25             ; Initialized SECTION carries eight extra bytes.
        CALL TGLEN
        JP NZ,TGEFMT
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; The proof accepts one section with ID one.
        CALL TGRCRC
        JP C,TGEIO
        CP 1
        JP NZ,TGEFMT         ; Storage kind one means initialized bytes.
        CALL TGRCRC
        JP C,TGEIO
        CP 5
        JP NZ,TGEFMT         ; Require readable executable storage.
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; Alignment one needs no rounding.
        CALL TGR32            ; Decode the declared section length.
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGECAP         ; The proof's section length is at most 32 bytes.
        LD HL,(TGVLO)
        LD A,H
        OR A
        JP NZ,TGECAP
        LD A,L
        OR A
        JP Z,TGEFMT          ; NOBJ sections cannot be empty.
        CP TGMAXB+1
        JP NC,TGECAP         ; Refuse a section larger than the stage buffer.
        LD (TGSLEN),HL       ; Retain the proven nonzero section length.
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; RUN region one is the only supported region.
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; This proof requires a fixed RUN placement.
        CALL TGR32            ; Read fixed RUN offset from region base.
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGEADDR        ; Address offsets must fit a Z80 word.
        LD HL,(TGVLO)
        LD (TGSOFF),HL       ; Retain the offset for bounds and final address.
        LD DE,(TGSLEN)
        ADD HL,DE            ; Compute the section's exclusive region end.
        JP C,TGEADDR
        LD DE,TGCAP+1        ; End 256 is valid; end 257 is not.
        OR A
        SBC HL,DE
        JP NC,TGEADDR
        LD DE,(TGSOFF)       ; Recover the validated section-relative offset.
        LD HL,TGBASE         ; Translate the relative offset to RUN address.
        ADD HL,DE
        JP C,TGEADDR
        LD (TGRUN),HL        ; Retain the section's absolute RUN address.
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; LOAD placement zero means identical to RUN.
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; The same region supplies LOAD and RUN.
        CALL TGR32            ; Same placement requires a zero load offset.
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGEFMT
        LD HL,(TGVLO)
        LD A,H
        OR L
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        LD (TGFILL),A        ; SECTION fill seeds bytes not supplied by IMAGE.
        LD HL,TGSTAG
        LD BC,(TGSLEN)
        LD B,C               ; Section length is one byte and never zero here.
        LD A,(TGFILL)
TGSFILL:
        LD (HL),A            ; Initialize one private staged byte.
        INC HL
        DJNZ TGSFILL         ; Finish fill before applying any IMAGE record.
        LD A,3
        LD (TGPHASE),A       ; IMAGE, SYMBOL or later declarations may follow.
        JP TGLOOP

; IMAGE ranges are copied only into the bounded private staging area.
TGIMG:
        LD A,(TGPHASE)
        CP 3
        JP Z,TGIGPH          ; No IMAGE has been accepted since SECTION.
        CP 4
        JP NZ,TGEFMT         ; IMAGE records cannot follow SYMBOL or RELOC.
TGIGPH:
        LD A,(TGIMGC)
        CP TGMAXI
        JP NC,TGECAP         ; Retain at most four ordered IMAGE records.
        LD HL,(TGPLEN)
        LD DE,7
        OR A
        SBC HL,DE
        JP C,TGEFMT          ; The IMAGE payload needs an ID, offset and byte.
        LD HL,(TGPLEN)
        LD DE,39
        OR A
        SBC HL,DE
        JP NC,TGECAP         ; One IMAGE record carries at most 32 data bytes.
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; IMAGE belongs to section one.
        CALL TGR32
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGEADDR        ; The proof stage uses 16-bit section offsets.
        LD HL,(TGVLO)
        LD (TGIMGS),HL       ; Remember the first byte's section offset.
        LD DE,(TGIMGE)
        OR A
        SBC HL,DE
        JP C,TGEFMT          ; IMAGE ranges increase and cannot overlap.
        LD HL,(TGPLEN)
        LD DE,6
        OR A
        SBC HL,DE             ; Remove section ID and the four-byte offset.
        LD (TGDATA),HL       ; The remainder is the number of image bytes.
        LD HL,(TGIMGS)
        LD DE,(TGDATA)
        ADD HL,DE            ; Compute the IMAGE range's exclusive end.
        JP C,TGEADDR
        LD (TGIMGE),HL       ; Retain the end for the next ordered IMAGE.
        LD DE,(TGSLEN)
        OR A
        SBC HL,DE
        JP C,TGIGOK          ; An end below SECTION.length is valid.
        JP Z,TGIGOK          ; Exact equality is also a valid exclusive end.
        JP TGEADDR
TGIGOK:
        LD HL,TGSTAG
        LD DE,(TGIMGS)
        ADD HL,DE
        LD (TGDST),HL        ; Save the destination across CRC-byte reads.
TGIGCOPY:
        CALL TGRCRC
        JP C,TGEIO
        LD HL,(TGDST)
        LD (HL),A            ; Replace the staged fill with this IMAGE byte.
        INC HL
        LD (TGDST),HL
        LD HL,(TGDATA)
        DEC HL
        LD (TGDATA),HL
        LD A,H
        OR L
        JP NZ,TGIGCOPY       ; Copy exactly the record's declared data length.
        LD A,(TGIMGC)
        INC A
        LD (TGIMGC),A
        LD A,4
        LD (TGPHASE),A       ; More IMAGE records may follow before symbols.
        JP TGLOOP

; SYMBOL records add bounded local definitions to a compact five-byte table.
TGSYM:
        LD A,(TGPHASE)
        CP 3
        JP Z,TGSYMPH         ; A module may omit all IMAGE records.
        CP 4
        JP Z,TGSYMPH
        CP 5
        JP NZ,TGEFMT         ; Symbols follow all IMAGE bytes, before RELOC.
TGSYMPH:
        LD A,(TGSYMC)
        CP TGMAXS
        JP NC,TGECAP         ; Four entries bound the target lookup table.
        LD DE,10
        CALL TGLEN
        JP NZ,TGEFMT         ; Local definitions have a ten-byte payload.
        CALL TGR16
        JP C,TGEIO
        LD (TGNEWID),HL      ; IDs are local to this one bounded object.
        LD A,H
        OR L
        JP Z,TGEFMT          ; Symbol ID zero is reserved.
        LD DE,(TGSYMP)
        OR A
        SBC HL,DE             ; IDs must be strictly increasing and unique.
        JP C,TGEFMT
        JP Z,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; Binding zero is a local definition.
        CALL TGRCRC
        JP C,TGEIO
        CP 1
        JP C,TGEFMT
        CP 4
        JP NC,TGEFMT         ; Value kind is CODE, ADDRESS or BOUNDARY.
        LD (TGKNEW),A        ; Retain kind while the offset is decoded.
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; This proof has one initialized section.
        CALL TGR32
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGEADDR        ; Definition offsets fit the bounded section.
        LD HL,(TGVLO)
        LD (TGSVAL),HL       ; Retain the section-relative value.
        LD DE,(TGSLEN)
        OR A
        SBC HL,DE
        JP C,TGSVOK          ; Every value below the end is in-section.
        JP NZ,TGEADDR        ; A greater value is never a valid definition.
        LD A,(TGKNEW)
        CP 3
        JP NZ,TGEADDR        ; Only BOUNDARY may name the exclusive end.
TGSVOK:
        LD A,(TGSYMC)        ; Convert the symbol index to a five-byte offset.
        LD L,A
        LD H,0
        LD D,H
        LD E,L               ; Keep one copy while HL is multiplied by five.
        ADD HL,HL            ; Two bytes per symbol index.
        ADD HL,HL            ; Four bytes per symbol index.
        ADD HL,DE            ; Five bytes per symbol index.
        LD DE,TGSTAB
        ADD HL,DE
        LD (TGDST),HL        ; Save this entry's table address.
        LD HL,(TGDST)
        LD DE,(TGNEWID)
        LD (HL),E            ; Store the local ID, low byte first.
        INC HL
        LD (HL),D
        INC HL
        LD DE,(TGSVAL)
        LD (HL),E            ; Store the section-relative offset.
        INC HL
        LD (HL),D
        INC HL
        LD A,(TGKNEW)
        LD (HL),A            ; Store CODE, ADDRESS or BOUNDARY kind.
        LD HL,(TGNEWID)
        LD (TGSYMP),HL       ; Retain the last ID for the next ordering check.
        LD A,(TGSYMC)
        INC A
        LD (TGSYMC),A
        LD A,5
        LD (TGPHASE),A       ; Symbols, relocations or layout may follow.
        JP TGLOOP

; RELOC resolves one local ABS16_RUN reference into staged bytes.
TGREL:
        LD A,(TGPHASE)
        CP 5
        JP Z,TGRELPH         ; At least one definition must precede RELOC.
        CP 6
        JP NZ,TGEFMT         ; RELOC records follow all symbols.
TGRELPH:
        LD A,(TGSYMC)
        OR A
        JP Z,TGEFMT
        LD A,(TGRELC)
        CP TGMAXR
        JP NC,TGECAP         ; Four entries bound the overlap-check table.
        LD DE,14
        CALL TGLEN
        JP NZ,TGEFMT         ; RELOC payload length is fourteen bytes.
        CALL TGR16
        JP C,TGEIO
        LD DE,1
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; This proof has one relocation source section.
        CALL TGR32
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGEADDR        ; Site offsets fit the 32-byte staging buffer.
        LD HL,(TGVLO)
        LD (TGSITE),HL       ; Retain the operand's first byte.
        INC HL
        INC HL
        JP C,TGEADDR
        LD DE,(TGSLEN)
        OR A
        SBC HL,DE
        JP C,TGRSOK          ; The complete word site is within the section.
        JP Z,TGRSOK
        JP TGEADDR
TGRSOK:
        CALL TGRCRC
        JP C,TGEIO
        CP 1
        JP NZ,TGEFMT         ; Relocation kind one is ABS16_RUN.
        CALL TGRCRC
        JP C,TGEIO
        CP 1
        JP Z,TGUSEOK         ; Control transfer requires a CODE target.
        CP 2
        JP NZ,TGEFMT         ; Use two is an ordinary data pointer.
TGUSEOK:
        LD (TGUSE),A
        CALL TGR16
        JP C,TGEIO
        LD (TGTID),HL        ; Resolve only against this object's local table.
        LD A,H
        OR L
        JP Z,TGEFMT
        CALL TGR32            ; Read the signed i32 byte addend.
        JP C,TGEIO
        LD HL,(TGVLO)
        LD (TGADLO),HL
        LD HL,(TGVHI)
        LD (TGADHI),HL
        CALL TGFIND
        JP C,TGEFMT          ; Imports and undefined IDs are unsupported.
        LD A,(TGUSE)
        CP 1
        JP NZ,TGRDATA
        LD A,(TGFKND)
        CP 1
        JP NZ,TGEFMT         ; Direct control transfers require CODE.
        JP TGRADD
TGRDATA:
        LD A,(TGFKND)
        CP 2
        JP Z,TGRADD          ; ADDRESS symbols are valid data pointers.
        CP 3
        JP NZ,TGEFMT         ; BOUNDARY is the other valid pointer kind.
TGRADD:
        LD HL,(TGADHI)
        LD DE,0
        OR A
        SBC HL,DE
        JP Z,TGRPOS          ; Positive i32 addends have a zero high word.
        LD HL,(TGADHI)
        LD DE,0FFFFH
        OR A
        SBC HL,DE
        JP Z,TGRNEG          ; Negative i32 addends have an FFFFH high word.
        JP TGEADDR            ; Larger addends cannot fit this section.
TGRPOS:
        LD HL,(TGFOFF)
        LD DE,(TGADLO)
        ADD HL,DE
        JP C,TGEADDR         ; Reject arithmetic wrap before checking the end.
        JP TGRADJ
TGRNEG:
        LD HL,(TGADLO)
        LD A,H
        OR L
        JP Z,TGEADDR         ; FFFF:0000 is -65536, outside this section.
        LD HL,0
        LD DE,(TGADLO)
        OR A
        SBC HL,DE            ; Negate the low word to obtain the magnitude.
        LD DE,(TGFOFF)
        EX DE,HL             ; HL=offset; DE=negative magnitude.
        OR A
        SBC HL,DE
        JP C,TGEADDR         ; The adjusted offset cannot be negative.
TGRADJ:
        LD (TGADJ),HL        ; Retain symbol offset plus the signed addend.
        LD DE,(TGSLEN)
        OR A
        SBC HL,DE
        JP C,TGRADOK         ; Any value below the end names a section byte.
        JP Z,TGRADEND        ; Equality is allowed only for BOUNDARY symbols.
        JP TGEADDR
TGRADEND:
        LD A,(TGFKND)
        CP 3
        JP NZ,TGEADDR
TGRADOK:
        LD HL,(TGRUN)        ; Add the checked offset to the RUN base.
        LD DE,(TGADJ)
        ADD HL,DE
        JP C,TGEADDR         ; Address 65536 cannot be encoded in ABS16.
        LD (TGABS),HL        ; Retain the final little-endian operand.
        CALL TGOVLAP         ; Two-byte sites must not overlap one another.
        JP C,TGEADDR
        LD HL,TGSTAG         ; Apply the operand to the private image.
        LD DE,(TGSITE)
        ADD HL,DE
        LD DE,(TGABS)
        LD (HL),E
        INC HL
        LD (HL),D
        CALL TGRSAVE         ; Remember this site for later overlap checks.
        LD A,(TGRELC)
        INC A
        LD (TGRELC),A
        LD A,6
        LD (TGPHASE),A
        JP TGLOOP

; Find the local definition named by TGTID; return its kind and offset.
TGFIND:
        LD A,(TGSYMC)
        OR A
        JP Z,TGFNMISS        ; An empty table cannot resolve an ID.
        LD B,A               ; Bound the linear search to four entries.
        LD HL,TGSTAB
        LD (TGSCAN),HL       ; Begin with symbol ID one in the packed table.
TGFLOOP:
        LD HL,(TGSCAN)
        LD A,(TGTID)
        CP (HL)
        JP NZ,TGFNEXT
        INC HL
        LD A,(TGTID+1)
        CP (HL)
        JP NZ,TGFNEXT
        INC HL
        LD A,(HL)
        LD (TGFOFF),A
        INC HL
        LD A,(HL)
        LD (TGFOFF+1),A
        INC HL
        LD A,(HL)
        LD (TGFKND),A
        OR A
        RET                  ; Return the definition with carry clear.
TGFNEXT:
        LD HL,(TGSCAN)
        LD DE,5
        ADD HL,DE            ; Each compact table entry occupies five bytes.
        LD (TGSCAN),HL
        DJNZ TGFLOOP         ; Inspect no more than the declared symbol count.
TGFNMISS:
        SCF
        RET                  ; Carry reports an undefined or unsupported ID.

; Compare a record's declared payload length with DE.
TGLEN:
        LD HL,(TGPLEN)
        OR A
        SBC HL,DE
        RET

; Decode one little-endian u16 through the CRC-accounted byte reader.
TGR16:
        CALL TGRCRC
        RET C
        LD E,A               ; Save the byte across CRC shifts.
        CALL TGRCRC
        RET C
        LD H,A               ; Assemble high then low into the returned word.
        LD L,E
        RET

; Decode two little-endian u16 values into TGVLO and TGVHI.
TGR32:
        CALL TGR16
        RET C
        LD (TGVLO),HL
        CALL TGR16
        RET C
        LD (TGVHI),HL
        RET

; Read one byte and update CRC-16/CCITT-FALSE with polynomial 1021H.
TGRCRC:
        CALL TGGET
        RET C
        LD C,A               ; Preserve the byte during CRC shifts.
        LD HL,(TGCRCW)
        XOR H
        LD H,A
        LD B,8               ; Shift input bits, most significant first.
TGCRCLP:
        ADD HL,HL
        JR NC,TGCRCNX        ; A shifted-out one selects the polynomial XOR.
        LD A,H
        XOR 10H
        LD H,A
        LD A,L
        XOR 21H
        LD L,A
TGCRCNX:
        DJNZ TGCRCLP
        LD (TGCRCW),HL
        LD A,C
        OR A                 ; Return the byte while clearing carry.
        RET

; Read one byte from the bounded in-memory object spool.
TGGET:
        LD HL,(TGLEFT)
        LD A,H
        OR L
        JP Z,TGGEOF          ; No read may pass the caller's exact extent.
        DEC HL
        LD (TGLEFT),HL
        LD HL,(TGIN)
        LD A,(HL)
        INC HL
        LD (TGIN),HL
        OR A                 ; Zero is valid; carry still indicates success.
        RET
TGGEOF:
        LD A,1
        SCF
        RET                  ; Carry identifies a truncated record or stream.

; Reject any previously claimed two-byte site that intersects this site.
TGOVLAP:
        LD A,(TGRELC)
        OR A
        JR Z,TGOVOK          ; The first relocation has nothing to compare.
        LD B,A
        LD HL,TGRTAB
TGOVLP:
        LD A,(TGSITE)
        CP (HL)
        JR Z,TGOVBAD         ; Identical starts always overlap.
        JR C,TGOVLO          ; Reverse subtraction for a positive distance.
        SUB (HL)
        CP 2
        JR C,TGOVBAD         ; Starts one byte apart share an operand byte.
        JR TGOVNX
TGOVLO:
        LD A,(TGSITE)
        LD C,A
        LD A,(HL)
        SUB C
        CP 2
        JR C,TGOVBAD
TGOVNX:
        INC HL
        INC HL               ; Advance past this two-byte site.
        DJNZ TGOVLP
TGOVOK:
        OR A
        RET                  ; Clear carry after every site is disjoint.
TGOVBAD:
        SCF
        RET

; Append the current site to the four-entry overlap table.
TGRSAVE:
        LD A,(TGRELC)
        LD L,A
        LD H,0
        ADD HL,HL            ; Each retained site is two bytes.
        LD DE,TGRTAB
        ADD HL,DE
        LD A,(TGSITE)
        LD (HL),A
        INC HL
        LD A,(TGSITE+1)
        LD (HL),A
        RET

; LAYOUT must name a local CODE definition and agree with COMMIT.
TGLAY:
        LD A,(TGPHASE)
        CP 5
        JP Z,TGLYPH          ; LAYOUT follows definitions and optional relocs.
        CP 6
        JP NZ,TGEFMT
TGLYPH:
        LD A,(TGSYMC)
        OR A
        JP Z,TGEFMT
        LD DE,4
        CALL TGLEN
        JP NZ,TGEFMT
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; Layout mode zero means an unlinked module.
        LD (TGLAYM),A
        CALL TGRCRC
        JP C,TGEIO
        OR A
        JP NZ,TGEFMT         ; LAYOUT flags are reserved and must be zero.
        CALL TGR16
        JP C,TGEIO
        LD (TGENTR),HL       ; Save the entry for COMMIT's repeated fields.
        LD A,H
        OR L
        JP Z,TGEFMT          ; A runnable proof object needs a nonzero entry.
        LD (TGTID),HL
        CALL TGFIND
        JP C,TGEFMT
        LD A,(TGFKND)
        CP 1
        JP NZ,TGEFMT         ; The module entry must be CODE.
        LD A,7
        LD (TGPHASE),A       ; Only the terminal COMMIT may follow LAYOUT.
        JP TGLOOP

; COMMIT closes the object; publish only after count, CRC and EOF checks pass.
TGCOM:
        LD A,(TGPHASE)
        CP 7
        JP NZ,TGEFMT
        LD DE,9
        CALL TGLEN
        JP NZ,TGEFMT
        CALL TGR32            ; COMMIT record count is a u32.
        JP C,TGEIO
        LD HL,(TGVHI)
        LD A,H
        OR L
        JP NZ,TGEFMT         ; This bounded stream count fits one word.
        LD HL,(TGVLO)
        LD DE,(TGRECS)
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; Count includes the terminal COMMIT record.
        CALL TGRCRC
        JP C,TGEIO
        LD B,A
        LD A,(TGLAYM)
        CP B
        JP NZ,TGEFMT         ; COMMIT repeats LAYOUT mode exactly.
        CALL TGR16
        JP C,TGEIO
        LD DE,(TGENTR)
        OR A
        SBC HL,DE
        JP NZ,TGEFMT         ; COMMIT repeats the selected entry ID.
        CALL TGGET
        JP C,TGEIO
        LD E,A               ; Read the stored CRC without folding it again.
        CALL TGGET
        JP C,TGEIO
        LD D,A
        LD HL,(TGCRCW)
        OR A
        SBC HL,DE
        JP NZ,TGECRC         ; CRC covers BEGIN through COMMIT entrySymbolId.
        LD HL,(TGLEFT)
        LD A,H
        OR L
        JP NZ,TGEFMT         ; COMMIT must be the final record and end at EOF.
        JP TGPUBL

; Copy the verified and relocated section into its requested target address.
TGPUBL:
        LD HL,TGSTAG
        LD DE,(TGRUN)
        LD BC,(TGSLEN)
        LDIR                 ; Publish only after complete validation.
        XOR A
        RET                  ; Success is A=0 with carry clear.

; Failure codes are stable; staged output is not published.
TGEIO:
        LD A,1               ; Input ended before its declared record bytes.
        SCF
        RET
TGEFMT:
        LD A,2               ; The record is malformed or outside the subset.
        SCF
        RET
TGECAP:
        LD A,3               ; Object, section or table exceeds its budget.
        SCF
        RET
TGECRC:
        LD A,4               ; Terminal checksum does not match the stream.
        SCF
        RET
TGEADDR:
        LD A,5               ; Invalid extent, overlap or final address.
        SCF
        RET
TGCEND:

; Fixed-size workspace: four five-byte symbols and four two-byte sites.
TGWORK:
TGIN:    DW 0                 ; Next input byte in the caller-owned spool.
TGLEFT:  DW 0                 ; Input bytes not yet consumed.
TGPLEN:  DW 0                 ; Declared payload byte count for this record.
TGRECS:  DW 0                 ; Record count, including the current header.
TGCRCW:  DW 0                 ; Running CRC-16/CCITT-FALSE.
TGVLO:   DW 0                 ; Low word of the most recently decoded u32.
TGVHI:   DW 0                 ; High word of the most recently decoded u32.
TGSOFF:  DW 0                 ; Fixed section offset from REGION base.
TGSLEN:  DW 0                 ; Initialized section length, at most 32 bytes.
TGRUN:   DW 0                 ; Absolute RUN and LOAD start of the section.
TGIMGE:  DW 0                 ; End of the previous IMAGE range.
TGIMGS:  DW 0                 ; Start offset of the current IMAGE range.
TGDATA:  DW 0                 ; IMAGE payload bytes not yet copied.
TGDST:   DW 0                 ; Current staging or table destination.
TGSYMP:  DW 0                 ; Previous SYMBOL ID for ordered uniqueness.
TGNEWID: DW 0                 ; SYMBOL ID currently being validated.
TGSVAL:  DW 0                 ; Current SYMBOL section-relative offset.
TGTID:   DW 0                 ; Symbol ID requested by entry or relocation.
TGFOFF:  DW 0                 ; Resolved local symbol section-relative offset.
TGADLO:  DW 0                 ; Low word of the signed relocation addend.
TGADHI:  DW 0                 ; High word of the signed relocation addend.
TGADJ:   DW 0                 ; Checked symbol offset plus addend.
TGSITE:  DW 0                 ; First byte of the current relocation operand.
TGABS:   DW 0                 ; Final 16-bit RUN address written at the site.
TGSCAN:  DW 0                 ; Current symbol-table entry during lookup.
TGKIND:  DB 0                 ; Current record kind.
TGPHASE: DB 0                 ; Highest record phase accepted so far.
TGIMGC:  DB 0                 ; Number of ordered IMAGE records, at most four.
TGSYMC:  DB 0                 ; Number of local symbols, at most four.
TGRELC:  DB 0                 ; Number of relocation sites, at most four.
TGLAYM:  DB 0                 ; LAYOUT mode repeated by COMMIT.
TGENTR:  DW 0                 ; LAYOUT entry SYMBOL ID repeated by COMMIT.
TGFILL:  DB 0                 ; SECTION fill for bytes missing from IMAGE.
TGUSE:   DB 0                 ; Relocation use: control or data pointer.
TGFKND:  DB 0                 ; Resolved kind: CODE, ADDRESS or BOUNDARY.
TGKNEW:  DB 0                 ; Kind of the SYMBOL currently being decoded.
TGSTAB:  DS 20                ; Four entries: ID, offset and value kind.
TGRTAB:  DS 8                 ; Four two-byte relocation-site offsets.
TGWEND:
TGSTAG:  DS 32                ; Private image, committed after validation.
TGSEND:
TGEND:
