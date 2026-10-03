; CP/M source opening and include resolution.
; SRC_OPEN: HL -> a 12-byte drive/name/type prefix; carry clear means success.
; Leading (include "NAME.EXT" ...) forms are resolved depth first before any
; byte reaches the reader: every part's own leading includes precede it, a
; name already in the table is imported once, a name still on the include
; path is a cycle, and at most SRC_MAX parts and INC_MAX nested files are
; accepted.  Names are CP/M 8.3 names on the root's drive.  Failures leave
; SRC_ERR set (1 open, 2 read, 3 close, 5 include) and the stream terminal.
; Private FCB and DMA state makes the adapter static and non-reentrant; IX and
; IY are preserved.

SRC_OPEN: LD DE,SRC_SEEN         ; Entry zero is always the root source.
        LD BC,12                 ; Only the drive/name/type prefix is retained.
        LDIR
        XOR A                    ; Clear sticky state from an earlier source.
        LD (SRC_ERR),A           ; No source error has occurred yet.
        LD (SRC_DONE),A          ; The stream has not ended.
        LD (SRC_LIVE),A          ; No FCB is open yet.
        LD (SRC_SEP),A           ; No separator is pending.
        LD (SRC_POS),A           ; The dependency order list starts empty.
        LD (INC_NEST),A          ; No part is on the include path yet.
        LD (SRC_PART),A          ; Locations start in the root.
        INC A
        LD (SRC_PEND),A          ; No location exists until the first byte.
        LD (SRC_CNT),A           ; The root is the only known entry.
        DEC A                    ; A = 0 selects the root entry.
        CALL .VISIT              ; Order the root's include tree, root last.
        RET C                    ; SRC_ERR records the open, read or include fault.
        XOR A                    ; Restart the order list for streaming.
        LD (SRC_POS),A           ; SRC_BYTE opens SRC_LIST[0] on its first call.
        RET                      ; Carry is clear: the source is ready.

; Visit part A: order its leading includes first, then append the part.  The
; part is rescanned from its first byte after every new dependency, because
; only one FCB and one DMA record exist; names already ordered are skipped.
.VISIT:
        LD C,A                   ; C holds the part index for the whole visit.
        LD HL,INC_NEST           ; Bound the number of files on the path.
        LD A,(HL)
        CP INC_MAX               ; A full path cannot open one more nested file.
        LD A,5                   ; Too deep is an include error.
        JP NC,SRC_FAIL           ; Set the sticky error and return carry.
        INC (HL)                 ; This part is now on the include path.
        LD A,C
        CALL INC_SLOT            ; HL addresses this part's header-length word.
        LD A,0FFH                ; FFFFH marks the part as being on the path.
        LD (HL),A
        INC HL
        LD (HL),A
.RESCAN:
        PUSH BC                  ; Keep the part index across BDOS calls.
        LD A,C
        CALL SRC_LOAD            ; Open the part with a fresh record cursor.
        JR C,.FAIL               ; A missing part is already a sticky error.
        CALL INC_SCAN            ; A = new dependency, or FFH when complete.
        JR NC,.PARSED            ; The leading region was well formed.
        LD A,5                   ; Malformed headers and cycles are include errors.
        CALL SRC_FAIL            ; A prior read error keeps precedence.
.FAIL:  CALL SRC_SHUT            ; Release the FCB; the stream stays failed.
        POP BC                   ; Balance the saved part index.
        SCF                      ; Report the recorded source failure.
        RET
.PARSED:
        PUSH AF                  ; Keep the dependency across the close.
        CALL SRC_SHUT            ; Close before any other part is opened.
        POP DE                   ; D = dependency index or FFH.
        POP BC                   ; C = this part's index.
        RET C                    ; A failed close is a source error.
        LD A,D
        INC A                    ; FFH means every leading include is ordered.
        JR Z,.DONE
        DEC A                    ; Recover the new dependency index.
        PUSH BC                  ; Keep this part's index across the recursion.
        CALL .VISIT              ; Order the dependency and its own includes.
        POP BC
        RET C                    ; Nested failures unwind with carry set.
        JR .RESCAN               ; Look for this part's next new dependency.
.DONE:  LD A,C
        CALL INC_SLOT            ; Replace the path marker with the header length.
        LD DE,(INC_END)          ; Bytes through the last include form.
        LD (HL),E
        INC HL
        LD (HL),D
        LD HL,SRC_POS            ; Append the part after its dependencies.
        LD E,(HL)
        INC (HL)                 ; At most SRC_MAX parts reach this point.
        LD D,0
        LD HL,SRC_LIST
        ADD HL,DE                ; HL addresses the next order-list byte.
        LD (HL),C
        LD HL,INC_NEST           ; The part leaves the include path.
        DEC (HL)
        OR A                     ; Carry is clear after a complete visit.
        RET

; Return HL -> the header-length word of part A.  DE is clobbered.
INC_SLOT:
        LD L,A                   ; Two bytes per part.
        LD H,0
        ADD HL,HL
        LD DE,INC_SPAN           ; Add the table base.
        ADD HL,DE
        RET

; Return HL -> the 12-byte source-table prefix of part A.  DE is clobbered.
SRC_SLOT:
        LD L,A                   ; Twelve bytes describe each source entry.
        LD H,0
        ADD HL,HL                ; Two times the part ordinal.
        ADD HL,HL                ; Four times the part ordinal.
        LD D,H
        LD E,L
        ADD HL,HL                ; Eight times the part ordinal.
        ADD HL,DE                ; Add the four-times component for twelve.
        LD DE,SRC_SEEN           ; Add the table base address.
        ADD HL,DE
        RET

; Open part A through SRC_FCB with a fresh record cursor.  A missing root is
; error 1 and a missing included part error 5; carry reports the failure.
SRC_LOAD: LD (SRC_PART),A        ; Locations and open failures name this part.
        CALL SRC_SLOT            ; HL addresses the part's FCB prefix.
        LD DE,SRC_FCB            ; Copy the 12-byte prefix into the FCB.
        LD BC,12
        LDIR
        XOR A                    ; DE now addresses the extent field.
        LD B,24                  ; Extent, allocation and record fields start zero.
.CLEAR: LD (DE),A
        INC DE
        DJNZ .CLEAR
        LD (SRC_EOF),A           ; The selected part is not at EOF.
        LD A,128                 ; Force a physical record read.
        LD (SRC_IDX),A
        LD DE,SRC_FCB            ; Open the selected source file.
        LD C,15                  ; BDOS open-file function.
        CALL SRC_BDOS
        INC A                    ; CP/M returns FFH for an unsuccessful open.
        JR Z,.MISSING
        LD A,1
        LD (SRC_LIVE),A          ; SRC_SHUT now owns the open FCB.
        OR A                     ; Carry clear: the part is ready to read.
        RET
.MISSING:
        LD A,(SRC_PART)          ; A missing root is an open failure.
        OR A
        LD A,1
        JP Z,SRC_FAIL            ; Record the root open failure and return carry.
        LD A,5                   ; A missing included part is an include error.
        JP SRC_FAIL
