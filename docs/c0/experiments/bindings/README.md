# Bounded binding proof

This host experiment streams the weather fixture through `source-driver.ts`
without an AST or replayed source log. The resolver arena is exactly 8,192
bytes: 6,336 name storage, 256 binding records, 768 grouped-use records, 384
scope records, a 384-byte literal-identity reserve and 64 bytes of control
state. Parallel `let` binder IDs use one separate 128-byte stack (64 `u16`
entries); each active `letForm` keeps only scalar stack marks and consumes its
contiguous range in source order. There is no duplicated per-`let` ID array.

The host output array has a 58,112-byte capacity and the patch list is an
explicit output oracle outside the target arena. Source strings and scanner
lookahead are caller-owned input. Native closure execution, generated native
byte cost, provider ABI, literal heap capacity and GC remain outside this
proof. See `evidence.json` for machine-readable accounting and weather
measurements.

From the Skate repository root, reproduce the complete compact check with:

```sh
deno task check:c0
```

The weather assertions include 415 access sites: 339 global operands and 76
lexical operands.
