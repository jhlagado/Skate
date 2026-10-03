; Native datum reader.
; RD_INIT: HL -> byte callback, DE -> symbol context, BC -> string context.
; RD_NEXT: A = event kind; RD_TAG:HL carries value events; carry reports an error.
; EOF and errors remain terminal until RD_INIT. Events are EOF, list open/close,
; quote, dot, symbol, scalar and string (0, 1, 2, 3, 4, 5, 7 and 8).
; Error codes 128..133 identify syntax, capacity, integer range, encoding,
; source-position and protocol failures. IX/IY are preserved and SP is balanced.
; The symbol and string contexts must already be initialised, disjoint, and
; remain stable for the read. The byte callback must remain valid for RD_INIT's
; lifetime.
; The reader uses lexer, decimal and interner modules, retains no complete datum
; and keeps static, non-reentrant state.

RD_INIT:
    LD (RD_SYMS),DE          ; Save the symbol-table context address.
    LD (RD_STRS),BC          ; Save the string-table context address.
    XOR A                   ; Start with no nesting, terminal error or EOF.
    LD (RD_DEPTH),A         ; No list or quote prefix is open.
    LD (RD_CODE),A             ; Clear the previous terminal diagnostic.
    LD (RD_ENDED),A             ; Permit reading from the new callback.
    LD (RD_TAG),A           ; Clear the previous logical result tag.
    CALL LX_INIT              ; Initialize byte lookahead and source coordinates.
    RET C                   ; Propagate initialization failure if supplied.
    LD A,1                  ; Mark this reader ready for RD_NEXT.
    LD (RD_READY),A         ; Publish readiness after lexical initialization.
    XOR A                   ; Return success, carry clear.
    RET                     ; Return with caller index registers preserved.

; Deliver one structural event or interned value; no whole datum is retained.
RD_NEXT:
    LD A,(RD_READY)         ; An uninitialized callback must not be invoked.
    OR A                    ; Test the initialization flag.
    JP Z,RD_PROTO             ; Reject use before RD_INIT.
    LD A,(RD_CODE)             ; Recover a prior terminal diagnostic.
    OR A                    ; Zero means this reader has not failed.
    JP NZ,RD_ERR            ; Repeated reads preserve the original reason.
    XOR A                   ; No numeric marker belongs to the next source event.
    LD (RD_FLOAT),A         ; DEC_READ sets it again only for an inexact literal.
    LD A,(RD_ENDED)             ; A completed source needs no further callback.
    OR A                    ; Test whether EOF has already been delivered.
    JP NZ,RD_EOFOK            ; Return stable EOF without touching the source.
    CALL LX_NEXT              ; Obtain one decoded lexical token.
    JP C,RD_LEXER           ; Translate lexer-only errors to reader codes.
    LD (RD_EVENT),A         ; Preserve the event kind across helpers.
    OR A                    ; Lexical kind zero is EOF.
    JP Z,RD_EOF                 ; Check unfinished structure before accepting EOF.
    CP 2                    ; A close completes its containing list.
    JP Z,.CLOSE             ; Validate and pop that list.
    CP 4                    ; A dot changes the current list's tail state.
    JP Z,.DOT                   ; It does not begin a datum itself.
    PUSH HL                 ; Preserve lexical payload or token-buffer address.
    CALL RD_TOP                 ; Inspect the current structural frame, if any.
    CP 5                    ; State five means a dotted tail is already complete.
    POP HL                  ; Recover token data without changing the comparison.
    JP Z,RD_BAD             ; No extra datum may follow a dotted tail.
    LD A,(RD_EVENT)         ; Recover the kind after the parent-state check.
    CP 1                    ; Opening a list adds a new structural frame.
    JR Z,.OPEN                 ; Push an empty-list frame.
    CP 3                    ; Apostrophe needs exactly one following datum.
    JR Z,.QUOTE               ; Push a pending quote frame.
    CP 6                    ; Numeric tokens still need exact conversion.
    JR Z,.NUMBER             ; Convert decimal text without intermediate rounding.
    CP 5                    ; Identifier bytes need permanent symbol identity.
    JR Z,.SYMBOL            ; Select the symbol table.
    CP 8                    ; Decoded string bytes need permanent string identity.
    JR Z,.STRING            ; Select the string table.
    XOR A                   ; Remaining scalar tokens have logical tag zero.
    LD (RD_TAG),A           ; Preserve the lexer's scalar payload in HL.
    JR .ATOM                   ; Complete this atomic datum.

; Native decimal conversion returns the language tag in A and payload in HL.
.NUMBER:
    CALL DEC_READ           ; Validate and convert the bounded numeric token.
    JP C,RD_FAIL             ; Numeric errors already use reader codes 128..130.
    LD (RD_TAG),A           ; Retain exact-integer versus floating representation.
    OR A                    ; The decimal parser uses tag zero for binary16 values.
    JR NZ,.SCALAR           ; Tag three remains an ordinary exact integer event.
    LD A,1                  ; Mark this source event as an inexact numeric token.
    LD (RD_FLOAT),A         ; The scope compiler preserves this bit through replay.
.SCALAR:
    LD A,7                  ; Expose a scalar event after conversion.
    LD (RD_EVENT),A         ; Hide the lexer's numeric-text event from callers.
    JR .ATOM                   ; Complete the numeric datum.

; Interner contexts contain their own packed descriptors and name pools.
.SYMBOL:
    PUSH IX                 ; Preserve the caller's index-register contract.
    LD IX,(RD_SYMS)          ; Select symbol descriptors and packed names.
    CALL SYM_ID             ; Reuse an existing ID or append one checked entry.
    POP IX                  ; Restore IX without altering error carry.
    JP C,RD_TABLE           ; Translate table errors into reader diagnostics.
    LD A,H                  ; Combine the thirteen-bit index with symbol subtype.
    OR 20H                  ; Reference subtype one occupies payload bits 15..13.
    LD H,A                  ; HL is now the encoded symbol reference.
    JR .REF                    ; Return logical reference tag one.
.STRING:
    PUSH IX                 ; Preserve the caller's index register.
    LD IX,(RD_STRS)          ; Select immutable-string descriptors and byte pool.
    CALL SYM_ID             ; Equal decoded strings reuse the same identity.
    POP IX                  ; Restore IX while retaining the error flag.
    JP C,RD_TABLE           ; Fail if the configured table cannot accept the value.
    LD A,H                  ; Add the string reference subtype to the index.
    OR 80H                  ; Subtype four identifies a permanent string.
    LD H,A                  ; HL now holds the encoded string reference.
.REF:
    LD A,1                  ; Symbols and strings use logical reference tag one.
    LD (RD_TAG),A           ; Publish the logical result tag.
.ATOM:
    PUSH HL                 ; Completion may inspect the nesting workspace.
    CALL RD_DATUM              ; Complete quotes and update the containing list.
    POP HL                  ; Restore the tagged result's payload.
    JP RD_OK                  ; Return the event with carry clear.

; A frame is 00 empty list, 01 nonempty list, 03 awaiting dotted tail,
; 05 completed dotted tail, or 80 pending quote. Sixty-four frames are fixed.
.OPEN:
    XOR A                   ; A newly opened list contains no completed datum.
    JR .PUSH                   ; Push its state on the bounded structure stack.
.QUOTE:
    LD A,80H                ; A quote prefix waits for one complete datum.
.PUSH:
    LD C,A                  ; Preserve the new frame state while checking depth.
    LD A,(RD_DEPTH)         ; Read the number of occupied structural frames.
    CP 64                   ; The next push must fit the fixed 64-byte stack.
    JP NC,RD_FULL              ; Reject before writing beyond the workspace.
    LD E,A                  ; Use the old depth as the next frame's offset.
    LD D,0                  ; Widen the byte index to a word.
    LD HL,RD_STACK            ; Locate the structural stack.
    ADD HL,DE               ; Address its first unused byte.
    LD (HL),C               ; Publish the pending list or quote state.
    INC A                   ; One more structural frame is now active.
    LD (RD_DEPTH),A         ; Record the new depth.
    JP RD_OK                  ; Return the open or quote event.

; Close only a list with no missing dotted-tail datum.
.CLOSE:
    CALL RD_TOP                 ; A returns FF for no frame; HL addresses a real one.
    CP 80H                  ; Quote and absent-frame markers are not closable lists.
    JR NC,RD_BAD            ; Reject ')' outside a list or immediately after quote.
    CP 3                    ; State three requires a datum after the dot.
    JR Z,RD_BAD             ; A closing parenthesis cannot supply that datum.
    LD A,(RD_DEPTH)         ; Remove the just-closed list frame.
    DEC A                   ; The enclosing frame becomes the new top.
    LD (RD_DEPTH),A         ; Publish the reduced structural depth.
    CALL RD_DATUM              ; The completed list may finish enclosing quotes.
    JP RD_OK                  ; Emit its close event.

; A dot requires at least one completed element and no previous dot.
.DOT:
    CALL RD_TOP                 ; Inspect the immediately containing frame.
    CP 1                    ; Only an ordinary nonempty list permits a dot.
    JR NZ,RD_BAD            ; Reject bare dots, leading dots and repeated dots.
    LD (HL),3               ; This list now requires exactly one tail datum.
    JP RD_OK                  ; Expose the separator to the consuming compiler.

; Return A=top state and HL=its address, or A=FF when the stack is empty.
RD_TOP:
    LD A,(RD_DEPTH)         ; Read the current depth.
    OR A                    ; Zero has no addressable top frame.
    JR Z,.EMPTY             ; Return the absent-frame marker.
    DEC A                   ; Convert depth to the final occupied offset.
    LD E,A                  ; Place that offset in DE.
    LD D,0                  ; The bounded stack uses a byte-sized offset.
    LD HL,RD_STACK            ; Load the structure workspace base.
    ADD HL,DE               ; Address the top frame.
    LD A,(HL)               ; Return its state byte.
    RET                     ; Keep HL for a possible state update.
.EMPTY:
    LD A,0FFH               ; Distinguish no parent from an empty list.
    RET                     ; No stack byte is accessed in this case.

; Completing one datum also completes every pending quote directly around it.
RD_DATUM:
    CALL RD_TOP                 ; Read the enclosing frame after datum completion.
    CP 80H                  ; A pending quote encloses exactly this datum.
    JR NZ,.PARENT           ; Otherwise update the enclosing list, if any.
    LD A,(RD_DEPTH)         ; Pop the completed quote wrapper.
    DEC A                   ; Move outward one structural level.
    LD (RD_DEPTH),A         ; Save the new depth.
    JR RD_DATUM                ; Multiple apostrophes complete without recursion.
.PARENT:
    CP 0FFH                 ; No parent means one top-level datum is complete.
    RET Z                   ; No structure is retained between top-level datums.
    CP 3                    ; Is this the required dotted-tail datum?
    LD A,1                  ; Default to an ordinary nonempty-list state.
    JR NZ,.STORE            ; Ordinary elements only set the has-element state.
    LD A,5                  ; A completed dotted tail permits only ')'.
.STORE:
    LD (HL),A               ; Update the containing list in place.
    RET                     ; Return without retaining any datum contents.

; EOF succeeds only when all lists and quote prefixes have completed.
RD_EOF:
    LD A,(RD_DEPTH)         ; Check for unfinished structure at lexical EOF.
    OR A                    ; Zero means the source ended between datums.
    JP Z,RD_EOFOK            ; A complete source ends between datums.
    CALL LX_MARK             ; Refresh the location to the actual EOF cursor.
    JP RD_BAD                ; Report incomplete structure at the EOF location.
RD_EOFOK:
    LD A,1                  ; Record terminal successful EOF.
    LD (RD_ENDED),A         ; Further calls need not invoke the source.
    XOR A                   ; Event zero, carry clear.
    RET                     ; Return stable EOF.
RD_OK:
    LD A,(RD_EVENT)         ; Restore the public event kind.
    OR A                    ; Clear carry without changing the event.
    RET                     ; RD_TAG:HL holds a result for atomic events.

; Keep native module error namespaces separate at the public reader boundary.
RD_LEXER:
    CP 130                  ; Lexer encoding and position errors follow capacity.
    JR C,RD_FAIL             ; Syntax/capacity already match the public codes.
    INC A                   ; Leave code130 for exact-integer literal range.
    JR RD_FAIL               ; Publish translated encoding or position failure.
RD_TABLE:
    CP 1                    ; Interner capacity maps to reader capacity.
    JR Z,RD_FULL               ; Preserve the token's source location.
    JR RD_PROTO               ; Invalid contexts are caller protocol failures.
RD_BAD:
    LD A,128                ; Malformed or incomplete datum structure.
    JR RD_FAIL               ; Latch the reason for stable repeated calls.
RD_FULL:
    LD A,129                ; Fixed reader or interner capacity was exceeded.
    JR RD_FAIL               ; Preserve this diagnostic until reset.
RD_PROTO:
    LD A,133                ; Initialization or interner contract violation.
RD_FAIL:
    LD (RD_CODE),A             ; Keep the original terminal diagnostic.
RD_ERR:
    SCF                     ; Carry distinguishes failure from an event kind.
    RET                     ; Return through the original caller stack frame.

.CODE_END:                  ; Exclusive end of native reader instructions.
.WORK:                      ; Fixed reader state; input tables are caller-owned.
RD_SYMS: DW 0                ; Symbol interner context address.
RD_STRS: DW 0                ; String interner context address.
RD_DEPTH: DB 0              ; Occupied list/quote structural frames, at most64.
RD_CODE: DB 0                  ; Terminal diagnostic, zero until an error.
RD_ENDED: DB 0                  ; One after successful EOF.
RD_READY: DB 0              ; One after RD_INIT.
RD_EVENT: DB 0              ; Current lexical/public event across helper calls.
RD_TAG: DB 0                ; Logical tag for the most recent atomic result.
RD_FLOAT: DB 0              ; One while the current source event is a binary16 literal.
RD_STACK: DS 64               ; One state byte per outstanding list or quote.
.WORK_END:                  ; Exclusive end of fixed reader workspace.
