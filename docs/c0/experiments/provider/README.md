# C0 prepared provider placement

This is an isolated ATOM/NOBJ feasibility proof for one prepared runtime
provider. It fixes the provider at `$0100`, puts its service vector and the
full existing runtime in that image, and appends one generated payload at the
measured exclusive end `$2A05`. The provider has no general internal
relocation pass: its absolute runtime addresses are assembled at the selected
origin. NOBJ still patches the provider's entry jump, its service-vector
entries, and the payload's service calls.

The proof uses the retained-CCP profile `cpm-64k`: TPA `$0100..$E400`
(58,112 bytes), with the native stack guard `$D400..$E400` (4,096 bytes).
This runtime allocation is measured independently of the compiler's
30,720-byte allocation; the two processes need not be co-resident.
The provider and payload are separate fixed initialized sections. The payload
also declares the real NOBJ zero sections for roots, activations, bitmap,
heap, and compiler-selected workspace. `linkSkateObjects` accepts the object
schemas and invokes the shared `validateSkatePlacedContracts` validator; the
test does not replace either check with a local ABI approximation.

## Measured image and map

ATOM assembled the provider at `$0100` and measured `PVEND=$2A05`, so its
image extent is `$0100..$2A05` exclusive, 10,501 bytes. That is an initialized
image extent, not an immutable-code claim. The included runtime has writable
private state inside it. Symbol-bound measurements separate the six private
static spans from the remaining instructions and constants:

| span | start | end | bytes |
| --- | ---: | ---: | ---: |
| allocator state `HWORK..HWEND` | `$0247` | `$0253` | 12 |
| collector state `GCWORK..GCWEND` | `$060B` | `$073C` | 305 |
| binary16 state `F16WORK..F16WEND` | `$0C4F` | `$0C6A` | 27 |
| numeric state `NWORK..NWEND` | `$0E69` | `$0E7B` | 18 |
| execution state `RTWORK..RTWEND` | `$291B` | `$29EC` | 209 |
| literal scratch `RTLIPTR..RTLIEND` | `$29EC` | `$2A02` | 22 |
| private static total |  |  | **593** |
| image bytes outside those spans |  |  | **9,908** |

The last row is the measured remainder containing vector entries, runtime
instructions, constants and the terminal hook. It is not reported as
read-only code because the NOBJ section is writable initialized storage.

The payload is `$2A05..$2AC4` exclusive, 191 bytes. Its descriptor starts at
`BOOTDESC=$2A63`; `TOPDESC=$2A8B`, `RTCONFIG=$2A93`, and the initialized
global table is `GLOBBASE=$2AAF..$2ABB` (12 bytes). The placed extents are:

| owner | interval | bytes |
| --- | ---: | ---: |
| provider image | `$0100..$2A05` | 10,501 |
| payload code, descriptor, and globals | `$2A05..$2AC4` | 191 |
| roots | `$3000..$3040` | 64 |
| activations | `$3100..$3180` | 128 |
| mark bitmap | `$3200..$3600` | 1,024 |
| workspace | `$3600..$3700` | 256 |
| heap | `$3700..$B700` | 32,768 |
| guarded native stack | `$D400..$E400` | 4,096 |

The workspace ends at `$3700`, so the pre-stack window is
`$D400-$3700 = $9D00` (40,192 bytes). The allocator contract caps the heap at
8,192 four-byte cells, or 32,768 bytes. The selected heap is therefore the
derived `min(40,192, 32,768)` capacity, with 7,424 bytes remaining before the
stack guard. Every interval above is half-open, disjoint, and below the
profile's exclusive `$E400` ceiling. Boundary tests use the 256-byte workspace
with three distinct failures: `$3000..$3100` overlaps roots, base `$D301`
ends at `STACKLOW+1` and is still inside TPA (the validator reports a stack
allocation overlap), and base `$E301` ends at `$E401`, exactly one byte past
TPA (NOBJ reports that the SECTION run extent does not fit its REGION).

## ABI and execution result

The provider exports thirteen real services through three-byte jumps:
numeric classification and add/subtract/multiply/divide/negate, heap
initialisation, collector configuration, execution initialisation,
packet-new, invoke, pair construction, and literal initialisation. Each
vector is relocated to the corresponding assembled runtime symbol. The
payload imports four of those services (`heap.initialize`,
`collector.configure`, `execution.initialize`, and `numeric.add`) and its
four `CALL` operands are checked against the linked vector addresses.

The provider carries the omitted-descriptor runtime contract payload
`[0,0,0,0]`. The payload carries version 2.0 descriptor `[1,0,1,0]`: its
40-byte `BOOTDESC` range and exported `skate.generated:entry` are checked by
the real validator. The descriptor declares 16 root slots, 128 activation
bytes, a 4,096-byte native stack, 256 workspace bytes, 8,192 heap cells, and
the two-entry global table shown above. That two-global table is a placement
fixture, not a weather-runtime capacity claim. No service is a fabricated
no-op.

The native proof starts at the fixed `$0100` entry, which jumps through the
patched entry relocation to the payload. It supplies integer-tagged inputs
`41 + 1` and `100 + 23`. The linked image executes the real allocator,
collector setup, execution setup, and numeric provider service, then exits at
the host sentinel with `(tag,value) = (3,42)` and `(3,123)`, respectively,
carry clear, and balanced `SP=$E400`. `HREADY=1` proves the real heap setup;
`RTINIT` leaves `IX=0` and `IY=$3000` as its documented empty-start state.
This is an input-dependent native result, not a host-computed expected value.
The write observer sees 32,879 CPU memory writes on each run: 22 stack writes
with low-water address `$E3FA`, and no write outside the declared provider
static spans, payload scratch, roots, activations, bitmap, heap, workspace, or
guarded stack. Canaries immediately below `$D400` and above `$E400` remain
intact, so code, CCP, and the byte outside the stack guard were not silently
written.

Integer and binary16 costs are deliberately not separated by this experiment.
The current numeric provider includes both paths. Omitting the measured
binary16 code/state would appear to save 1,299 + 27 = 1,326 bytes, but the
integer-only runtime split and its contract are not proved; that reduction is
not attempted.

After correctness, one eligible fixture-glue simplification was measured:
removing the success-path `OR A` from `PAYDONE` relies on the real
`numeric.add` contract's carry-clear success result. The payload fell from
192 to 191 bytes (`PAYEND` `$2AC5` to `$2AC4`), and both native inputs plus
the full scoped checks still pass. The provider extent is unchanged.

ATOM image materialization and NOBJ linking are host oracles here. The positive
proof performs two ATOM materializations, two local encode/parse pairs, two
link-input parses, and two debug80 image copies for the two executions. Those
host traversals are recorded separately in `evidence.json`; native NOBJ
streaming, CP/M publication, and compiler traversal counts are not claimed.

Run the scoped proof from the Skate checkout:

```sh
deno check --config deno.runtime.json \
  docs/c0/experiments/provider/*.ts
deno test --config deno.runtime.json \
  --allow-read=.,../atom,../z80-tool-services,../debug80-runtime,/tmp \
  --allow-write=/tmp docs/c0/experiments/provider/
```

The first command is a type check. The second currently reports two passing
tests: successful placement/link/execution, plus root-overlap, one-byte
stack-crossing, and one-byte TPA-overflow rejection. This directory is an
experiment only; it does not rewrite C1 or publish a COM file.
