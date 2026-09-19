import assert from "node:assert/strict";
import { inspectSources } from "./source-driver.ts";

const WEATHER: string | URL = (() => {
  try {
    const injected = Deno.env.get("SKATE_WEATHER_FIXTURE");
    if (injected) return injected;
  } catch {
    // The default URL keeps this test runnable without --allow-env.
  }
  return new URL("../../fixtures/weather/", import.meta.url);
})();
const weatherFile = (name: string) =>
  typeof WEATHER === "string" ? `${WEATHER}/${name}` : new URL(name, WEATHER);
const operand = (
  result: ReturnType<typeof inspectSources>,
  site: number,
) => [...result.resolver.output.bytes.slice(site + 3, site + 7)];
const sites = (result: ReturnType<typeof inspectSources>) =>
  Array.from(
    { length: result.resolver.output.length / 7 },
    (_, index) => index * 7,
  );

Deno.test("nested same-name staged binders retain the outer owner", () => {
  const result = inspectSources([
    "(define f (lambda () (let ((x (let ((x 1)) x))) x)))",
  ]);
  const access = sites(result);
  assert.equal(access.length, 2);
  assert.deepEqual(operand(result, access[0]), [0, 0, 0, 0]);
  assert.deepEqual(operand(result, access[1]), [0, 0, 0, 0]);
  assert.equal(result.resolver.snapshot().pendingSites, 0);
  assert.equal(result.resolver.snapshot().dynamicGlobals, 1); // f only.
});

Deno.test("one staged stack preserves order across multiple outer and nested binders", () => {
  const result = inspectSources([
    "(define f (lambda () (let " +
    "((x (let ((x 1)) x)) (y (let ((y 2)) y))) (+ x y))))",
  ]);
  const access = sites(result);
  assert.equal(access.length, 5);
  assert.deepEqual(operand(result, access[0]), [0, 0, 0, 0]);
  assert.deepEqual(operand(result, access[1]), [0, 0, 0, 0]);
  assert.deepEqual(operand(result, access[2]), [255, 255, 0, 0]);
  assert.deepEqual(operand(result, access[3]), [0, 0, 0, 0]);
  assert.deepEqual(operand(result, access[4]), [0, 0, 1, 0]);
  assert.equal(result.resolver.snapshot().pendingSites, 0);
});

Deno.test("late internal definitions shadow predefined and outer names", () => {
  const result = inspectSources([
    "(define + 7) (define f (lambda () (define probe (lambda () +)) " +
    "(define + 37) (probe)))",
  ]);
  const access = sites(result);
  assert.equal(access.length, 2);
  assert.deepEqual(operand(result, access[0]), [1, 0, 1, 0]);
  assert.deepEqual(operand(result, access[1]), [0, 0, 0, 0]);
  result.resolver.finish();
});

Deno.test("letrec initializer references do not bind to later body definitions", () => {
  const result = inspectSources([
    "(define answer 7) (define f (lambda () " +
    "(letrec ((probe (lambda () answer))) " +
    "(define answer 37) (probe))))",
  ]);
  const access = sites(result);
  assert.equal(access.length, 2);
  assert.deepEqual(operand(result, access[0]), [255, 255, 30, 0]);
  assert.deepEqual(operand(result, access[1]), [0, 0, 0, 0]);
  result.resolver.finish();
});

Deno.test("mutual and later globals resolve across source parts", () => {
  const result = inspectSources([
    "(define first second)",
    "(define second first)",
    "(define third first)",
  ]);
  const access = sites(result);
  assert.equal(access.length, 3);
  assert.deepEqual(operand(result, access[0]), [255, 255, 31, 0]);
  assert.deepEqual(operand(result, access[1]), [255, 255, 30, 0]);
  assert.deepEqual(operand(result, access[2]), [255, 255, 30, 0]);
  assert.equal(result.resolver.snapshot().globalSlots, 33);
  result.resolver.finish();
});

Deno.test("undefined names report the first source position after delayed resolution", () => {
  const first = "(define f missing)";
  assert.throws(
    () => inspectSources([first, "(define g missing)"]),
    new RegExp(`undefined missing at 0:${first.indexOf("missing")}`),
  );
});

Deno.test("parallel binder scratch is bounded and rejects the sixty-fifth staged name", () => {
  const bindings = Array.from(
    { length: 65 },
    (_, index) => `(b${index} 0)`,
  ).join(" ");
  assert.throws(
    () => inspectSources([`(let (${bindings}) b0)`]),
    /pending binder capacity/,
  );
});

Deno.test("the actual weather package fits the exact host arena accounting", async () => {
  const manifest = await Deno.readTextFile(weatherFile("WEATHER.SKM"));
  const parts: string[] = [];
  for (const name of manifest.trim().split(/\s+/)) {
    parts.push(await Deno.readTextFile(weatherFile(name)));
  }
  const result = inspectSources(parts);
  const metrics = result.resolver.snapshot();
  assert.deepEqual(parts.map((part) => part.length), [9015, 4284, 3467]);
  assert.equal(metrics.arenaBytes, 8192);
  assert.equal(metrics.names.peakLiveNames, 273);
  assert.equal(metrics.names.peakLiveSpellingBytes, 4078);
  assert.equal(metrics.peakBindings, 18);
  assert.equal(metrics.peakScopes, 16);
  assert.equal(metrics.peakGroups, 1);
  assert.equal(metrics.peakPendingSites, 1);
  assert.equal(metrics.globalSlots, 286);
  assert.equal(result.peakPendingBinders, 4);
  assert.equal(result.maxSourceDepth, 11);
  assert.equal(result.procedures, 26);
  assert.equal(result.resolver.output.length, 2905);
  assert.equal(result.resolver.output.failed, false);
  let globalOperands = 0;
  for (const site of sites(result)) {
    const tag = result.resolver.output.bytes[site + 3] |
      (result.resolver.output.bytes[site + 4] << 8);
    if (tag === 0xffff) globalOperands++;
  }
  assert.equal(globalOperands, 339);
  assert.equal(sites(result).length - globalOperands, 76);
  result.resolver.finish();
});
