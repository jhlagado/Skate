; Scope-control runtime output and scalar predicates
;
; The compiler and runtime share the value printer below.  Integer conversion
; remains separate from pair and literal output so each path has one clear
; responsibility and the main runtime module stays within the source limit.

; Return #t for zero and #f for every other exact integer.
SRTZERO:
        CP 3                     ; The predicate is defined only for exact integers.
        JP NZ,SRTERROR            ; Preserve the runtime type contract.
        LD A,H                   ; Combine the two payload bytes for the zero test.
        OR L                     ; Z means the exact integer is zero.
        JR Z,SRTZTRUE             ; Return canonical true for zero.
        LD A,0                   ; Tag zero identifies a boolean value.
        LD HL,0FE00H             ; #f has the reserved false payload.
        RET                      ; Return the false predicate result.
SRTZTRUE:
        LD A,0                   ; Tag zero identifies a boolean value.
        LD HL,0FE01H             ; #t has the reserved true payload.
        RET                      ; Return the true predicate result.

; Dispatch the final value printer.  Pair and literal values use the compact
; writer; the established decimal path remains for exact integers.
SRTPRINT:
        CP 3
        JP Z,SRTNUMPR
        JP SRTWRVAL

; Format an exact integer and print it through CP/M function 9.
SRTNUMPR:
        LD (SRTRES),HL         ; Retain the result during decimal conversion.
        LD DE,SRTBUF          ; Start writing at the message buffer.
        BIT 7,H                   ; A negative value needs a leading minus sign.
        JR Z,SRTIPOS              ; Positive values go directly to place handling.
        LD A,'-'                  ; Store the sign before taking the magnitude.
        LD (DE),A                 ; Write the sign byte.
        INC DE                    ; Advance to the first digit.
        XOR A                     ; Clear A before the low-byte negation.
        SUB L                     ; Negate the low payload byte.
        LD L,A                    ; Retain the low magnitude byte.
        LD A,0                    ; Preserve the low-byte borrow for negating H.
        SBC A,H                    ; Negate the high payload byte with borrow.
        LD H,A                    ; Retain the complete magnitude.
SRTIPOS:
        LD (SRTPTR),DE             ; Give the place routine its output cursor.
        XOR A                     ; No significant digit has been emitted yet.
        LD (SRTBEG),A         ; Suppress leading zeroes until needed.
        LD DE,10000                ; Select the ten-thousands place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,1000                 ; Select the thousands place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,100                  ; Select the hundreds place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD DE,10                   ; Select the tens place.
        CALL SRTPLACE              ; Append a digit when this place is used.
        LD A,1                     ; Units must always be emitted.
        LD (SRTBEG),A          ; Permit a zero units digit after a prefix.
        LD DE,1                    ; Select the units place.
        CALL SRTPLACE              ; Append the final digit.
        LD HL,(SRTPTR)             ; Locate the first unused message position.
        LD (HL),13                 ; CP/M text output uses carriage return first.
        INC HL                     ; Advance to the line-feed position.
        LD (HL),10                 ; Complete the CP/M line ending.
        INC HL                     ; Advance to function 9's terminator byte.
        LD (HL),'$'                ; Function 9 stops at the dollar byte.
        LD DE,SRTBUF           ; DE points to the completed message.
        JP SRTTEXT                 ; Send the completed text through byte output.

; Subtract one decimal place until the next subtraction would borrow.
SRTPLACE:
        LD B,0                     ; B counts how often the place value fits.
SRTPLP:
        OR A                       ; Clear carry before the signed subtraction.
        SBC HL,DE                  ; Try one more occurrence of this place.
        JR C,SRTPLDN          ; A borrow means the digit is complete.
        INC B                      ; Count the place value that fitted.
        JR SRTPLP            ; Continue until the next one would borrow.
SRTPLDN:
        ADD HL,DE                  ; Restore the first value that did not fit.
        LD A,B                     ; Copy the digit count for output decisions.
        OR A                       ; A nonzero count always becomes a digit.
        JR NZ,SRTPLOUT          ; Emit a significant digit.
        LD A,(SRTBEG)          ; Check whether a prior place emitted a digit.
        OR A                       ; A zero state still suppresses this place.
        RET Z                      ; Leave a leading zero out of the message.
SRTPLOUT:
        LD A,1                     ; Later zeroes are significant after this one.
        LD (SRTBEG),A          ; Publish the started state.
        LD A,B                     ; Convert the count to its ASCII digit.
        ADD A,'0'                  ; Add the ASCII zero offset.
        PUSH HL                    ; Preserve the remaining numeric value.
        LD HL,(SRTPTR)             ; Load the next output position.
        LD (HL),A                  ; Store the decimal digit.
        INC HL                     ; Advance the output cursor.
        LD (SRTPTR),HL             ; Preserve it for the next place.
        POP HL                     ; Restore the remaining numeric value.
        RET                        ; Return for the next decimal place.

SRTUNBD:
        LD DE,SRTUNBT        ; Explain the unbound reference.
        JP SRTOUT             ; Share the CP/M error-output path.
SRTERROR:
        CALL SRTDCLN              ; Clear active datum-reader roots before failure.
        LD DE,SRTERRTX          ; Explain an arithmetic or runtime failure.
SRTOUT:
        LD C,9                     ; Select CP/M's dollar-terminated output.
        CALL 5                     ; Print the terminal diagnostic.
        JP 0                       ; Do not return with a damaged value stack.

; Send a dollar-terminated runtime message through the selected byte service.
; Normal value output uses this path so a provider sees the same bytes as CP/M.
SRTTEXT:
        LD A,(DE)                  ; Read the next message byte.
        INC DE                     ; Advance before the service call can clobber DE.
        CP '$'                     ; Dollar terminates the internal text strings.
        RET Z                      ; Do not expose the terminator to the provider.
        CALL SRTCH                 ; Route one byte through the provider boundary.
        JR SRTTEXT                 ; Continue until the complete message is sent.

; Patched entry and generated-program data fields.
SRTRES:    DW 0                 ; Result payload retained by SRTPRINT.
SRTPTR:       DW 0                 ; Current decimal-output cursor.
SRTBEG:   DB 0                 ; Nonzero after the first significant digit.
SRTTAG:  DB 0                 ; Original tag retained by SRTFALSE.
SRTBOOL:      DB 0                 ; Branch decision retained while restoring A.
SRTOP:        DB 0                 ; Selected checked arithmetic operation.
SRTPID:       DB 0                 ; Predefined primitive kind for the active call.
SRTARGC:      DB 0                 ; Number of values in the current call packet.
SRTRESTF:     DB 0                 ; High-bit policy for the active procedure.
SRTMINAR:     DB 0                 ; Fixed minimum arity of the active procedure.
SRTRESTN:     DB 0                 ; Surplus values still waiting for the rest list.
SRTRESTI:     DB 0                 ; Packet index while reading surplus values.
SRTRESTC:     DB 0                 ; Original surplus count passed to SRTQBLD.
SRTNCT:       DB 0                 ; Number of generated operands not yet consumed.
; The exact-root operand table and allocation maps use a fixed work band
; outside the provider image.  The page domain ends its low band before 9000H,
; skips this band through B800H and manages B800H..C000H.
SRTNRTAB:     EQU 0A200H           ; Four-byte exact roots for up to 255 operands.
SRTNRVAL:     DW 0                 ; Shadow-root payload staging.
SRTNRTAG:     DB 0                 ; Shadow-root tag staging.
; These maps are outside the serialized provider image and occupy the 9000H
; through B800H work band reserved by the page manager.  Their larger extents
; cover the full 3000H..C000H address span, including images below 4000H.
SRTCLBM      EQU 09000H           ; 2304 bytes mark every allocated closure start.
SRTCLMK      EQU 09900H           ; 2304 bytes: even marks, odd vector type bits.
SRTBMB       EQU 0A600H           ; 4608 bytes mark every allocated binding start.
SRTNLEFT:     DB 0                 ; Remaining values in an arithmetic or compare fold.
SRTNACCT:     DB 0                 ; Accumulator tag for a variadic numeric fold.
SRTNTAG:      DB 0                 ; Current packet value tag during numeric work.
SRTNPTR:      DW 0                 ; Current packet cursor during a numeric fold.
SRTNACCV:     DW 0                 ; Accumulator payload for a variadic numeric fold.
SRTNVAL:      DW 0                 ; Current packet payload during numeric work.
SRTCCOD:      DW 0                 ; Raw NCMP relation for the current pair.
SRTLCN:       DB 0                 ; Remaining packet values while building list.
SRTLCP:       DW 0                 ; Packet cursor for the list builder.
SRTATMP:      DB 0                 ; Temporary tag while packing one argument.
SRTVAL:       DW 0                 ; Temporary payload while packing one argument.
SRTDESC:      DW 0                 ; Descriptor for the active procedure call.
SRTCDESC:     DW 0                 ; Descriptor belonging to the caller frame.
SRTFRMD:      DW 0                 ; Descriptor paired with the current frame map.
SRTCLPTR:     DW 0                 ; Binding pointer held across closure tracing.
SRTFRAME:     DW 0                 ; Active map base, zero while a frame is forming.
SRTOBJ:       DW 0                 ; Closure object currently being entered.
SRTENV:       DW 0                 ; Pointer array for the active procedure.
SRTCENV:      DW 0                 ; Caller environment restored at return.
SRTCENVN:     DB 0                 ; Active caller-map slot count for exact roots.
SRTNEWD:      DW 0                 ; Descriptor being copied into a closure.
SRTNENV:    DW 0                 ; Destination map during closure creation.
SRTHEAPP:     DW SRTHEPEN          ; Exclusive end of the closure/binding pool.
SRTBYTES:     DW 0                 ; Two-byte closure-map extent for the active shape.
SRTMAPB:      DW 0                 ; Four-byte active-map extent for the active shape.
SRTOLDSP:     DW 0                 ; Stack boundary before an activation map.
SRTLOWSP:     DW 0E400H            ; Lowest native stack boundary observed.
SRTBCNT:      DW 0                 ; Successful managed binding allocations.
SRTCCNT:      DW 0                 ; Successful closure allocations.
SRTPCNT:      DW 0                 ; Successful pair allocations.
SRTGCNT:      DW 0                 ; Entries into the stop-the-world collector.
SRTACNT:      DW 0                 ; Activation maps reserved by procedure calls.
SRTRET:       DW 0                 ; Helper return saved while moving the stack.
SRTCELLP:     DW 0                 ; Cell base retained during heap allocation.
SRTADDR:      DW 0                 ; Environment entry being filled.
SRTMASKP:     DW 0                 ; Descriptor mask cursor during activation setup.
SRTCURD:      DW 0                 ; Descriptor active before a tail transfer.
SRTSLOT:      DW 0                 ; Formal cell address during argument transfer.
SRTSADR:      DW 0                 ; Active four-byte slot address.
SRTSVAL:      DW 0                 ; Value payload held by a slot helper.
SRTSVTAG:     DB 0                 ; Value tag held by a slot helper.
SRTSFLG:      DB 0                 ; Active-slot flags held by a slot helper.
SRTSNUM:      DB 0                 ; Slot number held across promotion.
SRTNEXT:      DW 0                 ; Descriptor cursor during argument transfer.
SRTSRC:       DW 0                 ; Target closure map during a tail transfer.
SRTMASKV:     DB 0                 ; Current owned-mask byte.
SRTMASKN:     DB 0                 ; Capture-mask bytes left in a tail transfer.
SRTBITN:      DB 0                 ; Capture-mask bits left in the current byte.
SRTSLOTI:     DB 0                 ; Slot number represented by the mask cursor.
SRTSLOTS:     DB 0                 ; Number of pointer slots in the current shape.
SRTCSLOT:     DB 0                 ; Slot count used only while making a closure.
SRTCLSZ:      DW 0                 ; Rounded closure extent for allocation and sweep.
SRTCLIDX:     DB 0                 ; Four-byte size-class index for the active closure.
SRTCURS:      DB 0                 ; Pointer-slot extent of the current frame.
SRTIMGE:      DW 0                 ; Absolute end of the published runtime image.
SRTGBASE:     DW 0                 ; Start of published globals and static locals.
SRTGEND:      DW 0                 ; Exclusive end of globals and static locals.
SRTQROOT:     DW 0                 ; Absolute start of quoted-list cache records.
SRTQENDR:     DW 0                 ; Exclusive end of quoted-list cache records.
SRTSYMB:      DW 0                 ; Absolute start of the published symbol directory.
SRTSYME:      DW 0                 ; Exclusive end of the published symbol directory.
SRTARGPK:     DS 32                ; Eight four-byte argument records.
SRTOPS:       DW SRTOPB        ; Operator side-stack cursor between heap and guard.
SRTBUF:   DS 32                ; Decimal output buffer terminated for BDOS function 9.
SRTERRTX:  DB "RUNTIME ERROR",13,10,"$"
SRTUNBT: DB "UNBOUND",13,10,"$"

SRTEND:
