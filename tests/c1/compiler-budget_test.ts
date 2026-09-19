import assert from "node:assert/strict";

import { loadAssembly } from "../z80.ts";
import {
  C1_CORE_LIMIT,
  C1_STACK_TOP,
  measureC1Budget,
  renderC1Budget,
} from "../../tools/c1/compiler-budget.ts";

Deno.test("C1 image clears the core and initial-allocation gates", async () => {
  const assembled = await loadAssembly("src/compiler/arithmetic-compiler.asm");
  const budget = measureC1Budget(assembled.image, assembled.address, {
    sourceBytes: 10,
    objectBytes: 2_353,
    comBytes: 2_242,
  });
  assert.equal(budget.entry, 0x0100);
  assert.ok(budget.imageBytes < C1_CORE_LIMIT);
  assert.ok(budget.allocationRemaining > 0);
  assert.ok(budget.imageEnd < C1_STACK_TOP);
  assert.ok(budget.imageToStackGap > 0);
  assert.equal(budget.coreLimit, 16_384);
  assert.equal(budget.allocationLimit, 30_720);
  assert.ok(budget.spans.every((item) => item.bytes >= 0));
  assert.equal(budget.objectRecords, 19);
  assert.equal(budget.comRecords, 18);
  assert.match(renderC1Budget(budget), /generated NOBJ template/);
});

Deno.test("C1 static workspace stays inside the general workspace bucket", async () => {
  const assembled = await loadAssembly("src/compiler/arithmetic-compiler.asm");
  const budget = measureC1Budget(assembled.image, assembled.address, {
    sourceBytes: 10,
    objectBytes: 2_353,
    comBytes: 2_242,
  });
  assert.ok(budget.staticWorkspace < 4096);
  assert.ok(budget.workspaceRemaining > 0);
  assert.equal(budget.imageBytes, 12_514);
  assert.equal(budget.staticWorkspace, 2_846);
  assert.equal(budget.writableTotal, 5_199);
  assert.equal(budget.writableBucketRemaining, -1_103);
});
