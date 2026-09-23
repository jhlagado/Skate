; Construct a pair from the two scratch values used by both cons and lists.
;
; The class table stores one three-byte descriptor per slab: page number, next
; available-slab index and free-record head offset.  A free record's two CAR
; bytes hold the next free offset, with FFH as the end marker.  These links are
; never visible after the allocation bit is published.
SRTCONS:
        POP IX                     ; Preserve the generated continuation.
        POP DE                     ; Recover the CDR payload.
        POP BC                     ; Recover the CDR tag in B.
        POP HL                     ; Recover the CAR payload.
        POP AF                     ; Recover the CAR tag in A.
        LD (SRTQCDR),DE
        LD (SRTQCTAG),A
        LD A,B
        LD (SRTQDTAG),A
        LD (SRTQCAR),HL
        CALL SRTMAKEP
        PUSH IX
        RET

; Initialise the pair class and reserve its first managed page.
SRTPIN:
        XOR A
        LD (SRTPSLBN),A             ; No slab is available before this call.
        LD A,(SRTPGCNT)             ; The page domain bounds the descriptor table.
        CP 128                      ; The table covers the expanded two-extent domain.
        JR C,SRTPSIL                ; Keep a smaller qualified domain unchanged.
        LD A,128                    ; Never advertise more entries than the table holds.
SRTPSIL:
        LD (SRTPSLIM),A             ; Empty descriptors can later be reused.
        CALL SRTFINDP               ; The first free record creates one page.
        RET C                       ; Startup reports a page-capacity failure.
        LD (SRTPSCAN),HL            ; Keep the probe record while returning it.
        LD DE,4                     ; Locate its packed state byte.
        ADD HL,DE                   ; HL addresses the allocation and mark bits.
        XOR A                       ; Return the probe record to the free chain.
        LD (HL),A                   ; The page remains assigned to the pair class.
        LD A,(SRTPSLHD)             ; The first slab is the current list head.
        DEC A                       ; Convert its one-based index to a table index.
        LD L,A
        LD H,0
        LD C,A
        ADD HL,HL                   ; Double once toward the three-byte descriptor.
        LD A,C
        LD E,A
        LD D,0
        ADD HL,DE                   ; Add one index for a total of three bytes.
        LD DE,SRTPSLT
        ADD HL,DE
        LD DE,2                     ; Descriptor byte two stores the free head.
        ADD HL,DE
        LD A,(HL)
        LD (SRTPSNXT),A             ; The former head follows the returned record.
        LD HL,(SRTPSCAN)            ; Store that link in record zero's CAR bytes.
        LD A,(SRTPSNXT)
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        LD A,(SRTPSLHD)             ; Restore the descriptor address for this slab.
        DEC A
        LD L,A
        LD H,0
        LD C,A
        ADD HL,HL                   ; Double once toward the three-byte descriptor.
        LD A,C
        LD E,A
        LD D,0
        ADD HL,DE                   ; Add one index for a total of three bytes.
        LD DE,SRTPSLT
        ADD HL,DE
        LD DE,2
        ADD HL,DE
        XOR A
        LD (HL),A
        RET

; Allocate, initialise and return one five-byte pair record.
SRTMAKEP:
        LD HL,(SRTQCAR)             ; Copy constructor inputs into dedicated roots.
        LD (SRTCRCAR),HL
        LD HL,(SRTQCDR)
        LD (SRTCRCDR),HL
        LD A,(SRTQCTAG)
        LD (SRTCRCTA),A
        LD A,(SRTQDTAG)
        LD (SRTCRDTA),A
        LD A,1                       ; The roots remain live until initialisation ends.
        LD (SRTCRON),A
        CALL SRTFINDP               ; Find a record or grow the pair class.
        JR NC,SRTPINIT              ; Carry clear means the record is reserved.
        CALL SRTGC                  ; Reclaim unreachable records when full.
        CALL SRTFINDP               ; Retry after the complete collection.
        JP C,SRTERROR               ; No managed page or record remains.
SRTPINIT:
        LD (SRTQPAIR),HL            ; Keep the reserved record across root restore.
        XOR A                       ; The record is reserved; constructor roots can clear.
        LD (SRTCRON),A
        LD HL,(SRTCRCAR)             ; Restore inputs after a possible collection.
        LD (SRTQCAR),HL
        LD HL,(SRTCRCDR)
        LD (SRTQCDR),HL
        LD A,(SRTCRCTA)
        LD (SRTQCTAG),A
        LD A,(SRTCRDTA)
        LD (SRTQDTAG),A
        LD HL,(SRTQPAIR)            ; Recover the record address while writing fields.
        LD DE,(SRTQCAR)             ; Store the CAR payload at offsets zero and one.
        LD (HL),E                   ; Publish the low CAR byte.
        INC HL                      ; Advance to the high CAR byte.
        LD (HL),D                   ; Publish the high CAR byte.
        INC HL                      ; Advance to the low CDR byte.
        LD DE,(SRTQCDR)             ; Store the CDR payload at offsets two and three.
        LD (HL),E                   ; Publish the low CDR byte.
        INC HL                      ; Advance to the high CDR byte.
        LD (HL),D                   ; Publish the high CDR byte.
        INC HL                      ; Advance to the packed tag and state byte.
        LD A,(SRTQCTAG)             ; Keep the three-bit CAR tag in bits zero to two.
        AND 7                       ; A malformed internal tag cannot escape its field.
        LD (SRTPTAG),A              ; Preserve it while shifting the CDR tag.
        LD A,(SRTQDTAG)             ; Place the three-bit CDR tag in bits three to five.
        AND 7                       ; Keep the packed representation bounded.
        ADD A,A                     ; Shift the CDR tag one bit toward its field.
        ADD A,A                     ; Shift it two bits toward its field.
        ADD A,A                     ; Shift it three bits toward its field.
        LD B,A                      ; Preserve the shifted CDR tag across the merge.
        LD A,(SRTPTAG)              ; Recover the packed CAR tag.
        OR B                        ; Combine the two logical value tags.
        OR 40H                      ; Mark the record allocated after all values exist.
        LD (HL),A                   ; Publish one complete, live pair record.
        LD HL,(SRTQPAIR)            ; Return the logical pair address.
        LD A,1                      ; Tag one identifies a pair to generated code.
        RET

; Find and reserve a free record in the available-slab/free-record chains,
; or add one page when every assigned slab is full.
SRTFINDP:
        LD A,(SRTPSLHD)             ; The one-based index identifies the list head.
        OR A
        JR Z,SRTPSNEW               ; No available slab means the class must grow.
SRTPSHD:
        DEC A                       ; Convert the one-based list index to zero-based.
        LD L,A
        LD H,0
        LD C,A
        ADD HL,HL                   ; Double once toward the three-byte descriptor.
        LD A,C
        LD E,A
        LD D,0
        ADD HL,DE                   ; Add one index for a total of three bytes.
        LD DE,SRTPSLT
        ADD HL,DE
        LD (SRTPSST),HL             ; Preserve this descriptor across the scan.
        LD D,(HL)                   ; Read the page number; its low address byte is zero.
        LD E,0
        LD (SRTPSBA),DE             ; Preserve the current available slab base.
        INC HL
        INC HL                      ; Skip the next-list and free-head fields.
        LD A,(HL)                   ; FFH means this slab has become full.
        CP 0FFH
        JR Z,SRTPSD                 ; Remove a stale full head and inspect its successor.
        LD C,A                      ; Widen the record offset to a word.
        LD B,0
        LD HL,(SRTPSBA)
        ADD HL,BC                   ; HL names the first free record.
        LD (SRTPSCAN),HL            ; Keep its address while advancing the free head.
        LD E,(HL)                   ; A free record links to the next offset.
        INC HL
        LD D,(HL)                   ; The high link byte is zero for a same-page record.
        LD A,E
        CP 0FFH
        JR Z,SRTPSLS                ; FFH terminates this slab's free-record chain.
        LD (SRTPSNXT),A             ; Preserve the successor offset for publication.
        JR SRTPSHS
SRTPSLS:
        LD A,0FFH                   ; The slab is full after this reservation.
        LD (SRTPSNXT),A
SRTPSHS:
        LD HL,(SRTPSST)
        LD DE,2
        ADD HL,DE
        LD A,(SRTPSNXT)
        LD (HL),A                   ; Publish the next free offset before claiming this one.
        LD HL,(SRTPSCAN)
        LD DE,4
        ADD HL,DE                   ; Reach the packed state byte of the free record.
        LD A,(HL)
        OR 40H                      ; Preserve tags while claiming the record.
        LD (HL),A
        LD HL,(SRTPSCAN)             ; Return the record start, not its state byte.
        XOR A                       ; Carry clear and A zero report success.
        RET
SRTPSD:
        LD HL,(SRTPSST)              ; Read the successor slab index at descriptor offset one.
        LD DE,1
        ADD HL,DE
        LD A,(HL)
        LD (SRTPSLHD),A              ; Pop this full slab from the available list.
        JR SRTFINDP
SRTPSNEW:
        LD HL,1                     ; Request one whole page for a new pair slab.
        CALL SRTGPALL               ; The page manager owns all page arithmetic.
        RET C                       ; Preserve its capacity status on failure.
        CALL SRTPSADD               ; Record the page and initialise its flags.
        RET                         ; The first record is reserved for the caller.

; Add a newly allocated page to the pair class and reserve its first record.
SRTPSADD:
        LD (SRTPSBA),HL             ; Keep the page address during table arithmetic.
        LD A,(SRTPSLBN)             ; Search the high-water table for a released slot.
        LD C,A                      ; C counts descriptors still in the table.
        XOR A                       ; SRTPSIDX is a zero-based search cursor.
        LD (SRTPSIDX),A
SRTPSLOT:
        LD A,C
        OR A
        JR Z,SRTPSAPP               ; No hole remains; append after the high-water mark.
        LD A,(SRTPSIDX)
        LD L,A
        LD H,0
        LD E,A
        LD D,0
        ADD HL,HL                   ; Three bytes describe each pair slab.
        ADD HL,DE
        LD DE,SRTPSLT
        ADD HL,DE
        LD A,(HL)                   ; Zero page bytes identify released descriptors.
        OR A
        JR Z,SRTPSUSE               ; Reuse this slot without growing the table.
        LD A,(SRTPSIDX)
        INC A
        LD (SRTPSIDX),A
        DEC C
        JR SRTPSLOT
SRTPSAPP:
        LD A,(SRTPSLBN)
        LD C,A
        LD A,(SRTPSLIM)
        CP C
        JP C,SRTPSAFL               ; The qualified table cannot accept another slab.
        JP Z,SRTPSAFL
        LD A,C                      ; Append at the previous high-water index.
        LD (SRTPSIDX),A
        INC C
        LD A,C
        LD (SRTPSLBN),A             ; Publish the expanded high-water count.
        LD A,(SRTPSIDX)             ; Recover the selected descriptor index.
SRTPSUSE:
        LD A,(SRTPSIDX)             ; A hole carries its saved table index here.
        LD C,A                      ; C is the selected zero-based descriptor index.
        LD L,A
        LD H,0
        LD E,A
        LD D,0
        ADD HL,HL
        ADD HL,DE
        LD DE,SRTPSLT
        ADD HL,DE
        LD (SRTPSST),HL             ; Preserve the selected descriptor while publishing.
        LD DE,(SRTPSBA)             ; Recover the page base for publication.
        LD A,D                      ; Store its high page byte; the low byte is zero.
        LD (HL),A
        INC HL                      ; Descriptor byte one is the next slab index.
        LD A,(SRTPSLHD)             ; Link the new slab to the old list head.
        LD (HL),A
        INC HL                      ; Descriptor byte two is the free-record head.
        LD A,5                      ; Record one is the first free record after the probe.
        LD (HL),A
        LD A,C
        INC A                        ; Available-list links use one-based indices.
        LD (SRTPSLHD),A             ; The new slab's one-based index is the new head.
        LD C,50                      ; Initialise the remaining free-record chain.
        LD HL,(SRTPSBA)
        LD DE,5
        ADD HL,DE                   ; Begin at record one.
        LD (SRTPSCAN),HL
SRTPSFI:
        LD A,C
        DEC A
        JR Z,SRTPSFL                ; The final record links to the FFH sentinel.
        LD HL,(SRTPSCAN)
        LD A,L
        ADD A,5
        LD (HL),A                   ; Link to the next record's in-page offset.
        INC HL
        XOR A
        LD (HL),A                   ; Keep the link's high byte clear.
        JR SRTPSFS
SRTPSFL:
        LD HL,(SRTPSCAN)
        LD A,0FFH
        LD (HL),A                   ; FFH marks the end of the free-record chain.
        INC HL
        XOR A
        LD (HL),A
SRTPSFS:
        LD HL,(SRTPSCAN)
        LD DE,4
        ADD HL,DE
        XOR A
        LD (HL),A                   ; Free records carry no tags or ownership bits.
        LD HL,(SRTPSCAN)
        LD DE,5
        ADD HL,DE
        LD (SRTPSCAN),HL            ; Advance to the next five-byte record.
        DEC C
        JR NZ,SRTPSFI
        LD HL,(SRTPSBA)             ; Reserve record zero for this allocation.
        LD DE,4
        ADD HL,DE
        LD A,40H
        LD (HL),A
        LD HL,(SRTPSBA)             ; Return the first record's address.
        XOR A                       ; Carry clear reports a usable pair slot.
        RET
SRTPSAFL:
        LD HL,(SRTPSBA)             ; Return the page when no descriptor is available.
        LD DE,1
        CALL SRTGPREL
        LD A,1
        SCF
        RET

; car and cdr selectors.
SRTCAR:
        POP IX
        POP HL
        POP AF
        CALL SRTCARV
        JP C,SRTERROR
        PUSH IX
        RET

SRTCARV:
        LD (SRTQAVAL),HL
        LD (SRTQATAG),A
        CALL SRTPCHK
        RET C
        LD HL,(SRTQAVAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL                     ; Skip the two CDR payload bytes.
        INC HL
        INC HL                     ; Reach the packed tag and state byte.
        LD A,(HL)
        AND 7                       ; The CAR tag occupies bits zero to two.
        EX DE,HL
        RET
SRTCDR:
        POP IX
        POP HL
        POP AF
        CALL SRTCDRV
        JP C,SRTERROR
        PUSH IX
        RET

SRTCDRV:
        LD (SRTQAVAL),HL
        LD (SRTQATAG),A
        CALL SRTPCHK
        RET C
        LD HL,(SRTQAVAL)
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD A,(HL)
        SRL A                       ; Move CDR tag bits three through five down.
        SRL A
        SRL A
        AND 7                       ; Keep only the packed CDR tag.
        EX DE,HL
        RET

; Return booleans for pair? and null?.
SRTPAIRP:
        POP IX
        POP HL
        POP AF
        CALL SRTPCHK
        JR C,SRTFPALS
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
SRTFPALS:
        XOR A
        LD HL,0FE00H
        PUSH IX
        RET
SRTNULLP:
        POP IX
        POP HL
        POP AF
        OR A
        JR NZ,SRTFPALS
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR NZ,SRTFPALS
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
