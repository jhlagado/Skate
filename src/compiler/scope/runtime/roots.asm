; Exact root discovery for the scope compiler runtime.
;
; Static value records are bounded by compiler-patched addresses.  Transient
; stacks and packets are bounded by live cursors, and environment maps carry
; explicit slot counts.  The tracer dispatches by the stored Scheme tag before
; interpreting a payload as a pair, closure or binding reference.

; Visit every declared root category.  Static ranges are compiler-patched;
; transient ranges use their active cursors, and frame maps use slot counts.
SRTROOTS:
        CALL SRTCRMK               ; Constructor inputs are roots at allocation.
        LD HL,(SRTGBASE)
        LD DE,(SRTGEND)
        CALL SRTROTRG
        LD HL,(SRTQROOT)
        LD DE,(SRTQENDR)
        CALL SRTROTRG
        CALL SRTPKRT
        CALL SRTNRRT               ; Generated operand records remain live until consumed.
        CALL SRTOPRT
        CALL SRTQRT
        CALL SRTENRT
        LD A,(SRTQACTV)
        OR A
        RET Z
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        JP SRTMVALU

; Record one generated operand in the exact shadow root stack.  A:HL is
; returned unchanged so SCPUSH can continue with the native stack operation.
SRTNROOT:
        LD (SRTNRTAG),A
        LD (SRTNRVAL),HL
        LD A,(SRTNCT)
        CP 255
        JP NC,SRTERROR
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTNRTAB
        ADD HL,DE
        LD DE,(SRTNRVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTNRTAG)
        LD (HL),A
        INC HL
        LD A,1
        LD (HL),A
        LD A,(SRTNCT)
        INC A
        LD (SRTNCT),A
        LD A,(SRTNRTAG)
        LD HL,(SRTNRVAL)
        RET

; Remove B most-recent generated operand records while preserving A:HL.
SRTNPOPB:
        PUSH AF
        PUSH HL
        LD A,(SRTNCT)
        CP B
        JP C,SRTERROR
        SUB B
        LD (SRTNCT),A
        POP HL
        POP AF
        RET

; Remove one generated operand record while preserving A:HL.
SRTNPOP1:
        LD B,1
        JP SRTNPOPB

; Scan the active generated-operand records.
SRTNRRT:
        LD A,(SRTNCT)
        OR A
        RET Z
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTNRTAB
        ADD HL,DE
        EX DE,HL
        LD HL,SRTNRTAB
        JP SRTRAW

; Walk a half-open range of four-byte static value records.  The final byte
; is the publication flag, so unused cache and global slots are ignored.
SRTROTRG:
        LD (SRTROOTP),HL
        LD (SRTROOTE),DE
SRTROLP:
        LD HL,(SRTROOTP)
        LD DE,(SRTROOTE)
        OR A
        SBC HL,DE
        RET NC
        LD HL,(SRTROOTP)
        CALL SRTROREC
        LD HL,(SRTROOTP)
        LD DE,4
        ADD HL,DE
        LD (SRTROOTP),HL
        JR SRTROLP

; Visit one published four-byte value record when its initialized bit is set.
SRTROREC:
        LD (SRTROOTV),HL
        INC HL
        INC HL
        LD A,(HL)
        LD (SRTROOTT),A
        INC HL
        LD A,(HL)
        AND 1
        RET Z
        LD A,(SRTROOTT)
        LD HL,(SRTROOTV)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP SRTMVALU

; Visit a transient four-byte value record.  The enclosing cursor, rather than
; its spare byte, determines whether this record is live.
SRTROWR:
        LD (SRTROOTV),HL
        INC HL
        INC HL
        LD A,(HL)
        LD (SRTROOTT),A
        LD A,(SRTROOTT)
        LD HL,(SRTROOTV)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP SRTMVALU

; Scan exactly the active argument packet entries.
SRTPKRT:
        LD A,(SRTARGC)
        OR A
        RET Z
        LD B,A
        LD HL,SRTARGPK
        LD (SRTROOTP),HL
SRTPKLP:
        LD HL,(SRTROOTP)
        PUSH BC
        CALL SRTROWR
        POP BC
        LD HL,(SRTROOTP)
        LD DE,4
        ADD HL,DE
        LD (SRTROOTP),HL
        DJNZ SRTPKLP
        RET

; Scan active operator-stack records up to the published cursor.
SRTOPRT:
        LD HL,SRTOPB
        LD DE,(SRTOPS)
        JP SRTRAW

; Scan active quoted-data records up to the published cursor.
SRTQRT:
        LD HL,SRTQBASE
        LD DE,(SRTQSP)
        JP SRTRAW

; Walk a half-open range of active four-byte records without reading a flag.
SRTRAW:
        LD (SRTROOTP),HL
        LD (SRTROOTE),DE
SRTRAWLP:
        LD HL,(SRTROOTP)
        LD DE,(SRTROOTE)
        OR A
        SBC HL,DE
        RET NC
        LD HL,(SRTROOTP)
        PUSH HL
        CALL SRTROWR
        POP HL
        LD DE,4
        ADD HL,DE
        LD (SRTROOTP),HL
        JR SRTRAWLP

; Scan current and suspended environment maps.  Each entry is a binding
; pointer.  A frame is always ten bytes below its map.  Its caller descriptor
; is paired with the caller map saved in the same frame.
SRTENRT:
        LD HL,(SRTENV)
        LD A,(SRTSLOTS)
        CALL SRTENVM
        LD HL,(SRTFRAME)
        LD (SRTROOTP),HL
        LD DE,(SRTENV)
        OR A
        SBC HL,DE
        JR Z,SRTENCOM
        LD HL,(SRTCENV)
        LD A,(SRTCENVN)
        CALL SRTENVM
        LD HL,(SRTFRAME)
SRTENCOM:
        LD HL,(SRTROOTP)
        LD A,H
        OR L
        JR Z,SRTENPAR
SRTFRMLP:
        LD HL,(SRTROOTP)
        LD DE,8
        OR A
        SBC HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTFRMD),DE
        LD HL,(SRTROOTP)
        LD DE,10
        OR A
        SBC HL,DE
        LD DE,4
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTROOTP),DE
        LD HL,(SRTROOTP)
        LD A,H
        OR L
        RET Z
        LD HL,(SRTFRMD)
        LD A,H
        OR L
        JR Z,SRTENPAR
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD HL,(SRTROOTP)
        CALL SRTENVM
        LD HL,(SRTROOTP)
        JR SRTFRMLP
SRTENPAR:
        LD HL,(SRTCENV)
        LD A,(SRTCENVN)
        JP SRTENVM

SRTENVM:
        OR A
        RET Z
        LD (SRTENVP),HL
        LD (SRTENVN),A
SRTENVLP:
        LD HL,(SRTENVP)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (SRTENVP),HL
        EX DE,HL
        PUSH BC
        CALL SRTBMARK
        POP BC
        LD A,(SRTENVN)
        DEC A
        LD (SRTENVN),A
        JR NZ,SRTENVLP
        RET

; Trace a binding cell reached from an active environment or closure.  Its
; explicit mark bit prevents closure/binding cycles from recursing forever.
SRTBMARK:
        LD A,H
        OR L
        RET Z
        LD (SRTBADDR),HL
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        JR C,SRTBFAIL
        LD HL,(SRTBADDR)
        LD DE,3
        ADD HL,DE
        JR C,SRTBFAIL              ; A wrapped binding extent is invalid.
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,SRTBOK
        JR Z,SRTBOK
        JR SRTBFAIL
SRTBOK:
        CALL SRTBSTA
        JR Z,SRTBFAIL
        LD HL,(SRTBADDR)
        LD DE,2
        ADD HL,DE
        LD A,(HL)
        LD (SRTBFLG),A
        AND 20H
        RET Z
        LD A,(SRTBFLG)
        AND 40H
        JR NZ,SRTBMDON
        LD A,(SRTBFLG)
        OR 40H
        LD (HL),A
        LD A,(SRTBFLG)
        AND 8
        RET Z
        LD HL,(SRTBADDR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        AND 7
        EX DE,HL
        JP SRTMVALU
SRTBMDON:
        RET
SRTBFAIL:
        RET

; Trace a tagged managed value.  Pair validation and closure validation remain
; separate so a binding's full value is never decoded as a pair record.
SRTMVALU:
        CP 1
        JP Z,SRTMARK
        CP 2
        JP Z,SRTCLENQ
        RET

; Return carry clear only for an allocated closure start with a complete
; descriptor and environment extent.  The start bitmap rejects pointers into
; an object's payload or into a binding cell that happens to look similar.
SRTCLVLD:
        LD HL,(SRTCLOBJ)
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        JR C,SRTCLBAD
        LD HL,(SRTCLOBJ)
        BIT 0,L
        JR NZ,SRTCLBAD
        LD DE,2
        ADD HL,DE
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,SRTCLHDR
        JR Z,SRTCLHDR
        JR SRTCLBAD
SRTCLHDR:
        LD HL,(SRTCLOBJ)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTCLDSC),DE
        LD HL,(SRTCLDSC)
        LD DE,0100H
        OR A
        SBC HL,DE
        JR C,SRTCLBAD
        LD HL,(SRTCLDSC)
        LD DE,SRTCAPOF+SRTMASKB
        ADD HL,DE
        JR C,SRTCLBAD              ; The descriptor extent must fit in 16 bits.
        LD DE,(SRTIMGE)
        OR A
        SBC HL,DE
        JR C,SRTCLDM
        JR Z,SRTCLDM
        JR SRTCLBAD
SRTCLDM:
        LD HL,(SRTCLDSC)
        LD DE,3
        ADD HL,DE
        LD A,(HL)
        LD (SRTCLN),A
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,2
        ADD HL,DE
        LD DE,(SRTCLOBJ)
        ADD HL,DE
        JR C,SRTCLBAD              ; A wrapped closure extent is invalid.
        LD DE,(SRTHEAPP)
        OR A
        SBC HL,DE
        JR C,SRTCLGOD
        JR Z,SRTCLGOD
SRTCLBAD:
        SCF
        RET
SRTCLGOD:
        CALL SRTCLSTA
        JR Z,SRTCLBAD
        OR A
        RET

; Compute the byte index and single-bit mask for an even closure address.
; The address is measured in two-byte units from SRTHEAP.
SRTCLPOS:
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        SRL H
        RR L
        LD A,L
        AND 7
        LD C,A
        SRL H
        RR L
        SRL H
        RR L
        SRL H
        RR L
        LD A,C
        OR A
        JR Z,SRTCLPZ
        LD A,1
SRTCLPS:
        ADD A,A
        DEC C
        RET Z
        JR SRTCLPS
SRTCLPZ:
        LD A,1
        RET

; Test whether SRTCLOBJ is a recorded closure allocation start.
SRTCLSTA:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Test whether SRTCLOBJ has already entered this collection's worklist.
SRTCLSEE:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,(HL)
        AND C
        RET

; Set the current collection's closure mark bit.
SRTCLSET:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,(HL)
        OR C
        LD (HL),A
        LD A,1
        LD (SRTMNEW),A             ; Fallback passes must revisit new closures.
        RET

; Publish a newly allocated closure start for later exact validation.
SRTCLNEW:
        LD HL,(SRTOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,(HL)
        OR C
        LD (HL),A
        RET

; Clear all closure marks at the beginning of a collection.
SRTCLCLR:
        LD HL,SRTCLMK
        LD DE,SRTCLMK+1
        LD BC,08FFH
        XOR A
        LD (HL),A
        LDIR
        XOR A
        LD (SRTCLER),A
        RET

; Queue a validated closure without entering its capture graph recursively.
SRTCLENQ:
        LD (SRTCLOBJ),HL
        CALL SRTCLVLD
        RET C
        CALL SRTCLSEE
        RET NZ
        CALL SRTCLSET
        LD DE,(SRTMSTK)
        LD A,D
        CP 0D4H
        JR NC,SRTCLFUL
        LD HL,(SRTCLOBJ)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (SRTMSTK),DE
        RET
SRTCLFUL:
        LD A,1
        LD (SRTMOVER),A            ; The closure scan will trace this marked object.
        LD (SRTCLER),A             ; Retain the diagnostic overflow indication.
        RET

; Trace one queued closure through the descriptor capture mask.  Every
; capture is only read after the descriptor has bounded the declared slots.
SRTMCLOS:
        CALL SRTCLVLD
        RET C
        LD HL,(SRTCLDSC)
        LD DE,SRTCAPOF
        ADD HL,DE
        LD (SRTCLMP),HL
        XOR A
        LD (SRTCLSLT),A
        LD B,SRTMASKB
SRTCLMSK:
        LD HL,(SRTCLMP)
        LD A,(HL)
        INC HL
        LD (SRTCLMP),HL
        LD (SRTCLMV),A
        LD C,8
SRTCLBIT:
        LD A,(SRTCLMV)
        AND 1
        JR Z,SRTCLNX
        LD A,(SRTCLN)
        LD E,A
        LD A,(SRTCLSLT)
        CP E
        JR NC,SRTCLNX
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,2
        ADD HL,DE
        LD DE,(SRTCLOBJ)
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (SRTCLPTR),HL
        PUSH BC
        LD HL,(SRTCLMP)
        PUSH HL
        LD HL,(SRTCLOBJ)
        PUSH HL
        LD HL,(SRTCLDSC)
        PUSH HL
        LD A,(SRTCLN)
        PUSH AF
        LD A,(SRTCLSLT)
        PUSH AF
        LD A,(SRTCLMV)
        PUSH AF
        LD HL,(SRTCLPTR)
        CALL SRTBMARK
        POP AF
        LD (SRTCLMV),A
        POP AF
        LD (SRTCLSLT),A
        POP AF
        LD (SRTCLN),A
        POP HL
        LD (SRTCLDSC),HL
        POP HL
        LD (SRTCLOBJ),HL
        POP HL
        LD (SRTCLMP),HL
        POP BC
SRTCLNX:
        LD A,(SRTCLMV)
        SRL A
        LD (SRTCLMV),A
        LD A,(SRTCLSLT)
        INC A
        LD (SRTCLSLT),A
        DEC C
        JR NZ,SRTCLBIT
        DJNZ SRTCLMSK
        RET

; Trace every marked closure after a bounded queue overflow.  The start and
; mark maps make this a finite pass over the two-byte address units in the
; closure extent.  Repeating the pass reaches captures discovered later in
; the scan without recursing through the native stack.
SRTCLSCR:
        LD HL,(SRTHEAPP)           ; Scan only the configured managed address span.
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        SRL H
        RR L
        LD B,H                     ; Each visit tests one even closure address.
        LD C,L
        LD HL,SRTHEAP
        LD (SRTCLSCN),HL
SRTCSLP:
        LD HL,(SRTCLSCN)
        LD (SRTCLOBJ),HL
        PUSH BC
        CALL SRTCLSTA
        JR Z,SRTCPOP
        CALL SRTCLSEE
        JR Z,SRTCPOP
        CALL SRTMCLOS
SRTCPOP:
        POP BC
        LD HL,(SRTCLSCN)
        INC HL
        INC HL
        LD (SRTCLSCN),HL
        DEC BC
        LD A,B
        OR C
        JP NZ,SRTCSLP
        RET

; Convert a binding byte address to its bitmap byte and bit mask.
SRTBPOS:
        LD HL,(SRTBADDR)
        LD DE,SRTHEAP
        OR A
        SBC HL,DE
        JR C,SRTBPF
        LD A,H
        CP 90H
        JR NC,SRTBPF
        LD A,L
        AND 7
        LD C,A
        LD A,C
        OR A
        JR Z,SRTBPSZ
        LD A,1
SRTBPSH:
        ADD A,A
        DEC C
        JR NZ,SRTBPSH
        JR SRTBPSD
SRTBPSZ:
        LD A,1
SRTBPSD:
        LD C,A
        SRL H
        RR L
        SRL H
        RR L
        SRL H
        RR L
        LD DE,SRTBMB
        ADD HL,DE
        OR A
        RET
SRTBPF:
        XOR A
        SCF
        RET

; Return nonzero only when SRTBADDR is a recorded binding allocation start.
SRTBSTA:
        CALL SRTBPOS
        RET C
        LD A,(HL)
        AND C
        RET

; Record the binding start most recently allocated by SRTCELL.
SRTBNEW:
        LD HL,(SRTCELLP)
        LD (SRTBADDR),HL
        CALL SRTBPOS
        RET C
        LD A,(HL)
        OR C
        LD (HL),A
        LD HL,(SRTCELLP)
        RET

; Clear one allocation-start bit in the closure-start map.
SRTCLCLB:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLBM
        ADD HL,DE
        LD A,C
        CPL
        LD B,A
        LD A,(HL)
        AND B
        LD (HL),A
        RET

; Clear one queued-mark bit in the closure mark map.
SRTCLCLM:
        LD HL,(SRTCLOBJ)
        CALL SRTCLPOS
        LD C,A
        LD DE,SRTCLMK
        ADD HL,DE
        LD A,C
        CPL
        LD B,A
        LD A,(HL)
        AND B
        LD (HL),A
        RET

; Sweep the three-byte binding pages.  A live page remains owned by the page
; manager; dead cells form a page-local free list before it is joined to the
; global list.  An empty page is returned immediately, so no stale free-list
; address can survive the page release.
SRTBSW:
        LD HL,0
        LD (SRTBHEAD),HL
        LD HL,(SRTBPGBA)
        LD (SRTBPGC),HL             ; Save the current page across the scan.
        XOR A
        LD (SRTBPGI),A
SRTBPGLO:
        LD A,(SRTBPGI)
        LD D,A
        LD A,(SRTBPGN)
        CP D
        JP C,SRTBPGDN
        JP Z,SRTBPGDN
        LD A,D
        LD L,A
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        LD A,(HL)
        LD H,A
        LD L,0
        LD (SRTBPGBA),HL
        LD (SRTBSCAN),HL
        LD HL,0
        LD (SRTBPFRE),HL
        LD (SRTBPLST),HL
        XOR A
        LD (SRTBPLIV),A
        LD A,85
        LD (SRTCLPGQ),A
SRTBPGSL:
        LD A,(SRTCLPGQ)
        OR A
        JP Z,SRTBPGST
        LD HL,(SRTBSCAN)
        LD (SRTBADDR),HL
        CALL SRTBPOS
        JR C,SRTBPGNX
        LD (SRTBMAP),HL
        LD A,C
        LD (SRTBMSK),A
        LD A,(HL)
        AND C
        JR Z,SRTBPGFR               ; A clear bitmap bit is never a live cell.
        LD HL,(SRTBADDR)
        INC HL
        INC HL
        LD A,(HL)
        LD (SRTBFLG),A
        LD A,(SRTBFLG)
        AND 40H
        JR NZ,SRTBPGLV
SRTBPGFR:
        ; Every unmarked cell is reusable.  This includes cells reclaimed by
        ; an earlier collection and virgin slots that were never allocated.
        ; A cell is live only when both its allocation bit and mark bit are
        ; set; this prevents stale payload bytes in virgin slots from pinning
        ; a page.
        LD HL,(SRTBADDR)
        LD DE,(SRTBPFRE)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(SRTBPFRE)
        LD A,H
        OR L
        JR NZ,SRTBPGHD
        LD HL,(SRTBADDR)
        LD (SRTBPLST),HL
SRTBPGHD:
        LD HL,(SRTBADDR)
        LD (SRTBPFRE),HL
        INC HL
        INC HL
        XOR A
        LD (HL),A                  ; A reclaimed cell is no longer allocated.
        JR SRTBPGCL
SRTBPGLV:
        LD HL,(SRTBMAP)
        LD A,(HL)
        OR C
        LD (HL),A                  ; Restore the allocation bit for a live cell.
        LD HL,(SRTBADDR)
        INC HL
        INC HL
        LD A,(HL)
        AND 0BFH
        LD (HL),A                  ; Surviving cells lose only their mark bit.
        LD A,(SRTBPLIV)
        INC A
        LD (SRTBPLIV),A
        JR SRTBPGNX
SRTBPGCL:
        LD HL,(SRTBMAP)
        LD A,(SRTBMSK)
        CPL
        LD D,A
        LD A,(HL)
        AND D
        LD (HL),A
SRTBPGNX:
        LD HL,(SRTBSCAN)
        LD DE,3
        ADD HL,DE
        LD (SRTBSCAN),HL
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JP SRTBPGSL
SRTBPGST:
        LD A,(SRTBPLIV)
        OR A
        JR NZ,SRTBPGLP
        LD HL,(SRTBPGBA)
        LD DE,1
        CALL SRTGPREL
        JR C,SRTBPGLP             ; Keep the descriptor if release was rejected.
        LD A,(SRTBPGN)
        DEC A
        LD (SRTBPGN),A
        LD D,A
        LD A,(SRTBPGI)
        CP D
        JP NC,SRTBPGLO             ; The removed page was the final entry.
        LD L,D
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        LD A,(HL)
        PUSH AF
        LD A,(SRTBPGI)
        LD L,A
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        POP AF
        LD (HL),A                  ; Fill the hole with the former last entry.
        JP SRTBPGLO
SRTBPGLP:
        LD HL,(SRTBPFRE)
        LD A,H
        OR L
        JR Z,SRTBPGIN
        LD DE,(SRTBHEAD)
        LD HL,(SRTBPLST)
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,(SRTBPFRE)
        LD (SRTBHEAD),HL
SRTBPGIN:
        LD A,(SRTBPGI)
        INC A
        LD (SRTBPGI),A
        JP SRTBPGLO
SRTBPGDN:
        LD HL,(SRTBPGC)
        LD A,H
        OR L
        JR Z,SRTBPGZE
        LD A,(SRTBPGN)
        LD (SRTCLPGQ),A
        XOR A
        LD (SRTBPGI),A
SRTBPGCK:
        LD A,(SRTCLPGQ)
        OR A
        JR Z,SRTBPGZE
        LD A,(SRTBPGI)
        LD L,A
        LD H,0
        LD DE,SRTBPGS
        ADD HL,DE
        LD A,(HL)
        LD D,A
        LD HL,(SRTBPGC)
        LD A,H
        CP D
        JR Z,SRTBPGOK
        LD A,(SRTBPGI)
        INC A
        LD (SRTBPGI),A
        LD A,(SRTCLPGQ)
        DEC A
        LD (SRTCLPGQ),A
        JR SRTBPGCK
SRTBPGOK:
        LD HL,(SRTBPGC)
        LD (SRTBPGBA),HL
        LD HL,(SRTBPGED)
        LD (SRTBPGP),HL            ; All slots are on the rebuilt free chain.
        LD (SRTBEND),HL
        RET
SRTBPGZE:
        LD HL,0
        LD (SRTBPGBA),HL
        LD (SRTBPGP),HL
        LD (SRTBPGED),HL
        LD (SRTBEND),HL
        RET
