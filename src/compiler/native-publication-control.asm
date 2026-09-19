;=============================================================================
;  Recoverable CP/M publication for compiler commands
;=============================================================================
;
;  The emitter stages the NOBJ and COM files under temporary names, then
;  replaces the previous pair through CP/M rename operations.  Every BDOS
;  failure rolls back the pair and removes stale stage files.
;=============================================================================

AREMIT:
        CALL .S                    ; Remove stale stage files and recover old work.
        JP C,.E                    ; Abort before opening a new output on failure.
        CALL ARPATCH               ; Copy validated operands into the runtime image.
        CALL ARCRC                 ; Recompute the checksum over the patched object.
        CALL .NS                   ; Build the private NOBJ stage filename.
        LD HL,ARFCB                ; Point CTOPENW at the private NOBJ FCB.
        CALL CTOPENW               ; Create the private NOBJ stage file.
        JP C,.E                    ; Roll back if the stage cannot be opened.
        LD HL,AROBJ                ; Stream from the serialized object base.
        LD BC,AROBLEN              ; Include the complete header, image and checksum.
        CALL ARSTREAM              ; Write the checked NOBJ bytes.
        JP C,.E                    ; Roll back a transport failure.
        CALL CTCLOSEW              ; Flush and close the NOBJ stage.
        JP C,.E                    ; A close failure prevents publication.
        CALL .CS                   ; Build the private COM stage filename.
        LD HL,ARFCB                ; Point CTOPENW at the private COM FCB.
        CALL CTOPENW               ; Create the private COM stage file.
        JP C,.E                    ; Roll back if the stage cannot be opened.
        LD HL,AROBJ                ; Start at the same serialized object.
        LD DE,ARIMGOF              ; Skip the NOBJ header to the image payload.
        ADD HL,DE                  ; Point at the first COM byte.
        LD BC,ARIMGLN              ; Stream only the runtime image length.
        CALL ARSTREAM              ; Write the runnable COM image.
        JP C,.E                    ; Roll back a transport failure.
        CALL CTCLOSEW              ; Flush and close the COM stage.
        JP C,.E                    ; A close failure prevents publication.
        CALL .P                    ; Rename both stages into their final names.
        JP C,.E                    ; Leave recovery names for the next invocation.
        XOR A                      ; Clear carry to report a committed pair.
        RET                        ; Return to the command success path.

; Stage cleanup and pair publication for the compiler command.
.S:
        CALL .R                    ; Restore any recovery pair before staging.
        JP C,.SE                   ; Stop when recovery itself reports an error.
        XOR A                      ; Clear all publication-state flags.
        LD (.BN),A                 ; No NOBJ stage has been renamed yet.
        LD (.BC),A                 ; No COM stage has been renamed yet.
        LD (.NI),A                 ; No final NOBJ has been installed yet.
        LD (.CI),A                 ; No final COM has been installed yet.
        CALL .NS                   ; Select the NOBJ stage name.
        LD HL,ARFCB                ; Point at that temporary FCB.
        CALL CTDELETE              ; Remove a stale NOBJ stage if it exists.
        JR C,.SE                   ; Treat a delete error as cleanup failure.
        CALL .CS                   ; Select the COM stage name.
        LD HL,ARFCB                ; Point at the COM temporary FCB.
        CALL CTDELETE              ; Remove a stale COM stage if it exists.
        JR C,.SE                   ; Treat a delete error as cleanup failure.
        XOR A                      ; Return with carry clear after cleanup.
        RET                        ; Continue with a fresh publication.
.SE:
        SCF                        ; Report cleanup failure to AREMIT.
        RET                        ; The caller performs the common rollback.

; Restore any pair left in the recovery names by an interrupted publication.
; A missing recovery file is normal; an open/close failure leaves it in place
; for the next invocation instead of deleting a valid final file.
.R:
        CALL ARFCBN                ; Build the recovery NOBJ filename.
        CALL .PR                   ; Build the final NOBJ filename in .F2.
        LD HL,.F2                  ; Point at the recovery probe FCB.
        CALL CTOPENR               ; Test whether a recovery NOBJ exists.
        JR C,.RN                   ; If absent, continue with the COM recovery probe.
        CALL CTCLOSER              ; Close the successful probe.
        JR C,.RF                   ; A close error leaves recovery pending.
        CALL ARFCBN                ; Rebuild the recovery NOBJ name after the probe.
        LD HL,ARFCB                ; Point at the recovery NOBJ FCB.
        CALL CTDELETE              ; Remove any existing final NOBJ.
        JP C,.RF                   ; Do not rename over an uncertain state.
        CALL .PR                   ; Rebuild the final NOBJ name.
        LD HL,.F2                  ; Point at the recovery NOBJ name.
        LD DE,ARFCB                ; Point at the final NOBJ FCB.
        CALL CTRENAME              ; Restore the recovered NOBJ.
        JP C,.RF                   ; Keep the recovery file for a later retry.
.RN:
        CALL ARFCBC                ; Build the recovery COM filename.
        CALL .PC                   ; Build the final COM filename in .F2.
        LD HL,.F2                  ; Point at the recovery probe FCB.
        CALL CTOPENR               ; Test whether a recovery COM exists.
        JR C,.RC                   ; If absent, recovery is complete.
        CALL CTCLOSER              ; Close the successful probe.
        JR C,.RF                   ; A close error leaves recovery pending.
        CALL ARFCBC                ; Rebuild the recovery COM name after the probe.
        LD HL,ARFCB                ; Point at the recovery COM FCB.
        CALL CTDELETE              ; Remove any existing final COM.
        JP C,.RF                   ; Do not rename over an uncertain state.
        CALL .PC                   ; Rebuild the final COM name.
        LD HL,.F2                  ; Point at the recovery COM name.
        LD DE,ARFCB                ; Point at the final COM FCB.
        CALL CTRENAME              ; Restore the recovered COM.
.RC:
        XOR A                      ; Report that recovery completed.
        RET                        ; Continue with new staging.
.RF:
        SCF                        ; Report an unrecoverable recovery operation.
        RET                        ; The caller leaves recovery files in place.
.P:
        XOR A                      ; Clear the rename-state flags for this attempt.
        LD (.BN),A                 ; No NOBJ stage rename has succeeded.
        LD (.BC),A                 ; No COM stage rename has succeeded.
        LD (.NI),A                 ; No final NOBJ rename has succeeded.
        LD (.CI),A                 ; No final COM rename has succeeded.
        CALL ARFCBN                ; Build the NOBJ stage name.
        CALL .PR                   ; Build the final NOBJ name in .F2.
        LD HL,ARFCB                ; Point at the NOBJ stage FCB.
        LD DE,.F2                  ; Point at the final NOBJ FCB.
        CALL CTRENAME              ; Move the NOBJ stage into the recovery name.
        JR C,.NO                   ; Continue with COM even if this rename fails.
        LD A,1                     ; Record that the NOBJ recovery rename succeeded.
        LD (.BN),A                 ; The rollback path may now restore it.
.NO:
        CALL ARFCBC                ; Build the COM stage name.
        CALL .PC                   ; Build the final COM name in .F2.
        LD HL,ARFCB                ; Point at the COM stage FCB.
        LD DE,.F2                  ; Point at the final COM FCB.
        CALL CTRENAME              ; Move the COM stage into the recovery name.
        JR C,.NC                   ; Continue to final installation on failure.
        LD A,1                     ; Record that the COM recovery rename succeeded.
        LD (.BC),A                 ; The rollback path may now restore it.
.NC:
        CALL .NS                   ; Build the final NOBJ name.
        CALL .FN                   ; Build the NOBJ recovery name in .F2.
        LD HL,ARFCB                ; Point at the NOBJ recovery FCB.
        LD DE,.F2                  ; Point at the final NOBJ FCB.
        CALL CTRENAME              ; Install the recovered NOBJ as the final file.
        JP C,.F                    ; Roll back the pair on failure.
        LD A,1                     ; Record that the final NOBJ is installed.
        LD (.NI),A                 ; Rollback must remove it if COM fails.
        CALL .CS                   ; Build the final COM name.
        CALL .FC                   ; Build the COM recovery name in .F2.
        LD HL,ARFCB                ; Point at the COM recovery FCB.
        LD DE,.F2                  ; Point at the final COM FCB.
        CALL CTRENAME              ; Install the recovered COM as the final file.
        JP C,.F                    ; Roll back the pair on failure.
        LD A,1                     ; Record that the final COM is installed.
        LD (.CI),A                 ; The pair is now complete.
        CALL .PR                   ; Rebuild the NOBJ recovery name.
        LD HL,.F2                  ; Point at the NOBJ recovery file.
        CALL CTDELETE              ; Remove the consumed NOBJ recovery name.
        CALL .PC                   ; Rebuild the COM recovery name.
        LD HL,.F2                  ; Point at the COM recovery file.
        CALL CTDELETE              ; Remove the consumed COM recovery name.
        CALL .S                    ; Clear stage flags and stale files.
        RET                        ; Return with the pair published.
.F:
        CALL .B                    ; Remove or restore every partially moved file.
        SCF                        ; Report publication failure to AREMIT.
        RET                        ; No incomplete pair is reported as complete.
.B:
        LD A,(.CI)                 ; Test whether the final COM was installed.
        OR A                       ; Set flags from the installation marker.
        JR Z,.BNC                  ; Skip deletion when no final COM exists.
        CALL ARFCBC                ; Build the final COM FCB.
        LD HL,ARFCB                ; Point at the final COM to remove.
        CALL CTDELETE              ; Delete the incomplete final COM.
.BNC:
        LD A,(.NI)                 ; Test whether the final NOBJ was installed.
        OR A                       ; Set flags from the installation marker.
        JR Z,.BNB                  ; Skip deletion when no final NOBJ exists.
        CALL ARFCBN                ; Build the final NOBJ FCB.
        LD HL,ARFCB                ; Point at the final NOBJ to remove.
        CALL CTDELETE              ; Delete the incomplete final NOBJ.
.BNB:
        LD A,(.BC)                 ; Test whether the COM recovery rename succeeded.
        OR A                       ; Set flags from the recovery marker.
        JR Z,.BNC2                 ; Skip restore when no recovery COM exists.
        CALL .PC                   ; Build the COM recovery name.
        CALL ARFCBC                ; Build the final COM name in ARFCB.
        LD HL,.F2                  ; Point at the COM recovery file.
        LD DE,ARFCB                ; Point at the final COM destination.
        CALL CTRENAME              ; Restore the previous COM.
.BNC2:
        LD A,(.BN)                 ; Test whether the NOBJ recovery rename succeeded.
        OR A                       ; Set flags from the recovery marker.
        JP Z,.BST                  ; Skip restore when no recovery NOBJ exists.
        CALL .PR                   ; Build the NOBJ recovery name.
        CALL ARFCBN                ; Build the final NOBJ name in ARFCB.
        LD HL,.F2                  ; Point at the NOBJ recovery file.
        LD DE,ARFCB                ; Point at the final NOBJ destination.
        CALL CTRENAME              ; Restore the previous NOBJ.
.BST:
        CALL .S                    ; Remove stage names and clear all markers.
        RET                        ; Return after best-effort rollback.
.NS:
        CALL .X                    ; Copy the command basename into ARFCB.
        LD HL,ARFCB+9              ; Point at the extension field.
        LD (HL),'N'                ; Use NBS for the private NOBJ stage.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'B'                ; Store the stage marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'S'                ; Store the stage suffix.
        RET                        ; Return with the NOBJ stage FCB ready.
.CS:
        CALL .X                    ; Copy the command basename into ARFCB.
        LD HL,ARFCB+9              ; Point at the extension field.
        LD (HL),'C'                ; Use CBS for the private COM stage.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'B'                ; Store the stage marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'S'                ; Store the stage suffix.
        RET                        ; Return with the COM stage FCB ready.
.PR:
        CALL .Y                    ; Copy the final basename into the recovery FCB.
        LD HL,.F2+9                ; Point at the extension field.
        LD (HL),'N'                ; Use NPR for the NOBJ recovery name.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'P'                ; Store the recovery marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'R'                ; Store the recovery suffix.
        RET                        ; Return with the recovery NOBJ FCB ready.
.PC:
        CALL .Y                    ; Copy the final basename into the recovery FCB.
        LD HL,.F2+9                ; Point at the extension field.
        LD (HL),'C'                ; Use CPR for the COM recovery name.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'P'                ; Store the recovery marker.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'R'                ; Store the recovery suffix.
        RET                        ; Return with the recovery COM FCB ready.
.FN:
        CALL .Y                    ; Copy the final basename into the recovery FCB.
        LD HL,.F2+9                ; Point at the extension field.
        LD (HL),'N'                ; Use NOB for the final NOBJ name.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Store the normal object suffix.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'B'                ; Store the final extension character.
        RET                        ; Return with the NOBJ destination ready.
.FC:
        CALL .Y                    ; Copy the final basename into the recovery FCB.
        LD HL,.F2+9                ; Point at the extension field.
        LD (HL),'C'                ; Use COM for the final program name.
        INC HL                     ; Advance to the second extension character.
        LD (HL),'O'                ; Store the normal program suffix.
        INC HL                     ; Advance to the third extension character.
        LD (HL),'M'                ; Store the final extension character.
        RET                        ; Return with the COM destination ready.
.X:
        LD HL,005CH                ; Point at the command-tail basename.
        LD DE,ARFCB                ; Point at the working FCB basename.
        LD BC,9                    ; Copy drive and eight-character name fields.
        LDIR                       ; Preserve the command's selected basename.
        RET                        ; Return with the working FCB populated.
.Y:
        LD HL,ARFCB                ; Point at the current working FCB.
        LD DE,.F2                  ; Point at the private recovery FCB.
        LD BC,12                   ; Copy drive, name and extension fields.
        LDIR                       ; Preserve the selected basename and drive.
        RET                        ; Return with the recovery FCB populated.
.E:
        CALL .B                    ; Roll back every file moved so far.
        LD A,4                     ; Code 4 identifies output publication failure.
        LD (ARCODE),A              ; Preserve the diagnostic for ARFAIL.
        SCF                        ; Return failure to the command entry.
        RET                        ; No partial output is reported as committed.
.BN: DB 0                         ; NOBJ stage-to-recovery rename succeeded.
.BC: DB 0                         ; COM stage-to-recovery rename succeeded.
.NI: DB 0                         ; Final NOBJ installation succeeded.
.CI: DB 0                         ; Final COM installation succeeded.
.F2: DS 36                        ; Private FCB used for recovery and rename calls.
