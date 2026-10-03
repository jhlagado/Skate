; Scope publication layout and static data emission.
; Entry points: SCFIN, SCGINIT, SCGDATA, SCPENTRY and SCPROOTS.
;=============================================================================
;  Scope compiler final layout and CP/M publication
;=============================================================================
;
;  SCFIN closes the staged image and fixes every slot address.  SCOUT publishes
;  the matching ASO and COM images to temporary CP/M files before installing
;  their final names.
;=============================================================================

; Seed the fixed global area, append zeroed static slots and resolve generated
; addresses.  Globals were reserved after the runtime before any code.
SCFIN:
        LD HL,(SCPC)              ; Generated code ends at the current cursor.
        PUSH HL                    ; Keep the code end while sizing slot data.
        LD A,(SCLOCMAX)            ; Four bytes for every local high-water slot.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        PUSH HL                    ; Keep the static-slot extent.
        LD A,(SCQCNT)             ; Add one four-byte cache cell per quoted list.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        EX DE,HL                   ; DE now contains the cache-cell extent.
        POP HL                     ; Restore the global/local slot extent.
        ADD HL,DE
        POP DE                     ; DE is the generated-code end address.
        ADD HL,DE                  ; HL is the complete staged-image end estimate.
        JR NC,SCFENDNC             ; A nonwrapped endpoint is below $10000.
        LD A,H
        OR L
        JP NZ,SCCAP                ; A wrapped nonzero endpoint exceeds $10000.
        LD A,(SCPCET)
        OR A
        JP NZ,SCCAP                ; A second wrap exceeds the address space.
        JR SCFENDOK
SCFENDNC:
        LD A,(SCPCET)
        OR A
        JR Z,SCFENDOK              ; The current cursor was below $10000.
        LD A,H
        OR L
        JP NZ,SCCAP                ; A nonempty extent follows the endpoint.
SCFENDOK:
        LD HL,(SCGRBASE)           ; Globals occupy the area after the runtime.
        LD (SCGBASE),HL
        LD BC,(SCGCOUNT)          ; One four-byte record is reserved per global.
        XOR A                     ; Global slot zero is the first primitive mark.
        LD (SCGIDX),A
        JP SCGDATA                 ; Skip the helper body before entering the loop.

; Seed one predefined global with its primitive procedure value.  The area
; was emitted as zeroes, which leave ordinary names unbound, so only
; predefined names need the two PATCH words.
SCGINIT:
        LD A,(SCGIDX)             ; The compiler mark table is byte indexed.
        LD L,A
        LD H,0
        LD DE,SCGPRIM
        ADD HL,DE
        LD A,(HL)                 ; Zero denotes an ordinary uninitialized name.
        OR A
        RET Z                     ; Carry is clear for an ordinary name.
        DEC A                     ; Convert kind one..four to payload low $20..$23.
        ADD A,20H
        LD E,A
        LD D,0FEH                 ; Primitive payloads use the reserved high byte.
        LD A,(SCGIDX)             ; Address the global's four-byte record.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        PUSH DE
        LD DE,(SCGRBASE)
        ADD HL,DE
        POP DE
        PUSH HL
        CALL SINKPTCH              ; Payload word; SINKPTCH preserves BC.
        POP HL
        RET C
        INC HL
        INC HL
        LD DE,0100H               ; Tag zero, and the value is initialized.
        JP SINKPTCH

SCGDATA:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all global slots are present.
        JR Z,SCLDATA               ; Continue with local storage after the globals.
        CALL SCGINIT               ; Seed a predefined value.
        RET C
        LD A,(SCGIDX)              ; Advance the primitive-mark cursor.
        INC A
        LD (SCGIDX),A
        DEC BC                     ; Account for the slot just seeded.
        JR SCGDATA                 ; Continue until the global count is exhausted.
SCLDATA:
        LD HL,(SCPC)
        LD (SCLBASE),HL            ; Static locals follow the generated code.
        LD A,(SCLOCMAX)            ; The local high-water mark sets its extent.
        LD C,A                     ; Widen the byte count to a normal word.
        LD B,0                     ; Local slots also occupy four bytes each.
SCLOOP:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all local slots are present.
        JR Z,SCDATAOK              ; Continue with address fixups.
        XOR A                      ; Local slots start with zero payload and flag.
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        DEC BC                     ; Account for the slot just appended.
        JR SCLOOP                  ; Continue until the local extent is filled.
SCDATAOK:
        LD HL,(SCPC)
        LD (SCQBASE),HL            ; Quoted-list cache cells follow local storage.
        LD A,(SCQCNT)
        LD C,A
        LD B,0
SCQCLOOP:
        LD A,B
        OR C
        JR Z,SCQCDONE
        XOR A
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        DEC BC
        JR SCQCLOOP
SCQCDONE:
        LD HL,(SCPC)               ; The sink owns the logical output cursor.
        CALL SCPDESC               ; Patch the slot extent into every descriptor.
        RET C                      ; Preserve the staged-image capacity guard.
        CALL SCLITDAT             ; Append copied symbol and string literals.
        RET C                      ; Preserve the staged-image capacity guard.
        LD HL,(SCPC)               ; Literal data advances the final image cursor.
        LD A,(SCPCET)
        LD (SCAETOP),A             ; Publish the 17-bit ASO endpoint marker.
        LD DE,0100H                ; Convert the logical endpoint to a length.
        OR A                       ; Clear carry before measuring the image.
        SBC HL,DE                  ; HL becomes runtime plus code plus slot data.
        LD (SCIMGL),HL             ; SCOUT streams this exact payload length.
        CALL SCPENTRY              ; Point the runtime image at the generated program.
        CALL SCPSLOTS              ; Replace every slot placeholder with an address.
        RET                        ; Carry reports any capacity or layout failure.
