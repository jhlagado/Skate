import assert from "node:assert/strict";
import { managedRuntime, writeWord } from "./scope-runtime-fixture.ts";

Deno.test("a stale released base cannot shadow a live closure page", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const owner = assembled.address("CL_OWNER");
  const base = assembled.address("CL_PHYS");
  // Entry zero once owned page 80H and was released; entry one owns it now.
  memory[owner] = 0;
  memory[base] = 0x80;
  memory[owner + 1] = 1;
  memory[base + 1] = 0x80;
  // An FFH continuation entry is never a lookup target either.
  memory[owner + 2] = 0xff;
  memory[base + 2] = 0x81;

  writeWord(memory, assembled.address("CL_BASE"), 0x8010);
  assert.equal(call("SLAB_AT").carry, 0);
  assert.equal(memory[assembled.address("CL_PAGE")], 1);

  writeWord(memory, assembled.address("CL_BASE"), 0x8110);
  assert.equal(call("SLAB_AT").carry, 1);
  assert.equal(memory[assembled.address("CL_PAGE")], 0x80);
});

Deno.test("a closure-page miss changes no usage or base entry", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const use = assembled.address("CL_LIVE");
  const base = assembled.address("CL_PHYS");
  const before = [...memory.slice(use, use + 256)];
  writeWord(memory, assembled.address("CL_BASE"), 0x8010);
  assert.equal(call("SLAB_INC").carry, 1);
  assert.deepEqual([...memory.slice(use, use + 256)], before);
  assert.equal(memory[base], 0);
});

Deno.test("released closure pages clear their physical base entries", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const owner = assembled.address("CL_OWNER");
  const base = assembled.address("CL_PHYS");
  const index = assembled.address("CL_PAGE");

  memory[assembled.address("CL_CLASS")] = 0;
  const single = call("SLAB_ONE");
  assert.equal(single.carry, 0);
  const singleIndex = memory[index];
  assert.equal(memory[base + singleIndex], single.payload >>> 8);
  assert.equal(call("SLAB_REL").carry, 0);
  assert.equal(memory[owner + singleIndex], 0);
  assert.equal(memory[base + singleIndex], 0);

  // Leave a stale base in the next entry, then release a two-page run there.
  memory[base + 1] = 0x77;
  memory[assembled.address("CL_CLASS")] = 0x40;
  const run = call("SLAB_RUN");
  assert.equal(run.carry, 0);
  const runIndex = memory[index];
  assert.equal(memory[owner + runIndex], 0x41);
  assert.equal(memory[owner + runIndex + 1], 0xff);
  writeWord(memory, assembled.address("CL_PBASE"), run.payload);
  assert.equal(call("SLAB_GC2").carry, 0);
  assert.equal(memory[owner + runIndex], 0);
  assert.equal(memory[owner + runIndex + 1], 0);
  assert.equal(memory[base + runIndex], 0);
  assert.equal(memory[base + runIndex + 1], 0);
});

Deno.test("closure validation rejects an address two bytes past alignment", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const startMap = assembled.address("CL_MAP");
  const descriptor = assembled.address("START");
  for (const object of [0x8000, 0x8002]) {
    const unit = (object - 0x3000) >> 1;
    memory[startMap + (unit >> 3)] |= 1 << (unit & 7);
    writeWord(memory, object, descriptor);
  }
  writeWord(memory, assembled.address("CL_OBJ"), 0x8000);
  assert.equal(call("GC_OBJOK").carry, 0, "the aligned start is valid");
  // 8002H maps to the odd string-marker bit, which is never a start bit.
  writeWord(memory, assembled.address("CL_OBJ"), 0x8002);
  assert.equal(call("GC_OBJOK").carry, 1);
});
