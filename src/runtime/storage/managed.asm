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
        JP Z,RT_UNDEF
        LD A,(HL)
        AND 0FH                    ; The stored tag, eight included.
        LD (RT_TAG),A
        EX DE,HL
        RET

; Store a value in a four-byte heap binding and retain its capture and mark bits.
HEAP_PUT:
        LD (RT_TAG),A
        LD (ARG_VAL),HL
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
        LD A,(RT_TAG)
        OR BND_INIT+BND_USED       ; The value is initialized and allocated.
        OR B
        LD (DE),A
        LD A,(RT_TAG)
        LD HL,(ARG_VAL)
        RET

; Store through a four-byte heap binding only after its initialized bit is set.
HEAP_SET:
        LD (ARG_TAG),A
        LD (ARG_VAL),HL
        LD (HEAP_OBJ),DE
        INC DE
        INC DE
        INC DE
        LD A,(DE)
        AND BND_INIT
        JP Z,RT_UNDEF
        LD DE,(HEAP_OBJ)
        LD A,(ARG_TAG)
        LD HL,(ARG_VAL)
        JP HEAP_PUT

; Allocate a fresh closure object.  HL names its descriptor and the current
; environment supplies the shared cell pointers for a nested lambda.
HEAP_LAM:
        LD (DESC_NEW),HL          ; Retain the immutable procedure descriptor.
        LD HL,(ENV_CUR)            ; Captured inline values must be promoted before allocation.
        LD A,H
        OR L
        JR Z,.TOP                  ; A top-level closure has no active parent map.
        CALL SLOT_CAP              ; Promotion keeps every captured value GC-visible.
.TOP:
        LD HL,(DESC_NEW)
        LD DE,3                   ; Descriptor byte three stores the slot count.
        ADD HL,DE                 ; Read the fixed environment extent.
        LD A,(HL)                 ; Every closure receives that bounded slot area.
        LD (CL_SLOTS),A           ; Preserve the count while sizing the object.
        LD (CL_COUNT),A           ; The same count drives class selection and tracing.
        CALL SLAB_SZ              ; Calculate pointer bytes, rounded size and class.
        CALL SLAB_NEW             ; Reuse a dead object before growing the cursor.
        JR NC,.GOT
        CALL GC                   ; A full closure pool may contain dead objects.
        LD A,(CL_SLOTS)           ; Collection may use the same sizing scratch.
        LD (CL_COUNT),A           ; Restore the pending closure's slot count.
        CALL SLAB_SZ               ; Recompute bytes and class after collection.
        CALL SLAB_NEW
        JP C,ERROR                ; No class block remains after one collection.
.GOT:
        LD DE,(CNT_CLOS)           ; Count this successful closure allocation.
        INC DE
        LD (CNT_CLOS),DE
        LD (FRM_CLOS),HL          ; Return this pointer after copying the frame.
        LD (HEAP_OBJ),HL          ; Clear the entire rounded block before publishing.
        LD BC,(CL_SIZE)
        XOR A
.CLEAR:
        XOR A
        LD HL,(HEAP_OBJ)
        LD (HL),A
        INC HL
        LD (HEAP_OBJ),HL
        DEC BC
        LD A,B
        OR C
        JR NZ,.CLEAR
        CALL GC_OBJON              ; Record the exact closure object boundary.
        LD DE,(FRM_CLOS)           ; Restore the object base after bitmap arithmetic.
        LD HL,(DESC_NEW)           ; Store the descriptor pointer in the object.
        LD A,L                     ; Descriptor low byte.
        LD (DE),A
        INC DE
        LD A,H                     ; Descriptor high byte.
        LD (DE),A
        INC DE                     ; DE now names the new environment area.
        LD (ENV_DST),DE            ; Keep the destination across the copy.
        LD HL,(ENV_CUR)            ; An outer environment may seed this closure.
        LD A,H
        OR L
        JR Z,.NO_ENV               ; Top-level closures receive cleared slots.
        CALL MAP_ENV               ; Copy only promoted captured pointers.
.MARK:
        CALL ENV_MARK              ; Captured cells must survive later tail calls.
        JR .DONE                   ; Return the object pointer and procedure tag.
.NO_ENV:
        LD HL,(ENV_DST)            ; Clear the fresh environment when no parent exists.
        LD BC,(FRM_CLEN)           ; BC is the bounded byte count.
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
        LD HL,(FRM_CLOS)           ; Return the closure object as the payload.
        LD A,2                     ; Tag two denotes a callable closure object.
        RET                        ; The generated prefix jumps over its body.

; Calculate the current closure's four-byte class and rounded allocation size.
SLAB_SZ:
        LD A,(CL_COUNT)
        LD L,A
        LD H,0
        ADD HL,HL                 ; Two bytes represent each shared cell pointer.
        LD (FRM_CLEN),HL          ; Preserve the unrounded environment byte count.
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
        LD (CL_SIZE),HL
        SRL H
        RR L
        SRL H
        RR L
        DEC L
        LD A,L
        LD (CL_CLASS),A
        RET

; Select a dead block from the active class or allocate a typed closure slab.
; Carry set means no page or contiguous run remains below the binding cursor.
SLAB_NEW:
        LD A,(CL_CLASS)
        CP 40H
        JR NZ,.SMALL
        CALL SLAB_RUN              ; A 260-byte closure owns a two-page run.
        RET C
        LD (CL_BASE),HL
        CALL SLAB_INC
        RET C                      ; An unowned page cannot accept the allocation.
        LD HL,(CL_BASE)
        XOR A
        RET
.SMALL:
        LD A,(CL_CLASS)
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,CL_FREE
        ADD HL,DE
        LD (CL_HEAD),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD A,D
        OR E
        JR Z,.GROW
        LD (CL_BASE),DE
        EX DE,HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD HL,(CL_HEAD)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(CL_BASE)
        CALL SLAB_INC
        RET C                      ; An unowned page cannot accept the allocation.
        LD HL,(CL_BASE)
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
        JP C,ERROR
.GOT:
        LD DE,(CNT_BIND)           ; Count this successful binding allocation.
        INC DE
        LD (CNT_BIND),DE
        LD (HEAP_OBJ),HL
        CALL GC_VARON                ; Publish the exact binding start before stores.
        JP C,ERROR                  ; Never initialise a cell the collector cannot see.
        XOR A
        LD (HL),A                   ; Clear the payload low byte.
        INC HL
        LD (HL),A                   ; Clear the payload high byte.
        INC HL
        LD (HL),A                   ; Keep the future payload extension zero.
        INC HL
        LD A,BND_USED               ; Allocation is distinct from initialization.
        LD (HL),A
        LD HL,(HEAP_OBJ)            ; Return the new cell address in HL.
        RET

; Pop a reclaimed binding or allocate the next four-byte slot in a page.
.ALLOC:
        LD HL,(BND_FREE)
        LD A,H
        OR L
        JR Z,.IN_PAGE
        LD (HEAP_OBJ),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (BND_FREE),DE
        LD HL,(HEAP_OBJ)
        XOR A
        RET
.IN_PAGE:
        LD HL,(BND_NEXT)
        LD A,H
        OR L
        JR Z,.NEW_PAGE
        LD (HEAP_OBJ),HL
        LD DE,CELL_SZ
        ADD HL,DE
        LD DE,(BND_END)
        OR A
        SBC HL,DE
        JR C,.FITS
        JR Z,.FITS
        JR .NEW_PAGE
.FITS:
        LD HL,(HEAP_OBJ)
        LD DE,CELL_SZ
        ADD HL,DE
        LD (BND_NEXT),HL
        LD HL,(HEAP_OBJ)
        XOR A
        RET
.NEW_PAGE:
        LD A,(BND_CNT)
        CP 80H
        JR NC,.FULL
        LD HL,1
        CALL PAGE_NEW
        RET C
        LD (BND_BASE),HL
        LD (BND_SAVE),HL
        LD A,(BND_CNT)
        LD L,A
        LD H,0
        LD DE,BND_PHYS
        ADD HL,DE
        LD DE,(BND_SAVE)
        LD A,D
        LD (HL),A
        LD A,(BND_CNT)
        INC A
        LD (BND_CNT),A
        LD HL,(BND_BASE)
        LD DE,CELL_SZ
        ADD HL,DE
        LD (BND_NEXT),HL
        LD HL,(BND_BASE)
        LD DE,100H
        ADD HL,DE
        LD (BND_END),HL
        LD (BND_TOP),HL
        LD HL,(BND_BASE)
        XOR A
        RET
.FULL:
        SCF
        RET
