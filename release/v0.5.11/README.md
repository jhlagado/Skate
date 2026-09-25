# Skate 0.5.11

Skate is a Scheme compiler and runtime for Z80 computers running CP/M. This
patch release adds a small interactive example, **The House in the Clearing**,
to the Skate work disk.

The disk contains:

- `SKATE.COM` and `SKATE.RT`, the compiler and runtime;
- `EDIT.COM`, for editing source files;
- `README.TXT`, with CP/M instructions; and
- `ACCOUNT.SK8`, `ADVENT.SK8`, `HOUSE.SK8`, `RECEIPT.SK8` and `ROUTE.SK8`,
  five example programs.

`HOUSE.SK8` is a short text adventure. The player starts outside a house,
opens the window, climbs inside, chooses the upstairs or cellar route, and
opens the trapdoor to finish. Use one key at a time:

```text
o  open the window
c  climb inside
u  go upstairs
d  go downstairs or return to the hall
t  open the trapdoor
q  leave the game
```

The winning route is `ocuddt`. To try it in Triptych, select the writable
`B:` disk and run:

```text
SKATE HOUSE.SK8
HOUSE
```

The checked image is available as
[`site/releases/0.5.11/skate.img`](../../site/releases/0.5.11/skate.img), with
its loader description in
[`site/releases/0.5.11/system.json`](../../site/releases/0.5.11/system.json).

The compiler and runtime sizes are unchanged:

| Component | Bytes |
| --- | ---: |
| `SKATE.COM` compiler | 18,383 |
| `SKATE.RT` runtime payload | 17,003 |

The compiler, runtime, examples and image were built with ATOM and checked
through the Triptych CP/M host. The new game was compiled and played through
the complete winning route.

The language limits are unchanged: there is no general macro system or
quasiquote, reusable `call/cc`, `eval`, Scheme ports or general file
procedures. Direct port I/O remains outside Scheme at the provider boundary.
