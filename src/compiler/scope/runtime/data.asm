; Pair, quoted-list and literal output services for the generated runtime.
;
; Pair slabs contain 51 five-byte records.  A record stores the CAR payload,
; CDR payload and one packed byte: three bits for each value tag, one allocated
; bit and one mark bit.  Logical pair values use tag one and the record address
; as their payload.  Symbols and strings use tags four and five and point at a
; length-prefixed output literal.

; Save one value on the quoted-data stack.
SRTQPUT:
        LD (SRTQATAG),A            ; Keep the logical tag across the bound check.
        LD (SRTQAVAL),HL           ; Keep the payload beside it.
        LD HL,(SRTQSP)
        LD DE,4
        ADD HL,DE
        LD DE,SRTQEND
        OR A
        SBC HL,DE
        JP NC,SRTERROR             ; A malformed quoted list cannot overrun the stack.
        LD (SRTQNXT),HL
        LD HL,(SRTQSP)
        LD DE,(SRTQAVAL)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD A,(SRTQATAG)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD (SRTQSP),HL
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        RET

; Pop one value from the quoted-data stack.
SRTQPOP:
        LD HL,(SRTQSP)
        LD DE,SRTQBASE
        OR A
        SBC HL,DE
        JP Z,SRTERROR
        LD HL,(SRTQSP)
        LD DE,4
        OR A
        SBC HL,DE
        LD (SRTQSP),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        EX DE,HL
        RET

; Fold the values on the quoted-data stack into a proper or dotted list.
SRTQBLD:
        LD (SRTQNR),A              ; A counts heads plus the optional tail.
        LD A,1
        LD (SRTQACTV),A            ; The accumulator remains live across cons GC.
        LD A,B
        LD (SRTQDOTR),A            ; B is nonzero for a dotted tail.
        OR A
        JR Z,SRTQNIL
        CALL SRTQPOP                ; The dotted tail is the initial accumulator.
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQNR)
        DEC A
        LD (SRTQNR),A
        JR SRTQLP
SRTQNIL:
        XOR A
        LD (SRTQATAG),A
        LD HL,0FE02H               ; Canonical empty-list value.
        LD (SRTQAVAL),HL
SRTQLP:
        LD A,(SRTQNR)
        OR A
        JR Z,SRTQDONE
        CALL SRTQPOP                ; The preceding element becomes the new CAR.
        LD (SRTQCTAG),A
        LD (SRTQCAR),HL
        LD A,(SRTQATAG)
        LD (SRTQDTAG),A
        LD HL,(SRTQAVAL)
        LD (SRTQCDR),HL
        CALL SRTMAKEP
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQNR)
        DEC A
        LD (SRTQNR),A
        JR SRTQLP
SRTQDONE:
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        XOR A
        LD (SRTQACTV),A            ; The returned value is now held by its caller.
        LD A,(SRTQATAG)
        RET



; Stop-the-world mark-and-sweep for every five-byte pair slab.  Root discovery
; is exact: compiler-patched static records, active value stacks, frames and
; construction scratch are visited by type rather than by byte pattern.
SRTGC:
        CALL SRTPCLE                ; Clear only mark bits from the last cycle.
        CALL SRTCLCLR               ; Start this collection with an empty mark map.
        LD HL,SRTMKBS               ; Restart the bounded pair worklist.
        LD (SRTMSTK),HL             ; The next mark is written at its base.
        XOR A
        LD (SRTMOVER),A             ; No queue overflow has occurred yet.
        LD (SRTMNEW),A              ; Clear the fallback pass indicator.
        CALL SRTROOTS               ; Visit only declared live value locations.
        CALL SRTDRAIN               ; Process every queued object before overflow checks.
        LD A,(SRTMOVER)
        OR A
        JR Z,SRTSWEEP               ; A complete queue has visited every reachable edge.
SRTGFIX:
        XOR A
        LD (SRTMNEW),A              ; Report only marks created by this fallback pass.
        CALL SRTFSCRN               ; Visit every marked pair to recover missed edges.
        CALL SRTCLSCR               ; Visit every marked closure without recursion.
        CALL SRTDRAIN               ; Process entries found by the fallback scan.
        LD A,(SRTMNEW)
        OR A
        JR NZ,SRTGFIX               ; Continue until a fixed point is reached.
SRTSWEEP:
        CALL SRTBSW                 ; Reclaim dead three-byte bindings.
        CALL SRTCLSW                ; Reclaim dead rounded closure blocks.
        CALL SRTPSW                ; Rebuild free records and clear surviving marks.
        RET

; Mark the two typed inputs held across an allocation retry.  These roots use
; their own storage because the ordinary pair tracing scratch is overwritten
; while a queued pair is being inspected.
SRTCRMK:
        LD A,(SRTCRON)
        OR A
        RET Z
        LD A,(SRTCRCTA)
        LD HL,(SRTCRCAR)
        CALL SRTMVALU
SRTCRCD:
        LD A,(SRTCRDTA)
        LD HL,(SRTCRCDR)
        JP SRTMVALU

; Clear mark bits in every allocated or free record before tracing.
SRTPCLE:
        LD A,(SRTPSLBN)
        OR A
        RET Z
        LD B,A                      ; B counts the pair slabs.
        LD HL,SRTPSLT
SRTPCLAB:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,SRTPCLSK               ; Skip holes without scanning address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (SRTPSST),HL
        LD (SRTPSBA),DE
        LD (SRTPSCAN),DE
        LD C,51                     ; Each page contains 51 five-byte records.
SRTPCLP:
        LD HL,(SRTPSCAN)
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        AND 7FH                     ; Preserve tags and allocation, clear marking.
        LD (HL),A
        LD HL,(SRTPSCAN)
        LD DE,5
        ADD HL,DE
        LD (SRTPSCAN),HL
        DEC C
        JR NZ,SRTPCLP
        LD HL,(SRTPSST)
        DJNZ SRTPCLAB
        RET
SRTPCLSK:
        LD DE,3                     ; Advance over a released descriptor slot.
        ADD HL,DE
        DJNZ SRTPCLAB
        RET

; Sweep all pair slabs.  Dead records become zero-state records; live records
; retain their tags and allocation bit but lose the mark bit.
SRTPSW:
        LD A,(SRTPSLBN)
        OR A
        RET Z
        LD B,A
        LD HL,SRTPSLT
SRTPSWL:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,SRTPSWSK               ; Skip holes without sweeping address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (SRTPSST),HL
        LD (SRTPSBA),DE
        LD (SRTPSCAN),DE
        LD C,51
SRTPSWLP:
        LD HL,(SRTPSCAN)
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        AND 40H                     ; An unallocated record is already dead.
        JR Z,SRTPSWF
        LD A,(HL)
        AND 80H                     ; A marked allocation remains reachable.
        JR NZ,SRTPSWV
SRTPSWF:
        XOR A                       ; Clear stale tags and both ownership bits.
        LD (HL),A
        JR SRTPSWN
SRTPSWV:
        LD A,(HL)
        AND 7FH                     ; Keep the live record allocated for reuse.
        LD (HL),A
SRTPSWN:
        LD HL,(SRTPSCAN)
        LD DE,5
        ADD HL,DE
        LD (SRTPSCAN),HL
        DEC C
        JR NZ,SRTPSWLP
        LD HL,(SRTPSST)
        DJNZ SRTPSWL
        CALL SRTPSRB                ; Rebuild links after dead records were cleared.
        RET
SRTPSWSK:
        LD DE,3                     ; Advance over a released descriptor slot.
        ADD HL,DE
        DJNZ SRTPSWL
        CALL SRTPSRB
        RET

; Drain the bounded worklist.  A full queue is handled by the fallback scan.
SRTDRAIN:
        LD HL,(SRTMSTK)
        LD DE,SRTMKBS
        OR A
        SBC HL,DE
        RET Z
        LD HL,(SRTMSTK)
        LD DE,2
        OR A
        SBC HL,DE
        LD (SRTMSTK),HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        ; The shared pool no longer assigns closures a fixed address band.
        ; Consult the exact closure-start map instead of guessing from H.
        LD (SRTCLOBJ),HL
        PUSH HL
        CALL SRTCLSTA
        POP HL
        JR Z,SRTDPAIR
        CALL SRTMCLOS
        JR SRTDRAIN
SRTDPAIR:
        LD A,1
        CALL SRTMARKV
        JR SRTDRAIN

; Scan every marked pair after the bounded queue has overflowed.  Repeated
; passes compute the same fixed point as an unbounded worklist.
SRTFSCRN:
        LD A,(SRTPSLBN)
        OR A
        RET Z
        LD B,A
        LD HL,SRTPSLT
SRTGFS:
        LD A,(HL)                  ; A zero page byte denotes a released descriptor.
        OR A
        JR Z,SRTGFSK               ; Skip holes without scanning address zero.
        LD D,A                     ; Read the page number; its low address byte is zero.
        LD E,0
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        INC HL
        LD (SRTPSST),HL
        LD (SRTPSBA),DE
        LD (SRTPSCAN),DE
        LD C,51
SRTGFSLP:
        LD HL,(SRTPSCAN)
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        AND 80H                     ; Only marked records need another visit.
        JR Z,SRTGFSN
        LD DE,(SRTPSST)             ; Preserve the fallback cursor across validation.
        LD (SRTFSST),DE
        LD DE,(SRTPSBA)
        LD (SRTFSBA),DE
        LD DE,(SRTPSCAN)
        LD (SRTFSCAN),DE
        PUSH BC                     ; Preserve both slab and record counters.
        PUSH HL                     ; Preserve the record address across tracing.
        LD HL,(SRTPSCAN)
        CALL SRTMARKV               ; The queued value is the record start.
        POP HL
        POP BC
        LD DE,(SRTFSST)             ; Restore the slab cursor changed by SRTPCHK.
        LD (SRTPSST),DE
        LD DE,(SRTFSBA)
        LD (SRTPSBA),DE
        LD DE,(SRTFSCAN)
        LD (SRTPSCAN),DE
SRTGFSN:
        LD HL,(SRTPSCAN)
        LD DE,5
        ADD HL,DE
        LD (SRTPSCAN),HL
        DEC C
        JR NZ,SRTGFSLP
        LD HL,(SRTPSST)
        DJNZ SRTGFS
        RET
SRTGFSK:
        LD DE,3                     ; Advance over a released descriptor slot.
        ADD HL,DE
        DJNZ SRTGFS
        RET

; Scan a half-open byte range for the three-byte pattern payload,tag-one.
; The cursor may stop at end-3, but never at either of the two positions
; whose payload or tag byte would lie beyond the declared range.
SRTSCAN:
        LD (SRTSCP),HL
        LD (SRTSCE),DE
SRTSCLP:
        LD HL,(SRTSCP)
        LD DE,(SRTSCE)
        LD BC,2
        ADD HL,BC
        OR A
        SBC HL,DE
        JR NC,SRTSCEND
        LD HL,(SRTSCP)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        CP 1
        JR NZ,SRTSCNX
        EX DE,HL
        CALL SRTMARK
SRTSCNX:
        LD HL,(SRTSCP)
        INC HL
        LD (SRTSCP),HL
        JR SRTSCLP
SRTSCEND:
        RET

; Mark one pair and queue it for child scanning.
SRTMARK:
        LD A,1                      ; Validate the candidate as a pair value.
        CALL SRTPCHK
        RET C
        LD HL,(SRTPSAD)             ; Recover the validated record address.
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        AND 40H                     ; A swept or never-published record is ignored.
        RET Z
        LD A,(HL)
        AND 80H                     ; Already marked records are already queued.
        RET NZ
        LD A,(HL)
        OR 80H                      ; Set the mark bit without changing tags/allocation.
        LD (HL),A
        LD A,1
        LD (SRTMNEW),A             ; This object must be visited by the trace.
        LD HL,(SRTPSAD)             ; Queue the record address, not its state byte.
        LD DE,(SRTMSTK)
        LD A,D
        CP 0D4H
        JR NC,SRTMQOV              ; Preserve the mark and defer its children.
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (SRTMSTK),DE
        RET
SRTMQOV:
        LD A,1
        LD (SRTMOVER),A            ; The fallback scanner will revisit marked pairs.
        RET

; Trace the CAR and CDR pair edges of one queued record.
SRTMARKV:
        LD (SRTMVAL),HL
        LD A,1
        CALL SRTPCHK
        RET C
        ; Copy both payloads before marking either edge; SRTMARK may use HL/DE.
        LD HL,(SRTMVAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTQCAR),DE
        LD HL,(SRTMVAL)
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (SRTQCDR),DE
        LD HL,(SRTMVAL)
        LD DE,4
        ADD HL,DE
        LD A,(HL)
        LD (SRTQFLG),A
        AND 7                       ; The CAR tag occupies the low three bits.
        LD (SRTQCTAG),A
        LD A,(SRTQFLG)
        SRL A                       ; Shift the CDR tag down from bits three to five.
        SRL A
        SRL A
        AND 7
        LD (SRTQDTAG),A
        LD A,(SRTQCTAG)
        LD HL,(SRTQCAR)
        CALL SRTMVALU                ; Trace pair or closure CAR values.
SRTMVC:
        LD A,(SRTQDTAG)
        LD HL,(SRTQCDR)
        JP SRTMVALU

; Write a value using CP/M function two, including nested pair structure.
SRTWRVAL:
        CP 3
        JP Z,SRTWRNUM
        CP 1
        JP Z,SRTWPAIR
        CP 4
        JP Z,SRTWRLIT
        CP 5
        JP Z,SRTWRSTR
        OR A
        JP NZ,SRTERROR
        LD A,H
        CP 0FFH
        JP Z,SRTWCHAR              ; Byte characters share the scalar tag with booleans.
        PUSH HL
        LD DE,0FE02H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWNIL
        PUSH HL
        LD DE,0FE03H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWEOFV
        PUSH HL
        LD DE,0FE04H
        OR A
        SBC HL,DE
        POP HL
        JR Z,SRTWUNS
        PUSH HL                    ; Compare the false payload without changing it.
        LD DE,0FE00H               ; #f is the reserved false scalar.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; Test whether the payload is exactly FE00H.
        POP HL                     ; Restore the value for the following formatter.
        JR Z,SRTWBOOL              ; Preserve the established #t spelling.
        PUSH HL                    ; Compare the true payload without changing it.
        LD DE,0FE01H               ; #t is the reserved true scalar.
        OR A                       ; Clear carry before the subtraction.
        SBC HL,DE                  ; Test whether the payload is exactly FE01H.
        POP HL                     ; Restore the value for the following formatter.
        JR Z,SRTWBOOL              ; Preserve the established #t spelling.
        PUSH HL
        XOR A
        CALL NCLASS
        POP HL
        JP NC,SRTFPRN
SRTWBOOL:
        LD DE,SRTWQF
        LD A,H
        CP 0FEH
        JR NZ,SRTWMSG
        LD A,L
        OR A
        JR Z,SRTWMSG
        LD DE,SRTWQT
SRTWMSG:
        LD C,9
        JP 5

SRTWNIL:
        LD DE,SRTWNILT
        LD C,9
        JP 5

SRTWUNS:
        LD DE,SRTWUNST
        LD C,9
        JP 5

SRTWEOFV:
        LD DE,SRTWEOF
        LD C,9
        JP 5

; Print a character raw for display or as a hexadecimal reader spelling.
SRTWCHAR:
        LD A,(SRTWMODE)
        OR A
        JR Z,SRTWOUT
        LD A,35                    ; Prefix the readable character spelling with '#'.
        CALL SRTCH                  ; Send the hash byte through the BDOS-safe writer.
        LD A,92                    ; The second prefix byte is a backslash.
        CALL SRTCH                  ; Send the backslash through the BDOS-safe writer.
        LD A,'x'                    ; Hexadecimal spelling is valid for every byte.
        CALL SRTCH                  ; Send the hexadecimal marker.
        LD A,L                      ; Load the byte payload for hexadecimal output.
        CALL SRTWBYTE               ; Emit its two lower-case hexadecimal digits.
        RET                         ; The complete reader spelling is now emitted.
SRTWOUT:
        LD A,L                     ; Emit the byte payload itself.
        JP SRTCH

; Emit the two hexadecimal digits in one byte held in A.
SRTWBYTE:
        LD (SRTINB),A              ; Preserve the byte while selecting its nibbles.
        AND 0F0H                   ; Keep the high nibble of the byte.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        RRCA                       ; Shift the high nibble into the low position.
        CALL SRTWHXD               ; Emit the selected high-nibble digit.
        LD A,(SRTINB)              ; Restore the original byte for its low nibble.
        AND 0FH                    ; Keep the low nibble.
        JP SRTWHXD                 ; Emit the selected low-nibble digit.

; Look up one hexadecimal digit and send it to the CP/M character writer.
SRTWHXD:
        LD E,A                     ; Use the nibble as a table offset.
        LD D,0                     ; Form a word-sized table index.
        LD HL,SRTWHX               ; Point at the lower-case digit table.
        ADD HL,DE                  ; Select the requested digit.
        LD A,(HL)                  ; Load the selected digit character.
        JP SRTCH                   ; Send it while preserving the formatter state.

SRTWPAIR:
        PUSH HL                     ; CP/M output is allowed to clobber HL.
        LD A,'('
        CALL SRTCH
        POP HL
        PUSH HL                     ; Keep the outer pair while printing its CAR.
        LD A,1                       ; The outer value has already selected pair output.
        CALL SRTCARV                ; Decode the packed CAR field through one helper.
        JP C,SRTERROR               ; A corrupt pair cannot be printed safely.
        CALL SRTWRVAL
        POP HL
        PUSH HL                     ; Keep the outer pair while inspecting its CDR.
        LD A,1                       ; Decode the packed CDR tag and payload together.
        CALL SRTCDRV
        JP C,SRTERROR               ; A corrupt pair cannot be printed safely.
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQATAG)
        CP 1
        JR NZ,SRTWRDOT
        LD HL,(SRTQAVAL)
        CALL SRTPCHK
        JR C,SRTWRDOT
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWTAIL
        POP HL
        JR SRTWCLS
SRTWRDOT:
        LD A,(SRTQATAG)
        OR A
        JR NZ,SRTWRDV
        LD HL,(SRTQAVAL)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR Z,SRTWRNIL
SRTWRDV:
        LD A,' '
        CALL SRTCH
        LD A,'.'
        CALL SRTCH
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWRVAL
        POP HL
        JR SRTWCLS
SRTWRNIL:
        POP HL
        JR SRTWCLS
SRTWCLS:
        LD A,')'
        JP SRTCH

; Print the tail of a proper list without opening another parenthesis.
SRTWTAIL:
        PUSH HL                     ; Preserve this pair across its CAR output.
        LD A,1
        CALL SRTCARV                ; Read the next CAR from the packed record.
        JP C,SRTERROR
        CALL SRTWRVAL
        POP HL
        PUSH HL                     ; Preserve this pair while inspecting its CDR.
        LD A,1
        CALL SRTCDRV                ; Read the next CDR and its packed tag.
        JP C,SRTERROR
        LD (SRTQATAG),A
        LD (SRTQAVAL),HL
        LD A,(SRTQATAG)
        CP 1
        JR NZ,SRTWTNIL
        LD HL,(SRTQAVAL)
        CALL SRTPCHK
        JR C,SRTWTDOT
        LD A,' '
        CALL SRTCH
        LD HL,(SRTQAVAL)
        CALL SRTWTAIL
        POP HL
        RET
SRTWTNIL:
        OR A
        JR NZ,SRTWTDOT
        LD HL,(SRTQAVAL)
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR NZ,SRTWTDOT
        POP HL
        RET
SRTWTDOT:
        LD A,' '
        CALL SRTCH
        LD A,'.'
        CALL SRTCH
        LD A,' '
        CALL SRTCH
        LD A,(SRTQATAG)
        LD HL,(SRTQAVAL)
        CALL SRTWRVAL
        POP HL
        RET

SRTWRSTR:
        PUSH HL                     ; Preserve the literal pointer across BDOS.
        LD A,'"'
        CALL SRTCH
        POP HL
        CALL SRTWRLIT
        LD A,'"'
        JP SRTCH
SRTWRLIT:
        LD B,(HL)
        INC HL
SRTWLLP:
        LD A,B
        OR A
        RET Z
        LD A,(HL)
        INC HL
        PUSH HL                     ; Preserve the literal cursor across BDOS.
        PUSH BC                     ; Preserve the remaining count across BDOS.
        CALL SRTCH
        POP BC
        POP HL
        DJNZ SRTWLLP
        RET

SRTWRNUM:
        XOR A
        LD (SRTWBEG),A
        BIT 7,H
        JR Z,SRTWNP
        LD A,'-'
        CALL SRTCH
        XOR A
        SUB L
        LD L,A
        LD A,0                    ; Preserve the low-byte borrow for negating H.
        SBC A,H
        LD H,A
SRTWNP:
        LD DE,10000
        CALL SRTWDIG
        LD DE,1000
        CALL SRTWDIG
        LD DE,100
        CALL SRTWDIG
        LD DE,10
        CALL SRTWDIG
        LD A,1
        LD (SRTWBEG),A
        LD DE,1
        JP SRTWDIG
SRTWDIG:
        LD B,0
SRTWDL:
        OR A
        SBC HL,DE
        JR C,SRTWDD
        INC B
        JR SRTWDL
SRTWDD:
        ADD HL,DE
        LD A,B
        OR A
        JR NZ,SRTWDOUT
        LD A,(SRTWBEG)
        OR A
        RET Z
SRTWDOUT:
        LD A,1
        LD (SRTWBEG),A
        LD A,B
        ADD A,'0'
        JP SRTCH

; Preserve the caller's numeric remainder and procedure continuation across a
; provider byte-gateway call.  SRTOUTV is a three-byte JP vector: CP/M keeps
; its default target, while a native or WASM host may patch the target before
; entering the generated image.  The vector target receives A=the byte and
; must return through the CALL with the stack balanced; SRTCH restores every
; other caller-visible register below.
SRTCH:
        PUSH AF                    ; Retain the value tag and flags.
        PUSH BC                    ; Retain loop counters.
        PUSH DE                    ; Retain the decimal divisor or data pointer.
        PUSH HL                    ; Retain the decimal remainder or literal cursor.
        PUSH IX                    ; Retain the primitive return continuation.
        PUSH IY                    ; Retain any active indexed runtime state.
        CALL SRTOUTV               ; Dispatch through the provider byte-gateway vector.
        POP IY                     ; Restore the caller's indexed state.
        POP IX                     ; Restore the primitive continuation.
        POP HL                     ; Restore the numeric remainder.
        POP DE                     ; Restore the divisor or data pointer.
        POP BC                     ; Restore loop counters.
        POP AF                     ; Restore the original flags and value tag.
        RET                        ; Continue formatting or return to the primitive.

; Read one console byte while preserving the runtime continuation and cursors.
; SRTINV is the matching JP vector.  Its target returns A=the byte and may
; clobber the ordinary working registers; SRTIN restores the caller state.
SRTIN:
        PUSH BC                    ; Preserve the caller's packet count and counters.
        PUSH DE                    ; Preserve the caller's data pointer or divisor.
        PUSH HL                    ; Preserve the caller's value payload or cursor.
        PUSH IX                    ; Preserve the generated continuation across BDOS.
        PUSH IY                    ; Preserve indexed runtime state used by collection.
        CALL SRTINV                ; Dispatch through the provider byte-gateway vector.
        LD (SRTINB),A              ; Stage the byte before restoring caller registers.
        POP IY                     ; Restore indexed runtime state.
        POP IX                     ; Restore the primitive return continuation.
        POP HL                     ; Restore the caller's payload or cursor.
        POP DE                     ; Restore the caller's pointer or divisor.
        POP BC                     ; Restore the caller's packet count and counters.
        LD A,(SRTINB)              ; Return the byte obtained from the console.
        RET                        ; The primitive maps Control-Z to the EOF value.

; Running-program byte-gateway vectors.  A JP target is deliberately mutable:
; the CP/M image uses the local BDOS adapters below, while a Triptych native or
; WASM host can install a machine-profile entry point without changing the
; generated program or its language semantics.
SRTOUTV:
        JP SRTCPMO
SRTINV:
        JP SRTCPMI

; CP/M provider adapters.  These are the only generated-runtime instructions
; that know the BDOS console ABI.  A non-CP/M provider does not enter them.
SRTCPMO:
        LD E,A                     ; BDOS function two takes the character in E.
        LD C,2                     ; Console character output.
        CALL 5                     ; BDOS may overwrite general registers.
        RET

SRTCPMI:
        LD C,1                     ; BDOS function one reads one console byte.
        CALL 5                     ; CP/M returns the byte in A and may clobber registers.
        RET

SRTWQF:    DB "#f$"
SRTWQT:    DB "#t$"
SRTWNILT: DB "()$"
SRTWEOF:   DB "#<eof>$"
SRTWUNST:  DB "#<unspecified>$"
SRTWHX:    DB "0123456789abcdef"

SRTQSP:   DW SRTQBASE
SRTQNXT:  DW 0
SRTQCAR:  DW 0
SRTQCDR:  DW 0
SRTQAVAL: DW 0
SRTQPAIR: DW 0
SRTQCTAG: DB 0
SRTQDTAG: DB 0
SRTQFLG:  DB 0                  ; Packed pair flags retained while tracing or printing.
SRTPTAG:  DB 0                  ; Temporary packed CAR tag during pair construction.
SRTQATAG: DB 0
SRTQNR:   DB 0
SRTQDOTR: DB 0
SRTQACTV: DB 0                ; Nonzero while the list accumulator is a root.
SRTCRCAR: DW 0                  ; CAR payload rooted across a collecting allocation.
SRTCRCDR: DW 0                  ; CDR payload rooted across a collecting allocation.
SRTCRCTA: DB 0                  ; CAR tag for the pending constructor root.
SRTCRDTA: DB 0                  ; CDR tag for the pending constructor root.
SRTCRON:  DB 0                  ; Nonzero while constructor roots are active.
SRTBADDR: DW 0                  ; Binding pointer being validated or traced.
SRTBFLG:  DB 0                  ; Binding flags retained across value decoding.
SRTROOTP: DW 0                  ; Exact-root cursor shared by range walkers.
SRTROOTE: DW 0                  ; Exclusive end for an exact-root range.
SRTROOTV: DW 0                  ; Payload address of the current root record.
SRTROOTT: DB 0                  ; Tag of the current exact-root record.
SRTENVP:  DW 0                  ; Environment-map cursor during root tracing.
SRTENVN:  DB 0                  ; Remaining environment entries.
SRTCLOBJ: DW 0                  ; Closure object being validated.
SRTCLDSC: DW 0                  ; Descriptor pointer read from a closure header.
SRTCLN:   DB 0                  ; Closure slot count from its descriptor.
SRTCLMP:  DW 0                  ; Capture-mask cursor during closure tracing.
SRTCLMV:  DB 0                  ; Current capture-mask byte.
SRTCLSLT: DB 0                  ; Slot index represented by the mask cursor.
SRTCLER:  DB 0                  ; Nonzero reports a closure worklist overflow.
SRTCLCUR: DW 0                  ; High-water cursor for upward closure allocation.
SRTCLSCN: DW 0                  ; Address-unit cursor for closure scans.
SRTCFREE:  DS 130                ; Heads for rounded four-byte closure classes.
SRTCLOWN:  DS 128                ; Class owner for each logical closure page.
                                  ; Zero is free; 41H owns a two-page run; FFH continues it.
SRTCLUSE:  DS 128                ; Live object count for each owned page.
SRTCLPBA:  DS 128                ; Physical page high byte for each owner entry.
SRTCLCAP:  DB 64,32,21,16,12,10,9,8,7,6,5,5,4,4,4,4
            DB 3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2
            DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
            DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
SRTCLFP:  DW 0                  ; Active closure free-list head address.
SRTCLBAS:  DW 0                 ; Base of the active closure allocation.
SRTCLPGI:   DB 0                 ; Closure page index being selected or rebuilt.
SRTCLPGN:   DB 0                 ; Slots remaining while a slab chain is built.
SRTCLPGQ:   DB 0                 ; Remaining slots during a page sweep.
SRTCLPGH:   DB 0                 ; Physical high byte during owner lookup.
SRTCLPGA:   DW 0                 ; Physical base of the active closure page.
SRTCLPGE:   DW 0                 ; Exclusive end of a selected page or run.
SRTCLPGF:   DW 0                 ; Current object while building a slab chain.
SRTCLPGL:   DW 0                 ; Next object while building a slab chain.
SRTCLSTR:   DW 0                 ; Stride of the class currently being swept.
SRTBHEAD: DW 0                  ; Head of the reclaimed three-byte binding list.
SRTBEND:  DW 0                  ; End of the current binding page for reports.
SRTBPGP:  DW 0                  ; Next three-byte binding slot in the current page.
SRTBPGED: DW 0                  ; Exclusive end of the current binding page.
SRTBPGBA: DW 0                  ; Physical base of the current binding page.
SRTBPGC:  DW 0                  ; Physical base saved across a binding sweep.
SRTBPGN:  DB 0                  ; Number of pages assigned to bindings.
SRTBPGI:  DB 0                  ; Binding page index during a sweep.
SRTBPGS:  DS 128                ; Physical page high bytes assigned to bindings.
SRTBPFRE: DW 0                  ; Page-local free-chain head during a sweep.
SRTBPLST: DW 0                  ; Tail of the page-local free chain.
SRTBPLIV: DB 0                  ; Live binding count on the current page.
SRTBSCAN: DW 0                  ; Binding address during sweep.
SRTBMAP:  DW 0                  ; Binding bitmap byte during sweep.
SRTBMSK:  DB 0                  ; Binding bitmap bit during sweep.
SRTBLEFT: DW 0                  ; Binding bytes left in the sweep interval.
SRTCLMAP: DW 0                  ; Closure mark-map cursor during sweep.
SRTCLMKV: DB 0                  ; Closure mark bit during sweep.
SRTMSTK:  DW SRTMKBS
SRTMOVER: DB 0                    ; Nonzero means the bounded mark queue filled.
SRTMNEW:  DB 0                    ; Nonzero means a fallback pass marked an object.
SRTSCP:   DW 0
SRTSCE:   DW 0
SRTMVAL:  DW 0
SRTMTAG:  DB 0
SRTWRP:   DW 0
SRTWBEG:  DB 0
SRTWMODE: DB 0                    ; Zero displays contents; one writes readable syntax.

; Pair-class table and scan cursors.  Each entry is a page-aligned slab base.
SRTPSLBN: DB 0                    ; Number of five-byte pair slabs currently assigned.
SRTPSLT:  DS 384                  ; One hundred twenty-eight three-byte descriptors.
SRTPSLHD: DB 0                    ; One-based index of the first available slab.
SRTPSLIM: DB 0                    ; Maximum descriptor slots for the page domain.
SRTPSNXT: DB 0                    ; Temporary free-record or slab-list successor.
SRTPSIDX: DB 0                    ; Current descriptor index during a rebuild.
SRTPSLV:  DB 0                    ; Live-record count while rebuilding one slab.
SRTPSFST: DW 0                    ; First free record while chains are rebuilt.
SRTPSFLK: DW 0                    ; Last free record while chains are rebuilt.
SRTPSDP:   DW 0                   ; Current slab descriptor during a rebuild.
SRTPSBA:   DW 0                   ; Current slab base during allocation or tracing.
SRTPSCAN:  DW 0                   ; Current five-byte record during a slab walk.
SRTPSAD:   DW 0                   ; Candidate pair address being validated or marked.
SRTPSST:   DW 0                   ; Next slab-table entry saved during a record walk.
SRTFSST:   DW 0                   ; Fallback scan's saved descriptor cursor.
SRTFSBA:   DW 0                   ; Fallback scan's saved slab base.
SRTFSCAN:  DW 0                   ; Fallback scan's saved record cursor.

; One-byte staging for a BDOS console input call that may clobber registers.
SRTINB:    DB 0
