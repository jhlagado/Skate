/** Measure bounded structural parser variants against the accepted baseline. */
import assert from "node:assert/strict";
import {
  type Candidate,
  type NativeResult,
  ParserMachine,
  type RunOptions,
} from "./parser-machine.ts";
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
} from "./parser-model.ts";

const ROOT = "docs/c0/experiments/parser/";

interface VariantSpec {
  readonly name: string;
  readonly candidate: Candidate;
  readonly entry: string;
  readonly kind: "baseline" | "candidate";
}

interface Fixture {
  readonly name: string;
  readonly tokens: readonly number[];
  readonly options: RunOptions;
}

interface VariantMeasurement {
  readonly variant: string;
  readonly candidate: Candidate;
  readonly account: ReturnType<ParserMachine["account"]>;
  readonly maxInstructions: number;
  readonly maxCycles: number;
  readonly maxHardwareStackBytes: number;
  readonly maxPredictionStackBytes: number;
  readonly totalInstructions: number;
  readonly totalCycles: number;
  readonly cases: Readonly<Record<string, NativeResult>>;
}

const VARIANTS: readonly VariantSpec[] = [
  {
    name: "handwritten-baseline",
    candidate: "handwritten",
    entry: `${ROOT}handwritten-baseline.asm`,
    kind: "baseline",
  },
  {
    name: "handwritten-shared-loop",
    candidate: "handwritten",
    entry: `${ROOT}handwritten-compact-loop.asm`,
    kind: "candidate",
  },
  {
    name: "handwritten-shared-value-tail",
    candidate: "handwritten",
    entry: `${ROOT}handwritten-compact-value.asm`,
    kind: "candidate",
  },
  {
    name: "table-baseline",
    candidate: "table",
    entry: `${ROOT}table-baseline.asm`,
    kind: "baseline",
  },
  {
    name: "table-shared-dispatch",
    candidate: "table",
    entry: `${ROOT}table-compact-dispatch.asm`,
    kind: "candidate",
  },
  {
    name: "table-zero-boundaries",
    candidate: "table",
    entry: `${ROOT}table-compact-boundary.asm`,
    kind: "candidate",
  },
];

function fixtures(): readonly Fixture[] {
  const result: Fixture[] = HAND_CASES.map((testCase) => ({
    name: testCase.name,
    tokens: testCase.tokens,
    options: {},
  }));
  const depths: readonly [
    string,
    (depth: number) => number[],
    readonly number[],
  ][] = [
    ["application", nestApplications, [31, 32, 33]],
    ["argument-application", nestArgumentApplications, [31, 32, 33]],
    ["begin-later-body", nestBeginExpressions, [31, 32, 33]],
    ["lambda", nestLambdas, [30, 31, 32]],
    ["lambda-later-body", nestLambdaLaterBodies, [30, 31, 32]],
    ["if", nestIfs, [31, 32, 33]],
  ];
  for (const [name, build, counts] of depths) {
    for (const count of counts) {
      result.push({
        name: `depth-${count}-${name}`,
        tokens: build(count),
        options: {},
      });
    }
  }
  result.push(
    {
      name: "flat-discard-300",
      tokens: Array(300).fill(3),
      options: { discardActions: true, outputCapacity: 3 },
    },
    { name: "sink-capacity", tokens: [3], options: { outputCapacity: 3 } },
    {
      name: "sink-injected",
      tokens: [3],
      options: { injectSinkFailure: true },
    },
    {
      name: "sink-high-address",
      tokens: [3],
      options: { outputBase: 0xff00, outputCapacity: 0xff },
    },
    {
      name: "sink-high-wrap",
      tokens: Array(43).fill(3),
      options: { outputBase: 0xff00, outputCapacity: 0xff },
    },
    {
      name: "sink-high-no-record",
      tokens: [3],
      options: { outputBase: 0xfffd, outputCapacity: 2 },
    },
  );
  for (const [index, tokens] of generatedTokenLists(64).entries()) {
    result.push({
      name: `generated-${index.toString().padStart(3, "0")}`,
      tokens,
      options: {},
    });
  }
  return result;
}

function equivalent(
  left: NativeResult,
  right: NativeResult,
  context: string,
): void {
  for (
    const field of [
      "ok",
      "status",
      "carry",
      "consumed",
      "tokenFetches",
      "lookaheadFetches",
      "currentIndex",
      "outputUsed",
      "outputWrites",
      "returnPc",
      "finalSp",
      "ix",
      "iy",
      "canariesIntact",
      "inputReads",
    ] as const
  ) {
    assert.equal(left[field], right[field], `${context}: ${field} differs`);
  }
  assert.deepEqual(left.trace, right.trace, `${context}: trace differs`);
}

function checkAgainstOracle(result: NativeResult, fixture: Fixture): void {
  if (
    fixture.options.outputCapacity !== undefined ||
    fixture.options.injectSinkFailure
  ) return;
  const expected = referenceParse(fixture.tokens);
  assert.equal(result.ok, expected.ok, `${fixture.name} success`);
  assert.equal(result.status, expected.ok ? 0 : expected.code, fixture.name);
  assert.equal(result.currentIndex, expected.index, fixture.name);
}

async function measure(
  spec: VariantSpec,
  allFixtures: readonly Fixture[],
): Promise<VariantMeasurement> {
  const machine = await ParserMachine.open(spec.candidate, spec.entry);
  const cases: Record<string, NativeResult> = {};
  for (const fixture of allFixtures) {
    const result = machine.run(fixture.tokens, fixture.options);
    checkAgainstOracle(result, fixture);
    cases[fixture.name] = result;
  }
  const rows = Object.values(cases);
  return {
    variant: spec.name,
    candidate: spec.candidate,
    account: machine.account(),
    maxInstructions: Math.max(...rows.map((row) => row.steps)),
    maxCycles: Math.max(...rows.map((row) => row.cycles)),
    maxHardwareStackBytes: Math.max(...rows.map((row) => row.stackBytes)),
    maxPredictionStackBytes: Math.max(
      ...rows.map((row) => row.predictionBytes),
    ),
    totalInstructions: rows.reduce((sum, row) => sum + row.steps, 0),
    totalCycles: rows.reduce((sum, row) => sum + row.cycles, 0),
    cases,
  };
}

function publicMeasurement(
  measurement: VariantMeasurement,
): Record<string, unknown> {
  return {
    variant: measurement.variant,
    candidate: measurement.candidate,
    account: measurement.account,
    maxInstructions: measurement.maxInstructions,
    maxCycles: measurement.maxCycles,
    maxHardwareStackBytes: measurement.maxHardwareStackBytes,
    maxPredictionStackBytes: measurement.maxPredictionStackBytes,
    totalInstructions: measurement.totalInstructions,
    totalCycles: measurement.totalCycles,
  };
}

function delta(
  measurement: VariantMeasurement,
  baseline: VariantMeasurement,
): Record<string, number> {
  return {
    candidateImmutable: measurement.account.candidateImmutable -
      baseline.account.candidateImmutable,
    candidateWorkspace: measurement.account.candidateWorkspace -
      baseline.account.candidateWorkspace,
    maxHardwareStackBytes: measurement.maxHardwareStackBytes -
      baseline.maxHardwareStackBytes,
    maxPredictionStackBytes: measurement.maxPredictionStackBytes -
      baseline.maxPredictionStackBytes,
    maxInstructions: measurement.maxInstructions - baseline.maxInstructions,
    maxCycles: measurement.maxCycles - baseline.maxCycles,
    totalInstructions: measurement.totalInstructions -
      baseline.totalInstructions,
    totalCycles: measurement.totalCycles - baseline.totalCycles,
  };
}

export async function buildCompactionEvidence(): Promise<
  Record<string, unknown>
> {
  const allFixtures = fixtures();
  const measurements: VariantMeasurement[] = [];
  for (const spec of VARIANTS) {
    measurements.push(await measure(spec, allFixtures));
  }
  const retainedTable = await measure({
    name: "table-retained-combined",
    candidate: "table",
    entry: `${ROOT}table.asm`,
    kind: "candidate",
  }, allFixtures);
  for (const candidate of ["handwritten", "table"] as const) {
    const baseline = measurements.find((row) =>
      row.candidate === candidate && row.variant.endsWith("baseline")
    )!;
    for (
      const variant of measurements.filter((row) =>
        row.candidate === candidate && !row.variant.endsWith("baseline")
      )
    ) {
      for (const fixture of allFixtures) {
        equivalent(
          baseline.cases[fixture.name]!,
          variant.cases[fixture.name]!,
          `${variant.variant}/${fixture.name}`,
        );
      }
    }
  }
  const tableBaseline = measurements.find((row) =>
    row.variant === "table-baseline"
  )!;
  for (const fixture of allFixtures) {
    equivalent(
      tableBaseline.cases[fixture.name]!,
      retainedTable.cases[fixture.name]!,
      `table-retained-combined/${fixture.name}`,
    );
  }
  const baselineByCandidate = Object.fromEntries(
    (["handwritten", "table"] as const).map((candidate) => {
      const row = measurements.find((item) =>
        item.candidate === candidate && item.variant.endsWith("baseline")
      )!;
      return [candidate, row];
    }),
  );
  const variants = measurements.map((measurement) => {
    const baseline = baselineByCandidate[measurement.candidate];
    const decision = measurement.variant.endsWith("baseline")
      ? "baseline"
      : measurement.variant === "handwritten-shared-value-tail" ||
          measurement.variant === "table-shared-dispatch" ||
          measurement.variant === "table-zero-boundaries"
      ? "retained"
      : "rejected";
    const rationale = measurement.variant === "handwritten-shared-loop"
      ? "No immutable-byte saving; adds 64 peak stack bytes and cycles."
      : measurement.variant === "handwritten-shared-value-tail"
      ? "Saves 3 immutable bytes; adds 2 peak stack bytes and measured cycles."
      : measurement.variant === "table-shared-dispatch"
      ? "Saves 4 immutable bytes; size is prioritized over a 0.076% aggregate cycle increase with no stack/workspace increase."
      : measurement.variant === "table-zero-boundaries"
      ? "Saves 2 immutable table bytes with no measured cycle or stack delta."
      : "Accepted baseline for comparison.";
    return {
      ...publicMeasurement(measurement),
      decision,
      rationale,
      delta: delta(measurement, baseline),
    };
  });
  return {
    fixtureCount: allFixtures.length,
    retainedVariants: {
      handwritten: "handwritten-shared-value-tail",
      table: ["table-shared-dispatch", "table-zero-boundaries"],
    },
    rejectedVariants: [
      "handwritten-shared-loop",
    ],
    variants,
    retainedFinal: {
      table: {
        ...publicMeasurement(retainedTable),
        decision: "retained-combined",
        rationale:
          "Both tested table savings compose; immutable size is the priority and no workspace/stack increase occurs.",
        delta: delta(retainedTable, tableBaseline),
      },
    },
  };
}

if (import.meta.main) {
  console.log(JSON.stringify(await buildCompactionEvidence(), null, 2));
}
