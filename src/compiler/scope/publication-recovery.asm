;=============================================================================
;  Recoverable CP/M publication for the scope compiler
;=============================================================================
;
;  PUB_MAIN has already built complete COM and ASO stage files when these routines
;  run.  The previous generation is moved to sibling recovery names before a
;  new final name is installed.  A failed installation therefore restores the
;  old generation instead of deleting it. Legacy-object recovery names remain
;  for interrupted upgrades from older releases, but no new legacy object is installed.
;=============================================================================

; Replace the COM and ASO final outputs as one recoverable publication.
PUB_SWAP:
        XOR A                      ; No old file has moved and no new file is installed.
        LD (PUB_OLD),A             ; Clear the old-generation bit mask.
        LD (PUB_NEW),A             ; Clear the new-generation bit mask.
        LD A,'N'                   ; Select the legacy-object output class.
        LD (PUB_KIND),A            ; Name helpers read the selected class here.
        LD A,1                     ; Bit zero records an old legacy-object recovery file.
        LD (PUB_BIT),A             ; .SAVE uses this bit after a successful rename.
        CALL .SAVE                 ; Move a previous legacy object aside when it exists.
        JR C,.FAIL                 ; Restore anything moved before reporting failure.
        LD A,'C'                   ; Select the COM output class.
        LD (PUB_KIND),A            ; Keep the class across CP/M calls.
        LD A,2                     ; Bit one records an old COM recovery file.
        LD (PUB_BIT),A             ; .SAVE uses this bit after a successful rename.
        CALL .SAVE                 ; Move the previous COM aside when it exists.
        JR C,.FAIL                 ; Restore the legacy output if this move fails.
        LD A,'A'                   ; Select the ASO output class.
        LD (PUB_KIND),A            ; Keep the class across CP/M calls.
        LD A,4                     ; Bit two records an old ASO recovery file.
        LD (PUB_BIT),A             ; .SAVE uses this bit after a successful rename.
        CALL .SAVE                 ; Move the previous ASO aside when it exists.
        JR C,.FAIL                 ; Restore earlier outputs if this move fails.
        LD A,'C'                   ; Install the staged COM next.
        LD (PUB_KIND),A            ; Select CBS to COM for PUB_MOVE.
        CALL PUB_MOVE             ; Rename the complete COM stage.
        JR C,.FAIL                 ; Remove COM and restore the old generation.
        LD A,2                     ; Mark the installed COM for rollback.
        CALL PUB_MARK            ; Add this bit to the installation mask.
        LD A,'A'                   ; Install the staged ASO last.
        LD (PUB_KIND),A            ; Select SPL to ASO for PUB_MOVE.
        CALL PUB_MOVE             ; Rename the complete ASO stage.
        JR C,.FAIL                 ; Remove installed files and restore the old set.
        LD A,4                     ; Mark the installed ASO for rollback.
        CALL PUB_MARK            ; Add this bit to the installation mask.
        CALL PUB_DROP             ; Remove old recovery names after all installs.
        XOR A                      ; The two final names now form one generation.
        LD (PUB_OLD),A             ; No recovery is pending for this generation.
        LD (PUB_NEW),A             ; No rollback is pending after a successful commit.
        RET                        ; Return success to the compiler command.

; Remove newly installed files and restore every old file that was moved.
.FAIL:
        CALL PUB_UNDO              ; Remove new files and restore the previous generation.
        LD HL,M_OUTPUT             ; Publication failures use the output diagnostic.
        LD (ST_ERROR),HL           ; Preserve that diagnostic for .FAIL.
        SCF                        ; Report the publication failure to PUB_MAIN.
        RET                        ; The command prints its ordinary output diagnostic.

; Save one existing final output under its recovery name.
.SAVE:
        CALL PUB_OUT               ; Build the selected final FCB in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_OPEN at the final output.
        CALL CPM_OPEN              ; A carry means that this output is absent.
        JR C,.ABSENT             ; An absent old output needs no recovery record.
        CALL CPM_ENDR              ; Close the successful existence probe.
        JR C,.SAVE_BAD            ; Do not rename when the probe close failed.
        CALL PUB_KEEP             ; Copy the final basename and choose a recovery suffix.
        LD HL,PUB_FCB              ; The old final remains the rename source.
        LD DE,PUB_DST              ; PUB_DST contains the recovery destination.
        CALL CPM_REN                ; Move the old output out of the final name.
        JR C,.SAVE_BAD            ; The caller rolls back earlier moves.
        LD A,(PUB_BIT)             ; Recover the bit assigned to this output class.
        LD B,A                     ; Keep that bit while loading the old mask.
        LD A,(PUB_OLD)             ; Read the outputs already moved to recovery names.
        OR B                       ; Record this output as recoverable.
        LD (PUB_OLD),A             ; Publish the updated old-generation mask.
.ABSENT:
        XOR A                      ; Missing outputs are a successful no-op.
        RET                        ; Continue with the next output class.
.SAVE_BAD:
        SCF                        ; A CP/M failure prevents an unsafe replacement.
        RET                        ; The common rollback path restores prior files.

; Restore one recovery output, or discard a stale recovery after a committed run.
PUB_HEAL:
        CALL PUB_PREV              ; Build the selected recovery FCB in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_OPEN at the recovery output.
        CALL CPM_OPEN              ; A carry means that there is nothing to restore.
        JR C,.ABSENT             ; Continue when this class has no recovery file.
        CALL CPM_ENDR              ; Close the successful recovery existence probe.
        JR C,.FAIL                ; Keep the recovery file when close fails.
        LD A,(PUB_KIND)            ; Preserve the selected class across stage probes.
        PUSH AF                    ; PUB_ANY selects each class while probing.
        CALL PUB_ANY               ; Determine whether an interrupted install remains.
        POP AF                     ; Recover the class being restored.
        LD (PUB_KIND),A            ; Name the selected final and recovery files again.
        LD A,(PUB_ROLL)            ; A rollback in this process always restores old data.
        OR A                       ; Do not classify a failed rollback as stale cleanup.
        JR NZ,.RESTORE              ; Preserve the recovery file until it is restored.
        LD A,(PUB_LIVE)            ; A set flag means that a stage still exists.
        OR A                       ; Select restoration for an incomplete transaction.
        JR NZ,.RESTORE              ; Restore the old file before staging a new one.
        CALL PUB_DEST           ; Build the selected final FCB in PUB_DST.
        LD HL,PUB_DST              ; Probe the final installed by a completed run.
        CALL CPM_OPEN              ; A missing final means that restoration is required.
        JR C,.RESTORE                ; Restore the recovery file into its missing final.
        CALL CPM_ENDR              ; Close the final existence probe.
        JR C,.FAIL                ; Preserve both files when the close failed.
        CALL PUB_PREV              ; Rebuild the recovery name after CPM_OPEN changed it.
        LD HL,PUB_FCB              ; Point CPM_ERA at the stale recovery file.
        CALL CPM_ERA               ; The new final is already the committed generation.
        RET                        ; Carry reports a cleanup error to the next compile.
.RESTORE:
        CALL PUB_DEST           ; Build the final destination in PUB_DST.
        LD HL,PUB_DST              ; Point CPM_ERA at any partial new final.
        CALL CPM_ERA               ; CP/M treats an absent final as a successful delete.
        JR C,.FAIL                ; Do not overwrite an uncertain directory entry.
        CALL PUB_PREV              ; Rebuild the recovery source in PUB_FCB.
        CALL PUB_DEST           ; Rebuild the final destination in PUB_DST.
        LD HL,PUB_FCB              ; Point CPM_REN at the recovery source.
        LD DE,PUB_DST              ; Point CPM_REN at the final destination.
        CALL CPM_REN                ; Restore the previous generation by name.
        JR C,.FAIL                ; Leave recovery in place when restoration fails.
.ABSENT:
        XOR A                      ; A missing recovery file is normal.
        RET                        ; Continue recovery for the other output classes.
.FAIL:
        SCF                        ; Report a recovery operation that did not complete.
        RET                        ; The caller leaves the recovery name for retry.

; Restore stale recovery names before a new set of stages is opened.
PUB_TIDY:
        LD A,'N'                   ; Recover the previous legacy object first.
        LD (PUB_KIND),A            ; Select its recovery and final names.
        CALL PUB_HEAL            ; Restore it or remove a committed stale copy.
        RET C                      ; Stop before touching a second output on failure.
        LD A,'C'                   ; Recover the previous COM next.
        LD (PUB_KIND),A            ; Select the COM recovery and final names.
        CALL PUB_HEAL            ; Restore it or remove a committed stale copy.
        RET C                      ; Preserve a recovery failure for the command.
        LD A,'A'                   ; Recover the previous ASO last.
        LD (PUB_KIND),A            ; Select the ASO recovery and final names.
        CALL PUB_HEAL            ; Restore it or remove a committed stale copy.
        RET C                      ; Preserve a recovery failure for the command.
        CALL PUB_WIPE             ; Remove stages left by an interrupted rollback.
        RET                        ; Carry preserves a stage-delete failure for the command.

; Install the selected stage into its final name.
PUB_MOVE:
        CALL PUB_TEMP              ; Build NBS, CBS or SPL in PUB_FCB.
        CALL PUB_DEST           ; Build NOB, COM or ASO in PUB_DST.
        LD HL,PUB_FCB              ; Point CPM_REN at the stage source.
        LD DE,PUB_DST              ; Point CPM_REN at the final destination.
        JP CPM_REN                 ; Return the CP/M rename result directly.

; Add the mask in A to the set of newly installed output files.
PUB_MARK:
        LD B,A                     ; Keep the new installation bit.
        LD A,(PUB_NEW)             ; Read the installations already completed.
        OR B                       ; Add the current output class.
        LD (PUB_NEW),A             ; Publish the rollback mask.
        RET                        ; Carry remains clear after memory operations.

; Delete recovery names after a successful publication.  A failed cleanup is
; harmless: PUB_TIDY sees the final names and removes the stale copy next time.
PUB_DROP:
        LD A,'N'                   ; Select the legacy-object recovery name.
        LD (PUB_KIND),A            ; Name helpers read the class here.
        CALL PUB_PREV              ; Build NPR in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the legacy-object recovery.
        CALL CPM_ERA               ; Ignore cleanup carry; the final is committed.
        LD A,'C'                   ; Select the COM recovery name.
        LD (PUB_KIND),A            ; Keep the class explicit for the next helper.
        CALL PUB_PREV              ; Build CPR in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the recovery COM.
        CALL CPM_ERA               ; A later PUB_TIDY can retry a failed deletion.
        LD A,'A'                   ; Select the ASO recovery name.
        LD (PUB_KIND),A            ; Keep the class explicit for the last helper.
        CALL PUB_PREV              ; Build APR in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the recovery ASO.
        JP CPM_ERA                 ; Return the last cleanup result.

; Delete newly installed files, remove stages, and restore the old generation.
PUB_UNDO:
        LD A,1                     ; Tell PUB_HEAL that this is a known rollback.
        LD (PUB_ROLL),A            ; Recovery must restore, never discard, old files.
        CALL .DEL_NEW              ; Remove only final names installed by this attempt.
        JR C,.OLD_OBJ              ; Keep stages when a final delete failed.
        CALL PUB_WIPE              ; Remove incomplete stage names before restoration.
.OLD_OBJ:
        LD A,(PUB_OLD)             ; Read the old-generation recovery mask.
        AND 1                      ; Test the legacy-object recovery bit.
        JR Z,.OLD_COM              ; Skip restoration when no legacy object moved.
        LD A,'N'                   ; Select the legacy-object recovery name.
        LD (PUB_KIND),A            ; Restore the selected old output.
        CALL PUB_HEAL              ; The final name was removed above.
.OLD_COM:
        LD A,(PUB_OLD)             ; Read the old-generation recovery mask again.
        AND 2                      ; Test the COM recovery bit.
        JR Z,.OLD_ASO              ; Skip restoration when no COM was moved.
        LD A,'C'                   ; Select the COM recovery name.
        LD (PUB_KIND),A            ; Restore the selected old output.
        CALL PUB_HEAL              ; Keep going after a best-effort restore.
.OLD_ASO:
        LD A,(PUB_OLD)             ; Read the old-generation recovery mask once more.
        AND 4                      ; Test the ASO recovery bit.
        JR Z,.CLEAR                ; Skip restoration when no ASO was moved.
        LD A,'A'                   ; Select the ASO recovery name.
        LD (PUB_KIND),A            ; Restore the selected old output.
        CALL PUB_HEAL              ; Keep recovery names when CP/M reports failure.
.CLEAR:
        XOR A                      ; Rollback has no pending installation state.
        LD (PUB_OLD),A             ; Old recovery bits are restored or left visible.
        LD (PUB_NEW),A             ; New final names were removed above.
        LD (PUB_ROLL),A            ; Future calls use normal restart classification.
        RET                        ; The caller reports the original publication error.

; Delete only final names whose corresponding new stages were installed.
.DEL_NEW:
        LD A,(PUB_NEW)             ; Read the new-generation installation mask.
        AND 1                      ; Test the legacy-object installation bit.
        JR Z,.NEW_COM              ; Skip its delete when it was not installed.
        LD A,'N'                   ; Select the legacy-object final name.
        LD (PUB_KIND),A            ; Name helpers read the class here.
        CALL PUB_OUT               ; Build NOB in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the new legacy object.
        CALL CPM_ERA               ; Best-effort cleanup precedes restoration.
        RET C                      ; Leave the remaining stages as transaction proof.
.NEW_COM:
        LD A,(PUB_NEW)             ; Read the installation mask again.
        AND 2                      ; Test the COM installation bit.
        JR Z,.NEW_ASO              ; Skip a COM delete when it was not installed.
        LD A,'C'                   ; Select the COM final name.
        LD (PUB_KIND),A            ; Name helpers read the class here.
        CALL PUB_OUT               ; Build COM in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the new COM.
        CALL CPM_ERA               ; Best-effort cleanup precedes restoration.
        RET C                      ; Leave the remaining stages as transaction proof.
.NEW_ASO:
        LD A,(PUB_NEW)             ; Read the installation mask for the last class.
        AND 4                      ; Test the ASO installation bit.
        RET Z                      ; Skip an ASO delete when it was not installed.
        LD A,'A'                   ; Select the ASO final name.
        LD (PUB_KIND),A            ; Name helpers read the class here.
        CALL PUB_OUT               ; Build ASO in PUB_FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the new ASO.
        JP CPM_ERA                 ; Return the last cleanup result.

; Remove all three temporary stage names.
PUB_WIPE:
        LD A,'N'                   ; Select the legacy-object stage.
        LD (PUB_KIND),A            ; Build NBS in PUB_FCB.
        CALL PUB_TEMP              ; Build the selected stage FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the legacy-object stage.
        CALL CPM_ERA               ; Continue after a best-effort delete.
        RET C                      ; Preserve the failed stage as transaction proof.
        LD A,'C'                   ; Select the COM stage.
        LD (PUB_KIND),A            ; Build CBS in PUB_FCB.
        CALL PUB_TEMP              ; Build the selected stage FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the COM stage.
        CALL CPM_ERA               ; Continue after a best-effort delete.
        RET C                      ; Preserve the failed stage as transaction proof.
        LD A,'A'                   ; Select the ASO stage.
        LD (PUB_KIND),A            ; Build SPL in PUB_FCB.
        CALL PUB_TEMP              ; Build the selected stage FCB.
        LD HL,PUB_FCB              ; Point CPM_ERA at the ASO stage.
        JP CPM_ERA                 ; Return the last cleanup result.

; Build the selected final name in PUB_FCB from the command basename.
PUB_OUT:
        CALL PUB_BASE              ; Copy drive and eight-character basename fields.
        LD HL,PUB_FCB+9            ; Point at the extension field.
        LD A,(PUB_KIND)            ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first final extension letter.
        INC HL                     ; Advance to the second extension letter.
        CP 'A'                     ; ASO is the only final name with an S here.
        JR Z,.ASO              ; Complete the ASO extension.
        LD (HL),'O'                ; NOB and COM both use O as their second letter.
        INC HL                     ; Advance to the final extension letter.
        CP 'N'                     ; Distinguish NOB from COM.
        JR Z,.NOB              ; Complete the NOB extension.
        LD (HL),'M'                ; Complete the COM extension.
        RET                        ; Return with PUB_FCB pointing at the final COM.
.NOB:
        LD (HL),'B'                ; Complete the NOB extension.
        RET                        ; Return with PUB_FCB pointing at the legacy object.
.ASO:
        LD (HL),'S'                ; ASO uses S as its middle extension letter.
        INC HL                     ; Advance to the ASO suffix.
        LD (HL),'O'                ; Complete the ASO extension.
        RET                        ; Return with PUB_FCB pointing at the final ASO.

; Build the selected stage name in PUB_FCB from the command basename.
PUB_TEMP:
        CALL PUB_BASE              ; Copy drive and eight-character basename fields.
        LD HL,PUB_FCB+9            ; Point at the extension field.
        LD A,(PUB_KIND)            ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first stage extension letter.
        INC HL                     ; Advance to the second stage extension letter.
        CP 'A'                     ; The ASO stage is SPL rather than ABS.
        JR Z,.SPL              ; Complete the ASO stage extension.
        LD (HL),'B'                ; Legacy-object and COM stages use B in the middle.
        INC HL                     ; Advance to the final stage extension letter.
        LD (HL),'S'                ; Complete NBS or CBS.
        RET                        ; Return with PUB_FCB pointing at the selected stage.
.SPL:
        DEC HL                     ; Replace the class marker A with SPL's S.
        LD (HL),'S'                ; The private ASO stage uses SPL.
        INC HL                     ; Advance to the second spool letter.
        LD (HL),'P'                ; Mark the spool file explicitly.
        INC HL                     ; Advance to the final stage letter.
        LD (HL),'L'                ; Complete SPL.
        RET                        ; Return with PUB_FCB pointing at the ASO stage.

; Build the selected recovery name in PUB_FCB.
PUB_PREV:
        CALL PUB_BASE              ; Copy drive and eight-character basename fields.
        LD HL,PUB_FCB+9            ; Point at the extension field.
        LD A,(PUB_KIND)            ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first recovery letter.
        INC HL                     ; Advance to the recovery marker.
        LD (HL),'P'                ; P marks a file saved during publication.
        INC HL                     ; Advance to the recovery suffix.
        LD (HL),'R'                ; R completes NPR, CPR or APR.
        RET                        ; Return with PUB_FCB pointing at recovery.

; Copy the selected source basename to PUB_DST and make it the final destination.
PUB_DEST:
        LD HL,PUB_FCB              ; Source FCB contains the current basename.
        LD DE,PUB_DST              ; PUB_DST receives a separate rename destination.
        LD BC,12                   ; Copy drive, name and extension fields.
        LDIR                       ; Preserve the source name while changing the suffix.
        LD HL,PUB_DST+9           ; Point at the destination extension.
        LD A,(PUB_KIND)            ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first final extension letter.
        INC HL                     ; Advance to the second final extension letter.
        CP 'A'                     ; ASO is the only final name with an S here.
        JR Z,.ASO                  ; Complete the ASO destination extension.
        LD (HL),'O'                ; NOB and COM both use O as their second letter.
        INC HL                     ; Advance to the final extension letter.
        CP 'N'                     ; Distinguish NOB from COM.
        JR Z,.NOB                  ; Complete the NOB destination extension.
        LD (HL),'M'                ; Complete the COM destination extension.
        RET                        ; Return with PUB_DST pointing at the final COM.
.NOB:
        LD (HL),'B'                ; Complete the NOB destination extension.
        RET                        ; Return with PUB_DST pointing at the legacy object.
.ASO:
        LD (HL),'S'                ; ASO uses S as its middle extension letter.
        INC HL                     ; Advance to the ASO suffix.
        LD (HL),'O'                ; Complete the ASO destination extension.
        RET                        ; Return with PUB_DST pointing at the final ASO.

; Copy the selected source basename to PUB_DST and make it a recovery destination.
PUB_KEEP:
        LD HL,PUB_FCB              ; Source FCB contains the current final name.
        LD DE,PUB_DST              ; PUB_DST receives a separate rename destination.
        LD BC,12                   ; Copy drive, name and extension fields.
        LDIR                       ; Preserve the source name while changing the suffix.
        LD HL,PUB_DST+9           ; Point at the destination extension.
        LD A,(PUB_KIND)            ; Read the selected output class.
        LD (HL),A                  ; N, C or A is the first recovery letter.
        INC HL                     ; Advance to the recovery marker.
        LD (HL),'P'                ; P marks a file saved during publication.
        INC HL                     ; Advance to the recovery suffix.
        LD (HL),'R'                ; R completes NPR, CPR or APR.
        RET                        ; Return with PUB_DST pointing at recovery.

; Probe every stage to distinguish an unfinished transaction from committed
; output whose recovery cleanup was interrupted.
PUB_ANY:
        XOR A                      ; Clear the stage-presence marker.
        LD (PUB_LIVE),A       ; No stage has been observed yet.
        LD A,'N'                   ; Probe NBS.
        LD (PUB_KIND),A            ; Select the legacy-object stage.
        CALL .PROBE            ; Set the marker when NBS exists.
        LD A,'C'                   ; Probe CBS.
        LD (PUB_KIND),A            ; Select the COM stage.
        CALL .PROBE            ; Set the marker when CBS exists.
        LD A,'A'                   ; Probe SPL.
        LD (PUB_KIND),A            ; Select the ASO stage.
        CALL .PROBE            ; Set the marker when SPL exists.
        XOR A                      ; Missing stages are not recovery failures.
        RET                        ; The marker is returned through PUB_LIVE.

; Set PUB_LIVE when the selected stage can be opened for reading.
.PROBE:
        CALL PUB_TEMP              ; Build the selected temporary stage FCB.
        LD HL,PUB_FCB              ; Point CPM_OPEN at that stage.
        CALL CPM_OPEN              ; A carry denotes an absent stage.
        RET C                      ; Leave the marker clear for an absent stage.
        LD A,1                     ; An open stage proves an incomplete transaction.
        LD (PUB_LIVE),A       ; Publish that fact before closing the probe.
        CALL CPM_ENDR              ; Close the successful probe.
        XOR A                      ; Probe cleanup does not decide recovery policy.
        RET                        ; The stage marker remains set after this call.

; Publication state and the selected output class.
PUB_OLD:       DB 0                ; Old final outputs moved to recovery names.
PUB_NEW:      DB 0                 ; New final outputs installed from stage names.
PUB_BIT:      DB 0                 ; Bit assigned to the selected output class.
PUB_KIND:      DB 0                ; N, C or A for legacy object, COM or ASO.
PUB_LIVE: DB 0                ; A stage remains during an interrupted commit.
PUB_ROLL: DB 0                ; Nonzero while PUB_UNDO must restore old outputs.
