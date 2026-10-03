import assert from "node:assert/strict";
import { managedRuntime, writeWord } from "./scope-runtime-fixture.ts";

Deno.test("vector overflow fallback preserves every rooted pair", async () => {
  const { assembled, memory, call } = await managedRuntime(true);
  const count = 513;
  // Above the page tables at C400H..C780H; the records cross only the empty
  // quoted-data and reader stacks and end below the mark worklist at D000H.
  const roots = 0xc780;
  const vectors: number[] = [];
  const pairs: number[] = [];

  for (let index = 0; index < count; index++) {
    memory[assembled.address("VEC_REQ")] = 1;
    const vector = call("VEC_NEW");
    assert.equal(vector.carry, 0);
    vectors.push(vector.payload);

    const pair = call("PAIR_NEW");
    assert.equal(pair.carry, 0);
    pairs.push(pair.payload);
    writeWord(memory, vector.payload, 1);
    writeWord(memory, vector.payload + 1, pair.payload);
    memory[vector.payload + 3] = 0;
    memory[vector.payload + 4] = 1;
  }

  for (let index = 0; index < count; index++) {
    const root = roots + index * 4;
    writeWord(memory, root, vectors[index]);
    memory[root + 2] = 0; // Clear extension byte.
    memory[root + 3] = 0x17;
  }
  writeWord(memory, assembled.address("SRTGBASE"), roots);
  writeWord(memory, assembled.address("SRTGEND"), roots + count * 4);

  call("GC");
  assert.equal(memory[assembled.address("SRTMOVER")], 1);
  for (const pair of pairs) {
    assert.equal(memory[pair + 3] & 0x40, 0x40, `pair ${pair.toString(16)}`);
  }
});
