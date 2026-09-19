import assert from "node:assert/strict";
import { type NativeResult, ParserMachine } from "./parser-machine.ts";
import {
  generatedTokenLists,
  HAND_CASES,
  nestApplications,
  nestArgumentApplications,
  nestBeginExpressions,
  nestIfs,
  nestLambdaLaterBodies,
  nestLambdas,
  referenceParse,
  type TraceRecord,
} from "./parser-model.ts";

let machinesPromise:
  | Promise<readonly [ParserMachine, ParserMachine]>
  | undefined;

function machines(): Promise<readonly [ParserMachine, ParserMachine]> {
  machinesPromise ??= Promise.all([
    ParserMachine.open("handwritten"),
    ParserMachine.open("table"),
  ]);
  return machinesPromise;
}

function flatten(records: readonly TraceRecord[]): number[] {
  return records.flatMap((
    { action, index },
  ) => [action, index & 255, index >>> 8]);
}

function checkRun(
  result: NativeResult,
  tokens: readonly number[],
  expected: ReturnType<typeof referenceParse>,
): void {
  assert.equal(result.ok, expected.ok, `${result.candidate} success mismatch`);
  assert.equal(result.status, expected.ok ? 0 : expected.code);
  assert.equal(result.carry, expected.ok ? 0 : 1);
  assert.equal(result.currentIndex, expected.index);
  assert.equal(result.consumed, expected.consumed);
  assert.equal(result.inputReads, result.tokenFetches);
  assert.deepEqual(result.trace, flatten(expected.actions));
  assert.equal(result.outputUsed, result.trace.length);
  assert.equal(result.finalSp, 0xe002);
  assert.equal(result.returnPc, 0xff00);
  assert.equal(result.ix, 0x1357);
  assert.equal(result.iy, 0x2468);
  assert(result.canariesIntact);
  if (expected.ok) {
    assert.equal(result.tokenFetches, tokens.length);
    assert.equal(result.lookaheadFetches, tokens.length + 1);
  } else if (expected.index === tokens.length) {
    assert.equal(result.tokenFetches, expected.consumed);
    assert.equal(result.lookaheadFetches, expected.consumed + 1);
  } else {
    assert.equal(result.tokenFetches, expected.consumed + 1);
    assert.equal(result.lookaheadFetches, result.tokenFetches);
  }
}

async function checkBoth(
  tokens: readonly number[],
  options: Parameters<ParserMachine["run"]>[1] = {},
): Promise<readonly NativeResult[]> {
  const expected = referenceParse(tokens);
  const results = (await machines()).map((machine) =>
    machine.run(tokens, options)
  );
  for (const result of results) checkRun(result, tokens, expected);
  assert.deepEqual(results[0]!.trace, results[1]!.trace);
  assert.equal(results[0]!.status, results[1]!.status);
  assert.equal(results[0]!.currentIndex, results[1]!.currentIndex);
  return results;
}

const handTraces: Readonly<Record<string, readonly number[]>> = {
  empty: [],
  atom: [1, 0, 0, 3, 1, 0],
  name: [2, 0, 0, 3, 1, 0],
  "application-one": [
    17,
    1,
    0,
    1,
    1,
    0,
    18,
    2,
    0,
    20,
    3,
    0,
    3,
    3,
    0,
  ],
  "if-two-operand": [
    4,
    2,
    0,
    1,
    2,
    0,
    5,
    3,
    0,
    1,
    3,
    0,
    6,
    4,
    0,
    8,
    4,
    0,
    9,
    5,
    0,
    3,
    5,
    0,
  ],
  "begin-empty": [10, 2, 0, 11, 3, 0, 3, 3, 0],
  "lambda-empty-parameters": [
    12,
    2,
    0,
    14,
    4,
    0,
    1,
    4,
    0,
    15,
    5,
    0,
    16,
    6,
    0,
    3,
    6,
    0,
  ],
};

Deno.test("hand-authored traces preserve action positions", async () => {
  for (const testCase of HAND_CASES) {
    const expected = handTraces[testCase.name];
    if (expected === undefined) continue;
    const results = await checkBoth(testCase.tokens);
    assert.deepEqual(results[0]!.trace, expected, testCase.name);
  }
});

Deno.test("all specified grammar forms and failures agree with the host oracle", async () => {
  for (const testCase of HAND_CASES) await checkBoth(testCase.tokens);
});

Deno.test("consumption and lookahead counts distinguish EOF from token fetches", async () => {
  const atom = (await checkBoth([3]))[0]!;
  assert.equal(atom.tokenFetches, 1);
  assert.equal(atom.consumed, 1);
  assert.equal(atom.lookaheadFetches, 2);
  const failure = (await checkBoth([1, 3]))[0]!;
  assert.equal(failure.status, 128);
  assert.equal(failure.currentIndex, 2);
  assert.equal(failure.tokenFetches, 2);
  assert.equal(failure.consumed, 2);
  assert.equal(failure.lookaheadFetches, 3);
});

Deno.test("depth 31 and 32 are accepted and depth 33 fails at its OPEN", async () => {
  const groups: readonly [
    string,
    (n: number) => number[],
    readonly number[],
  ][] = [
    ["application", nestApplications, [31, 32, 33]],
    ["argument-application", nestArgumentApplications, [31, 32, 33]],
    ["begin-later-body", nestBeginExpressions, [31, 32, 33]],
    // Each lambda has a formal-list OPEN.  30/31/32 wrappers therefore reach
    // actual simultaneous depths 31/32/33 respectively.
    ["lambda", nestLambdas, [30, 31, 32]],
    ["lambda-later-body", nestLambdaLaterBodies, [30, 31, 32]],
    ["if", nestIfs, [31, 32, 33]],
  ];
  for (const [name, build, counts] of groups) {
    for (const [offset, count] of counts.entries()) {
      const tokens = build(count);
      const results = await checkBoth(tokens);
      const expected = referenceParse(tokens);
      if (offset < 2) {
        assert(expected.ok, `${name} depth ${count} unexpectedly failed`);
        assert.equal(results[0]!.status, 0);
        assert.equal(results[1]!.status, 0);
        assert(results[1]!.predictionBytes <= 256);
      } else {
        assert.equal(results[0]!.status, 129);
        assert.equal(results[1]!.status, 129);
        assert.equal(results[0]!.currentIndex, expected.index);
        assert.equal(results[1]!.currentIndex, expected.index);
      }
      assert(results[0]!.stackBytes <= 2048);
      assert(results[1]!.stackBytes <= 2048);
    }
  }
});

Deno.test("generated token fixtures preserve the independent oracle", async () => {
  for (const tokens of generatedTokenLists(256)) await checkBoth(tokens);
});

Deno.test("sink capacity, injected failure and high-address output are guarded", async () => {
  const exhausted = (await machines()).map((machine) =>
    machine.run([3], { outputCapacity: 3 })
  );
  for (const result of exhausted) {
    assert.equal(result.status, 129);
    assert.equal(result.currentIndex, 1);
    assert.deepEqual(result.trace, [1, 0, 0]);
    assert.equal(result.outputUsed, 3);
  }
  const injected = (await machines()).map((machine) =>
    machine.run([3], { injectSinkFailure: true })
  );
  for (const result of injected) {
    assert.equal(result.status, 130);
    assert.equal(result.currentIndex, 0);
    assert.deepEqual(result.trace, []);
    assert.equal(result.outputUsed, 0);
  }
  const high = await checkBoth([3], {
    outputBase: 0xff00,
    outputCapacity: 0xff,
  });
  for (const result of high) {
    assert.equal(result.status, 0);
    assert(result.canariesIntact);
  }
});

Deno.test("high-address exhaustion rejects before wrap or partial record", async () => {
  for (const machine of await machines()) {
    const wrapped = machine.run(Array(43).fill(3), {
      outputBase: 0xff00,
      outputCapacity: 0xff,
    });
    assert.equal(wrapped.status, 129);
    assert.equal(wrapped.currentIndex, 43);
    assert.equal(wrapped.outputUsed, 0xff);
    assert.equal(wrapped.outputWrites, 0xff);
    assert.equal(wrapped.trace.length, 0xff);
    assert(wrapped.canariesIntact);

    const noRecord = machine.run([3], {
      outputBase: 0xfffd,
      outputCapacity: 2,
    });
    assert.equal(noRecord.status, 129);
    assert.equal(noRecord.currentIndex, 0);
    assert.equal(noRecord.outputUsed, 0);
    assert.equal(noRecord.outputWrites, 0);
    assert.deepEqual(noRecord.trace, []);
    assert(noRecord.canariesIntact);
  }
});

Deno.test("output configuration rejects caller return and stack canary overlap", async () => {
  for (const machine of await machines()) {
    for (const outputBase of [0xd7fc, 0xdffc, 0xe000, 0xe002]) {
      assert.throws(
        () => machine.run([3], { outputBase, outputCapacity: 3 }),
        /output or its canaries overlap/,
      );
    }
  }
});

Deno.test("failure is followed by a clean re-entry", async () => {
  for (const machine of await machines()) {
    const failed = machine.run([1, 3]);
    assert.equal(failed.status, 128);
    const recovered = machine.run([3]);
    assert.equal(recovered.status, 0);
    assert.deepEqual(recovered.trace, [1, 0, 0, 3, 1, 0]);
    assert.equal(recovered.tokenFetches, 1);
    assert.equal(recovered.consumed, 1);
    assert.equal(recovered.currentIndex, 1);
    assert(recovered.canariesIntact);
  }
});

Deno.test("discard mode keeps parser memory constant for a long flat stream", async () => {
  for (const machine of await machines()) {
    const short = machine.run(Array(32).fill(3), {
      discardActions: true,
      outputCapacity: 3,
    });
    const long = machine.run(Array(300).fill(3), {
      discardActions: true,
      outputCapacity: 3,
    });
    assert.equal(short.status, 0);
    assert.equal(long.status, 0);
    assert.equal(short.outputWrites, 0);
    assert.equal(long.outputWrites, 0);
    assert.equal(short.trace.length, 0);
    assert.equal(long.trace.length, 0);
    assert.equal(short.stackBytes, long.stackBytes);
    assert.equal(short.predictionBytes, long.predictionBytes);
    assert.equal(long.outputUsed, 300 * 6);
    assert.equal(long.tokenFetches, 300);
    assert.equal(long.consumed, 300);
    assert(long.canariesIntact);
  }
});

Deno.test("candidate and shared accounts stay inside the provisional limits", async () => {
  for (const candidate of ["handwritten", "table"] as const) {
    const machine = (await machines()).find((item) =>
      item.candidate === candidate
    )!;
    const account = machine.account();
    assert(account.candidateImmutable <= 2048);
    assert(account.candidateWorkspace <= 512);
    assert(account.explicitStack <= 256);
    assert(account.commonCodeAndImmutable > 0);
    assert(account.commonWorkspace > 0);
    console.log(JSON.stringify({ candidate, account }));
  }
});
