; Exact root discovery for stacks, packets, static slots and frames.
; Entry points: SRTROOTS, SRTNROOT, SRTRAW and SRTENRT.
; Included in runtime order by ../roots.asm.

; Exact root discovery for the scope-control runtime.
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
        CALL SRTDRRT               ; Reader values remain live during pair folding.
        CALL SRTENRT
        CALL SRTCEROT              ; Scan maps saved by active call/ec records.
        LD A,(SRTDRACC)
        OR A
        JR Z,SRTQAC                 ; No separate list accumulator is active.
        LD A,(SRTDATAG)
        LD HL,(SRTDAVAL)
        CALL SRTMVALU
SRTQAC:
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
        XOR A
        LD (HL),A                  ; The extension byte stays clear.
        INC HL
        LD A,(SRTNRTAG)
        OR SRTCLIVE                ; A live record and its tag.
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
        JR C,SRTNPOPX
        SUB B
        LD (SRTNCT),A
        POP HL
        POP AF
        OR A                       ; A remains intact while successful removal clears carry.
        RET
SRTNPOPX:
        JP SRTERROR

; Remove one generated operand record while preserving A:HL.
SRTNPOP1:
        LD B,1
        JP SRTNPOPB

; Mark the active reader value stack during a collection.
SRTDRRT:
        LD A,(SRTDRACT)             ; An inactive reader has no temporary roots.
        OR A
        RET Z
        LD HL,SRTDRVB               ; Reader values occupy four-byte records.
        LD DE,(SRTDRVP)             ; The live cursor bounds the root range.
        JP SRTRAW

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
; is the publication flag, so unused cache and static slots are ignored.
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
        INC HL
        LD A,(HL)
        AND SRTCLIVE
        RET Z
        LD A,(HL)
        AND 0FH
        LD (SRTROOTT),A
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
        INC HL
        LD A,(HL)
        AND 0FH
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
        PUSH BC
        CALL SRTSROOT             ; Active entries are four-byte inline/promoted slots.
        POP BC
        LD HL,(SRTENVP)
        LD DE,4
        ADD HL,DE
        LD (SRTENVP),HL
        LD A,(SRTENVN)
        DEC A
        LD (SRTENVN),A
        JR NZ,SRTENVLP
        RET
