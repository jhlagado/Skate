import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";

type RuntimeImage = Awaited<ReturnType<typeof loadAssembly>>;
type CpuState = {
  a: number;
  b: number;
  h: number;
  l: number;
  ix: number;
  pc: number;
  sp: number;
  flags: { C: number };
};

function writeWord(memory: Uint8Array, address: number, value: number) {
  memory[address] = value & 255;
  memory[address + 1] = value >>> 8;
}

function readWord(memory: Uint8Array, address: number) {
  return memory[address] | memory[address + 1] << 8;
}

function runEntry(
  assembled: RuntimeImage,
  label: string,
  memory: Uint8Array,
  cpu: CpuState,
  setup: () => void,
  beforeConstruction: (() => void) | undefined = undefined,
  limit = 20_000_000,
) {
  const returnAddress = 0xef00;
  const gcAddress = assembled.address("SRTGC");
  const constructorAddress = assembled.address("SRTMAKEP");
  cpu.pc = assembled.address(label);
  cpu.sp = 0xdff0;
  writeWord(memory, cpu.sp, returnAddress);
  setup();
  let gcCount = 0;
  let forcedCount = 0;
  let steps = 0;
  while (cpu.pc !== returnAddress) {
    assert.ok(++steps < limit, `${label} did not return`);
    if (cpu.pc === gcAddress) gcCount++;
    if (beforeConstruction && cpu.pc === constructorAddress) {
      beforeConstruction();
      forcedCount++;
    }
    assembled.runtime.step();
  }
  return {
    carry: cpu.flags.C,
    forcedCount,
    gcCount,
    payload: (cpu.h << 8) | cpu.l,
    sp: cpu.sp,
    steps,
  };
}

function initialiseSinglePairPage(
  assembled: RuntimeImage,
  memory: Uint8Array,
  cpu: CpuState,
) {
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(
    runEntry(assembled, "SRTGPINI", memory, cpu, () => {}).carry,
    0,
  );
  assert.equal(
    runEntry(assembled, "SRTPIN", memory, cpu, () => {}).carry,
    0,
  );
  // Keep this fixture to one class page so the constructor must collect
  // instead of growing into the second managed extent.
  memory[assembled.address("SRTPSLIM")] = 1;
  return memory[assembled.address("SRTPSLT")] << 8;
}

function fillSinglePairPage(
  assembled: RuntimeImage,
  memory: Uint8Array,
  page: number,
) {
  const end = page + 0x100;
  const canary = memory.slice(end, end + 4);
  for (let address = page; address + 4 < end; address += 5) {
    if ((memory[address + 4] & 0x40) !== 0) continue;
    writeWord(memory, address, 0);
    writeWord(memory, address + 2, 0);
    memory[address + 4] = 0x40;
  }
  assert.deepEqual(memory.slice(end, end + 4), canary);
  memory[assembled.address("SRTPSLT") + 2] = 0xff;
  memory[assembled.address("SRTPSLHD")] = 0;
}

function callRoutine(
  assembled: RuntimeImage,
  label: string,
  memory: Uint8Array,
  cpu: CpuState,
  limit = 20_000_000,
) {
  return runEntry(assembled, label, memory, cpu, () => {}, undefined, limit);
}

Deno.test("direct cons preserves both scalar inputs through collection", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu as CpuState;
  const pairPage = initialiseSinglePairPage(assembled, memory, cpu);
  const result = runEntry(
    assembled,
    "SRTCONS",
    memory,
    cpu,
    () => {
      writeWord(memory, 0xdff2, 0x5678);
      writeWord(memory, 0xdff4, 0x0300);
      writeWord(memory, 0xdff6, 0x1234);
      writeWord(memory, 0xdff8, 0x0300);
    },
    () => fillSinglePairPage(assembled, memory, pairPage),
  );
  assert.equal(result.gcCount, 1);
  assert.equal(result.forcedCount, 1);
  assert.equal(result.sp, 0xdffa);
  assert.equal(result.carry, 0);
  assert.equal(readWord(memory, result.payload), 0x1234);
  assert.equal(readWord(memory, result.payload + 2), 0x5678);
  assert.equal(memory[result.payload + 4], 0x5b);
});

Deno.test("packet cons preserves both scalar inputs through collection", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu as CpuState;
  const pairPage = initialiseSinglePairPage(assembled, memory, cpu);
  const packet = assembled.address("SRTARGPK");
  const result = runEntry(
    assembled,
    "SRTPCONS",
    memory,
    cpu,
    () => {
      cpu.ix = 0xef00;
      memory[assembled.address("SRTARGC")] = 2;
      writeWord(memory, packet, 0x1234);
      memory[packet + 2] = 3;
      writeWord(memory, packet + 4, 0x5678);
      memory[packet + 6] = 3;
    },
    () => fillSinglePairPage(assembled, memory, pairPage),
  );
  assert.equal(result.gcCount, 1);
  assert.equal(result.forcedCount, 1);
  assert.equal(result.sp, 0xdff0);
  assert.equal(result.carry, 0);
  assert.equal(readWord(memory, result.payload), 0x1234);
  assert.equal(readWord(memory, result.payload + 2), 0x5678);
  assert.equal(memory[result.payload + 4], 0x5b);
});

Deno.test("quoted list construction survives collection at both allocations", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu as CpuState;
  const pairPage = initialiseSinglePairPage(assembled, memory, cpu);
  const quoted = assembled.address("SRTQBASE");
  const result = runEntry(
    assembled,
    "SRTQBLD",
    memory,
    cpu,
    () => {
      writeWord(memory, quoted, 41);
      memory[quoted + 2] = 3;
      writeWord(memory, quoted + 4, 42);
      memory[quoted + 6] = 3;
      writeWord(memory, assembled.address("SRTQSP"), quoted + 8);
      cpu.a = 2;
      cpu.b = 0;
    },
    () => fillSinglePairPage(assembled, memory, pairPage),
  );
  assert.equal(result.gcCount, 2);
  assert.equal(result.forcedCount, 2);
  assert.equal(result.sp, 0xdff2);
  assert.equal(result.carry, 0);
  const head = result.payload;
  const tail = readWord(memory, head + 2);
  assert.equal(readWord(memory, head), 41);
  assert.equal(memory[head + 4], 0x4b);
  assert.equal(readWord(memory, tail), 42);
  assert.equal(readWord(memory, tail + 2), 0xfe02);
  assert.equal(memory[tail + 4], 0x43);
});

Deno.test("tracing preserves a linked list of more than one thousand pairs", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-runtime-image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu as CpuState;
  cpu.h = assembled.image.end >>> 8;
  cpu.l = assembled.image.end & 255;
  assert.equal(
    callRoutine(assembled, "SRTGPINI", memory, cpu).carry,
    0,
  );
  assert.equal(callRoutine(assembled, "SRTPIN", memory, cpu).carry, 0);

  const records: number[] = [];
  for (let index = 0; index < 1100; index++) {
    const result = callRoutine(assembled, "SRTFINDP", memory, cpu);
    assert.equal(result.carry, 0, `allocation ${index} failed`);
    records.push(result.payload);
  }
  for (let index = 0; index < records.length; index++) {
    const address = records[index];
    writeWord(memory, address, index);
    if (index + 1 < records.length) {
      writeWord(memory, address + 2, records[index + 1]);
      memory[address + 4] = 0x4b;
    } else {
      writeWord(memory, address + 2, 0xfe02);
      memory[address + 4] = 0x43;
    }
  }
  writeWord(memory, 0xd700, records[0]);
  memory[0xd702] = 1;
  memory[0xd703] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), 0xd700);
  writeWord(memory, assembled.address("SRTGEND"), 0xd704);
  const result = callRoutine(assembled, "SRTGC", memory, cpu, 50_000_000);
  assert.equal(result.sp, 0xdff2);
  for (let index = 0; index < records.length; index++) {
    const address = records[index];
    assert.equal(readWord(memory, address), index);
    assert.equal(
      readWord(memory, address + 2),
      index + 1 < records.length ? records[index + 1] : 0xfe02,
    );
    assert.equal(memory[address + 4], index + 1 < records.length ? 0x4b : 0x43);
  }
});
