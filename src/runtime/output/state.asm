; Runtime state shared by output, invocation, storage and publication.
; These definitions remain after output code to preserve the image layout.
RT_TAG:  DB 0                 ; Original tag retained by RT_TEST.
RT_BOOL:      DB 0                 ; Branch decision retained while restoring A.
PRIM_ID:       DB 0                ; Predefined primitive kind for the active call.
ARG_CNT:      DB 0                 ; Number of values in the current call packet.
REST_ON:     DB 0                  ; High-bit policy for the active procedure.
REST_MIN:     DB 0                 ; Fixed minimum arity of the active procedure.
REST_CNT:     DB 0                 ; Surplus values still waiting for the rest list.
REST_IDX:     DB 0                 ; Packet index while reading surplus values.
REST_LEN:     DB 0                 ; Original surplus count passed to QT_FOLD.
ROOT_TOP:       DW 0               ; Newest pending-operand record, or zero.
ROOT_RET:       DW 0               ; ARG_PUSH's continuation while it pushes.
; The allocation maps use a fixed work band outside the provider image,
; B800H..CF00H, just below the transient bands.  Below them the heap grows up
; from the image and the stack down from B800H.
ROOT_VAL:     DW 0                 ; ARG_PUSH's payload while it pushes.
; These maps cover the full 3000H..C000H address span, including images
; below 4000H.
CL_MAP      EQU 0B800H            ; 2304 bytes mark every allocated closure start.
GC_MARKS      EQU 0C100H          ; 2304 bytes: even marks, odd vector type bits.
BND_MAP       EQU 0CA00H          ; 1152 bytes: one bit per four-byte binding cell.
NUM_LEFT:     DB 0                 ; Remaining values in an arithmetic or compare fold.
NUM_ATAG:     DB 0                 ; Accumulator tag for a variadic numeric fold.
NUM_AEXT:     DB 0                 ; Accumulator byte 2 for a variadic numeric fold.
NUM_VEXT:     DB 0                 ; Current packet value byte 2 during numeric work.
NUM_TAG:      DB 0                 ; Current packet value tag during numeric work.
NUM_PTR:      DW 0                 ; Current packet cursor during a numeric fold.
NUM_ACC:     DW 0                  ; Accumulator payload for a variadic numeric fold.
NUM_VAL:      DW 0                 ; Current packet payload during numeric work.
NUM_REL:      DW 0                 ; Raw NUM_CMP relation for the current pair.
PKT_LEFT:       DB 0               ; Remaining packet values while building list.
PKT_PTR:       DW 0                ; Packet cursor for the list builder.
ARG_TAG:      DB 0                 ; Temporary tag while packing one argument.
ARG_VAL:       DW 0                ; Temporary payload while packing one argument.
DESC_CUR:      DW 0                ; Descriptor for the active procedure call.
DESC_RET:     DW 0                 ; Descriptor belonging to the caller frame.
DESC_FRM:      DW 0                ; Descriptor paired with the current frame map.
GC_BIND:     DW 0                  ; Binding pointer held across closure tracing.
FRM_BASE:     DW 0                 ; Active map base, zero while a frame is forming.
FRM_CLOS:       DW 0               ; Closure object currently being entered.
ENV_CUR:       DW 0                ; Pointer array for the active procedure.
ENV_RET:      DW 0                 ; Caller environment restored at return.
ENV_RCNT:     DB 0                 ; Active caller-map slot count for exact roots.
DESC_NEW:      DW 0                ; Descriptor being copied into a closure.
ENV_DST:    DW 0                 ; Destination map during closure creation.
HEAP_LIM:     DW RT_HIEND          ; Exclusive end of the closure/binding pool.
FRM_CLEN:     DW 0                 ; Two-byte closure-map extent for the active shape.
FRM_MLEN:      DW 0                ; Four-byte active-map extent for the active shape.
FRM_SP:     DW 0                   ; Stack boundary before an activation map.
RT_LOWSP:     DW RT_STK            ; Lowest native stack boundary observed.
STK_FLR:    DW 0                 ; The stack may not come below this: one page
                                   ; above the highest heap page.
CNT_BIND:      DW 0                ; Successful managed binding allocations.
CNT_CLOS:      DW 0                ; Successful closure allocations.
CNT_PAIR:      DW 0                ; Successful pair allocations.
CNT_GC:      DW 0                  ; Entries into the stop-the-world collector.
CNT_MAPS:      DW 0                ; Activation maps reserved by procedure calls.
FRM_SAVE:       DW 0               ; Helper return saved while moving the stack.
HEAP_OBJ:     DW 0                 ; Cell base retained during heap allocation.
.ENTRY:      DW 0                  ; Environment entry being filled.
MASK_PTR:     DW 0                 ; Descriptor mask cursor during activation setup.
DESC_OLD:      DW 0                ; Descriptor active before a tail transfer.
.SLOT:      DW 0                   ; Formal cell address during argument transfer.
SLOT_CUR:      DW 0                ; Active four-byte slot address.
SLOT_VAL:      DW 0                ; Value payload held by a slot helper.
SLOT_TAG:     DB 0                 ; Value tag held by a slot helper.
REST_EXT:     DB 0                 ; Byte 2 of a rest-binding argument.
REST_NXT:  DB 0                    ; Slot of the next formal being installed.
SLOT_REP:      DB 0                ; Active-slot flags held by a slot helper.
SLOT_NUM:      DB 0                ; Slot number held across promotion.
DESC_PTR:      DW 0                ; Descriptor cursor during argument transfer.
FRM_SRC:       DW 0                ; Target closure map during a tail transfer.
MASK_VAL:     DB 0                 ; Current owned-mask byte.
MASK_CNT:     DB 0                 ; Capture-mask bytes left in a tail transfer.
MASK_FIT:     DB 0                 ; Mask bytes left before the width runs out.
MASK_BIT:      DB 0                ; Capture-mask bits left in the current byte.
MASK_IDX:     DB 0                 ; Slot number represented by the mask cursor.
SLOT_CNT:     DB 0                 ; Number of pointer slots in the current shape.
CL_SLOTS:     DB 0                 ; Slot count used only while making a closure.
CL_SIZE:      DW 0                 ; Rounded closure extent for allocation and sweep.
CL_CLASS:     DB 0                 ; Four-byte size-class index for the active closure.
FRM_SPAN:      DB 0                ; Pointer-slot extent of the current frame.
RT_LIMIT:      DW 0                ; Absolute end of the published runtime image.
G_BASE:     DW 0                   ; Start of published globals and static locals.
G_END:      DW 0                   ; Exclusive end of globals and static locals.
QT_START:     DW 0                 ; Absolute start of quoted-list cache records.
QT_STOP:     DW 0                  ; Exclusive end of quoted-list cache records.
DR_DIR:      DW 0                  ; Absolute start of the published symbol directory.
DR_DEND:      DW 0                 ; Exclusive end of the published symbol directory.
ARG_PKT      EQU 0D680H            ; ARG_MAX four-byte records, after PS_TABLE.
OPS_SP:       DW RT_OPLO       ; Operator side-stack cursor between heap and guard.
OUT_BUF:   DS 32               ; Decimal output buffer terminated for BDOS function 9.
TX_ERROR:  DB "RUNTIME ERROR",13,10,"$"
TX_UNDEF: DB "UNBOUND",13,10,"$"

.LAST:
