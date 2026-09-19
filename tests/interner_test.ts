import assert from "node:assert/strict";
import { ByteInterner } from "../tools/interner.ts";
import { internerMachine } from "./interner-machine.ts";
const ascii = (s: string) => new TextEncoder().encode(s);

Deno.test("native interner matches packed host identities and atomic capacity errors", async () => {
  const m = await internerMachine();
  for (const kind of [0, 1]) {
    m.configure(0x2000, kind, 4, 40);
    assert.equal(m.call("IINIT").carry, 0);
    const host = new ByteInterner({
      kind: kind ? "string" : "symbol",
      maxEntries: 4,
      maxBytes: 40,
    });
    const values = kind
      ? [new Uint8Array(), Uint8Array.of(255, 0), ascii("hi"), ascii("Hi")]
      : [ascii("hi"), ascii("Hi"), ascii("long"), ascii("x")];
    for (const bytes of [...values, ...values]) {
      m.memory.set(bytes, 0x6000);
      const result = m.call("INTERN", 0x2000, 0x6000, bytes.length);
      assert.equal(result.carry, 0);
      assert.equal(result.status, 0);
      assert.equal(result.id, host.intern(bytes));
      const actual = m.snapshot();
      assert.deepEqual(
        { descriptors: actual.descriptors, pool: actual.pool },
        host.snapshot(),
      );
    }
    const before = m.snapshot();
    m.memory.set(ascii("new"), 0x6000);
    const error = m.call("INTERN", 0x2000, 0x6000, 3);
    assert.equal(error.status, 1);
    assert.equal(error.carry, 1);
    assert.deepEqual(m.snapshot(), before);
  }
});

Deno.test("native interner validates lengths, ASCII and source extents before mutation", async () => {
  const m = await internerMachine();
  m.configure(0x2000, 0, 10, 31);
  m.call("IINIT");
  m.memory.fill(65, 0x6000, 0x6020);
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 31).status, 0);
  const before = m.snapshot();
  for (const length of [0, 32, 256, 65535]) {
    assert.equal(m.call("INTERN", 0x2000, 0x6000, length).status, 2);
    assert.deepEqual(m.snapshot(), before);
  }
  m.memory[0x6000] = 128;
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 1).status, 2);
  m.memory[0x6000] = 66;
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 1).status, 1);
  assert.equal(m.call("INTERN", 0x2000, 0xffff, 2).status, 2);
  assert.deepEqual(m.snapshot(), before);
  m.configure(0x2000, 1, 3, 256);
  m.call("IINIT");
  m.memory.fill(255, 0x6000, 0x60ff);
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 255).id, 0);
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 256).status, 2);
  m.memory[0xffff] = 42;
  assert.equal(m.call("INTERN", 0x2000, 0xffff, 1).id, 1);
});

Deno.test("native init validates configuration boundaries and preserves failures", async () => {
  const m = await internerMachine();
  for (
    const [kind, entries, bytes, table, pool] of [
      [0, 8193, 1, 0x3000, 0x4000],
      [2, 1, 1, 0x3000, 0x4000],
      [0, 1, 1, 0xfffe, 0x4000],
      [1, 1, 1, 0xfffd, 0x4000],
      [0, 1, 2, 0x3000, 0xffff],
    ]
  ) {
    m.configure(0x2000, kind, entries, bytes, table, pool);
    const before = m.memory.slice(0x2000, 0x200e);
    assert.equal(m.call("IINIT").status, 2);
    assert.deepEqual(m.memory.slice(0x2000, 0x200e), before);
  }
  assert.equal(m.call("IINIT", 0xfff3).status, 2);
  m.configure(0x2000, 0, 1, 1, 0xfffd, 0x4000);
  assert.equal(m.call("IINIT").status, 0);
  m.configure(0x2000, 1, 1, 1, 0x3000, 0xffff);
  assert.equal(m.call("IINIT").status, 0);
  m.memory[0x6000] = 99;
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 1).status, 0);
  assert.equal(m.memory[0xffff], 99);
  m.configure(0x2000, 0, 0, 0);
  m.call("IINIT");
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 1).status, 1);
  m.memory[0x200d] = 0;
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 1).status, 3);
});

Deno.test("native contexts remain independent and string offsets cross byte boundaries", async () => {
  const m = await internerMachine();
  m.configure(0x2000, 1, 3, 512);
  m.configure(0x2100, 0, 2, 8, 0x3200, 0x4400);
  m.call("IINIT", 0x2000);
  m.call("IINIT", 0x2100);
  m.memory.fill(255, 0x6000, 0x60ff);
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 255).id, 0);
  m.memory[0x6000] = 1;
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 1).id, 1);
  m.memory.set(ascii("sym"), 0x6000);
  assert.equal(m.call("INTERN", 0x2100, 0x6000, 3).id, 0);
  assert.equal(m.call("INTERN", 0x2000, 0x6000, 3).id, 2);
  assert.deepEqual(
    m.snapshot().descriptors.slice(-4),
    Uint8Array.of(0, 1, 3, 0),
  );
  assert.deepEqual(m.snapshot(0x2100).pool, ascii("sym"));
  console.log(
    `interner code=${m.address("IEND") - m.address("IINIT")} workspace=${
      m.address("IWEND") - m.address("IWORK")
    } context=14`,
  );
});

Deno.test("native final 13-bit identity and first exhausted insertion are distinguished", async () => {
  const m = await internerMachine();
  m.configure(0x1800, 1, 8192, 16384, 0x8000, 0x2000);
  assert.equal(m.call("IINIT", 0x1800).status, 0);
  // Seed a valid table to exercise the last identity without quadratic setup.
  for (let id = 0; id < 8191; id++) {
    m.putWord(0x8000 + 4 * id, 2 * id);
    m.putWord(0x8002 + 4 * id, 2);
    m.putWord(0x2000 + 2 * id, id);
  }
  m.putWord(0x1808, 8191);
  m.putWord(0x180a, 16382);
  m.putWord(0x6100, 8191);
  const last = m.call("INTERN", 0x1800, 0x6100, 2);
  assert.equal(last.status, 0);
  assert.equal(last.id, 8191);
  assert.equal(m.word(0x1808), 8192);
  assert.equal(m.word(0x180a), 16384);
  assert.equal(m.word(0xfffc), 16382);
  assert.equal(m.call("INTERN", 0x1800, 0x6100, 2).id, 8191);
  const before = m.snapshot(0x1800);
  m.putWord(0x6100, 8192);
  const full = m.call("INTERN", 0x1800, 0x6100, 2);
  assert.equal(full.status, 1);
  assert.equal(full.carry, 1);
  assert.deepEqual(m.snapshot(0x1800), before);
  console.log(
    `last identity cycles=${last.cycles} additional stack=${last.stackBytes}`,
  );
});
