; Runtime state shared by output, invocation, storage and publication.
; These definitions remain after output code to preserve the image layout.
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
; skips this band through AB00H and manages AB00H..C000H.
SRTNRTAB:     EQU 0A200H           ; Four-byte exact roots for up to 255 operands.
SRTNRVAL:     DW 0                 ; Shadow-root payload staging.
SRTNRTAG:     DB 0                 ; Shadow-root tag staging.
; These maps are outside the serialized provider image and occupy the 9000H
; through AB00H work band reserved by the page manager.  Their larger extents
; cover the full 3000H..C000H address span, including images below 4000H.
SRTCLBM      EQU 09000H           ; 2304 bytes mark every allocated closure start.
SRTCLMK      EQU 09900H           ; 2304 bytes: even marks, odd vector type bits.
SRTBMB       EQU 0A600H           ; 1152 bytes: one bit per four-byte binding cell.
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
SRTMASKR:     DB 0                 ; Mask bytes left before the width runs out.
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
