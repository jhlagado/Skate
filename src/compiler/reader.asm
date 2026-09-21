;=============================================================================
;  Skate native datum reader
;=============================================================================

;  PURPOSE
;  -------
;  Turn lexer tokens into structural events or interned literal values.
;  Consume the source incrementally; retain no complete datum.

;  PUBLIC INTERFACE
;  ----------------
;

;+---------------------------------------------------------------------------+
;|  RINIT - Attach a source and reset reader state.                          |
;|                                                                           |
;|  CALL                                                                     |
;|    HL -> byte-source callback.                                            |
;|    DE -> initialized symbol context.                                      |
;|    BC -> initialized string context.                                      |
;|    The two contexts must be disjoint.                                     |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    A = 0; carry clear.                                                    |
;+---------------------------------------------------------------------------+

;+---------------------------------------------------------------------------+
;|  RNEXT - Return one structural event or interned value.                   |
;|                                                                           |
;|  SUCCESS                                                                  |
;|    A = event kind; carry clear.                                           |
;|    For value kinds 5, 7 and 8: RTAG:HL = logical value.                   |
;|                                                                           |
;|  FAILURE                                                                  |
;|    A = reader error code; carry set.                                      |
;+---------------------------------------------------------------------------+

;  EVENT KINDS
;  -----------
;
;  0  EOF
;  1  open parenthesis
;  2  close parenthesis
;  3  quote
;  4  dot
;  5  symbol
;  7  scalar
;  8  string

;  ERROR CODES
;  -----------
;
;  128  syntax
;  129  capacity
;  130  integer range
;  131  encoding
;  132  source position
;  133  protocol

;  STATE AND DEPENDENCIES
;  ----------------------
;
;  EOF and errors stay terminal until RINIT.
;  LTOKOFF/LTOKLIN/LTOKCOL locate the current token.
;  Unfinished structure at EOF is reported at EOF.
;
;  AF/BC/DE/HL are clobbered. IX/IY are preserved; SP is balanced.
;  Static state makes the reader non-reentrant.
;
;  Requires lexer.asm, decimal.asm and interner.asm.
;  No Scheme heap. This stage checks root structure.
;  Form semantics belong to a later stage.
;  Source uses ATOM and documented Z80 instructions only.
;=============================================================================

; Bind the preinitialized permanent tables and reset structural state.
RINIT:
    LD (RSYMCTX),DE          ; Save the symbol-table context address.
    LD (RSTRCTX),BC          ; Save the string-table context address.
    XOR A                   ; Start with no nesting, terminal error or EOF.
    LD (RDEPTH),A           ; No list or quote prefix is open.
    LD (RERRCODE),A            ; Clear the previous terminal diagnostic.
    LD (REOFSEEN),A             ; Permit reading from the new callback.
    LD (RTAG),A             ; Clear the previous logical result tag.
    CALL LEXINIT              ; Initialize byte lookahead and source coordinates.
    RET C                   ; Propagate initialization failure if supplied.
    LD A,1                  ; Mark this reader ready for RNEXT.
    LD (RREADY),A           ; Publish readiness after lexical initialization.
    XOR A                   ; Return success, carry clear.
    RET                     ; Return with caller index registers preserved.

; Deliver one structural event or interned value; no whole datum is retained.
RNEXT:
    LD A,(RREADY)           ; An uninitialized callback must not be invoked.
    OR A                    ; Test the initialization flag.
    JP Z,RPROTERR             ; Reject use before RINIT.
    LD A,(RERRCODE)            ; Recover a prior terminal diagnostic.
    OR A                    ; Zero means this reader has not failed.
    JP NZ,RERRRET           ; Repeated reads preserve the original reason.
    XOR A                   ; No numeric marker belongs to the next source event.
    LD (RNUMFLT),A          ; DPARSE sets it again only for an inexact literal.
    LD A,(REOFSEEN)             ; A completed source needs no further callback.
    OR A                    ; Test whether EOF has already been delivered.
    JP NZ,REOFGOOD            ; Return stable EOF without touching the source.
    CALL LEXNEXT              ; Obtain one decoded lexical token.
    JP C,RLEXERR            ; Translate lexer-only errors to reader codes.
    LD (REVENT),A           ; Preserve the event kind across helpers.
    OR A                    ; Lexical kind zero is EOF.
    JP Z,REOFREAD               ; Check unfinished structure before accepting EOF.
    CP 2                    ; A close completes its containing list.
    JP Z,RCLOSE             ; Validate and pop that list.
    CP 4                    ; A dot changes the current list's tail state.
    JP Z,RDOTMARK               ; It does not begin a datum itself.
    PUSH HL                 ; Preserve lexical payload or token-buffer address.
    CALL RSTACKTP               ; Inspect the current structural frame, if any.
    CP 5                    ; State five means a dotted tail is already complete.
    POP HL                  ; Recover token data without changing the comparison.
    JP Z,RSYNTAX            ; No extra datum may follow a dotted tail.
    LD A,(REVENT)           ; Recover the kind after the parent-state check.
    CP 1                    ; Opening a list adds a new structural frame.
    JR Z,ROPENLST              ; Push an empty-list frame.
    CP 3                    ; Apostrophe needs exactly one following datum.
    JR Z,RQUOTEFR             ; Push a pending quote frame.
    CP 6                    ; Numeric tokens still need exact conversion.
    JR Z,RNUMERIC            ; Convert decimal text without intermediate rounding.
    CP 5                    ; Identifier bytes need permanent symbol identity.
    JR Z,RSYMBOL            ; Select the symbol table.
    CP 8                    ; Decoded string bytes need permanent string identity.
    JR Z,RSTRING            ; Select the string table.
    XOR A                   ; Remaining scalar tokens have logical tag zero.
    LD (RTAG),A             ; Preserve the lexer's scalar payload in HL.
    JR RATOMVAL                ; Complete this atomic datum.

; Native decimal conversion returns the language tag in A and payload in HL.
RNUMERIC:
    CALL DPARSE             ; Validate and convert the bounded numeric token.
    JP C,RERRSET             ; Numeric errors already use reader codes 128..130.
    LD (RTAG),A             ; Retain exact-integer versus floating representation.
    OR A                    ; The decimal parser uses tag zero for binary16 values.
    JR NZ,RNUMX             ; Tag three remains an ordinary exact integer event.
    LD A,1                  ; Mark this source event as an inexact numeric token.
    LD (RNUMFLT),A          ; The scope compiler preserves this bit through replay.
RNUMX:
    LD A,7                  ; Expose a scalar event after conversion.
    LD (REVENT),A           ; Hide the lexer's numeric-text event from callers.
    JR RATOMVAL                ; Complete the numeric datum.

; Interner contexts contain their own packed descriptors and name pools.
RSYMBOL:
    PUSH IX                 ; Preserve the caller's index-register contract.
    LD IX,(RSYMCTX)          ; Select symbol descriptors and packed names.
    CALL INTERN             ; Reuse an existing ID or append one checked entry.
    POP IX                  ; Restore IX without altering error carry.
    JP C,RINTERR            ; Translate table errors into reader diagnostics.
    LD A,H                  ; Combine the thirteen-bit index with symbol subtype.
    OR 20H                  ; Reference subtype one occupies payload bits 15..13.
    LD H,A                  ; HL is now the encoded symbol reference.
    JR RREFENC                 ; Return logical reference tag one.
RSTRING:
    PUSH IX                 ; Preserve the caller's index register.
    LD IX,(RSTRCTX)          ; Select immutable-string descriptors and byte pool.
    CALL INTERN             ; Equal decoded strings reuse the same identity.
    POP IX                  ; Restore IX while retaining the error flag.
    JP C,RINTERR            ; Fail if the configured table cannot accept the value.
    LD A,H                  ; Add the string reference subtype to the index.
    OR 80H                  ; Subtype four identifies a permanent string.
    LD H,A                  ; HL now holds the encoded string reference.
RREFENC:
    LD A,1                  ; Symbols and strings use logical reference tag one.
    LD (RTAG),A             ; Publish the logical result tag.
RATOMVAL:
    PUSH HL                 ; Completion may inspect the nesting workspace.
    CALL RCOMPDAT              ; Complete quotes and update the containing list.
    POP HL                  ; Restore the tagged result's payload.
    JR REVTGOOD               ; Return the event with carry clear.

; A frame is 00 empty list, 01 nonempty list, 03 awaiting dotted tail,
; 05 completed dotted tail, or 80 pending quote. Sixty-four frames are fixed.
ROPENLST:
    XOR A                   ; A newly opened list contains no completed datum.
    JR RPUSHFRM                ; Push its state on the bounded structure stack.
RQUOTEFR:
    LD A,80H                ; A quote prefix waits for one complete datum.
RPUSHFRM:
    LD C,A                  ; Preserve the new frame state while checking depth.
    LD A,(RDEPTH)           ; Read the number of occupied structural frames.
    CP 64                   ; The next push must fit the fixed 64-byte stack.
    JP NC,RCAPERR              ; Reject before writing beyond the workspace.
    LD E,A                  ; Use the old depth as the next frame's offset.
    LD D,0                  ; Widen the byte index to a word.
    LD HL,RSTACKBY            ; Locate the structural stack.
    ADD HL,DE               ; Address its first unused byte.
    LD (HL),C               ; Publish the pending list or quote state.
    INC A                   ; One more structural frame is now active.
    LD (RDEPTH),A           ; Record the new depth.
    JR REVTGOOD               ; Return the open or quote event.

; Close only a list with no missing dotted-tail datum.
RCLOSE:
    CALL RSTACKTP               ; A returns FF for no frame; HL addresses a real one.
    CP 80H                  ; Quote and absent-frame markers are not closable lists.
    JR NC,RSYNTAX           ; Reject ')' outside a list or immediately after quote.
    CP 3                    ; State three requires a datum after the dot.
    JR Z,RSYNTAX            ; A closing parenthesis cannot supply that datum.
    LD A,(RDEPTH)           ; Remove the just-closed list frame.
    DEC A                   ; The enclosing frame becomes the new top.
    LD (RDEPTH),A           ; Publish the reduced structural depth.
    CALL RCOMPDAT              ; The completed list may finish enclosing quotes.
    JR REVTGOOD               ; Emit its close event.

; A dot requires at least one completed element and no previous dot.
RDOTMARK:
    CALL RSTACKTP               ; Inspect the immediately containing frame.
    CP 1                    ; Only an ordinary nonempty list permits a dot.
    JR NZ,RSYNTAX           ; Reject bare dots, leading dots and repeated dots.
    LD (HL),3               ; This list now requires exactly one tail datum.
    JR REVTGOOD               ; Expose the separator to the consuming compiler.

; Return A=top state and HL=its address, or A=FF when the stack is empty.
RSTACKTP:
    LD A,(RDEPTH)           ; Read the current depth.
    OR A                    ; Zero has no addressable top frame.
    JR Z,REMPTY             ; Return the absent-frame marker.
    DEC A                   ; Convert depth to the final occupied offset.
    LD E,A                  ; Place that offset in DE.
    LD D,0                  ; The bounded stack uses a byte-sized offset.
    LD HL,RSTACKBY            ; Load the structure workspace base.
    ADD HL,DE               ; Address the top frame.
    LD A,(HL)               ; Return its state byte.
    RET                     ; Keep HL for a possible state update.
REMPTY:
    LD A,0FFH               ; Distinguish no parent from an empty list.
    RET                     ; No stack byte is accessed in this case.

; Completing one datum also completes every pending quote directly around it.
RCOMPDAT:
    CALL RSTACKTP               ; Read the enclosing frame after datum completion.
    CP 80H                  ; A pending quote encloses exactly this datum.
    JR NZ,RCPARENT          ; Otherwise update the enclosing list, if any.
    LD A,(RDEPTH)           ; Pop the completed quote wrapper.
    DEC A                   ; Move outward one structural level.
    LD (RDEPTH),A           ; Save the new depth.
    JR RCOMPDAT                ; Multiple apostrophes complete without recursion.
RCPARENT:
    CP 0FFH                 ; No parent means one top-level datum is complete.
    RET Z                   ; No structure is retained between top-level datums.
    CP 3                    ; Is this the required dotted-tail datum?
    LD A,1                  ; Default to an ordinary nonempty-list state.
    JR NZ,RCPSTORE          ; Ordinary elements only set the has-element state.
    LD A,5                  ; A completed dotted tail permits only ')'.
RCPSTORE:
    LD (HL),A               ; Update the containing list in place.
    RET                     ; Return without retaining any datum contents.

; EOF succeeds only when all lists and quote prefixes have completed.
REOFREAD:
    LD A,(RDEPTH)           ; Check for unfinished structure at lexical EOF.
    OR A                    ; Zero means the source ended between datums.
    JR NZ,RSYNTAX           ; Report incomplete structure at the EOF location.
    LD A,1                  ; Record terminal successful EOF.
    LD (REOFSEEN),A             ; Further calls need not invoke the source.
REOFGOOD:
    XOR A                   ; Event zero, carry clear.
    RET                     ; Return stable EOF.
REVTGOOD:
    LD A,(REVENT)           ; Restore the public event kind.
    OR A                    ; Clear carry without changing the event.
    RET                     ; RTAG:HL holds a result for atomic events.

; Keep native module error namespaces separate at the public reader boundary.
RLEXERR:
    CP 130                  ; Lexer encoding and position errors follow capacity.
    JR C,RERRSET             ; Syntax/capacity already match the public codes.
    INC A                   ; Leave code130 for exact-integer literal range.
    JR RERRSET               ; Publish translated encoding or position failure.
RINTERR:
    CP 1                    ; Interner capacity maps to reader capacity.
    JR Z,RCAPERR               ; Preserve the token's source location.
    JR RPROTERR               ; Invalid contexts are caller protocol failures.
RSYNTAX:
    LD A,128                ; Malformed or incomplete datum structure.
    JR RERRSET               ; Latch the reason for stable repeated calls.
RCAPERR:
    LD A,129                ; Fixed reader or interner capacity was exceeded.
    JR RERRSET               ; Preserve this diagnostic until reset.
RPROTERR:
    LD A,133                ; Initialization or interner contract violation.
RERRSET:
    LD (RERRCODE),A            ; Keep the original terminal diagnostic.
RERRRET:
    SCF                     ; Carry distinguishes failure from an event kind.
    RET                     ; Return through the original caller stack frame.

REND:                       ; Exclusive end of native reader instructions.
RWORK:                      ; Fixed reader state; input tables are caller-owned.
RSYMCTX: DW 0                ; Symbol interner context address.
RSTRCTX: DW 0                ; String interner context address.
RDEPTH: DB 0                ; Occupied list/quote structural frames, at most64.
RERRCODE: DB 0                 ; Terminal diagnostic, zero until an error.
REOFSEEN: DB 0                  ; One after successful EOF.
RREADY: DB 0                ; One after RINIT.
REVENT: DB 0                ; Current lexical/public event across helper calls.
RTAG: DB 0                  ; Logical tag for the most recent atomic result.
RNUMFLT: DB 0               ; One while the current source event is a binary16 literal.
RSTACKBY: DS 64               ; One state byte per outstanding list or quote.
RWEND:                      ; Exclusive end of fixed reader workspace.
