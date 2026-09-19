import assert from "node:assert/strict";
import { linkSkateObjects } from "../../../../tools/link.ts";
import { runObserved } from "./provider_memory.ts";
import {
  address,
  assembleFixture,
  assertMap,
  linkOptions,
  PAYLOAD_END,
  payloadObject,
  profile,
  PROVIDER_BASE,
  PROVIDER_END,
  providerObject,
  providerPrivateBytes,
  providerServices,
  ROOTBASE,
  STACKLOW,
  STACKTOP,
  word,
  writableSpans,
} from "./provider_fixture.ts";

Deno.test("prepared fixed-origin provider links ABI and executes input-dependent payload", async () => {
  const [providerAssembly, payloadAssembly] = await assembleFixture();
  assert.equal(address(providerAssembly, "PVEND"), PROVIDER_END);
  const privateBytes = providerPrivateBytes(providerAssembly);
  assert.equal(privateBytes, 593, "measured provider private static bytes");
  assert.equal(PROVIDER_END - PROVIDER_BASE - privateBytes, 9908);
  assert.equal(address(payloadAssembly, "PAYENTRY"), PROVIDER_END);
  assert.equal(address(payloadAssembly, "PAYEND"), PAYLOAD_END);
  assertMap(profile);

  const provider = providerObject(providerAssembly);
  const payload = payloadObject(payloadAssembly);
  const linked = linkSkateObjects([
    { id: "provider", bytes: provider.serialized },
    { id: "payload", bytes: payload.serialized },
  ], linkOptions());
  assert.equal(linked.entry?.address, PROVIDER_END);
  const linkedRegion = linked.regions.find(({ targetRegionId }) =>
    targetRegionId === profile.id
  );
  assert.ok(linkedRegion);

  for (const [_, vector, target] of providerServices) {
    const vectorAddress = address(providerAssembly, vector);
    const targetAddress = address(providerAssembly, target);
    assert.equal(
      word(linkedRegion.bytes, vectorAddress - linkedRegion.base + 1),
      targetAddress,
    );
  }
  const payloadBytes = linkedRegion.bytes.slice(
    PROVIDER_END - linkedRegion.base,
    PAYLOAD_END - linkedRegion.base,
  );
  const payloadCalls: number[] = [];
  for (let offset = 0; offset + 2 < payloadBytes.length; offset += 1) {
    if (payloadBytes[offset] === 0xcd) {
      payloadCalls.push(word(payloadBytes, offset + 1));
    }
  }
  assert.deepEqual(payloadCalls, [
    address(providerAssembly, "PVHINI"),
    address(providerAssembly, "PVGCST"),
    address(providerAssembly, "PVRTIN"),
    address(providerAssembly, "PVNADD"),
  ]);

  const allowedSpans = writableSpans(providerAssembly, payloadAssembly);
  const region = linked.regions.find(({ targetRegionId }) =>
    targetRegionId === profile.id
  );
  assert.ok(region);
  const first = runObserved(region, {
    entry: PROVIDER_BASE,
    left: 41,
    right: 1,
    stackLow: STACKLOW,
    stackTop: STACKTOP,
    allowedSpans,
  });
  const second = runObserved(region, {
    entry: PROVIDER_BASE,
    left: 100,
    right: 23,
    stackLow: STACKLOW,
    stackTop: STACKTOP,
    allowedSpans,
  });
  for (const run of [first, second]) {
    assert.equal(run.cpu.a, 3);
    assert.equal(run.cpu.flags.C, 0);
    assert.equal(run.cpu.sp, STACKTOP);
    assert.equal(run.cpu.ix, 0, "RTINIT starts without an activation");
    assert.equal(run.cpu.iy, ROOTBASE, "RTINIT starts at the root base");
    assert.equal(run.violations.length, 0, run.violations.join("; "));
    assert.equal(run.writeCount, 32879);
    assert.equal(run.stackWrites, 22);
    assert.equal(run.stackLowWater, 0xe3fa);
    assert.equal(run.canariesIntact, true);
    for (
      const [name, count] of [
        ["payload input/result scratch", 9],
        ["guarded stack", 22],
        ["allocator state", 12],
        ["heap", 32764],
        ["collector state", 13],
        ["execution state", 49],
        ["numeric state", 10],
      ] as const
    ) {
      assert.equal(run.writesBySpan.get(name), count, name);
    }
  }
  assert.equal(first.cpu.h * 256 + first.cpu.l, 42);
  assert.equal(second.cpu.h * 256 + second.cpu.l, 123);
  assert.notEqual(
    first.cpu.h * 256 + first.cpu.l,
    second.cpu.h * 256 + second.cpu.l,
  );
  assert.equal(first.memory[address(providerAssembly, "HREADY")], 1);
  assert.equal(second.memory[address(providerAssembly, "HREADY")], 1);
});
