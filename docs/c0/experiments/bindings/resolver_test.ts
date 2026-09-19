import assert from "node:assert/strict";
import { BindingResolver } from "./resolver.ts";

const operand = (
  resolver: BindingResolver,
  site: number,
) => [...resolver.output.bytes.slice(site + 3, site + 7)];

function closeLocal(resolver: BindingResolver) {
  resolver.seal();
  resolver.leaveScope();
}

Deno.test("a late local definition shadows a predefined name in an earlier lambda", () => {
  const resolver = new BindingResolver(["+"]);
  assert.equal(resolver.declare("+"), 0);
  resolver.enterScope();
  resolver.enterScope();
  const site = resolver.use("+", { part: 0, offset: 3 }, 1);
  closeLocal(resolver);
  assert.equal(resolver.declare("+"), 0);
  assert.deepEqual(operand(resolver, site.site), [1, 0, 0, 0]);
  closeLocal(resolver);
  resolver.finish();
});

Deno.test("an unresolved inner group promotes through closed scopes before global binding", () => {
  const resolver = new BindingResolver();
  resolver.enterScope();
  resolver.enterScope();
  const site = resolver.use("later", { part: 2, offset: 17 }, 7);
  closeLocal(resolver);
  closeLocal(resolver);
  assert.equal(resolver.snapshot().pendingSites, 1);
  assert.equal(resolver.declare("later"), 0);
  assert.deepEqual(operand(resolver, site.site), [255, 255, 0, 0]);
  resolver.finish();
});

Deno.test("an inner use falls back to an already declared outer local", () => {
  const resolver = new BindingResolver();
  resolver.enterScope();
  assert.equal(resolver.declare("value"), 0);
  resolver.enterScope();
  const site = resolver.use("value", { part: 0, offset: 11 });
  closeLocal(resolver);
  assert.deepEqual(operand(resolver, site.site), [1, 0, 0, 0]);
  closeLocal(resolver);
  resolver.finish();
});

Deno.test("sibling scopes reuse released name IDs but pending globals keep ownership", () => {
  const resolver = new BindingResolver();
  const first = resolver.names.intern("short-lived");
  resolver.enterScope();
  resolver.declare("short-lived");
  resolver.use("short-lived", { part: 0, offset: 1 });
  closeLocal(resolver);
  assert.throws(() => resolver.names.spelling(first), /inactive/);

  resolver.enterScope();
  resolver.declare("sibling");
  assert.equal(resolver.names.intern("sibling"), first);
  closeLocal(resolver);

  resolver.enterScope();
  resolver.use("still-live", { part: 0, offset: 2 });
  const held = resolver.names.intern("still-live");
  closeLocal(resolver);
  const fresh = resolver.names.intern("fresh");
  assert.notEqual(fresh, held);
  resolver.declare("still-live");
  resolver.finish();
});

Deno.test("letrec initializer groups resolve before its reopened body definitions", () => {
  const resolver = new BindingResolver();
  assert.equal(resolver.declare("answer"), 0);
  resolver.enterScope();
  resolver.enterScope();
  resolver.enterScope();
  const initializer = resolver.use("answer", { part: 0, offset: 29 }, 3);
  closeLocal(resolver); // initializer lambda
  resolver.seal(); // letrec initializer region
  resolver.reopenDefinitions(); // same frame, distinct definition region
  resolver.declare("answer");
  closeLocal(resolver); // letrec body
  closeLocal(resolver); // enclosing procedure
  assert.deepEqual(operand(resolver, initializer.site), [255, 255, 0, 0]);
  resolver.finish();
});

Deno.test("many uses share one group while distinct procedures consume group slots", () => {
  const shared = new BindingResolver();
  shared.enterScope();
  const sites: number[] = [];
  for (let i = 0; i < 1000; i++) {
    sites.push(shared.use("shared", { part: 0, offset: i }, 9).site);
  }
  assert.equal(shared.snapshot().peakGroups, 1);
  assert.equal(shared.snapshot().peakPendingSites, 1000);
  closeLocal(shared);
  shared.declare("shared");
  shared.finish();
  assert.deepEqual(operand(shared, sites[999]), [255, 255, 0, 0]);

  const distinct = new BindingResolver();
  distinct.enterScope();
  for (let i = 0; i < 64; i++) {
    distinct.use("distinct", { part: 0, offset: i }, i);
  }
  const before = distinct.output.length;
  assert.throws(
    () => distinct.use("distinct", { part: 0, offset: 64 }, 64),
    /group capacity/,
  );
  assert.equal(distinct.output.length, before);
  assert.equal(distinct.output.failed, true);
  assert.throws(
    () => distinct.use("other", { part: 0, offset: 65 }),
    /abandoned/,
  );
});

Deno.test("output writes and reads abandon the private generation", () => {
  const writeFailure = new BindingResolver();
  writeFailure.output.failWrite = 1;
  assert.throws(
    () => writeFailure.use("x", { part: 0, offset: 0 }),
    /output write/,
  );
  assert.equal(writeFailure.output.failed, true);
  assert.throws(
    () => writeFailure.use("y", { part: 0, offset: 1 }),
    /abandoned/,
  );

  const readFailure = new BindingResolver();
  readFailure.enterScope();
  readFailure.use("x", { part: 0, offset: 0 });
  readFailure.output.failRead = 1;
  assert.throws(() => readFailure.seal(), /output read/);
  assert.equal(readFailure.output.failed, true);
  assert.throws(() => readFailure.leaveScope(), /abandoned/);
});

Deno.test("the first undefined global retains its original source position", () => {
  const resolver = new BindingResolver();
  resolver.enterScope();
  resolver.use("missing", { part: 0, offset: 101 }, 4);
  resolver.use("missing", { part: 1, offset: 2 }, 4);
  closeLocal(resolver);
  assert.throws(() => resolver.finish(), /undefined missing at 0:101/);
  assert.equal(resolver.output.failed, true);
});
