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

async function rootRuntime() {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  assert.ok(assembled.image.end <= 0x7000, "runtime overlaps fixture scratch");
  const pairBase = 0x8000;
  const heapBase = assembled.address("RT_HEAP");
  const descriptor = assembled.address("PS_TABLE");
  const imageEnd = (assembled.image.end + 0xff) & 0xff00;
  const closureMapBytes = assembled.address("GC_MARKS") -
    assembled.address("CL_MAP");
  const bindingMapBytes = assembled.address("RT_HIGH") -
    assembled.address("BND_MAP");

  memory.fill(0, imageEnd, 0xe000);
  memory.fill(
    0,
    assembled.address("CL_MAP"),
    assembled.address("CL_MAP") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("GC_MARKS"),
    assembled.address("GC_MARKS") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("BND_MAP"),
    assembled.address("BND_MAP") + bindingMapBytes,
  );
  memory.fill(
    0,
    assembled.address("CL_OWNER"),
    assembled.address("CL_OWNER") + 128,
  );
  memory.fill(
    0,
    assembled.address("CL_LIVE"),
    assembled.address("CL_LIVE") + 128,
  );
  memory.fill(
    0,
    assembled.address("CL_PHYS"),
    assembled.address("CL_PHYS") + 128,
  );
  memory.fill(
    0,
    assembled.address("BND_PHYS"),
    assembled.address("BND_PHYS") + 128,
  );
  memory[assembled.address("PS_COUNT")] = 1;
  memory[descriptor] = pairBase >>> 8;
  memory[descriptor + 1] = 0;
  memory[descriptor + 2] = 0xff;
  for (let index = 0; index < PAIRS_PER_SLAB; index++) {
    memory[pairBase + index * PAIR_BYTES + CAR_META] = 0x43;
    memory[pairBase + index * PAIR_BYTES + CDR_META] = 0;
  }

  writeWord(memory, assembled.address("HEAP_LIM"), 0xc000);
  writeWord(memory, assembled.address("RT_LIMIT"), 0xc200);
  writeWord(memory, assembled.address("G_BASE"), 0);
  writeWord(memory, assembled.address("G_END"), 0);
  writeWord(memory, assembled.address("QT_START"), 0);
  writeWord(memory, assembled.address("QT_STOP"), 0);
  writeWord(memory, assembled.address("OPS_SP"), assembled.address("RT_OPLO"));
  writeWord(memory, assembled.address("QT_SP"), assembled.address("RT_QTLO"));
  memory[assembled.address("ARG_CNT")] = 0;
  memory[assembled.address("SLOT_CNT")] = 0;
  writeWord(memory, assembled.address("ENV_CUR"), 0);
  writeWord(memory, assembled.address("ENV_RET"), 0);
  memory[assembled.address("ENV_RCNT")] = 0;
  memory[assembled.address("QT_HELD")] = 0;
  memory[assembled.address("GC_HOLD")] = 0;
  writeWord(memory, assembled.address("CL_TOP"), 0);
  writeWord(memory, assembled.address("BND_TOP"), 0);
  writeWord(memory, assembled.address("BND_CNT"), 0);

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
    writeWord(memory, address + CDR_PAYLOAD, cdr);
    memory[address + CAR_META] = 0x43;
    memory[address + CDR_META] = 0;
  }

  function bindingStart(address: number) {
    const cell = (address - heapBase) >> 2;
    memory[assembled.address("BND_MAP") + (cell >> 3)] |= 1 << (cell & 7);
  }

  function closureStart(address: number) {
    const unit = (address - heapBase) >> 1;
    memory[assembled.address("CL_MAP") + (unit >> 3)] |= 1 << (unit & 7);
  }

  function bindingPages(...pages: number[]) {
    memory[assembled.address("BND_CNT")] = pages.length;
    pages.forEach((page, index) => {
      memory[assembled.address("BND_PHYS") + index] = page;
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
  writeWord(memory, 0x7600, pairAddress);
  memory[0x7602] = 0; // Clear extension byte.
  memory[0x7603] = 0x11;
  writeWord(memory, assembled.address("G_BASE"), 0x7600);
  writeWord(memory, assembled.address("G_END"), 0x7604);
  call("GC");
}

Deno.test("exact roots preserve a published global pair and ignore inactive bytes", async () => {
  const fixture = await rootRuntime();
  const { memory, pairBase, pair } = fixture;
  pair(pairBase);
  pair(pairBase + PAIR_BYTES);
  memory[0x7600] = pairBase & 255;
  memory[0x7601] = pairBase >>> 8;
  memory[0x7602] = 0;
  preserveStaticPair(fixture, pairBase);
  assert.equal(memory[pairBase + CAR_META], 0x43);
  assert.equal(memory[pairBase + PAIR_BYTES + CAR_META], 0);
});

Deno.test("exact roots preserve an active argument packet", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, pairBase, pair, call } = fixture;
  pair(pairBase);
  const packet = assembled.address("ARG_PKT");
  writeWord(memory, packet, pairBase);
  memory[packet + 2] = 0; // Clear extension byte.
  memory[packet + 3] = 0x11;
  memory[assembled.address("ARG_CNT")] = 1;
  call("GC");
  assert.equal(memory[pairBase + CAR_META], 0x43);
});

Deno.test("exact roots preserve generated operands", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, pairBase, pair, call } = fixture;
  pair(pairBase);
  const roots = assembled.address("ROOT_TAB");
  writeWord(memory, roots, pairBase);
  memory[roots + 2] = 0; // Clear extension byte.
  memory[roots + 3] = 0x11;
  memory[assembled.address("ROOT_CNT")] = 1;
  call("GC");
  assert.equal(memory[pairBase + CAR_META], 0x43);
});

Deno.test("exact roots preserve operator and quoted stack entries", async () => {
  for (const stack of ["RT_OPLO", "RT_QTLO"] as const) {
    const fixture = await rootRuntime();
    const { assembled, memory, pairBase, pair, call } = fixture;
    pair(pairBase);
    const base = assembled.address(stack);
    writeWord(memory, base, pairBase);
    memory[base + 2] = 0; // Clear extension byte.
    memory[base + 3] = 1;
    writeWord(
      memory,
      assembled.address(stack === "RT_OPLO" ? "OPS_SP" : "QT_SP"),
      base + 4,
    );
    call("GC");
    assert.equal(memory[pairBase + CAR_META], 0x43, stack);
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
  const map = 0x7600;
  const binding = 0x7200;
  bindingStart(binding);
  bindingPages(0x72);
  writeWord(memory, map, binding);
  memory[map + 2] = 0;
  memory[map + 3] = 0x20; // Promoted.
  writeWord(memory, binding, pairBase);
  memory[binding + 3] = 0x51;
  writeWord(memory, assembled.address("ENV_CUR"), map);
  memory[assembled.address("SLOT_CNT")] = 1;
  call("GC");
  assert.equal(memory[pairBase + CAR_META], 0x43);
  assert.equal(memory[binding + 3] & 0xe0, 0x40);
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
  pair(pairBase + PAIR_BYTES);
  const currentMap = 0x7600;
  const callerMap = 0x7610;
  const currentBinding = 0x7200;
  const callerBinding = 0x7204;
  const currentDescriptor = 0xc100;
  const callerDescriptor = 0xc140;
  bindingStart(currentBinding);
  bindingStart(callerBinding);
  bindingPages(0x72);
  writeWord(memory, currentMap, currentBinding);
  writeWord(memory, callerMap, callerBinding);
  memory[currentMap + 2] = 0;
  memory[currentMap + 3] = 0x20; // Promoted.
  memory[callerMap + 2] = 0;
  memory[callerMap + 3] = 0x20; // Promoted.
  writeWord(memory, currentBinding, pairBase);
  writeWord(memory, callerBinding, pairBase + PAIR_BYTES);
  memory[currentBinding + 3] = 0x51;
  memory[callerBinding + 3] = 0x51;
  memory[currentDescriptor + 3] = 1;
  memory[callerDescriptor + 3] = 1;
  writeWord(memory, currentMap - 4, callerMap);
  writeWord(memory, currentMap - 6, currentDescriptor);
  writeWord(memory, callerMap - 4, 0);
  writeWord(memory, callerMap - 6, callerDescriptor);
  writeWord(memory, assembled.address("ENV_CUR"), currentMap);
  writeWord(memory, assembled.address("FRM_BASE"), currentMap);
  memory[assembled.address("SLOT_CNT")] = 1;
  call("GC");
  assert.equal(memory[pairBase + CAR_META], 0x43);
  assert.equal(memory[pairBase + PAIR_BYTES + CAR_META], 0x43);
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
  const closure = 0x7800;
  const binding = 0x7c00;
  bindingStart(binding);
  bindingPages(0x7c);
  fixture.closureStart(closure);
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 2] = 0;
  memory[descriptor + 3] = 1;
  memory[descriptor + 5] = 1; // One mask byte each:
  memory[descriptor + 6] = 0; // owned slots,
  memory[descriptor + 7] = 1; // captured slots.
  writeWord(memory, closure, descriptor);
  writeWord(memory, closure + 2, binding);
  writeWord(memory, binding, pairBase);
  memory[binding + 3] = 0x51;
  writeWord(memory, 0x7600, closure);
  memory[0x7602] = 0; // Clear extension byte.
  memory[0x7603] = 0x12;
  writeWord(memory, assembled.address("G_BASE"), 0x7600);
  writeWord(memory, assembled.address("G_END"), 0x7604);
  call("GC");
  assert.equal(memory[pairBase + CAR_META], 0x43);
});

Deno.test("closure roots drain a full worklist without reporting an error", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, heapBase, call } = fixture;
  const descriptor = 0xc100;
  const closureBase = 0x7800;
  const roots = 0x8200;
  assert.ok(roots + 513 * 4 <= assembled.address("RT_LOEND"));
  const count = 513;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 2] = 0;
  memory[descriptor + 3] = 0;
  memory[assembled.address("G_BASE")] = roots & 255;
  memory[assembled.address("G_BASE") + 1] = roots >>> 8;
  writeWord(memory, assembled.address("G_END"), roots + count * 4);
  // Closure starts are four-byte aligned; odd map units are object markers.
  writeWord(memory, assembled.address("HEAP_LIM"), closureBase + count * 4);
  for (let index = 0; index < count; index++) {
    const closure = closureBase + index * 4;
    writeWord(memory, closure, descriptor);
    const unit = ((closureBase - heapBase) >> 1) + index * 2;
    const bit = assembled.address("CL_MAP") + (unit >> 3);
    memory[bit] |= 1 << (unit & 7);
    const root = roots + index * 4;
    writeWord(memory, root, closure);
    memory[root + 2] = 0; // Clear extension byte.
    memory[root + 3] = 0x12;
  }
  call("GC");
  for (let index = 0; index < count; index++) {
    const unit = ((closureBase - heapBase) >> 1) + index * 2;
    const mark = assembled.address("CL_MAP") + (unit >> 3);
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
  const chainBase = 0x7800;
  const emptyBase = 0x8c00;
  const bindingBase = 0x7000;
  const roots = 0x8200;
  assert.ok(roots + 513 * 4 <= assembled.address("RT_LOEND"));
  const chainCount = 160;
  const emptyCount = 511;
  writeWord(memory, branchDescriptor, 0x4000);
  memory[branchDescriptor + 3] = 2;
  memory[branchDescriptor + 5] = 1; // One mask byte each:
  memory[branchDescriptor + 6] = 0; // owned slots,
  memory[branchDescriptor + 7] = 3; // captured slots.
  writeWord(memory, emptyDescriptor, 0x4000);
  memory[emptyDescriptor + 3] = 0;
  // Closure starts are four-byte aligned, so six-byte closures use eight-byte
  // slots and two-byte closures use four-byte slots.
  for (let index = 0; index < chainCount; index++) {
    const closure = chainBase + index * 8;
    const firstBinding = bindingBase + index * 8;
    const secondBinding = firstBinding + 4;
    closureStart(closure);
    writeWord(memory, closure, branchDescriptor);
    writeWord(memory, closure + 2, firstBinding);
    writeWord(memory, closure + 4, secondBinding);
    bindingStart(firstBinding);
    bindingStart(secondBinding);
    const firstChild = index + 1 < chainCount
      ? chainBase + (index + 1) * 8
      : 0xfe02;
    const secondChild = index + 2 < chainCount
      ? chainBase + (index + 2) * 8
      : 0xfe02;
    writeWord(memory, firstBinding, firstChild);
    memory[firstBinding + 3] = (index + 1 < chainCount ? 2 : 0) | 0x50;
    writeWord(memory, secondBinding, secondChild);
    memory[secondBinding + 3] = (index + 2 < chainCount ? 2 : 0) | 0x50;
  }
  bindingPages(0x70, 0x71, 0x72, 0x73, 0x74);
  for (let index = 0; index < emptyCount; index++) {
    const closure = emptyBase + index * 4;
    closureStart(closure);
    writeWord(memory, closure, emptyDescriptor);
  }
  for (let index = 0; index < emptyCount; index++) {
    const root = roots + index * 4;
    writeWord(memory, root, emptyBase + index * 4);
    memory[root + 2] = 0; // Clear extension byte.
    memory[root + 3] = 0x12;
  }
  const chainRoot = roots + emptyCount * 4;
  writeWord(memory, chainRoot, chainBase);
  memory[chainRoot + 2] = 0; // Clear extension byte.
  memory[chainRoot + 3] = 0x12;
  writeWord(memory, assembled.address("G_BASE"), roots);
  writeWord(memory, assembled.address("G_END"), roots + 512 * 4);
  writeWord(memory, assembled.address("HEAP_LIM"), 0xc000);
  const result = call("GC");
  assert.equal(result.carry, 0);
  assert.equal(memory[assembled.address("CL_FULL")], 1);
  for (let index = 0; index < chainCount; index++) {
    const unit = ((chainBase - heapBase) >> 1) + index * 4;
    const mark = assembled.address("CL_MAP") + (unit >> 3);
    assert.ok(memory[mark] & (1 << (unit & 7)), `chain closure ${index}`);
  }
});

Deno.test("an interior pair pointer is rejected without touching the canary", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, pairBase, pair, call } = fixture;
  pair(pairBase);
  memory[0x7f00] = 0xa5;
  writeWord(memory, 0x7800, pairBase + 1);
  memory[0x7802] = 0; // Clear extension byte.
  memory[0x7803] = 0x11;
  writeWord(memory, assembled.address("G_BASE"), 0x7800);
  writeWord(memory, assembled.address("G_END"), 0x7804);
  call("GC");
  assert.equal(memory[pairBase + CAR_META], 0);
  assert.equal(memory[0x7f00], 0xa5);
});

Deno.test("an unaligned binding interior is rejected before its flags change", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, bindingStart, call } = fixture;
  const binding = 0x7200;
  bindingStart(binding);
  memory[binding + 3] = 0x51;
  memory[binding + 4] = 1;
  call("GC_VAR", binding + 1);
  assert.equal(memory[binding + 4], 1);
  assert.equal(memory[assembled.address("BND_FLAG")], 0);
});

Deno.test("a descriptor extent that wraps the address space is rejected", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, call } = fixture;
  const closure = 0x7800;
  const descriptor = 0xfff0;
  fixture.closureStart(closure);
  writeWord(memory, assembled.address("CL_OBJ"), closure);
  writeWord(memory, assembled.address("HEAP_LIM"), 0xc000);
  writeWord(memory, assembled.address("RT_LIMIT"), 0xc200);
  writeWord(memory, closure, descriptor);
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 0;
  const result = call("GC_OBJOK");
  assert.equal(result.carry, 1);
});

Deno.test("a binding extent that wraps the address space is rejected", async () => {
  const fixture = await rootRuntime();
  const { assembled, memory, call } = fixture;
  writeWord(memory, assembled.address("HEAP_LIM"), 0xc000);
  memory[0xb5ff] = 0x80;
  memory[0x0001] = 1;
  call("GC_VAR", 0xfffe);
  assert.equal(memory[0x0001], 1);
});
