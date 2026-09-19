import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";
import {
  measureNativeCompilerBudget,
  NATIVE_COMPILER_PROFILES,
  NATIVE_COMPILER_STACK_GUARD,
  NATIVE_MACRO_ARENA_BASE,
  NATIVE_PAIR_OVERLAY_BASE,
  planNativeCompilerMap,
  renderNativeCompilerBudget,
} from "../tools/native-budget.ts";

Deno.test("production compiler fits below its native stack guard", async () => {
  const assembled = await loadAssembly("compiler/skate.asm");
  const budget = measureNativeCompilerBudget(
    assembled.image,
    assembled.address,
  );
  assert.equal(budget.entry, 0x0100);
  assert.ok(budget.imageEnd < NATIVE_COMPILER_STACK_GUARD);
  assert.ok(budget.imageToStackGap > 0);
  assert.ok(budget.spans.every((item) => item.bytes >= 0));
  assert.match(renderNativeCompilerBudget(budget), /NOBJ skeleton/);
});

Deno.test(
  "native compiler map accepts cpm-64k and exposes transient windows",
  async () => {
    const assembled = await loadAssembly("compiler/skate.asm");
    const budget = measureNativeCompilerBudget(
      assembled.image,
      assembled.address,
    );
    const map = planNativeCompilerMap("cpm-64k", budget.imageEnd);
    assert.equal(map.accepted, true);
    assert.equal(map.tpaTop, NATIVE_COMPILER_PROFILES["cpm-64k"]);
    assert.equal(map.pairOverlay.start, NATIVE_PAIR_OVERLAY_BASE);
    assert.equal(map.macroArena.start, NATIVE_MACRO_ARENA_BASE);
    assert.equal(map.macroArena.bytes, 0x2400);
    assert.equal(map.errors.length, 0);
    assert.match(
      renderNativeCompilerBudget(budget, map),
      /Profile accepted: yes/,
    );
  },
);

Deno.test("native compiler map rejects cpm-32k before package work", () => {
  const map = planNativeCompilerMap("cpm-32k", NATIVE_COMPILER_STACK_GUARD);
  assert.equal(map.accepted, false);
  assert.deepEqual(map.errors, [
    "profile TPA does not reach the macro arena",
  ]);
  assert.equal(map.macroArena.bytes, 0);
  assert.match(
    renderNativeCompilerBudget({
      entry: 0x0100,
      imageEnd: NATIVE_COMPILER_STACK_GUARD,
      imageBytes: NATIVE_COMPILER_STACK_GUARD - 0x0100,
      stackGuard: NATIVE_COMPILER_STACK_GUARD,
      imageToStackGap: 0,
      spans: [],
    }, map),
    /Profile error: profile TPA does not reach the macro arena/,
  );
});

Deno.test("native compiler map rejects an image over the stack guard", () => {
  const map = planNativeCompilerMap("cpm-64k", NATIVE_COMPILER_STACK_GUARD + 1);
  assert.equal(map.accepted, false);
  assert.ok(
    map.errors.includes("compiler image overlaps the native stack guard"),
  );
});
