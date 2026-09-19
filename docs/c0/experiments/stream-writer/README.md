# Native streamed NOBJ writer

This experiment tests the C0 output path in ATOM assembly. The caller streams
the fixed 70-byte declaration, image bytes, and bounded patch bytes. The writer
keeps only a 119-byte IMAGE payload buffer, one 128-byte patch-spool buffer,
the reviewed 128-byte RPATCH DMA buffer, and its explicit state. It writes the
declaration and IMAGE records to a staged CP/M file, spools PATCH records, late
rewrites the SECTION length, appends PATCH and LAYOUT records, rereads the
staged logical bytes for CRC, and emits COMMIT last.

The test machine is a hostile BDOS boundary oracle. It destroys scratch
registers after each call, counts sequential and random transfers, injects
read/write failures, observes stack low-water, and rejects native writes
outside the RPATCH and writer workspaces. It is not a complete CP/M disk or
publication proof.

Run the focused proof from the legacy checkout:

```sh
deno test --config deno.runtime.json \
  --allow-read=.,../atom,../z80-tool-services,../debug80-runtime,/tmp \
  --allow-write=/tmp docs/c0/experiments/stream-writer/
```

The focused battery has 11 passing tests. It covers a 9,001-byte image, first
and final patch boundaries, one byte before/exactly at/one byte after the
58,112-byte image cap, declaration and patch protocol failures, the 1,024-byte
spool cap, injected sequential and random BDOS failures, and abort without a
valid COMMIT. The shared NOBJ parser and materializer accept the successful
output.

The assembled account is:

| account | bytes |
| --- | ---: |
| stream-writer code and immutable data | 1,887 |
| stream-writer writable workspace | 343 |
| RPATCH code | 162 |
| RPATCH writable workspace | 172 |
| combined functional code | 2,049 |
| observed native stack in the two-patch run | 16 |

The 9,001-byte two-patch run made 78 sequential reads, 80 sequential writes,
3 random reads, 1 random write, and 161 DMA selections. The 12-byte compaction
removed four dead pointer-clearing stores after `SWINIT`; the complete focused
battery was rerun before retaining it.

The writer checks its own u16 image capacity and spool capacity. The caller
still owns declaration validity, patch non-overlap, and the final-image
precondition. Generated output, provider/runtime bytes, compiler allocation,
and CP/M publication remain separate C1 implementation accounts; this C0
experiment only accepts the staged publication boundary.
