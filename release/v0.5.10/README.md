# Skate 0.5.10

Skate is a Scheme compiler and runtime for Z80 computers running CP/M. This
patch release keeps the language and compiler from 0.5.9 and tidies the
Triptych working disk so it contains the programs and tools a user needs.

The disk contains:

- `SKATE.COM` and `SKATE.RT`, the compiler and runtime;
- `EDIT.COM`, for editing source files;
- `README.TXT`, with CP/M instructions; and
- `ACCOUNT.SK8`, `ADVENT.SK8`, `RECEIPT.SK8` and `ROUTE.SK8`, four example
  programs.

To try an example in Triptych, select the writable `B:` disk and run:

```text
SKATE RECEIPT.SK8
RECEIPT
```

The checked image is available as
[`site/releases/0.5.10/skate.img`](../../site/releases/0.5.10/skate.img), with
its loader description in
[`site/releases/0.5.10/system.json`](../../site/releases/0.5.10/system.json).

The compiler and runtime sizes are unchanged from 0.5.9:

| Component | Bytes |
| --- | ---: |
| `SKATE.COM` compiler | 18,383 |
| `SKATE.RT` runtime payload | 17,003 |

The image was built with ATOM and checked through the Triptych CP/M host. The
compiler and examples were compiled, run and reopened after a remount.

The language limits are unchanged: there is no general macro system or
quasiquote, reusable `call/cc`, `eval`, Scheme ports or general file
procedures. Direct port I/O remains outside Scheme at the provider boundary.
