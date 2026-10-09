; Scope publication streams ASO and COM stages through CP/M.
; Entry points: PUB_SEND, PUB_ASO, PUB_MAIN, PUB_BASE, PUB_CBS and PUB_SPL.
; Stream a COM image or ASO record through the CP/M transport.
PUB_SEND:
        LD (PUB_SRCP),HL           ; Save the stream pointer while CPM_PUT runs.
        LD (PUB_LEFT),BC           ; Save the remaining byte count.
.LOOP:
        LD BC,(PUB_LEFT)           ; Test for the end of this stream.
        LD A,B                     ; Combine both count bytes into one zero test.
        OR C                       ; A zero pair means every byte has been accepted.
        JR Z,.DONE                 ; Return after the final record has been flushed.
        LD HL,(PUB_SRCP)           ; Load the next staged byte address.
        LD A,(HL)                  ; Pass that byte to the CP/M output adapter.
        INC HL                     ; Advance the saved pointer before the call.
        LD (PUB_SRCP),HL           ; Preserve the advanced pointer.
        CALL CPM_PUT               ; Write one byte through the private record cache.
        RET C                      ; A transport failure aborts publication.
        LD HL,(PUB_LEFT)           ; Reload the remaining count.
        DEC HL                     ; Account for the byte just written.
        LD (PUB_LEFT),HL           ; Publish the decremented stream count.
        JR .LOOP                   ; Stream the next byte.
.DONE:
        XOR A                      ; Carry clear reports a complete stream.
        RET                        ; The caller closes the output FCB.

; Write the staged COM image as an ASO v1 stream. The image is emitted with
; slot operands cleared, then the resolved slot words are restored as PATCH
; records. Runtime layout fields remain part of the IMAGE data for now.
PUB_ASO:
        JP ASO_DONE                ; The ASO stage was opened before parsing.

; Replay ASO into the COM stage, then publish the checked pair.
PUB_MAIN:
        CALL PUB_ASO               ; Build and close the temporary ASO stage.
        JR C,.FAIL                 ; Preserve the old outputs on ASO failure.
        CALL PUB_CBS               ; Build the temporary COM FCB name.
        LD HL,PUB_FCB              ; Point CPM_MAKE at the temporary COM.
        CALL CPM_MAKE              ; Create a fresh stage file.
        JR C,.FAIL                 ; Leave the completed ASO stage untouched.
        CALL ASO_COM                ; Replay every ASO window into the COM stage.
        JR C,.FAIL                 ; Close and abandon a failed replay.
        CALL CPM_ENDW              ; Flush and close the COM stage.
        JR C,.FAIL                 ; A close failure prevents replacement.
        JP PUB_SWAP                ; Replace the COM and ASO outputs through recovery names.
.FAIL:
        CALL CPM_ENDW              ; Close any open stage and flush no bad bytes.
        CALL PUB_UNDO              ; Remove partial stages and restore moved outputs.
        LD HL,(ST_ERROR)           ; Materializer capacity is still a compiler bound.
        LD DE,M_CAP
        OR A
        SBC HL,DE
        JR Z,.KEEP_CAP              ; Keep CAP instead of relabelling it OUTPUT ERROR.
        LD HL,M_OUTPUT             ; Distinguish a disk publication failure from source errors.
        LD (ST_ERROR),HL           ; The command driver prints this diagnostic.
        SCF                       ; Carry reports the publication failure.
        RET                        ; Staged names remain available for inspection.
.KEEP_CAP:
        SCF                        ; The rollback is complete; retain the CAP pointer.
        RET
PUB_SNAG:
        CALL CPM_ENDR              ; Recovery did not open a new writable stage.
        LD HL,M_OUTPUT             ; Preserve the output diagnostic for the caller.
        LD (ST_ERROR),HL           ; The next command reports the unresolved recovery.
        SCF                       ; Carry prevents a second rollback with empty masks.
        RET                        ; Recovery files and stages remain for a later retry.
; Copy the command basename into PUB_FCB, retaining drive and eight name bytes.
PUB_BASE:
        LD HL,005CH               ; CCP places the command-tail FCB here.
        LD DE,PUB_FCB             ; PUB_FCB owns the output basename.
        LD BC,9                   ; Copy drive and eight-character name fields.
        LDIR                       ; Preserve the selected source basename.
        RET                        ; Extension helpers fill bytes 9..11.

; Build the temporary COM stage FCB.
PUB_CBS:
        CALL PUB_BASE              ; Start from the command basename.
        LD HL,PUB_FCB+9            ; Point at the temporary COM extension.
        LD (HL),'C'                ; Use CBS for the private COM stage.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'B'                ; Store the stage marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'S'                ; Store the stage suffix.
        RET                        ; Return with PUB_FCB ready for CPM_MAKE.

; Build the temporary ASO stage FCB.
PUB_SPL:
        CALL PUB_BASE              ; Start from the command basename.
        LD HL,PUB_FCB+9            ; Point at the temporary ASO extension.
        LD (HL),'S'                ; SPL is the private spool extension.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'P'                ; Mark the spool file explicitly.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'L'                ; Complete SPL.
        RET                        ; Return with PUB_FCB ready for CPM_MAKE.
