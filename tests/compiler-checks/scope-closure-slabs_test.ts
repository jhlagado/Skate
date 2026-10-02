import assert from "node:assert/strict";
import { managedRuntime, writeWord } from "./scope-runtime-fixture.ts";

Deno.test("a stale released base cannot shadow a live closure page", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const owner = assembled.address("SRTCLOWN");
  const base = assembled.address("SRTCLPBA");
  // Entry zero once owned page 80H and was released; entry one owns it now.
  memory[owner] = 0;
  memory[base] = 0x80;
  memory[owner + 1] = 1;
  memory[base + 1] = 0x80;
  // An FFH continuation entry is never a lookup target either.
  memory[owner + 2] = 0xff;
  memory[base + 2] = 0x81;

  writeWord(memory, assembled.address("SRTCLBAS"), 0x8010);
  assert.equal(call("SRTCLFND").carry, 0);
  assert.equal(memory[assembled.address("SRTCLPGI")], 1);

  writeWord(memory, assembled.address("SRTCLBAS"), 0x8110);
  assert.equal(call("SRTCLFND").carry, 1);
  assert.equal(memory[assembled.address("SRTCLPGI")], 0x80);
});

Deno.test("a closure-page miss changes no usage or base entry", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const use = assembled.address("SRTCLUSE");
  const base = assembled.address("SRTCLPBA");
  const before = [...memory.slice(use, use + 256)];
  writeWord(memory, assembled.address("SRTCLBAS"), 0x8010);
  assert.equal(call("SRTCLINC").carry, 1);
  assert.deepEqual([...memory.slice(use, use + 256)], before);
  assert.equal(memory[base], 0);
});

Deno.test("released closure pages clear their physical base entries", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const owner = assembled.address("SRTCLOWN");
  const base = assembled.address("SRTCLPBA");
  const index = assembled.address("SRTCLPGI");

  memory[assembled.address("SRTCLIDX")] = 0;
  const single = call("SRTCLP1");
  assert.equal(single.carry, 0);
  const singleIndex = memory[index];
  assert.equal(memory[base + singleIndex], single.payload >>> 8);
  assert.equal(call("SRTCLPRE").carry, 0);
  assert.equal(memory[owner + singleIndex], 0);
  assert.equal(memory[base + singleIndex], 0);

  // Leave a stale base in the next entry, then release a two-page run there.
  memory[base + 1] = 0x77;
  memory[assembled.address("SRTCLIDX")] = 0x40;
  const run = call("SRTCLPRN");
  assert.equal(run.carry, 0);
  const runIndex = memory[index];
  assert.equal(memory[owner + runIndex], 0x41);
  assert.equal(memory[owner + runIndex + 1], 0xff);
  writeWord(memory, assembled.address("SRTCLPGA"), run.payload);
  assert.equal(call("SRTCLR2").carry, 0);
  assert.equal(memory[owner + runIndex], 0);
  assert.equal(memory[owner + runIndex + 1], 0);
  assert.equal(memory[base + runIndex], 0);
  assert.equal(memory[base + runIndex + 1], 0);
});
