# Weather corpus fixture

This is the deterministic C0 acceptance package. It contains 224 synthetic
daily observations. For day `d` from 1 through 224:

```text
low  = (d mod 17) - 8
high = low + 12 + (d mod 5)
rain = d mod 20
```

`DATA01.SK8` defines one quoted four-field record for each day. `GROUPS.SK8`
groups those records into fourteen lists of sixteen. `REPORTS.SK8` defines the
reporting procedures and invokes `run-report`.

The package has exactly 256 user globals, uses ordinary identifiers no longer
than sixteen bytes, and is deliberately a future target-execution input. The
checked-in evidence reports lexical and structural measurements only; it does
not claim that this source has run on a Z80 or that native compiler memory
limits have been proven.

Inputs `r` and `R` select total rain; `h` selects the number of days above 20.
Other input, including EOF, selects the summary. Its fields are days, total
rain, total high temperature, hot days, wet days, first day, first low
temperature, shared-counter result, and hot days with rain above 10. The last
condition exercises both operands of `and`; it selects 12 of the 26 hot days.
Each path then prints the late-shadowing result 37 and the mutual-tail result
`#t`, on separate lines. Expected output uses CP/M CR/LF.

`readerSymbolBytes` counts the host reader's permanent spelling pool, not peak
native storage. `referencesToLaterGlobals` is a source statistic, not a live
fixup count. `distinctQuotedLiteralContents` counts distinct authored contents,
not object identities or runtime heap cells. No source capacity or runtime
memory conclusion follows from the host analyzer's own allocations.
