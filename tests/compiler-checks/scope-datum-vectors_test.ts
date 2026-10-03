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
  memory[routine] = 0x2a;
  memory[routine + 1] = cursor & 0xff;
  memory[routine + 2] = cursor >>> 8;
  memory[routine + 3] = 0x7e;
  memory[routine + 4] = 0x23;
  memory[routine + 5] = 0x22;
  memory[routine + 6] = cursor & 0xff;
  memory[routine + 7] = cursor >>> 8;
  memory[routine + 8] = 0xc9;
  writeWord(memory, cursor, queue);
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
    carry: cpu.flags.C,
    tag: cpu.a,
    payload: (cpu.h << 8) | cpu.l,
  };
}

function readDatumError(bytes: readonly number[]) {
  return managedRuntime().then(({ assembled, memory, cpu }) => {
    installBdosReader(memory, bytes);
    memory[assembled.address("SRTARGC")] = 0;
    memory[assembled.address("SRTINCR")] = 0;
    memory[assembled.address("SRTINST")] = 0;
    memory[assembled.address("SRTERROR")] = 0x37;
    memory[assembled.address("SRTERROR") + 1] = 0xc9;
    const result = readDatum(assembled, memory, cpu, true, 2_000_000);
    assert.equal(result.carry, 1);
  });
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

function vectorElement(memory: Uint8Array, vector: number, index: number) {
  const element = vector + 1 + index * 4;
  return {
    tag: memory[element + 3],
    payload: readWord(memory, element),
  };
}

function initialiseReader(
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  memory: Uint8Array,
) {
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;
  memory[assembled.address("SRTINST")] = 0;
}

Deno.test("datum reader constructs empty and tagged vectors", async () => {
  const { assembled, memory, cpu } = await managedRuntime(true);
  installBdosReader(
    memory,
    [...Array.from(new TextEncoder().encode("#() #(1 #t 3)")), 0x1a],
  );
  initialiseReader(assembled, memory);

  const empty = readDatum(assembled, memory, cpu);
  assert.equal(empty.tag, 7);
  assert.equal(memory[empty.payload], 0);

  const values = readDatum(assembled, memory, cpu);
  assert.equal(values.tag, 7);
  assert.equal(memory[values.payload], 3);
  assert.deepEqual(vectorElement(memory, values.payload, 0), {
    tag: 3,
    payload: 1,
  });
  assert.deepEqual(vectorElement(memory, values.payload, 1), {
    tag: 0,
    payload: 0xfe01,
  });
  assert.deepEqual(vectorElement(memory, values.payload, 2), {
    tag: 3,
    payload: 3,
  });
});

Deno.test("datum reader preserves nested vector and pair values", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  installBdosReader(
    memory,
    [...Array.from(new TextEncoder().encode("#(#(1 2) (3 4))")), 0x1a],
  );
  initialiseReader(assembled, memory);

  const outer = readDatum(assembled, memory, cpu);
  assert.equal(outer.tag, 7);
  assert.equal(memory[outer.payload], 2);
  const nested = vectorElement(memory, outer.payload, 0);
  assert.equal(nested.tag, 7);
  assert.equal(memory[nested.payload], 2);
  assert.deepEqual(vectorElement(memory, nested.payload, 0), {
    tag: 3,
    payload: 1,
  });
  assert.deepEqual(vectorElement(memory, nested.payload, 1), {
    tag: 3,
    payload: 2,
  });

  const pair = vectorElement(memory, outer.payload, 1);
  assert.equal(pair.tag, 1);
  assert.deepEqual(pairPart(call, cpu, "PAIR_CAR", pair.payload), {
    carry: 0,
    tag: 3,
    payload: 3,
  });
  const pairTail = pairPart(call, cpu, "PAIR_CDR", pair.payload);
  assert.equal(pairTail.tag, 1);
  assert.deepEqual(pairPart(call, cpu, "PAIR_CAR", pairTail.payload), {
    carry: 0,
    tag: 3,
    payload: 4,
  });
  assert.deepEqual(pairPart(call, cpu, "PAIR_CDR", pairTail.payload), {
    carry: 0,
    tag: 0,
    payload: 0xfe02,
  });
});

Deno.test("datum reader enforces vector size and delimiter limits", async () => {
  const { assembled, memory, cpu } = await managedRuntime(true);
  installBdosReader(
    memory,
    Array.from(
      new TextEncoder().encode(`#(${Array(64).fill("1").join(" ")})\x1a`),
    ),
  );
  initialiseReader(assembled, memory);
  const result = readDatum(assembled, memory, cpu);
  assert.equal(result.tag, 7);
  assert.equal(memory[result.payload], 64);
  assert.deepEqual(vectorElement(memory, result.payload, 63), {
    tag: 3,
    payload: 1,
  });

  await readDatumError(
    Array.from(
      new TextEncoder().encode(`#(${Array(65).fill("1").join(" ")})\x1a`),
    ),
  );
  await readDatumError(Array.from(new TextEncoder().encode("#(1 . 2\x1a")));
});

Deno.test("datum reader keeps vector elements live through a collection", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);

  // Keep one four-element vector alive and leave a second one unreachable in
  // the same slab. Clearing that class's free-list head and making the page
  // allocator fail forces the final reader allocation through SRTGC, where the
  // reader value stack must keep every pair child alive.
  memory[assembled.address("SRTVREQ")] = 4;
  const retained = call("SRTVACL");
  const discarded = call("SRTVACL");
  assert.equal(retained.carry, 0);
  assert.equal(discarded.carry, 0);
  memory[retained.payload] = 0;
  memory[discarded.payload] = 0;
  const root = 0xd700;
  writeWord(memory, root, retained.payload);
  memory[root + 2] = 0; // Clear extension byte.
  memory[root + 3] = 0x17;
  writeWord(memory, assembled.address("SRTGBASE"), root);
  writeWord(memory, assembled.address("SRTGEND"), root + 4);
  const classIndex = memory[assembled.address("SRTCLIDX")];
  writeWord(
    memory,
    assembled.address("SRTCFREE") + classIndex * 2,
    0,
  );
  memory[assembled.address("SLAB_ADD")] = 0x37; // SCF: no new page for this proof.
  memory[assembled.address("SLAB_ADD") + 1] = 0xc9; // RET after the forced failure.

  installBdosReader(
    memory,
    Array.from(
      new TextEncoder().encode("#((1 . 2) (3 . 4) (5 . 6) (7 . 8))\x1a"),
    ),
  );
  initialiseReader(assembled, memory);
  const result = readDatum(assembled, memory, cpu);
  assert.equal(result.tag, 7);
  assert.equal(memory[result.payload], 4);
  assert.ok(readWord(memory, assembled.address("SRTGCNT")) > 0);
  for (const [index, expected] of [1, 3, 5, 7].entries()) {
    const value = vectorElement(memory, result.payload, index);
    assert.equal(value.tag, 1);
    assert.deepEqual(pairPart(call, cpu, "PAIR_CAR", value.payload), {
      carry: 0,
      tag: 3,
      payload: expected,
    });
    assert.deepEqual(pairPart(call, cpu, "PAIR_CDR", value.payload), {
      carry: 0,
      tag: 3,
      payload: expected + 1,
    });
  }
  assert.equal(memory[assembled.address("SRTDRACT")], 0);
  assert.equal(memory[assembled.address("SRTDRFC")], 0);
  assert.equal(memory[assembled.address("SRTDRVC")], 0);
  assert.equal(
    readWord(memory, assembled.address("SRTDRVP")),
    assembled.address("SRTDRVB"),
  );
  assert.equal(readWord(memory, assembled.address("SRTDRFP")), 0);
});

Deno.test("datum reader cleans up when vector allocation is exhausted", async () => {
  const { assembled, memory, cpu } = await managedRuntime();

  // Select the twelve-byte class used by a two-element vector, then make both
  // page-allocation attempts fail. The reader must still leave no live frame,
  // value-root or lookahead state when SRTVACL reports the capacity error.
  memory[assembled.address("SRTVREQ")] = 2;
  const size = assembled.address("SRTVSZ");
  cpu.pc = size;
  cpu.sp = 0xdff0;
  writeWord(memory, cpu.sp, 0xef00);
  let sizeSteps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++sizeSteps < 100_000, "SRTVSZ did not return");
    assembled.runtime.step();
  }
  const classIndex = memory[assembled.address("SRTCLIDX")];
  writeWord(memory, assembled.address("SRTCFREE") + classIndex * 2, 0);
  memory[assembled.address("SLAB_ADD")] = 0x37; // SCF: no page is available.
  memory[assembled.address("SLAB_ADD") + 1] = 0xc9; // RET after the failure.

  installBdosReader(
    memory,
    Array.from(new TextEncoder().encode("#(1 2)\x1a")),
  );
  initialiseReader(assembled, memory);

  const error = assembled.address("SRTERROR");
  memory[error] = 0xcd; // Call the production cleanup routine.
  writeWord(memory, error + 1, assembled.address("SRTDCLN"));
  memory[error + 3] = 0x37; // Return the allocation error to this test.
  memory[error + 4] = 0xc9;
  const result = readDatum(assembled, memory, cpu, true, 2_000_000);
  assert.equal(result.carry, 1);
  assert.ok(readWord(memory, assembled.address("SRTGCNT")) > 0);
  assert.equal(memory[assembled.address("SRTDRACT")], 0);
  assert.equal(memory[assembled.address("SRTDRFC")], 0);
  assert.equal(memory[assembled.address("SRTDRVC")], 0);
  assert.equal(memory[assembled.address("SRTDRACC")], 0);
  assert.equal(
    readWord(memory, assembled.address("SRTDRVP")),
    assembled.address("SRTDRVB"),
  );
  assert.equal(readWord(memory, assembled.address("SRTDRFP")), 0);
  assert.equal(memory[assembled.address("SRTDRLEN")], 0);
  assert.equal(memory[assembled.address("SRTDSLN")], 0);
  assert.equal(memory[assembled.address("SRTINST")], 0);
  assert.equal(memory[assembled.address("SRTINCR")], 0);
});
