;=============================================================================
;  NOBJ section-5 staging helpers
;=============================================================================
;
;  These helpers are kept in their own ATOM source part because the native
;  procedure lowerer is already close to ATOM's 16-bit source-offset limit.
;  They serialize the small, shape-specific relocation set after the recipe
;  has been written, then let the publication code regenerate the recipe for
;  the final staged stream.
;=============================================================================

; Build the relocation records for the variable section after its recipe has
; been streamed.  The code slot remains bounded, but the record set is now
; shape-specific: scalar code has one service call, while the pair body has
; the four provider/root operands it actually uses.
N8DRECS:
        LD HL,0
        LD (N8DRECLN),HL
        XOR A
        LD (N8DRCNT),A
        LD HL,N8RECBUF
        LD (N8DRPTR),HL
        LD A,(N8CMODE)
        CP 3
        JR Z,N8DRGEN
        CP 1
        JR Z,N8DRPAIR
        LD A,(N8GARGC)
        CP 2
        JR Z,N8DRBIN
        LD DE,6
        JR N8DRSCAL
N8DRBIN:
        LD DE,11
N8DRSCAL:
        LD A,(N8GSVC)
        LD C,A
        LD B,0
        LD A,1
        JP N8DRSET
N8DRPAIR:
        LD DE,20
        LD BC,18
        LD A,1
        CALL N8DRSET
        LD DE,23
        LD BC,21
        LD A,2
        CALL N8DRSET
        LD DE,51
        LD BC,20
        LD A,2
        CALL N8DRSET
        LD DE,57
        LD BC,19
        LD A,1
        JP N8DRSET

; Emit one relocation for every nested arithmetic service call recorded by the
; native code generator.  The call table is separate from the output record
; buffer, so it remains available until CRC and COMMIT have been written.
N8DRGEN:
        LD A,(N8GCALLN)
        OR A
        RET Z
        LD (N8GLEFT),A
        LD HL,N8GCTBL
        LD (N8GTPTR),HL
N8DRGLP:
        LD HL,(N8GTPTR)
        LD E,(HL)
        INC HL
        LD D,(HL)
        LD (N8DRSITE),DE
        INC HL
        LD C,(HL)
        LD B,0
        LD (N8DRTGT),BC
        INC HL
        INC HL
        LD (N8GTPTR),HL
        LD A,1
        LD (N8DRUSE),A
        CALL N8DRADD
        LD A,(N8GLEFT)
        DEC A
        LD (N8GLEFT),A
        JR NZ,N8DRGLP
        RET

; Append one section-5 ABS16_RUN relocation.  NOBJ relocation records carry a
; three-byte envelope and a fourteen-byte payload.
N8DRSET:
        LD (N8DRSITE),DE
        LD (N8DRTGT),BC
        LD (N8DRUSE),A
N8DRADD:
        LD A,(N8DRCNT)
        INC A
        LD (N8DRCNT),A
        LD A,9
        CALL N8DRBYTE
        LD A,14
        CALL N8DRBYTE
        XOR A
        CALL N8DRBYTE
        LD A,5
        CALL N8DRBYTE
        XOR A
        CALL N8DRBYTE
        LD HL,(N8DRSITE)
        LD A,L
        CALL N8DRBYTE
        LD A,H
        CALL N8DRBYTE
        XOR A
        CALL N8DRBYTE
        CALL N8DRBYTE
        LD A,1
        CALL N8DRBYTE
        LD A,(N8DRUSE)
        CALL N8DRBYTE
        LD HL,(N8DRTGT)
        LD A,L
        CALL N8DRBYTE
        LD A,H
        CALL N8DRBYTE
        XOR A
        CALL N8DRBYTE
        CALL N8DRBYTE
        CALL N8DRBYTE
        CALL N8DRBYTE
        RET

; The checked-in skeleton already contains 65 records.  Add the
; shape-specific records before CRC and COMMIT are streamed.
N8CMSET:
        LD A,(N8DRCNT)
        ADD A,65
        LD DE,N8CMTCNT
        CALL N8OBJADR
        LD (HL),A
        INC HL
        XOR A
        LD (HL),A
        INC HL
        LD (HL),A
        INC HL
        LD (HL),A
        RET

N8DRBYTE:
        PUSH AF
        LD HL,(N8DRPTR)
        POP AF
        LD (HL),A
        INC HL
        LD (N8DRPTR),HL
        LD HL,(N8DRECLN)
        INC HL
        LD (N8DRECLN),HL
        RET

; Recreate the recipe after N8CRC has used its staging buffer for the dynamic
; relocation records.  N8STOBJ regenerates the records once the recipe is on
; disk, so both streams remain bounded by the existing spool.
N8RSTR:
        LD A,(N4RTAG)
        CP 1
        JR NZ,N8RZERO
        LD HL,(N4RVAL)
        JP N8SERIAL
N8RZERO:
        LD HL,0
        LD (N8OUTLEN),HL
        XOR A
        RET

; Dynamic relocation staging state.  N8RECBUF is safe here because the recipe
; has already been consumed by the preceding N8STOBJ stream when N8DRECS is
; called, and N8RSTR recreates it after CRC calculation.
N8DRECLN:   DW 0
N8DRCNT:    DB 0
N8DRPTR:    DW 0
N8DRSITE:   DW 0
N8DRTGT:    DW 0
N8DRUSE:    DB 0
N8GLEFT:    DB 0
N8GTPTR:    DW 0

; Stream the checked skeleton around the dynamic result, recipe and code.
N8STOBJ:
        LD HL,N4OBJ
        LD BC,N8MDOFF
        CALL N4STREAM
        RET C
        LD HL,N8MSGBUF
        LD BC,(N8MLEN)
        CALL N4STREAM
        RET C
        LD HL,N4OBJ
        LD DE,N8RREC
        ADD HL,DE
        LD BC,N8RSPAN
        CALL N4STREAM
        RET C
        LD HL,N8RHEAD
        LD BC,N8RHLEN
        CALL N4STREAM
        RET C
        LD HL,N8RECBUF
        LD BC,(N8OUTLEN)
        CALL N4STREAM
        RET C
        LD HL,N4OBJ
        LD DE,N8CHEAD
        ADD HL,DE
        LD BC,N8CSPAN
        CALL N4STREAM
        RET C
        LD HL,N4OBJ
        LD DE,N8CODOF
        ADD HL,DE
        LD BC,(N8CLENW)
        CALL N4STREAM
        RET C
        LD HL,N4OBJ
        LD DE,N8CSTAT
        ADD HL,DE
        LD BC,N8RELLN
        CALL N4STREAM
        RET C
        CALL N8DRECS
        CALL N8CMSET
        LD HL,N8RECBUF
        LD BC,(N8DRECLN)
        CALL N4STREAM
        RET C
        LD HL,N4OBJ
        LD DE,N8RELTAL
        ADD HL,DE
        LD BC,N8METAL
        CALL N4STREAM
        RET C
        LD DE,N4CRCOF
        CALL N8OBJADR
        LD BC,2
        JP N4STREAM

; Compute CRC-16/CCITT-FALSE over the same output pieces as N8STOBJ.
N8CRC:
        LD DE,0FFFFH
        LD HL,N4OBJ
        LD BC,N8MDOFF
        CALL N4CRSEG
        LD HL,N8MSGBUF
        LD BC,(N8MLEN)
        CALL N4CRSEG
        LD HL,N4OBJ
        LD BC,N8RREC
        ADD HL,BC
        LD BC,N8RSPAN
        CALL N4CRSEG
        LD HL,N8RHEAD
        LD BC,N8RHLEN
        CALL N4CRSEG
        LD HL,N8RECBUF
        LD BC,(N8OUTLEN)
        CALL N4CRSEG
        LD HL,N4OBJ
        PUSH DE
        LD DE,N8CHEAD
        ADD HL,DE
        POP DE
        LD BC,N8CSPAN
        CALL N4CRSEG
        LD HL,N4OBJ
        PUSH DE
        LD DE,N8CODOF
        ADD HL,DE
        POP DE
        LD BC,(N8CLENW)
        CALL N4CRSEG
        LD HL,N4OBJ
        PUSH DE
        LD DE,N8CSTAT
        ADD HL,DE
        POP DE
        LD BC,N8RELLN
        CALL N4CRSEG
        PUSH DE
        CALL N8DRECS
        POP DE
        PUSH DE
        CALL N8CMSET
        POP DE
        LD HL,N8RECBUF
        LD BC,(N8DRECLN)
        CALL N4CRSEG
        LD HL,N4OBJ
        PUSH DE
        LD DE,N8RELTAL
        ADD HL,DE
        POP DE
        LD BC,N8METAL
        CALL N4CRSEG
        LD HL,N4OBJ
        PUSH DE
        LD DE,N4CRCOF
        CALL N8OBJADR
        POP DE
        LD (HL),E
        INC HL
        LD (HL),D
        RET
