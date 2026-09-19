/** Generate the checked-in native parser correctness/compaction evidence. */
import {
  type Candidate,
  type NativeResult,
  ParserMachine,
} from "./parser-machine.ts";
import { buildCompactionEvidence } from "./parser-compaction.ts";
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

const HERE = new URL("./", import.meta.url);
const SOURCE_FILES = [
  "common.asm",
  "handwritten.asm",
  "handwritten-core.asm",
  "handwritten-baseline.asm",
  "handwritten-baseline-core.asm",
  "handwritten-compact-loop.asm",
  "handwritten-compact-loop-core.asm",
  "handwritten-compact-value.asm",
  "handwritten-compact-value-core.asm",
  "table.asm",
  "table-core.asm",
  "table-baseline.asm",
  "table-baseline-core.asm",
  "table-compact-boundary.asm",
  "table-compact-boundary-core.asm",
  "table-compact-dispatch.asm",
  "table-compact-dispatch-core.asm",
  "parser-model.ts",
  "parser-machine.ts",
  "parser-compaction.ts",
  "parser_test.ts",
  "parser-evidence.ts",
];

async function hash(bytes: Uint8Array): Promise<string> {
  // Copy so the view has an ordinary ArrayBuffer under Deno's strict types.
  const digest = await crypto.subtle.digest(
    "SHA-256",
    bytes.slice().buffer as ArrayBuffer,
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

async function revision(repo: URL): Promise<string> {
  const head = (await Deno.readTextFile(new URL(".git/HEAD", repo))).trim();
  if (!head.startsWith("ref: ")) return head;
  return (await Deno.readTextFile(
    new URL(`.git/${head.slice(5)}`, repo),
  )).trim();
}

interface CaseRun {
  readonly name: string;
  readonly tokenCount: number;
  readonly options: Parameters<ParserMachine["run"]>[1];
  readonly expected: {
    readonly ok: boolean;
    readonly code: number;
    readonly index: number;
    readonly actionCount: number;
  };
  readonly candidates: Readonly<Record<Candidate, NativeResult>>;
}

function resultFor(
  machine: ParserMachine,
  tokens: readonly number[],
  options: Parameters<ParserMachine["run"]>[1] = {},
): NativeResult {
  return machine.run(tokens, options);
}

function compactResult(result: NativeResult): Record<string, unknown> {
  return {
    ok: result.ok,
    status: result.status,
    carry: result.carry,
    actionBytes: result.outputUsed,
    consumed: result.consumed,
    tokenFetches: result.tokenFetches,
    lookaheadFetches: result.lookaheadFetches,
    currentIndex: result.currentIndex,
    instructions: result.steps,
    cycles: result.cycles,
    hardwareStackBytes: result.stackBytes,
    predictionStackBytes: result.predictionBytes,
    outputWrites: result.outputWrites,
    nativeWrites: result.nativeWrites,
    inputReads: result.inputReads,
    returnPc: result.returnPc,
    finalSp: result.finalSp,
    ix: result.ix,
    iy: result.iy,
    canariesIntact: result.canariesIntact,
  };
}

export async function buildEvidence(): Promise<Record<string, unknown>> {
  const [handwritten, table] = await Promise.all([
    ParserMachine.open("handwritten"),
    ParserMachine.open("table"),
  ]);
  const machines: Readonly<Record<Candidate, ParserMachine>> = {
    handwritten,
    table,
  };
  const cases: Array<
    readonly [string, readonly number[], Parameters<ParserMachine["run"]>[1]]
  > = HAND_CASES.map((testCase) => [testCase.name, testCase.tokens, {}]);
  cases.push(
    ["depth31-app", nestApplications(31), {}],
    ["depth32-app", nestApplications(32), {}],
    ["depth33-app", nestApplications(33), {}],
    ["depth31-argument-app", nestArgumentApplications(31), {}],
    ["depth32-argument-app", nestArgumentApplications(32), {}],
    ["depth33-argument-app", nestArgumentApplications(33), {}],
    ["depth31-begin-later-body", nestBeginExpressions(31), {}],
    ["depth32-begin-later-body", nestBeginExpressions(32), {}],
    ["depth33-begin-later-body", nestBeginExpressions(33), {}],
    ["depth31-lambda", nestLambdas(30), {}],
    ["depth32-lambda", nestLambdas(31), {}],
    ["depth33-lambda", nestLambdas(32), {}],
    ["depth31-lambda-later-body", nestLambdaLaterBodies(30), {}],
    ["depth32-lambda-later-body", nestLambdaLaterBodies(31), {}],
    ["depth33-lambda-later-body", nestLambdaLaterBodies(32), {}],
    ["depth31-if", nestIfs(31), {}],
    ["depth32-if", nestIfs(32), {}],
    ["depth33-if", nestIfs(33), {}],
    ["flat-discard-300", Array(300).fill(3), {
      discardActions: true,
      outputCapacity: 3,
    }],
    ["sink-capacity", [3], { outputCapacity: 3 }],
    ["sink-injected", [3], { injectSinkFailure: true }],
    ["sink-high-address", [3], { outputBase: 0xff00, outputCapacity: 0xff }],
    ["sink-high-wrap", Array(43).fill(3), {
      outputBase: 0xff00,
      outputCapacity: 0xff,
    }],
    ["sink-high-no-record", [3], {
      outputBase: 0xfffd,
      outputCapacity: 2,
    }],
  );
  for (const [index, tokens] of generatedTokenLists(64).entries()) {
    cases.push([`generated-${index.toString().padStart(3, "0")}`, tokens, {}]);
  }
  const measured: CaseRun[] = [];
  for (const [name, tokens, options] of cases) {
    const expected = referenceParse(tokens);
    const results = {
      handwritten: resultFor(handwritten, tokens, options),
      table: resultFor(table, tokens, options),
    };
    measured.push({
      name,
      tokenCount: tokens.length,
      options,
      expected: {
        ok: expected.ok,
        code: expected.code,
        index: expected.index,
        actionCount: expected.actions.length,
      },
      candidates: results,
    });
  }
  const accounts = Object.fromEntries(
    (Object.keys(machines) as Candidate[]).map((candidate) => [
      candidate,
      machines[candidate].account(),
    ]),
  );
  const summary = Object.fromEntries(
    (Object.keys(machines) as Candidate[]).map((candidate) => {
      const rows = measured.map((row) => row.candidates[candidate]);
      return [candidate, {
        maxInstructions: Math.max(...rows.map((row) => row.steps)),
        maxCycles: Math.max(...rows.map((row) => row.cycles)),
        maxHardwareStackBytes: Math.max(...rows.map((row) => row.stackBytes)),
        maxPredictionStackBytes: Math.max(
          ...rows.map((row) => row.predictionBytes),
        ),
        allCanariesIntact: rows.every((row) => row.canariesIntact),
        allReturnPcsRestored: rows.every((row) => row.returnPc === 0xff00),
        allStacksRestored: rows.every((row) => row.finalSp === 0xe002),
      }];
    }),
  );
  const sourceHashes: Record<string, string> = {};
  for (const file of SOURCE_FILES) {
    sourceHashes[file] = await hash(await Deno.readFile(new URL(file, HERE)));
  }
  const compaction = await buildCompactionEvidence();
  const baselineEvidence = await hash(
    await Deno.readFile(new URL("parser-evidence-baseline.json", HERE)),
  );
  const skateRoot = new URL("../../../../", HERE);
  const atomRoot = new URL("../../../../../atom/", HERE);
  const z80Harness = new URL("../../../../tests/z80.ts", HERE);
  return {
    schema: "c0-native-parser-compaction-1",
    date: "2026-09-19",
    baselineEvidence: {
      path: "parser-evidence-baseline.json",
      sha256: baselineEvidence,
      schema: "c0-native-parser-baseline-1",
    },
    skateRevision: await revision(skateRoot),
    atomRevision: await revision(atomRoot),
    assembler: "ATOM revision540798c",
    cpu: "documented Z80 as executed by Debug80 Runtime",
    tooling: {
      z80Harness: {
        path: "tests/z80.ts",
        sha256: await hash(await Deno.readFile(z80Harness)),
      },
    },
    fixture: {
      inputBase: "0x6000",
      outputBase: "0x8000 (high-address probe 0xff00)",
      stackGuard:
        "0xd800-0xe000 (2048 bytes writable, four-byte outer canaries)",
      parserEntry: "PPARSE at $0100-origin fixture",
    },
    accounting: {
      parserAllowance: 2048,
      candidateWorkspaceAllowance: 512,
      predictionStackAllowance: 256,
      hardwareStackAllowance: 2048,
      traceRecordBytes: 3,
      commonAdapterSinkSeparate: true,
    },
    accounts,
    summary,
    compaction,
    cases: measured.map((row) => ({
      name: row.name,
      tokenCount: row.tokenCount,
      options: row.options,
      expected: row.expected,
      candidates: {
        handwritten: compactResult(row.candidates.handwritten),
        table: compactResult(row.candidates.table),
      },
    })),
    sourceHashes,
    excludedCosts: [
      "tokenization and source text retention",
      "binding resolution and duplicate-name checks",
      "quote/data construction and derived-form lowering",
      "full native emitter, fixups, publication and generated runtime",
    ],
  };
}

if (import.meta.main) {
  const evidence = await buildEvidence();
  await Deno.writeTextFile(
    new URL("parser-evidence.json", HERE),
    JSON.stringify(evidence, null, 2) + "\n",
  );
  console.log(JSON.stringify(evidence, null, 2));
}
