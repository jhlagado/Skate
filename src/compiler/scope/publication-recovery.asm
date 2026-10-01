;=============================================================================
;  Recoverable CP/M publication for the scope compiler
;=============================================================================
;
;  SCOUT has already built complete COM and ASO stage files when these routines
;  run.  The previous generation is moved to sibling recovery names before a
;  new final name is installed.  A failed installation therefore restores the
;  old generation instead of deleting it. Legacy-object recovery names remain
;  for interrupted upgrades from older releases, but no new legacy object is installed.
;=============================================================================

; Replace the COM and ASO final outputs as one recoverable publication.
SCPUB:
        XOR A                      ; No old file has moved and no new file is installed.
        LD (SCOLD),A               ; Clear the old-generation bit mask.
        LD (SCINST),A              ; Clear the new-generation bit mask.
        LD A,'N'                   ; Select the legacy-object output class.
        LD (SCTYPE),A              ; Name helpers read the selected class here.
        LD A,1                     ; Bit zero records an old legacy-object recovery file.
        LD (SCMASK),A              ; SCSAVE uses this bit after a successful rename.
        CALL SCSAVE                ; Move a previous legacy object aside when it exists.
        JP C,SCPFAIL               ; Restore anything moved before reporting failure.
        LD A,'C'                   ; Select the COM output class.
        LD (SCTYPE),A              ; Keep the class across CP/M calls.
        LD A,2                     ; Bit one records an old COM recovery file.
        LD (SCMASK),A              ; SCSAVE uses this bit after a successful rename.
        CALL SCSAVE                ; Move the previous COM aside when it exists.
        JP C,SCPFAIL               ; Restore the legacy output if this move fails.
        LD A,'A'                   ; Select the ASO output class.
        LD (SCTYPE),A              ; Keep the class across CP/M calls.
        LD A,4                     ; Bit two records an old ASO recovery file.
        LD (SCMASK),A              ; SCSAVE uses this bit after a successful rename.
        CALL SCSAVE                ; Move the previous ASO aside when it exists.
        JP C,SCPFAIL               ; Restore earlier outputs if this move fails.
        LD A,'C'                   ; Install the staged COM next.
        LD (SCTYPE),A              ; Select CBS to COM for SCINSTAL.
        CALL SCINSTAL             ; Rename the complete COM stage.
        JP C,SCPFAIL               ; Remove COM and restore the old generation.
        LD A,2                     ; Mark the installed COM for rollback.
        CALL SCMARKIN            ; Add this bit to the installation mask.
        LD A,'A'                   ; Install the staged ASO last.
        LD (SCTYPE),A              ; Select SPL to ASO for SCINSTAL.
        CALL SCINSTAL             ; Rename the complete ASO stage.
        JP C,SCPFAIL               ; Remove installed files and restore the old set.
        LD A,4                     ; Mark the installed ASO for rollback.
        CALL SCMARKIN            ; Add this bit to the installation mask.
        CALL SCPDREC              ; Remove old recovery names after all installs.
        XOR A                      ; The two final names now form one generation.
        LD (SCOLD),A               ; No recovery is pending for this generation.
        LD (SCINST),A              ; No rollback is pending after a successful commit.
        RET                        ; Return success to the compiler command.

; Remove newly installed files and restore every old file that was moved.
SCPFAIL:
        CALL SCPROLL               ; Remove new files and restore the previous generation.
        LD HL,SCOUTTXT             ; Publication failures use the output diagnostic.
        LD (SCERRPTR),HL           ; Preserve that diagnostic for SCFAIL.
        SCF                        ; Report the publication failure to SCOUT.
        RET                        ; The command prints its ordinary output diagnostic.

; Save one existing final output under its recovery name.
SCSAVE:
        CALL SCFINALT              ; Build the selected final FCB in SCFCB.
        LD HL,SCFCB                ; Point CTOPENR at the final output.
        CALL CTOPENR               ; A carry means that this output is absent.
        JP C,SCSAVMIS            ; An absent old output needs no recovery record.
        CALL CTCLOSER              ; Close the successful existence probe.
        JP C,SCSAVBAD             ; Do not rename when the probe close failed.
        CALL SCRECFB              ; Copy the final basename and choose a recovery suffix.
        LD HL,SCFCB                ; The old final remains the rename source.
        LD DE,SCF2                 ; SCF2 contains the recovery destination.
        CALL CTRENAME               ; Move the old output out of the final name.
        JP C,SCSAVBAD             ; The caller rolls back earlier moves.
        LD A,(SCMASK)              ; Recover the bit assigned to this output class.
        LD B,A                     ; Keep that bit while loading the old mask.
        LD A,(SCOLD)               ; Read the outputs already moved to recovery names.
        OR B                       ; Record this output as recoverable.
        LD (SCOLD),A               ; Publish the updated old-generation mask.
SCSAVMIS:
        XOR A                      ; Missing outputs are a successful no-op.
        RET                        ; Continue with the next output class.
SCSAVBAD:
        SCF                        ; A CP/M failure prevents an unsafe replacement.
        RET                        ; The common rollback path restores prior files.

; Restore one recovery output, or discard a stale recovery after a committed run.
SCRESTOR:
        CALL SCRECT                ; Build the selected recovery FCB in SCFCB.
        LD HL,SCFCB                ; Point CTOPENR at the recovery output.
        CALL CTOPENR               ; A carry means that there is nothing to restore.
        JP C,SCRESMIS            ; Continue when this class has no recovery file.
        CALL CTCLOSER              ; Close the successful recovery existence probe.
        JP C,SCRESBAD             ; Keep the recovery file when close fails.
        LD A,(SCTYPE)              ; Preserve the selected class across stage probes.
        PUSH AF                    ; SCANY selects each class while probing.
        CALL SCANY                 ; Determine whether an interrupted install remains.
        POP AF                     ; Recover the class being restored.
        LD (SCTYPE),A              ; Name the selected final and recovery files again.
        LD A,(SCROLLF)             ; A rollback in this process always restores old data.
        OR A                       ; Do not classify a failed rollback as stale cleanup.
        JP NZ,SCRESTR               ; Preserve the recovery file until it is restored.
        LD A,(SCSTGF)              ; A set flag means that a stage still exists.
        OR A                       ; Select restoration for an incomplete transaction.
        JP NZ,SCRESTR               ; Restore the old file before staging a new one.
        CALL SCFDEST            ; Build the selected final FCB in SCF2.
        LD HL,SCF2                 ; Probe the final installed by a completed run.
        CALL CTOPENR               ; A missing final means that restoration is required.
        JP C,SCRESTR                 ; Restore the recovery file into its missing final.
        CALL CTCLOSER              ; Close the final existence probe.
        JP C,SCRESBAD             ; Preserve both files when the close failed.
        CALL SCRECT                ; Rebuild the recovery name after CTOPENR changed it.
        LD HL,SCFCB                ; Point CTDELETE at the stale recovery file.
        CALL CTDELETE              ; The new final is already the committed generation.
        RET                        ; Carry reports a cleanup error to the next compile.
SCRESTR:
        CALL SCFDEST            ; Build the final destination in SCF2.
        LD HL,SCF2                 ; Point CTDELETE at any partial new final.
        CALL CTDELETE              ; CP/M treats an absent final as a successful delete.
        JP C,SCRESBAD             ; Do not overwrite an uncertain directory entry.
        CALL SCRECT                ; Rebuild the recovery source in SCFCB.
        CALL SCFDEST            ; Rebuild the final destination in SCF2.
        LD HL,SCFCB                ; Point CTRENAME at the recovery source.
        LD DE,SCF2                 ; Point CTRENAME at the final destination.
        CALL CTRENAME               ; Restore the previous generation by name.
        JP C,SCRESBAD             ; Leave recovery in place when restoration fails.
SCRESMIS:
        XOR A                      ; A missing recovery file is normal.
        RET                        ; Continue recovery for the other output classes.
SCRESBAD:
        SCF                        ; Report a recovery operation that did not complete.
        RET                        ; The caller leaves the recovery name for retry.

; Restore stale recovery names before a new set of stages is opened.
SCPRECOV:
        LD A,'N'                   ; Recover the previous legacy object first.
        LD (SCTYPE),A              ; Select its recovery and final names.
        CALL SCRESTOR            ; Restore it or remove a committed stale copy.
        RET C                      ; Stop before touching a second output on failure.
        LD A,'C'                   ; Recover the previous COM next.
        LD (SCTYPE),A              ; Select the COM recovery and final names.
        CALL SCRESTOR            ; Restore it or remove a committed stale copy.
        RET C                      ; Preserve a recovery failure for the command.
        LD A,'A'                   ; Recover the previous ASO last.
        LD (SCTYPE),A              ; Select the ASO recovery and final names.
        CALL SCRESTOR            ; Restore it or remove a committed stale copy.
        RET C                      ; Preserve a recovery failure for the command.
        CALL SCPDSTA              ; Remove stages left by an interrupted rollback.
        RET                        ; Carry preserves a stage-delete failure for the command.

; Install the selected stage into its final name.
SCINSTAL:
        CALL SCSTAGET              ; Build NBS, CBS or SPL in SCFCB.
        CALL SCFDEST            ; Build NOB, COM or ASO in SCF2.
        LD HL,SCFCB                ; Point CTRENAME at the stage source.
        LD DE,SCF2                 ; Point CTRENAME at the final destination.
        JP CTRENAME                ; Return the CP/M rename result directly.

; Add the mask in A to the set of newly installed output files.
SCMARKIN:
        LD B,A                     ; Keep the new installation bit.
        LD A,(SCINST)              ; Read the installations already completed.
        OR B                       ; Add the current output class.
        LD (SCINST),A              ; Publish the rollback mask.
        RET                        ; Carry remains clear after memory operations.

; Delete recovery names after a successful publication.  A failed cleanup is
; harmless: SCPRECOV sees the final names and removes the stale copy next time.
SCPDREC:
        LD A,'N'                   ; Select the legacy-object recovery name.
        LD (SCTYPE),A              ; Name helpers read the class here.
        CALL SCRECT                ; Build NPR in SCFCB.
        LD HL,SCFCB                ; Point CTDELETE at the legacy-object recovery.
        CALL CTDELETE              ; Ignore cleanup carry; the final is committed.
        LD A,'C'                   ; Select the COM recovery name.
        LD (SCTYPE),A              ; Keep the class explicit for the next helper.
        CALL SCRECT                ; Build CPR in SCFCB.
        LD HL,SCFCB                ; Point CTDELETE at the recovery COM.
        CALL CTDELETE              ; A later SCPRECOV can retry a failed deletion.
        LD A,'A'                   ; Select the ASO recovery name.
        LD (SCTYPE),A              ; Keep the class explicit for the last helper.
        CALL SCRECT                ; Build APR in SCFCB.
        LD HL,SCFCB                ; Point CTDELETE at the recovery ASO.
        JP CTDELETE                ; Return the last cleanup result.

; Delete newly installed files, remove stages, and restore the old generation.
SCPROLL:
        LD A,1                     ; Tell SCRESTOR that this is a known rollback.
        LD (SCROLLF),A             ; Recovery must restore, never discard, old files.
        CALL SCPDINS               ; Remove only final names installed by this attempt.
        JR C,SCPRNS                ; Keep stages when a final delete failed.
        CALL SCPDSTA               ; Remove incomplete stage names before restoration.
SCPRNS:
        LD A,(SCOLD)               ; Read the old-generation recovery mask.
        AND 1                      ; Test the legacy-object recovery bit.
        JR Z,SCPRNOC               ; Skip restoration when no legacy object moved.
        LD A,'N'                   ; Select the legacy-object recovery name.
        LD (SCTYPE),A              ; Restore the selected old output.
        CALL SCRESTOR              ; The final name was removed above.
SCPRNOC:
        LD A,(SCOLD)               ; Read the old-generation recovery mask again.
        AND 2                      ; Test the COM recovery bit.
        JR Z,SCPRNOA               ; Skip restoration when no COM was moved.
        LD A,'C'                   ; Select the COM recovery name.
        LD (SCTYPE),A              ; Restore the selected old output.
        CALL SCRESTOR              ; Keep going after a best-effort restore.
SCPRNOA:
        LD A,(SCOLD)               ; Read the old-generation recovery mask once more.
        AND 4                      ; Test the ASO recovery bit.
        JR Z,SCPRCLR               ; Skip restoration when no ASO was moved.
        LD A,'A'                   ; Select the ASO recovery name.
        LD (SCTYPE),A              ; Restore the selected old output.
        CALL SCRESTOR              ; Keep recovery names when CP/M reports failure.
SCPRCLR:
        XOR A                      ; Rollback has no pending installation state.
        LD (SCOLD),A               ; Old recovery bits are restored or left visible.
        LD (SCINST),A              ; New final names were removed above.
        LD (SCROLLF),A             ; Future calls use normal restart classification.
        RET                        ; The caller reports the original publication error.

; Delete only final names whose corresponding new stages were installed.
SCPDINS:
        LD A,(SCINST)              ; Read the new-generation installation mask.
        AND 1                      ; Test the legacy-object installation bit.
        JR Z,SCPDINOC              ; Skip its delete when it was not installed.
        LD A,'N'                   ; Select the legacy-object final name.
        LD (SCTYPE),A              ; Name helpers read the class here.
        CALL SCFINALT              ; Build NOB in SCFCB.
        LD HL,SCFCB                ; Point CTDELETE at the new legacy object.
        CALL CTDELETE              ; Best-effort cleanup precedes restoration.
        RET C                      ; Leave the remaining stages as transaction proof.
SCPDINOC:
        LD A,(SCINST)              ; Read the installation mask again.
        AND 2                      ; Test the COM installation bit.
        JR Z,SCPDINOA              ; Skip a COM delete when it was not installed.
        LD A,'C'                   ; Select the COM final name.
        LD (SCTYPE),A              ; Name helpers read the class here.
        CALL SCFINALT              ; Build COM in SCFCB.
        LD HL,SCFCB                ; Point CTDELETE at the new COM.
        CALL CTDELETE              ; Best-effort cleanup precedes restoration.
        RET C                      ; Leave the remaining stages as transaction proof.
SCPDINOA:
        LD A,(SCINST)              ; Read the installation mask for the last class.
        AND 4                      ; Test the ASO installation bit.
        RET Z                      ; Skip an ASO delete when it was not installed.
        LD A,'A'                   ; Select the ASO final name.
        LD (SCTYPE),A              ; Name helpers read the class here.
        CALL SCFINALT              ; Build ASO in SCFCB.
        LD HL,SCFCB                ; Point CTDELETE at the new ASO.
        JP CTDELETE                ; Return the last cleanup result.

; Remove all three temporary stage names.
SCPDSTA:
        LD A,'N'                   ; Select the legacy-object stage.
        LD (SCTYPE),A              ; Build NBS in SCFCB.
        CALL SCSTAGET              ; Build the selected stage FCB.
        LD HL,SCFCB                ; Point CTDELETE at the legacy-object stage.
        CALL CTDELETE              ; Continue after a best-effort delete.
        RET C                      ; Preserve the failed stage as transaction proof.
        LD A,'C'                   ; Select the COM stage.
        LD (SCTYPE),A              ; Build CBS in SCFCB.
        CALL SCSTAGET              ; Build the selected stage FCB.
        LD HL,SCFCB                ; Point CTDELETE at the COM stage.
        CALL CTDELETE              ; Continue after a best-effort delete.
        RET C                      ; Preserve the failed stage as transaction proof.
        LD A,'A'                   ; Select the ASO stage.
        LD (SCTYPE),A              ; Build SPL in SCFCB.
        CALL SCSTAGET              ; Build the selected stage FCB.
        LD HL,SCFCB                ; Point CTDELETE at the ASO stage.
        JP CTDELETE                ; Return the last cleanup result.

; Build the selected final name in SCFCB from the command basename.
SCFINALT:
        CALL SCBASE                ; Copy drive and eight-character basename fields.
        LD HL,SCFCB+9              ; Point at the extension field.
        LD A,(SCTYPE)              ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first final extension letter.
        INC HL                     ; Advance to the second extension letter.
        CP 'A'                     ; ASO is the only final name with an S here.
        JR Z,SCFAS             ; Complete the ASO extension.
        LD (HL),'O'                ; NOB and COM both use O as their second letter.
        INC HL                     ; Advance to the final extension letter.
        CP 'N'                     ; Distinguish NOB from COM.
        JR Z,SCFNB             ; Complete the NOB extension.
        LD (HL),'M'                ; Complete the COM extension.
        RET                        ; Return with SCFCB pointing at the final COM.
SCFNB:
        LD (HL),'B'                ; Complete the NOB extension.
        RET                        ; Return with SCFCB pointing at the legacy object.
SCFAS:
        LD (HL),'S'                ; ASO uses S as its middle extension letter.
        INC HL                     ; Advance to the ASO suffix.
        LD (HL),'O'                ; Complete the ASO extension.
        RET                        ; Return with SCFCB pointing at the final ASO.

; Build the selected stage name in SCFCB from the command basename.
SCSTAGET:
        CALL SCBASE                ; Copy drive and eight-character basename fields.
        LD HL,SCFCB+9              ; Point at the extension field.
        LD A,(SCTYPE)              ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first stage extension letter.
        INC HL                     ; Advance to the second stage extension letter.
        CP 'A'                     ; The ASO stage is SPL rather than ABS.
        JR Z,SCSAS             ; Complete the ASO stage extension.
        LD (HL),'B'                ; Legacy-object and COM stages use B in the middle.
        INC HL                     ; Advance to the final stage extension letter.
        LD (HL),'S'                ; Complete NBS or CBS.
        RET                        ; Return with SCFCB pointing at the selected stage.
SCSAS:
        DEC HL                     ; Replace the class marker A with SPL's S.
        LD (HL),'S'                ; The private ASO stage uses SPL.
        INC HL                     ; Advance to the second spool letter.
        LD (HL),'P'                ; Mark the spool file explicitly.
        INC HL                     ; Advance to the final stage letter.
        LD (HL),'L'                ; Complete SPL.
        RET                        ; Return with SCFCB pointing at the ASO stage.

; Build the selected recovery name in SCFCB.
SCRECT:
        CALL SCBASE                ; Copy drive and eight-character basename fields.
        LD HL,SCFCB+9              ; Point at the extension field.
        LD A,(SCTYPE)              ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first recovery letter.
        INC HL                     ; Advance to the recovery marker.
        LD (HL),'P'                ; P marks a file saved during publication.
        INC HL                     ; Advance to the recovery suffix.
        LD (HL),'R'                ; R completes NPR, CPR or APR.
        RET                        ; Return with SCFCB pointing at recovery.

; Copy the selected source basename to SCF2 and make it the final destination.
SCFDEST:
        LD HL,SCFCB                ; Source FCB contains the current basename.
        LD DE,SCF2                 ; SCF2 receives a separate rename destination.
        LD BC,12                   ; Copy drive, name and extension fields.
        LDIR                       ; Preserve the source name while changing the suffix.
        LD HL,SCF2+9              ; Point at the destination extension.
        LD A,(SCTYPE)              ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first final extension letter.
        INC HL                     ; Advance to the second final extension letter.
        CP 'A'                     ; ASO is the only final name with an S here.
        JR Z,SCFDAS                ; Complete the ASO destination extension.
        LD (HL),'O'                ; NOB and COM both use O as their second letter.
        INC HL                     ; Advance to the final extension letter.
        CP 'N'                     ; Distinguish NOB from COM.
        JR Z,SCFDNB                ; Complete the NOB destination extension.
        LD (HL),'M'                ; Complete the COM destination extension.
        RET                        ; Return with SCF2 pointing at the final COM.
SCFDNB:
        LD (HL),'B'                ; Complete the NOB destination extension.
        RET                        ; Return with SCF2 pointing at the legacy object.
SCFDAS:
        LD (HL),'S'                ; ASO uses S as its middle extension letter.
        INC HL                     ; Advance to the ASO suffix.
        LD (HL),'O'                ; Complete the ASO destination extension.
        RET                        ; Return with SCF2 pointing at the final ASO.

; Copy the selected source basename to SCF2 and make it a recovery destination.
SCRECFB:
        LD HL,SCFCB                ; Source FCB contains the current final name.
        LD DE,SCF2                 ; SCF2 receives a separate rename destination.
        LD BC,12                   ; Copy drive, name and extension fields.
        LDIR                       ; Preserve the source name while changing the suffix.
        LD HL,SCF2+9              ; Point at the destination extension.
        LD A,(SCTYPE)              ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first recovery letter.
        INC HL                     ; Advance to the recovery marker.
        LD (HL),'P'                ; P marks a file saved during publication.
        INC HL                     ; Advance to the recovery suffix.
        LD (HL),'R'                ; R completes NPR, CPR or APR.
        RET                        ; Return with SCF2 pointing at recovery.

; Probe every stage to distinguish an unfinished transaction from committed
; output whose recovery cleanup was interrupted.
SCANY:
        XOR A                      ; Clear the stage-presence marker.
        LD (SCSTGF),A         ; No stage has been observed yet.
        LD A,'N'                   ; Probe NBS.
        LD (SCTYPE),A              ; Select the legacy-object stage.
        CALL SCTEST            ; Set the marker when NBS exists.
        LD A,'C'                   ; Probe CBS.
        LD (SCTYPE),A              ; Select the COM stage.
        CALL SCTEST            ; Set the marker when CBS exists.
        LD A,'A'                   ; Probe SPL.
        LD (SCTYPE),A              ; Select the ASO stage.
        CALL SCTEST            ; Set the marker when SPL exists.
        XOR A                      ; Missing stages are not recovery failures.
        RET                        ; The marker is returned through SCSTGF.

; Set SCSTGF when the selected stage can be opened for reading.
SCTEST:
        CALL SCSTAGET              ; Build the selected temporary stage FCB.
        LD HL,SCFCB                ; Point CTOPENR at that stage.
        CALL CTOPENR               ; A carry denotes an absent stage.
        RET C                      ; Leave the marker clear for an absent stage.
        LD A,1                     ; An open stage proves an incomplete transaction.
        LD (SCSTGF),A         ; Publish that fact before closing the probe.
        CALL CTCLOSER              ; Close the successful probe.
        XOR A                      ; Probe cleanup does not decide recovery policy.
        RET                        ; The stage marker remains set after this call.

; Publication state and the selected output class.
SCOLD:       DB 0                  ; Old final outputs moved to recovery names.
SCINST:      DB 0                  ; New final outputs installed from stage names.
SCMASK:      DB 0                  ; Bit assigned to the selected output class.
SCTYPE:      DB 0                  ; N, C or A for legacy object, COM or ASO.
SCSTGF: DB 0                  ; A stage remains during an interrupted commit.
SCROLLF: DB 0                 ; Nonzero while SCPROLL must restore old outputs.
