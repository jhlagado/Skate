%INCLUDE "origin.asm"
%INCLUDE "../runtime/allocator.asm"
%INCLUDE "../runtime/collector.asm"
%INCLUDE "../runtime/binary16.asm"
%INCLUDE "../runtime/numeric.asm"
%INCLUDE "../runtime/execution.asm"

; Establish one heap, bitmap and execution-region map for every ABI case.
TESTINIT:
        LD SP,0F000H             ; Keep the test stack below its declared guard.
        LD HL,HEAPBASE           ; HINIT builds the free list before RTINIT checks it.
        LD BC,128                ; Reserve 127 usable cells for closure fixtures.
        CALL HINIT               ; The allocator validates the full arena before writing.
        JP C,TALLOCER       ; Setup errors stop before execution tests begin.
        LD HL,BMAPBAS         ; GCSET installs the exact mark-bitmap extent.
        LD BC,16                 ; 128 physical cells require sixteen bitmap bytes.
        CALL GCSET               ; The collector remains available to future M7 frame tests.
        JP C,TALLOCER       ; Do not continue with an unconfigured collector.
        LD HL,RTCONFIG           ; Install root, activation, heap, code and stack bounds.
        CALL RTINIT              ; RTINIT also verifies that HINIT used this heap base.
        RET                      ; Return with IX zero and IY at ROOTBASE.

; Create a real allocator-owned closure for the common test procedure.
TMAKEC:
        LD HL,RTCONFIG           ; The harness resets CPU registers between entry points.
        CALL RTINIT              ; Restore the runtime's empty root cursor before allocation.
        LD HL,TPDESC             ; The closure retains this immutable procedure descriptor.
        LD DE,0                  ; This test lambda captures no outer environment.
        CALL RTMKCLOS            ; Runtime allocation publishes a fully initialized closure.
        LD A,H                   ; The returned payload includes closure subtype two.
        AND 01FH                 ; Keep only the low thirteen heap-index bits.
        LD H,A                   ; HL is now the untagged closure index.
        LD (TCLOIDX),HL          ; Packet setup stores that index in a REF/CLOSURE value.
        RET                      ; Return with the allocator-owned closure ready for use.

; Prepare the oversized-descriptor closure before its no-write failure proof.
TMAKEBIG:
        LD HL,RTCONFIG           ; Start with a valid empty root cursor for RTMKCLOS.
        CALL RTINIT              ; The harness resets IY between public test entry points.
        LD HL,TPBIGDS            ; This closure points at the intentionally oversized descriptor.
        LD DE,0                  ; No environment is captured by the test closure.
        CALL RTMKCLOS            ; Allocate the closure before the test snapshots heap state.
        LD A,H                   ; Remove closure subtype bits from the returned payload.
        AND 01FH                 ; Keep the thirteen-bit heap-cell index.
        LD H,A                   ; HL is now the untagged index stored in the test workspace.
        LD (TCLOIDX),HL          ; The following failure case must not allocate another closure.
        RET                      ; Return with the invalid-size target ready for dispatch.

; Exercise a direct CALL to a statically known literal-lambda entry.
RUNDIR:
        CALL TRESET           ; Clear root/activation cursors without touching the heap.
        LD BC,1                  ; The literal closure takes one fixed argument.
        CALL RTPKNEW             ; Reserve environment, callee and argument root slots.
        LD (TPACKET),DE       ; Save the packet address while filling its values.
        CALL TFILLPK      ; Store the closure and exact integer argument.
        LD HL,DIRCONT         ; The body must see the CALL continuation at its SP.
        LD (TEXPECT),HL       ; Save that return PC for the common body assertion.
        LD DE,(TPACKET)       ; Restore the packet base after the setup helper.
        LD BC,1                  ; Restore the arity consumed by packet construction.
        CALL RTSTKCHK        ; Prove room before the direct CALL pushes a continuation.
        CALL TPENTRY       ; Direct path skips RTINVOKE but shares RTENTER/RTRETURN.
DIRCONT:
        RET                      ; The procedure result is already rooted at packet base.

; Exercise a computed closure through RTINVOKE and its descriptor jump.
RUNIND:
        CALL TRESET           ; Each case begins with IX=0 and empty root/activation stacks.
        LD BC,1                  ; The computed closure also takes one argument.
        CALL RTPKNEW             ; The entire call packet is rooted before dispatch.
        LD (TPACKET),DE       ; Keep its base while the tagged callee is installed.
        CALL TFILLPK      ; The value comes from a packet slot, not a direct label.
        LD HL,INCONT       ; The target must return through RTINVOKE's original CALL.
        LD (TEXPECT),HL       ; Save the expected continuation for the body assertion.
        LD DE,(TPACKET)       ; Restore the rooted packet base.
        LD BC,1                  ; Restore its exact argument count.
        CALL RTSTKCHK        ; Prove room before CALL RTINVOKE.
        CALL RTINVOKE            ; The resolver uses JP, leaving one continuation on the stack.
INCONT:
        RET                      ; Return to the host harness after the native call completes.

; Read both arguments through their reverse-linked heap bindings.
RUN2ARG:
        CALL TRESET              ; Begin with the dynamic roots and activations empty.
        LD HL,TPDESC2            ; Use a second fixed-arity procedure descriptor.
        LD DE,0                  ; This lambda has no captured parent environment.
        CALL RTMKCLOS            ; Construct a fresh closure through the runtime service.
        LD A,H                   ; Remove the closure subtype from the returned payload.
        AND 01FH                 ; Only the thirteen-bit cell index belongs in TCLOIDX.
        LD H,A                   ; HL is now the untagged heap index.
        LD (TCLOIDX),HL          ; Packet setup will store this closure in its callee slot.
        LD BC,2                  ; The procedure accepts two exact arguments.
        CALL RTPKNEW             ; Root the callee and both argument destinations first.
        LD (TPACKET),DE          ; Preserve the packet base while filling its values.
        CALL TFILL2              ; Store exact arguments forty-two and ninety-nine.
        LD HL,TWOACONT           ; Both bindings must be readable before the caller resumes.
        LD (TEXPECT),HL          ; The body checks this original continuation.
        LD DE,(TPACKET)          ; Restore the complete rooted packet base.
        LD BC,2                  ; Restore the exact arity after packet creation.
        CALL RTSTKCHK            ; Check stack room before adding the invocation continuation.
        CALL RTINVOKE            ; Computed dispatch reaches the second descriptor's entry.
TWOACONT:
        RET                      ; RTRETURN has placed argument one in the result root.

; Exercise repeated tail transfer while observing continuation and frame reuse.
RUNTAIL:
        CALL TRESET           ; Start from a fresh root and activation extent.
        LD BC,1                  ; Every tail transfer uses the same fixed arity.
        CALL RTPKNEW             ; Reserve the initial procedure packet.
        LD (TPACKET),DE       ; Save the destination packet for setup.
        CALL TFILLPK      ; Install the allocator-owned closure and first argument.
        LD A,1                   ; Select the bounded tail-loop body.
        LD (TTLMODE),A      ; The same native entry will service each transfer.
        LD A,25                  ; Twenty-five tail jumps follow the initial entry.
        LD (TTLLEFT),A      ; The test counter is deliberately outside the call stack.
        XOR A                    ; No body entry has been observed yet.
        LD (TTLCNT),A     ; The test checks activation depth independently of count.
        LD HL,TAILCONT           ; Every iteration must retain this one caller continuation.
        LD (TEXPECT),HL       ; The common body verifies it at each target entry.
        LD DE,(TPACKET)       ; Restore the initial packet base.
        LD BC,1                  ; Restore the fixed argument count.
        CALL RTSTKCHK        ; Reserve headroom before the initial indirect call.
        CALL RTINVOKE            ; Later transfers use JP RTTAIL and do not push return words.
TAILCONT:
        RET                      ; The final reused activation consumes the original word.

; Exhaust free cells so frame entry collects its already-rooted call packet.
RUNGCFRE:
        CALL TRESET              ; Keep the initialized heap but clear runtime cursors.
        LD BC,1                  ; The packet contains one callee and one exact argument.
        CALL RTPKNEW             ; Reserve and publish the entire root packet first.
        LD (TPACKET),DE          ; Preserve its base while installing the input values.
        CALL TFILLPK             ; Root both the closure and forty-two before allocation.
        LD BC,(HFCOUNT)          ; Reserve every remaining free cell as unreachable garbage.
        LD (TGCFILL),BC          ; HPOP clobbers BC, so retain the exact fill count.
        CALL HRES                ; This reservation succeeds without needing collection.
        JP C,TALLOCER            ; A failed setup invalidates the forced-collection proof.
TGCLOOP:
        LD HL,(TGCFILL)          ; Test how many reserved garbage cells remain to pop.
        LD A,H                   ; Combine both count bytes before the termination check.
        OR L                     ; Zero means every permitted pop has been consumed.
        JP Z,TGCDONE             ; HDONE releases the completed garbage construction.
        CALL HPOP                ; Remove and clear one cell without allowing a collection.
        JP C,TALLOCER            ; Every pop must fit the bulk reservation.
        LD HL,(TGCFILL)          ; Decrement the retained count after this successful pop.
        DEC HL                   ; One fewer unreachable cell remains to consume.
        LD (TGCFILL),HL          ; Preserve the count across the next allocator call.
        JP TGCLOOP               ; Fill the entire free list before invoking the procedure.
TGCDONE:
        CALL HDONE               ; The zeroed cells are now allocated but unreachable.
        LD HL,GCCONT             ; The frame's collection must preserve this continuation.
        LD (TEXPECT),HL          ; The body checks the original caller return address.
        LD DE,(TPACKET)          ; Restore the packet base for the computed call.
        LD BC,1                  ; The closure descriptor has fixed arity one.
        CALL RTSTKCHK            ; Check native room before CALL RTINVOKE.
        CALL RTINVOKE            ; GRES must retain the rooted closure and argument.
GCCONT:
        RET                      ; The body returns the value from its collected frame.

; Reject wrong arity before a computed call can publish an activation record.
RUNARERR:
        CALL TRESET              ; Reset cursors but retain the closure in the heap.
        LD BC,0                   ; The descriptor requires one argument.
        CALL RTPKNEW              ; A zero-argument packet still has environment and callee slots.
        LD (TPACKET),DE            ; Save the packet base while installing its closure.
        CALL TFILLCAL              ; Keep the closure rooted; no argument slot is present.
        LD DE,(TPACKET)            ; Restore packet base for dynamic dispatch.
        LD BC,0                   ; Preserve the deliberately incorrect count.
        CALL RTSTKCHK              ; The arity trap must precede activation publication.
        CALL RTINVOKE              ; This path terminates with error category two.
ARERRRET:
        RET                        ; Unreachable after the platform error boundary halts.

; Reject a descriptor whose frame is larger than the entire physical heap.
RUNBIGFR:
        CALL TRESET              ; Keep existing heap objects but reset roots and activations.
        LD BC,1                  ; The descriptor arity is valid even though its frame is not.
        CALL RTPKNEW             ; Prepare and root one argument before dispatch.
        LD (TPACKET),DE          ; Preserve the packet base while installing its values.
        CALL TFILLPK             ; Capacity failure must occur after packet validation.
        LD DE,(TPACKET)          ; Restore packet base for descriptor resolution.
        LD BC,1                  ; Preserve the correct fixed arity.
        CALL RTSTKCHK            ; Check stack room before invoking the closure.
        CALL RTINVOKE            ; RTFRAME must reject before heap or activation writes.
BIGFRET:
        RET                      ; Unreachable after the terminal capacity error.

; Reject the first string-descriptor count whose four-byte extent wraps.
RSTRMAX:
        CALL TRESET              ; Begin with a valid initialized execution map.
        LD HL,TCODEB             ; Keep the table base inside the code image.
        LD (RTSTRBAS),HL         ; RTSTRCK must reject the count before using it.
        LD HL,16384              ; Exactly 16,384 descriptors occupy 65,536 bytes.
        LD (RTSTRCNT),HL         ; The exclusive extent would wrap to the base.
        XOR A                    ; No pool is needed to exercise the descriptor bound.
        LD (RTSTRBYT),A          ; Clear the low pool-byte count.
        LD (RTSTRBYT+1),A        ; Clear the high pool-byte count.
        CALL RTSTRCK              ; The invariant trap proves the span is rejected.
        RET                      ; Unreachable after RTSTRCK reports the bad configuration.

; Reject a packet that exceeds the configured root extent before clearing slots.
RUNROOTC:
        CALL TRESET              ; Start with the full root interval and an empty IY.
        LD HL,ROOTBASE+8         ; Leave room for headers but not a one-argument packet.
        LD (RTROOTX),HL             ; The test narrows the runtime limit before reservation.
        LD BC,1                  ; Environment, callee and one argument require twelve bytes.
        CALL RTPKNEW             ; Capacity failure must occur before the first root write.
ROOTCRET:
        RET                      ; Unreachable after the terminal capacity error.

; Restore empty dynamic cursors while retaining the initialized heap closure.
TRESET:
        LD HL,RTCONFIG           ; RTINIT clears IX, IY, activation use and root high-water.
        CALL RTINIT              ; The immutable region map remains valid between cases.
        XOR A                    ; Clear mode and observation fields for one independent run.
        LD (TTLMODE),A      ; Normal body returns a fixed value.
        LD (TTLCNT),A     ; No tail entries have been counted.
        LD (TOBSIX),A         ; Clear the low byte before storing a zero word below.
        LD (TOBSIX+1),A       ; Observation starts with no activation address.
        RET                      ; Return with the allocator and closure untouched.

; Fill a packet's callee slot with the allocator-owned closure reference.
TFILLCAL:
        LD HL,(TPACKET)       ; The helper receives its packet through private test state.
        LD DE,4                  ; Slot one follows the environment slot at packet +0.
        ADD HL,DE                ; HL now addresses the callee's tag byte.
        LD (HL),1                ; Logical tag one means a reference value.
        INC HL                   ; Advance to the closure payload low byte.
        LD DE,(TCLOIDX)     ; The allocator returned this nonzero cell index.
        LD A,D                   ; Add closure subtype two in payload bits 14..12.
        OR 040H                  ; A capture-free closure uses link index zero.
        LD (HL),E                ; Store payload low byte.
        INC HL                   ; Advance to payload high byte.
        LD (HL),A                ; Store subtype and high index bits.
        INC HL                   ; Advance to the collector padding byte.
        LD (HL),0                ; Root Slots always have zero padding.
        RET                      ; Return without writing an argument slot.

; Store one exact integer argument after the callee has been rooted.
TFILLPK:
        CALL TFILLCAL              ; Initialize the callee before adding argument data.
        LD HL,(TPACKET)       ; Reload the packet base for argument zero.
        LD DE,8                  ; Argument zero follows the two header slots.
        ADD HL,DE                ; HL now addresses the first argument tag.
        LD (HL),3                ; Logical tag three denotes an exact signed integer.
        INC HL                   ; Advance to argument payload low byte.
        LD (HL),42               ; Store the exact value forty-two.
        INC HL                   ; Advance to argument payload high byte.
        LD (HL),0                ; Forty-two fits in the low payload byte.
        INC HL                   ; Advance to slot padding.
        LD (HL),0                ; Keep every active root descriptor well formed.
        RET                      ; The caller owns the packet until RTRETURN publishes a result.

; Fill a two-argument packet with distinguishable exact values.
TFILL2:
        CALL TFILLCAL             ; Root the second procedure closure before its arguments.
        LD HL,(TPACKET)           ; Argument zero begins at packet offset eight.
        LD DE,8                   ; Skip environment and callee Slots.
        ADD HL,DE                 ; HL addresses argument zero's logical tag byte.
        LD (HL),3                 ; The first argument is an exact signed integer.
        INC HL                    ; Advance to its payload low byte.
        LD (HL),42                ; Argument zero is forty-two.
        INC HL                    ; Advance to its payload high byte.
        LD (HL),0                 ; Forty-two fits in one payload byte.
        INC HL                    ; Advance to the first root slot's padding.
        LD (HL),0                 ; Keep its four-byte Slot canonical.
        LD HL,(TPACKET)           ; Reload the packet base for argument one.
        LD DE,12                  ; Argument one follows argument zero's four-byte slot.
        ADD HL,DE                 ; HL now addresses argument one's tag byte.
        LD (HL),3                 ; The second argument is also exact.
        INC HL                    ; Advance to its payload low byte.
        LD (HL),99                ; Argument one is ninety-nine.
        INC HL                    ; Advance to its payload high byte.
        LD (HL),0                 ; Ninety-nine fits in one payload byte.
        INC HL                    ; Advance to the second root slot's padding.
        LD (HL),0                 ; The active collector requires zero padding.
        RET                       ; Both values remain rooted until RTFRAME copies them.

; Common procedure entry for both direct and descriptor-dispatched calls.
TPENTRY:
        LD HL,TPDESC       ; Direct code supplies its immutable descriptor address.
        CALL RTENTER             ; Both paths establish exactly the same activation record.
        JP TPBODY          ; The original caller return word remains at [SP].

; Entry wrapper for the two-argument parameter lookup proof.
T2ENTRY:
        LD HL,TPDESC2           ; The common entry validates this exact descriptor identity.
        CALL RTENTER            ; The procedure receives the same packet and activation ABI.
        JP T2BODY               ; The caller's original continuation remains at [SP].

; Read slot zero and slot one to prove reverse-built bindings preserve lexical order.
T2BODY:
        LD L,(IX+2)              ; Inspect the current activation's packet environment slot.
        LD H,(IX+3)              ; The frame reference is at the same record offset for every call.
        LD A,(HL)                ; Save its logical tag before RTRETURN replaces the slot.
        LD (TOBSECT),A           ; The environment must be a reference value.
        INC HL                   ; Advance to the environment payload low byte.
        LD E,(HL)                ; Preserve the low heap-index byte.
        INC HL                   ; Advance to the payload high byte.
        LD D,(HL)                ; DE is subtype three plus the high index bits.
        LD (TOBSENV),DE          ; Keep the environment payload for host-side checks.
        CALL RTGETVAL               ; Read the first parameter from lexical slot zero.
        DW 0,0                   ; The address is in the current frame at depth zero.
        LD (T2VAL0),HL           ; Preserve forty-two while looking up the next binding.
        LD (T2TAG0),A            ; Preserve the first parameter's logical tag.
        CALL RTGETVAL               ; Read the second parameter through the next binding link.
        DW 0,1                   ; The second lexical address is depth zero, slot one.
        JP RTRETURN              ; Return ninety-nine in the common value convention.

; Entry wrapper for the deliberately impossible frame-size descriptor.
TBIGENTR:
        LD HL,TPBIGDS            ; The target stub must pass the same descriptor as its closure.
        CALL RTENTER             ; The capacity error should occur in RTFRAME before publication.
        JP TPBODY                ; Unreachable, but the descriptor still names a valid entry.

; Verify return PC/SP/IY/IX at each entry and return the integer argument.
TPBODY:
        LD (TOBSSP),SP        ; Record the native entry stack address for the harness.
        PUSH IX                  ; Copy the active record pointer without changing IX.
        POP HL                   ; HL is the address observed at the procedure body.
        LD (TOBSIX),HL        ; Tail entries must all reuse this same ten-byte record.
        PUSH IY                  ; Copy the root top without changing its live value.
        POP HL                   ; HL is the active packet end at body entry.
        LD (TOBSIY),HL        ; The host compares it with the exact packet high-water.
        POP HL                   ; Read the actual continuation without consuming it permanently.
        LD (TOBSRET),HL       ; Preserve the return PC for both test inspection and compare.
        PUSH HL                  ; Restore the original return word and SP before the body continues.
        LD DE,(TEXPECT)       ; Load the one continuation expected by this test run.
        OR A                     ; Clear carry before comparing the observed PC.
        SBC HL,DE                ; A zero difference proves dispatch added no persistent return.
        JP NZ,RTINVERR        ; Stop if direct, indirect or tail dispatch changed the PC.
        LD L,(IX+2)              ; Inspect the current activation's packet environment slot.
        LD H,(IX+3)              ; Tail entries reuse the packet at this same record offset.
        LD A,(HL)                ; Save the logical tag before RTRETURN replaces this slot.
        LD (TOBSECT),A           ; The environment must be a logical heap reference.
        INC HL                   ; Advance to its payload low byte.
        LD E,(HL)                ; Preserve the environment index's low byte.
        INC HL                   ; Advance to its payload high byte.
        LD D,(HL)                ; DE is subtype three plus the high index bits.
        LD (TOBSENV),DE          ; Keep the frame reference for host-side layout checks.
        LD A,(TTLMODE)      ; Normal direct/indirect calls return immediately.
        OR A                     ; Nonzero selects the repeated tail-call path.
        JP NZ,TTAILBDY       ; Each tail body stages another rooted packet.
        CALL RTGETVAL                ; Read parameter zero from the heap binding cell.
        DW 0,0                    ; The lexical address is depth zero, slot zero.
        JP RTRETURN               ; Root the looked-up argument and restore the continuation.

; Stage an identical closure packet, then replace this activation via RTTAIL.
TTAILBDY:
        LD A,(TTLCNT)     ; Count every body entry, including the initial call.
        INC A                    ; One more transfer reached the same procedure descriptor.
        LD (TTLCNT),A     ; The count is a test observation, not part of its recursion path.
        LD A,(TTLLEFT)      ; A zero counter ends the measured tail sequence.
        OR A                     ; Test before decrementing or staging another packet.
        JP Z,TTAILEND        ; The final body returns through RTRETURN.
        DEC A                    ; One bounded tail step has now been consumed.
        LD (TTLLEFT),A      ; The next entry observes the updated test count.
        LD BC,1                  ; Reserve one callee and one argument beyond the live packet.
        CALL RTPKNEW             ; This staging extent is discarded after the overlap-safe copy.
        LD (TPACKET),DE       ; Retain the higher source packet while filling it.
        CALL TFILLPK      ; The callee and argument are rooted before RTTAIL.
        LD DE,(TPACKET)       ; Restore the staged packet base.
        LD BC,1                  ; Restore its fixed argument count.
        JP RTTAIL                ; Reuse the activation and its original continuation.
TTAILEND:
        CALL RTGETVAL               ; Read parameter zero from the final reused lexical frame.
        DW 0,0                   ; The tail target has the same depth-zero slot address.
        JP RTRETURN              ; This consumes the initial caller word exactly once.

; Terminal test trap: preserve the runtime category and halt for host inspection.
RTERROR:
        LD (TERROR),A         ; The fixture observes the exact failure category.
        HALT                     ; No error path resumes Scheme execution.
TALLOCER:
        LD A,4                   ; Setup failures indicate a broken test fixture invariant.
        JP RTERROR               ; The host reports the error instead of running partial setup.

; Address-space fixtures. The arrays are external RAM, not bytes in the image.
ROOTBASE EQU 06000H
ROOTEND EQU 06400H
ACTBASE EQU 06500H
ACTEND EQU 06900H
BMAPBAS EQU 07000H
HEAPBASE EQU 08000H
HPCELLS EQU 128
STACKLOW EQU 0E000H

; The descriptor's entry address is the wrapper used by direct and indirect calls.
TPDESC:
        DW TPENTRY
        DW 1
        DW 1
        DW 0

TPDESC2:
        DW T2ENTRY
        DW 2
        DW 2
        DW 0

TPBIGDS:
        DW TBIGENTR
        DW 1
        DW 0FFFFH
        DW 0

TCODEB EQU 0100H
TCODEE:
RTCONFIG:
        DW ROOTBASE
        DW ROOTEND
        DW ACTBASE
        DW ACTEND
        DW HEAPBASE
        DW TCODEB
        DW TCODEE
        DW STACKLOW
        DW 0                    ; No global table is needed by this runtime fixture.
        DW 0                    ; Keep the ABI-2 region map's empty-table pair explicit.
        DW 0                    ; No immutable string descriptor table is needed here.
        DW 0                    ; Keep the extended string count empty.
        DW 0                    ; No immutable string pool is needed here.
        DW 0                    ; Keep the extended string byte count empty.

; Test observations and a persistent allocator-owned closure index.
TESTWORK:
TPACKET: DW 0
TCLOIDX: DW 0
TEXPECT: DW 0
TOBSSP: DW 0
TOBSIX: DW 0
TOBSIY: DW 0
TOBSRET: DW 0
TOBSENV: DW 0
T2VAL0: DW 0
TGCFILL: DW 0
TERROR: DB 0
TOBSECT: DB 0
T2TAG0: DB 0
TTLMODE: DB 0
TTLLEFT: DB 0
TTLCNT: DB 0
TESTWEND:
