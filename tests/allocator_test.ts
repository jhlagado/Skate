import assert from "node:assert/strict";
import { allocatorMachine } from "./allocator-machine.ts";
import {
  type Cell,
  decodePair,
  type Heap,
  NIL,
  REF,
  reference,
  SCALAR,
  UNBOUND,
} from "../tools/representation.ts";
const m = await allocatorMachine();
function success(name: string, hl = 0, bc = 0) {
  const r = m.call(name, hl, bc);
  assert.equal(r.status, 0, `${name} status`);
  assert.equal(r.carry, 0, `${name} carry`);
  return r;
}
function init(base: number, cells: number) {
  m.arena(base, cells);
  success("HINIT", base, cells);
}
function failure(name: string, status: number, hl = 0, bc = 0) {
  const before = m.memory.slice();
  const r = m.call(name, hl, bc);
  assert.equal(r.status, status, `${name} status`);
  assert.equal(r.carry, 1, `${name} carry`);
  assert.deepEqual(
    m.memory.slice(m.workStart, m.workEnd),
    before.slice(m.workStart, m.workEnd),
    `${name} state atomicity`,
  );
  const heap = m.state();
  if (heap.ready) {
    assert.deepEqual(
      m.memory.slice(heap.base, heap.base + 4 * heap.cells),
      before.slice(heap.base, heap.base + 4 * heap.cells),
      `${name} heap atomicity`,
    );
  }
  assert.ok(
    r.writes.every((p) => p >= 0x6fc0 && p < 0x7000),
    `${name} wrote state before failure`,
  );
}
function freeList() {
  const s = m.state(), seen = new Set<number>();
  let i = s.head;
  while (i) {
    assert.ok(
      i > 0 && i < s.cells && !seen.has(i),
      `invalid/repeated free index ${i}`,
    );
    seen.add(i);
    assert.equal(m.word(s.base + 4 * i + 2), 0);
    i = m.word(s.base + 4 * i);
  }
  assert.equal(seen.size, s.free);
  return seen;
}
Deno.test("allocator rejects calls before initialization without modifying state", () => {
  failure("HRES", 3, 0, 1);
  failure("HPOP", 3);
  failure("HDONE", 3);
});
Deno.test("arena bounds and initialization failures are atomic", () => {
  for (
    const [base, cells] of [
      [0, 2],
      [0x8000, 2],
      [0x8001, 255],
      [0x8000, 256],
      [0x8004, 8191],
      [0x8000, 8192],
      [0xfff8, 2],
      [0xfff7, 2],
    ]
  ) {
    m.arena(base, cells);
    m.memory.fill(0xa5, base, Math.min(65536, base + 4 * cells));
    const zero = m.memory.slice(base, base + 4);
    success("HINIT", base, cells);
    assert.deepEqual(m.memory.slice(base, base + 4), zero);
    assert.deepEqual(m.state(), {
      base,
      cells,
      head: 1,
      free: cells - 1,
      left: 0,
      active: 0,
      ready: 1,
    });
    freeList();
  }
  for (
    const [base, cells] of [
      [0x8000, 0],
      [0x8000, 1],
      [0, 8193],
      [0, 32767],
      [0, 32768],
      [0, 65534],
      [0, 65535],
      [0x8005, 8191],
      [0x8001, 8192],
      [0xfff9, 2],
      [0xffff, 2],
    ]
  ) failure("HINIT", 2, base, cells);
  // A recoverable failed initialization must leave the old allocator usable.
  success("HRES", 0, 1);
  success("HPOP");
  success("HDONE");
});
Deno.test("all 8191 usable cells allocate exactly once, including final address FFFC", () => {
  init(0x8000, 8192);
  const seen = new Set<number>();
  for (let i = 1; i < 8192; i++) {
    const before = m.state();
    success("HRES", 0, 1);
    assert.equal(m.state().head, before.head);
    assert.equal(m.state().free, before.free);
    const r = success("HPOP");
    assert.equal(r.hl, i);
    assert.equal(r.de, 0x8000 + 4 * i);
    assert.ok(!seen.has(r.hl));
    seen.add(r.hl);
    assert.deepEqual(m.memory.slice(r.de, r.de + 4), new Uint8Array(4));
    assert.equal(m.state().active, 1);
    assert.equal(m.state().left, 0);
    success("HDONE");
  }
  assert.equal(seen.size, 8191);
  assert.equal(m.state().head, 0);
  assert.equal(m.state().free, 0);
  failure("HRES", 1, 0, 1);
  failure("HRES", 2, 0, 8192);
  freeList();
});
Deno.test("one/two/frame reservations have exact capacity and protocol boundaries", () => {
  for (const k of [0, 1, 2, 3, 255, 256, 1024, 8191]) {
    init(0x8000, 8192);
    success("HRES", 0, k);
    failure("HRES", 3, 0, 1);
    failure("HINIT", 3, 0x8000, 8192);
    if (k) failure("HDONE", 3);
    for (let j = 0; j < k; j++) success("HPOP");
    failure("HPOP", 3);
    failure("HRES", 3, 0, 0);
    failure("HINIT", 3, 0x8000, 8192);
    assert.equal(m.state().active, 1);
    success("HDONE");
    failure("HDONE", 3);
    assert.equal(m.state().free, 8191 - k);
    freeList();
  }
  for (const k of [1, 2, 3, 255, 256, 1024]) {
    init(0x8000, k + 1);
    failure("HRES", 2, 0, k + 1);
    success("HRES", 0, 1);
    success("HPOP");
    success("HDONE");
    failure("HRES", 1, 0, k); // Capacity valid but one cell short.
    success("HRES", 0, k - 1);
    for (let i = 0; i < k - 1; i++) success("HPOP");
    success("HDONE");
  }
});
function putWord(address: number, word: number) {
  m.memory[address] = word & 255;
  m.memory[address + 1] = word >>> 8;
}
function cell(index: number, words: Cell) {
  const p = m.state().base + 4 * index;
  putWord(p, words[0]);
  putWord(p + 2, words[1]);
}
function heap(): Heap {
  const s = m.state();
  return Array.from(
    { length: s.cells },
    (_, i) => [m.word(s.base + 4 * i), m.word(s.base + 4 * i + 2)] as Cell,
  );
}
Deno.test("fragmented free list supports complete ordinary, escaped and frame objects", () => {
  init(0x9001, 16);
  const order = [9, 2, 14, 1, 12, 4, 7, 3, 11, 5, 15, 8, 6, 13, 10];
  for (let i = 0; i < order.length; i++) cell(order[i], [order[i + 1] ?? 0, 0]);
  putWord(m.address("HHEAD"), order[0]);
  freeList();
  // Inputs here are fixed host fixtures; M3 will prove live runtime input roots.
  success("HRES", 0, 1);
  const pair = success("HPOP").hl;
  cell(pair, [0x3c00, 0]);
  success("HDONE");
  assert.deepEqual(decodePair(heap(), pair), [[SCALAR, 0x3c00], [SCALAR, NIL]]);
  success("HRES", 0, 2);
  const anchor = success("HPOP").hl;
  const aux = success("HPOP").hl;
  cell(aux, [pair, 0xc001]);
  cell(anchor, [0x4000, 0xe000 | aux]);
  assert.equal(m.state().active, 1);
  success("HDONE");
  assert.deepEqual(decodePair(heap(), anchor), [
    [SCALAR, 0x4000],
    reference(0, pair),
  ]);
  success("HRES", 0, 4);
  const frame = Array.from({ length: 4 }, () => success("HPOP").hl);
  cell(frame[0], [NIL, frame[1]]);
  cell(frame[1], [anchor, 0x2000 | frame[2]]);
  cell(frame[2], [UNBOUND, frame[3]]);
  cell(frame[3], [0x4200, 0]);
  assert.equal(m.state().active, 1);
  success("HDONE");
  assert.deepEqual(decodePair(heap(), frame[1])[0], [REF, anchor]);
  assert.equal(m.word(m.state().base + 4 * frame[2]), UNBOUND);
  assert.deepEqual([...freeList()], order.slice(7));
});
Deno.test("deterministic reserve/pop/publish sequences match an independent ownership model", () => {
  init(0x8103, 257);
  let seed = 17;
  const available = new Set(Array.from({ length: 256 }, (_, i) => i + 1));
  let remaining: number | null = null;
  const next = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed;
  };
  for (let step = 0; step < 3000; step++) {
    const op = next() % 3;
    if (op === 0) {
      const k = (next() >>> 16) % 260;
      if (remaining !== null) failure("HRES", 3, 0, k);
      else if (k > 256) failure("HRES", 2, 0, k);
      else if (k > available.size) failure("HRES", 1, 0, k);
      else {
        success("HRES", 0, k);
        remaining = k;
      }
    } else if (op === 1) {
      if (remaining === null || remaining === 0) failure("HPOP", 3);
      else {
        const r = success("HPOP");
        assert.ok(available.delete(r.hl));
        remaining--;
      }
    } else if (remaining !== 0) failure("HDONE", 3);
    else {
      success("HDONE");
      remaining = null;
    }
    assert.equal(m.state().free, available.size);
    assert.equal(m.state().active, remaining === null ? 0 : 1);
    assert.equal(m.state().left, remaining ?? 0);
  }
  if (remaining !== null) {
    while (remaining-- > 0) success("HPOP");
    success("HDONE");
  }
  freeList();
});
Deno.test("allocator module census and execution costs", () => {
  console.log(
    JSON.stringify(
      {
        code: m.address("HEND") - m.address("HINIT"),
        workspace: m.workEnd - m.workStart,
        operations: Object.fromEntries(m.stats),
      },
      null,
      2,
    ),
  );
});

Deno.test("combined numeric and allocator runtime preserves an active construction", async () => {
  const combined = await allocatorMachine("tests/runtime.asm");
  combined.arena(0x8000, 8192);
  assert.equal(combined.call("HINIT", 0x8000, 8192).status, 0);
  assert.equal(combined.call("HRES", 0, 1).status, 0);
  const before = combined.state();
  const number = combined.call("NADD", 30000, 3 << 8, 3, 1);
  assert.equal(number.status, 3);
  assert.equal(number.carry, 0);
  assert.equal(number.hl, 30001);
  assert.deepEqual(combined.state(), before);
  const cell = combined.call("HPOP");
  assert.equal(cell.status, 0);
  assert.equal(cell.hl, 1);
  combined.memory[cell.de] = number.hl & 255;
  combined.memory[cell.de + 1] = number.hl >>> 8;
  combined.memory[cell.de + 3] = 0x60;
  assert.equal(combined.call("HDONE").status, 0);
  assert.equal(combined.word(cell.de), 30001);
  assert.equal(combined.word(cell.de + 2), 0x6000);
  console.log(
    `Combined runtime: ${
      combined.address("HWEND") - combined.address("F16CLASS")
    } bytes (including all workspaces)`,
  );
});
