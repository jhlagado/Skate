;=============================================================================
;  Skate native primitive dispatch
;=============================================================================

; Resolve a closure or primitive, then jump through the ordinary call packet.
RTINVOKE:
        CALL RTSTKCHK          ; Prove the helper and target-entry stack path fits.
        CALL RTCHKPK           ; Validate every staged value slot before reading it.
        CALL RTDISPCH           ; Resolve either a checked closure or a primitive scalar.
        LD DE,(RTPACKET)           ; Restore the packet base expected by the target entry.
        LD BC,(RTPKARGC)             ; Restore the argument count expected by the target entry.
        LD HL,(RTTARGET)           ; Both closures and primitive wrappers use one target address.
        JP (HL)                    ; Dispatch without adding a second return word.

; Resolve a closure or a primitive scalar stored in the packet's callee slot.
RTDISPCH:
        XOR A                      ; Closure dispatch is the default path.
        LD (RTISPRIM),A            ; RTTAIL checks this flag after validating its activation.
        LD HL,(RTPACKET)           ; The callee is the second four-byte packet slot.
        LD DE,4                    ; Skip the environment value in slot zero.
        ADD HL,DE                  ; HL now addresses the callee tag.
        LD A,(HL)                  ; Closures use REF; primitives use private scalar immediates.
        CP 1                       ; Logical tag one is the only closure representation.
        JP Z,RTCALLCL              ; RTRESLV validates its subtype, cell and descriptor.
        OR A                       ; Primitive procedures are tag-zero scalar values.
        JP NZ,RTTYERR              ; Reject numbers, references of other kinds and invalid tags.
        INC HL                     ; Advance from the scalar tag to its payload low byte.
        LD E,(HL)                  ; Preserve the primitive ID's low payload byte.
        INC HL                     ; Advance to the payload high byte.
        LD D,(HL)                  ; DE now contains the complete primitive encoding.
        LD A,D                     ; Every primitive value has the private FE high byte.
        CP 0FEH                    ; Do not treat an arbitrary scalar as a procedure.
        JP NZ,RTTYERR              ; Only compiler-reserved primitive payloads may dispatch.
        LD A,E                     ; Extract FE20H through FE3CH's low-byte ID.
        CP 020H                    ; IDs begin immediately after the scalar constants.
        JP C,RTTYERR               ; Lower immediates are not primitive procedures.
        SUB 020H                   ; Normalize the encoded payload to its table index.
        CP 29                      ; P5 implements primitive IDs zero through twenty-eight.
        JP NC,RTTYERR              ; Reject reserved or unsupported primitive values.
        LD (RTPRIMID),A            ; Retain the index while calculating its table address.
        LD L,A                     ; HL begins with the zero-extended table index.
        LD H,0                     ; Each primitive-table entry is a two-byte target address.
        ADD HL,HL                  ; Convert the target index to a word offset.
        LD DE,RTPRIMTB             ; The table order matches the stable primitive identities.
        ADD HL,DE                  ; Address the selected wrapper pointer.
        LD E,(HL)                  ; Read the target's low address byte.
        INC HL                     ; Advance to the high address byte.
        LD D,(HL)                  ; DE now contains the selected dispatch wrapper.
        LD (RTTARGET),DE           ; RTINVOKE or RTTAIL will jump through this target.
        LD A,1                     ; Mark this as a primitive rather than a closure entry.
        LD (RTISPRIM),A            ; Primitive dispatch does not allocate an activation.
        XOR A                      ; Return success with carry clear.
        RET                        ; The caller performs the indirect jump.

RTCALLCL:
        CALL RTRESLV               ; Check closure type, descriptor bounds and exact arity.
        RET                        ; RTRESLV publishes the validated target in RTTARGET.

; Primitive IDs are stable global values; table order is the published ABI.
RTPRIMTB:
        DW RTPLUS,RTMINUS,RTMULT,RTDIVID
        DW RTCMPEQ,RTCMPLES,RTCMPGRE,RTCMPLEQ,RTCMPGEQ
        DW RTPCONS,RTPCAROP,RTPCDROP,RTPNULL,RTPPAIR,RTPLIST,RTPEQUAL
        DW RTNOT,RTNUMP,RTBOOLP,RTSYMBP,RTPROCP,RTSTRP,RTCHARP
        DW RTDISP,RTWRITE,RTNEWLIN,RTREADCH,RTEOFP,RTAPPLY

RTBADPRM:
        JP RTTYERR                 ; A reserved primitive scalar is not callable in P5.

; Comparison wrappers select equality, ordering or an inclusive bound check.
RTCMPEQ:
        LD A,0                     ; Raw comparison code zero means equal.
        JP RTCMPRUN                ; Validate every operand before reducing the chain.
RTCMPLES:
        LD A,1                     ; Raw comparison code FFFFH means less.
        JP RTCMPRUN                ; Adjacent comparisons are evaluated left to right.
RTCMPGRE:
        LD A,2                     ; Raw comparison code one means greater.
        JP RTCMPRUN                ; Continue after a false result to catch later type errors.
RTCMPLEQ:
        LD A,3                     ; Inclusive less-or-equal accepts raw -1 or zero.
        JP RTCMPRUN                ; The unordered code two is never true.
RTCMPGEQ:
        LD A,4                     ; Inclusive greater-or-equal accepts zero or one.

; Compare every adjacent pair after validating the complete argument sequence.
RTCMPRUN:
        LD (RTCMPMD),A            ; Preserve the selected relation while loading arguments.
        LD HL,(RTPKARGC)           ; Comparisons require at least two numeric operands.
        LD DE,2                    ; The minimum relation has exactly one adjacent pair.
        OR A                       ; Clear carry before the unsigned arity comparison.
        SBC HL,DE                  ; A smaller count cannot form a comparison.
        JP C,RTARERR               ; Report the fixed lower arity through the call boundary.
        LD HL,0                    ; Begin the validation pass at argument zero.
        LD (RTNUMIDX),HL           ; RTNLOAD addresses each rooted packet value in turn.
RTCMPVAL:
        LD HL,(RTNUMIDX)           ; Stop once every argument has passed numeric validation.
        LD DE,(RTPKARGC)           ; The packet count was checked before this pass began.
        OR A                       ; Clear carry before the unsigned index comparison.
        SBC HL,DE                  ; Equality or greater means the validation pass is complete.
        JP NC,RTCMPSRT           ; Only numeric values may reach the relation reduction.
        CALL RTNLOAD               ; Load one argument as A:HL without consuming its root slot.
        CALL NCLASS                 ; Validate its tag and payload independently.
        JP C,RTNFAIL               ; Preserve the runtime's type-error code on bad input.
        LD HL,(RTNUMIDX)           ; Advance the validation index after a successful check.
        INC HL                     ; Exactly one argument has just been classified.
        LD (RTNUMIDX),HL           ; Keep the complete 16-bit index for the next pass.
        JP RTCMPVAL                ; Continue until the entire argument list is validated.
RTCMPSRT:
        LD A,1                     ; A true relation remains true until a pair disproves it.
        LD (RTCMPFLG),A           ; Later pairs are still examined after the first false one.
        LD HL,0                    ; The first argument becomes the previous comparison value.
        LD (RTNUMIDX),HL           ; Reload argument zero from the rooted packet.
        CALL RTNLOAD               ; Preserve its original representation and payload.
        LD (RTNUMTAG),A            ; Keep the previous operand's logical tag.
        LD (RTNUMACC),HL           ; Keep its payload while loading the next operand.
        LD HL,1                    ; Adjacent comparison starts with argument one.
        LD (RTNUMIDX),HL           ; The validation pass already proved this index exists.
RTCMPLP:
        LD HL,(RTNUMIDX)           ; Check whether the final adjacent pair has been consumed.
        LD DE,(RTPKARGC)           ; Compare the next index with the complete argument count.
        OR A                       ; Clear carry before the unsigned index comparison.
        SBC HL,DE                  ; A completed chain returns the accumulated boolean.
        JP NC,RTCMPDON            ; Every pair has been evaluated, even after a false one.
        CALL RTNLOAD               ; Load the right operand for this adjacent comparison.
        LD A,(RTARGTAG)            ; Numeric ABI B is the right operand's representation tag.
        LD B,A                     ; Preserve it while restoring the left operand below.
        LD DE,(RTARGVAL)           ; Numeric ABI DE is the right operand's payload.
        LD A,(RTNUMTAG)            ; Numeric ABI A is the previous operand's tag.
        LD HL,(RTNUMACC)           ; Numeric ABI HL is the previous operand's payload.
        CALL NCMP                  ; Return raw -1, 0, +1 or unordered code two.
        JP C,RTNFAIL               ; Validation above makes this unreachable except corruption.
        LD (RTCPCODE),HL          ; Preserve the raw code while testing this relation.
        CALL RTCMPTST             ; Set the accumulated boolean when this pair fails.
        LD A,(RTARGTAG)            ; The right operand becomes the next pair's left value.
        LD (RTNUMTAG),A            ; Preserve its representation tag across the index update.
        LD HL,(RTARGVAL)           ; Restore its payload from the staged argument scratch.
        LD (RTNUMACC),HL           ; Keep it as the previous comparison value.
        LD HL,(RTNUMIDX)           ; Advance to the next adjacent pair.
        INC HL                     ; One right operand has now become the new left.
        LD (RTNUMIDX),HL           ; Preserve the complete comparison index.
        JP RTCMPLP                ; Continue to validate and compare every adjacent pair.
RTCMPDON:
        LD A,(RTCMPFLG)           ; Convert the accumulated relation to Scheme booleans.
        OR A                       ; A nonzero flag selects canonical #t.
        JP NZ,RTTRUE               ; The pair chain was true for every adjacent comparison.
        JP RTFALSE                 ; Any failed or unordered relation returns #f.

; Apply the selected relation to RTCPCODE without short-circuiting validation.
RTCMPTST:
        LD A,(RTCMPMD)            ; Select the requested relation family.
        OR A                       ; Equality accepts exactly raw zero.
        JP Z,RTCMPEQT              ; Test the saved comparison code.
        CP 1                       ; Less-than accepts exactly raw FFFFH.
        JP Z,RTCMPLTT              ; Test the saved comparison code.
        CP 2                       ; Greater-than accepts exactly raw one.
        JP Z,RTCMPGTT              ; Test the saved comparison code.
        CP 3                       ; Less-or-equal rejects only +1 and unordered.
        JP Z,RTCMPLET              ; Test both disallowed raw codes.
        JP RTCMPGET                ; Greater-or-equal rejects only -1 and unordered.
RTCMPEQT:
        LD HL,(RTCPCODE)          ; Equality is true only when both code bytes are zero.
        LD A,H                     ; Inspect the raw code high byte.
        OR L                       ; Combine it with the low byte for a zero test.
        RET Z                      ; Keep the accumulated true flag when equal.
        JP RTCMPBAD              ; Any ordering or unordered result disproves equality.
RTCMPLTT:
        LD HL,(RTCPCODE)          ; Less is represented by the signed word FFFFH.
        LD DE,0FFFFH               ; Compare both bytes without relying on flags from NCMP.
        OR A                       ; Clear carry before the exact code comparison.
        SBC HL,DE                  ; Equality leaves Z set.
        RET Z                      ; Keep true for a strict less result.
        JP RTCMPBAD              ; Greater, equal and unordered are false for <.
RTCMPGTT:
        LD HL,(RTCPCODE)          ; Greater is represented by raw code one.
        LD DE,1                    ; Compare against the complete positive code.
        OR A                       ; Clear carry before subtracting the expected code.
        SBC HL,DE                  ; Equality leaves Z set.
        RET Z                      ; Keep true for a strict greater result.
        JP RTCMPBAD              ; Less, equal and unordered are false for >.
RTCMPLET:
        LD HL,(RTCPCODE)          ; Less-or-equal rejects greater and unordered codes.
        LD DE,1                    ; First disallowed code is strict greater.
        OR A                       ; Clear carry before comparing raw words.
        SBC HL,DE                  ; Equality leaves Z set for raw +1.
        JP Z,RTCMPBAD            ; A greater pair disproves <=.
        LD HL,(RTCPCODE)          ; Re-read the code after the first comparison.
        LD DE,2                    ; Second disallowed code is unordered.
        OR A                       ; Clear carry before the second exact comparison.
        SBC HL,DE                  ; Equality leaves Z set for raw unordered.
        RET NZ                     ; Less or equal leaves the accumulated flag unchanged.
        JP RTCMPBAD              ; Unordered never satisfies an ordering relation.
RTCMPGET:
        LD HL,(RTCPCODE)          ; Greater-or-equal rejects less and unordered codes.
        LD DE,0FFFFH               ; First disallowed code is strict less.
        OR A                       ; Clear carry before comparing raw words.
        SBC HL,DE                  ; Equality leaves Z set for raw -1.
        JP Z,RTCMPBAD            ; A less pair disproves >=.
        LD HL,(RTCPCODE)          ; Re-read the code after the first comparison.
        LD DE,2                    ; Second disallowed code is unordered.
        OR A                       ; Clear carry before the second exact comparison.
        SBC HL,DE                  ; Equality leaves Z set for raw unordered.
        RET NZ                     ; Greater or equal leaves the accumulated flag unchanged.
RTCMPBAD:
        XOR A                      ; Mark the relation false while continuing the scan.
        LD (RTCMPFLG),A           ; Later operands still undergo full numeric validation.
        RET                        ; Return to the adjacent-pair loop.

; Primitive wrappers return normally or complete a tail call through RTRETURN.
RTPRDONE:
        LD B,A                     ; Preserve the logical result tag during the mode check.
        LD A,(RTREUSE)             ; RTTAIL sets reuse only for its immediate primitive target.
        OR A                       ; Zero means this wrapper belongs to an ordinary call.
        JP NZ,RTPRTAIL             ; A tail primitive returns through the current activation.
        LD A,B                     ; Restore the ordinary result tag.
        RET                        ; Resume the instruction after CALL RTINVOKE.
RTPRTAIL:
        XOR A                      ; A primitive consumes the tail-reuse request itself.
        LD (RTREUSE),A             ; Do not let a later closure entry inherit this flag.
        LD A,B                     ; Restore the primitive result tag for the return epilogue.
        JP RTRETURN                ; Drop this activation and return its result to the caller.

; Primitive scalar IDs zero through three call the numeric runtime by operation.
RTPLUS:
        XOR A                      ; Numeric operation zero is variadic addition.
        JP RTNUMRUN                ; Share argument loading, folding and error conversion.
RTMINUS:
        LD A,1                     ; Numeric operation one is subtraction.
        JP RTNUMRUN                ; Unary minus uses NNEG in the shared wrapper.
RTMULT:
        LD A,2                     ; Numeric operation two is variadic multiplication.
        JP RTNUMRUN                ; The empty product returns exact one.
RTDIVID:
        LD A,3                     ; Numeric operation three is left division.
RTNUMRUN:
        LD (RTNUMOP),A             ; Retain the operation while reading packet values.
        LD HL,(RTPKARGC)           ; Zero arguments are legal only for + and *.
        LD A,H                     ; Test both bytes of the supplied arity.
        OR L                       ; A nonzero count enters the operation-specific setup.
        JP NZ,RTNVALID              ; Validate every operand before choosing a fold path.
        LD A,(RTNUMOP)             ; Identify which zero-argument case was requested.
        OR A                       ; Addition's empty identity is exact zero.
        JP Z,RTNEMPTY              ; Return zero without entering the numeric leaf module.
        CP 2                       ; Multiplication's empty identity is exact one.
        JP Z,RTNEMPTY              ; The operation-specific branch below supplies that one.
        JP RTARERR                 ; Unary or left operations have no zero-argument result.
RTNVALID:
        LD HL,0                    ; Begin the complete numeric validation pass at argument zero.
        LD (RTNUMIDX),HL           ; RTNLOAD addresses each rooted packet value in turn.
RTNVALL:
        LD HL,(RTNUMIDX)           ; Stop only after every supplied operand has been checked.
        LD DE,(RTPKARGC)           ; The packet count was validated before dispatch.
        OR A                       ; Clear carry before the unsigned index comparison.
        SBC HL,DE                  ; Equality or greater means validation is complete.
        JP NC,RTNSTART             ; Only now may operation-specific folding begin.
        CALL RTNLOAD               ; Load one argument without consuming its root slot.
        CALL NCLASS                ; Reject nonnumeric tags before any arithmetic occurs.
        JP C,RTNFAIL               ; A bad operand has precedence over later overflow.
        LD HL,(RTNUMIDX)           ; Advance the validation index after a valid operand.
        INC HL                     ; Exactly one argument has just been classified.
        LD (RTNUMIDX),HL           ; Preserve the complete 16-bit index for the next pass.
        JP RTNVALL                 ; Continue until the whole argument sequence is valid.
RTNEMPTY:
        LD A,(RTNUMOP)             ; Recover the empty operation after its arity check.
        CP 2                       ; Only multiplication selects the value one.
        LD HL,0                    ; Addition's identity is exact integer zero.
        JP NZ,RTPRIMOK            ; Preserve exact tag three for the empty sum.
        INC HL                     ; Multiplication's identity is exact integer one.
RTPRIMOK:
        LD A,3                     ; Both identities use the exact-integer value tag.
        JP RTPRDONE                ; Primitive tail calls use the same return epilogue.
RTNSTART:
        LD HL,0                    ; Start each operation's argument index at zero.
        LD (RTNUMIDX),HL           ; The packet helper adds the two fixed header slots.
        LD A,(RTNUMOP)             ; Check whether subtraction needs a unary special case.
        CP 1                       ; Unary subtraction must preserve floating signed zero.
        JP Z,RTNUMMIN              ; Load the first value before choosing negate or fold.
        CP 3                       ; Division starts from exact one and divides every value.
        JP Z,RTNUMDIV              ; This also implements the one-argument reciprocal.
        LD A,3                     ; Addition and multiplication start with an exact identity.
        LD (RTNUMTAG),A            ; The accumulator is an exact integer until N* promotes it.
        LD A,(RTNUMOP)             ; Select zero for + or one for *.
        CP 0                       ; The zero-argument branch already handled both identities.
        LD HL,0                    ; Initialize the addition accumulator.
        JP Z,RTNIDENT              ; Keep zero when the operation is addition.
        LD HL,1                    ; Multiplication starts at exact one.
RTNIDENT:
        LD (RTNUMACC),HL           ; Save the identity before loading argument zero.
        JP RTNLOOP                 ; Fold every argument from the start of the packet.
RTNUMDIV:
        LD HL,(RTPKARGC)           ; Distinguish reciprocal from ordinary left division.
        LD DE,1                    ; A single operand computes one divided by that value.
        OR A                       ; Clear carry before comparing the two counts.
        SBC HL,DE                  ; Equality selects the unary reciprocal path.
        JP Z,RTDIVONE              ; Keep the identity-one fold for exactly one operand.
        LD HL,0                    ; Multi-operand division starts with source operand zero.
        LD (RTNUMIDX),HL           ; Load that first operand without performing a divide.
        CALL RTNLOAD               ; Validate it when the first binary operation runs.
        LD (RTNUMTAG),A            ; Preserve its original representation tag.
        LD (RTNUMACC),HL           ; Preserve its payload as the left divisor operand.
        LD HL,1                    ; The first division uses source operand one as the right.
        LD (RTNUMIDX),HL           ; Continue with the remaining operands in source order.
        JP RTNLOOP                 ; Apply left-associative division to every remaining value.
RTDIVONE:
        LD A,3                     ; Division promotes exact inputs to binary16.
        LD (RTNUMTAG),A            ; The initial one is supplied as an exact integer.
        LD HL,1                    ; One operand therefore computes its reciprocal.
        LD (RTNUMACC),HL           ; Keep the identity before loading argument zero.
        LD HL,0                    ; Unary division starts at the sole source operand.
        LD (RTNUMIDX),HL           ; Include argument zero in the reciprocal operation.
        JP RTNLOOP                 ; Divide one by that operand.
RTNUMMIN:
        LD HL,(RTPKARGC)           ; Distinguish unary negation from left subtraction.
        LD DE,1                    ; A count of one selects exactly one input value.
        OR A                       ; Clear carry before comparing the two counts.
        SBC HL,DE                  ; Equality means there are no later operands to fold.
        JP Z,RTNEGONE              ; Use NNEG so unary floating zero changes its sign.
        LD HL,0                    ; A multi-argument subtraction starts from argument zero.
        LD (RTNUMIDX),HL           ; Retain its packet index while the helper loads it.
        CALL RTNLOAD               ; Return argument zero as its original tag and payload.
        LD (RTNUMTAG),A            ; Preserve its tag as the left arithmetic operand.
        LD (RTNUMACC),HL           ; Preserve its value until argument one is loaded.
        LD HL,1                    ; Subtraction begins folding at argument index one.
        LD (RTNUMIDX),HL           ; Every later operand is evaluated and already rooted.
        JP RTNLOOP                 ; Apply left-associative subtraction to the rest.
RTNEGONE:
        LD HL,0                    ; Unary minus always reads argument zero.
        LD (RTNUMIDX),HL           ; Keep the lookup index in stable scratch.
        CALL RTNLOAD               ; Load the value without changing its tagged encoding.
        CALL NNEG                  ; Unary minus has distinct signed-zero behavior.
        JP C,RTNFAIL               ; Translate numeric errors to the runtime error contract.
        LD (RTNUMACC),HL           ; Save the result so the shared epilogue can return it.
        LD (RTNUMTAG),A            ; Keep its tag paired with the payload.
        JP RTNDONE                 ; Return the unary result without a binary fold.
RTNLOOP:
        LD HL,(RTNUMIDX)           ; Compare the next argument index with packet arity.
        LD DE,(RTPKARGC)           ; The count was checked when the call packet was staged.
        OR A                       ; Clear carry before the unsigned index comparison.
        SBC HL,DE                  ; A completed fold has consumed every argument.
        JP NC,RTNDONE              ; Return the accumulator after the final operand.
        CALL RTNLOAD               ; Load the next argument's tag and two-byte payload.
        LD (RTARGTAG),A            ; Keep the right tag while restoring the accumulator.
        LD (RTARGVAL),HL           ; Keep the right payload while selecting the operation.
        LD A,(RTNUMOP)             ; Dispatch to the numeric runtime's stable public entry.
        OR A                       ; Operation zero selects NADD.
        JP Z,RTNUMADD              ; Each leaf validates both tags before arithmetic.
        CP 1                       ; Operation one selects NSUB.
        JP Z,RTNUMSUB              ; The accumulator remains the left operand.
        CP 2                       ; Operation two selects NMUL.
        JP Z,RTNUMMUL              ; Exact overflow is reported before the next operand.
        JP RTDIVOP                 ; Operation three selects NDIV.
RTNUMADD:
        LD A,(RTARGTAG)            ; Load the right representation tag first.
        LD B,A                     ; Numeric ABI B is the right representation tag.
        LD DE,(RTARGVAL)           ; Numeric ABI DE is the right payload.
        LD A,(RTNUMTAG)            ; Numeric ABI A is the left representation tag.
        LD HL,(RTNUMACC)           ; Numeric ABI HL is the left payload.
        CALL NADD                  ; The numeric module validates, promotes and adds.
        JP RTNUMRES                ; Save a successful accumulator or report its error.
RTNUMSUB:
        LD A,(RTARGTAG)            ; Supply the next value's original representation tag.
        LD B,A                     ; Preserve it for the numeric right operand.
        LD DE,(RTARGVAL)           ; Supply its payload as the numeric right operand.
        LD A,(RTNUMTAG)            ; Keep the accumulator as the left representation tag.
        LD HL,(RTNUMACC)           ; Restore its payload after loading the next argument.
        CALL NSUB                  ; N* preserves exact arithmetic when both sides are exact.
        JP RTNUMRES                ; Carry separates numeric errors from successful values.
RTNUMMUL:
        LD A,(RTARGTAG)            ; Load the next argument's representation tag.
        LD B,A                     ; Preserve it for the numeric right operand.
        LD DE,(RTARGVAL)           ; Load its payload for the public numeric entry.
        LD A,(RTNUMTAG)            ; Restore the left accumulator tag.
        LD HL,(RTNUMACC)           ; Restore the left accumulator payload.
        CALL NMUL                  ; Multiply with exact signed overflow checks.
        JP RTNUMRES                ; Retain the exact or binary16 result for the next step.
RTDIVOP:
        LD A,(RTARGTAG)            ; Supply the right argument's original tag.
        LD B,A                     ; Numeric ABI B is the right representation tag.
        LD DE,(RTARGVAL)           ; Supply its payload in the numeric ABI's DE pair.
        LD A,(RTNUMTAG)            ; The accumulator is the left representation.
        LD HL,(RTNUMACC)           ; Restore its payload from stable workspace.
        CALL NDIV                  ; Division always returns a binary16 scalar.
        JP RTNUMRES                ; A zero divisor follows binary16 infinity/NaN rules.
RTNUMRES:
        JP C,RTNFAIL               ; N* returns carry for a type error or exact overflow.
        LD (RTNUMACC),HL           ; Save the value before advancing to the next argument.
        LD (RTNUMTAG),A            ; Save its representation tag alongside the payload.
        LD HL,(RTNUMIDX)           ; Advance the complete unsigned argument index.
        INC HL                     ; One numeric operation consumed exactly one operand.
        LD (RTNUMIDX),HL           ; Preserve it across the next packet-slot calculation.
        JP RTNLOOP                 ; Continue the left fold until argc is exhausted.
RTNDONE:
        LD A,(RTNUMTAG)            ; Return the accumulator's logical value tag.
        LD HL,(RTNUMACC)           ; Return its payload in the common A:HL convention.
        JP RTPRDONE                ; Ordinary and tail primitive calls share one epilogue.
RTNFAIL:
        CP 1                       ; Numeric error one is a Scheme type error.
        JP Z,RTERROR               ; Preserve the established runtime type-error code.
        LD A,6                     ; Runtime error six denotes exact integer overflow.
        JP RTERROR                 ; Keep numeric overflow distinct from call arity errors.

; Load argument RTNUMIDX as A:HL from the rooted packet without consuming it.
RTNLOAD:
        LD HL,(RTNUMIDX)           ; Convert the argument index to its four-byte slot offset.
        ADD HL,HL                  ; First doubling gives a two-byte value offset.
        ADD HL,HL                  ; Second doubling gives the complete root-slot stride.
        LD DE,8                    ; Argument zero begins after the packet's two headers.
        ADD HL,DE                  ; Add the fixed environment and callee slots.
        LD DE,(RTPACKET)           ; The packet base was validated before dispatch.
        ADD HL,DE                  ; HL now points at the selected argument's tag.
        JP C,RTINVERR              ; A wrapped address contradicts the checked packet extent.
        LD A,(HL)                  ; Keep the logical tag while reading the payload.
        LD (RTARGTAG),A            ; Preserve it across the byte-address increments.
        INC HL                     ; Move to the payload low byte.
        LD E,(HL)                  ; Read payload low.
        INC HL                     ; Advance to payload high.
        LD D,(HL)                  ; DE now contains the tagged value's payload.
        EX DE,HL                   ; Return the payload in HL without changing the tag.
        LD (RTARGVAL),HL           ; Retain the same payload for the comparison or fold.
        LD A,(RTARGTAG)            ; Restore the tag into A for NNEG or the arithmetic fold.
        RET                        ; The packet remains rooted until the primitive returns.

; Pair primitive wrappers reuse M9 services, then select ordinary or tail return.
RTPCONS:
        CALL RTCONSP               ; Construct a pair from both rooted arguments.
        JP RTPRDONE                ; Preserve its value while returning through the caller.
RTPCAROP:
        CALL RTPAIRCA              ; Read one checked pair's CAR.
        JP RTPRDONE                ; Return through RTRETURN when this is a tail primitive.
RTPCDROP:
        CALL RTPAIRCD              ; Read one checked pair's CDR.
        JP RTPRDONE                ; The pair service leaves A:HL as its result.
RTPNULL:
        CALL RTNULLP               ; Test the canonical NIL immediate.
        JP RTPRDONE                ; Predicates return the ordinary boolean encoding.
RTPPAIR:
        CALL RTPAIRP               ; Test whether the argument names a valid pair anchor.
        JP RTPRDONE                ; A tail predicate returns from the current activation.
RTPLIST:
        CALL RTLIST                ; Build a fresh proper list from every packet argument.
        JP RTPRDONE                ; Collection-visible packet roots survive the constructor.
RTPEQUAL:
        CALL RTEQVAL               ; Compare logical tag and payload identity.
        JP RTPRDONE                ; Return the boolean through the common primitive epilogue.

; Invoke a procedure with the values in one final proper list.
; The original apply packet remains rooted while a second packet is staged.
RTAPPLY:
        CALL RTSTKCHK              ; List validation and packet staging need bounded helpers.
        CALL RTCHKPK               ; Keep the procedure and list rooted before reading either.
        CALL RTARGTWO              ; apply accepts exactly a procedure and one argument list.
        LD HL,0                    ; Argument zero is the procedure value.
        LD (RTNUMIDX),HL           ; Reuse the indexed packet loader for the first slot.
        CALL RTNLOAD               ; Load the procedure without consuming its root slot.
        LD (RTAPFTAG),A            ; Retain its logical tag until the new callee slot is filled.
        LD (RTAPFVAL),HL           ; Retain its payload across list validation and allocation.
        LD HL,1                    ; Argument one is the final list of call arguments.
        LD (RTNUMIDX),HL           ; Select the second packet value for the same loader.
        CALL RTNLOAD               ; Load the list while the original packet remains rooted.
        LD (RTAPLTAG),A            ; The count pass updates this tag as it follows each CDR.
        LD (RTAPLLST),HL           ; The list payload is either NIL or a checked pair anchor.
        LD (RTAPOTAG),A            ; Preserve the list head before the count pass reaches NIL.
        LD (RTAPOVAL),HL           ; Packet allocation changes RTPACKET, so retain the head here.
        XOR A                      ; Start with zero list elements consumed.
        LD (RTAPCNT),A             ; Clear the low count byte.
        LD (RTAPCNT+1),A           ; Clear the high count byte without a word constant.
        CALL RTAPCNTL              ; Validate properness and count up to the packet bound.
        LD BC,(RTAPCNT)            ; Reserve exactly one argument slot per list element.
        CALL RTPKNEW               ; The old apply packet remains below this rooted packet.
        LD HL,(RTPACKET)           ; The new packet's callee slot follows its environment slot.
        LD DE,4                    ; Skip the NIL environment header.
        ADD HL,DE                  ; HL now addresses the new callee tag byte.
        LD A,(RTAPFTAG)            ; Copy the procedure into the dispatch slot.
        LD (HL),A                  ; Preserve its logical tag for RTDISPCH.
        INC HL                     ; Advance to the payload low byte.
        LD DE,(RTAPFVAL)           ; Restore the procedure payload.
        LD (HL),E                  ; Store the low payload byte.
        INC HL                     ; Advance to the payload high byte.
        LD (HL),D                  ; Complete the new callee value.
        INC HL                     ; Advance to the collector padding byte.
        LD (HL),0                  ; Keep the callee root slot canonical.
        LD HL,(RTPACKET)           ; Argument zero follows the two packet headers.
        LD DE,8                    ; Skip environment and callee slots.
        ADD HL,DE                  ; HL is the first destination argument slot.
        LD (RTAPDST),HL            ; Fill advances this pointer by one rooted slot.
        LD A,(RTAPOTAG)            ; Restore the original list head for the second pass.
        LD (RTAPLTAG),A            ; The fill pass must copy from the first CAR again.
        LD HL,(RTAPOVAL)           ; Restore its payload after RTPKNEW changed RTPACKET.
        LD (RTAPLLST),HL           ; The original apply packet still roots the complete list.
        LD HL,(RTAPCNT)            ; The count becomes the fill loop's remaining work.
        LD (RTAPLEFT),HL           ; A zero-length list skips the pair-copy loop.
        LD A,H                     ; Test both bytes of the staged argument count.
        OR L                       ; Zero means the new packet is already complete.
        JP Z,RTAPCALL              ; Dispatch the zero-argument procedure directly.
        CALL RTAPFILL              ; Copy each CAR into the new packet in source order.
RTAPCALL:
        LD A,(RTREUSE)             ; A tail primitive reached apply without a return address.
        OR A                       ; Ordinary calls may invoke the target with CALL below.
        JP NZ,RTAPTAIL             ; Let RTTAIL reuse the current activation for tail apply.
        LD DE,(RTPACKET)           ; The staged packet is the target's rooted call packet.
        LD BC,(RTPKARGC)           ; RTPKNEW published the list length as the target arity.
        CALL RTINVOKE              ; Reuse the generic dispatcher for closures and primitives.
        JP RTPRDONE                ; Return the target result through apply's primitive entry.
RTAPTAIL:
        LD DE,(RTPACKET)            ; RTTAIL receives the newly staged packet explicitly.
        LD BC,(RTPKARGC)            ; Pass its list-derived arity through the normal tail ABI.
        JP RTTAIL                   ; Tail dispatch replaces or reuses the current activation.

; Return #t only when the argument is the canonical false immediate.
RTNOT:
        CALL RTSTKCHK              ; Keep the predicate's helper path bounded.
        CALL RTCHKPK               ; Validate the complete rooted packet first.
        CALL RTARGONE              ; not accepts exactly one value.
        CALL RTGETARG              ; Load its logical tag and payload.
        OR A                       ; Only scalar values can be the false immediate.
        JP NZ,RTNOTNO              ; References and numbers are true in a condition.
        LD A,H                     ; Compare the high payload byte with FE.
        CP 0FEH                    ; Boolean payloads occupy the FE00/FE01 pair.
        JP NZ,RTNOTNO              ; Any other scalar is not false.
        LD A,L                     ; Inspect the low payload byte.
        OR A                       ; FE00 is the sole false value.
        JP NZ,RTNOTNO              ; FE01 and every other low byte are true.
        XOR A                      ; Return the canonical true immediate.
        LD HL,0FE01H               ; #t payload.
        JP RTPRDONE                ; Complete an ordinary or tail primitive return.
RTNOTNO:
        XOR A                      ; Return the canonical false immediate.
        LD HL,0FE00H               ; #f payload.
        JP RTPRDONE                ; Complete an ordinary or tail primitive return.

; Predicates below retain the value ABI: tag zero is scalar, tag one is REF.
RTNUMP:
        CALL RTSTKCHK              ; Keep bounded predicate helper depth.
        CALL RTCHKPK               ; Validate every packet slot before reading the argument.
        CALL RTARGONE              ; number? accepts exactly one value.
        CALL RTGETARG              ; Load the candidate number.
        CALL NCLASS                ; Numeric classification rejects invalid NaNs.
        JP C,RTNUMNO               ; A rejected scalar is simply not a number.
        XOR A                      ; Canonical #t tag.
        LD HL,0FE01H               ; Canonical #t payload.
        JP RTPRDONE                ; Return through the primitive epilogue.
RTNUMNO:
        XOR A                      ; Canonical #f tag.
        LD HL,0FE00H               ; Canonical #f payload.
        JP RTPRDONE                ; Return through the primitive epilogue.

RTBOOLP:
        CALL RTSTKCHK              ; Keep bounded predicate helper depth.
        CALL RTCHKPK               ; Validate the packet before reading its one value.
        CALL RTARGONE              ; boolean? accepts exactly one value.
        CALL RTGETARG              ; Load the candidate scalar.
        OR A                       ; Booleans use scalar tag zero.
        JP NZ,RTBOOLNO             ; References and numeric tags are not booleans.
        LD A,H                     ; Both boolean payloads have high byte FE.
        CP 0FEH                    ; Reject all other scalar families first.
        JP NZ,RTBOOLNO             ; Characters and primitive values are not booleans.
        LD A,L                     ; Only low bytes zero and one are assigned.
        CP 2                       ; Values at or above two are not booleans.
        JP NC,RTBOOLNO             ; Return false for every other immediate.
        XOR A                      ; Canonical #t tag.
        LD HL,0FE01H               ; Canonical #t payload.
        JP RTPRDONE                ; Return through the primitive epilogue.
RTBOOLNO:
        XOR A                      ; Canonical #f tag.
        LD HL,0FE00H               ; Canonical #f payload.
        JP RTPRDONE                ; Return through the primitive epilogue.

RTSYMBP:
        CALL RTSTKCHK              ; Keep bounded predicate helper depth.
        CALL RTCHKPK               ; Validate the packet before reading its one value.
        CALL RTARGONE              ; symbol? accepts exactly one value.
        CALL RTGETARG              ; Load the candidate reference.
        CP 1                       ; Symbols use logical reference tag one.
        JP NZ,RTSYMNO              ; Scalars and other references are not symbols.
        LD A,H                     ; Reference subtype occupies payload bits 15..13.
        AND 0E0H                   ; Retain only those subtype bits.
        CP 020H                    ; Subtype one denotes an interned symbol.
        JP NZ,RTSYMNO              ; Pairs, closures, environments and strings differ.
        XOR A                      ; Canonical #t tag.
        LD HL,0FE01H               ; Canonical #t payload.
        JP RTPRDONE                ; Return through the primitive epilogue.
RTSYMNO:
        XOR A                      ; Canonical #f tag.
        LD HL,0FE00H               ; Canonical #f payload.
        JP RTPRDONE                ; Return through the primitive epilogue.

RTPROCP:
        CALL RTSTKCHK              ; Keep bounded predicate helper depth.
        CALL RTCHKPK               ; Validate the packet before reading its one value.
        CALL RTARGONE              ; procedure? accepts exactly one value.
        CALL RTGETARG              ; Load the candidate reference.
        CP 1                       ; Heap closures use logical reference tag one.
        JP Z,RTPROCRF              ; Validate the closure subtype below.
        OR A                       ; Primitive procedures use scalar tag zero.
        JP NZ,RTPROCNO             ; Every other value is not a procedure.
        LD A,H                     ; Primitive IDs occupy FE20 through FE3C.
        CP 0FEH                    ; The private scalar high byte identifies primitives.
        JP NZ,RTPROCNO             ; Numeric scalars and immediates are not callable.
        LD A,L                     ; The low byte carries the stable primitive ID.
        CP 020H                    ; IDs begin after the scalar-immediate range.
        JP C,RTPROCNO              ; Lower FE values are not primitive procedures.
        CP 03DH                    ; FE3D is the first value beyond the 29-entry table.
        JP NC,RTPROCNO             ; Reserved scalar values remain nonprocedures.
        JP RTPROCY                  ; A compiler primitive is a first-class procedure.
RTPROCRF:
        LD A,H                     ; Retain the encoded heap-reference subtype.
        AND 0E0H                   ; Remove the thirteen-bit heap index.
        CP 040H                    ; Subtype two denotes a closure.
        JP NZ,RTPROCNO             ; Pairs, symbols, environments and strings differ.
RTPROCY:
        XOR A                      ; Canonical #t tag.
        LD HL,0FE01H               ; Canonical #t payload.
        JP RTPRDONE                ; Return through the primitive epilogue.
RTPROCNO:
        XOR A                      ; Canonical #f tag.
        LD HL,0FE00H               ; Canonical #f payload.
        JP RTPRDONE                ; Return through the primitive epilogue.

RTSTRP:
        CALL RTSTKCHK              ; Keep bounded predicate helper depth.
        CALL RTCHKPK               ; Validate the packet before reading its one value.
        CALL RTARGONE              ; string? accepts exactly one value.
        CALL RTGETARG              ; Load the candidate reference.
        CP 1                       ; Strings use logical reference tag one.
        JP NZ,RTSTRNO              ; Scalars and nonstring references are false.
        LD A,H                     ; Retain the encoded reference subtype.
        AND 0E0H                   ; Remove the thirteen-bit string identity.
        CP 080H                    ; Subtype four denotes an interned string.
        JP NZ,RTSTRNO              ; Every other reference subtype is different.
        XOR A                      ; Canonical #t tag.
        LD HL,0FE01H               ; Canonical #t payload.
        JP RTPRDONE                ; Return through the primitive epilogue.
RTSTRNO:
        XOR A                      ; Canonical #f tag.
        LD HL,0FE00H               ; Canonical #f payload.
        JP RTPRDONE                ; Return through the primitive epilogue.

RTCHARP:
        CALL RTSTKCHK              ; Keep bounded predicate helper depth.
        CALL RTCHKPK               ; Validate the packet before reading its one value.
        CALL RTARGONE              ; char? accepts exactly one value.
        CALL RTGETARG              ; Load the candidate scalar.
        OR A                       ; Characters use scalar tag zero.
        JP NZ,RTCHARNO             ; References and exact integers are not characters.
        LD A,H                     ; Character payloads occupy FF00 through FFFF.
        CP 0FFH                    ; The high payload byte identifies this scalar family.
        JP NZ,RTCHARNO             ; FE immediates and binary16 values differ.
        XOR A                      ; Canonical #t tag.
        LD HL,0FE01H               ; Canonical #t payload.
        JP RTPRDONE                ; Return through the primitive epilogue.
RTCHARNO:
        XOR A                      ; Canonical #f tag.
        LD HL,0FE00H               ; Canonical #f payload.
        JP RTPRDONE                ; Return through the primitive epilogue.

; Display and write share a bounded scalar printer in this first host adapter.
RTDISP:
        CALL RTSTKCHK              ; Keep printer helper depth bounded.
        CALL RTCHKPK               ; Validate every packet slot before reading one value.
        CALL RTARGONE              ; display accepts exactly one value.
        XOR A                      ; Display writes characters in their raw form.
        LD (RTPRMODE),A            ; RTPRVAL distinguishes display from write.
        CALL RTGETARG              ; Load the value to print.
        CALL RTPRVAL               ; Emit its supported scalar representation.
        XOR A                      ; display returns UNSPECIFIED.
        LD HL,0FE04H               ; Canonical unspecified payload.
        JP RTPRDONE                ; Complete an ordinary or tail primitive return.
RTWRITE:
        CALL RTSTKCHK              ; Keep printer helper depth bounded.
        CALL RTCHKPK               ; Validate every packet slot before reading one value.
        CALL RTARGONE              ; write accepts exactly one value.
        LD A,1                     ; Write uses readable character syntax.
        LD (RTPRMODE),A            ; RTPRVAL prefixes character values with #\.
        CALL RTGETARG              ; Load the value to print.
        CALL RTPRVAL               ; Emit the same scalar representation as display.
        XOR A                      ; write returns UNSPECIFIED.
        LD HL,0FE04H               ; Canonical unspecified payload.
        JP RTPRDONE                ; Complete an ordinary or tail primitive return.

RTNEWLIN:
        CALL RTSTKCHK              ; Keep the console helper bounded.
        CALL RTCHKPK               ; Validate the zero-argument packet shape.
        CALL RTARZERO              ; newline accepts no values.
        LD A,13                    ; CP/M consoles use CR/LF newlines.
        CALL RTPUTCH                ; Emit carriage return through BDOS.
        LD A,10                    ; Emit line feed after carriage return.
        CALL RTPUTCH                ; Preserve the same output contract as the printer.
        XOR A                      ; newline returns UNSPECIFIED.
        LD HL,0FE04H               ; Canonical unspecified payload.
        JP RTPRDONE                ; Complete an ordinary or tail primitive return.

RTREADCH:
        CALL RTSTKCHK              ; Keep the console helper bounded.
        CALL RTCHKPK               ; Validate the zero-argument packet shape.
        CALL RTARZERO              ; read-char accepts no values.
        LD C,1                     ; CP/M BDOS function one reads one console byte.
        CALL $0005                 ; The target adapter supplies the console byte in A.
        CP 26                      ; Control-Z is the CP/M end-of-file convention.
        JP Z,RTREOF                ; Return the singleton EOF value instead of a character.
        LD L,A                     ; Character payload low byte is the input byte.
        LD H,0FFH                  ; FFxx identifies a byte character.
        XOR A                      ; Characters use scalar logical tag zero.
        JP RTPRDONE                ; Complete an ordinary or tail primitive return.
RTREOF:
        XOR A                      ; EOF is a scalar immediate.
        LD HL,0FE03H               ; Canonical EOF payload.
        JP RTPRDONE                ; Complete an ordinary or tail primitive return.

RTEOFP:
        CALL RTSTKCHK              ; Keep the predicate's helper path bounded.
        CALL RTCHKPK               ; Validate the complete rooted packet first.
        CALL RTARGONE              ; eof-object? accepts exactly one value.
        CALL RTGETARG              ; Load the candidate scalar.
        OR A                       ; EOF is a scalar immediate.
        JP NZ,RTEOFNO              ; References and numeric values are not EOF.
        LD A,H                     ; Compare the high byte of FE03.
        CP 0FEH                    ; Reject other scalar families.
        JP NZ,RTEOFNO              ; Characters and primitives use different payloads.
        LD A,L                     ; Inspect the singleton's low byte.
        CP 3                       ; FE03 is the only EOF payload.
        JP NZ,RTEOFNO              ; Every other immediate is not EOF.
        XOR A                      ; Canonical #t tag.
        LD HL,0FE01H               ; Canonical #t payload.
        JP RTPRDONE                ; Return through the primitive epilogue.
RTEOFNO:
        XOR A                      ; Canonical #f tag.
        LD HL,0FE00H               ; Canonical #f payload.
        JP RTPRDONE                ; Return through the primitive epilogue.

; Print integers and characters directly; other values get a short readable marker.
RTPRVAL:
        CP 3                       ; Exact integers have their own decimal printer.
        JP Z,RTINTPR
        OR A                       ; Scalar zero and reference one have separate printers.
        JP Z,RTSCALR               ; Check the character payload for a scalar value.
        CP 1                       ; Only a logical reference can name a literal string.
        JP NZ,RTPRMARK             ; Other internal tags remain visibly unsupported.
        LD A,H                     ; The reference subtype distinguishes interned strings.
        AND 0E0H                   ; Remove the thirteen-bit string descriptor index.
        CP 080H                    ; Subtype four is the immutable literal-string table.
        JP Z,RTSTRVAL               ; Print its bytes through the same BDOS byte path.
        JP RTPRMARK                ; Other references retain the bounded marker form.
RTSCALR:
        LD A,H                     ; Character scalars have high payload byte FF.
        CP 0FFH                    ; Only those scalars are emitted as raw characters.
        JP Z,RTPRCHAR              ; Display and write select their character syntax here.
        JP RTPRMARK                ; Other references retain the bounded marker form.

; Print one immutable literal string selected by the reference payload in HL.
RTSTRVAL:
        LD A,H                     ; Keep only the thirteen-bit descriptor index.
        AND 01FH                   ; The high five payload bits carry the string subtype.
        LD H,A                     ; HL now contains the untagged string descriptor index.
        LD (RTSTRIDX),HL           ; Preserve the index while checking its table bound.
        LD DE,(RTSTRCNT)           ; The startup contract supplied the descriptor count.
        OR A                       ; Clear carry before the unsigned index comparison.
        SBC HL,DE                  ; An index at or above the count is corrupt metadata.
        JP NC,RTINVERR             ; Do not read outside the immutable descriptor table.
        LD HL,(RTSTRIDX)           ; Convert the descriptor index to a four-byte offset.
        ADD HL,HL                  ; First doubling gives two bytes per descriptor.
        ADD HL,HL                  ; Second doubling gives the complete descriptor offset.
        LD DE,(RTSTRBAS)           ; Add the offset to the resident descriptor table.
        ADD HL,DE                  ; HL addresses the selected descriptor's byte offset.
        LD E,(HL)                  ; Read the string-pool offset low byte.
        INC HL                     ; Advance to the offset high byte.
        LD D,(HL)                  ; DE now carries the immutable pool offset.
        INC HL                     ; Advance to the descriptor length low byte.
        LD (RTSTROFF),DE           ; Retain the offset while reading the length.
        LD E,(HL)                  ; Read the string length low byte.
        INC HL                     ; Advance to the length high byte.
        LD D,(HL)                  ; DE now carries the immutable string length.
        LD (RTSTRLEN),DE           ; Preserve it across pool address calculation.
        LD HL,(RTSTROFF)           ; Check offset plus length against the pool extent.
        LD DE,(RTSTRLEN)           ; A descriptor may name the empty end of the pool.
        ADD HL,DE                  ; HL is the selected string's exclusive pool end.
        JP C,RTINVERR              ; A wrapped descriptor extent is impossible metadata.
        LD DE,(RTSTRBYT)           ; Compare the selected end with the pool byte count.
        OR A                       ; Clear carry before the unsigned extent comparison.
        SBC HL,DE                  ; Carry or equality means the selected bytes fit.
        JP C,RTSTROK               ; The string ends below the immutable pool end.
        JP Z,RTSTROK               ; An empty string may end exactly at the pool end.
        JP RTINVERR                ; Refuse a descriptor that reaches beyond the pool.
RTSTROK:
        LD HL,(RTSTRPOL)           ; Begin at the immutable string pool base.
        LD DE,(RTSTROFF)           ; Add the selected descriptor's byte offset.
        ADD HL,DE                  ; HL addresses the first byte to emit.
        LD (RTSTRPTR),HL           ; Retain the cursor while the mode is inspected.
        LD A,(RTPRMODE)            ; Zero means display; one means readable write syntax.
        OR A                       ; Display emits only the literal bytes.
        JP Z,RTSTRLP               ; Skip the opening quote for display.
        LD A,34                    ; write surrounds strings with double quotes.
        CALL RTPUTCH               ; The byte helper preserves the string cursor.
RTSTRLP:
        LD BC,(RTSTRLEN)           ; BC counts the bounded bytes still to emit.
        LD HL,(RTSTRPTR)           ; HL points into the immutable pool.
RTSTRLOP:
        LD A,B                     ; Test the complete 16-bit byte count.
        OR C                       ; Zero ends the string without reading past the pool.
        JP Z,RTSTREND               ; The selected literal has been emitted.
        LD A,(HL)                  ; Load one original string byte.
        INC HL                     ; Advance only after the byte address was validated.
        CALL RTPUTCH               ; Emit it through the CP/M console byte contract.
        DEC BC                     ; One immutable byte has been consumed.
        JP RTSTRLOP                ; Continue until the descriptor length reaches zero.
RTSTREND:
        LD A,(RTPRMODE)            ; Display returns after the final literal byte.
        OR A                       ; Only write needs a closing quote.
        RET Z                      ; Preserve the normal display printer return path.
        LD A,34                    ; Complete readable string syntax for write.
        JP RTPUTCH                 ; Emit and return through the common byte helper.
RTPRCHAR:
        LD A,(RTPRMODE)            ; Zero means display; one means write.
        OR A                       ; Display leaves a character unadorned.
        JP Z,RTCHOUT               ; Emit the character byte itself.
        LD A,35                    ; write prefixes characters with '#'.
        CALL RTPUTCH                ; PUTCHAR preserves the original value registers.
        LD A,92                    ; The second prefix byte is a backslash.
        CALL RTPUTCH                ; Keep the syntax readable on a CP/M console.
RTCHOUT:
        LD A,L                     ; Emit the character byte itself.
        JP RTPUTCH
RTPRMARK:
        LD A,35                    ; Unsupported scalar forms are visibly marked with '#'.
        CALL RTPUTCH                ; Keep the console output valid without a table pointer.
        LD A,60                    ; '<' starts the descriptive marker.
        CALL RTPUTCH                ; Runtime details remain outside the value ABI.
        LD A,62                     ; '>' closes the marker.
        JP RTPUTCH                  ; Return with the caller's A:HL untouched by contract.

; Signed exact-integer printer used by display, write and diagnostics.
RTINTPR:
        LD A,0                     ; Suppress leading zeroes until the first digit.
        LD (RTPRFLAG),A            ; Keep the flag in runtime workspace.
        BIT 7,H                    ; A set sign bit denotes a negative two's-complement word.
        JP Z,RTPRPOS               ; Positive values can enter decimal places directly.
        LD A,45                    ; Emit the minus sign before taking the magnitude.
        CALL RTPUTCH                ; PUTCHAR preserves the value registers for conversion.
        LD A,0                     ; Negate the low byte with borrow into the high byte.
        SUB L                      ; Two's-complement low-byte subtraction.
        LD L,A                     ; Keep the resulting magnitude low byte.
        LD A,0                     ; Complete two's-complement negation of the high byte.
        SBC A,H                    ; Preserve magnitude 32768 for the minimum integer.
        LD H,A                     ; Continue with an unsigned magnitude.
RTPRPOS:
        LD DE,10000                ; Emit ten-thousands through ones in order.
        CALL RTPLACE                ; Each place subtracts until the next digit.
        LD DE,1000                 ; Thousands place.
        CALL RTPLACE                ; Preserve a leading-zero suppression flag.
        LD DE,100                   ; Hundreds place.
        CALL RTPLACE                ; Preserve the original magnitude in HL.
        LD DE,10                    ; Tens place.
        CALL RTPLACE                ; The ones place below always emits a digit.
        LD A,1                      ; The final place must emit zero for the value zero.
        LD (RTPRFLAG),A             ; Mark output before the ones-place conversion.
        LD DE,1                     ; Ones place.
        JP RTPLACE                  ; Return after emitting the final decimal digit.
RTPLACE:
        LD B,0                     ; B counts how many times this place subtracts.
RTPLACEL:
        OR A                       ; Clear carry before subtracting the place value.
        SBC HL,DE                  ; A borrow means the next digit would be too large.
        JP C,RTPLCOK                ; Restore the place value and emit the digit.
        INC B                      ; Count one digit and continue while it still fits.
        JP RTPLACEL                ; Decimal digits are bounded to at most five iterations.
RTPLCOK:
        ADD HL,DE                  ; Restore the first value that did not fit.
        LD A,B                     ; Test whether this place produced a nonzero digit.
        OR A                       ; A zero digit may still be suppressed.
        JP NZ,RTEMITD               ; Emit every nonzero digit.
        LD A,(RTPRFLAG)            ; Check whether an earlier place has already emitted.
        OR A                       ; Leading zeroes are omitted until that flag is set.
        RET Z                      ; Suppress this zero while preserving HL for the next place.
RTEMITD:
        LD A,1                     ; Mark that decimal output has begun.
        LD (RTPRFLAG),A            ; All following places, including zero, are emitted.
        LD A,B                     ; Convert the digit count to ASCII.
        ADD A,48                   ; ASCII '0' is 48.
        JP RTPUTCH                 ; Emit one digit and return to the next place.

RTPUTCH:
        PUSH AF                   ; BDOS uses A/DE/BC; preserve the caller's value registers.
        PUSH BC                   ; Preserve argument count and scratch.
        PUSH DE                   ; Preserve decimal place or caller data.
        PUSH HL                   ; Preserve the value payload.
        LD E,A                    ; CP/M function two expects the character in E.
        LD C,2                    ; BDOS console output function.
        CALL $0005                ; The target adapter emits one byte.
        POP HL                    ; Restore the value payload.
        POP DE                    ; Restore the decimal place.
        POP BC                    ; Restore argument count and scratch.
        POP AF                    ; Restore the caller's flags and accumulator byte.
        RET                       ; Return with the original value convention intact.

RTPRFLAG:
        DB 0                      ; Decimal printer's leading-zero state.
RTPRMODE:
        DB 0                      ; Zero for display characters, one for write syntax.
RTPRWEND:                         ; Exclusive end of the printer's mutable state.
