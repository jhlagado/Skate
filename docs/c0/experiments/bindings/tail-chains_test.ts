import assert from "node:assert/strict";
import {
  EMPTY,
  HANDLE_COUNT,
  OUTPUT_CAPACITY,
  StagedOutput,
  TailChains,
} from "./tail-chains.ts";

Deno.test("many pending tail leaves use bounded handles and final disjoint patches", () => {
  const output = new StagedOutput(), chains = new TailChains(output);
  let owner = EMPTY;
  for (let i = 0; i < 1000; i++) {
    owner = chains.merge(owner, chains.candidate());
  }
  assert.equal(chains.metrics.peakHandles, 2);
  assert.equal(chains.metrics.outstandingSites, 1000);
  assert.equal(
    output.patches.length,
    0,
    "temporary links must not be NOBJ patches",
  );
  chains.resolve(owner, true, 0x3456);
  assert.equal(chains.metrics.liveHandles, 0);
  assert.equal(chains.metrics.outstandingSites, 0);
  assert.equal(output.patches.length, 1000);
  for (let i = 0; i < 1000; i++) {
    assert.deepEqual(
      output.bytes.slice(i * 3, i * 3 + 3),
      Uint8Array.of(0xc3, 0x56, 0x34),
    );
    assert.equal(output.patches[i].offset, i * 3);
  }
});

Deno.test("sequence, conditional and independent lambda contexts retain only proper tails", () => {
  const output = new StagedOutput(), chains = new TailChains(output);
  const first = chains.merge(chains.candidate(), chains.candidate()); // if arms
  chains.resolve(first, false, 0x1234); // another enclosing body expression starts
  const known = chains.knownCall(0x1234); // argument never becomes a candidate
  const lambdaBody = chains.candidate();
  chains.resolve(lambdaBody, true, 0x3456); // lambda starts its own tail context
  const last = chains.merge(chains.candidate(), chains.candidate());
  chains.resolve(last, true, 0x3456);
  assert.deepEqual([0, 3, known, 9, 12, 15].map((x) => output.bytes[x]), [
    0xcd,
    0xcd,
    0xcd,
    0xc3,
    0xc3,
    0xc3,
  ]);
  assert.deepEqual(output.patches.map((x) => x.offset), [0, 3, 9, 12, 15]);
});

Deno.test("exact handle and output limits refuse before writes", () => {
  const output = new StagedOutput(), chains = new TailChains(output);
  const owners = Array.from({ length: HANDLE_COUNT }, () => chains.candidate());
  const before = chains.handles.slice(),
    length = output.length,
    writes = output.writes;
  assert.throws(() => chains.candidate(), /handle capacity/);
  assert.deepEqual(chains.handles, before);
  assert.equal(output.length, length);
  assert.equal(output.writes, writes);
  for (const h of owners) chains.resolve(h, false, 0x1234);
  const small = new StagedOutput(3), bounded = new TailChains(small);
  bounded.candidate();
  const snapshot = bounded.handles.slice();
  assert.throws(() => bounded.candidate(), /output capacity/);
  assert.deepEqual(bounded.handles, snapshot);
  assert.equal(small.length, 3);
});

Deno.test("repeated independent forms release every handle", () => {
  const chains = new TailChains(new StagedOutput());
  for (let i = 0; i < 5000; i++) {
    chains.resolve(chains.candidate(), i % 2 === 0, 0x2345);
  }
  assert.equal(chains.metrics.peakHandles, 1);
  assert.equal(chains.metrics.peakSites, 1);
  assert.equal(chains.metrics.liveHandles, 0);
  assert.equal(chains.output.length, 15000);
  assert.ok(chains.output.length < OUTPUT_CAPACITY);
});

Deno.test("aliasing, consumed handles and corrupted links reject", () => {
  const output = new StagedOutput(), chains = new TailChains(output);
  const a = chains.candidate(), b = chains.candidate();
  assert.throws(() => chains.merge(a, a), /duplicate handle/);
  assert.throws(() => chains.merge(b, a), /emission order/);
  const merged = chains.merge(a, b);
  assert.throws(() => chains.resolve(b, true, 0x1234), /consumed/);
  output.bytes[1] = 0;
  output.bytes[2] = 0; // cycle back to the first call
  assert.throws(
    () => chains.resolve(merged, true, 0x1234),
    /invalid or cyclic/,
  );
  assert.equal(output.patches.length, 0);
});

Deno.test("I/O failure preserves partial private output and forbids reuse", () => {
  for (const operation of ["read", "write"] as const) {
    const output = new StagedOutput(), chains = new TailChains(output);
    const owner = chains.merge(chains.candidate(), chains.candidate());
    if (operation === "read") output.failRead = output.reads + 2;
    else output.failWrite = output.writes + 2;
    assert.throws(
      () => chains.resolve(owner, true, 0x1234),
      new RegExp(`output ${operation}`),
    );
    assert.equal(output.failed, true);
    assert.equal(output.patches.length, 1);
    assert.throws(() => chains.candidate(), /abandoned generation/);
  }
});

Deno.test("end gate catches an orphan skipped by a corrupt forward link", () => {
  const output = new StagedOutput(), chains = new TailChains(output);
  const owner = chains.merge(
    chains.merge(chains.candidate(), chains.candidate()),
    chains.candidate(),
  );
  output.bytes[1] = 6;
  output.bytes[2] = 0;
  chains.resolve(owner, true, 0x1234);
  assert.equal(chains.metrics.outstandingSites, 1);
  assert.equal(chains.metrics.liveHandles, 0);
  assert.throws(() => chains.finish(), /unfinished tail sites/);
  assert.equal(output.failed, true);
  assert.throws(() => chains.knownCall(0x1234), /abandoned generation/);
});

Deno.test("spool failure after a successful COM change abandons the generation", () => {
  const output = new StagedOutput(), chains = new TailChains(output);
  const owner = chains.merge(chains.candidate(), chains.candidate());
  output.failSpoolWrite = 2;
  assert.throws(() => chains.resolve(owner, true, 0x1234), /patch spool write/);
  assert.equal(output.patches.length, 1);
  assert.deepEqual(output.bytes.slice(3, 6), Uint8Array.of(0xc3, 0x34, 0x12));
  assert.equal(output.failed, true);
  assert.throws(() => chains.finish(), /abandoned generation/);
});

Deno.test("component completion and retained-CCP output bound are explicit", () => {
  for (const invalid of [0, -1, OUTPUT_CAPACITY + 1, 65536, 3.5, NaN]) {
    assert.throws(() => new StagedOutput(invalid), /output capacity bounds/);
  }
  const output = new StagedOutput(), chains = new TailChains(output);
  chains.knownCall(0x1234);
  chains.resolve(chains.candidate(), true, 0x1234);
  chains.finish();
  assert.equal(output.failed, false);
});
