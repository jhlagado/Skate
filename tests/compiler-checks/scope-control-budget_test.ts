import assert from "node:assert/strict";

import { loadAssembly } from "../z80.ts";
import {
  measureScopeControlBudget,
  renderScopeControlBudget,
  SCOPE_ALLOCATION_LIMIT,
  SCOPE_CORE_LIMIT,
} from "../../tools/compiler-checks/scope-control-budget.ts";

Deno.test("scope compiler stays below its core and allocation gates", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope-control-compiler.asm",
  );
  const budget = measureScopeControlBudget(assembled.image, assembled.address);
  assert.ok(budget.imageBytes < SCOPE_CORE_LIMIT);
  assert.ok(budget.allocationRemaining > 0);
  assert.ok(budget.stackGap > 0);
  assert.ok(budget.stagedOutputLimit > 0);
  assert.equal(budget.globalSlotCapacity, 256);
  assert.equal(budget.localSlotCapacity, 128);
  assert.equal(budget.fixupCapacity, 320);
  assert.equal(budget.symbolCapacity, 320);
  assert.equal(budget.imageBytes, 13_185);
  assert.equal(budget.coreRemaining, SCOPE_CORE_LIMIT - budget.imageBytes);
  assert.equal(
    budget.allocationRemaining,
    SCOPE_ALLOCATION_LIMIT - budget.allocationBytes,
  );
  assert.equal(budget.stagedOutputLimit, 12_160);
  assert.equal(budget.fixedTableBytes, 17_920);
  assert.equal(budget.allocationBytes, 45_313);
  assert.match(renderScopeControlBudget(budget), /256 globals/);
});
