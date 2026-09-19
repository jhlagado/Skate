import assert from "node:assert/strict";
import { collectorMachine } from "./collector-machine.ts";
const m = await collectorMachine();
const measures: {
  name: string;
  cycles: number;
  steps: number;
  passes: number;
  overflow: number;
}[] = [];
function ok(name: string, hl = 0, bc = 0, de = 0) {
  const r = m.call(name, hl, bc, de);
  assert.equal(r.status, 0, `${name} status`);
  assert.equal(r.carry, 0, `${name} carry`);
  return r;
}
function fail(name: string, status: number, hl = 0, bc = 0, de = 0) {
  const s = m.state(), heap = m.memory.slice(s.base, s.base + 4 * s.count);
  const r = m.call(name, hl, bc, de);
  assert.equal(r.status, status, `${name} status`);
  assert.equal(r.carry, 1);
  assert.deepEqual(m.state(), s, `${name} allocator state`);
  assert.deepEqual(
    m.memory.slice(s.base, s.base + 4 * s.count),
    heap,
    `${name} heap`,
  );
  return r;
}
function init(count: number, base = 0x8000, bitmap = 0x6000, allocate = true) {
  m.heapRange(base, count);
  m.bitmapRange(bitmap, Math.ceil(count / 8));
  ok("HINIT", base, count);
  ok("GCSET", bitmap, Math.ceil(count / 8));
  if (allocate) {
    ok("HRES", 0, count - 1);
    for (let i = 1; i < count; i++) ok("HPOP");
    ok("HDONE");
  }
  return { count, base, bitmap };
}
function roots(indices: number[], address = 0x4000, descriptors = 0x3000) {
  indices.forEach((i, n) => m.slot(address + 4 * n, [1, i]));
  m.descriptor(descriptors, address, indices.length);
  return descriptors;
}
function collected(
  expected: Set<number>,
  descriptor = 0x3000,
  count = 1,
  label = "",
) {
  const s = m.state();
  const before = m.memory.slice(s.base, s.base + 4 * s.count);
  const r = ok("GCCOLL", descriptor, count);
  assert.equal(r.hl, s.count - 1 - expected.size);
  const free = m.freeSet();
  for (let i = 1; i < s.count; i++) {
    assert.equal(free.has(i), !expected.has(i), `cell ${i} liveness`);
    if (expected.has(i)) {
      assert.deepEqual(
        m.memory.slice(s.base + 4 * i, s.base + 4 * i + 4),
        before.slice(4 * i, 4 * i + 4),
        `live cell ${i} changed`,
      );
    }
  }
  assert.deepEqual(
    m.memory.slice(s.base, s.base + 4),
    before.slice(0, 4),
    "reserved zero changed",
  );
  const bitmap = m.word(m.address("GCMBASE"));
  assert.ok(
    m.memory.slice(bitmap, bitmap + Math.ceil(s.count / 8)).every((x) =>
      x === 0
    ),
    "marks not reset",
  );
  if (label) {
    measures.push({
      name: label,
      cycles: r.cycles,
      steps: r.steps,
      passes: m.word(m.address("GCPASSES")),
      overflow: m.memory[m.address("GCQOVFL")],
    });
  }
  return r;
}
Deno.test("collector setup rejects uninitialized, active and invalid configurations", () => {
  fail("GCSET", 3, 0x6000, 1);
  fail("GCCOLL", 3, 0, 0);
  init(2);
  const config = m.memory.slice(
    m.address("GCMBASE"),
    m.address("GCCONFIG") + 1,
  );
  fail("GCSET", 2, 0x6000, 0);
  assert.deepEqual(
    m.memory.slice(m.address("GCMBASE"), m.address("GCCONFIG") + 1),
    config,
  );
  fail("GCSET", 2, 0x6000, 2);
  // One-byte bitmap can end at 65536 without wrapping its writes.
  m.bitmapRange(0xffff, 1);
  ok("GCSET", 0xffff, 1);
  roots([1]);
  collected(new Set([1]));
  init(16);
  fail("GCSET", 2, 0xffff, 2);
  // HINIT has discarded all allocations; roots are empty.
  ok("HINIT", 0x8000, 16);
  ok("HRES", 0, 1);
  fail("GCCOLL", 3, 0, 0);
  fail("GCSET", 3, 0x6000, 2);
  fail("GRES", 3, 0, 1, 0);
  ok("HPOP");
  fail("GCCOLL", 3, 0, 0);
  ok("HDONE");
  m.heapRange(0x8100, 16);
  ok("HINIT", 0x8100, 16);
  fail("GCCOLL", 3, 0, 0);
  ok("GCSET", 0x6000, 2);
});
Deno.test("empty roots reclaim everything; all-live heap preserves every cell", () => {
  init(8192);
  m.memory[0x8000] = 0xa5;
  collected(new Set(), 0xffff, 0, "full heap, no roots");
  assert.equal(m.state().free, 8191);
  ok("HRES", 0, 8191);
  for (let i = 1; i < 8192; i++) ok("HPOP");
  ok("HDONE");
  for (let i = 1; i < 8192; i++) m.cell(i, 0x4000 | i, i === 1 ? 0 : i - 1);
  roots([8191]);
  collected(
    new Set(Array.from({ length: 8191 }, (_, i) => i + 1)),
    0x3000,
    1,
    "full reverse chain, worklist",
  );
  assert.equal(m.memory[m.address("GCQOVFL")], 0);
  assert.equal(m.state().free, 0);
});
Deno.test("strided stack/global/constant/fixed roots trace only heap-backed references", () => {
  init(32);
  m.cell(1, 0x6002, 0x2000); // ENV parent is sole path to cell2.
  m.cell(2, 0xfe02, 3);
  m.cell(3, 5, 0x6000); // Integer5 is not an edge.
  m.cell(4, 0xffff, 0x4006);
  m.cell(6, 0xfe02, 0); // Closure raw word ignored.
  for (
    const [p, value] of [
      [0x4000, [1, 0x6001]],
      [0x4102, [1, 0x4004]],
      [0x4108, [3, 7]],
      [0x4200, [1, 8]],
      [0x4300, [1, 9]],
      [0x4304, [1, 0x200a]],
      [0x4308, [1, 0x800b]],
      [0x430c, [0, 12]],
    ] as const
  ) m.slot(p, value);
  m.descriptor(0x3000, 0x4000, 1);
  m.descriptor(0x3006, 0x4102, 2, 6);
  m.descriptor(0x300c, 0x4200, 1);
  m.descriptor(0x3012, 0x4300, 4);
  collected(new Set([1, 2, 3, 4, 6, 8, 9]), 0x3000, 4);
});
Deno.test("escaped CDR, CAR and environment-parent sole edges survive alongside cycles", () => {
  for (const subtype of [0, 2, 3]) {
    init(16);
    m.cell(1, 0x3c00, 0xe002);
    m.cell(2, (subtype << 13) | 3, 0xc001);
    m.cell(3, 0xfe02, subtype === 2 ? 0x4004 : 4);
    m.cell(4, 3, 0x2000);
    roots([1]);
    collected(new Set([1, 2, 3, 4]));
  }
  init(16);
  m.cell(1, 0x4003, 0xe002);
  m.cell(2, 0x6004, 0xc009);
  m.cell(3, 0xffff, 0x4004);
  m.cell(4, 0x6005, 0x2006);
  m.cell(5, 0xfe02, 0);
  m.cell(6, 1, 0x2000);
  roots([1]);
  collected(new Set([1, 2, 3, 4, 5, 6]));
  // The same graph after sweep must remain valid through another collection.
  collected(new Set([1, 2, 3, 4, 5, 6]));
});
Deno.test("integer and permanent-reference payloads never become false heap edges", () => {
  for (const tag of [0, 3]) {
    init(16);
    m.cell(1, 3, 0xe002);
    m.cell(2, 4, 0xc000 | (tag << 3) | tag);
    roots([1]);
    collected(new Set([1, 2]));
  }
  init(16);
  m.cell(1, 0x2003, 0x2002);
  m.cell(2, 0x8004, 0x2000);
  roots([1]);
  collected(new Set([1, 2]));
});
Deno.test("root overflow recovers dropped backward edges through repeated scans", () => {
  init(512);
  for (let i = 1; i <= 128; i++) m.cell(i, 0, i - 1);
  roots([...Array.from({ length: 128 }, (_, i) => 200 + i), 128]);
  collected(
    new Set([
      ...Array.from({ length: 128 }, (_, i) => 200 + i),
      ...Array.from({ length: 128 }, (_, i) => i + 1),
    ]),
    0x3000,
    1,
    "overflow: 128-node dropped reverse chain",
  );
  assert.equal(m.memory[m.address("GCQOVFL")], 1);
  assert.ok(m.word(m.address("GCPASSES")) > 1);
});
Deno.test("edge-generated queue overflow retains all descendants on a full heap", () => {
  init(8192);
  const live = new Set<number>();
  for (let i = 1; i <= 200; i++) {
    live.add(i);
    live.add(300 + i);
    // Links enqueue leaves first, then CAR enqueues the next spine node.
    // LIFO processing follows the spine while pending leaves accumulate.
    m.cell(i, i < 200 ? i + 1 : 0, (i < 200 ? 0x2000 : 0) | (300 + i));
  }
  roots([1]);
  collected(live, 0x3000, 1, "full heap, comb overflow");
  assert.equal(m.memory[m.address("GCQOVFL")], 1);
});
Deno.test("root descriptor and slot endpoints use checked wider arithmetic", () => {
  init(16);
  m.slot(0xfffc, [1, 1]);
  m.descriptor(0x3000, 0xfffc, 1);
  collected(new Set([1]));
  init(16);
  m.slot(0x4000, [1, 1]);
  m.descriptor(0xfffa, 0x4000, 1);
  collected(new Set([1]), 0xfffa, 1);
  init(16);
  m.descriptor(0x3000, 0xffff, 0, 0);
  collected(new Set());
  init(16);
  fail("GCCOLL", 2, 0xfffb, 1);
  fail("GCCOLL", 2, 0, 0xffff);
  for (
    const [start, count, stride] of [
      [0xfffd, 1, 4],
      [0x4000, 2, 3],
      [0x4000, 65535, 65535],
      [0xfff8, 3, 4],
      [0x4000, 32768, 4],
    ]
  ) {
    m.descriptor(0x3000, start, count, stride);
    fail("GCCOLL", 2, 0x3000, 1);
  }
});
Deno.test("malformed reachable objects fail before sweep and valid retry clears stale marks", () => {
  for (
    const value of [[1, 0], [1, 16], [1, 0xa001], [1, 0x6000], [2, 0], [
      4,
      0,
    ]] as const
  ) {
    init(16);
    m.slot(0x4000, value);
    m.descriptor(0x3000, 0x4000, 1);
    fail("GCCOLL", 4, 0x3000, 1);
  }
  for (const words of [[0, 0x8000], [0, 0xa000], [0, 0xe000], [0, 0xe010]]) {
    init(16);
    m.cell(1, words[0], words[1]);
    roots([1]);
    fail("GCCOLL", 4, 0x3000, 1);
  }
  for (const metadata of [0, 0xc040, 0xc002, 0xc010, 0xc004, 0xc020]) {
    init(16);
    m.cell(1, 0, 0xe002);
    m.cell(2, 0, metadata);
    roots([1]);
    fail("GCCOLL", 4, 0x3000, 1);
  }
  init(16);
  m.cell(1, 0, 2);
  m.cell(2, 0, 0x8000);
  roots([1]);
  fail("GCCOLL", 4, 0x3000, 1);
  m.cell(2, 0, 0);
  collected(new Set([1, 2]));
});
Deno.test("allocation retry preserves rooted arguments and collects only on capacity failure", () => {
  init(16);
  m.cell(1, 0xfe02, 0);
  m.slot(0x4000, [1, 1]);
  m.descriptor(0x3000, 0x4000, 1);
  ok("GRES", 0x3000, 2, 1);
  assert.equal(m.state().active, 1);
  assert.equal(m.state().left, 2);
  assert.ok(!m.freeSet().has(1));
  const first = ok("HPOP"), second = ok("HPOP");
  assert.notEqual(first.hl, 1);
  assert.notEqual(second.hl, 1);
  // Publish an escaped pair only after both cells have valid contents.
  m.cell(first.hl, 30000, 0xe000 | second.hl);
  m.cell(second.hl, 1, 0xc019);
  m.slot(0x4004, [1, first.hl]);
  m.descriptor(0x3000, 0x4000, 2);
  fail("GCCOLL", 3, 0x3000, 1);
  ok("HDONE");
  collected(new Set([1, first.hl, second.hl]));
  // A request that cannot ever fit must not run GC or change reachable state.
  fail("GRES", 2, 0x3000, 16, 1);
  init(16);
  roots(Array.from({ length: 15 }, (_, i) => i + 1));
  const r = m.call("GRES", 0x3000, 1, 1);
  assert.equal(r.status, 1);
  assert.equal(r.carry, 1);
  assert.equal(m.state().active, 0);
  assert.equal(m.state().free, 0);
  // Enough capacity takes the noncollecting path despite unused bad descriptors.
  ok("HINIT", 0x8000, 16);
  ok("GRES", 0xffff, 1, 0xffff);
  assert.equal(m.state().left, 1);
  ok("HPOP");
  ok("HDONE");
});
Deno.test("deterministic encoded graphs match independent logical adjacency sets", () => {
  let seed = 0x6c;
  const next = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 16;
  };
  for (let trial = 0; trial < 20; trial++) {
    init(257);
    const edges = new Map<number, number[]>();
    for (let i = 1; i < 257; i++) {
      const left = next() % 256 + 1, right = next() % 257, kind = next() % 4;
      const children = [
        ...(right ? [right] : []),
        ...(kind === 1 && left ? [left] : []),
      ];
      edges.set(i, children);
      m.cell(i, kind === 1 ? left : 0x6000 | left, (kind << 13) | right);
    }
    const initial = [next() % 256 + 1, next() % 256 + 1],
      expected = new Set<number>(),
      pending = [...initial];
    while (pending.length) {
      const i = pending.pop()!;
      if (expected.has(i)) continue;
      expected.add(i);
      pending.push(...edges.get(i)!);
    }
    roots(initial);
    collected(expected);
  }
});
Deno.test("failed post-collection reservation reclaims garbage without popping live cells", () => {
  init(16);
  for (let i = 1; i <= 13; i++) m.cell(i, 0, i < 13 ? i + 1 : 0);
  roots([1]);
  const before = m.memory.slice(0x8004, 0x8000 + 14 * 4);
  const r = m.call("GRES", 0x3000, 3, 1);
  assert.equal(r.status, 1);
  assert.equal(r.carry, 1);
  assert.equal(m.state().active, 0);
  assert.equal(m.state().left, 0);
  assert.equal(m.state().free, 2);
  assert.deepEqual(m.freeSet(), new Set([14, 15]));
  assert.deepEqual(m.memory.slice(0x8004, 0x8000 + 14 * 4), before);
  assert.equal(m.stats.get("GRES")!.stackBytes, 8);
});
Deno.test("nonzero root padding fails before sweep", () => {
  init(16);
  roots([1]);
  m.memory[0x4003] = 1;
  fail("GCCOLL", 4, 0x3000, 1);
  m.memory[0x4003] = 0;
  collected(new Set([1]));
});
Deno.test("collector storage and full-heap pause measurements", () => {
  console.log(
    JSON.stringify(
      {
        code: m.address("GCCODEND") - m.address("GCSET"),
        workspace: m.address("GCWEND") - m.address("GCWORK"),
        operations: Object.fromEntries(m.stats),
        pauses: measures,
      },
      null,
      2,
    ),
  );
});

Deno.test("complete runtime computes an integer, reclaims space and preserves its rooted pair", async () => {
  const all = await collectorMachine("tests/runtime.asm");
  all.heapRange(0x8000, 32);
  all.bitmapRange(0x6000, 4);
  assert.equal(all.call("HINIT", 0x8000, 32).status, 0);
  assert.equal(all.call("GCSET", 0x6000, 4).status, 0);
  assert.equal(all.call("HRES", 0, 31).status, 0);
  for (let i = 1; i < 32; i++) assert.equal(all.call("HPOP").status, 0);
  assert.equal(all.call("HDONE").status, 0);
  const number = all.call("NADD", 30000, 3 << 8, 1, 20000, 3);
  assert.equal(number.status, 3);
  assert.equal(number.carry, 0);
  assert.equal(number.hl, 30001);
  all.cell(1, number.hl, 0x6000);
  all.slot(0x4000, [1, 1]);
  all.descriptor(0x3000, 0x4000, 1);
  const reserve = all.call("GRES", 0x3000, 2, 1);
  assert.equal(reserve.status, 0);
  assert.equal(reserve.carry, 0);
  assert.equal(all.state().active, 1);
  assert.equal(all.word(0x8004), 30001);
  assert.ok(!all.freeSet().has(1));
  for (let i = 0; i < 2; i++) assert.equal(all.call("HPOP").status, 0);
  assert.equal(all.call("HDONE").status, 0);
  console.log(
    `Complete runtime resident bytes: ${
      all.address("GCWEND") - all.address("F16CLASS")
    }, plus bitmap and heap`,
  );
});
