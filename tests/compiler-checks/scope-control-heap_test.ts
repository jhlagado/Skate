import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";

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
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  memory.fill(0, 0x8000, 0x9000);
  const slabBase = 0x4000;
  const slabCount = 11;
  const recordsPerSlab = 51;
  memory[assembled.address("SRTPSLBN")] = slabCount;
  for (let slab = 0; slab < slabCount; slab++) {
    const base = slabBase + slab * 0x100;
    const descriptor = assembled.address("SRTPSLT") + slab * 3;
    memory[descriptor] = base >>> 8;
    memory[descriptor + 1] = 0;
    memory[descriptor + 2] = 0xff;
    for (let slot = 0; slot < recordsPerSlab; slot++) {
      const address = base + slot * 5;
      writeWord(memory, address, 42);
      writeWord(memory, address + 2, 0xfe02);
      memory[address + 4] = 0;
    }
  }
  const recordAddress = (index: number) =>
    slabBase + Math.floor(index / recordsPerSlab) * 0x100 +
    (index % recordsPerSlab) * 5;
  for (let index = 0; index <= rootCount; index++) {
    memory[recordAddress(index) + 4] = 0x43; // integer CAR, empty-list CDR, allocated
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
  writeWord(memory, parent + 2, child);
  memory[parent + 4] = 0x4b; // integer CAR, pair CDR, allocated
  const orphan = recordAddress(560);
  memory[orphan + 4] = 0x43;
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
  assert.equal(result.memory[result.parent + 4], 0x4b);
  assert.equal(result.memory[result.child + 4], 0x43);
  assert.equal(result.memory[result.orphan + 4], 0);
});

Deno.test("collector preserves an edge at the worklist limit", async () => {
  const result = await collectorFixture(512);
  assert.equal(result.memory[result.parent + 4], 0x4b);
  assert.equal(result.memory[result.child + 4], 0x43);
  assert.equal(result.memory[result.orphan + 4], 0);
});

Deno.test("collector preserves an edge missed by a full worklist", async () => {
  const result = await collectorFixture(513);
  assert.equal(result.memory[result.parent + 4], 0x4b);
  assert.equal(result.memory[result.child + 4], 0x43);
  assert.equal(result.memory[result.orphan + 4], 0);
});

Deno.test("collector does not read past a root scan interval", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  memory.fill(0, 0x4000, 0x4100);
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
    "src/compiler/scope-control-runtime-image.asm",
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
  for (let index = 0; index < 102; index++) {
    const result = call("SRTFINDP");
    assert.equal(result.carry, 0, `allocation ${index} failed`);
    records.push(result.payload);
  }
  const firstBase = records[0];
  const secondBase = records[51];
  assert.equal(records[50], firstBase + 50 * 5);
  assert.equal(records[51], secondBase);
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
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = 0x5e;
  cpu.l = 0;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);
  // Keep the fixture at one slab so the constructor exercises collection
  // instead of growing into the second managed extent.
  memory[assembled.address("SRTPSLIM")] = 1;

  const records: number[] = [];
  for (let index = 0; index < 51; index++) {
    const result = callLabel(assembled, "SRTFINDP", memory, cpu);
    assert.equal(result.carry, 0);
    records.push(result.payload);
    memory[result.payload + 4] = 0x40;
  }
  const root = records[0];
  writeWord(memory, root, 42);
  writeWord(memory, root + 2, 0xfe02);
  memory[root + 4] = 0x43;

  writeWord(memory, assembled.address("SRTQCAR"), root);
  writeWord(memory, assembled.address("SRTQCDR"), 5678);
  memory[assembled.address("SRTQCTAG")] = 1;
  memory[assembled.address("SRTQDTAG")] = 3;

  const result = callLabel(assembled, "SRTMAKEP", memory, cpu);
  assert.equal(result.carry, 0);
  const pair = result.payload;
  assert.equal(memory[root + 4], 0x43, "pending pair root was swept");
  assert.equal(memory[pair] | memory[pair + 1] << 8, root);
  assert.equal(memory[pair + 2] | memory[pair + 3] << 8, 5678);
  assert.equal(memory[pair + 4], 0x59);

  for (let index = 0; index < 49; index++) {
    assert.equal(callLabel(assembled, "SRTFINDP", memory, cpu).carry, 0);
  }
  writeWord(memory, assembled.address("SRTQCAR"), 1234);
  writeWord(memory, assembled.address("SRTQCDR"), 5678);
  memory[assembled.address("SRTQCTAG")] = 3;
  memory[assembled.address("SRTQDTAG")] = 3;
  const scalarPair = callLabel(assembled, "SRTMAKEP", memory, cpu).payload;
  assert.equal(memory[scalarPair] | memory[scalarPair + 1] << 8, 1234);
  assert.equal(memory[scalarPair + 2] | memory[scalarPair + 3] << 8, 5678);
  assert.equal(memory[scalarPair + 4], 0x5b);
});

Deno.test("overflow fallback restores its slab cursor after child tracing", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  const table = assembled.address("SRTPSLT");
  memory[assembled.address("SRTPSLBN")] = 2;
  memory[table] = 0x40;
  memory[table + 1] = 0;
  memory[table + 2] = 0xff;
  memory[table + 3] = 0x41;
  memory[table + 4] = 0;
  memory[table + 5] = 0xff;
  const first = 0x4000;
  const second = 0x4100;
  writeWord(memory, first, 0);
  writeWord(memory, first + 2, second);
  memory[first + 4] = 0xc9;
  writeWord(memory, first + 5, 0);
  writeWord(memory, first + 7, first + 10);
  memory[first + 9] = 0xc9;
  memory[first + 10 + 4] = 0x43;
  memory[second + 4] = 0x43;
  assert.equal(callLabel(assembled, "SRTFSCRN", memory, cpu).carry, 0);
  assert.equal(memory[first + 10 + 4], 0xc3);
  assert.equal(memory[second + 4], 0xc3);
});

Deno.test("pair slabs return pages and reuse released descriptors", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = 0x5e;
  cpu.l = 0;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  const before = memory[assembled.address("SRTPGFRE")] |
    memory[assembled.address("SRTPGFRE") + 1] << 8;
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);
  assert.equal(callLabel(assembled, "SRTGC", memory, cpu).carry, 0);
  const after = memory[assembled.address("SRTPGFRE")] |
    memory[assembled.address("SRTPGFRE") + 1] << 8;
  assert.equal(after, before, "empty slab did not return its page");
  assert.equal(memory[assembled.address("SRTPSLT")], 0);
  const reused = callLabel(assembled, "SRTFINDP", memory, cpu);
  assert.equal(reused.carry, 0);
  assert.equal(reused.payload, 0x5f00);
  assert.equal(memory[assembled.address("SRTPSLBN")], 1);
});

Deno.test("pair slabs reuse a middle descriptor without losing live slabs", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);

  const records: number[] = [];
  for (let index = 0; index < 51 * 3; index++) {
    const result = callLabel(assembled, "SRTFINDP", memory, cpu);
    assert.equal(result.carry, 0, `allocation ${index} failed`);
    records.push(result.payload);
  }
  const firstBase = records[0];
  const middleBase = records[51];
  const lastBase = records[102];
  assert.notEqual(firstBase, middleBase);
  assert.notEqual(middleBase, lastBase);

  for (let slot = 0; slot < 51; slot++) {
    memory[middleBase + slot * 5 + 4] = 0;
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
});

Deno.test("pair descriptor table reaches beyond thirty-two slabs", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(callLabel(assembled, "SRTGPINI", memory, cpu).carry, 0);
  assert.equal(callLabel(assembled, "SRTPIN", memory, cpu).carry, 0);
  for (let index = 0; index < 51 * 33; index++) {
    const result = callLabel(assembled, "SRTFINDP", memory, cpu);
    assert.equal(result.carry, 0, `allocation ${index} failed`);
  }
  assert.equal(memory[assembled.address("SRTPSLBN")], 33);
  assert.equal(callLabel(assembled, "SRTFINDP", memory, cpu).carry, 0);
});
