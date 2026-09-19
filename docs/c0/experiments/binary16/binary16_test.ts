import assert from "node:assert/strict";
import { assemble, integerProof, PROVIDER_BASE } from "./integer_fixture.ts";

const includedEntry = "docs/c0/experiments/binary16/provider-binary16.asm";
const integerEntry = "docs/c0/experiments/binary16/provider-integer.asm";

const privateSpans = (assembly: Awaited<ReturnType<typeof assemble>>) =>
  [
    ["allocator", "HWORK", "HWEND"],
    ["collector", "GCWORK", "GCWEND"],
    ["binary16", "F16WORK", "F16WEND"],
    ["numeric", "NWORK", "NWEND"],
    ["execution", "RTWORK", "RTWEND"],
    ["literal", "RTLIPTR", "RTLIEND"],
  ].flatMap(([name, start, end]) => {
    try {
      const first = assembly.address(start!);
      const last = assembly.address(end!);
      return [{ name, start: first, end: last, bytes: last - first }];
    } catch {
      return [];
    }
  });

function extent(assembly: Awaited<ReturnType<typeof assemble>>): number {
  return assembly.address("PVEND") - PROVIDER_BASE;
}

Deno.test("provider comparison assembles both variants and links integer payload", async () => {
  const [included, integer, payload] = await Promise.all([
    assemble(includedEntry),
    assemble(integerEntry),
    assemble(
      "docs/c0/experiments/binary16/payload-binary16.asm",
    ),
  ]);
  assert.equal(included.address("PVEND"), 0x2a05);
  assert.equal(payload.address("PAYEND"), 0x2ac4);
  assert.equal(extent(included), 10501);
  assert.equal(extent(integer), 9110);
  assert.equal(extent(included) - extent(integer), 1391);
  assert.equal(
    included.address("F16END") - included.address("F16CLASS"),
    1299,
  );
  assert.equal(
    included.address("F16WEND") - included.address("F16WORK"),
    27,
  );
  assert.equal(included.address("NEND") - included.address("NCLASS"), 511);
  assert.equal(integer.address("NEND") - integer.address("NCLASS"), 442);
  assert.throws(() => integer.address("F16CLASS"), /ATOM omitted/);
  const includedPrivate = privateSpans(included).reduce(
    (sum, span) => sum + span.bytes,
    0,
  );
  const integerPrivate = privateSpans(integer).reduce(
    (sum, span) => sum + span.bytes,
    0,
  );
  assert.equal(includedPrivate, 593);
  assert.equal(integerPrivate, 570);
  const proof = await integerProof();
  assert.equal(proof.providerBytes, 9110);
  assert.equal(proof.payloadBytes, 191);
  assert.equal(proof.privateBytes, 570);
  assert.equal(proof.stackBytes, 6);
  assert.equal(proof.linkedBytes, 0xe300);
  const retainedGap = 0x2a05 - integer.address("PVEND");
  assert.equal(retainedGap, 1391);
  console.log(
    JSON.stringify(
      {
        included: {
          providerExtent: extent(included),
          privateStatic: includedPrivate,
          immutableRemainder: extent(included) - includedPrivate,
          binary16Code: included.address("F16END") -
            included.address("F16CLASS"),
          binary16Workspace: included.address("F16WEND") -
            included.address("F16WORK"),
          numericCode: included.address("NEND") - included.address("NCLASS"),
          numericWorkspace: included.address("NWEND") -
            included.address("NWORK"),
        },
        integerOnly: {
          providerExtent: extent(integer),
          privateStatic: integerPrivate,
          immutableRemainder: extent(integer) - integerPrivate,
          numericCode: integer.address("NEND") - integer.address("NCLASS"),
          numericWorkspace: integer.address("NWEND") -
            integer.address("NWORK"),
          retainedFixedPlacementGap: retainedGap,
        },
        providerSaving: extent(included) - extent(integer),
        fixedPayloadBytes: payload.address("PAYEND") - 0x2a05,
        integerProof: {
          stackBytes: proof.stackBytes,
          linkedRegionBytes: proof.linkedBytes,
          runs: proof.runs,
        },
      },
      null,
      2,
    ),
  );
});
