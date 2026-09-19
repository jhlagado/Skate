import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

async function sourceMachine(
  records: Uint8Array[],
  failure = 1,
  open = 0,
  close = 0,
) {
  const { runtime, address } = await loadAssembly("tests/cpm-source.asm");
  const cpu = runtime.cpu, mem = runtime.hardware.memory;
  let dma = 0, reads = 0;
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    assert.ok(
      (p >= address("CSWORK") && p < address("CSWEND")) ||
        (p >= 0xef00 && p < 0xf000),
      `Unexpected source-adapter write at ${p.toString(16)}`,
    );
    mem[p] = v;
  };
  mem[5] = 0xc9;
  function call(name: string) {
    cpu.pc = address(name);
    cpu.sp = 0xf000;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.h = 0x80;
    cpu.l = 0;
    mem[0xf000] = 0;
    mem[0xf001] = 0xff;
    let steps = 0;
    while (cpu.pc !== 0xff00) {
      assert.ok(++steps < 10000);
      if (cpu.pc === 5) {
        switch (cpu.c) {
          case 15:
            cpu.a = open;
            break;
          case 16:
            cpu.a = close;
            break;
          case 26:
            dma = cpu.d * 256 + cpu.e;
            cpu.a = 0;
            break;
          case 20: {
            const record = records[reads++];
            if (record) mem.set(record, dma);
            cpu.a = record ? 0 : failure;
            break;
          }
          default:
            throw new Error(`Unexpected BDOS ${cpu.c}`);
        }
        cpu.ix = 0;
        cpu.iy = 0;
        cpu.b =
          cpu.c =
          cpu.d =
          cpu.e =
          cpu.h =
          cpu.l =
            0xaa;
      }
      runtime.step();
    }
    assert.equal(cpu.sp, 0xf002);
    assert.equal(cpu.ix, 0x1357);
    assert.equal(cpu.iy, 0x2468);
    return { carry: cpu.flags.C, value: cpu.a };
  }
  mem.set(new TextEncoder().encode("\0INPUT   SK8"), 0x8000);
  return { call, mem, address, reads: () => reads };
}

async function packageMachine(
  files: Map<string, Uint8Array[]>,
  open = 0,
  close = 0,
) {
  const { runtime, address } = await loadAssembly("tests/cpm-source.asm");
  const cpu = runtime.cpu, mem = runtime.hardware.memory;
  let dma = 0;
  const offsets = new Map<string, number>();
  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (p: number, v: number) => void;
  }).memWrite = (p, v) => {
    assert.ok(
      (p >= address("CSWORK") && p < address("CSWEND")) ||
        (p >= 0xef00 && p < 0xf000),
      `Unexpected source-adapter write at ${p.toString(16)}`,
    );
    mem[p] = v;
  };
  mem[5] = 0xc9;
  function fcbName(pointer: number) {
    const name = String.fromCharCode(...mem.slice(pointer + 1, pointer + 9))
      .trimEnd();
    const ext = String.fromCharCode(...mem.slice(pointer + 9, pointer + 12))
      .trimEnd();
    return ext ? `${name}.${ext}` : name;
  }
  function call(name: string) {
    cpu.pc = address(name);
    cpu.sp = 0xf000;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.h = 0x80;
    cpu.l = 0;
    mem[0xf000] = 0;
    mem[0xf001] = 0xff;
    let steps = 0;
    while (cpu.pc !== 0xff00) {
      assert.ok(++steps < 100000);
      if (cpu.pc === 5) {
        const pointer = cpu.d * 256 + cpu.e;
        switch (cpu.c) {
          case 15: {
            const key = fcbName(pointer);
            if (!files.has(key)) cpu.a = 255;
            else {
              offsets.set(key, 0);
              cpu.a = open;
            }
            break;
          }
          case 16:
            cpu.a = close;
            break;
          case 26:
            dma = pointer;
            cpu.a = 0;
            break;
          case 20: {
            const key = fcbName(pointer);
            const records = files.get(key);
            const index = offsets.get(key) ?? 0;
            const record = records?.[index];
            if (record) {
              mem.set(record, dma);
              offsets.set(key, index + 1);
              cpu.a = 0;
            } else cpu.a = 1;
            break;
          }
          default:
            throw new Error(`Unexpected BDOS ${cpu.c}`);
        }
        cpu.ix = 0;
        cpu.iy = 0;
        cpu.b =
          cpu.c =
          cpu.d =
          cpu.e =
          cpu.h =
          cpu.l =
            0xaa;
      }
      runtime.step();
    }
    assert.equal(cpu.sp, 0xf002);
    assert.equal(cpu.ix, 0x1357);
    assert.equal(cpu.iy, 0x2468);
    return { carry: cpu.flags.C, value: cpu.a };
  }
  return { call, mem, address };
}

function record(text: string) {
  const bytes = new Uint8Array(128).fill(26);
  bytes.set(new TextEncoder().encode(text));
  return bytes;
}

function records(text: string) {
  const bytes = new TextEncoder().encode(text);
  return Array.from(
    { length: Math.max(1, Math.ceil(bytes.length / 128)) },
    (_, index) => {
      const chunk = new Uint8Array(128).fill(26);
      chunk.set(bytes.slice(index * 128, (index + 1) * 128));
      return chunk;
    },
  );
}

Deno.test("CP/M source crosses records and preserves callback registers", async () => {
  const records = Array.from(
    { length: 130 },
    (_, i) => new Uint8Array(128).fill(32 + i % 90),
  );
  const m = await sourceMachine(records);
  assert.equal(m.call("CSOPEN").carry, 0);
  assert.deepEqual([
    ...m.mem.slice(m.address("CSFCB") + 12, m.address("CSFCB") + 36),
  ], new Array(24).fill(0));
  for (const record of records) {
    for (const value of record) {
      assert.deepEqual(m.call("CSBYTE"), { carry: 0, value });
    }
  }
  assert.equal(m.call("CSBYTE").carry, 1);
  const reads = m.reads();
  assert.equal(m.call("CSBYTE").carry, 1);
  assert.equal(m.reads(), reads);
  assert.deepEqual(m.call("CSCLOSE"), { carry: 0, value: 0 });
});

Deno.test("CP/M source distinguishes padding, empty input and disk failures", async () => {
  for (
    const [records, failure, open, close, expected] of [
      [[new Uint8Array(128).fill(26)], 2, 0, 0, 0],
      [[], 1, 0, 0, 0],
      [[], 2, 0, 0, 2],
      [[], 1, 255, 0, 1],
      [[], 1, 0, 255, 3],
      [[], 2, 0, 255, 2],
    ] as const
  ) {
    const m = await sourceMachine([...records], failure, open, close);
    m.call("CSOPEN");
    assert.equal(m.call("CSBYTE").carry, 1);
    assert.deepEqual(m.call("CSCLOSE"), {
      carry: expected ? 1 : 0,
      value: expected,
    });
    assert.deepEqual(m.call("CSCLOSE"), {
      carry: expected ? 1 : 0,
      value: expected,
    });
  }
});

Deno.test("CP/M source streams an ordered SKM package", async () => {
  const files = new Map([
    ["SOURCE.SKM", [record("ONE.SK8\r\nTWO.SK8\r\n\x1a")]],
    ["ONE.SK8", [record("one")]],
    ["TWO.SK8", [record("two")]],
  ]);
  const m = await packageMachine(files);
  m.mem.set(new TextEncoder().encode("\0SOURCE  SKM"), 0x8000);
  assert.deepEqual(m.call("CSOPEN"), { carry: 0, value: 1 });
  const bytes: number[] = [];
  for (;;) {
    const result = m.call("CSBYTE");
    if (result.carry) break;
    bytes.push(result.value);
  }
  assert.deepEqual(bytes, [...new TextEncoder().encode("one\ntwo")]);
  assert.deepEqual(m.call("CSCLOSE"), { carry: 0, value: 0 });
  assert.deepEqual(m.call("CSCLOSE"), { carry: 0, value: 0 });
});

Deno.test("CP/M source rejects duplicate or missing SKM parts", async () => {
  for (
    const [manifest, expected] of [
      ["ONE.SK8\nONE.SK8\n\x1a", 5],
      ["MISSING.SK8\n\x1a", 5],
      ["BAD+NAME.SK8\n\x1a", 5],
    ] as const
  ) {
    const files = new Map<string, Uint8Array[]>([
      ["SOURCE.SKM", [record(manifest)]],
      ["ONE.SK8", [record("one")]],
    ]);
    const m = await packageMachine(files);
    m.mem.set(new TextEncoder().encode("\0SOURCE  SKM"), 0x8000);
    assert.deepEqual(m.call("CSOPEN"), { carry: 0, value: 1 });
    for (;;) {
      if (m.call("CSBYTE").carry) break;
    }
    assert.deepEqual(m.call("CSCLOSE"), { carry: 1, value: expected });
  }
});

Deno.test("CP/M source bounds the SKM manifest stream", async () => {
  const files = new Map<string, Uint8Array[]>([
    ["SOURCE.SKM", records(`${" ".repeat(2048)}ONE.SK8\n\x1a`)],
  ]);
  const m = await packageMachine(files);
  m.mem.set(new TextEncoder().encode("\0SOURCE  SKM"), 0x8000);
  assert.deepEqual(m.call("CSOPEN"), { carry: 0, value: 1 });
  for (;;) {
    if (m.call("CSBYTE").carry) break;
  }
  assert.deepEqual(m.call("CSCLOSE"), { carry: 1, value: 6 });
});
