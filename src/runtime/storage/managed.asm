; Managed closure and binding storage for the scope-control runtime.
;
; Compiler-owned static records and dynamic heap cells use four bytes.  Heap
; cells carry two payload bytes, a reserved extension byte and packed metadata.
; Closures use rounded four-byte size classes in typed 256-byte pages;
; bindings grow down from the pool ceiling and stop at the closure high-water
; mark.

; Load a four-byte heap binding addressed by HL.  Static compiler slots use
; RT_LOAD; this helper is selected only through an active environment map.
HEAP_GET:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        LD A,(HL)
        AND BND_INIT
        JP Z,SRTUNBD
        LD A,(HL)
        AND 0FH                    ; The stored tag, eight included.
        LD (SRTTAG),A
        EX DE,HL
        RET

; Store a value in a four-byte heap binding and retain its capture and mark bits.
HEAP_PUT:
        LD (SRTTAG),A
        LD (SRTVAL),HL
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        XOR A
        LD (DE),A                  ; The extension byte stays clear.
        INC DE
        LD A,(DE)
        AND BND_ESC+BND_USED+BND_MARK
        LD B,A                     ; Keep the escape, allocation and mark bits.
        LD A,(SRTTAG)
        OR BND_INIT+BND_USED       ; The value is initialized and allocated.
        OR B
        LD (DE),A
        LD A,(SRTTAG)
        LD HL,(SRTVAL)
        RET

; Store through a four-byte heap binding only after its initialized bit is set.
HEAP_SET:
        LD (SRTATMP),A
        LD (SRTVAL),HL
        LD (SRTCELLP),DE
        INC DE
        INC DE
        INC DE
        LD A,(DE)
        AND BND_INIT
        JP Z,SRTUNBD
        LD DE,(SRTCELLP)
        LD A,(SRTATMP)
        LD HL,(SRTVAL)
        JP HEAP_PUT

; Allocate a fresh closure object.  HL names its descriptor and the current
; environment supplies the shared cell pointers for a nested lambda.
HEAP_LAM:
        LD (SRTNEWD),HL           ; Retain the immutable procedure descriptor.
        LD HL,(SRTENV)             ; Captured inline values must be promoted before allocation.
        LD A,H
        OR L
        JR Z,.TOP                  ; A top-level closure has no active parent map.
        CALL SLOT_CAP              ; Promotion keeps every captured value GC-visible.
.TOP:
        LD HL,(SRTNEWD)
        LD DE,3                   ; Descriptor byte three stores the slot count.
        ADD HL,DE                 ; Read the fixed environment extent.
        LD A,(HL)                 ; Every closure receives that bounded slot area.
        LD (SRTCSLOT),A           ; Preserve the count while sizing the object.
        LD (SRTCLN),A             ; The same count drives class selection and tracing.
        CALL SLAB_SZ              ; Calculate pointer bytes, rounded size and class.
        CALL SLAB_NEW             ; Reuse a dead object before growing the cursor.
        JR NC,.GOT
        CALL GC                   ; A full closure pool may contain dead objects.
        LD A,(SRTCSLOT)           ; Collection may use the same sizing scratch.
        LD (SRTCLN),A             ; Restore the pending closure's slot count.
        CALL SLAB_SZ               ; Recompute bytes and class after collection.
        CALL SLAB_NEW
        JP C,SRTERROR             ; No class block remains after one collection.
.GOT:
        LD DE,(SRTCCNT)            ; Count this successful closure allocation.
        INC DE
        LD (SRTCCNT),DE
        LD (SRTOBJ),HL            ; Return this pointer after copying the frame.
        LD (SRTCELLP),HL          ; Clear the entire rounded block before publishing.
        LD BC,(SRTCLSZ)
        XOR A
.CLEAR:
        XOR A
        LD HL,(SRTCELLP)
        LD (HL),A
        INC HL
        LD (SRTCELLP),HL
        DEC BC
        LD A,B
        OR C
        JR NZ,.CLEAR
        CALL GC_OBJON              ; Record the exact closure object boundary.
        LD DE,(SRTOBJ)             ; Restore the object base after bitmap arithmetic.
        LD HL,(SRTNEWD)            ; Store the descriptor pointer in the object.
        LD A,L                     ; Descriptor low byte.
        LD (DE),A
        INC DE
        LD A,H                     ; Descriptor high byte.
        LD (DE),A
        INC DE                     ; DE now names the new environment area.
        LD (SRTNENV),DE            ; Keep the destination across the copy.
        LD HL,(SRTENV)             ; An outer environment may seed this closure.
        LD A,H
        OR L
        JR Z,.NO_ENV               ; Top-level closures receive cleared slots.
        CALL MAP_ENV               ; Copy only promoted captured pointers.
.MARK:
        CALL ENV_MARK              ; Captured cells must survive later tail calls.
        JR .DONE                   ; Return the object pointer and procedure tag.
.NO_ENV:
        LD HL,(SRTNENV)            ; Clear the fresh environment when no parent exists.
        LD BC,(SRTBYTES)           ; BC is the bounded byte count.
        LD A,B                     ; A zero-sized map needs no clearing pass.
        OR C
        JR Z,.DONE                 ; Nullary closures return immediately.
        XOR A                      ; Uninitialized values start at zero bytes.
.ENV_LOOP:
        XOR A                      ; Keep every cleared byte at zero.
        LD (HL),A                  ; Clear one value byte.
        INC HL                     ; Advance through the new environment.
        DEC BC                     ; Consume one byte from the bounded extent.
        LD A,B
        OR C
        JR NZ,.ENV_LOOP            ; Stop exactly at the environment boundary.
.DONE:
        LD HL,(SRTOBJ)             ; Return the closure object as the payload.
        LD A,2                     ; Tag two denotes a callable closure object.
        RET                        ; The generated prefix jumps over its body.

; Calculate the current closure's four-byte class and rounded allocation size.
SLAB_SZ:
        LD A,(SRTCLN)
        LD L,A
        LD H,0
        ADD HL,HL                 ; Two bytes represent each shared cell pointer.
        LD (SRTBYTES),HL          ; Preserve the unrounded environment byte count.
        LD BC,2
        ADD HL,BC                 ; The descriptor pointer precedes the map.
        LD A,L
        AND 3
        JR Z,.ALIGNED
        LD BC,4
        ADD HL,BC
        LD A,L
        AND 0FCH
        LD L,A
.ALIGNED:
        LD (SRTCLSZ),HL
        SRL H
        RR L
        SRL H
        RR L
        DEC L
        LD A,L
        LD (SRTCLIDX),A
        RET

; Select a dead block from the active class or allocate a typed closure slab.
; Carry set means no page or contiguous run remains below the binding cursor.
SLAB_NEW:
        LD A,(SRTCLIDX)
        CP 40H
        JR NZ,.SMALL
        CALL SLAB_RUN              ; A 260-byte closure owns a two-page run.
        RET C
        LD (SRTCLBAS),HL
        CALL SLAB_INC
        RET C                      ; An unowned page cannot accept the allocation.
        LD HL,(SRTCLBAS)
        XOR A
        RET
.SMALL:
        LD A,(SRTCLIDX)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,SRTCFREE
        ADD HL,DE
        LD (SRTCLFP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.GROW
        LD (SRTCLBAS),DE
        EX DE,HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(SRTCLFP)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(SRTCLBAS)
        CALL SLAB_INC
        RET C                      ; An unowned page cannot accept the allocation.
        LD HL,(SRTCLBAS)
        XOR A
        RET
.GROW:
        CALL SLAB_ADD
        RET C
        JP SLAB_NEW

; Allocate and clear one four-byte heap binding.
HEAP_NEW:
        CALL .ALLOC
        JR NC,.GOT
        CALL GC                     ; Reclaim dead bindings before reporting full.
        CALL .ALLOC
        JP C,SRTERROR
.GOT:
        LD DE,(SRTBCNT)            ; Count this successful binding allocation.
        INC DE
        LD (SRTBCNT),DE
        LD (SRTCELLP),HL
        CALL GC_VARON                ; Publish the exact binding start before stores.
        JP C,SRTERROR               ; Never initialise a cell the collector cannot see.
        XOR A
        LD (HL),A                   ; Clear the payload low byte.
        INC HL
        LD (HL),A                   ; Clear the payload high byte.
        INC HL
        LD (HL),A                   ; Keep the future payload extension zero.
        INC HL
        LD A,BND_USED               ; Allocation is distinct from initialization.
        LD (HL),A
        LD HL,(SRTCELLP)            ; Return the new cell address in HL.
        RET

; Pop a reclaimed binding or allocate the next four-byte slot in a page.
.ALLOC:
        LD HL,(SRTBHEAD)
        LD A,H
        OR L
        JR Z,.IN_PAGE
        LD (SRTCELLP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTBHEAD),DE
        LD HL,(SRTCELLP)
        XOR A
        RET
.IN_PAGE:
        LD HL,(SRTBPGP)
        LD A,H
        OR L
        JR Z,.NEW_PAGE
        LD (SRTCELLP),HL
        LD DE,CELL_SZ
        ADD HL,DE
        LD DE,(SRTBPGED)
        OR A
        SBC HL,DE
        JR C,.FITS
        JR Z,.FITS
        JR .NEW_PAGE
.FITS:
        LD HL,(SRTCELLP)
        LD DE,CELL_SZ
        ADD HL,DE
        LD (SRTBPGP),HL
        LD HL,(SRTCELLP)
        XOR A
        RET
.NEW_PAGE:
        LD A,(SRTBPGN)
        CP 80H
        JR NC,.FULL
        LD HL,1
        CALL PAGE_NEW
        RET C
        LD (SRTBPGBA),HL
        LD (SRTBPGC),HL
        LD A,(SRTBPGN)
        LD L,A
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        LD DE,(SRTBPGC)
        LD A,D
        LD (HL),A
        LD A,(SRTBPGN)
        INC A
        LD (SRTBPGN),A
        LD HL,(SRTBPGBA)
        LD DE,CELL_SZ
        ADD HL,DE
        LD (SRTBPGP),HL
        LD HL,(SRTBPGBA)
        LD DE,100H
        ADD HL,DE
        LD (SRTBPGED),HL
        LD (SRTBEND),HL
        LD HL,(SRTBPGBA)
        XOR A
        RET
.FULL:
        SCF
        RET
