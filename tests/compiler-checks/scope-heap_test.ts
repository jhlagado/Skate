import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";

const PAIR_BYTES = 8;
const PAIRS_PER_SLAB = 32;
const CAR_META = 3;
const CDR_PAYLOAD = 4;
const CDR_META = 7;

function writeWord(memory: Uint8Array, address: number, value: number) {
  memory[address] = value & 255;
  memory[address + 1] = value >>> 8;
}

function callLabel(
  assembled: Awaited<ReturnType<typeof loadAssembly>>,
  label: string,
  memory: Uint8Array,
  cpu: {
    pc: number;
    sp: number;
    flags: { C: number };
    h: number;
    l: number;
  },
) {
  cpu.pc = assembled.address(label);
  cpu.sp = 0xdff0;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 20_000_000, `${label} did not return`);
    assembled.runtime.step();
  }
  assert.equal(cpu.sp, 0xdff2);
  return {
    carry: cpu.flags.C,
    payload: (cpu.h << 8) | cpu.l,
  };
}

async function collectorFixture(rootCount: number) {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  memory.fill(0, 0x8000, 0x9000);
  const slabBase = (assembled.image.end + 0xff) & 0xff00;
  const slabCount = 17;
  assert.ok(slabBase + slabCount * 0x100 <= 0x8000, "slabs overlap roots");
  const recordsPerSlab = PAIRS_PER_SLAB;
  memory[assembled.address("SRTPSLBN")] = slabCount;
  for (let slab = 0; slab < slabCount; slab++) {
    const base = slabBase + slab * 0x100;
    const descriptor = assembled.address("SRTPSLT") + slab * 3;
    memory[descriptor] = base >>> 8;
    memory[descriptor + 1] = 0;
    memory[descriptor + 2] = 0xff;
    for (let slot = 0; slot < recordsPerSlab; slot++) {
      const address = base + slot * PAIR_BYTES;
      writeWord(memory, address, 42);
      writeWord(memory, address + CDR_PAYLOAD, 0xfe02);
      memory[address + CAR_META] = 0;
      memory[address + CDR_META] = 0;
    }
  }
  const recordAddress = (index: number) =>
    slabBase + Math.floor(index / recordsPerSlab) * 0x100 +
    (index % recordsPerSlab) * PAIR_BYTES;
  for (let index = 0; index <= rootCount; index++) {
    memory[recordAddress(index) + CAR_META] = 0x43; // integer CAR, allocated
    memory[recordAddress(index) + CDR_META] = 0; // empty-list CDR
  }
  for (let index = 0; index < rootCount; index++) {
    const root = 0x8000 + index * 4;
    writeWord(memory, root, recordAddress(index));
    memory[root + 2] = 1;
    memory[root + 3] = 1;
  }
  writeWord(memory, assembled.address("SRTGBASE"), 0x8000);
  writeWord(memory, assembled.address("SRTGEND"), 0x8000 + rootCount * 4);
  const parent = recordAddress(rootCount - 1);
  const child = recordAddress(rootCount);
  writeWord(memory, parent + CDR_PAYLOAD, child);
  memory[parent + CAR_META] = 0x43; // integer CAR, allocated
  memory[parent + CDR_META] = 1; // pair CDR
  const orphan = recordAddress(530);
  memory[orphan + CAR_META] = 0x43;
  cpu.pc = assembled.address("SRTGC");
  cpu.sp = 0xdff0;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 10_000_000, "collector did not return");
    assembled.runtime.step();
  }
  assert.equal(cpu.sp, 0xdff2);
  return { memory, parent, child, orphan, steps };
}

Deno.test("collector preserves an edge below the worklist limit", async () => {
  const result = await collectorFixture(511);
  assert.equal(result.memory[result.parent + CAR_META], 0x43);
  assert.equal(result.memory[result.parent + CDR_META], 1);
  assert.equal(result.memory[result.child + CAR_META], 0x43);
  assert.equal(result.memory[result.orphan + CAR_META], 0);
});

Deno.test("collector preserves an edge at the worklist limit", async () => {
  const result = await collectorFixture(512);
  assert.equal(result.memory[result.parent + CAR_META], 0x43);
  assert.equal(result.memory[result.parent + CDR_META], 1);
  assert.equal(result.memory[result.child + CAR_META], 0x43);
  assert.equal(result.memory[result.orphan + CAR_META], 0);
});

Deno.test("collector preserves an edge missed by a full worklist", async () => {
  const result = await collectorFixture(513);
  assert.equal(result.memory[result.parent + CAR_META], 0x43);
  assert.equal(result.memory[result.parent + CDR_META], 1);
  assert.equal(result.memory[result.child + CAR_META], 0x43);
  assert.equal(result.memory[result.orphan + CAR_META], 0);
});

Deno.test("collector does not read past a root scan interval", async () => {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  memory[0xa000] = 1;
  writeWord(memory, 0x9ffe, 0xa000);
  cpu.h = 0x9f;
  cpu.l = 0xfe;
  cpu.d = 0xa0;
  cpu.e = 0;
  cpu.pc = assembled.address("SRTSCAN");
  cpu.sp = 0xdff0;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 10_000_000, "collector did not return");
    assembled.runtime.step();
  }
  assert.equal(cpu.sp, 0xdff2);
  assert.equal(memory[0xa000], 1, "scan read beyond the A000 boundary");
});

Deno.test("pair allocator follows free chains across a second slab", async () => {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  const call = (label: string) => {
    cpu.pc = assembled.address(label);
    cpu.sp = 0xdff0;
    writeWord(memory, cpu.sp, 0xef00);
    let steps = 0;
    while (cpu.pc !== 0xef00) {
      assert.ok(++steps < 10_000_000, `${label} did not return`);
      assembled.runtime.step();
    }
    assert.equal(cpu.sp, 0xdff2);
    return {
      carry: cpu.flags.C,
      payload: (cpu.h << 8) | cpu.l,
    };
  };

  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(call("SRTGPINI").carry, 0);
  assert.equal(call("SRTPIN").carry, 0);

  const records: number[] = [];
  for (let index = 0; index < PAIRS_PER_SLAB * 2; index++) {
    const result = call("SRTFINDP");
    assert.equal(result.carry, 0, `allocation ${index} failed`);
    records.push(result.payload);
  }
  const firstBase = records[0];
  const secondBase = records[PAIRS_PER_SLAB];
  assert.equal(
    records[PAIRS_PER_SLAB - 1],
    firstBase + (PAIRS_PER_SLAB - 1) * PAIR_BYTES,
  );
  assert.equal(records[PAIRS_PER_SLAB], secondBase);
  assert.equal(memory[assembled.address("SRTPSLBN")], 2);

  assert.equal(call("SRTGC").carry, 0);
  const reused = call("SRTFINDP");
  assert.equal(reused.carry, 0);
  assert.ok(
    records.includes(reused.payload),
    "collection did not return a pair record to the free chain",
  );
});

Deno.test("constructor roots survive collection and retain both inputs", async () => {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);
  // Keep the fixture at one slab so the constructor exercises collection
  // instead of growing into the second managed extent.
  memory[assembled.address("SRTPSLIM")] = 1;

  const records: number[] = [];
  for (let index = 0; index < PAIRS_PER_SLAB; index++) {
    const result = callLabel(assembled, "SRTFINDP", memory, cpu);
    assert.equal(result.carry, 0);
    records.push(result.payload);
    memory[result.payload + CAR_META] = 0x40;
  }
  const root = records[0];
  writeWord(memory, root, 42);
  writeWord(memory, root + CDR_PAYLOAD, 0xfe02);
  memory[root + CAR_META] = 0x43;
  memory[root + CDR_META] = 0;

  writeWord(memory, assembled.address("SRTQCAR"), root);
  writeWord(memory, assembled.address("SRTQCDR"), 5678);
  memory[assembled.address("SRTQCTAG")] = 1;
  memory[assembled.address("SRTQDTAG")] = 3;

  const result = callLabel(assembled, "SRTMAKEP", memory, cpu);
  assert.equal(result.carry, 0);
  const pair = result.payload;
  assert.equal(memory[root + CAR_META], 0x43, "pending pair root was swept");
  assert.equal(memory[pair] | memory[pair + 1] << 8, root);
  assert.equal(
    memory[pair + CDR_PAYLOAD] | memory[pair + CDR_PAYLOAD + 1] << 8,
    5678,
  );
  assert.equal(memory[pair + CAR_META], 0x41);
  assert.equal(memory[pair + CDR_META], 3);

  for (let index = 0; index < PAIRS_PER_SLAB - 2; index++) {
    assert.equal(callLabel(assembled, "SRTFINDP", memory, cpu).carry, 0);
  }
  writeWord(memory, assembled.address("SRTQCAR"), 1234);
  writeWord(memory, assembled.address("SRTQCDR"), 5678);
  memory[assembled.address("SRTQCTAG")] = 3;
  memory[assembled.address("SRTQDTAG")] = 3;
  const scalarPair = callLabel(assembled, "SRTMAKEP", memory, cpu).payload;
  assert.equal(memory[scalarPair] | memory[scalarPair + 1] << 8, 1234);
  assert.equal(
    memory[scalarPair + CDR_PAYLOAD] |
      memory[scalarPair + CDR_PAYLOAD + 1] << 8,
    5678,
  );
  assert.equal(memory[scalarPair + CAR_META], 0x43);
  assert.equal(memory[scalarPair + CDR_META], 3);
});

Deno.test("overflow fallback restores its slab cursor after child tracing", async () => {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  const table = assembled.address("SRTPSLT");
  memory[assembled.address("SRTPSLBN")] = 2;
  const first = (assembled.image.end + 0xff) & 0xff00;
  const second = first + 0x100;
  assert.ok(second + 0x100 <= 0x8000, "slabs overlap root workspace");
  memory[table] = first >>> 8;
  memory[table + 1] = 0;
  memory[table + 2] = 0xff;
  memory[table + 3] = second >>> 8;
  memory[table + 4] = 0;
  memory[table + 5] = 0xff;
  writeWord(memory, first, 0);
  writeWord(memory, first + CDR_PAYLOAD, second);
  memory[first + CAR_META] = 0xc1;
  memory[first + CDR_META] = 1;
  writeWord(memory, first + PAIR_BYTES, 0);
  writeWord(memory, first + PAIR_BYTES + CDR_PAYLOAD, first + 2 * PAIR_BYTES);
  memory[first + PAIR_BYTES + CAR_META] = 0xc1;
  memory[first + PAIR_BYTES + CDR_META] = 1;
  memory[first + 2 * PAIR_BYTES + CAR_META] = 0x43;
  memory[second + CAR_META] = 0x43;
  assert.equal(callLabel(assembled, "SRTFSCRN", memory, cpu).carry, 0);
  assert.equal(memory[first + 2 * PAIR_BYTES + CAR_META], 0xc3);
  assert.equal(memory[second + CAR_META], 0xc3);
});

Deno.test("pair slabs return pages and reuse released descriptors", async () => {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  const before = memory[assembled.address("SRTPGFRE")] |
    memory[assembled.address("SRTPGFRE") + 1] << 8;
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);
  const firstPairPage = memory[assembled.address("SRTPSLT")] << 8;
  assert.equal(callLabel(assembled, "SRTGC", memory, cpu).carry, 0);
  const after = memory[assembled.address("SRTPGFRE")] |
    memory[assembled.address("SRTPGFRE") + 1] << 8;
  assert.equal(after, before, "empty slab did not return its page");
  assert.equal(memory[assembled.address("SRTPSLT")], 0);
  const reused = callLabel(assembled, "SRTFINDP", memory, cpu);
  assert.equal(reused.carry, 0);
  assert.equal(reused.payload, firstPairPage);
  assert.equal(memory[assembled.address("SRTPSLBN")], 1);
});

Deno.test("pair slabs reuse a middle descriptor without losing live slabs", async () => {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);

  const records: number[] = [];
  for (let index = 0; index < PAIRS_PER_SLAB * 3; index++) {
    const result = callLabel(assembled, "SRTFINDP", memory, cpu);
    assert.equal(result.carry, 0, `allocation ${index} failed`);
    records.push(result.payload);
  }
  const firstBase = records[0];
  const middleBase = records[PAIRS_PER_SLAB];
  const lastBase = records[PAIRS_PER_SLAB * 2];
  assert.notEqual(firstBase, middleBase);
  assert.notEqual(middleBase, lastBase);

  for (let slot = 0; slot < PAIRS_PER_SLAB; slot++) {
    memory[middleBase + slot * PAIR_BYTES + CAR_META] = 0;
  }
  assert.equal(callLabel(assembled, "SRTPSRB", memory, cpu).carry, 0);
  const descriptor = assembled.address("SRTPSLT");
  assert.notEqual(memory[descriptor], 0);
  assert.equal(memory[descriptor + 3], 0);
  assert.notEqual(memory[descriptor + 6], 0);

  const replacement = callLabel(assembled, "SRTFINDP", memory, cpu);
  assert.equal(replacement.carry, 0);
  assert.notEqual(memory[descriptor], 0, "first descriptor was overwritten");
  assert.notEqual(
    memory[descriptor + 3],
    0,
    "middle descriptor was not reused",
  );
  assert.notEqual(memory[descriptor + 6], 0, "last descriptor was overwritten");
  cpu.a = 1;
  cpu.h = firstBase >>> 8;
  cpu.l = firstBase & 255;
  assert.equal(
    callLabel(assembled, "SRTPCHK", memory, cpu).carry,
    0,
    "live pair in the first slab was lost",
  );
  cpu.a = 1;
  cpu.h = lastBase >>> 8;
  cpu.l = lastBase & 255;
  assert.equal(
    callLabel(assembled, "SRTPCHK", memory, cpu).carry,
    0,
    "live pair after a released descriptor was lost",
  );
});

Deno.test("pair descriptor table reaches beyond thirty-two slabs", async () => {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);
  for (let index = 0; index < PAIRS_PER_SLAB * 33; index++) {
    const result = callLabel(assembled, "SRTFINDP", memory, cpu);
    assert.equal(result.carry, 0, `allocation ${index} failed`);
  }
  assert.equal(memory[assembled.address("SRTPSLBN")], 33);
  assert.equal(callLabel(assembled, "SRTFINDP", memory, cpu).carry, 0);
});
