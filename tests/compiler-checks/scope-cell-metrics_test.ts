import assert from "node:assert/strict";
import {
  summarizeCellMeasurements,
} from "../../tools/compiler-checks/cell-metrics.mjs";

Deno.test("cell metrics keep independent maxima separate from allocation traffic", () => {
  const metrics = summarizeCellMeasurements([
    {
      comBytes: 100,
      asoBytes: 120,
      imageBytes: 90,
      pairAllocations: 3,
      bindingAllocations: 2,
      closureAllocations: 1,
      collections: 2,
      activations: 4,
    },
    {
      comBytes: 110,
      asoBytes: 115,
      imageBytes: 95,
      pairAllocations: 1,
      bindingAllocations: 5,
      closureAllocations: 2,
      collections: 1,
      activations: 3,
    },
  ]);
  assert.equal(metrics.maxComBytes, 110);
  assert.equal(metrics.maxAsoBytes, 120);
  assert.equal(metrics.maxPairAllocations, 3);
  assert.equal(metrics.maxBindingAllocations, 5);
  assert.equal(metrics.pairAllocations, 4);
  assert.equal(metrics.bindingAllocations, 7);
  assert.equal(metrics.currentPairAllocationBytes, 20);
  assert.equal(metrics.experimentPairAllocationBytes, 32);
  assert.equal(metrics.currentBindingAllocationBytes, 21);
  assert.equal(metrics.experimentBindingAllocationBytes, 28);
});

Deno.test("cell metrics reject an empty suite", () => {
  assert.throws(() => summarizeCellMeasurements([]), /empty/);
});
