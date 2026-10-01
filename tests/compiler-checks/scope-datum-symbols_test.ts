import assert from "node:assert/strict";

import {
  managedRuntime,
  readWord,
  writeWord,
} from "./scope-runtime-fixture.ts";

function installBdosReader(memory: Uint8Array, bytes: readonly number[]) {
  const queue = 0xf200;
  const cursor = 0xf0f0;
  const routine = 0xf100;
  memory.set(bytes, queue);
  memory[5] = 0xc3;
  memory[6] = routine & 255;
  memory[7] = routine >>> 8;
  memory[routine] = 0x2a;
  memory[routine + 1] = cursor & 255;
  memory[routine + 2] = cursor >>> 8;
  memory[routine + 3] = 0x7e;
  memory[routine + 4] = 0x23;
  memory[routine + 5] = 0x22;
  memory[routine + 6] = cursor & 255;
  memory[routine + 7] = cursor >>> 8;
  memory[routine + 8] = 0xc9;
  writeWord(memory, cursor, queue);
}

function readDatum(
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  memory: Uint8Array,
  cpu: Awaited<ReturnType<typeof managedRuntime>>["cpu"],
  terminalError = false,
) {
  cpu.pc = assembled.address("SRTDRRD");
  cpu.sp = 0xdff2;
  cpu.ix = 0xef00;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 50_000_000, "SRTDRRD did not return");
    assembled.runtime.step();
  }
  if (terminalError) assert.ok(cpu.sp <= 0xdff2);
  else assert.equal(cpu.sp, 0xdff2);
  return { carry: cpu.flags.C, tag: cpu.a, payload: (cpu.h << 8) | cpu.l };
}

function prepare(
  memory: Uint8Array,
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  bytes: readonly number[],
) {
  installBdosReader(memory, bytes);
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;
  writeWord(memory, assembled.address("SRTSYMB"), 0);
  writeWord(memory, assembled.address("SRTSYME"), 0);
  writeWord(memory, assembled.address("SRTSYAP"), 0);
}

async function datumError(bytes: readonly number[]) {
  const { assembled, memory, cpu } = await managedRuntime();
  prepare(memory, assembled, bytes);
  const error = assembled.address("SRTERROR");
  memory[error] = 0xcd;
  writeWord(memory, error + 1, assembled.address("SRTDCLN"));
  memory[error + 3] = 0x37;
  memory[error + 4] = 0xc3;
  writeWord(memory, error + 5, 0xef00);
  const result = readDatum(assembled, memory, cpu, true);
  assert.equal(result.carry, 1);
  assert.equal(memory[assembled.address("SRTDRACT")], 0);
  assert.equal(memory[assembled.address("SRTSYAP")], 0);
}

function installErrorTrap(
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  memory: Uint8Array,
) {
  const error = assembled.address("SRTERROR");
  memory[error] = 0xcd;
  writeWord(memory, error + 1, assembled.address("SRTDCLN"));
  memory[error + 3] = 0x37;
  memory[error + 4] = 0xc3;
  writeWord(memory, error + 5, 0xef00);
}

Deno.test("datum reader reuses each distinct arena spelling", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  prepare(memory, assembled, [
    ...new TextEncoder().encode("alpha beta beta"),
    0x1a,
  ]);
  const first = readDatum(assembled, memory, cpu);
  const second = readDatum(assembled, memory, cpu);
  const third = readDatum(assembled, memory, cpu);
  assert.equal(first.tag, 4);
  assert.equal(second.tag, 4);
  assert.equal(third.tag, 4);
  assert.notEqual(first.payload, second.payload);
  assert.equal(second.payload, third.payload);
  assert.equal(memory[first.payload], 5);
  assert.deepEqual(
    Array.from(memory.slice(first.payload + 1, first.payload + 6)),
    Array.from(new TextEncoder().encode("alpha")),
  );
});

Deno.test("datum reader searches every published literal", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const directory = 0xd700;
  const alpha = 0xd800;
  const beta = 0xd810;
  prepare(memory, assembled, [...new TextEncoder().encode("beta"), 0x1a]);
  memory[directory] = 2;
  writeWord(memory, directory + 1, alpha);
  writeWord(memory, directory + 3, beta);
  writeWord(memory, assembled.address("SRTSYMB"), directory);
  writeWord(memory, assembled.address("SRTSYME"), directory + 5);
  memory[alpha] = 5;
  memory.set(new TextEncoder().encode("alpha"), alpha + 1);
  memory[beta] = 4;
  memory.set(new TextEncoder().encode("beta"), beta + 1);
  const result = readDatum(assembled, memory, cpu);
  assert.deepEqual(result, { carry: 0, tag: 4, payload: beta });
  assert.equal(readWord(memory, assembled.address("SRTSYAP")), 0);
});

Deno.test("datum reader interns a directory miss after all entries", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const directory = 0xd700;
  const alpha = 0xd800;
  const beta = 0xd810;
  prepare(memory, assembled, [...new TextEncoder().encode("delta"), 0x1a]);
  memory[directory] = 2;
  writeWord(memory, directory + 1, alpha);
  writeWord(memory, directory + 3, beta);
  writeWord(memory, assembled.address("SRTSYMB"), directory);
  writeWord(memory, assembled.address("SRTSYME"), directory + 5);
  memory[alpha] = 5;
  memory.set(new TextEncoder().encode("alpha"), alpha + 1);
  memory[beta] = 4;
  memory.set(new TextEncoder().encode("beta"), beta + 1);
  const result = readDatum(assembled, memory, cpu);
  assert.equal(result.tag, 4);
  assert.equal(result.payload, assembled.address("SRTSYA"));
  assert.equal(
    readWord(memory, assembled.address("SRTSYAP")),
    assembled.address("SRTSYA") + 6,
  );
});

Deno.test("datum reader permits an arena record ending at its limit", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const arenaEnd = assembled.address("SRTSYAE");
  const arenaStart = arenaEnd - 6;
  prepare(memory, assembled, [
    ...new TextEncoder().encode("alpha beta"),
    0x1a,
  ]);
  installErrorTrap(assembled, memory);
  writeWord(memory, assembled.address("SRTSYAP"), arenaStart);
  const first = readDatum(assembled, memory, cpu);
  assert.equal(first.payload, arenaStart);
  assert.equal(readWord(memory, assembled.address("SRTSYAP")), arenaEnd);
  const second = readDatum(assembled, memory, cpu, true);
  assert.equal(second.carry, 1);
  assert.equal(memory[assembled.address("SRTDRACT")], 0);
  assert.equal(readWord(memory, assembled.address("SRTSYAP")), arenaEnd);
});

Deno.test("datum reader accepts the 31-byte symbol limit", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const spelling = "a".repeat(31);
  prepare(memory, assembled, [...new TextEncoder().encode(spelling), 0x1a]);
  const result = readDatum(assembled, memory, cpu);
  assert.equal(result.tag, 4);
  assert.equal(memory[result.payload], 31);
});

Deno.test("datum reader rejects overlong and invalid symbol spellings", async () => {
  await datumError([...new TextEncoder().encode("a".repeat(32)), 0x1a]);
  await datumError([...new TextEncoder().encode("a#b"), 0x1a]);
  await datumError([...new TextEncoder().encode(".name"), 0x1a]);
});
