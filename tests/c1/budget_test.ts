import assert from "node:assert/strict";

import { loadAssembly } from "../z80.ts";
import {
  C1_CORE_LIMIT,
  C1_STACK_TOP,
  measureC1Budget,
  renderC1Budget,
} from "../../tools/c1/c1-budget.ts";

Deno.test("C1 image clears the core and initial-allocation gates", async () => {
  const assembled = await loadAssembly("src/compiler/c1.asm");
  const budget = measureC1Budget(assembled.image, assembled.address, {
    sourceBytes: 10,
    objectBytes: 219,
    comBytes: 128,
  });
  assert.equal(budget.entry, 0x0100);
  assert.ok(budget.imageBytes < C1_CORE_LIMIT);
  assert.ok(budget.allocationRemaining > 0);
  assert.ok(budget.imageEnd < C1_STACK_TOP);
  assert.ok(budget.imageToStackGap > 0);
  assert.equal(budget.coreLimit, 16_384);
  assert.equal(budget.allocationLimit, 30_720);
  assert.ok(budget.spans.every((item) => item.bytes >= 0));
  assert.equal(budget.objectRecords, 2);
  assert.equal(budget.comRecords, 1);
  assert.match(renderC1Budget(budget), /generated NOBJ template/);
});

Deno.test("C1 static workspace stays inside the general workspace bucket", async () => {
  const assembled = await loadAssembly("src/compiler/c1.asm");
  const budget = measureC1Budget(assembled.image, assembled.address, {
    sourceBytes: 10,
    objectBytes: 219,
    comBytes: 128,
  });
  assert.ok(budget.staticWorkspace < 4096);
  assert.ok(budget.workspaceRemaining > 0);
  assert.equal(budget.imageBytes, 10_557);
  assert.equal(budget.staticWorkspace, 2_981);
});
