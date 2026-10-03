; Construct a pair from the two scratch values used by both cons and lists.
;
; The class table stores one three-byte descriptor per slab: page number, next
; available-slab index and free-record head offset.  A free record's two CAR
; bytes hold the next free offset, with FFH as the end marker.  These links are
; never visible after the allocation bit is published.
CONS:
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
        CALL PAIR_NEW
        PUSH IX
        RET

; Initialise the pair class and reserve its first managed page.
PAIR_INI:
        XOR A
        LD (SRTPSLBN),A             ; No slab is available before this call.
        LD A,(PAGE_CNT)             ; The page domain bounds the descriptor table.
        CP 128                      ; The table covers the expanded two-extent domain.
        JR C,.LIMIT                 ; Keep a smaller qualified domain unchanged.
        LD A,128                    ; Never advertise more entries than the table holds.
.LIMIT:
        LD (SRTPSLIM),A             ; Empty descriptors can later be reused.
        CALL PAIR_GET               ; The first free record creates one page.
        RET C                       ; Startup reports a page-capacity failure.
        LD (SRTPSCAN),HL            ; Keep the probe record while returning it.
        LD DE,CAR_TAG               ; Locate the CAR metadata byte.
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

; Allocate, initialise and return one eight-byte pair record.
PAIR_NEW:
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
        CALL PAIR_GET               ; Find a record or grow the pair class.
        JR NC,.INIT                 ; Carry clear means the record is reserved.
        CALL SRTGC                  ; Reclaim unreachable records when full.
        CALL PAIR_GET               ; Retry after the complete collection.
        JP C,SRTERROR               ; No managed page or record remains.
.INIT:
        LD DE,(SRTPCNT)             ; Count this successfully reserved pair.
        INC DE
        LD (SRTPCNT),DE
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
        INC HL                      ; Advance to the reserved CAR extension byte.
        XOR A
        LD (HL),A                   ; Keep the future payload extension canonical.
        INC HL                      ; Advance to the CAR metadata byte.
        LD A,(SRTQCTAG)
        AND 0FH
        OR 40H                      ; Publish allocation after both values are rooted.
        LD (HL),A
        INC HL                      ; Advance to the low CDR payload byte.
        LD DE,(SRTQCDR)             ; Store the CDR payload at offsets four and five.
        LD (HL),E                   ; Publish the low CDR byte.
        INC HL                      ; Advance to the high CDR byte.
        LD (HL),D                   ; Publish the high CDR byte.
        INC HL                      ; Advance to the reserved CDR extension byte.
        XOR A
        LD (HL),A                   ; Keep the future payload extension canonical.
        INC HL                      ; Advance to the CDR metadata byte.
        LD A,(SRTQDTAG)
        AND 0FH
        LD (HL),A                   ; The CDR tag occupies its own cell metadata.
        LD HL,(SRTQPAIR)            ; Return the logical pair address.
        LD A,1                      ; Tag one identifies a pair to generated code.
        RET

; Find and reserve a free record in the available-slab/free-record chains,
; or add one page when every assigned slab is full.
PAIR_GET:
        LD A,(SRTPSLHD)             ; The one-based index identifies the list head.
        OR A
        JR Z,.GROW                  ; No available slab means the class must grow.
.HEAD:
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
        JR Z,.DROP                  ; Remove a stale full head and inspect its successor.
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
        JR Z,.NOW_FULL              ; FFH terminates this slab's free-record chain.
        LD (SRTPSNXT),A             ; Preserve the successor offset for publication.
        JR .TAKE
.NOW_FULL:
        LD A,0FFH                   ; The slab is full after this reservation.
        LD (SRTPSNXT),A
.TAKE:
        LD HL,(SRTPSST)
        LD DE,2
        ADD HL,DE
        LD A,(SRTPSNXT)
        LD (HL),A                   ; Publish the next free offset before claiming this one.
        LD HL,(SRTPSCAN)
        LD DE,CAR_TAG
        ADD HL,DE                   ; Reach the CAR metadata byte of the free record.
        LD A,(HL)
        OR 40H                      ; Preserve tags while claiming the record.
        LD (HL),A
        LD HL,(SRTPSCAN)             ; Return the record start, not its state byte.
        XOR A                       ; Carry clear and A zero report success.
        RET
.DROP:
        LD HL,(SRTPSST)              ; Read the successor slab index at descriptor offset one.
        LD DE,1
        ADD HL,DE
        LD A,(HL)
        LD (SRTPSLHD),A              ; Pop this full slab from the available list.
        JR PAIR_GET
.GROW:
        LD HL,1                     ; Request one whole page for a new pair slab.
        CALL PAGE_NEW               ; The page manager owns all page arithmetic.
        RET C                       ; Preserve its capacity status on failure.
        CALL .ADD_PAGE              ; Record the page and initialise its flags.
        RET                         ; The first record is reserved for the caller.

; Add a newly allocated page to the pair class and reserve its first record.
.ADD_PAGE:
        LD (SRTPSBA),HL             ; Keep the page address during table arithmetic.
        LD A,(SRTPSLBN)             ; Search the high-water table for a released slot.
        LD C,A                      ; C counts descriptors still in the table.
        XOR A                       ; SRTPSIDX is a zero-based search cursor.
        LD (SRTPSIDX),A
.SEEK:
        LD A,C
        OR A
        JR Z,.APPEND                ; No hole remains; append after the high-water mark.
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
        JR Z,.USE                   ; Reuse this slot without growing the table.
        LD A,(SRTPSIDX)
        INC A
        LD (SRTPSIDX),A
        DEC C
        JR .SEEK
.APPEND:
        LD A,(SRTPSLBN)
        LD C,A
        LD A,(SRTPSLIM)
        CP C
        JP C,.FULL                  ; The qualified table cannot accept another slab.
        JP Z,.FULL
        LD A,C                      ; Append at the previous high-water index.
        LD (SRTPSIDX),A
        INC C
        LD A,C
        LD (SRTPSLBN),A             ; Publish the expanded high-water count.
        LD A,(SRTPSIDX)             ; Recover the selected descriptor index.
.USE:
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
        LD A,PAIR_SZ                ; Record one is the first free record after the probe.
        LD (HL),A
        LD A,C
        INC A                        ; Available-list links use one-based indices.
        LD (SRTPSLHD),A             ; The new slab's one-based index is the new head.
        LD C,PAIR_CAP-1             ; Initialise the remaining free-record chain.
        LD HL,(SRTPSBA)
        LD DE,PAIR_SZ
        ADD HL,DE                   ; Begin at record one.
        LD (SRTPSCAN),HL
.LINK:
        LD A,C
        DEC A
        JR Z,.LAST                  ; The final record links to the FFH sentinel.
        LD HL,(SRTPSCAN)
        LD A,L
        ADD A,PAIR_SZ
        LD (HL),A                   ; Link to the next record's in-page offset.
        INC HL
        XOR A
        LD (HL),A                   ; Keep the link's high byte clear.
        JR .CLEAR
.LAST:
        LD HL,(SRTPSCAN)
        LD A,0FFH
        LD (HL),A                   ; FFH marks the end of the free-record chain.
        INC HL
        XOR A
        LD (HL),A
.CLEAR:
        LD HL,(SRTPSCAN)
        INC HL                      ; Skip the free-record link's two bytes.
        INC HL
        XOR A
        LD (HL),A                   ; Clear the CAR extension byte.
        INC HL
        LD (HL),A                   ; Free records carry no CAR metadata.
        INC HL
        INC HL
        INC HL
        LD (HL),A                   ; Clear the CDR extension byte.
        INC HL
        LD (HL),A                   ; Free records carry no CDR metadata.
        LD HL,(SRTPSCAN)
        LD DE,PAIR_SZ
        ADD HL,DE
        LD (SRTPSCAN),HL            ; Advance to the next eight-byte record.
        DEC C
        JR NZ,.LINK
        LD HL,(SRTPSBA)             ; Reserve record zero for this allocation.
        INC HL
        INC HL
        XOR A
        LD (HL),A                   ; Clear the CAR extension byte.
        INC HL
        LD A,40H
        LD (HL),A                   ; Reserve record zero in its CAR metadata.
        INC HL
        INC HL
        INC HL
        XOR A
        LD (HL),A                   ; Clear the CDR extension byte.
        INC HL
        LD (HL),A                   ; Record zero has no CDR tag yet.
        LD HL,(SRTPSBA)             ; Return the first record's address.
        XOR A                       ; Carry clear reports a usable pair slot.
        RET
.FULL:
        LD HL,(SRTPSBA)             ; Return the page when no descriptor is available.
        LD DE,1
        CALL PAGE_REL
        LD A,1
        SCF
        RET

; car and cdr selectors.
CAR:
        POP IX
        POP HL
        POP AF
        CALL PAIR_CAR
        JP C,SRTERROR
        PUSH IX
        RET

PAIR_CAR:
        LD (SRTQAVAL),HL
        LD (SRTQATAG),A
        CALL PAIR_CHK
        RET C
        LD HL,(SRTQAVAL)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL                     ; Reach the CAR metadata byte.
        LD A,(HL)
        AND 0FH                     ; The CAR tag occupies its cell metadata nibble.
.OK:
        OR A                       ; Pair access reports success with carry clear.
        EX DE,HL
        RET
CDR:
        POP IX
        POP HL
        POP AF
        CALL PAIR_CDR
        JP C,SRTERROR
        PUSH IX
        RET

PAIR_CDR:
        LD (SRTQAVAL),HL
        LD (SRTQATAG),A
        CALL PAIR_CHK
        RET C
        LD HL,(SRTQAVAL)
        LD DE,CDR_LO
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        INC HL
        ; Reach the CDR metadata byte.
        LD A,(HL)
        AND 0FH                      ; The CDR tag occupies its cell metadata nibble.
.OK:
        OR A                       ; Pair access reports success with carry clear.
        EX DE,HL
        RET

; Return booleans for pair? and null?.
PAIR_IS:
        POP IX
        POP HL
        POP AF
        CALL PAIR_CHK
        JR C,PAIR_NO
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
PAIR_NO:
        XOR A
        LD HL,0FE00H
        PUSH IX
        RET
PAIR_NIL:
        POP IX
        POP HL
        POP AF
        OR A
        JR NZ,PAIR_NO
        LD DE,0FE02H
        OR A
        SBC HL,DE
        JR NZ,PAIR_NO
        XOR A
        LD HL,0FE01H
        PUSH IX
        RET
