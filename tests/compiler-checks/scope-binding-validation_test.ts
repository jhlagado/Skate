import assert from "node:assert/strict";
import {
  managedRuntime,
  readWord,
  writeWord,
} from "./scope-runtime-fixture.ts";

Deno.test("an unmapped binding cell stops before any cell bytes are written", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  // A damaged free list hands SRTCELL a cell outside the binding start map.
  const bad = 0xd702;
  writeWord(memory, bad, 0);
  writeWord(memory, assembled.address("SRTBHEAD"), bad);
  memory.fill(0x5a, 0xa700, 0xa710);
  memory.fill(0x5a, bad, bad + 4);
  writeWord(memory, bad, 0);

  cpu.pc = assembled.address("SRTCELL");
  cpu.sp = 0xdff0;
  writeWord(memory, cpu.sp, 0xef00);
  const error = assembled.address("SRTERROR");
  let steps = 0;
  while (cpu.pc !== 0xef00 && cpu.pc !== error) {
    assert.ok(++steps < 1_000_000, "SRTCELL did not finish");
    assembled.runtime.step();
  }
  assert.equal(cpu.pc, error, "an unmapped cell must be a runtime error");
  assert.deepEqual(
    [...memory.slice(0xa700, 0xa710)],
    new Array(16).fill(0x5a),
    "SRTCELL wrote through an unrestored pointer",
  );
  assert.deepEqual([...memory.slice(bad + 2, bad + 4)], [0x5a, 0x5a]);
});

Deno.test("SRTBNEW returns the cell address with carry on failure", async () => {
  const { assembled, memory, call } = await managedRuntime();
  writeWord(memory, assembled.address("SRTCELLP"), 0xd702);
  const result = call("SRTBNEW");
  assert.equal(result.carry, 1);
  assert.equal(result.payload, 0xd702);
  assert.equal(readWord(memory, assembled.address("SRTCELLP")), 0xd702);
});
