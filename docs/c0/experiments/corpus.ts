/** C0 host corpus analyzer; it is not a compiler or target implementation. */
import {
  createNativeSourcePackage,
  parseNativeManifest,
} from "../../../tools/native-source-package.ts";
import { SourceReader } from "../../../tools/reader.ts";
import {
  buildCorpus,
  type CorpusFiles,
  dailyName,
  DATA_COUNT,
  type ExpectedResults,
  expectedResults,
  FIXTURE_DIR,
  GLOBAL_COUNT,
  PART_NAMES,
} from "./corpus-source.ts";

export { DATA_COUNT, GLOBAL_COUNT, PART_NAMES } from "./corpus-source.ts";

interface Table {
  readonly descriptors: Uint8Array;
  readonly pool: Uint8Array;
}
interface Scan {
  readonly forms: number;
  readonly maxDepth: number;
  readonly quoteCount: number;
  readonly integerCount: number;
  readonly symbolIds: readonly number[];
}
export interface CorpusMetrics {
  readonly manifestParts: readonly string[];
  readonly partBytes: Readonly<Record<string, number>>;
  readonly partForms: Readonly<Record<string, number>>;
  readonly sourceBytes: number;
  readonly sourceHash: string;
  readonly partHashes: Readonly<Record<string, string>>;
  readonly globalCount: number;
  readonly ordinaryGlobalNameMax: number;
  readonly ordinaryGlobalNamesAtMax: readonly string[];
  readonly maxIdentifierLength: number;
  readonly maxListDepth: number;
  readonly referencesToLaterGlobals: number;
  readonly allGlobalsUsed: boolean;
  readonly dataReferenceCounts: Readonly<Record<string, number>>;
  readonly readerSymbols: number;
  readonly readerSymbolBytes: number;
  readonly readerStrings: number;
  readonly readerStringBytes: number;
  readonly quotedLiteralOccurrences: number;
  readonly distinctQuotedLiteralContents: number;
  readonly numericLiteralOccurrences: number;
  readonly unmeasured: readonly string[];
  readonly expected: ExpectedResults;
}

function symbolText(table: Table, id: number): string {
  const at = id * 3;
  const offset = table.descriptors[at]! | (table.descriptors[at + 1]! << 8);
  return String.fromCharCode(
    ...table.pool.slice(offset, offset + table.descriptors[at + 2]!),
  );
}

function scan(reader: SourceReader): Scan {
  let depth = 0, maxDepth = 0, forms = 0, quoteCount = 0, integerCount = 0;
  const symbolIds: number[] = [];
  for (const event of reader.events()) {
    if (event.kind === "open") {
      depth++;
      maxDepth = Math.max(maxDepth, depth);
    } else if (event.kind === "close") {
      depth--;
      if (depth === 0) forms++;
    } else if (event.kind === "quote") quoteCount++;
    else if (event.kind === "value" && event.value[0] === 3) integerCount++;
    else if (event.kind === "symbol") symbolIds.push(event.id);
  }
  if (depth !== 0) throw new SyntaxError("source form did not close");
  return { forms, maxDepth, quoteCount, integerCount, symbolIds };
}

function tokens(line: string): string[] {
  return line.split(/[^A-Za-z0-9!?$%&*\/:<=>^_~+.\-]+/).filter(Boolean);
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  return left.length === right.length &&
    left.every((byte, index) => byte === right[index]);
}

async function hash(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(bytes).buffer,
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export async function analyzeCorpus(
  files: CorpusFiles,
): Promise<CorpusMetrics> {
  const names = parseNativeManifest(files.manifest);
  if (names.join("\n") !== PART_NAMES.join("\n")) {
    throw new Error("corpus manifest order or names changed");
  }
  const packageData = createNativeSourcePackage(files.manifest, files.parts);
  const sourceText = new TextDecoder().decode(packageData.bytes);
  const lines = sourceText.split(/\r?\n/).filter((line) => line.length > 0);
  const definitionLines = lines.filter((line) => line.startsWith("(define "));
  const globalNames = definitionLines.map((line) =>
    line.match(/^\(define\s+([^\s()]+)/)?.[1] ?? ""
  );
  if (
    globalNames.some((name) => !name) || globalNames.length !== GLOBAL_COUNT
  ) {
    throw new Error(`expected ${GLOBAL_COUNT} top-level definition headers`);
  }
  if (new Set(globalNames).size !== GLOBAL_COUNT) {
    throw new Error("duplicate user global");
  }
  const index = new Map(lines.flatMap((line, position) => {
    const name = line.match(/^\(define\s+([^\s()]+)/)?.[1];
    return name ? [[name, position] as const] : [];
  }));
  const references = new Map(globalNames.map((name) => [name, 0]));
  let referencesToLaterGlobals = 0;
  for (const [lineIndex, line] of lines.entries()) {
    for (const name of tokens(line)) {
      const target = index.get(name);
      if (target === undefined) continue;
      references.set(name, references.get(name)! + 1);
      if (target > lineIndex) {
        referencesToLaterGlobals++;
      }
    }
  }
  for (const name of globalNames) {
    references.set(name, references.get(name)! - 1);
  }
  const reader = new SourceReader(packageData.bytes, packageData);
  const packageScan = scan(reader);
  const symbols = reader.symbols.snapshot();
  const strings = reader.strings.snapshot();
  const symbolNames = Array.from(
    { length: symbols.descriptors.length / 3 },
    (_, id) => symbolText(symbols, id),
  );
  const maxGlobalName = Math.max(...globalNames.map((name) => name.length));
  const quoted = new Set(
    sourceText.match(/'\([^()\r\n]*\)/g) ?? [],
  );
  const partBytes: Record<string, number> = {};
  const partForms: Record<string, number> = {};
  const partHashes: Record<string, string> = {};
  for (const name of names) {
    const bytes = files.parts.get(name);
    if (!bytes) throw new Error(`missing ${name}`);
    const partReader = new SourceReader(bytes, name);
    partBytes[name] = bytes.length;
    partForms[name] = scan(partReader).forms;
    partHashes[name] = await hash(bytes);
  }
  return {
    manifestParts: names,
    partBytes,
    partForms,
    sourceBytes: packageData.bytes.length,
    sourceHash: await hash(packageData.bytes),
    partHashes,
    globalCount: globalNames.length,
    ordinaryGlobalNameMax: maxGlobalName,
    ordinaryGlobalNamesAtMax: globalNames.filter((name) =>
      name.length === maxGlobalName
    ),
    maxIdentifierLength: Math.max(...symbolNames.map((name) => name.length)),
    maxListDepth: packageScan.maxDepth,
    referencesToLaterGlobals,
    allGlobalsUsed: [...references.values()].every((count) => count > 0),
    dataReferenceCounts: Object.fromEntries(
      Array.from({ length: DATA_COUNT }, (_, offset) => {
        const name = dailyName(offset + 1);
        return [name, references.get(name) ?? 0];
      }),
    ),
    readerSymbols: symbols.descriptors.length / 3,
    readerSymbolBytes: symbols.pool.length,
    readerStrings: strings.descriptors.length / 4,
    readerStringBytes: strings.pool.length,
    quotedLiteralOccurrences: packageScan.quoteCount,
    distinctQuotedLiteralContents: quoted.size,
    numericLiteralOccurrences: packageScan.integerCount,
    unmeasured: [
      "native parser, fixup and stack storage",
      "target code, runtime and live-heap capacity",
      "target execution time and tail-call stack behavior",
    ],
    expected: expectedResults(),
  };
}

export async function writeCorpusFixture(): Promise<CorpusMetrics> {
  const files = buildCorpus();
  await Deno.mkdir(FIXTURE_DIR, { recursive: true });
  for (const [name, bytes] of files.parts) {
    await Deno.writeFile(new URL(name, FIXTURE_DIR), bytes);
  }
  await Deno.writeFile(new URL("WEATHER.SKM", FIXTURE_DIR), files.manifest);
  const metrics = await analyzeCorpus(files);
  await Deno.writeTextFile(
    new URL("./corpus-evidence.json", import.meta.url),
    JSON.stringify(metrics, null, 2) + "\n",
  );
  return metrics;
}

export async function checkCorpusFixture(): Promise<CorpusMetrics> {
  const expected = buildCorpus();
  const manifest = await Deno.readFile(new URL("WEATHER.SKM", FIXTURE_DIR));
  if (!sameBytes(manifest, expected.manifest)) {
    throw new Error("checked-in manifest differs from deterministic corpus");
  }
  const parts = new Map<string, Uint8Array>();
  for (const name of PART_NAMES) {
    const actual = await Deno.readFile(new URL(name, FIXTURE_DIR));
    if (!sameBytes(actual, expected.parts.get(name)!)) {
      throw new Error(`checked-in ${name} differs from deterministic corpus`);
    }
    parts.set(name, actual);
  }
  return analyzeCorpus({ manifest, parts });
}

if (import.meta.main) {
  const metrics = Deno.args.includes("--write")
    ? await writeCorpusFixture()
    : await checkCorpusFixture();
  console.log(JSON.stringify(metrics, null, 2));
}
