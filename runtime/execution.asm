;=============================================================================
;  Skate native call, closure and binding ABI
;=============================================================================

%INCLUDE "execution-frame.asm"
%INCLUDE "execution-pairs.asm"
%INCLUDE "execution-primitives.asm"
%INCLUDE "execution-calls.asm"
%INCLUDE "execution-literals.asm"

;  PURPOSE
;  -------
;  Validate rooted call packets, dispatch closures and manage activations.

;  PUBLIC INTERFACE
;  ----------------

;+---------------------------------------------------------------------------+
;|  RTINIT                                                                   |
;|    Copy the checked region map and initialize runtime state.              |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTSTKCHK                                                                 |
;|    Check native-stack headroom before a call site.                        |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTPKNEW                                                                  |
;|    Reserve and clear a rooted call packet.                                |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTINVOKE                                                                 |
;|    Dispatch a computed closure without adding a continuation.             |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTTAIL                                                                   |
;|    Reuse the current activation for a staged tail packet.                 |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTENTER                                                                  |
;|    Establish or reuse the target activation record.                       |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTRETURN                                                                 |
;|    Root the result, restore caller state and return.                      |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTMKCLOS                                                                 |
;|    Allocate a closure with an optional captured environment.              |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTGETVAL                                                                    |
;|    Read a lexical binding using inline depth and slot operands.           |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTCURENV                                                                 |
;|    Return the active environment index in DE; preserve descriptor HL.     |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTSETBND                                                                 |
;|    Store A:HL in an initialized binding using inline depth and slot.     |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTINITBD                                                                 |
;|    Initialize an UNBOUND slot using inline depth and slot operands.      |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTLETFRM                                                                |
;|    Create a let environment from a rooted packet of initializer values.   |
;|    Input: DE = packet base; BC = binding count.                           |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RTLETEND                                                                |
;|    Restore the parent environment and root top; preserve result A:HL.      |
;+---------------------------------------------------------------------------+

;  REGION MAP (HL -> ten consecutive words)
;  -------------------------------------------
;
;  OFFSET  REGION
;  ------  ---------------------------
;  +0      Root base.
;  +2      Root end.
;  +4      Activation base.
;  +6      Activation end.
;  +8      Heap base.
;  +10     Code base.
;  +12     Code end.
;  +14     Native-stack low address.
;  +16     Global-table base, zero only when global count is zero.
;  +18     Global count; each entry occupies six bytes.

;  ACTIVATION RECORD (10 bytes)
;  ----------------------------
;
;  OFFSET  FIELD
;  +0      Previous IX.
;  +2      Packet base.
;  +4      Caller root restore.
;  +6      Native entry SP.
;  +8      Argument count.

;  ERROR SERVICE
;  -------------
;
;  The platform module supplies RTERROR.
;  A = 1 type; A = 2 arity; A = 3 capacity.
;  A = 4 invariant or configuration failure.
;  A = 5 read or assignment of an UNBOUND lexical binding.
;  A = 6 exact integer arithmetic overflow.
;=============================================================================

RTSMARG EQU 32
RTRECSZ EQU 10

; Load configuration and establish empty root and activation stacks.
RTINIT:
        LD DE,RTROOTB           ; Copy the ten-word region map into private state.
        LD BC,20                   ; The map contains ten two-byte configuration words.
        LDIR                       ; The caller keeps the map disjoint from this workspace.
        LD E,(HL)                 ; The extended map now names the string descriptors.
        INC HL                    ; Advance to the descriptor count word.
        LD D,(HL)                 ; Complete the descriptor-table address.
        INC HL                    ; Keep HL at the count field's following byte.
        LD (RTSTRBAS),DE          ; Retain the immutable string-table base.
        LD E,(HL)                 ; Read the number of four-byte string descriptors.
        INC HL                    ; Advance to the count high byte.
        LD D,(HL)                 ; Complete the descriptor count.
        INC HL                    ; Advance to the immutable string-pool address.
        LD (RTSTRCNT),DE         ; Retain the checked string count.
        LD E,(HL)                 ; Read the string-pool base low byte.
        INC HL                    ; Advance to the pool base high byte.
        LD D,(HL)                 ; Complete the string-pool base.
        INC HL                    ; Advance to the pool byte count.
        LD (RTSTRPOL),DE          ; Retain the immutable string-pool base.
        LD E,(HL)                 ; Read the complete string-pool byte count.
        INC HL                    ; Advance over the count low byte.
        LD D,(HL)                 ; Complete the pool byte count.
        LD (RTSTRBYT),DE         ; Retain the checked pool extent.
        CALL RTSTRCK               ; Validate descriptor and pool spans before execution.
        LD HL,(RTROOTB)         ; Root slots begin on a four-byte boundary.
        LD A,L                     ; Inspect the low address bits before accepting the map.
        AND 3                      ; A root slot is four bytes wide.
        JP NZ,RTBADCFG          ; Reject a misaligned root base before state setup.
        LD HL,(RTROOTX)          ; The exclusive root end must share that alignment.
        LD A,L                     ; No slot may straddle the configured region end.
        AND 3                      ; A partial final slot is not usable capacity.
        JP NZ,RTBADCFG          ; Reject a misaligned root end.
        LD HL,(RTROOTX)          ; Compare the root interval before publishing cursors.
        LD DE,(RTROOTB)         ; Subtract base from end to check that it is nonempty.
        OR A                       ; Clear carry before the unsigned extent comparison.
        SBC HL,DE                  ; A negative or zero extent cannot hold a call packet.
        JP C,RTBADCFG           ; The root end precedes its base.
        JP Z,RTBADCFG           ; An empty root stack cannot hold the two packet headers.
        LD HL,(RTAREND)            ; The activation arena also needs at least one record.
        LD DE,(RTARBASE)           ; Its end is exclusive; partial trailing bytes are allowed.
        OR A                       ; Start an unsigned subtraction.
        SBC HL,DE                  ; The usable record count is floor((end-base)/10).
        JP C,RTBADCFG           ; The activation end precedes its base.
        LD DE,RTRECSZ      ; Reject an arena smaller than one complete record.
        OR A                       ; Clear carry before testing the minimum size.
        SBC HL,DE                  ; At least ten bytes are required for one activation.
        JP C,RTBADCFG           ; A short arena cannot accept any procedure entry.
        LD HL,(RTCODEE)          ; Descriptors and entries must reside in the code image.
        LD DE,(RTCODEB)         ; Validate the half-open code interval.
        OR A                       ; Clear carry before comparing its endpoints.
        SBC HL,DE                  ; The code end must be above the code base.
        JP C,RTBADCFG           ; Reject a wrapped or reversed code range.
        JP Z,RTBADCFG           ; An empty code range contains no callable descriptor.
        LD A,(HREADY)              ; Call dispatch depends on an initialized heap.
        OR A                       ; HINIT publishes this flag only after building the free list.
        JP Z,RTBADCFG           ; Do not retain a heap base before allocator setup.
        LD HL,(HBASE)              ; The execution module and allocator must agree on the arena.
        LD DE,(RTHEAPB)         ; Configuration supplies the expected heap base.
        OR A                       ; Compare the two addresses as unsigned words.
        SBC HL,DE                  ; A mismatch means closure indices would decode incorrectly.
        JP NZ,RTBADCFG          ; Reject stale or inconsistent heap geometry.
        CALL RTGLOBCK              ; Validate the global-table extent and prepare its root span.
        LD HL,(RTROOTB)         ; Start with an empty value stack.
        LD (RTROOTP),HL              ; RTROOTP mirrors IY for the collector's root descriptor.
        LD (RTROOTMX),HL         ; No root slot has been used yet.
        LD (RTROOTDS),HL           ; The fixed descriptor always starts at ROOTBASE.
        LD HL,0                    ; The fixed descriptor initially scans no root slots.
        LD (RTROOTCT),HL           ; Keep its count zero until the first root is published.
        LD HL,4                    ; Every scanned value slot has a four-byte stride.
        LD (RTSTRIDE),HL           ; Install that stride before any allocation can collect.
        LD HL,(RTROOTB)              ; Reload ROOTBASE after storing the four-byte stride.
        PUSH HL                    ; Move the root base into the index register without aliasing it.
        POP IY                     ; IY is now the first unused root-slot address.
        LD HL,(RTARBASE)           ; Start with an empty activation stack.
        LD (RTACTCUR),HL            ; ARCUR points to the next ten-byte record.
        LD (RTACTHI),HL           ; No activation record has been published yet.
        LD IX,0                    ; Zero means the startup code has no current activation.
        XOR A                      ; Clear the one-shot reuse flag and return success.
        LD (RTREUSE),A             ; No target entry is inheriting an activation.
        RET                        ; Return with IY at the root base and IX zero.

; Validate the global table against the executable image and install its value span.
RTGLOBCK:
        LD HL,(RTGLBCNT)           ; A zero count is valid only with a zero table address.
        LD A,H                     ; Test both bytes of the configured entry count.
        OR L                       ; No entries means no global value roots exist.
        JP Z,RTGLBZRO              ; Set the empty descriptor after checking its address.
        LD DE,8193                 ; Global indices are thirteen-bit values, so at most 8192 fit.
        OR A                       ; Clear carry before the unsigned maximum comparison.
        SBC HL,DE                  ; 8193 is the first count that cannot be represented.
        JP NC,RTBADCFG             ; Reject oversized tables before multiplying the stride.
        LD HL,(RTGLBASE)           ; Begin with the declared table base.
        LD DE,(RTCODEB)            ; Every nonempty table must begin in the executable image.
        OR A                       ; Clear carry before the unsigned lower-bound check.
        SBC HL,DE                  ; A borrow means the table begins below CODEBASE.
        JP C,RTBADCFG              ; Do not inspect or scan an out-of-image table.
        LD HL,(RTGLBCNT)           ; Each table entry occupies six bytes.
        ADD HL,HL                  ; Retain 2*count before forming the complete byte length.
        LD D,H                     ; DE stores the two-byte partial product.
        LD E,L                     ; The two copies combine to form six times the count.
        ADD HL,HL                  ; HL now contains 4*count.
        ADD HL,DE                  ; Add 2*count to obtain the complete table length.
        LD DE,(RTGLBASE)           ; Add that length to the declared table base.
        ADD HL,DE                  ; HL is the table's exclusive end address.
        JP C,RTBADCFG              ; A wrapped extent cannot fit in the code image.
        LD DE,(RTCODEE)            ; The complete table may end exactly at CODEEND.
        OR A                       ; Clear carry before comparing the exclusive endpoints.
        SBC HL,DE                  ; Carry or equality means the table remains in the image.
        JP C,RTGLOBOK              ; A lower endpoint is wholly inside the executable range.
        JP Z,RTGLOBOK              ; Equality is valid for the complete table extent.
        JP RTBADCFG                ; Reject before computing any value-slot address.
RTGLOBOK:
        LD HL,(RTGLBASE)           ; Global entries begin with the two-byte symbol index.
        LD DE,2                    ; The collector starts at the following four-byte Slot.
        ADD HL,DE                  ; HL is the first global value-tag address.
        JP C,RTBADCFG              ; A wrapped value base contradicts the checked table extent.
        LD (RTGLOBDS),HL           ; Install the first strided global value slot.
        LD HL,(RTGLBCNT)           ; The descriptor scans one value from every entry.
        LD (RTGLOBC),HL            ; Retain the checked global count.
        LD HL,6                    ; Symbol index plus one four-byte value defines the stride.
        LD (RTGLBSTR),HL           ; Install the six-byte step between global values.
        RET                        ; RTROOTDS and RTGLOBDS now describe both root regions.
RTGLBZRO:
        LD HL,(RTGLBASE)           ; An empty global table must not advertise a stale address.
        LD A,H                     ; Test both bytes before accepting the zero-count case.
        OR L                       ; The address/count pair is either fully empty or present.
        JP NZ,RTBADCFG             ; Reject a nonzero base paired with an empty table.
        LD HL,0                    ; Keep the empty descriptor's slot pointer at zero.
        LD (RTGLOBDS),HL           ; The collector ignores this address when count is zero.
        LD (RTGLOBC),HL            ; Publish the empty global root count.
        LD HL,6                    ; Preserve the correct entry stride for later validation.
        LD (RTGLBSTR),HL           ; Empty descriptors still have a canonical stride.
        RET                        ; No global slot can be read or collected in this mode.

; Reserve the configured maximum call depth before executing a CALL.
RTSTKCHK:
        PUSH HL                    ; The descriptor or leaf argument may be live.
        PUSH DE                    ; Packet callers retain their base across this check.
        LD HL,0                    ; Clear the high word before copying the current SP.
        ADD HL,SP                  ; HL now contains the native stack pointer.
        LD DE,(RSTACKL)         ; Stack storage grows down toward this guard address.
        OR A                       ; Clear carry before measuring remaining headroom.
        SBC HL,DE                  ; HL is the number of bytes above the guard.
        JP C,RTCAPERR            ; SP below the guard leaves no safe helper area.
        LD DE,RTSMARG      ; Keep room for dispatch, entry and return helpers.
        OR A                       ; Begin a second unsigned subtraction.
        SBC HL,DE                  ; A short remainder means a helper could cross the guard.
        JP C,RTCAPERR            ; Fail before the caller pushes its continuation.
        POP DE                     ; Restore the packet base or caller's saved address.
        POP HL                     ; Restore the descriptor or caller's saved value.
        XOR A                      ; Sufficient headroom; carry is clear.
        RET                        ; Return without changing the caller's register contract.

; Add two NIL-initialized slots plus one slot per argument at the root top.
; Input BC is the argument count; output DE is the packet base and IY its end.
RTPKNEW:
        CALL RTSTKCHK          ; Packet setup itself uses the bounded native stack.
        LD (RTPKARGC),BC             ; Keep the requested argument count across extent checks.
        LD HL,(RTPKARGC)             ; Begin with the argument-slot count.
        LD DE,2                    ; The packet also contains environment and callee slots.
        ADD HL,DE                  ; Add those two fixed slots before scaling to bytes.
        JP C,RTCAPERR            ; Reject slot-count wrap before any root write.
        ADD HL,HL                  ; Two bytes per tagged value so far.
        JP C,RTCAPERR            ; Reject an overflowing packet extent.
        ADD HL,HL                  ; Four bytes per root slot.
        JP C,RTCAPERR            ; Reject wrap before calculating the endpoint.
        LD (RTPKLEN),HL              ; Retain the complete packet byte length.
        PUSH IY                    ; Read the current root top without changing it.
        POP DE                     ; DE is the candidate packet base.
        LD (RTPACKET),DE           ; Save the base while its full extent is checked.
        LD HL,(RTROOTB)         ; A packet may not begin below the configured roots.
        EX DE,HL                   ; Compare packet base against root base.
        OR A                       ; Clear carry before the unsigned comparison.
        SBC HL,DE                  ; A borrow means the caller's root cursor is invalid.
        JP C,RTCAPERR            ; Reject an out-of-range packet base before writing.
        PUSH IY                    ; Validate that the existing root cursor is still in range.
        POP HL                     ; HL is the current root top.
        LD DE,(RTROOTX)          ; Compare it with the exclusive root end.
        OR A                       ; Clear carry for unsigned comparison.
        SBC HL,DE                  ; A positive result means IY has passed the root limit.
        JP C,RTPKBASE           ; A top below the limit is valid.
        JP Z,RTPKBASE           ; A top exactly at the limit is also valid.
        JP RTCAPERR              ; Reject before writing any packet slot.
RTPKBASE:
        LD HL,(RTPACKET)           ; Add the requested packet size to its base.
        LD DE,(RTPKLEN)              ; The checked size includes every four-byte slot.
        ADD HL,DE                  ; HL is the exclusive packet end.
        JP C,RTCAPERR            ; Reject a wrapped end before any root write.
        LD (RTPKEND),HL              ; Keep the endpoint for both bound checks and commit.
        LD DE,(RTROOTX)          ; The full packet must fit below the root limit.
        OR A                       ; Compare endpoint and configured end as unsigned words.
        SBC HL,DE                  ; Carry or equality means the packet fits.
        JP C,RTPKINIT             ; The endpoint is below the limit.
        JP Z,RTPKINIT             ; The endpoint may equal the exclusive limit.
        JP RTCAPERR              ; Capacity failure occurs before the first slot is cleared.
RTPKINIT:
        LD HL,(RTPKARGC)             ; Clear the environment, callee and argument slots.
        LD DE,2                    ; The number of slots is arguments plus two headers.
        ADD HL,DE                  ; The earlier overflow check already proved this addition safe.
        LD B,H                     ; BC counts slots while HL walks their storage.
        LD C,L                     ; The loop initializes one complete four-byte value at a time.
        LD HL,(RTPACKET)           ; Start at the packet base returned to the caller.
RTPKLOOP:
        LD (HL),0                  ; NIL uses logical tag zero.
        INC HL                     ; Move to the low payload byte.
        LD (HL),2                  ; NIL payload is FE02H, in little-endian order.
        INC HL                     ; Move to the high payload byte.
        LD (HL),0FEH               ; Complete the fixed NIL payload.
        INC HL                     ; Move to the root-slot padding byte.
        LD (HL),0                  ; The collector requires zero padding.
        INC HL                     ; Advance to the next four-byte slot.
        DEC BC                     ; One environment/callee/argument slot is initialized.
        LD A,B                     ; Test the remaining 16-bit slot count.
        OR C                       ; The loop ends only after every slot is NIL.
        JP NZ,RTPKLOOP           ; Keep all reserved destinations safe at the next allocation.
        LD HL,(RTPKEND)              ; Publish the end only after packet initialization completes.
        PUSH HL                    ; Set both the architectural and collector-visible root cursors.
        POP IY                     ; IY remains the first unused root slot.
        LD (RTROOTP),HL              ; The collector scans exactly ROOTBASE..RTROOTP.
        LD HL,(RTROOTMX)         ; Compare this completed reservation with prior use.
        EX DE,HL                   ; DE holds the previous high-water address.
        LD HL,(RTROOTP)              ; HL holds the new root top.
        OR A                       ; Clear carry before the high-water comparison.
        SBC HL,DE                  ; A positive difference means the stack grew.
        JP C,RTPKHIGH          ; Keep the previous maximum when this packet is smaller.
        JP Z,RTPKHIGH          ; Equal tops do not change the high-water mark.
        LD HL,(RTROOTP)              ; Publish the new maximum root extent.
        LD (RTROOTMX),HL         ; Tests can inspect this address after execution.
RTPKHIGH:
        LD DE,(RTPACKET)           ; Return the packet base in the call input register.
        LD BC,(RTPKARGC)             ; Restore the requested argument count.
        XOR A                      ; Packet reservation succeeded; carry is clear.
        RET                        ; The caller may now evaluate operator and arguments.

; Activation and packet failures all terminate through the platform boundary.
RTTYERR:
        LD A,1                     ; Error 1 is a nonprocedure or malformed closure value.
        JP RTERROR                 ; The platform owns user-visible terminal diagnostics.
RTARERR:
        LD A,2                     ; Error 2 is an exact fixed-arity mismatch.
        JP RTERROR                 ; No activation has been published on this path.
RTCAPERR:
        LD A,3                     ; Error 3 covers root, activation and native-stack limits.
        JP RTERROR                 ; Capacity checks precede packet or record writes.
RTINVERR:
        LD A,4                     ; Error 4 identifies corrupted runtime metadata or state.
        JP RTERROR                 ; The runtime cannot safely resume after this condition.
RTUNBERR:
        LD A,5                     ; Error 5 is a read or assignment of an UNBOUND slot.
        JP RTERROR                 ; Internal definitions report this before publishing a value.
RTBADCFG:
        JP RTINVERR             ; Invalid setup is an invariant failure before execution.

; Validate the immutable string tables copied from the extended region map.
RTSTRCK:
        LD HL,(RTSTRCNT)         ; A zero count is valid only with an empty table pair.
        LD A,H                     ; Test both count bytes before reading its address.
        OR L                       ; No descriptors means no string references are valid.
        JP Z,RTSTRZER             ; Check the corresponding empty addresses below.
        LD DE,16384                ; 16,384 descriptors would wrap the 16-bit extent.
        OR A                       ; Clear carry before the unsigned count comparison.
        SBC HL,DE                  ; 16,384 is the first count whose extent wraps.
        JP NC,RTBADCFG             ; Reject a wrapped descriptor span before using it.
        LD HL,(RTSTRBAS)          ; Begin with the descriptor table's image address.
        LD DE,(RTCODEB)            ; Immutable tables must begin inside the code image.
        OR A                       ; Clear carry before the unsigned lower-bound check.
        SBC HL,DE                  ; A borrow means the table begins below CODEBASE.
        JP C,RTBADCFG              ; Reject the table before calculating its extent.
        LD HL,(RTSTRCNT)         ; Form four bytes per descriptor without multiplication.
        ADD HL,HL                  ; First doubling gives two bytes per descriptor.
        ADD HL,HL                  ; Second doubling gives the complete descriptor extent.
        JP C,RTBADCFG              ; A wrapped extent cannot belong to the image.
        LD DE,(RTSTRBAS)          ; Add the extent to the checked table base.
        ADD HL,DE                  ; HL is the descriptor table's exclusive end.
        JP C,RTBADCFG              ; A wrapped end cannot be resident.
        LD DE,(RTCODEE)            ; The table may end exactly at CODEEND.
        OR A                       ; Clear carry before comparing exclusive endpoints.
        SBC HL,DE                  ; Carry or equality means the span fits.
        JP C,RTSTRPC           ; A lower endpoint remains inside the image.
        JP Z,RTSTRPC           ; Equality is valid for the complete descriptor span.
        JP RTBADCFG                ; Reject an out-of-image descriptor table.
RTSTRPC:
        LD HL,(RTSTRBYT)         ; A zero-byte pool needs no resident address.
        LD A,H                     ; Test both pool-length bytes before validating its base.
        OR L                       ; Empty strings may share a zero pool address.
        RET Z                       ; Descriptor offsets and zero lengths remain valid.
        LD HL,(RTSTRPOL)          ; Begin with the nonempty string pool address.
        LD DE,(RTCODEB)            ; The pool must lie in the immutable image.
        OR A                       ; Clear carry before the unsigned lower-bound check.
        SBC HL,DE                  ; A borrow means the pool begins below CODEBASE.
        JP C,RTBADCFG              ; Reject the pool before reading any descriptor offset.
        LD HL,(RTSTRPOL)          ; Add the checked byte extent to the pool base.
        LD DE,(RTSTRBYT)         ; DE carries the complete immutable pool length.
        ADD HL,DE                  ; HL is the pool's exclusive end.
        JP C,RTBADCFG              ; A wrapped pool end cannot be resident.
        LD DE,(RTCODEE)            ; The pool may end exactly at CODEEND.
        OR A                       ; Clear carry before comparing exclusive endpoints.
        SBC HL,DE                  ; Carry or equality means the pool span fits.
        JP C,RTSTRGOD             ; A lower endpoint remains inside the image.
        JP Z,RTSTRGOD             ; Equality is valid for the complete pool span.
        JP RTBADCFG                ; Reject an out-of-image string pool.
RTSTRZER:
        LD HL,(RTSTRBAS)          ; Empty descriptor tables must advertise a zero base.
        LD A,H                     ; Test both address bytes before accepting emptiness.
        OR L                       ; A stale address would make string references ambiguous.
        JP NZ,RTBADCFG             ; Reject a nonzero base paired with zero descriptors.
        LD HL,(RTSTRPOL)          ; Empty pools use the same canonical zero address.
        LD A,H                     ; Test both pool-address bytes.
        OR L                       ; A nonzero pool without descriptors is invalid metadata.
        JP NZ,RTBADCFG             ; Reject before startup publishes runtime state.
RTSTRGOD:
        RET                        ; The immutable table spans are now inside the code image.

; Runtime-owned coordinates and non-reentrant helper scratch.
RTWORK:
RTROOTB: DW 0                   ; First four-byte tagged root slot.
RTROOTX: DW 0                    ; Exclusive end of root storage.
RTARBASE: DW 0                      ; First ten-byte activation record.
RTAREND: DW 0                       ; Exclusive end of activation storage.
RTHEAPB: DW 0                    ; Must match allocator HBASE after HINIT.
RTCODEB: DW 0                    ; Lowest callable descriptor/entry address.
RTCODEE: DW 0                     ; Exclusive code and descriptor extent.
RSTACKL: DW 0                    ; Guard address below the descending native stack.
RTGLBASE: DW 0                    ; Global-table base copied from region-map word eight.
RTGLBCNT: DW 0                    ; Global-table count from region-map word nine.
RTROOTP: DW 0                         ; Collector-visible root top; mirrors IY.
RTROOTMX: DW 0                    ; Greatest root-top address observed.
RTACTCUR: DW 0                       ; Next unused activation-record address.
RTACTHI: DW 0                      ; Greatest activation end observed.
RTREUSE: DB 0                       ; One-shot flag consumed by the next procedure entry.
RTISPRIM: DB 0                      ; One when dispatch selected a primitive wrapper.
RTPRIMID: DB 0                      ; Primitive identity decoded from FE20H through FE3CH.
RTNUMOP: DB 0                       ; Numeric fold operation: 0 add, 1 subtract, 2 multiply, 3 divide.
RTNUMTAG: DB 0                      ; Logical tag of the current numeric accumulator.
RTNUMIDX: DW 0                      ; Argument index currently consumed by numeric folding.
RTNUMACC: DW 0                      ; Payload of the current numeric accumulator.
RTARGTAG: DB 0                      ; Logical tag of the current staged argument.
RTARGVAL: DW 0                      ; Payload of the current staged argument.
RTCMPMD: DB 0                      ; Comparison relation: equal, less, greater, <= or >=.
RTCMPFLG: DB 0                     ; Accumulated adjacent-comparison truth flag.
RTCPCODE: DW 0                     ; Raw NCMP result for the current adjacent pair.
RTPKARGC: DW 0                        ; Current packet's fixed argument count.
RTPKLEN: DW 0                         ; Current packet byte length, including its two headers.
RTPACKET: DW 0                      ; Current or staged packet base.
RTPKEND: DW 0                         ; Current packet's exclusive end.
RTCHKTP: DW 0                    ; IY captured while validating a packet.
RTDESCPT: DW 0                        ; Resolved immutable procedure descriptor.
RTPASSED: DW 0                      ; Descriptor supplied by the target entry stub.
RTTARGET: DW 0                      ; Validated native entry address.
RTSLOTS: DW 0                       ; Validated lexical frame slot count.
RTMINAR: DW 0                       ; Minimum arity loaded from the procedure descriptor.
RTRESTF: DB 0                       ; Nonzero selects dotted-formal surplus-list binding.
RTRESTIX: DW 0                      ; Argument index while a surplus list is built.
RTAPFTAG: DB 0                      ; Procedure tag retained while apply stages its packet.
RTAPFVAL: DW 0                      ; Procedure payload retained across list validation.
RTAPLTAG: DB 0                      ; Current apply-list tag during count and fill passes.
RTAPLLST: DW 0                      ; Current apply-list payload during pair traversal.
RTAPOTAG: DB 0                      ; Original apply-list tag retained across the count pass.
RTAPOVAL: DW 0                      ; Original apply-list payload retained for the fill pass.
RTAPCNT: DW 0                       ; Number of proper-list elements staged by apply.
RTAPLEFT: DW 0                      ; Remaining list elements during packet filling.
RTAPDST: DW 0                       ; Next four-byte argument slot in the staged packet.
RTAPVTAG: DB 0                      ; CAR tag retained while its destination is addressed.
RTAPVVAL: DW 0                      ; CAR payload retained while its CDR is decoded.
RTINDEX: DW 0                       ; Closure heap-cell index during address decoding.
RTPKDST: DW 0                        ; Current activation packet base for tail copying.
RTPKSRC: DW 0                         ; Staged packet base for tail copying.
RTPKXEND: DW 0                     ; Validated tail packet end at the destination.
RTACTNEW: DW 0                     ; Candidate activation record during publication.
RTUSRSP: DW 0                     ; Original user return-word address at entry.
RTNATSP: DW 0                       ; Saved native entry SP while RTRETURN restores IX.
RTACTPRV: DW 0                        ; Previous activation while RTRETURN restores SP.
RTRESVAL: DW 0                      ; Result payload preserved across the return epilogue.
RTRESTAG: DB 0                      ; Result tag paired with RTRESVAL.
RTALIGN: DB 0                     ; Kept zero for alignment of following workspace.
RTROOTDS: DW 0                      ; Collector descriptor base for active value roots.
RTROOTCT: DW 0                      ; Active root-slot count derived from IY.
RTSTRIDE: DW 0                      ; Active value-root stride, always four bytes.
RTGLOBDS: DW 0                      ; First global value-tag address, or zero when empty.
RTGLOBC: DW 0                      ; Number of global value slots in the table.
RTGLBSTR: DW 0                    ; Global value-slot stride, including its symbol index.
RTDSCADR: DW 0                      ; Descriptor supplied to RTMKCLOS.
RTCAPIDX: DW 0                      ; Captured environment index supplied to RTMKCLOS.
RTCLOIDX: DW 0                      ; Closure cell index during construction.
RTMKADDR: DW 0                      ; Closure cell address during construction.
RTCAPENV: DW 0                      ; Captured environment index decoded from a closure.
RTVALCNT: DW 0                      ; Packet root slots left to check before dispatch.
RTLINKIX: DW 0                     ; Next lexical link read or previous cell during frame build.
RTSLOTIX: DW 0                      ; Current lexical slot while bindings are built.
RTCELLIX: DW 0                      ; Heap index returned by the current HPOP.
RTCELADR: DW 0                     ; HPOP address or selected lexical binding cell address.
RTFRAMEI: DW 0                      ; Environment header index being constructed.
RTFRAMEA: DW 0                      ; Address of the environment header under construction.
RTVALTAG: DB 0                     ; Logical tag for frame construction or a binding update.
RTVALPAY: DW 0                     ; Payload for frame construction or a binding update.
RTDEPLO: DB 0                      ; Low depth byte consumed from an inline lexical operand.
RTDEPHI: DB 0                      ; High depth byte consumed from an inline lexical operand.
RTSLOTLO: DB 0                     ; Low slot byte consumed from an inline lexical operand.
RTSLOTHI: DB 0                     ; High slot byte consumed from an inline lexical operand.
RTACCPTR: DW 0                     ; Return PC after the inline lexical depth and slot.
RTDEPTH: DW 0                      ; Parent links remaining during lexical lookup.
RTSLOTNO: DW 0                     ; Binding links remaining during lexical lookup.
RTENVIND: DW 0                     ; Active or parent environment index during lookup.
RTCURPKT: DW 0                     ; Rooted environment-slot address from the active packet.
RTBNDIND: DW 0                     ; Header or binding index supplied to RTREADLK.
RTBINDMD: DB 0                     ; Zero selects heap cells; one selects global image data.
RTBNDADR: DW 0                     ; Direct global tag address, retained across value access.
RTGETTAG: DB 0                     ; Validated CAR tag read from the selected binding.
RTGETPAY: DW 0                     ; Selected binding payload while its return PC is restored.
RTCARPTR: DW 0                      ; Rooted packet address from which pair CAR is loaded.
RTCDRPTR: DW 0                      ; Rooted packet or accumulator slot for pair CDR.
RTCARTAG: DB 0                      ; Logical tag of CAR during pair construction/comparison.
RTCARVAL: DW 0                      ; Payload of CAR during pair construction/comparison.
RTCDRTAG: DB 0                      ; Logical tag of CDR during pair construction.
RTCDRVAL: DW 0                      ; Payload of CDR during pair construction.
RTPAIRIX: DW 0                     ; Pair anchor index or ordinary CDR link being checked.
RTPAIRAD: DW 0                     ; Address of the pair anchor under inspection.
RTPHYTAG: DB 0                      ; Validated physical anchor tag: ordinary or escaped.
RTMETALO: DB 0                      ; Escaped metadata low byte containing both logical tags.
RTAUXIDX: DW 0                      ; Escaped-pair auxiliary cell index.
RTAUXADR: DW 0                      ; Address of an escaped-pair auxiliary cell.
RTNEWIDX: DW 0                     ; Anchor index reserved for the pair being built.
RTNEWADR: DW 0                     ; Anchor address reserved for the pair being built.
RTESCFLG: DB 0                      ; Nonzero selects the two-cell escaped-pair layout.
RTLISTIX: DW 0                     ; Argument index while list cells are built backwards.
RTSTRBAS: DW 0                    ; Immutable four-byte string descriptor table.
RTSTRCNT: DW 0                   ; Number of string descriptors in the image.
RTSTRPOL: DW 0                    ; Immutable byte pool for literal strings.
RTSTRBYT: DW 0                   ; Number of bytes in the immutable string pool.
RTSTRIDX: DW 0                     ; String descriptor index while printing a value.
RTSTROFF: DW 0                     ; Byte offset loaded from the selected descriptor.
RTSTRLEN: DW 0                     ; Byte length loaded from the selected descriptor.
RTSTRPTR: DW 0                     ; Current byte in the selected immutable string.
RTWEND:

; Literal-recipe interpreter state.  The service keeps its bounded parser
; cursor and temporary packet separate from procedure and primitive scratch.
RTLIPTR:  DW 0                     ; Next recipe byte to inspect.
RTLILEFT: DW 0                     ; Remaining recipe bytes.
RTLIPACK: DW 0                     ; Rooted packet base for stack and call slots.
RTLIBASE:  DW 0                    ; First four-byte value-stack slot.
RTLIDEP:  DW 0                     ; Current postfix value-stack depth.
RTLIDEST: DW 0                     ; Destination slot for a newly consed value.
RTLITAG:  DB 0                     ; Atom tag while its payload is checked.
RTLICART: DB 0                     ; CAR tag copied from the value stack.
RTLICARV: DW 0                     ; CAR payload copied from the value stack.
RTLICDRT: DB 0                     ; CDR tag copied from the value stack.
RTLICDRV: DW 0                     ; CDR payload copied from the value stack.
RTLICRET: DB 0                     ; Selected result tag during root compaction.
RTLICREV: DW 0                     ; Selected result payload during compaction.
