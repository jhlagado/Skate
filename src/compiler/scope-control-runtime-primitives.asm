; Predefined arithmetic procedure values for the scope-control runtime.
;
; Primitive values use tag zero and payloads FE20H through FE23H.  The
; dispatcher validates packet arity, pushes values in the numeric ABI order,
; and returns through the continuation supplied in IX.

; Pack arguments, then recover the operator value saved before evaluation.
SRTPACKO:
        POP IX                   ; Save the SRTPACKO helper return address.
        LD B,A                   ; B counts values still on the native stack.
        LD C,A                   ; C is the packet index, starting at count-1.
        LD A,B                   ; A supplies the zero-count test below.
        OR A
        JP Z,SRTPKGZ             ; A nullary call skips directly to the side pop.
        DEC C
SRTPKGL:
        POP HL                   ; Recover one reverse-pushed argument payload.
        POP AF                   ; Recover its tag word.
        LD (SRTATMP),A           ; Preserve the tag while addressing the packet.
        LD (SRTVAL),HL           ; Preserve the payload while multiplying the index.
        LD L,C
        LD H,0
        ADD HL,HL
        ADD HL,HL
        LD DE,SRTARGPK
        ADD HL,DE
        LD DE,(SRTVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTATMP)
        LD (HL),A
        INC HL
        LD A,1
        LD (HL),A
        DEC C
        DJNZ SRTPKGL
SRTPKGZ:
        CALL SRTOPPOP            ; Recover the value evaluated before arguments.
        PUSH IX                  ; Restore the SRTPACKO helper return address.
        RET

; Save A:HL on the fixed side stack used for operator values. The area between
; the heap ceiling and native-stack guard does not consume either resource.
SRTOPUSH:
        LD (SRTATMP),A           ; Preserve the value tag while finding the top.
        LD (SRTVAL),HL           ; Preserve the payload across the bounds check.
        LD HL,(SRTOPS)           ; The side cursor grows upward in four-byte steps.
        LD DE,4
        ADD HL,DE
        LD DE,SRTOPEND
        OR A
        SBC HL,DE
        JP NC,SRTERROR            ; Too many nested operators is a runtime error.
        LD (SRTNEXT),HL           ; Retain the checked new cursor.
        LD HL,(SRTOPS)
        LD DE,(SRTVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTATMP)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A                 ; The fourth byte keeps the record fixed-width.
        INC HL
        LD (SRTOPS),HL
        RET

; Pop the most recent operator value from the fixed side stack.
SRTOPPOP:
        LD HL,(SRTOPS)
        LD DE,SRTOPB
        OR A
        SBC HL,DE
        JP Z,SRTERROR             ; A missing operator is a malformed call.
        LD HL,(SRTOPS)
        LD DE,4
        OR A
        SBC HL,DE
        LD (SRTOPS),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; Dispatch a predefined primitive through the checked numeric ABI as either a
; normal application continuation or the current procedure epilogue. Packet
; values are read directly so a primitive call adds no argument stack frame.
SRTPRIM:
        LD A,(SRTPID)              ; Kinds zero through three are numeric primitives.
        CP 4
        JP C,SRTPNUM               ; +, -, *, and zero? share numeric validation.
        CP 14
        JP C,SRTDAT                ; Existing pair, list and output services.
        CP 16
        JP C,SRTPQRM               ; quotient and remainder are integer-only.
        CP 21
        JP C,SRTCMP                ; Five numeric comparisons accept two or more.
        JP Z,SRTNOT                 ; not is the first unary logical predicate.
        CP 29
        JP C,SRTTYPE                ; Type predicates occupy the remaining IDs.
        JP SRTERROR                ; The reserved range has no other services.

; Validate one logical numeric value. Tag three is exact integer; tag zero is
; binary16 except for the reserved booleans, sentinels and primitive values.
SRTNCHK:
        LD (SRTNTAG),A
        CP 3
        JR Z,SRTNOK
        OR A
        JR NZ,SRTNFAIL
        LD (SRTNVAL),HL
        LD A,H
        OR L
        JR Z,SRTNFAIL
        LD HL,(SRTNVAL)
        LD DE,1
        OR A
        SBC HL,DE
        JR Z,SRTNFAIL
        LD HL,(SRTNVAL)
        LD A,H
        CP 0FEH
        JR NZ,SRTNF16
        LD A,L
        CP 2
        JR C,SRTNFAIL
        CP 5
        JR C,SRTNFAIL
        CP 20H
        JR C,SRTNF16
        CP 3DH
        JR C,SRTNFAIL
SRTNF16:
        LD HL,(SRTNVAL)
        LD A,H
        CP 0FFH
        JR Z,SRTNFAIL             ; FFxx is the reserved byte-character range.
        LD A,(SRTNTAG)
        CALL NCLASS
        RET
SRTNOK:
        OR A
        RET
SRTNFAIL:
        SCF
        RET

; Validate every packet value before folding any result.  This preserves the
; language rule that a later type error is not hidden by an earlier overflow.
SRTNVALL:
        LD A,(SRTARGC)              ; Walk exactly the values in the packet.
        LD (SRTNLEFT),A             ; The counter is independent of packet contents.
        OR A
        JR Z,SRTNVRET                ; Empty + and * calls have no values to check.
        LD HL,SRTARGPK              ; Begin at the first four-byte value record.
SRTNVLP:
        LD E,(HL)                   ; Recover the payload low byte.
        INC HL
        LD D,(HL)                   ; Recover the payload high byte.
        INC HL
        LD A,(HL)                   ; Recover the logical value tag.
        INC HL
        INC HL                      ; Skip the record flag before preserving the next address.
        PUSH HL                     ; Preserve the next packet address.
        EX DE,HL                    ; NCLASS receives the payload in HL.
        CALL SRTNCHK                ; Accept exact integers and valid numeric scalars.
        POP HL                      ; Restore the packet cursor after classification.
        JP C,SRTERROR               ; Every arithmetic argument must be a number.
        LD A,(SRTNLEFT)
        DEC A
        LD (SRTNLEFT),A
        JR NZ,SRTNVLP
SRTNVRET:
        RET

; Fold +, -, and * with the exact identities and one-argument subtraction.
SRTPNUM:
        CALL SRTNVALL               ; Validate the whole packet before arithmetic.
        LD A,(SRTPID)
        CP 3
        JP Z,SRTPZERO               ; Kind three is the unary zero? predicate.
        CP 0
        JR Z,SRTPADDV
        CP 1
        JR Z,SRPTSUBV
        JR SRPTMULV
SRTPADDV:
        LD A,3                      ; Exact integer zero is the empty-sum identity.
        LD (SRTNACCT),A
        XOR A
        LD H,A
        LD L,A
        JR SRTPFOLD
SRPTMULV:
        LD A,3                      ; Exact integer one is the empty-product identity.
        LD (SRTNACCT),A
        LD HL,1
        JR SRTPFOLD
SRPTSUBV:
        LD A,(SRTARGC)
        OR A
        JP Z,SRTERROR               ; Subtraction requires at least one operand.
        CP 1
        JR NZ,SRTPFOLD              ; Two or more operands use left subtraction.
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL NNEG                   ; Unary subtraction is checked negation.
        JP C,SRTERROR
        PUSH IX
        RET
SRTPFOLD:
        LD (SRTNACCV),HL            ; Keep the current folded payload.
        LD A,(SRTARGC)
        OR A
        JR Z,SRTPFRET               ; + and * return their identities at arity zero.
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTNACCV),HL            ; First argument replaces the identity.
        LD (SRTNACCT),A
        LD A,(SRTARGC)
        DEC A
        LD (SRTNLEFT),A
        LD HL,SRTARGPK+4
        LD (SRTNPTR),HL
SRTPFLP:
        LD A,(SRTNLEFT)
        OR A
        JR Z,SRTPFRET
        LD HL,(SRTNPTR)
        CALL SRTPVAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD HL,(SRTNACCV)
        LD DE,(SRTNVAL)
        LD A,(SRTNTAG)
        LD B,A
        LD A,(SRTPID)
        LD C,A
        LD A,C
        OR A
        JR Z,SRTPFADD
        CP 1
        JR Z,SRTPFSUB
        LD A,(SRTNACCT)
        CALL NMUL
        JR SRTPFCHK
SRTPFADD:
        LD A,(SRTNACCT)
        CALL NADD
        JR SRTPFCHK
SRTPFSUB:
        LD A,(SRTNACCT)
        CALL NSUB
SRTPFCHK:
        JP C,SRTERROR
        LD (SRTNACCV),HL
        LD (SRTNACCT),A
        LD HL,(SRTNPTR)
        LD DE,4
        ADD HL,DE
        LD (SRTNPTR),HL
        LD A,(SRTNLEFT)
        DEC A
        LD (SRTNLEFT),A
        JR SRTPFLP
SRTPFRET:
        LD A,(SRTNACCT)
        LD HL,(SRTNACCV)
        PUSH IX
        RET

; zero? remains a checked unary exact-integer predicate.
SRTPZERO:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        PUSH IX
        JP SRTZERO

; quotient and remainder require exactly two exact-integer arguments.
SRTPQRM:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTNACCV),HL
        LD (SRTNACCT),A
        LD HL,SRTARGPK+4
        CALL SRTPVAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD A,(SRTNTAG)
        LD B,A
        LD HL,(SRTNACCV)
        LD DE,(SRTNVAL)
        LD A,(SRTPID)
        LD C,A
        LD A,C
        CP 14
        JR Z,SRTPQUOT
        LD A,(SRTNACCT)
        CALL NREM
        JR SRTPQRCK
SRTPQUOT:
        LD A,(SRTNACCT)
        CALL NQUOT
SRTPQRCK:
        JP C,SRTERROR
        PUSH IX
        RET

; Compare each adjacent numeric pair after validating the complete packet.
SRTCMP:
        LD A,(SRTARGC)
        CP 2
        JP C,SRTERROR
        CALL SRTNVALL
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTNACCV),HL
        LD (SRTNACCT),A
        LD A,(SRTARGC)
        DEC A
        LD (SRTNLEFT),A
        LD HL,SRTARGPK+4
        LD (SRTNPTR),HL
SRTCLOOP:
        LD A,(SRTNLEFT)
        OR A
        JP Z,SRTBYES
        LD HL,(SRTNPTR)
        CALL SRTPVAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD HL,(SRTNACCV)
        LD DE,(SRTNVAL)
        LD A,(SRTNTAG)
        LD B,A
        LD A,(SRTNACCT)
        CALL NCMP
        JP C,SRTERROR
        LD (SRTCCOD),HL
        CALL SRTCONE
        OR A
        JP Z,SRTBNO
        LD HL,(SRTNVAL)
        LD (SRTNACCV),HL
        LD A,(SRTNTAG)
        LD (SRTNACCT),A
        LD HL,(SRTNPTR)
        LD DE,4
        ADD HL,DE
        LD (SRTNPTR),HL
        LD A,(SRTNLEFT)
        DEC A
        LD (SRTNLEFT),A
        JR SRTCLOOP

; Turn NCMP's -1, 0, +1 and unordered codes into the selected relation.
SRTCONE:
        LD A,(SRTCCOD+1)
        OR A
        JR NZ,SRTCNNEG
        LD A,(SRTCCOD)
        OR A
        JR Z,SRTCNZER
        CP 1
        JR Z,SRTCNPOS
        XOR A                      ; Unordered comparisons are always false.
        RET
SRTCNNEG:
        CP 0FFH
        JR NZ,SRTCNBAD
        LD A,(SRTCCOD)
        CP 0FFH
        JR NZ,SRTCNBAD
        LD A,(SRTPID)
        CP 17                       ; < accepts the negative code.
        JR Z,SRTCYES
        CP 19                       ; <= also accepts the negative code.
        JR Z,SRTCYES
        JR SRTCNO
SRTCNZER:
        LD A,(SRTPID)
        CP 16                       ; = accepts equality.
        JR Z,SRTCYES
        CP 19                       ; <= and >= accept equality.
        JR Z,SRTCYES
        CP 20
        JR Z,SRTCYES
        JR SRTCNO
SRTCNPOS:
        LD A,(SRTPID)
        CP 18                       ; > accepts a positive code.
        JR Z,SRTCYES
        CP 20                       ; >= accepts a positive code.
        JR Z,SRTCYES
        JR SRTCNO
SRTCNBAD:
        XOR A
        RET
SRTCYES:
        LD A,1
        RET
SRTCNO:
        XOR A
        RET

; not and the type predicates return canonical boolean values.
SRTNOT:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        CALL SRTFALSE
        JP Z,SRTBYES
        JP SRTBNO
SRTTYPE:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTNVAL),HL
        LD (SRTNTAG),A
        LD A,(SRTPID)
        CP 22
        JP Z,SRTTNUM
        CP 23
        JP Z,SRTTBOOL
        CP 24
        JP Z,SRTTSYM
        CP 25
        JP Z,SRTTPRO
        CP 26
        JP Z,SRTTSTR
        CP 27
        JP Z,SRTTCHAR
        JP SRTTEOF
SRTTNUM:
        LD A,(SRTNTAG)
        LD HL,(SRTNVAL)
        CALL SRTNCHK
        JP C,SRTBNO
        JP SRTBYES
SRTTBOOL:
        LD A,(SRTNTAG)
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD DE,0
        OR A
        SBC HL,DE
        JP Z,SRTBYES
        LD HL,(SRTNVAL)
        LD DE,1
        OR A
        SBC HL,DE
        JP Z,SRTBYES
        JP SRTBNO
SRTTSYM:
        LD A,(SRTNTAG)
        CP 4
        JP Z,SRTBYES
        JP SRTBNO
SRTTPRO:
        LD A,(SRTNTAG)
        CP 2
        JP Z,SRTBYES
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD A,H
        CP 0FEH
        JP NZ,SRTBNO
        LD A,L
        CP 20H
        JP C,SRTBNO
        CP 3DH
        JP C,SRTBYES
        JP SRTBNO
SRTTSTR:
        LD A,(SRTNTAG)
        CP 5
        JP Z,SRTBYES
        JP SRTBNO
SRTTCHAR:
        LD A,(SRTNTAG)
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD A,H
        CP 0FFH
        JP Z,SRTBYES
        JP SRTBNO
SRTTEOF:
        LD A,(SRTNTAG)
        OR A
        JP NZ,SRTBNO
        LD HL,(SRTNVAL)
        LD DE,0FE03H
        OR A
        SBC HL,DE
        JP NZ,SRTBNO
SRTBYES:
        LD A,1
SRTPBRES:
        OR A
        JR Z,SRTBZERO
        XOR A
        LD HL,1
        PUSH IX
        RET
SRTBZERO:
        XOR A
        LD HL,0
        PUSH IX
        RET
SRTBNO:
        XOR A
        JR SRTPBRES

; Dispatch the data and output primitives introduced by the C4 value model.
SRTDAT:
        LD A,(SRTPID)
        CP 4
        JP Z,SRTPCONS
        CP 5
        JP Z,SRTPCAR
        CP 6
        JP Z,SRTPCDR
        CP 7
        JP Z,SRTPPAR
        CP 8
        JP Z,SRTNPRED
        CP 9
        JP Z,SRTLIST
        CP 10
        JP Z,SRTPEQ
        CP 11
        JP Z,SRTWRITE
        CP 12
        JP Z,SRTDSPP
        CP 13
        JP Z,SRTNWL
        JP SRTERROR

; Read one packet argument and leave its value in A:HL.
SRTONE:
        LD A,(SRTARGC)
        CP 1
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        JP SRTPVAL

; Build one pair from the two packet values.
SRTPCONS:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD HL,SRTARGPK+4
        CALL SRTPVAL
        LD (SRTQCDR),HL
        LD (SRTQDTAG),A
        CALL SRTMAKEP
        PUSH IX
        RET

; Apply a selector to the one packet argument.
SRTPCAR:
        CALL SRTONE
        CALL SRTCARV
        JP C,SRTERROR
        PUSH IX
        RET
SRTPCDR:
        CALL SRTONE
        CALL SRTCDRV
        JP C,SRTERROR
        PUSH IX
        RET

; pair? returns false for every non-pair value.
SRTPPAR:
        CALL SRTONE
        CALL SRTPCHK
        JP C,SRTFPALS
        XOR A
        LD HL,1
        PUSH IX
        RET

; null? recognises the canonical empty-list value and nothing else.
SRTNPRED:
        CALL SRTONE
        OR A
        JP NZ,SRTFPALS
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JP NZ,SRTFPALS
        XOR A
        LD HL,1
        PUSH IX
        RET

; list consumes the bounded packet in source order and folds it into pairs.
SRTLIST:
        LD A,(SRTARGC)
        CP 8
        JP NC,SRTERROR
        LD (SRTLCN),A
        LD HL,SRTARGPK
        LD (SRTLCP),HL
SRTLLP:
        LD A,(SRTLCN)
        OR A
        JR Z,SRTLDONE
        LD HL,(SRTLCP)
        CALL SRTPVAL
        CALL SRTQPUT
        LD HL,(SRTLCP)
        LD DE,4
        ADD HL,DE
        LD (SRTLCP),HL
        LD A,(SRTLCN)
        DEC A
        LD (SRTLCN),A
        JR SRTLLP
SRTLDONE:
        LD A,(SRTARGC)
        LD B,0
        CALL SRTQBLD
        PUSH IX
        RET

; eq? compares both logical tags and payloads.
SRTPEQ:
        LD A,(SRTARGC)
        CP 2
        JP NZ,SRTERROR
        LD HL,SRTARGPK
        CALL SRTPVAL
        LD (SRTQCAR),HL
        LD (SRTQCTAG),A
        LD HL,SRTARGPK+4
        CALL SRTPVAL
        LD (SRTQCDR),HL
        LD (SRTQDTAG),A
        LD A,(SRTQCTAG)
        LD B,A
        LD A,(SRTQDTAG)
        CP B
        JP NZ,SRTFPALS
        LD HL,(SRTQCAR)
        LD DE,(SRTQCDR)
        OR A
        SBC HL,DE
        JP NZ,SRTFPALS
        XOR A
        LD HL,1
        PUSH IX
        RET

; write and display return UNSPECIFIED after printing their one argument.
SRTWRITE:
        CALL SRTONE
        CALL SRTWRVAL
        JP SRTUNSP
SRTDSPP:
        CALL SRTONE
        CP 5
        JR NZ,SRTDISPV
        CALL SRTWRLIT
        JP SRTUNSP
SRTDISPV:
        CALL SRTWRVAL
        JP SRTUNSP

; newline accepts no arguments and returns UNSPECIFIED.
SRTNWL:
        LD A,(SRTARGC)
        OR A
        JP NZ,SRTERROR
        LD A,13
        CALL SRTCH
        LD A,10
        CALL SRTCH
SRTUNSP:
        XOR A
        LD HL,0FE04H
        PUSH IX
        RET

; Read a packet record at HL and return its tag in A and payload in HL.
SRTPVAL:
        LD E,(HL)                  ; Read payload low.
        INC HL
        LD D,(HL)                  ; Read payload high.
        INC HL
        LD A,(HL)                  ; Read the logical value tag.
        EX DE,HL                   ; Return the payload while discarding the cursor.
        RET

; A primitive tail call removes the current epilogue, then returns through it
; after the checked operation has consumed the packet values.
SRTTPRIM:
        CALL SRTIVAL               ; Validate and classify the reserved payload.
        POP IX                     ; The current frame's epilogue is now the return.
        JP SRTPRIM                 ; Evaluate with the reused procedure frame.
