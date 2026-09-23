import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";

function writeWord(memory: Uint8Array, address: number, value: number) {
  memory[address] = value & 255;
  memory[address + 1] = value >>> 8;
}

async function rootRuntime() {
  const assembled = await loadAssembly(
    "src/compiler/scope/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  const pairBase = 0x8000;
  const heapBase = assembled.address("SRTHEAP");
  const descriptor = assembled.address("SRTPSLT");
  const imageEnd = (assembled.image.end + 0xff) & 0xff00;
  const closureMapBytes = assembled.address("SRTCLMK") -
    assembled.address("SRTCLBM");
  const bindingMapBytes = assembled.address("SRTMPEND") -
    assembled.address("SRTBMB");

  memory.fill(0, imageEnd, 0xe000);
  memory.fill(
    0,
    assembled.address("SRTCLBM"),
    assembled.address("SRTCLBM") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("SRTCLMK"),
    assembled.address("SRTCLMK") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("SRTBMB"),
    assembled.address("SRTBMB") + bindingMapBytes,
  );
  memory.fill(
    0,
    assembled.address("SRTCLOWN"),
    assembled.address("SRTCLOWN") + 128,
  );
  memory.fill(
    0,
    assembled.address("SRTCLUSE"),
    assembled.address("SRTCLUSE") + 128,
  );
  memory.fill(
    0,
    assembled.address("SRTCLPBA"),
    assembled.address("SRTCLPBA") + 128,
  );
  memory.fill(
    0,
    assembled.address("SRTBPGS"),
    assembled.address("SRTBPGS") + 128,
  );
  memory[assembled.address("SRTPSLBN")] = 1;
  memory[descriptor] = pairBase >>> 8;
  memory[descriptor + 1] = 0;
  memory[descriptor + 2] = 0xff;
  for (let index = 0; index < 51; index++) {
    memory[pairBase + index * 5 + 4] = 0x43;
  }

  writeWord(memory, assembled.address("SRTHEAPP"), 0xc000);
  writeWord(memory, assembled.address("SRTIMGE"), 0xc200);
  writeWord(memory, assembled.address("SRTGBASE"), 0);
  writeWord(memory, assembled.address("SRTGEND"), 0);
  writeWord(memory, assembled.address("SRTQROOT"), 0);
  writeWord(memory, assembled.address("SRTQENDR"), 0);
  writeWord(memory, assembled.address("SRTOPS"), assembled.address("SRTOPB"));
  writeWord(memory, assembled.address("SRTQSP"), assembled.address("SRTQBASE"));
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTSLOTS")] = 0;
  writeWord(memory, assembled.address("SRTENV"), 0);
  writeWord(memory, assembled.address("SRTCENV"), 0);
  memory[assembled.address("SRTCENVN")] = 0;
  memory[assembled.address("SRTQACTV")] = 0;
  memory[assembled.address("SRTCRON")] = 0;
  writeWord(memory, assembled.address("SRTCLCUR"), 0);
  writeWord(memory, assembled.address("SRTBEND"), 0);
  writeWord(memory, assembled.address("SRTBPGN"), 0);

  function call(label: string, hl = 0) {
    cpu.h = hl >>> 8;
    cpu.l = hl & 255;
    cpu.pc = assembled.address(label);
    cpu.sp = 0xdff0;
    writeWord(memory, cpu.sp, 0xef00);
    let steps = 0;
    while (cpu.pc !== 0xef00) {
      assert.ok(++steps < 20_000_000, `${label} did not return`);
      assembled.runtime.step();
    }
    assert.equal(cpu.sp, 0xdff2);
    return { carry: cpu.flags.C, a: cpu.a };
  }

  function pair(address: number, car = 1, cdr = 0xfe02) {
    writeWord(memory, address, car);
    writeWord(memory, address + 2, cdr);
    memory[address + 4] = 0x43;
  }

  function bindingStart(address: number) {
    const offset = address - heapBase;
    memory[assembled.address("SRTBMB") + (offset >> 3)] |= 1 << (offset & 7);
  }

  function closureStart(address: number) {
    const unit = (address - heapBase) >> 1;
    memory[assembled.address("SRTCLBM") + (unit >> 3)] |= 1 << (unit & 7);
  }

  function bindingPages(...pages: number[]) {
    memory[assembled.address("SRTBPGN")] = pages.length;
    pages.forEach((page, index) => {
      memory[assembled.address("SRTBPGS") + index] = page;
    });
  }

  return {
    assembled,
    memory,
    pairBase,
    heapBase,
    pair,
    bindingStart,
    bindingPages,
    closureStart,
    call,
  };
}

function preserveStaticPair(
  fixture: Awaited<ReturnType<typeof rootRuntime>>,
  pairAddress: number,
) {
  const { assembled, memory, call } = fixture;
  writeWord(memory, 0x5c00, pairAddress);
  memory[0x5c02] = 1;
  memory[0x5c03] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), 0x5c00);
  writeWord(memory, assembled.address("SRTGEND"), 0x5c04);
  call("SRTGC");
}

Deno.test("exact roots preserve a published global pair and ignore inactive bytes", async () => {
  const fixture = await rootRuntime();
  const { memory, pairBase, pair } = fixture;
  pair(pairBase);
  pair(pairBase + 5);
  memory[0x5c00] = pairBase & 255;
  memory[0x5c01] = pairBase >>> 8;
  memory[0x5c02] = 1;
  preserveStaticPair(fixture, pairBase);
  assert.equal(memory[pairBase + 4], 0x43);
  assert.equal(memory[pairBase + 5 + 4], 0);
});

Deno.test("exact roots preserve an active argument packet", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, pairBase, pair, call } = fixture;
  pair(pairBase);
  const packet = assembled.address("SRTARGPK");
  writeWord(memory, packet, pairBase);
  memory[packet + 2] = 1;
  memory[packet + 3] = 1;
  memory[assembled.address("SRTARGC")] = 1;
  call("SRTGC");
  assert.equal(memory[pairBase + 4], 0x43);
});

Deno.test("exact roots preserve generated operands", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, pairBase, pair, call } = fixture;
  pair(pairBase);
  const roots = assembled.address("SRTNRTAB");
  writeWord(memory, roots, pairBase);
  memory[roots + 2] = 1;
  memory[roots + 3] = 1;
  memory[assembled.address("SRTNCT")] = 1;
  call("SRTGC");
  assert.equal(memory[pairBase + 4], 0x43);
});

Deno.test("exact roots preserve operator and quoted stack entries", async () => {
  for (const stack of ["SRTOPB", "SRTQBASE"] as const) {
    const fixture = await rootRuntime();
    const { assembled, memory, pairBase, pair, call } = fixture;
    pair(pairBase);
    const base = assembled.address(stack);
    writeWord(memory, base, pairBase);
    memory[base + 2] = 1;
    memory[base + 3] = 0;
    writeWord(
      memory,
      assembled.address(stack === "SRTOPB" ? "SRTOPS" : "SRTQSP"),
      base + 4,
    );
    call("SRTGC");
    assert.equal(memory[pairBase + 4], 0x43, stack);
  }
});

Deno.test("an active environment traces its binding value", async () => {
  const fixture = await rootRuntime();
  const {
    assembled,
    memory,
    pairBase,
    pair,
    bindingStart,
    bindingPages,
    call,
  } = fixture;
  pair(pairBase);
  const map = 0x5c00;
  const binding = 0x6200;
  bindingStart(binding);
  bindingPages(0x62);
  writeWord(memory, map, binding);
  writeWord(memory, binding, pairBase);
  memory[binding + 2] = 0x29;
  writeWord(memory, assembled.address("SRTENV"), map);
  memory[assembled.address("SRTSLOTS")] = 1;
  call("SRTGC");
  assert.equal(memory[pairBase + 4], 0x43);
  assert.equal(memory[binding + 2] & 0x70, 0x20);
});

Deno.test("suspended environments remain roots through their frame maps", async () => {
  const fixture = await rootRuntime();
  const {
    assembled,
    memory,
    pairBase,
    pair,
    bindingStart,
    bindingPages,
    call,
  } = fixture;
  pair(pairBase);
  pair(pairBase + 5);
  const currentMap = 0x5c00;
  const callerMap = 0x5c10;
  const currentBinding = 0x6200;
  const callerBinding = 0x6204;
  const currentDescriptor = 0xc100;
  const callerDescriptor = 0xc140;
  bindingStart(currentBinding);
  bindingStart(callerBinding);
  bindingPages(0x62);
  writeWord(memory, currentMap, currentBinding);
  writeWord(memory, callerMap, callerBinding);
  writeWord(memory, currentBinding, pairBase);
  writeWord(memory, callerBinding, pairBase + 5);
  memory[currentBinding + 2] = 0x29;
  memory[callerBinding + 2] = 0x29;
  memory[currentDescriptor + 3] = 1;
  memory[callerDescriptor + 3] = 1;
  writeWord(memory, currentMap - 10 + 4, callerMap);
  writeWord(memory, currentMap - 10 + 2, currentDescriptor);
  writeWord(memory, callerMap - 10 + 4, 0);
  writeWord(memory, callerMap - 10 + 2, callerDescriptor);
  writeWord(memory, assembled.address("SRTENV"), currentMap);
  writeWord(memory, assembled.address("SRTFRAME"), currentMap);
  memory[assembled.address("SRTSLOTS")] = 1;
  call("SRTGC");
  assert.equal(memory[pairBase + 4], 0x43);
  assert.equal(memory[pairBase + 5 + 4], 0x43);
});

Deno.test("a captured closure traces only its declared binding slots", async () => {
  const fixture = await rootRuntime();
  const {
    assembled,
    memory,
    pairBase,
    pair,
    bindingStart,
    bindingPages,
    call,
  } = fixture;
  pair(pairBase);
  const descriptor = 0xc100;
  const closure = 0x7000;
  const binding = 0x7400;
  bindingStart(binding);
  bindingPages(0x74);
  fixture.closureStart(closure);
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 2] = 0;
  memory[descriptor + 3] = 1;
  memory[descriptor + 28] = 1;
  writeWord(memory, closure, descriptor);
  writeWord(memory, closure + 2, binding);
  writeWord(memory, binding, pairBase);
  memory[binding + 2] = 0x29;
  writeWord(memory, 0x5c00, closure);
  memory[0x5c02] = 2;
  memory[0x5c03] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), 0x5c00);
  writeWord(memory, assembled.address("SRTGEND"), 0x5c04);
  call("SRTGC");
  assert.equal(memory[pairBase + 4], 0x43);
});

Deno.test("closure roots drain a full worklist without reporting an error", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, heapBase, call } = fixture;
  const descriptor = 0xc100;
  const closureBase = 0x7000;
  const roots = 0x5000;
  const count = 513;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 2] = 0;
  memory[descriptor + 3] = 0;
  memory[assembled.address("SRTGBASE")] = roots & 255;
  memory[assembled.address("SRTGBASE") + 1] = roots >>> 8;
  writeWord(memory, assembled.address("SRTGEND"), roots + count * 4);
  writeWord(memory, assembled.address("SRTHEAPP"), closureBase + count * 2);
  for (let index = 0; index < count; index++) {
    const closure = closureBase + index * 2;
    writeWord(memory, closure, descriptor);
    const unit = ((closureBase - heapBase) >> 1) + index;
    const bit = assembled.address("SRTCLBM") + (unit >> 3);
    memory[bit] |= 1 << (unit & 7);
    const root = roots + index * 4;
    writeWord(memory, root, closure);
    memory[root + 2] = 2;
    memory[root + 3] = 1;
  }
  call("SRTGC");
  for (let index = 0; index < count; index++) {
    const unit = ((closureBase - heapBase) >> 1) + index;
    const mark = assembled.address("SRTCLBM") + (unit >> 3);
    assert.ok(
      memory[mark] & (1 << (unit & 7)),
      `closure ${index} was not traced`,
    );
  }
});

Deno.test("closure overflow fallback stays within the native stack", async () => {
  const fixture = await rootRuntime();
  const {
    assembled,
    memory,
    heapBase,
    bindingStart,
    bindingPages,
    closureStart,
    call,
  } = fixture;
  const branchDescriptor = 0xc100;
  const emptyDescriptor = 0xc140;
  const chainBase = 0x7000;
  const emptyBase = 0x7800;
  const bindingBase = 0x6000;
  const roots = 0x5000;
  const chainCount = 160;
  const emptyCount = 511;
  writeWord(memory, branchDescriptor, 0x4000);
  memory[branchDescriptor + 3] = 2;
  memory[branchDescriptor + 28] = 3;
  writeWord(memory, emptyDescriptor, 0x4000);
  memory[emptyDescriptor + 3] = 0;
  for (let index = 0; index < chainCount; index++) {
    const closure = chainBase + index * 6;
    const firstBinding = bindingBase + index * 8;
    const secondBinding = firstBinding + 4;
    closureStart(closure);
    writeWord(memory, closure, branchDescriptor);
    writeWord(memory, closure + 2, firstBinding);
    writeWord(memory, closure + 4, secondBinding);
    bindingStart(firstBinding);
    bindingStart(secondBinding);
    const firstChild = index + 1 < chainCount
      ? chainBase + (index + 1) * 6
      : 0xfe02;
    const secondChild = index + 2 < chainCount
      ? chainBase + (index + 2) * 6
      : 0xfe02;
    writeWord(memory, firstBinding, firstChild);
    memory[firstBinding + 2] = (index + 1 < chainCount ? 2 : 0) | 0x28;
    writeWord(memory, secondBinding, secondChild);
    memory[secondBinding + 2] = (index + 2 < chainCount ? 2 : 0) | 0x28;
  }
  bindingPages(0x60, 0x61, 0x62, 0x63, 0x64);
  for (let index = 0; index < emptyCount; index++) {
    const closure = emptyBase + index * 2;
    closureStart(closure);
    writeWord(memory, closure, emptyDescriptor);
  }
  for (let index = 0; index < emptyCount; index++) {
    const root = roots + index * 4;
    writeWord(memory, root, emptyBase + index * 2);
    memory[root + 2] = 2;
    memory[root + 3] = 1;
  }
  const chainRoot = roots + emptyCount * 4;
  writeWord(memory, chainRoot, chainBase);
  memory[chainRoot + 2] = 2;
  memory[chainRoot + 3] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), roots);
  writeWord(memory, assembled.address("SRTGEND"), roots + 512 * 4);
  writeWord(memory, assembled.address("SRTHEAPP"), 0xc000);
  const result = call("SRTGC");
  assert.equal(result.carry, 0);
  assert.equal(memory[assembled.address("SRTCLER")], 1);
  for (let index = 0; index < chainCount; index++) {
    const unit = ((chainBase - heapBase) >> 1) + index * 3;
    const mark = assembled.address("SRTCLBM") + (unit >> 3);
    assert.ok(memory[mark] & (1 << (unit & 7)), `chain closure ${index}`);
  }
});

Deno.test("an interior pair pointer is rejected without touching the canary", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, pairBase, pair, call } = fixture;
  pair(pairBase);
  memory[0x7f00] = 0xa5;
  writeWord(memory, 0x7000, pairBase + 1);
  memory[0x7002] = 1;
  memory[0x7003] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), 0x7000);
  writeWord(memory, assembled.address("SRTGEND"), 0x7004);
  call("SRTGC");
  assert.equal(memory[pairBase + 4], 0);
  assert.equal(memory[0x7f00], 0xa5);
});

Deno.test("an odd binding interior is rejected before its flags change", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, bindingStart, call } = fixture;
  const binding = 0x6200;
  bindingStart(binding);
  memory[binding + 2] = 0x29;
  memory[binding + 4] = 1;
  call("SRTBMARK", binding + 1);
  assert.equal(memory[binding + 4], 1);
  assert.equal(memory[assembled.address("SRTBFLG")], 0);
});

Deno.test("a descriptor extent that wraps the address space is rejected", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, call } = fixture;
  const closure = 0x7000;
  const descriptor = 0xfff0;
  fixture.closureStart(closure);
  writeWord(memory, assembled.address("SRTCLOBJ"), closure);
  writeWord(memory, assembled.address("SRTHEAPP"), 0xc000);
  writeWord(memory, assembled.address("SRTIMGE"), 0xc200);
  writeWord(memory, closure, descriptor);
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 0;
  const result = call("SRTCLVLD");
  assert.equal(result.carry, 1);
});

Deno.test("a binding extent that wraps the address space is rejected", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, call } = fixture;
  writeWord(memory, assembled.address("SRTHEAPP"), 0xc000);
  memory[0xb5ff] = 0x80;
  memory[0x0001] = 1;
  call("SRTBMARK", 0xfffe);
  assert.equal(memory[0x0001], 1);
});
