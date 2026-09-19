import assert from "node:assert/strict";
import {
  materializeNobj1Object,
  parseNobj1,
} from "@jhlagado/z80-tool-services";
import { createStreamMachine } from "./machine.ts";
import { finish, imageBytes, patch, start } from "./fixture.ts";

Deno.test("native writer streams a >8 KiB image and materializes patches", async () => {
  const machine = await createStreamMachine();
  const image = imageBytes(9001);
  const patches = [
    { offset: 118, bytes: Uint8Array.of(0xa1, 0xb2, 0xc3, 0xd4), slot: 0 },
    { offset: 8998, bytes: Uint8Array.of(0xe5, 0xf6, 0x17), slot: 1 },
  ];
  start(machine);
  const bytes = finish(machine, image, patches);
  const object = parseNobj1(bytes);
  const materialized = materializeNobj1Object(object).regions[0]!;
  const expected = image.slice();
  for (const item of patches) expected.set(item.bytes, item.offset);
  assert.equal(object.sections[0]!.length, image.length);
  assert.equal(materialized.usedLength, image.length);
  assert.deepEqual(materialized.bytes.slice(0, image.length), expected);
  assert.equal(object.commit.recordCount, machine.stats().recordCount);
  assert.notEqual(bytes.length % 128, 0, "final physical record is partial");
  const remainder = bytes.length % 128;
  assert.ok(
    machine.stage.slice(bytes.length, bytes.length + 128 - remainder).every((
      byte,
    ) => byte === 0x1a),
    "BDOS final record padding",
  );
  assert.ok(
    machine.stats().sequentialReads > 70,
    "CRC and spool rereads count",
  );
  assert.ok(
    machine.stats().randomReads >= 1 && machine.stats().randomWrites >= 1,
  );
  assert.ok(machine.stats().sequentialWrites > 70, "stage output writes count");
  assert.ok(machine.stats().stackBytes > 0 && machine.stats().stackBytes <= 64);
});

Deno.test("patch at the first and final image boundaries is retained", async () => {
  const machine = await createStreamMachine();
  const image = imageBytes(256);
  const patches = [
    { offset: 252, bytes: Uint8Array.of(0xe1, 0xe2, 0xe3, 0xe4), slot: 1 },
  ];
  start(machine);
  patch(machine, 0, Uint8Array.of(0xd1, 0xd2, 0xd3, 0xd4), 0);
  const bytes = finish(machine, image, patches);
  const object = parseNobj1(bytes);
  const result = materializeNobj1Object(object).regions[0]!;
  const expected = image.slice();
  expected.set(Uint8Array.of(0xd1, 0xd2, 0xd3, 0xd4), 0);
  for (const item of patches) expected.set(item.bytes, item.offset);
  assert.deepEqual(result.bytes.slice(0, image.length), expected);
});

Deno.test("writer workspace and transfer accounts are explicit", async () => {
  const machine = await createStreamMachine();
  assert.equal(machine.address("SWCODEND") - machine.address("SWINIT"), 1887);
  assert.equal(machine.codeBytes, 162);
  assert.equal(machine.helperWorkspaceBytes, 172);
  assert.equal(machine.writerWorkspaceBytes, 343);
  start(machine);
  finish(machine, imageBytes(239));
  const stats = machine.stats();
  assert.equal(stats.stageLength, machine.logicalStage().length);
  assert.ok(stats.dmaSelections >= 2);
  assert.ok(stats.bdosCalls > stats.dmaSelections);
});
