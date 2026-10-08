import assert from "node:assert/strict";

import { loadAssembly } from "../z80.ts";
import {
  measureScopeControlBudget,
  renderScopeControlBudget,
  SCOPE_ALLOCATION_LIMIT,
  SCOPE_CORE_LIMIT,
  SCOPE_LOAD,
  SCOPE_STAGE_GUARD,
} from "../../tools/compiler-checks/scope-budget.ts";

Deno.test("scope compiler stays within the transient allocation budget", async () => {
  const assembled = await loadAssembly(
    "src/compiler/scope/compiler.asm",
  );
  assert.equal(assembled.address("CMD_MAIN"), SCOPE_LOAD);
  const budget = measureScopeControlBudget(assembled.image, assembled.address);
  assert.equal(budget.imageEnd - SCOPE_LOAD, budget.imageBytes);
  assert.ok(budget.stageGap >= SCOPE_STAGE_GUARD);
  assert.ok(budget.allocationBytes <= SCOPE_ALLOCATION_LIMIT);
  assert.ok(budget.allocationRemaining >= 0);
  assert.ok(budget.stackGap > 0);
  assert.ok(budget.stagedOutputLimit > 0);
  assert.equal(budget.globalSlotCapacity, 256);
  assert.equal(budget.localSlotCapacity, 128);
  assert.equal(budget.fixupCapacity, 640);
  assert.equal(budget.procedureCapacity, 255);
  assert.equal(budget.procedureDepth, 26);
  assert.equal(budget.symbolCapacity, 640);
  assert.equal(budget.coreRemaining, SCOPE_CORE_LIMIT - budget.imageBytes);
  assert.equal(
    budget.allocationRemaining,
    SCOPE_ALLOCATION_LIMIT - budget.allocationBytes,
  );
  assert.match(renderScopeControlBudget(budget), /256 globals/);
});

Deno.test("scope budget rejects an image that reaches the stage guard", () => {
  const address = (label: string) =>
    label === "CMD_MAIN" ? SCOPE_LOAD : label === "W_STAGE" ? 0x5800 : 0;
  assert.throws(
    () =>
      measureScopeControlBudget(
        { end: 0x5800 - SCOPE_STAGE_GUARD + 1 },
        address,
      ),
    RangeError,
  );
});
