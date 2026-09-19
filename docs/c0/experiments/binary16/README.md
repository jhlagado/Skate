# Binary16 provider size comparison

This C0 experiment measures the prepared ATOM provider with the existing
binary16 runtime against an integer-only provider assembled from the same
allocator, collector and execution modules. Both images keep the ABI-2
provider vector and NOBJ contract. The integer image keeps the numeric service
names and entry points, accepts exact signed-word values (tag 3), and rejects
binary16 values (tag 0); its `NDIV` entry reports the unsupported floating
result as status 2. That omission is deliberate and is not presented as a
complete float-enabled compiler variant.

The included build is the real prepared provider in
`../provider/provider.asm`, wrapped locally as `provider-binary16.asm`. Its
binary16 module is assembled and covered by the existing exhaustive
classification, conversion, arithmetic and comparison test in
`tests/binary16_test.ts`. The integer build uses `numeric-integer.asm` in
`provider-integer.asm`. `integer_fixture.ts` constructs both NOBJ objects with
the shared linker, links the integer payload, and runs the linked image under
Debug80's write observer.

ATOM reports the included provider extent from `$0100` through `$2A05` as
10,501 bytes. The integer-only provider ends at `$2496`, for 9,110 bytes. The
provider saving is therefore 1,391 bytes. The integer payload deliberately
retains the prepared payload origin `$2A05`, so the fixed placement reserves a
1,391-byte gap between the shorter provider and the unchanged 191-byte
payload. The complete fixed-origin initialized footprint consequently still
ends at `$2AC4`; the gap is reported rather than counted as a false whole-image
saving. A compactly relocated payload would be a separate placement experiment.

The assembler-derived accounts are:

| account | binary16 included | integer-only |
| --- | ---: | ---: |
| provider extent from `$0100` | 10,501 | 9,110 |
| private static state | 593 | 570 |
| instruction/constant remainder | 9,908 | 8,540 |
| binary16 code | 1,299 | 0 |
| binary16 workspace | 27 | 0 |
| numeric dispatch code | 511 | 442 |
| numeric workspace | 18 | 22 |
| payload code, descriptor and globals | 191 | 191 |

The “instruction/constant remainder” is the provider extent after the
declared writable module spans. It is an immutable remainder account, not a
claim that every byte is executable code. The payload contract reserves 256
bytes of workspace, 32,768 heap bytes and a 4,096-byte native stack. The linked
integer proof observed a 6-byte deepest stack use (`$E3FA` through `$E400`),
balanced SP, intact stack canaries and no writes outside the declared spans.
Each of its two input-dependent runs made 32,880 writes and 22 stack writes.

The focused compaction changed the two nearby `NPREPARE` failure branches in
the integer module from absolute conditional jumps to range-valid relative
jumps. Before that change the integer provider measured 9,112 bytes and the
numeric dispatch measured 444 bytes. The assembled result is 9,110 and 442;
the linked proof still passes.

The compiler-side extension costs are kept separate from the provider image.
The shared decimal literal converter measures 818 code bytes and 101 workspace
bytes (`DPARSE..DWORK` and `DWORK..DWEND` in the native compiler image). It
handles exact integers and binary16 spellings together, so an integer-only
delta is not claimed. The mixed numeric dispatcher measures 511 code bytes and
18 workspace bytes; the combined binary16-plus-dispatch extent is 1,855 bytes
because the modules share tails. Ordinary float output uses an 89-byte
`N4F16..N4CRC` compiler path for lossless `F16:hhhh` formatting, including the
shared line terminator. Its isolated integer-only delta is also unmeasured.

The existing native batteries pass 5 exhaustive binary16 tests, 3 decimal
literal/formatting tests, 4 native arithmetic tests and 6 mixed numeric tests.
These prove the included behavior and its measured accounts; they do not turn
the integer-only provider into a complete float-free compiler variant.

Run the scoped comparison with:

```text
deno check --config deno.runtime.json docs/c0/experiments/binary16/*.ts
deno test --config deno.runtime.json --allow-read=.,../atom,../z80-tool-services,../debug80-runtime,/tmp --allow-write=/tmp docs/c0/experiments/binary16/
```

The included binary16 coverage and prepared-provider link proof are:

```text
deno test --config deno.runtime.json --allow-read=.,../atom,../debug80-runtime,../z80-tool-services tests/binary16_test.ts
deno test --config deno.runtime.json --allow-read=.,../atom,../z80-tool-services,../debug80-runtime,/tmp --allow-write=/tmp docs/c0/experiments/provider/
```

The host assembler, NOBJ encoder/parser, linker and Debug80 runtime are test
oracles. This directory does not claim CP/M publication, compiler integration,
or general provider relocation. The integer-only provider remains a bounded
size comparison: only its linked `NADD` workload is executed, while `NSUB`,
`NMUL`, `NCMP` and unsupported `NDIV` need a later complete integer-runtime
proof before that variant could be adopted.
