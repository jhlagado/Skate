# NOBJ 1.0 golden vectors

The hex files are complete byte streams unless the name says otherwise.
Whitespace in a hex file is ignored. The wire authority is
[docs/nobj-1.0.md](../../docs/nobj-1.0.md).

## Fixture profiles

The fixtures use these explicit target layouts:

- The ATOM empty and endpoint cases use one nonbanked Z80 region. The empty
  case requests 0100-0200; the endpoint case requests 8000-10000.
- The Skate service case uses one nonbanked readable, writable, executable
  region from 0100 through 10000. Its conformance provider advertises
  Skate runtime ABI 2.0 service numeric.add at 4200. First-fit places the
  four-byte section at 0100, so resolving the relocation produces
  CD 00 42 C9. This vector checks wire resolution only; it does not claim
  runtime execution.
- The banked Nucleus case uses ROM bank 0 and bank 1, each at 4000-6000, plus
  common writable RAM at 8000-A000. All image regions use fill E5, including
  gaps and unused tails; the sections use fill 00, so the vectors exercise
  region fill outside declared sections. Code in either bank can access its own
  bank and common RAM; bank 0 and bank 1 cannot directly access each other. The
  conformance provider enforces runtime identity 0004's 33-byte vector and
  37-byte state layout; the vector is not a linked production runtime image.
- The loaded Nucleus case uses an image window at 4000-A000 and a writable view
  at 8000-A000 over the same flat RAM storage. Both views request fill E5. It
  uses section fill 00 and exercises overlapping REGION aliases, same-address
  RUN/LOAD views, used-end equality and the loaded-mode entry constraint.

## Accepted vectors

| File | Records | Bytes | CRC | What it proves |
| --- | ---: | ---: | --- | --- |
| valid-atom-empty.nobj.hex | 6 | 135 | FEB3 | Empty image, source-part metadata, cursor at region base |
| valid-atom-cursor-65536.nobj.hex | 7 | 164 | 33B5 | No IMAGE records, initialized fill, high-water and cursor at 65536 |
| valid-atom-cursor-below-high-water.nobj.hex | 8 | 176 | 6C48 | Final cursor below the initialized section's high-water mark |
| valid-skate-service-reloc.nobj.hex | 11 | 217 | AB93 | Separate runtime/value contracts, a service import and ABS16_RUN |
| valid-nucleus-banked-rom.nobj.hex | 27 | 648 | 611E | Bank identity, ROM load/RAM run ranges, fixed vector/state lengths, BSS, stack, fill gaps/tails and source-part order |
| valid-nucleus-loaded.nobj.hex | 19 | 465 | 9AC8 | Loaded image/writable aliases, same-physical initializer views, used-end equality and entry-before-writable |

Accepted means structurally and contract-valid under the profile stated above.
The Nucleus vector validates its layout; it is not an emulator test.

## Rejected vectors

| File | Records | Bytes | CRC | Expected rejection |
| --- | ---: | ---: | --- | --- |
| invalid-bad-crc.nobj.hex | 6 | 135 | FFB3 stored | COMMIT CRC differs from the calculated FEB3 |
| invalid-cross-bank-call.nobj.hex | 31 | 718 | BEC8 | Structurally valid; bank 1 cannot directly call code in bank 0 |
| invalid-overlapping-patch.nobj.hex | 8 | 128 | BA11 | The two PATCH intervals overlap |
| invalid-reloc-address-65536.nobj.hex | 8 | 151 | 0318 | Relocation resolves to 65536, which cannot fit ABS16 |
| invalid-unknown-contract.nobj.hex | 4 | 61 | 5C78 | Inspection may succeed; link and runnable publication reject the unsupported required contract |
| invalid-unknown-record-kind.nobj.hex | 4 | 35 | 08E9 | Reserved record kind 7F; framing and CRC are otherwise valid |
| invalid-truncated-image.nobj.hex | — | 16 | — | IMAGE declares seven payload bytes but only one follows; no COMMIT |

The complete vectors have a correct record count and CRC except the deliberate
CRC failure. The truncated stream has no COMMIT. A separate disposable Deno
checker verified complete-stream framing, record order, counts and CRCs, plus
the fixture-specific Nucleus range relationships, loaded alias constraints,
ATOM cursor/high-water cases and sample gap/tail fill bytes. It is not a
production codec and is not checked in.
