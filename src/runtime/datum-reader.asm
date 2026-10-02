; Bounded runtime datum reader.
;
; This unit accepts scalar datums and delegates compound construction to the
; adjacent datum modules.  The shared input helpers leave a delimiter or
; sticky EOF for the next operation.  Symbol tokens are interned separately.

; Read one datum from the current input port or an explicit input port.
SRTDRRD:
        CALL SRTINSET               ; No argument selects current input; one names a port.
SRTDRST:
        LD A,1                      ; Mark the reader active for root cleanup.
        LD (SRTDRACT),A
        XOR A                       ; No construction roots are live yet.
        LD (SRTDRRC),A
        LD (SRTDRFC),A          ; No list, vector or quote frame is open.
        LD (SRTDRVC),A            ; No temporary value slots are occupied.
        LD (SRTDRLEN),A           ; No numeric token bytes have been consumed.
        XOR A                     ; No nested value has produced EOF yet.
        LD (SRTDEOF),A
        CALL SRTDRVAL             ; Parse one complete scalar or list datum.
        JP C,SRTERROR             ; A checked parser failure propagates outward.
        JP SRTDRDON               ; Top-level cleanup preserves the lookahead.

; Parse one datum and return its ordinary A:HL value without ending the read.
SRTDRVAL:
        XOR A                     ; The caller must inspect EOF from this value.
        LD (SRTDEOF),A
        CALL SRTDRSK              ; Whitespace and comments precede every datum.
        JR C,SRTDREOF             ; EOF is a value at the top level.
        CALL SRTDRTK              ; Consume the first non-space input byte.
        JP C,SRTDREOF             ; A provider race still produces EOF.
        LD (SRTDRDIG),A           ; Preserve the first token byte for numeric parsing.
        CP '#'                     ; Dispatch booleans and characters together.
        JP Z,SRTDRHS
        CP '('                     ; Lists are constructed by datum-lists.asm.
        JR Z,SRTDRLV
        CP 34                      ; Strings are built by datum-strings.asm.
        JR Z,SRTDRSV
        CP ')'                     ; A close without an open list is malformed.
        JP Z,SRTERROR
        CP 39                      ; Quote syntax waits for the quote increment.
        JP Z,SRTERROR
        CP '0'                     ; A digit-leading token is an exact integer.
        JR C,SRTDRNSG
        CP ':'
        JP C,SRTDNFST
SRTDRNSG:
        CP '+'                     ; A sign followed by a digit is numeric.
        JR Z,SRTDRSGN
        CP '-'                     ; A sign followed by a digit is numeric.
        JR Z,SRTDRSGN
        JP SRTDRSYM                ; Other tokens use the bounded symbol interner.
SRTDRSGN:
        CALL SRTDRPK               ; Inspect the byte after the possible sign.
        JP C,SRTDRSYM              ; A lone sign is an ordinary symbol.
        LD (SRTDRNXT),A            ; Keep the peeked byte across the delimiter test.
        CALL SRTDISDL              ; A delimiter leaves the sign as a symbol.
        JP Z,SRTDRSYM
        LD A,(SRTDRNXT)
        CP '0'
        JP C,SRTDRSYM
        CP ':'
        JP C,SRTDNFST              ; The existing exact-integer parser owns digits.
        JP SRTDRSYM
SRTDRLV:
        CALL SRTDRLST             ; Return the completed list as a raw value.
        RET
SRTDRSV:
        CALL SRTDRSTR             ; Return the completed string as a raw value.
        RET

; Return the canonical EOF value after an empty input or sticky provider EOF.
SRTDREOF:
        LD A,1                     ; An enclosing list rejects EOF before close.
        LD (SRTDEOF),A
        XOR A                       ; EOF uses the scalar logical tag.
        LD HL,0FE03H                ; FE03 is the runtime EOF singleton.
        RET                          ; Top-level SRTDRST performs normal cleanup.

; Parse the dispatch byte following a hash marker.
SRTDRHS:
        CALL SRTDRTK              ; Read t, f or the character backslash.
        JP C,SRTERROR               ; A missing dispatch byte is malformed.
        CP 't'                      ; #t is the canonical true value.
        JP Z,SRTDRT
        CP 'f'                      ; #f is the canonical false value.
        JP Z,SRTDRF
        CP 92                       ; Backslash introduces one byte character data.
        JP Z,SRTDRCH
        CP '('                      ; #(...) is a bounded datum vector.
        JP Z,SRTDRVEC
        JP SRTERROR                 ; Other dispatch forms wait for later units.

; Return true after checking that the token has ended at a delimiter.
SRTDRT:
        CALL SRTDCKDL          ; A boolean cannot be a prefix of a symbol.
        JP NZ,SRTERROR
        XOR A                       ; Boolean values use the scalar tag.
        LD HL,0FE01H                ; FE01 is canonical #t.
        RET

; Return false after checking that the token has ended at a delimiter.
SRTDRF:
        CALL SRTDCKDL          ; A boolean cannot be a prefix of a symbol.
        JP NZ,SRTERROR
        XOR A                       ; Boolean values use the scalar tag.
        LD HL,0FE00H                ; FE00 is canonical #f.
        RET

; Read a character spelling after #\: one printable byte, xHH, space or
; newline.  The spelling is collected in the symbol buffer until a delimiter.
SRTDRCH:
        XOR A                       ; Start an empty spelling in the symbol buffer.
        LD (SRTDRLEN),A
        CALL SRTDRTK              ; The first byte may itself be a delimiter.
        JP C,SRTERROR               ; A missing character is malformed.
        CP 33                       ; Control bytes and space need a name.
        JP C,SRTERROR
        CP 127                      ; DEL and high bytes need the hex spelling.
        JP NC,SRTERROR
SRTDCHLP:
        CALL SRTSYPUT               ; Append the byte; carry after 31 bytes.
        JP C,SRTERROR               ; No accepted spelling is that long.
        CALL SRTDCKDL               ; Z means a delimiter or EOF ends the spelling.
        JR Z,SRTDCHND
        CALL SRTDRTK                ; Consume the next spelling byte.
        JP C,SRTERROR               ; A peeked byte cannot turn into provider EOF.
        JR SRTDCHLP
SRTDCHND:
        LD HL,SRTDRSB               ; HL addresses the first spelling byte.
        LD A,(SRTDRLEN)             ; Select the spelling form by its length.
        DEC A                       ; A single byte denotes itself.
        JR Z,SRTDCHV1
        CP 2                        ; Three bytes may be the xHH spelling.
        JR NZ,SRTDCHNM
        LD A,(HL)                   ; The hex form starts with lowercase x.
        CP 'x'
        JR NZ,SRTDCHNM
        INC HL                      ; Decode the high hexadecimal digit.
        LD A,(HL)
        CALL SRTDSHX
        JP C,SRTERROR               ; Reject a malformed hexadecimal digit.
        RLCA                        ; Move the nibble into bits 7..4.
        RLCA
        RLCA
        RLCA
        LD B,A                      ; Keep the high nibble while decoding the low.
        INC HL                      ; Decode the low hexadecimal digit.
        LD A,(HL)
        CALL SRTDSHX
        JP C,SRTERROR               ; Reject a malformed hexadecimal digit.
        OR B                        ; Join both nibbles into the character byte.
        JR SRTDCHVL
SRTDCHNM:
        LD HL,SRTDCSPN              ; Try the exact space name.
        CALL SRTDCMAT
        JR Z,SRTDCHVL               ; A holds byte 32 after a match.
        LD HL,SRTDCNLN              ; Newline is the only other accepted name.
        CALL SRTDCMAT
        JP NZ,SRTERROR              ; Unknown names are malformed.
        JR SRTDCHVL                 ; A holds byte 10 after a match.
SRTDCHV1:
        LD A,(HL)                   ; Return the single spelling byte.
SRTDCHVL:
        LD L,A                      ; Characters use the low payload byte.
        LD H,0FFH                   ; FFxx is the reserved character range.
        XOR A                       ; Characters use the scalar logical tag.
        RET

; Compare the collected spelling with the length-prefixed name at HL.  Z
; reports an exact match and returns the byte stored after the name in A.
SRTDCMAT:
        LD A,(SRTDRLEN)             ; Names must match the full spelling length.
        CP (HL)
        RET NZ
        LD B,A                      ; B counts the bytes left to compare.
        LD DE,SRTDRSB               ; DE walks the collected spelling.
SRTDCMLP:
        INC HL                      ; Advance to the next name byte.
        LD A,(DE)                   ; Compare one spelling byte.
        CP (HL)
        RET NZ                      ; A mismatch leaves NZ for the caller.
        INC DE
        DJNZ SRTDCMLP
        INC HL                      ; The character value follows the name.
        LD A,(HL)                   ; Loading it keeps the final Z result.
        RET

SRTDCSPN: DB 5,"space",32           ; #\space denotes byte 32.
SRTDCNLN: DB 7,"newline",10         ; #\newline denotes byte 10.

; Skip spaces and semicolon comments.  A delimiter remains in lookahead.
SRTDRSK:
SRTDSLP:
        CALL SRTDRPK              ; Peek without consuming the next datum byte.
        RET C                       ; Sticky EOF ends the skip operation.
        CP ' '                      ; Space is horizontal whitespace.
        JR Z,SRTDSTK
        CP 9                        ; Tab is horizontal whitespace.
        JR Z,SRTDSTK
        CP 10                       ; LF is a logical line ending.
        JR Z,SRTDSTK
        CP 13                       ; Keep CR accepted for provider compatibility.
        JR Z,SRTDSTK
        CP ';'                      ; A semicolon starts a line comment.
        JR Z,SRTDCMT
        OR A                        ; A non-space byte remains in lookahead.
        RET
SRTDSTK:
        CALL SRTDRTK              ; Consume the whitespace byte.
        JR C,SRTDSLP              ; EOF after whitespace is still ordinary EOF.
        JR SRTDSLP
SRTDCMT:
        CALL SRTDRTK              ; Consume the semicolon itself.
SRTDCLP:
        CALL SRTDRTK              ; Consume comment bytes through the newline.
        JR C,SRTDSLP              ; EOF terminates a final comment cleanly.
        CP 10                       ; Logical LF ends the comment.
        JR NZ,SRTDCLP
        JR SRTDSLP

; Peek one logical input byte and return it in A, with carry for sticky EOF.
SRTDRPK:
        LD A,(SRTINST)           ; Inspect the shared port lookahead state.
        CP 1
        JR Z,SRTDPKBY          ; A pending byte needs no provider call.
        CP 2
        JR Z,SRTDPEOF           ; Sticky EOF is returned without blocking.
        CALL SRTINNXT              ; Obtain one byte through the port adapter.
        CALL SRTDRASC              ; Datum input is restricted to ASCII bytes.
        LD A,H                      ; EOF has the reserved FE high payload byte.
        CP 0FEH
        JR NZ,SRTDPKCH         ; A different high byte is a character.
        LD A,L                      ; Check the canonical EOF low payload byte.
        CP 03H
        JR Z,SRTDPEOF           ; SRTINNXT has already made EOF sticky.
SRTDPKCH:
        LD A,L                      ; Retain the logical byte for the next take.
        LD (SRTINPBY),A
        LD A,1                      ; State one means a pending logical byte.
        LD (SRTINST),A
SRTDPKBY:
        LD A,(SRTINPBY)           ; Return the retained byte with carry clear.
        OR A                        ; OR clears carry without changing the byte.
        RET
SRTDPEOF:
        SCF                         ; Carry distinguishes EOF from a byte value.
        RET

; Take one logical input byte and return it in A, with carry for sticky EOF.
SRTDRTK:
        LD A,(SRTINST)           ; Consume a byte already retained by peek.
        CP 1
        JR Z,SRTDTKBY
        CP 2
        JR Z,SRTDTEOF           ; Sticky EOF remains EOF on every take.
        CALL SRTINNXT              ; Obtain an unbuffered logical value.
        CALL SRTDRASC              ; Datum input is restricted to ASCII bytes.
        LD A,H                      ; Inspect the returned value's high payload.
        CP 0FEH
        JR NZ,SRTDTKCH         ; A character has high byte FF.
        LD A,L                      ; Confirm the canonical EOF low payload byte.
        CP 03H
        JR Z,SRTDTEOF           ; SRTINNXT has already recorded sticky EOF.
SRTDTKCH:
        LD A,L                      ; Return the unbuffered logical character byte.
        OR A                        ; Clear carry for a normal byte result.
        RET
SRTDTKBY:
        XOR A                       ; Empty the shared pending-byte state.
        LD (SRTINST),A
        LD A,(SRTINPBY)            ; Return the retained character byte.
        OR A                        ; Clear carry for a normal byte result.
        RET
SRTDTEOF:
        SCF                         ; Carry reports the sticky EOF state.
        RET

; Return Z when A is a token delimiter and NZ otherwise.
SRTDISDL:
        CP ' '                      ; Space terminates a token.
        JR Z,SRTDDEL
        CP 9                        ; Tab terminates a token.
        JR Z,SRTDDEL
        CP 10                       ; LF terminates a token.
        JR Z,SRTDDEL
        CP 13                       ; CR terminates a token.
        JR Z,SRTDDEL
        CP 34                       ; A string opener terminates a preceding token.
        JR Z,SRTDDEL
        CP '('                      ; An opening list delimiter ends a scalar.
        JR Z,SRTDDEL
        CP ')'                      ; A closing list delimiter ends a scalar.
        JR Z,SRTDDEL
        CP 39                       ; Apostrophe ends a scalar token.
        JR Z,SRTDDEL
        CP ';'                      ; A comment begins at a token boundary.
        JR Z,SRTDDEL
        LD A,1                      ; Non-delimiters return a nonzero flag.
        OR A                        ; Clear carry while setting NZ.
        RET
SRTDDEL:
        XOR A                       ; Z identifies a delimiter to the caller.
        RET

; Check the next byte without consuming a delimiter.
SRTDCKDL:
        CALL SRTDRPK              ; EOF also terminates a complete scalar token.
        JR C,SRTDCKOK
        JP SRTDISDL               ; Return the delimiter predicate directly.
SRTDCKOK:
        XOR A                       ; EOF is an accepted token boundary.
        RET

; Reject non-ASCII character bytes while keeping the direct read-char contract.
SRTDRASC:
        LD A,H                      ; Only FFxx values are raw character bytes.
        CP 0FFH
        RET NZ                      ; EOF and other scalar values are left alone.
        LD A,L
        CP 80H                      ; Seven-bit input is the datum-reader policy.
        RET C
        JP SRTERROR

; Start a signed decimal exact-integer token with its first byte in A.
SRTDNFST:
        XOR A                       ; Clear the accumulating magnitude.
        LD (SRTDRNUM),A
        LD (SRTDRNUM+1),A
        LD A,1                      ; Count the first spelling byte.
        LD (SRTDRLEN),A
        XOR A                       ; Positive sign is the default.
        LD (SRTDRSG),A
        LD (SRTDRSN),A             ; A sign by itself is not a number.
        LD A,(SRTDRDIG)              ; The first byte was staged by the caller.
        JP SRTDNBYT

; The dispatch path stages the first token byte here before entering parsing.
SRTDNBYT:
        CP '+'                       ; A leading plus changes no magnitude.
        JR Z,SRTDPLS
        CP '-'                       ; A leading minus is applied after parsing.
        JR Z,SRTDMNS
        CALL SRTDADD             ; The first byte must be a decimal digit.
        JP C,SRTERROR
        LD A,1                       ; Record that at least one digit was seen.
        LD (SRTDRSN),A
        JR SRTDNLP
SRTDPLS:
        XOR A                        ; Keep the explicit positive sign.
        LD (SRTDRSG),A
        JR SRTDNLP
SRTDMNS:
        LD A,1                       ; Record the negative sign for final folding.
        LD (SRTDRSG),A
        JR SRTDNLP

; Consume subsequent token digits until a delimiter or EOF is encountered.
SRTDNLP:
        CALL SRTDRPK              ; Leave the terminating delimiter pending.
        JR C,SRTDNDON           ; EOF finishes an unterminated final integer.
        CALL SRTDISDL              ; A delimiter ends the numeric spelling.
        JR Z,SRTDNDON
        CALL SRTDRTK              ; Consume the next non-delimiter byte.
        JP C,SRTERROR               ; A provider EOF cannot follow a peeked byte.
        LD (SRTDRDIG),A             ; Preserve it while checking token capacity.
        LD A,(SRTDRLEN)
        INC A
        CP 65                       ; A numeric spelling is limited to 64 bytes.
        JP NC,SRTERROR
        LD (SRTDRLEN),A
        LD A,(SRTDRDIG)
        CALL SRTDADD             ; Every remaining byte must be a digit.
        JP C,SRTERROR
        LD A,1                       ; Publish that the token contains a digit.
        LD (SRTDRSN),A
        JR SRTDNLP

; Add the decimal digit in A to the bounded 16-bit magnitude.
SRTDADD:
        CP '0'                       ; Reject bytes below ASCII zero.
        RET C
        CP ':'                       ; ASCII colon is one past the digit range.
        JR C,SRTDDIG
        SCF                         ; Bytes after nine are malformed digits.
        RET
SRTDDIG:
        SUB '0'                      ; Convert the digit to an unsigned value.
        LD (SRTDRDIG),A              ; Retain it while multiplying the magnitude.
        LD HL,(SRTDRNUM)             ; HL is the current accumulated magnitude.
        LD B,H                       ; BC becomes two times the old magnitude.
        LD C,L
        ADD HL,HL                    ; Multiply the accumulator by two.
        JR C,SRTDOV                  ; Reject overflow before widening the product.
        LD B,H                       ; Keep two times the value for the final add.
        LD C,L
        ADD HL,HL                    ; Multiply by four.
        JR C,SRTDOV                  ; Reject overflow before the next doubling.
        ADD HL,HL                    ; Multiply by eight.
        JR C,SRTDOV                  ; Reject overflow before adding the final digit.
        ADD HL,BC                    ; Eight plus two gives ten times the value.
        JR C,SRTDOV                  ; Carry means the 16-bit magnitude overflowed.
        LD A,(SRTDRDIG)              ; Restore the converted decimal digit.
        LD C,A                       ; Add the digit as a 16-bit value.
        LD B,0
        ADD HL,BC                    ; Check carry for the final digit addition.
        JR C,SRTDOV
        LD (SRTDRNUM),HL             ; Publish the new magnitude for the next digit.
        OR A                         ; Clear carry for the successful digit.
        RET
SRTDOV:
        SCF                          ; Report an overflowing or malformed digit.
        RET

; Finish the exact-integer token and apply its sign with a signed-16 bound.
SRTDNDON:
        LD A,(SRTDRSN)             ; A sign without a digit is malformed.
        OR A
        JP Z,SRTERROR
        LD HL,(SRTDRNUM)             ; Recover the unsigned magnitude.
        LD A,(SRTDRSG)
        OR A
        JR Z,SRTDRPOS
        LD A,H                       ; Negative values may reach magnitude 32768.
        CP 80H
        JR C,SRTDNGOK
        JP NZ,SRTERROR
        LD A,L
        OR A
        JP NZ,SRTERROR
SRTDNGOK:
        XOR A                        ; Form the two's-complement signed payload.
        SUB L
        LD L,A
        LD A,0
        SBC A,H
        LD H,A
        LD A,3                       ; Exact integers use logical tag three.
        OR A                          ; Successful integer parsing clears carry.
        RET
SRTDRPOS:
        LD A,H                       ; Positive values must remain below 0x8000.
        CP 80H
        JP NC,SRTERROR
        LD A,3                       ; Exact integers use logical tag three.
        OR A                          ; Successful integer parsing clears carry.
        RET

; Publish a successful immediate result and preserve shared lookahead state.
SRTDRDON:
        LD (SRTDRTAG),A              ; Save the result while clearing reader state.
        LD (SRTDVAL),HL
        CALL SRTDRSTP               ; Keep pending delimiter or sticky EOF intact.
        LD A,(SRTDRTAG)
        LD HL,(SRTDVAL)
        PUSH IX                      ; Return through the common packet cleanup.
        RET

; Stop a successful read without touching the port's pending input state.
SRTDRSTP:
        XOR A                        ; The parser no longer owns temporary roots.
        LD (SRTDRACT),A
        LD (SRTDRRC),A
        LD (SRTDRFC),A
        LD (SRTDRVC),A
        LD (SRTDRACC),A
        LD (SRTDRFP),A
        LD (SRTDRFP+1),A
        LD HL,SRTDRVB                ; Discard any value slots consumed by the read.
        LD (SRTDRVP),HL
        LD (SRTDRLEN),A
        LD (SRTDSLN),A
        RET

; Clear active reader state before the common fatal runtime-error message.
SRTDCLN:
        LD A,(SRTDRACT)              ; Inactive runtime errors need no cleanup.
        OR A
        RET Z
        XOR A                        ; Drop temporary roots and parser cursors.
        LD (SRTDRACT),A
        LD (SRTDRRC),A
        LD (SRTDRFC),A
        LD (SRTDRVC),A
        LD (SRTDRACC),A
        LD (SRTDRFP),A
        LD (SRTDRFP+1),A
        LD HL,SRTDRVB                ; Failed construction cannot retain stack roots.
        LD (SRTDRVP),HL
        LD (SRTDRLEN),A
        LD (SRTDSLN),A
        LD (SRTINST),A           ; A failed read cannot retain a stale byte.
        LD (SRTINCR),A               ; Reset the physical line-ending state too.
        RET

SRTDRACT:    DB 0                    ; Nonzero while a datum read owns its roots.
SRTDRRC:  DB 0                    ; Active exact-root count for later units.
SRTDRFC: DB 0                    ; Open construction frames for later units.
SRTDRVC:   DB 0                    ; Used construction-value slots for later units.
SRTDRVP:   DW SRTDRVB             ; Next free reader value-stack address.
SRTDRFP:   DW 0                    ; Current reader frame address, if any.
SRTDRACC:  DB 0                    ; Nonzero while the list accumulator is a root.
SRTDATAG: DB 0                    ; Accumulator tag during list construction.
SRTDAVAL: DW 0                    ; Accumulator payload during list construction.
SRTDRNR:   DB 0                    ; Remaining values while folding one list.
SRTDRDOT:  DB 0                    ; Nonzero while SRTDRBLD is folding a dotted list.
SRTDEOF: DB 0                    ; Nonzero when the current nested value is EOF.
SRTDRLEN:   DB 0                    ; Numeric spelling length, bounded at 64 bytes.
SRTDRNUM:    DW 0                    ; Unsigned magnitude for an exact integer.
SRTDRSG:   DB 0                    ; Nonzero while the token has a minus sign.
SRTDRSN:   DB 0                    ; Nonzero after at least one digit is read.
SRTDRDIG:    DB 0                    ; Current decimal or character byte.
SRTDRNXT:    DB 0                    ; Peeked byte used to classify a signed token.
SRTDRTAG:    DB 0                    ; Result tag saved across normal cleanup.
SRTDVAL:    DW 0                    ; Result payload saved across normal cleanup.
