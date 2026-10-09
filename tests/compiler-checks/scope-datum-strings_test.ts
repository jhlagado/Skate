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
  cpu.pc = assembled.address("DR_READ");
  cpu.sp = 0xb3f2;
  cpu.ix = 0xef00;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 50_000_000, "DR_READ did not return");
    assembled.runtime.step();
  }
  if (terminalError) {
    assert.ok(cpu.sp <= 0xb3f2);
  } else {
    assert.equal(cpu.sp, 0xb3f2);
  }
  return {
    carry: cpu.flags.C,
    tag: cpu.a,
    payload: (cpu.h << 8) | cpu.l,
  };
}

async function readDatumError(bytes: readonly number[]) {
  const { assembled, memory, cpu } = await managedRuntime();
  installBdosReader(memory, bytes);
  memory[assembled.address("ARG_CNT")] = 0;
  memory[assembled.address("IN_CR")] = 0;
  memory[assembled.address("IN_STATE")] = 0;
  // Preserve the real cleanup hook before returning to the test trap.  A
  // direct SCF/JP replacement would leave reader roots and lookahead state
  // untested on the error path.
  const error = assembled.address("ERROR");
  memory[error] = 0xcd; // CALL DR_CLEAR.
  writeWord(memory, error + 1, assembled.address("DR_CLEAR"));
  memory[error + 3] = 0x37; // SCF.
  memory[error + 4] = 0xc3; // JP the test trap.
  writeWord(memory, error + 5, 0xef00);
  const result = readDatum(assembled, memory, cpu, true);
  assert.equal(result.carry, 1);
  assert.equal(memory[assembled.address("DR_LIVE")], 0);
  assert.equal(memory[assembled.address("DR_ROOTS")], 0);
  assert.equal(memory[assembled.address("DR_DEPTH")], 0);
  assert.equal(memory[assembled.address("DR_SLOTS")], 0);
  assert.equal(memory[assembled.address("DR_HELD")], 0);
  assert.equal(memory[assembled.address("DR_SIZE")], 0);
  assert.equal(memory[assembled.address("IN_STATE")], 0);
  assert.equal(memory[assembled.address("IN_CR")], 0);
}

function stringBytes(memory: Uint8Array, payload: number) {
  const length = memory[payload];
  return Array.from(memory.slice(payload + 1, payload + 1 + length));
}

function exhaustManagedPages(
  { assembled, memory, call }: Awaited<ReturnType<typeof managedRuntime>>,
) {
  for (let index = 0; index < 256; index++) {
    // Take every page, past the soft line kept for the stack.
    memory[assembled.address("PAGE_HRD")] = 1;
    const result = call("PAGE_NEW", 1);
    if (result.carry) return index;
  }
  assert.fail("managed page pool did not report exhaustion");
}

Deno.test("datum reader allocates strings and decodes the source escapes", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime();
  installBdosReader(
    memory,
    Array.from(new TextEncoder().encode(
      '"hello" "" "a\\n\\r\\t\\"\\\\\\x00;\\xFF;" 42 ',
    )),
  );
  memory[assembled.address("ARG_CNT")] = 0;
  memory[assembled.address("IN_CR")] = 0;
  memory[assembled.address("IN_STATE")] = 0;

  const hello = readDatum(assembled, memory, cpu);
  assert.equal(hello.tag, 6);
  assert.deepEqual(stringBytes(memory, hello.payload), [
    104,
    101,
    108,
    108,
    111,
  ]);
  assert.equal(call("STR_CHK", hello.payload).carry, 0);

  const empty = readDatum(assembled, memory, cpu);
  assert.equal(empty.tag, 6);
  assert.deepEqual(stringBytes(memory, empty.payload), []);

  const escaped = readDatum(assembled, memory, cpu);
  assert.equal(escaped.tag, 6);
  assert.deepEqual(stringBytes(memory, escaped.payload), [
    97,
    10,
    13,
    9,
    34,
    92,
    0,
    255,
  ]);

  const integer = readDatum(assembled, memory, cpu);
  assert.deepEqual(integer, { carry: 0, tag: 3, payload: 42 });
});

Deno.test("datum reader accepts 255 decoded bytes and rejects the 256th", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  installBdosReader(memory, [34, ...new Array(255).fill(65), 34, 0x1a]);
  memory[assembled.address("ARG_CNT")] = 0;
  memory[assembled.address("IN_CR")] = 0;
  memory[assembled.address("IN_STATE")] = 0;

  const result = readDatum(assembled, memory, cpu);
  assert.equal(result.tag, 6);
  assert.equal(memory[result.payload], 255);
  assert.deepEqual(
    stringBytes(memory, result.payload),
    new Array(255).fill(65),
  );

  await readDatumError([34, ...new Array(256).fill(65), 34, 0x1a]);
});

Deno.test("managed strings survive collection while a 255-byte value is rooted", async () => {
  const fixture = await managedRuntime();
  const { assembled, memory, cpu, call } = fixture;
  const rooted = 0xd700;

  memory[assembled.address("STR_LEN")] = 255;
  const longString = call("STR_NEW");
  assert.equal(longString.carry, 0);
  memory[longString.payload] = 255;
  for (let index = 0; index < 255; index++) {
    memory[longString.payload + 1 + index] = index;
  }
  writeWord(memory, rooted, longString.payload);
  memory[rooted + 2] = 0; // Clear extension byte.
  memory[rooted + 3] = 0x16;
  writeWord(memory, assembled.address("G_BASE"), rooted);
  writeWord(memory, assembled.address("G_END"), rooted + 4);

  // A 128-byte payload is a one-object class, so the next allocation of the
  // same size must collect the discarded value before it can proceed.
  memory[assembled.address("STR_LEN")] = 128;
  const discarded = call("STR_NEW");
  assert.equal(discarded.carry, 0);
  memory[discarded.payload] = 128;
  memory[discarded.payload + 1] = 0x5a;

  const exhausted = exhaustManagedPages(fixture);
  assert.ok(exhausted > 0, "page pool should contain resident runtime pages");
  installBdosReader(memory, [34, ...new Array(128).fill(0x42), 34, 0x1a]);
  memory[assembled.address("ARG_CNT")] = 0;
  memory[assembled.address("IN_CR")] = 0;
  memory[assembled.address("IN_STATE")] = 0;
  const replacement = readDatum(assembled, memory, cpu);
  assert.equal(replacement.tag, 6);
  assert.equal(readWord(memory, assembled.address("CNT_GC")), 1);
  assert.equal(call("STR_CHK", longString.payload).carry, 0);
  assert.deepEqual(
    stringBytes(memory, longString.payload),
    Array.from({ length: 255 }, (_, index) => index),
  );
  assert.equal(memory[replacement.payload], 128);
  assert.deepEqual(
    stringBytes(memory, replacement.payload),
    new Array(128).fill(0x42),
  );
});

Deno.test("datum string allocation failure runs the reader cleanup hook", async () => {
  const fixture = await managedRuntime();
  const { assembled, memory, cpu } = fixture;
  exhaustManagedPages(fixture);
  installBdosReader(memory, [34, 65, 34, 0x1a]);
  memory[assembled.address("ARG_CNT")] = 0;
  memory[assembled.address("IN_CR")] = 0;
  memory[assembled.address("IN_STATE")] = 0;

  const error = assembled.address("ERROR");
  memory[error] = 0xcd; // CALL DR_CLEAR.
  writeWord(memory, error + 1, assembled.address("DR_CLEAR"));
  memory[error + 3] = 0x37; // SCF.
  memory[error + 4] = 0xc3; // JP the test trap.
  writeWord(memory, error + 5, 0xef00);
  const result = readDatum(assembled, memory, cpu, true);
  assert.equal(result.carry, 1);
  assert.equal(memory[assembled.address("DR_LIVE")], 0);
  assert.equal(memory[assembled.address("DR_ROOTS")], 0);
  assert.equal(memory[assembled.address("DR_DEPTH")], 0);
  assert.equal(memory[assembled.address("DR_SLOTS")], 0);
  assert.equal(memory[assembled.address("DR_HELD")], 0);
  assert.equal(memory[assembled.address("DR_SIZE")], 0);
});

Deno.test("datum reader rejects malformed strings and raw controls", async () => {
  await readDatumError([34, 65, 0x1a]);
  await readDatumError(Array.from(new TextEncoder().encode('"\\q"\x1a')));
  await readDatumError(Array.from(new TextEncoder().encode('"\\x0g;"\x1a')));
  await readDatumError(Array.from(new TextEncoder().encode('"\\x00"\x1a')));
  await readDatumError([34, 1, 34, 0x1a]);
  await readDatumError([34, 127, 34, 0x1a]);
});
