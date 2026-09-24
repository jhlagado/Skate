import assert from "node:assert/strict";
import { managedRuntime, writeWord } from "./scope-runtime-fixture.ts";

Deno.test("vector overflow fallback preserves every rooted pair", async () => {
  const { assembled, memory, call } = await managedRuntime(true);
  const count = 513;
  const roots = 0xc000;
  const vectors: number[] = [];
  const pairs: number[] = [];

  for (let index = 0; index < count; index++) {
    memory[assembled.address("SRTVREQ")] = 1;
    const vector = call("SRTVACL");
    assert.equal(vector.carry, 0);
    vectors.push(vector.payload);

    const pair = call("SRTMAKEP");
    assert.equal(pair.carry, 0);
    pairs.push(pair.payload);
    writeWord(memory, vector.payload, 1);
    writeWord(memory, vector.payload + 1, pair.payload);
    memory[vector.payload + 3] = 1;
    memory[vector.payload + 4] = 0;
  }

  for (let index = 0; index < count; index++) {
    const root = roots + index * 4;
    writeWord(memory, root, vectors[index]);
    memory[root + 2] = 7;
    memory[root + 3] = 1;
  }
  writeWord(memory, assembled.address("SRTGBASE"), roots);
  writeWord(memory, assembled.address("SRTGEND"), roots + count * 4);

  call("SRTGC");
  assert.equal(memory[assembled.address("SRTMOVER")], 1);
  for (const pair of pairs) {
    assert.equal(memory[pair + 4] & 0x40, 0x40, `pair ${pair.toString(16)}`);
  }
});
