; Scope publication state, ASO header and CP/M staging records.
; Data labels are shared by the publication modules.
; ASO v1 header: magic, version one, COM origin $0100 and zero fill.
ASO_HEAD:
        DB $41,$53,$4f,$01,$00,$01,$00

; Compiler publication state and private CP/M FCBs.
PUB_GLB:  DW 0                   ; Staged address of global slot zero.
PUB_LOC:  DW 0                   ; Staged address of local slot zero.
.DESC:  DW 0                     ; Staged address of procedure descriptor zero.
PUB_SIZE:   DW 0                 ; Runtime image payload length.
PUB_ABS:   DW 0                  ; Temporary absolute address for a patch.
PUB_SRCP:    DW 0                ; Stream input cursor.
PUB_LEFT:   DW 0                 ; Remaining stream byte count.
ASO_FILL:   DW 0                 ; Staged source cursor for ASO IMAGE data.
ASO_ADDR:  DW 0                  ; Absolute address of the next ASO IMAGE.
ASO_LEN:  DW 0                   ; Current IMAGE payload length.
ASO_STOP:  DW 0                  ; ASO high-water and final-cursor word.
ASO_TOP:  DB 0                  ; ASO high-water top byte, one only at $10000.
ASO_OVER: DB 0                  ; Top byte of the current record endpoint.
ASO_FULL:  DB 0                 ; Top byte of contiguous IMAGE coverage.
ASO_CEIL:  DB 0                 ; Top byte of the current replay window end.
ASO_EDGE:  DW 0                 ; Low word of the current record endpoint.
PUB_TODO:   DW 0                 ; Remaining slot-fixup record count.
.DESCS:  DB 0                    ; Descriptors still waiting for serialization.
.DESC_IDX:  DB 0                 ; Descriptor index being serialized.
.FORMALS: DB 0                 ; Formal slot fields left in one descriptor.
PUB_FCB:    DS 36                ; Working stage or final output FCB.
PUB_DST:     DS 36               ; Destination FCB used by CPM_REN.
