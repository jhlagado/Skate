; Managed closure and binding storage for the Skate runtime.
;
; Compiler-owned static records remain four bytes.  Dynamic environment cells
; use three bytes: two payload bytes followed by packed tag, state and mark
; bits.  Closures use rounded four-byte size classes in typed 256-byte pages;
; bindings grow down from the pool ceiling and stop at the closure high-water
; mark.

; Load a three-byte heap binding addressed by HL.  Static compiler slots use
; SRTLOAD; this helper is selected only through an active environment map.
SRTBLOAD:
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        LD (SRTTAG),A
        AND 8
        JP Z,SRTUNBD
        LD A,(SRTTAG)
        AND 80H
        JR NZ,SRTBESCV
        LD A,(SRTTAG)
        AND 7
        EX DE,HL
        RET
SRTBESCV:
        LD A,8
        EX DE,HL
        RET

; Store a value in a three-byte heap binding and retain its capture and mark bits.
SRTBSTOR:
        LD (SRTTAG),A
        LD (SRTVAL),HL
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD A,(DE)
        AND 70H
        LD B,A
        LD A,(SRTTAG)
        CP 8
        JR Z,SRTBTESC
        AND 7
        OR 28H
        JR SRTBTAG
SRTBTESC:
        LD A,80H
        OR 28H
SRTBTAG:
        OR B
        LD (DE),A
        LD A,(SRTTAG)
        LD HL,(SRTVAL)
        RET

; Store through a three-byte heap binding only after its initialized bit is set.
SRTBSET:
        LD (SRTATMP),A
        LD (SRTVAL),HL
        LD (SRTCELLP),DE
        INC DE
        INC DE
        LD A,(DE)
        AND 8
        JP Z,SRTUNBD
        LD DE,(SRTCELLP)
        LD A,(SRTATMP)
        LD HL,(SRTVAL)
        JP SRTBSTOR

; Allocate a fresh closure object.  HL names its descriptor and the current
; environment supplies the shared cell pointers for a nested lambda.
SRTMAKE:
        LD (SRTNEWD),HL           ; Retain the immutable procedure descriptor.
        LD DE,3                   ; Descriptor byte three stores the slot count.
        ADD HL,DE                 ; Read the fixed environment extent.
        LD A,(HL)                 ; Every closure receives that bounded slot area.
        LD (SRTCSLOT),A           ; Preserve the count while sizing the object.
        LD (SRTCLN),A             ; The same count drives class selection and tracing.
        CALL SRTCLSIZ             ; Calculate pointer bytes, rounded size and class.
        CALL SRTCLALC             ; Reuse a dead object before growing the cursor.
        JR NC,SRTMKOK
        CALL SRTGC                ; A full closure pool may contain dead objects.
        LD A,(SRTCSLOT)           ; Collection may use the same sizing scratch.
        LD (SRTCLN),A             ; Restore the pending closure's slot count.
        CALL SRTCLSIZ              ; Recompute bytes and class after collection.
        CALL SRTCLALC
        JP C,SRTERROR             ; No class block remains after one collection.
SRTMKOK:
        LD (SRTOBJ),HL            ; Return this pointer after copying the frame.
        LD (SRTCELLP),HL          ; Clear the entire rounded block before publishing.
        LD BC,(SRTCLSZ)
        XOR A
SRTMKCLR:
        LD HL,(SRTCELLP)
        LD (HL),A
        INC HL
        LD (SRTCELLP),HL
        DEC BC
        LD A,B
        OR C
        JR NZ,SRTMKCLR
        CALL SRTCLNEW              ; Record the exact closure object boundary.
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
        JR Z,SRTMAKE0              ; Top-level closures receive cleared slots.
        LD BC,(SRTBYTES)           ; Copy complete logical slots, including tags.
        LD A,B                     ; A nullary closure has no map to copy.
        OR C
        JR Z,SRTMAKEM              ; Skip LDIR when its count is zero.
        LDIR                       ; Source and destination are nonoverlapping.
SRTMAKEM:
        CALL SRTMARKC              ; Captured cells must survive later tail calls.
        JR SRTMAKER                ; Return the object pointer and procedure tag.
SRTMAKE0:
        LD HL,(SRTNENV)            ; Clear the fresh environment when no parent exists.
        LD BC,(SRTBYTES)           ; BC is the bounded byte count.
        LD A,B                     ; A zero-sized map needs no clearing pass.
        OR C
        JR Z,SRTMAKER              ; Nullary closures return immediately.
        XOR A                      ; Uninitialized values start at zero bytes.
SRTMAK0L:
        XOR A                      ; Keep every cleared byte at zero.
        LD (HL),A                  ; Clear one value byte.
        INC HL                     ; Advance through the new environment.
        DEC BC                     ; Consume one byte from the bounded extent.
        LD A,B
        OR C
        JR NZ,SRTMAK0L             ; Stop exactly at the environment boundary.
SRTMAKER:
        LD HL,(SRTOBJ)             ; Return the closure object as the payload.
        LD A,2                     ; Tag two denotes a callable closure object.
        RET                        ; The generated prefix jumps over its body.

; Calculate the current closure's four-byte class and rounded allocation size.
SRTCLSIZ:
        LD A,(SRTCLN)
        LD L,A
        LD H,0
        ADD HL,HL                 ; Two bytes represent each shared cell pointer.
        LD (SRTBYTES),HL          ; Preserve the unrounded environment byte count.
        LD BC,2
        ADD HL,BC                 ; The descriptor pointer precedes the map.
        LD A,L
        AND 3
        JR Z,SRTCLSOK
        LD BC,4
        ADD HL,BC
        LD A,L
        AND 0FCH
        LD L,A
SRTCLSOK:
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
SRTCLALC:
        LD A,(SRTCLIDX)
        CP 40H
        JR NZ,SRTCLSM
        CALL SRTCLPRN              ; A 260-byte closure owns a two-page run.
        RET C
        LD (SRTCLBAS),HL
        CALL SRTCLINC
        LD HL,(SRTCLBAS)
        XOR A
        RET
SRTCLSM:
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
        JR Z,SRTCLBUP
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
        CALL SRTCLINC
        LD HL,(SRTCLBAS)
        XOR A
        RET
SRTCLBUP:
        CALL SRTCLPNW
        RET C
        JP SRTCLALC

; Allocate and clear one three-byte heap binding.
SRTCELL:
        CALL SRTBALC
        JR NC,SRTCELOK
        CALL SRTGC                  ; Reclaim dead bindings before reporting full.
        CALL SRTBALC
        JP C,SRTERROR
SRTCELOK:
        LD (SRTCELLP),HL
        CALL SRTBNEW                 ; Publish the exact binding start before stores.
        XOR A
        LD (HL),A                   ; Clear the payload low byte.
        INC HL
        LD (HL),A                   ; Clear the payload high byte.
        INC HL
        LD A,20H                    ; Allocation is distinct from initialization.
        LD (HL),A
        LD HL,(SRTCELLP)            ; Return the new cell address in HL.
        RET

; Pop a reclaimed binding or allocate the next three-byte slot in a page.
SRTBALC:
        LD HL,(SRTBHEAD)
        LD A,H
        OR L
        JR Z,SRTBPCUR
        LD (SRTCELLP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTBHEAD),DE
        LD HL,(SRTCELLP)
        XOR A
        RET
SRTBPCUR:
        LD HL,(SRTBPGP)
        LD A,H
        OR L
        JR Z,SRTBNEWP
        LD (SRTCELLP),HL
        LD DE,3
        ADD HL,DE
        LD DE,(SRTBPGED)
        OR A
        SBC HL,DE
        JR C,SRTBPVOK
        JR Z,SRTBPVOK
        JR SRTBNEWP
SRTBPVOK:
        LD HL,(SRTCELLP)
        LD DE,3
        ADD HL,DE
        LD (SRTBPGP),HL
        LD HL,(SRTCELLP)
        XOR A
        RET
SRTBNEWP:
        LD A,(SRTBPGN)
        CP 80H
        JR NC,SRTBAFL
        LD HL,1
        CALL SRTGPALL
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
        LD DE,3
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
SRTBAFL:
        SCF
        RET
