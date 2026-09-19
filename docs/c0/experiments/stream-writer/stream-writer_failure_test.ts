import assert from "node:assert/strict";
import { parseNobj1 } from "@jhlagado/z80-tool-services";
import {
  declarations,
  imageBytes,
  start,
  streamImage,
  type StreamMachine,
} from "./fixture.ts";
import { createStreamMachine, PATCH_SOURCE } from "./machine.ts";

function rawPatch(
  machine: StreamMachine,
  offset: number,
  bytes: Uint8Array,
  slot = 0,
): { status: number; carry: number } {
  const source = PATCH_SOURCE + slot * 8;
  machine.memory.set(bytes, source);
  const result = machine.call("SWPATCH", {
    b: bytes.length,
    hl: offset,
    de: source,
  });
  return { status: result.status, carry: result.carry };
}

function assertNoCommit(machine: StreamMachine): void {
  assert.throws(
    () => parseNobj1(machine.logicalStage()),
    /NOBJ|record|COMMIT|truncated|unknown|SECTION|IMAGE/i,
  );
}

function startWithPrefix(machine: StreamMachine, length: number): void {
  machine.reset();
  assert.equal(machine.call("SWINIT", { hl: 0x8000, de: 0x8040 }).status, 0);
  for (let index = 0; index < length; index++) {
    const result = machine.call("SWDECB", { a: declarations[index] });
    assert.equal(result.status, 0);
  }
}

Deno.test("image capacity accepts below and exact, then rejects one byte over", async () => {
  const machine = await createStreamMachine();
  const capacity = machine.address("SWIMGCAP");
  start(machine);
  streamImage(machine, imageBytes(capacity - 1));
  assert.equal(machine.stats().imageBytes, capacity - 1);
  assert.equal(machine.call("SWIMGB", { a: 0x55 }).status, 0);
  assert.equal(machine.stats().imageBytes, capacity);
  const over = machine.call("SWIMGB", { a: 0x55 });
  assert.deepEqual({ status: over.status, carry: over.carry }, {
    status: 1,
    carry: 1,
  });
  assertNoCommit(machine);
});

Deno.test("declaration and patch capacities fail before publication", async () => {
  const early = await createStreamMachine();
  startWithPrefix(early, declarations.length - 1);
  assert.equal(early.call("SWDECEND").status, 1);
  assertNoCommit(early);

  const extra = await createStreamMachine();
  startWithPrefix(extra, declarations.length);
  assert.equal(extra.call("SWDECB", { a: 0 }).status, 1);

  const machine = await createStreamMachine();
  start(machine);
  assert.deepEqual(rawPatch(machine, 0, new Uint8Array()), {
    status: 5,
    carry: 1,
  });
  assert.deepEqual(rawPatch(machine, 0, Uint8Array.of(1, 2, 3, 4, 5)), {
    status: 5,
    carry: 1,
  });
  assert.deepEqual(rawPatch(machine, 0xe2ff, Uint8Array.of(1, 2)), {
    status: 5,
    carry: 1,
  });
  assertNoCommit(machine);
});

Deno.test("spool capacity rejects the first record that cannot fit", async () => {
  const machine = await createStreamMachine();
  start(machine);
  for (let slot = 0; slot < 78; slot++) {
    assert.deepEqual(
      rawPatch(
        machine,
        slot,
        Uint8Array.of(slot, slot + 1, slot + 2, slot + 3),
        slot,
      ),
      { status: 0, carry: 0 },
    );
  }
  assert.deepEqual(
    rawPatch(machine, 78, Uint8Array.of(1, 2, 3, 4), 78),
    { status: 5, carry: 1 },
  );
  assertNoCommit(machine);
});

for (
  const [name, injection] of [
    ["sequential read", { sequentialRead: 1 }],
    ["sequential write", { sequentialWrite: 1 }],
    ["random read", { randomRead: 1 }],
    ["random write", { randomWrite: 1 }],
  ] as const
) {
  Deno.test(`injected ${name} failure prevents COMMIT`, async () => {
    const machine = await createStreamMachine();
    start(machine, declarations, injection);
    let writeResult = { status: 0, carry: 0 };
    for (const byte of imageBytes(239)) {
      const result = machine.call("SWIMGB", { a: byte });
      writeResult = { status: result.status, carry: result.carry };
      if (result.status !== 0) break;
    }
    const result = writeResult.status === 0
      ? machine.call("SWFINAL", { maxSteps: 30_000_000 })
      : writeResult;
    assert.notEqual(result.status, 0);
    assert.equal(result.carry, 1);
    assertNoCommit(machine);
  });
}

Deno.test("abort abandons a staged generation", async () => {
  const machine = await createStreamMachine();
  start(machine);
  streamImage(machine, imageBytes(239));
  const result = machine.call("SWABORT");
  assert.deepEqual({ status: result.status, carry: result.carry }, {
    status: 6,
    carry: 1,
  });
  assertNoCommit(machine);
});
