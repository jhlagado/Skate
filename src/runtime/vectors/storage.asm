; Vector class allocation and address validation.
; VEC_NEW consumes VEC_REQ and may collect. Success returns the block in HL
; with carry clear; allocation failure sets carry.
; Constructor values must remain rooted across that allocation.

; Allocate a vector block and set its ownership and type marker.
VEC_NEW:
        CALL VEC_SIZE              ; Derive the rounded class from the request.
        CALL SLAB_NEW              ; Reuse a class block before growing the pool.
        JR NC,.GOT                 ; Carry clear means a block is reserved.
        CALL GC                     ; Reclaim dead managed objects once.
        CALL VEC_SIZE              ; Recompute the request-sized class after collection.
        CALL SLAB_NEW              ; Retry the same class after sweeping.
        RET C                      ; Preserve the capacity failure for the caller.
.GOT:
        LD (VEC_OBJ),HL            ; Retain the exact block start.
        LD (FRM_CLOS),HL           ; GC_OBJON publishes the common start bitmap.
        CALL GC_OBJON               ; Publish the allocation start in the map.
        CALL VEC_SETM               ; Mark the block as a vector, not a closure.
        LD HL,(VEC_OBJ)            ; Return the block base to the constructor.
        OR A                       ; Clear carry after successful publication.
        RET
; Compute a rounded four-byte class for one-byte count plus four-byte values.
VEC_SIZE:
        LD A,(VEC_REQ)             ; Read the constructor count, not tracer scratch.
        LD L,A
        LD H,0
        ADD HL,HL                  ; Multiply the count by four.
        ADD HL,HL
        INC HL                     ; Add the count byte at the front of the block.
        LD BC,3                    ; Round the one-mod-four size upward.
        ADD HL,BC
        LD A,L
        AND 0FCH                   ; Preserve H while clearing the low residue.
        LD L,A
        LD (CL_SIZE),HL            ; The class allocator consumes the rounded size.
        SRL H
        RR L
        SRL H
        RR L
        DEC L                      ; Four bytes per class index, zero based.
        LD A,L
        LD (CL_CLASS),A            ; Publish the selected class for SLAB_NEW.
        RET

; Validate HL as a vector address; the caller has already checked its tag.
; Carry clear returns the object base in HL. Scratch registers are clobbered.
VEC_CHK:
        LD (CL_OBJ),HL             ; Preserve the candidate across range checks.
        LD DE,RT_HEAP              ; Reject values below the managed pool.
        OR A
        SBC HL,DE
        JP C,.BAD
        LD HL,(CL_OBJ)              ; Vector starts are aligned to four bytes.
        LD A,L
        AND 3
        JP NZ,.BAD
        LD DE,(HEAP_LIM)            ; Reject values at or above the pool end.
        OR A
        SBC HL,DE
        JP NC,.BAD
        CALL VEC_TEST                ; Require the exact vector marker bit.
        JP Z,.BAD
        LD HL,(CL_OBJ)              ; Find the owning logical closure page.
        LD (CL_BASE),HL
        CALL SLAB_AT
        LD A,(CL_PAGE)
        CP 80H
        JP NC,.BAD                  ; A missing owner cannot describe a vector.
        LD L,A
        LD H,0
        LD DE,CL_OWNER
        ADD HL,DE
        LD A,(HL)                   ; The owner byte is class index plus one.
        CP 1
        JP C,.BAD
        CP 42H                      ; Class 64 is the two-page upper limit.
        JP NC,.BAD
        DEC A
        LD (CL_CLASS),A
        CALL SLAB_GET                ; Recover the physical page base.
        LD A,(CL_CLASS)              ; Rebuild the exact class extent from its owner.
        INC A
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD (CL_SIZE),HL
        LD HL,(CL_OBJ)
        LD DE,(CL_PBASE)
        OR A
        SBC HL,DE                   ; Compute the within-page object offset.
        JP C,.BAD
        LD A,(CL_CLASS)
        CP 40H
        JR Z,.TWO_PAGE              ; The 260-byte class may start only at zero.
        LD A,H
        OR A
        JP NZ,.BAD                  ; A one-page class cannot cross its page.
        JR .LEN_CHK
.TWO_PAGE:
        LD A,H
        OR L
        JP NZ,.BAD                  ; The two-page class has one legal object start.
.LEN_CHK:
        LD HL,(CL_OBJ)              ; Read the length only after ownership is proven.
        LD A,(HL)
        LD (VEC_LEN),A
        CP 65
        JP NC,.BAD                  ; The stored count must fit the supported class.
        LD L,A
        LD H,0
        ADD HL,HL                  ; Calculate count times four.
        ADD HL,HL
        INC HL                     ; Include the length byte in the used extent.
        LD DE,(CL_SIZE)
        OR A
        SBC HL,DE
        JR C,.GOOD                  ; A smaller used extent fits the class block.
        JR Z,.GOOD                  ; An exact class-sized vector is also valid.
        JP .BAD                     ; A larger used extent is malformed.
.GOOD:
        LD HL,(CL_OBJ)
        OR A
        RET
.BAD:
        SCF                         ; The candidate is not a live vector start.
        RET
