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

; Append zeroed four-byte slots and resolve generated addresses.
SCFIN:
        LD HL,(SCPC)              ; Generated code ends at the current cursor.
        PUSH HL                    ; Keep the code end while sizing slot data.
        LD HL,(SCGCOUNT)           ; Four bytes are needed for every global slot.
        ADD HL,HL
        ADD HL,HL
        LD A,(SCLOCMAX)            ; Add four bytes for every local high-water slot.
        PUSH HL                    ; Keep the global extent while scaling locals.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        EX DE,HL                   ; DE now contains four times the local count.
        POP HL                     ; Restore the four-times-global extent.
        ADD HL,DE
        PUSH HL                    ; Keep the combined user-slot extent.
        LD A,(SCQCNT)             ; Add one four-byte cache cell per quoted list.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        EX DE,HL                   ; DE now contains the cache-cell extent.
        POP HL                     ; Restore the global/local slot extent.
        ADD HL,DE
        PUSH HL                    ; Keep the slot extent while sizing descriptors.
        LD A,(SCPCOUNT)            ; Every procedure uses one fixed metadata record.
        LD L,A                     ; Widen the descriptor count to a word.
        LD H,0
        LD D,H                     ; Keep the original count for the final add.
        LD E,L
        ADD HL,HL                  ; Two times the descriptor count.
        ADD HL,HL                  ; Four times the descriptor count.
        PUSH HL                    ; Keep four times the count.
        ADD HL,HL                  ; Eight times the descriptor count.
        PUSH HL                    ; Keep eight times the count.
        ADD HL,HL                  ; Sixteen times the descriptor count.
        ADD HL,HL                  ; Thirty-two times the descriptor count.
        POP DE                     ; Recover eight times the count.
        ADD HL,DE                  ; Forty times the descriptor count.
        POP DE                     ; Recover four times the count.
        ADD HL,DE                  ; Complete forty-four bytes per descriptor.
        POP DE                     ; Recover the global and local slot extent.
        ADD HL,DE                  ; Add descriptor records to the final image.
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
        LD HL,(SCPC)               ; Restore the generated-code cursor for slot data.
        LD (SCGBASE),HL           ; Globals follow the generated instruction bytes.
        LD BC,(SCGCOUNT)          ; One four-byte record is reserved per global.
        XOR A                     ; Global slot zero is the first primitive mark.
        LD (SCGIDX),A
        JP SCGDATA                 ; Skip the helper body before entering the loop.

; Write one global value record, seeding predefined names with their procedure
; value while leaving ordinary names unbound until a definition stores them.
SCGINIT:
        LD A,(SCGIDX)             ; The compiler mark table is byte indexed.
        LD L,A
        LD H,0
        LD DE,SCGPRIM
        ADD HL,DE
        LD A,(HL)                 ; Zero denotes an ordinary uninitialized name.
        OR A
        JR Z,SCGZERO              ; Ordinary names receive four zero bytes.
        DEC A                     ; Convert kind one..four to payload low $20..$23.
        ADD A,20H
        CALL SINKBYTE              ; Primitive procedure payload low byte.
        RET C
        LD A,0FEH                 ; Primitive payloads use the reserved high byte.
        CALL SINKBYTE
        RET C
        XOR A                     ; Tag zero identifies a primitive procedure value.
        CALL SINKBYTE
        RET C
        LD A,1                     ; Predefined values are initialized at startup.
        JP SINKBYTE
SCGZERO:
        XOR A                     ; Ordinary names begin with no payload or tag.
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        CALL SINKBYTE
        RET C
        JP SINKBYTE                ; The zero flag makes an unresolved load fail.

SCGDATA:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all global slots are present.
        JR Z,SCLDATA               ; Continue with local storage after the globals.
        CALL SCGINIT               ; Materialize an ordinary or predefined value.
        LD A,(SCGIDX)              ; Advance the primitive-mark cursor.
        INC A
        LD (SCGIDX),A
        DEC BC                     ; Account for the slot just appended.
        JR SCGDATA                 ; Continue until the global count is exhausted.
SCLDATA:
        LD HL,(SCPC)
        LD (SCLBASE),HL            ; Locals follow the complete global area.
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
        CALL SCPDESC               ; Append absolute procedure descriptors.
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
