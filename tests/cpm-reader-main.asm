; ============================================================================
; Native reader qualification program: SKREAD INPUT.SK8
; ============================================================================
;
; Runs the production reader against BDOS records. This is a reader diagnostic,
; not a compiler. Success means the entire source passed RNEXT and file close.
; The fixed test profile reserves $7000..$7FFF for the native stack.
;
        ORG 100H
        LD HL,(6)
        LD L,0
        LD DE,8000H
        OR A
        SBC HL,DE
        JP C,CRMEMERR    ; Reject before taking ownership of the native stack.
        LD SP,8000H
        LD HL,005CH     ; CCP supplies the first command argument's FCB prefix.
        CALL CSOPEN
        JP C,CRIOERR
        LD IX,CRSYMCXT
        CALL IINIT
        JP C,CRREADNO
        LD IX,CRSTRCXT
        CALL IINIT
        JP C,CRREADNO
        LD HL,CSBYTE
        LD DE,CRSYMCXT
        LD BC,CRSTRCXT
        CALL RINIT
CRLOOP: CALL RNEXT
        JP C,CRREADNO
        OR A
        JR NZ,CRLOOP    ; Drain every event, including nested structure.
        CALL CSCLOSE
        JP C,CRIOERR    ; Reader EOF alone cannot establish successful disk I/O.
        LD DE,CROK
        JP CRPRINT
CRREADNO:
        CALL CSCLOSE    ; Release the file even when syntax validation fails.
        JP C,CRIOERR
        LD DE,CRBAD
        JP CRPRINT
CRIOERR:
        LD DE,CRIO
        JP CRPRINT
CRMEMERR:
        LD DE,CRMEM
CRPRINT:
        LD C,9
        CALL 5
        JP 0            ; Return through CP/M warm boot to the CCP prompt.
CROK:   DB 82,69,65,68,32,79,75,13,10,36
CRBAD:  DB 82,69,65,68,32,69,82,82,79,82,13,10,36
CRIO:   DB 83,79,85,82,67,69,32,73,47,79,32,69,82,82,79,82,13,10,36
CRMEM:  DB 73,78,83,85,70,70,73,67,73,69,78,84,32,77,69,77,79,82,89,13,10,36
CRSYMCXT:
        DW CRSYMS,16,CRSYMPL,512,0,0
        DB 0,0
CRSTRCXT:
        DW CRSTRS,16,CRSTRPL,512,0,0
        DB 1,0
CRSYMS: DS 48
CRSTRS: DS 64
CRSYMPL: DS 512
CRSTRPL: DS 512
