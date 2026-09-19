# C0 staged-file patch experiment

This isolated ATOM helper changes one to four bytes in an already-open private
staging file using CP/M random-record operations. It is a component measurement,
not a native NOBJ writer, provider or publication implementation.

The caller supplies a checked logical file length and a stable, nonwrapping
source span disjoint from helper workspace, DMA and stack. Failures may leave
part of a patch on disk. That generation must be abandoned. Valid-range attempts
leave DMA pointing at the private 128-byte buffer; bounds rejection leaves it
unchanged. After a valid-range attempt, the caller must select another DMA
before unrelated I/O.

The host BDOS boundary oracle models 128-byte reads/writes, injects first/second
record failures, and destroys scratch registers plus IX/IY on every call. All
native and modeled DMA writes pass through the memory ownership guard. Tests
check actual return PC, SP, IX/IY, source integrity, unchanged FCB identity
bytes, neighboring file bytes and padding. Real BDOS execution, internal stack,
extent updates and disk failures require a later Portable CP/M integration
proof.

## Correctness and compaction

The independently reviewed baseline assembled to 170 instruction bytes and 172
workspace bytes. Stack use was six bytes, plus the caller's two-byte return
address. The 172 bytes comprise a 128-byte DMA, a 36-byte FCB and eight state
bytes. There are no immutable tables or generated-program costs.

Compaction selects DMA once for the private operation. Portable CP/M's random
read and write paths preserve the process DMA selection; its BDOS source writes
CURDMA during reset and function 26, not random I/O. The result is 162
instruction bytes, saving eight, with unchanged workspace/stack and record
transfers.

Four-byte patches within one record fell from 153 instructions / 1,578 T-states
to 149 / 1,534. Crossing a record boundary fell from 205 / 2,088 to 193 / 1,956.
These counts include the oracle's RET at the BDOS vector but exclude real BDOS
execution. Set-DMA calls fell from two/four to one; reads and writes remain one
each within a record, two each across a boundary. No speed regression was
observed in these equivalent boundary cases.

All three test groups pass: 1,024 alignment/length cases, invalid lengths and
logical EOF/16-bit overflow, far record positions, and injected I/O failures.
The source and measurement hashes are recorded in evidence.json. The original
baseline account is in baseline-evidence.json. The register-copy alternative
passed the same tests but assembled to 173 bytes, 11 larger than the retained
result. Its one-record four-byte patch used 1,129 T-states (405 fewer); its
two-record patch used 1,738 (218 fewer). Workspace, stack and record transfers
were unchanged. It was rejected on the size-first criterion. No compaction
plateau is claimed.

Run from the Skate checkout:

```sh
deno test --config deno.runtime.json --allow-read docs/c0/experiments/record-patch/
```

The experiment is integrated under docs/c0/experiments and remains outside
production source. Its scoped tests are included in check:c0.
