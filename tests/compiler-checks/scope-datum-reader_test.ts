import assert from "node:assert/strict";

import {
  managedRuntime,
  readWord,
  writeWord,
} from "./scope-runtime-fixture.ts";

function installBdosReader(memory: Uint8Array, bytes: readonly number[]) {
  const queue = 0xf200;
  const cursor = 0xf2f0;
  const routine = 0xf100;
  memory.set(bytes, queue);
  memory[5] = 0xc3;
  memory[6] = routine & 0xff;
  memory[7] = routine >>> 8;
  memory[routine] = 0x2a; // LD HL,(cursor).
  memory[routine + 1] = cursor & 0xff;
  memory[routine + 2] = cursor >>> 8;
  memory[routine + 3] = 0x7e; // LD A,(HL).
  memory[routine + 4] = 0x23; // INC HL.
  memory[routine + 5] = 0x22; // LD (cursor),HL.
  memory[routine + 6] = cursor & 0xff;
  memory[routine + 7] = cursor >>> 8;
  memory[routine + 8] = 0xc9; // RET.
  writeWord(memory, cursor, queue);
  return { cursor };
}

function readDatum(
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  memory: Uint8Array,
  cpu: Awaited<ReturnType<typeof managedRuntime>>["cpu"],
  terminalError = false,
  maxSteps = 50_000_000,
) {
  cpu.pc = assembled.address("SRTDRRD");
  cpu.sp = 0xdff2;
  cpu.ix = 0xef00;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(
      ++steps < maxSteps,
      `SRTDRRD did not return at PC=$${cpu.pc.toString(16)}`,
    );
    assembled.runtime.step();
  }
  assert.equal(cpu.sp, terminalError ? 0xdff4 : 0xdff2);
  return {
    assembled,
    memory,
    carry: cpu.flags.C,
    tag: cpu.a,
    payload: (cpu.h << 8) | cpu.l,
  };
}

function readChar(
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  memory: Uint8Array,
  cpu: Awaited<ReturnType<typeof managedRuntime>>["cpu"],
) {
  cpu.pc = assembled.address("SRTRDCH");
  cpu.sp = 0xdff2;
  cpu.ix = 0xef00;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 50_000_000, "SRTRDCH did not return");
    assembled.runtime.step();
  }
  assert.equal(cpu.sp, 0xdff2);
  return { tag: cpu.a, payload: (cpu.h << 8) | cpu.l };
}

function readDatumError(bytes: readonly number[]) {
  return managedRuntime().then(({ assembled, memory, cpu }) => {
    installBdosReader(memory, bytes);
    memory[assembled.address("SRTARGC")] = 0;
    memory[assembled.address("SRTINCR")] = 0;
    memory[assembled.address("SRTINST")] = 0;
    // Turn the terminal error into a checked return for malformed-input tests.
    memory[assembled.address("SRTERROR")] = 0x37; // SCF.
    memory[assembled.address("SRTERROR") + 1] = 0xc9; // RET.
    const result = readDatum(assembled, memory, cpu, true, 2_000_000);
    assert.equal(result.carry, 1);
  });
}

function addDigit(
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  memory: Uint8Array,
  cpu: Awaited<ReturnType<typeof managedRuntime>>["cpu"],
  magnitude: number,
  digit: number,
) {
  writeWord(memory, assembled.address("SRTDRNUM"), magnitude);
  cpu.a = digit;
  cpu.pc = assembled.address("SRTDADD");
  cpu.sp = 0xdff2;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 1_000, "SRTDADD did not return");
    assembled.runtime.step();
  }
  assert.equal(cpu.sp, 0xdff4);
  return {
    carry: cpu.flags.C,
    magnitude: readWord(memory, assembled.address("SRTDRNUM")),
  };
}

function pairPart(
  call: Awaited<ReturnType<typeof managedRuntime>>["call"],
  cpu: Awaited<ReturnType<typeof managedRuntime>>["cpu"],
  selector: "PAIR_CAR" | "PAIR_CDR",
  payload: number,
) {
  cpu.a = 1;
  return call(selector, payload);
}

Deno.test("datum reader returns scalar integers, booleans and characters", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  installBdosReader(
    memory,
    Array.from(new TextEncoder().encode(
      "-32768 32767 #t #f #\\A ",
    )),
  );
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;

  const integers = readDatum(assembled, memory, cpu);
  assert.equal(integers.tag, 3);
  assert.equal(integers.payload, 0x8000);

  const positive = readDatum(assembled, memory, cpu);
  assert.equal(positive.tag, 3);
  assert.equal(positive.payload, 0x7fff);

  const truth = readDatum(assembled, memory, cpu);
  assert.equal(truth.tag, 0);
  assert.equal(truth.payload, 0xfe01);

  const falsehood = readDatum(assembled, memory, cpu);
  assert.equal(falsehood.tag, 0);
  assert.equal(falsehood.payload, 0xfe00);

  const character = readDatum(assembled, memory, cpu);
  assert.equal(character.tag, 0);
  assert.equal(character.payload, 0xff41);
});

Deno.test("datum reader preserves port lookahead across read-char", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  installBdosReader(
    memory,
    [...Array.from(new TextEncoder().encode("42 #t")), 0x1a],
  );
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;

  assert.deepEqual(
    readDatum(assembled, memory, cpu),
    { assembled, memory, carry: 0, tag: 3, payload: 42 },
  );
  assert.deepEqual(readChar(assembled, memory, cpu), {
    tag: 0,
    payload: 0xff20,
  });
  assert.deepEqual(
    readDatum(assembled, memory, cpu),
    { assembled, memory, carry: 0, tag: 0, payload: 0xfe01 },
  );
});

Deno.test("datum reader rejects malformed, overflowing and non-ASCII input", async () => {
  const invalidDigit = await managedRuntime();
  assert.equal(
    addDigit(
      invalidDigit.assembled,
      invalidDigit.memory,
      invalidDigit.cpu,
      12,
      "x".charCodeAt(0),
    ).carry,
    1,
  );
  assert.equal(
    addDigit(
      invalidDigit.assembled,
      invalidDigit.memory,
      invalidDigit.cpu,
      10_000,
      "0".charCodeAt(0),
    ).carry,
    1,
  );
  assert.deepEqual(
    addDigit(
      invalidDigit.assembled,
      invalidDigit.memory,
      invalidDigit.cpu,
      3_276,
      "7".charCodeAt(0),
    ),
    { carry: 0, magnitude: 32_767 },
  );

  await readDatumError(Array.from(new TextEncoder().encode("12x\x1a")));
  await readDatumError(Array.from(new TextEncoder().encode("#\\ \x1a")));
  await readDatumError([0x80, 0x1a]);
  await readDatumError([...new Array(65).fill(0x30), 0x1a]);
});

Deno.test("datum reader accepts the 64-byte numeric spelling limit", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  installBdosReader(memory, [...new Array(64).fill(0x30), 0x1a]);
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;
  assert.deepEqual(readDatum(assembled, memory, cpu), {
    assembled,
    memory,
    carry: 0,
    tag: 3,
    payload: 0,
  });
});

Deno.test("datum reader shares lookahead across successive reads and sticky EOF", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const bytes = Array.from(
    new TextEncoder().encode("; comment\r\n 12 #t #\\A"),
  );
  bytes.push(0x1a);
  const { cursor } = installBdosReader(memory, bytes);
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;

  function readDatum() {
    cpu.pc = assembled.address("SRTDRRD");
    cpu.sp = 0xdff2;
    cpu.ix = 0xef00;
    let steps = 0;
    while (cpu.pc !== 0xef00) {
      assert.ok(++steps < 50_000_000, "successive SRTDRRD did not return");
      assembled.runtime.step();
    }
    assert.equal(cpu.sp, 0xdff2);
    return {
      tag: cpu.a,
      payload: (cpu.h << 8) | cpu.l,
    };
  }

  assert.deepEqual(readDatum(), { tag: 3, payload: 12 });
  assert.deepEqual(readDatum(), { tag: 0, payload: 0xfe01 });
  assert.deepEqual(readDatum(), { tag: 0, payload: 0xff41 });
  const eof = readDatum();
  assert.deepEqual(eof, { tag: 0, payload: 0xfe03 });
  const afterEof = memory[cursor] | (memory[cursor + 1] << 8);
  assert.deepEqual(readDatum(), eof);
  assert.equal(memory[cursor] | (memory[cursor + 1] << 8), afterEof);
  assert.equal(memory[assembled.address("SRTINST")], 2);
});

Deno.test("datum reader constructs proper, nested and dotted lists", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  installBdosReader(
    memory,
    [...Array.from(new TextEncoder().encode("(1 2 (3 . 4)) (5 . 6)")), 0x1a],
  );
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;

  const outer = readDatum(assembled, memory, cpu);
  assert.equal(outer.tag, 1, `tag=${outer.tag} payload=${outer.payload}`);
  const first = pairPart(call, cpu, "PAIR_CAR", outer.payload);
  assert.deepEqual(
    { tag: first.tag, payload: first.payload },
    { tag: 3, payload: 1 },
    `outer state=${memory[outer.payload + 4].toString(16)}`,
  );
  const secondPair = pairPart(call, cpu, "PAIR_CDR", outer.payload);
  assert.equal(secondPair.tag, 1);
  const second = pairPart(call, cpu, "PAIR_CAR", secondPair.payload);
  assert.deepEqual(
    { tag: second.tag, payload: second.payload },
    { tag: 3, payload: 2 },
  );
  const nestedPair = pairPart(call, cpu, "PAIR_CDR", secondPair.payload);
  assert.equal(nestedPair.tag, 1);
  const nestedValue = pairPart(call, cpu, "PAIR_CAR", nestedPair.payload);
  assert.equal(nestedValue.tag, 1);
  const nestedHead = pairPart(call, cpu, "PAIR_CAR", nestedValue.payload);
  assert.deepEqual(
    { tag: nestedHead.tag, payload: nestedHead.payload },
    { tag: 3, payload: 3 },
  );
  const dottedTail = pairPart(call, cpu, "PAIR_CDR", nestedValue.payload);
  assert.deepEqual(
    { tag: dottedTail.tag, payload: dottedTail.payload },
    { tag: 3, payload: 4 },
  );
  const outerEnd = pairPart(call, cpu, "PAIR_CDR", nestedPair.payload);
  assert.deepEqual(
    { tag: outerEnd.tag, payload: outerEnd.payload },
    { tag: 0, payload: 0xfe02 },
  );

  const dotted = readDatum(assembled, memory, cpu);
  assert.equal(dotted.tag, 1);
  const dottedHead = pairPart(call, cpu, "PAIR_CAR", dotted.payload);
  assert.deepEqual(
    { tag: dottedHead.tag, payload: dottedHead.payload },
    { tag: 3, payload: 5 },
  );
  const dottedCdr = pairPart(call, cpu, "PAIR_CDR", dotted.payload);
  assert.deepEqual(
    { tag: dottedCdr.tag, payload: dottedCdr.payload },
    { tag: 3, payload: 6 },
  );
});

Deno.test("datum reader accepts the 64-value aggregate limit", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  const source = `(${Array(64).fill("1").join(" ")})\x1a`;
  installBdosReader(memory, Array.from(new TextEncoder().encode(source)));
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;

  const result = readDatum(assembled, memory, cpu);
  let value = { tag: result.tag, payload: result.payload };
  let count = 0;
  while (value.tag === 1) {
    const head = pairPart(call, cpu, "PAIR_CAR", value.payload);
    assert.deepEqual({ tag: head.tag, payload: head.payload }, {
      tag: 3,
      payload: 1,
    });
    value = pairPart(call, cpu, "PAIR_CDR", value.payload);
    count++;
  }
  assert.equal(count, 64);
  assert.deepEqual({ tag: value.tag, payload: value.payload }, {
    tag: 0,
    payload: 0xfe02,
  });
});

Deno.test("datum reader keeps nested values and its accumulator live through GC", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  memory[assembled.address("SRTPSLIM")] = 2;
  for (let index = 0; index < 100; index++) {
    assert.equal(call("PAIR_NEW").carry, 0);
  }

  installBdosReader(
    memory,
    Array.from(new TextEncoder().encode("((1 . 2) 3 4 5)\x1a")),
  );
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;
  const result = readDatum(assembled, memory, cpu);
  assert.equal(readWord(memory, assembled.address("SRTGCNT")), 1);
  assert.equal(result.tag, 1);

  const nested = pairPart(call, cpu, "PAIR_CAR", result.payload);
  assert.equal(nested.tag, 1);
  assert.deepEqual(
    pairPart(call, cpu, "PAIR_CAR", nested.payload),
    { carry: 0, tag: 3, payload: 1 },
  );
  assert.deepEqual(
    pairPart(call, cpu, "PAIR_CDR", nested.payload),
    { carry: 0, tag: 3, payload: 2 },
  );
  let rest = pairPart(call, cpu, "PAIR_CDR", result.payload);
  for (const expected of [3, 4, 5]) {
    assert.equal(rest.tag, 1);
    assert.deepEqual(
      pairPart(call, cpu, "PAIR_CAR", rest.payload),
      { carry: 0, tag: 3, payload: expected },
    );
    rest = pairPart(call, cpu, "PAIR_CDR", rest.payload);
  }
  assert.deepEqual(rest, { carry: 0, tag: 0, payload: 0xfe02 });
});

Deno.test("datum reader clears roots when pair allocation fails", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  memory[assembled.address("SRTPSLIM")] = 1;
  const roots = 0xd700;
  const pairs: number[] = [];
  for (let index = 0; index < 32; index++) {
    const pair = call("PAIR_NEW");
    assert.equal(pair.carry, 0);
    pairs.push(pair.payload);
  }
  for (const [index, payload] of pairs.entries()) {
    const root = roots + index * 4;
    writeWord(memory, root, payload);
    memory[root + 2] = 0; // Clear extension byte.
    memory[root + 3] = 0x11;
  }
  writeWord(memory, assembled.address("SRTGBASE"), roots);
  writeWord(memory, assembled.address("SRTGEND"), roots + pairs.length * 4);

  installBdosReader(memory, Array.from(new TextEncoder().encode("(1 2)\x1a")));
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;
  memory[assembled.address("SRTOUT")] = 0x37; // SCF.
  memory[assembled.address("SRTOUT") + 1] = 0xc9; // RET.

  const result = readDatum(assembled, memory, cpu, true, 2_000_000);
  assert.equal(result.carry, 1);
  assert.equal(readWord(memory, assembled.address("SRTGCNT")), 1);
  assert.equal(memory[assembled.address("SRTDRACT")], 0);
  assert.equal(memory[assembled.address("SRTDRFC")], 0);
  assert.equal(memory[assembled.address("SRTDRVC")], 0);
  assert.equal(memory[assembled.address("SRTDRACC")], 0);
  assert.equal(
    readWord(memory, assembled.address("SRTDRVP")),
    assembled.address("RT_DRVLO"),
  );
  assert.equal(readWord(memory, assembled.address("SRTDRFP")), 0);
});

Deno.test("reader construction stack preserves tagged values", async () => {
  const { cpu, call } = await managedRuntime(true);
  cpu.a = 3;
  assert.deepEqual(
    call("SRTDRPUT", 1),
    { carry: 0, tag: 3, payload: 1 },
  );
  assert.deepEqual(
    call("SRTDRPOP"),
    { carry: 0, tag: 3, payload: 1 },
  );
});

Deno.test("datum reader makes a dotted pair", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  installBdosReader(memory, [
    ...Array.from(new TextEncoder().encode("(3 . 4)")),
    0x1a,
  ]);
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;
  const result = readDatum(assembled, memory, cpu);
  assert.equal(result.tag, 1);
  const head = pairPart(call, cpu, "PAIR_CAR", result.payload);
  const tail = pairPart(call, cpu, "PAIR_CDR", result.payload);
  assert.deepEqual(
    { tag: head.tag, payload: head.payload },
    { tag: 3, payload: 3 },
  );
  assert.deepEqual({ tag: tail.tag, payload: tail.payload }, {
    tag: 3,
    payload: 4,
  });
});

Deno.test("datum reader rejects malformed list punctuation", async () => {
  await readDatumError(Array.from(new TextEncoder().encode("(1 .2)\x1a")));
  await readDatumError(Array.from(new TextEncoder().encode("(1 .. 2)\x1a")));
  await readDatumError(Array.from(new TextEncoder().encode("(1 . . 2)\x1a")));
  await readDatumError(Array.from(new TextEncoder().encode("(. 1)\x1a")));
  await readDatumError(Array.from(new TextEncoder().encode("(1 .)\x1a")));
  await readDatumError(Array.from(new TextEncoder().encode("(1 . 2 3)\x1a")));
  await readDatumError(Array.from(new TextEncoder().encode("(1 2\x1a")));
});

Deno.test("datum reader rejects excessive list depth and aggregate values", async () => {
  const deep = `${"(".repeat(33)}1${")".repeat(33)}\x1a`;
  await readDatumError(Array.from(new TextEncoder().encode(deep)));

  const wide = `(${Array(65).fill("1").join(" ")})\x1a`;
  await readDatumError(Array.from(new TextEncoder().encode(wide)));
});
