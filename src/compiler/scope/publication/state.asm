; Scope publication state, ASO header and CP/M staging records.
; Data labels are shared by the publication modules.
; ASO v1 header: magic, version one, COM origin $0100 and zero fill.
SCAHEAD:
        DB $41,$53,$4f,$01,$00,$01,$00

; Compiler publication state and private CP/M FCBs.
SCGBASE:  DW 0                   ; Staged address of global slot zero.
SCLBASE:  DW 0                   ; Staged address of local slot zero.
SCPBASE:  DW 0                   ; Staged address of procedure descriptor zero.
SCIMGL:   DW 0                   ; Runtime image payload length.
SCTARG:   DW 0                   ; Temporary absolute address for a patch.
SCPTR:    DW 0                   ; Stream input cursor.
SCLEFT:   DW 0                   ; Remaining stream byte count.
SCAIMG:   DW 0                   ; Staged source cursor for ASO IMAGE data.
SCAADDR:  DW 0                   ; Absolute address of the next ASO IMAGE.
SCACHUNK:  DW 0                  ; Current IMAGE payload length.
SCAENDP:  DW 0                   ; ASO high-water and final-cursor word.
SCAETOP:  DB 0                  ; ASO high-water top byte, one only at $10000.
SCAEPTOP: DB 0                  ; Top byte of the current record endpoint.
SCAIMGT:  DB 0                  ; Top byte of contiguous IMAGE coverage.
SCAWTOP:  DB 0                  ; Top byte of the current replay window end.
SCAEPTR:  DW 0                  ; Low word of the current record endpoint.
SCFIXC:   DW 0                   ; Remaining slot-fixup record count.
SCPDREM:  DB 0                   ; Descriptors still waiting for serialization.
SCPDIDX:  DB 0                   ; Descriptor index being serialized.
SCPDSLT: DB 0                  ; Formal slot fields left in one descriptor.
SCFCB:    DS 36                  ; Working stage or final output FCB.
SCF2:     DS 36                  ; Destination FCB used by CTRENAME.
