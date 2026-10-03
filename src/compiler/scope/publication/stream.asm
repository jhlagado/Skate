; Scope publication streams ASO and COM stages through CP/M.
; Entry points: SCSTREAM, SCAWRITE, SCOUT, SCBASE, SCCBS and SCSPL.
; Stream a COM image or ASO record through the CP/M transport.
SCSTREAM:
        LD (SCPTR),HL              ; Save the stream pointer while CPM_PUT runs.
        LD (SCLEFT),BC             ; Save the remaining byte count.
SCSTRLP:
        LD BC,(SCLEFT)             ; Test for the end of this stream.
        LD A,B                     ; Combine both count bytes into one zero test.
        OR C                       ; A zero pair means every byte has been accepted.
        JR Z,SCSTRDN               ; Return after the final record has been flushed.
        LD HL,(SCPTR)              ; Load the next staged byte address.
        LD A,(HL)                  ; Pass that byte to the CP/M output adapter.
        INC HL                     ; Advance the saved pointer before the call.
        LD (SCPTR),HL              ; Preserve the advanced pointer.
        CALL CPM_PUT               ; Write one byte through the private record cache.
        RET C                      ; A transport failure aborts publication.
        LD HL,(SCLEFT)             ; Reload the remaining count.
        DEC HL                     ; Account for the byte just written.
        LD (SCLEFT),HL             ; Publish the decremented stream count.
        JR SCSTRLP                 ; Stream the next byte.
SCSTRDN:
        XOR A                      ; Carry clear reports a complete stream.
        RET                        ; The caller closes the output FCB.

; Write the staged COM image as an ASO v1 stream. The image is emitted with
; slot operands cleared, then the resolved slot words are restored as PATCH
; records. Runtime layout fields remain part of the IMAGE data for now.
SCAWRITE:
        JP SINKEND                 ; The ASO stage was opened before parsing.

; Replay ASO into the COM stage, then publish the checked pair.
SCOUT:
        CALL SCAWRITE              ; Build and close the temporary ASO stage.
        JP C,SCOUTER               ; Preserve the old outputs on ASO failure.
        CALL SCCBS                 ; Build the temporary COM FCB name.
        LD HL,SCFCB                ; Point CPM_MAKE at the temporary COM.
        CALL CPM_MAKE              ; Create a fresh stage file.
        JP C,SCOUTER               ; Leave the completed ASO stage untouched.
        CALL SCAMULTI               ; Replay every ASO window into the COM stage.
        JP C,SCOUTER               ; Close and abandon a failed replay.
        CALL CPM_ENDW              ; Flush and close the COM stage.
        JP C,SCOUTER               ; A close failure prevents replacement.
        JP SCPUB                   ; Replace the COM and ASO outputs through recovery names.
SCOUTER:
        CALL CPM_ENDW              ; Close any open stage and flush no bad bytes.
        CALL SCPROLL               ; Remove partial stages and restore moved outputs.
        LD HL,(SCERRPTR)           ; Materializer capacity is still a compiler bound.
        LD DE,SCCAPTXT
        OR A
        SBC HL,DE
        JR Z,SCOUTCAP               ; Keep CAP instead of relabelling it OUTPUT ERROR.
        LD HL,SCOUTTXT             ; Distinguish a disk publication failure from source errors.
        LD (SCERRPTR),HL           ; The command driver prints this diagnostic.
        SCF                       ; Carry reports the publication failure.
        RET                        ; Staged names remain available for inspection.
SCOUTCAP:
        SCF                        ; The rollback is complete; retain the CAP pointer.
        RET
SCPRECER:
        CALL CPM_ENDR              ; Recovery did not open a new writable stage.
        LD HL,SCOUTTXT             ; Preserve the output diagnostic for the caller.
        LD (SCERRPTR),HL           ; The next command reports the unresolved recovery.
        SCF                       ; Carry prevents a second rollback with empty masks.
        RET                        ; Recovery files and stages remain for a later retry.
; Copy the command basename into SCFCB, retaining drive and eight name bytes.
SCBASE:
        LD HL,005CH               ; CCP places the command-tail FCB here.
        LD DE,SCFCB               ; SCFCB owns the output basename.
        LD BC,9                   ; Copy drive and eight-character name fields.
        LDIR                       ; Preserve the selected source basename.
        RET                        ; Extension helpers fill bytes 9..11.

; Build the temporary COM stage FCB.
SCCBS:
        CALL SCBASE                ; Start from the command basename.
        LD HL,SCFCB+9              ; Point at the temporary COM extension.
        LD (HL),'C'                ; Use CBS for the private COM stage.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'B'                ; Store the stage marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'S'                ; Store the stage suffix.
        RET                        ; Return with SCFCB ready for CPM_MAKE.

; Build the temporary ASO stage FCB.
SCSPL:
        CALL SCBASE                ; Start from the command basename.
        LD HL,SCFCB+9              ; Point at the temporary ASO extension.
        LD (HL),'S'                ; SPL is the private spool extension.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'P'                ; Mark the spool file explicitly.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'L'                ; Complete SPL.
        RET                        ; Return with SCFCB ready for CPM_MAKE.
