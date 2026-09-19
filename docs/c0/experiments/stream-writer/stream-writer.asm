; C0 bounded native streamed-NOBJ writer.
;
; The experiment owns two already-open private binary FCBs supplied by the
; caller: RPFCB is the NOBJ stage and SWPFCB is a patch spool.  The caller
; supplies declaration bytes and native image bytes as events.  No source
; image, syntax tree, or patch-site list is retained.
;
; Public ABI (A=0/C=0 succeeds, A=status/C=1 fails):
;   SWINIT      HL -> stage FCB prefix, DE -> patch-spool FCB prefix.
;               The prefixes are copied; the files must already be open.
;   SWDECB  A = one byte from the fixed three-record declaration prefix.
;   SWDECEND   End declarations.  The fixture contract is exactly 70 bytes.
;   SWIMGB A = one emitted native byte.  IMAGE records use 119-byte
;               payloads so their complete envelope fits one 128-byte record.
;   SWPATCH     HL = section offset, DE = stable source bytes, B = 1..4.
;               The caller promises non-overlap and final-image bounds; the
;               writer checks u16/capacity and spool-capacity bounds.
;   SWFINAL     Flush, rewrite SECTION length, copy PATCH spool, append LAYOUT,
;               reread staged bytes for CRC, and append COMMIT.
;   SWABORT     Abandon the generation.  A failed generation cannot finalise.
;
; The section declaration is the fixed C0 fixture contract used by the host
; tests: BEGIN (12 bytes), REGION (30), SECTION (28), with the four-byte
; SECTION length at serialized offset 51.  Declaration bytes are supplied by
; the caller and are not counted as production writer metadata.
;
; RPATCH is the reviewed bounded random-record helper.  It uses RPFCB/RPBUFFER
; for the stage rewrite.  The writer's own SWIMAGE buffer, SWPFCB/SWPBUF

%INCLUDE "stream-writer-all.asm"
