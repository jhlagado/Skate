; Scope publication layout and static data emission.
; Entry points: PUB_END, .SEED, .GLOBALS, PUB_LINK and .ROOTS.
;=============================================================================
;  Scope compiler final layout and CP/M publication
;=============================================================================
;
;  PUB_END closes the staged image and fixes every slot address.  PUB_MAIN publishes
;  the matching ASO and COM images to temporary CP/M files before installing
;  their final names.
;=============================================================================

; Seed the fixed global area, append zeroed static slots and resolve generated
; addresses.  Globals were reserved after the runtime before any code.
PUB_END:
        LD HL,(ST_PC)             ; Generated code ends at the current cursor.
        PUSH HL                    ; Keep the code end while sizing slot data.
        LD A,(ST_LMAX)             ; Four bytes for every local high-water slot.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        PUSH HL                    ; Keep the static-slot extent.
        LD A,(QUO_CNT)            ; Add one four-byte cache cell per quoted list.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        EX DE,HL                   ; DE now contains the cache-cell extent.
        POP HL                     ; Restore the global/local slot extent.
        ADD HL,DE
        POP DE                     ; DE is the generated-code end address.
        ADD HL,DE                  ; HL is the complete staged-image end estimate.
        JR NC,.NO_WRAP             ; A nonwrapped endpoint is below $10000.
        LD A,H
        OR L
        JP NZ,ERR_CAP              ; A wrapped nonzero endpoint exceeds $10000.
        LD A,(ST_PCHI)
        OR A
        JP NZ,ERR_CAP              ; A second wrap exceeds the address space.
        JR .FITS
.NO_WRAP:
        LD A,(ST_PCHI)
        OR A
        JR Z,.FITS                 ; The current cursor was below $10000.
        LD A,H
        OR L
        JP NZ,ERR_CAP              ; A nonempty extent follows the endpoint.
.FITS:
        LD HL,(ST_GBASE)           ; Globals occupy the area after the runtime.
        LD (PUB_GLB),HL
        LD BC,(ST_GLOBS)          ; One four-byte record is reserved per global.
        XOR A                     ; Global slot zero is the first primitive mark.
        LD (ST_GIDX),A
        JP .GLOBALS                ; Skip the helper body before entering the loop.

; Seed one predefined global with its primitive procedure value.  The area
; was emitted as zeroes, which leave ordinary names unbound, so only
; predefined names need the two PATCH words.
.SEED:
        LD A,(ST_GIDX)            ; The compiler mark table is byte indexed.
        LD L,A
        LD H,0
        LD DE,W_GPRIM
        ADD HL,DE
        LD A,(HL)                 ; Zero denotes an ordinary uninitialized name.
        OR A
        RET Z                     ; Carry is clear for an ordinary name.
        DEC A                     ; Convert kind one..four to payload low $20..$23.
        ADD A,20H
        LD E,A
        LD D,0FEH                 ; Primitive payloads use the reserved high byte.
        LD A,(ST_GIDX)            ; Address the global's four-byte record.
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        PUSH DE
        LD DE,(ST_GBASE)
        ADD HL,DE
        POP DE
        PUSH HL
        CALL SINK_FIX              ; Payload word; SINK_FIX preserves BC.
        POP HL
        RET C
        INC HL
        INC HL
        LD DE,1000H               ; Clear extension; initialized, tag zero.
        JP SINK_FIX

.GLOBALS:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all global slots are present.
        JR Z,.LOCALS               ; Continue with local storage after the globals.
        CALL .SEED                 ; Seed a predefined value.
        RET C
        LD A,(ST_GIDX)             ; Advance the primitive-mark cursor.
        INC A
        LD (ST_GIDX),A
        DEC BC                     ; Account for the slot just seeded.
        JR .GLOBALS                ; Continue until the global count is exhausted.
.LOCALS:
        LD HL,(ST_PC)
        LD (PUB_LOC),HL            ; Static locals follow the generated code.
        LD A,(ST_LMAX)             ; The local high-water mark sets its extent.
        LD C,A                     ; Widen the byte count to a normal word.
        LD B,0                     ; Local slots also occupy four bytes each.
.LOCAL:
        LD A,B                     ; Test the high count byte first.
        OR C                       ; A zero pair means all local slots are present.
        JR Z,.CACHE                ; Continue with address fixups.
        XOR A                      ; Local slots start with zero payload and flag.
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        DEC BC                     ; Account for the slot just appended.
        JR .LOCAL                  ; Continue until the local extent is filled.
.CACHE:
        LD HL,(ST_PC)
        LD (QUO_BASE),HL           ; Quoted-list cache cells follow local storage.
        LD A,(QUO_CNT)
        LD C,A
        LD B,0
.CELL:
        LD A,B
        OR C
        JR Z,.FINISH
        XOR A
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        CALL SINK_PUT
        RET C
        DEC BC
        JR .CELL
.FINISH:
        LD HL,(ST_PC)              ; The sink owns the logical output cursor.
        CALL PUB_DESC              ; Patch the slot extent into every descriptor.
        RET C                      ; Preserve the staged-image capacity guard.
        CALL LIT_EMIT             ; Append copied symbol and string literals.
        RET C                      ; Preserve the staged-image capacity guard.
        LD HL,(ST_PC)              ; Literal data advances the final image cursor.
        LD A,(ST_PCHI)
        LD (ASO_TOP),A             ; Publish the 17-bit ASO endpoint marker.
        LD DE,0100H                ; Convert the logical endpoint to a length.
        OR A                       ; Clear carry before measuring the image.
        SBC HL,DE                  ; HL becomes runtime plus code plus slot data.
        LD (PUB_SIZE),HL           ; PUB_MAIN streams this exact payload length.
        CALL PUB_LINK              ; Point the runtime image at the generated program.
        CALL PUB_FIX               ; Replace every slot placeholder with an address.
        RET                        ; Carry reports any capacity or layout failure.
