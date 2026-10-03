; Vector class allocation and address validation.
; SRTVACL consumes SRTVREQ and may collect. Success returns the block in HL
; with carry clear; allocation failure sets carry.
; Constructor values must remain rooted across that allocation.

; Allocate a vector block and set its ownership and type marker.
SRTVACL:
        CALL SRTVSZ                ; Derive the rounded class from the request.
        CALL SLAB_NEW              ; Reuse a class block before growing the pool.
        JR NC,SRTVAK               ; Carry clear means a block is reserved.
        CALL GC                     ; Reclaim dead managed objects once.
        CALL SRTVSZ                ; Recompute the request-sized class after collection.
        CALL SLAB_NEW              ; Retry the same class after sweeping.
        RET C                      ; Preserve the capacity failure for the caller.
SRTVAK:
        LD (SRTVOBJ),HL            ; Retain the exact block start.
        LD (SRTOBJ),HL             ; GC_OBJON publishes the common start bitmap.
        CALL GC_OBJON               ; Publish the allocation start in the map.
        CALL SRTVSMK                ; Mark the block as a vector, not a closure.
        LD HL,(SRTVOBJ)            ; Return the block base to the constructor.
        OR A                       ; Clear carry after successful publication.
        RET
; Compute a rounded four-byte class for one-byte count plus four-byte values.
SRTVSZ:
        LD A,(SRTVREQ)             ; Read the constructor count, not tracer scratch.
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
        LD (SRTCLSZ),HL            ; The class allocator consumes the rounded size.
        SRL H
        RR L
        SRL H
        RR L
        DEC L                      ; Four bytes per class index, zero based.
        LD A,L
        LD (SRTCLIDX),A            ; Publish the selected class for SLAB_NEW.
        RET

; Validate HL as a vector address; the caller has already checked its tag.
; Carry clear returns the object base in HL. Scratch registers are clobbered.
SRTVLD:
        LD (SRTCLOBJ),HL           ; Preserve the candidate across range checks.
        LD DE,RT_HEAP              ; Reject values below the managed pool.
        OR A
        SBC HL,DE
        JP C,SRTVBD
        LD HL,(SRTCLOBJ)            ; Vector starts are aligned to four bytes.
        LD A,L
        AND 3
        JP NZ,SRTVBD
        LD DE,(SRTHEAPP)            ; Reject values at or above the pool end.
        OR A
        SBC HL,DE
        JP NC,SRTVBD
        CALL SRTVSST                 ; Require the exact vector marker bit.
        JP Z,SRTVBD
        LD HL,(SRTCLOBJ)            ; Find the owning logical closure page.
        LD (SRTCLBAS),HL
        CALL SLAB_AT
        LD A,(SRTCLPGI)
        CP 80H
        JP NC,SRTVBD                ; A missing owner cannot describe a vector.
        LD L,A
        LD H,0
        LD DE,SRTCLOWN
        ADD HL,DE
        LD A,(HL)                   ; The owner byte is class index plus one.
        CP 1
        JP C,SRTVBD
        CP 42H                      ; Class 64 is the two-page upper limit.
        JP NC,SRTVBD
        DEC A
        LD (SRTCLIDX),A
        CALL SLAB_GET                ; Recover the physical page base.
        LD A,(SRTCLIDX)              ; Rebuild the exact class extent from its owner.
        INC A
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD (SRTCLSZ),HL
        LD HL,(SRTCLOBJ)
        LD DE,(SRTCLPGA)
        OR A
        SBC HL,DE                   ; Compute the within-page object offset.
        JP C,SRTVBD
        LD A,(SRTCLIDX)
        CP 40H
        JR Z,SRTV2PG                ; The 260-byte class may start only at zero.
        LD A,H
        OR A
        JP NZ,SRTVBD                ; A one-page class cannot cross its page.
        JR SRTVOCHK
SRTV2PG:
        LD A,H
        OR L
        JP NZ,SRTVBD                ; The two-page class has one legal object start.
SRTVOCHK:
        LD HL,(SRTCLOBJ)            ; Read the length only after ownership is proven.
        LD A,(HL)
        LD (SRTVLENB),A
        CP 65
        JP NC,SRTVBD                ; The stored count must fit the supported class.
        LD L,A
        LD H,0
        ADD HL,HL                  ; Calculate count times four.
        ADD HL,HL
        INC HL                     ; Include the length byte in the used extent.
        LD DE,(SRTCLSZ)
        OR A
        SBC HL,DE
        JR C,SRTVGOOD               ; A smaller used extent fits the class block.
        JR Z,SRTVGOOD               ; An exact class-sized vector is also valid.
        JP SRTVBD                   ; A larger used extent is malformed.
SRTVGOOD:
        LD HL,(SRTCLOBJ)
        OR A
        RET
SRTVBD:
        SCF                         ; The candidate is not a live vector start.
        RET
