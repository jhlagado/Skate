# C0 NOBJ framing model

This host-only experiment consumes an emitted byte stream once, appends ordered
IMAGE then PATCH records, finalizes a reserved SECTION length in place, and
computes the final CRC/COMMIT. The actual shared NOBJ validator accepts the
result; its materialized bytes equal the separately patched COM model.

Five tests cover late length, cross-record and final-byte patches, exact
58,112-byte image capacity and first excess, exact 16-patch experiment capacity,
overlap/bounds failures, out-of-order records with a recomputed valid checksum,
stale checksum/length and trailing bytes. The patch limit is a fixture bound,
not the compact compiler's accepted capacity.

Independent review found no framing defect. It found an omitted initial NOBJ
write in the modeled traversal account, now corrected. The model counts one
sequential NOBJ emission, one final CRC read and one sequential COM emission,
plus the separately reported header and COM patch rewrites. Host buffer copies
and the validator/materializer's full-object passes are explicitly excluded.
They are test oracles, not native storage or traversal claims.

This proves wire ordering and materialization only. It does not prove bounded
native emission, CP/M transfer counts, runtime contracts, provider placement or
safe publication. The full-TPA image test is a format boundary, not a runnable
memory allocation: a program still needs runtime data, heap and stack.

Run from the Skate checkout:

```sh
deno test --config deno.runtime.json docs/c0/experiments/nobj/
```
