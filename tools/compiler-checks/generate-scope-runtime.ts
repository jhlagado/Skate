/**
 * Generate the checked runtime byte table used by the scope compiler.
 *
 * With `--check`, compare the committed files with a fresh generation instead
 * of writing them, and fail when either has drifted from the runtime source.
 */

import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";

const VALUES_PATH = "src/runtime/values.inc";
const TEMPLATE_PATH = "src/runtime/template.inc";

export interface ScopeRuntimeFiles {
  length: number;
  values: string;
  template: string;
}

/** Assemble src/runtime/image.asm and render values.inc and template.inc. */
export async function generateScopeRuntimeFiles(
  root: URL = new URL("../../", import.meta.url),
): Promise<ScopeRuntimeFiles> {
  const assembled = await assembleAtomProject({
    root: root.pathname,
    entry: "src/runtime/image.asm",
    assembler: undefined,
    target: undefined,
    maxInstructions: 1_000_000_000,
    maxCycles: 10_000_000_000,
    sink: undefined,
  });
  const image = materializeAtomGeneration(assembled.generation);
  if (!image) throw new Error("scope-control runtime produced no image");
  const payload = image.bytes.slice(0x0100);
  const symbols = new Map<string, number>(
    assembled.generation.symbols.map((symbol: {
      name: string;
      value: number;
    }) => [symbol.name.toLowerCase(), symbol.value]),
  );

  function address(name: string): number {
    const value = symbols.get(name.toLowerCase());
    if (value === undefined) {
      throw new Error(`scope-control runtime has no ${name}`);
    }
    return value;
  }

  function offset(name: string): number {
    return address(name) - 0x0100;
  }

  const values = [
    "; Runtime addresses used by the scope-control compiler.",
    `SRTLEN EQU ${payload.length}`,
    `SRTCLP EQU ${offset("SRTCALL") + 1}`,
    `SRTLDA EQU ${address("SRTLOAD")}`,
    `SRTQGET EQU ${address("SRTQGET")}`,
    `SRTSTA EQU ${address("SRTSTORE")}`,
    `SRTSETS EQU ${address("SRTSET")}`,
    `SRTFAL EQU ${address("SRTFALSE")}`,
    `SRTADD EQU ${address("SRTADD")}`,
    `SRTSUB EQU ${address("SRTSUB")}`,
    `SRTMUL EQU ${address("SRTMUL")}`,
    `SRTMAKE EQU ${address("SRTMAKE")}`,
    `SRTINVOK EQU ${address("SRTINVOK")}`,
    `SRTOPINV EQU ${address("SRTOPINV")}`,
    `SRTOTAIL EQU ${address("SRTOTAIL")}`,
    `SRTOTCL EQU ${address("SRTOTCL")}`,
    `SRTOPUSH EQU ${address("SRTOPUSH")}`,
    `SRTNROOT EQU ${address("SRTNROOT")}`,
    `SRTNPOPB EQU ${address("SRTNPOPB")}`,
    `SRTNPOP1 EQU ${address("SRTNPOP1")}`,
    `SRTCECAL EQU ${address("SRTCECAL")}`,
    `SRTTAIL EQU ${address("SRTTAIL")}`,
    `SRTTCALL EQU ${address("SRTTCALL")}`,
    `SRTLOADI EQU ${address("SRTLOADI")}`,
    `SRTSTORI EQU ${address("SRTSTORI")}`,
    `SRTSETI EQU ${address("SRTSETI")}`,
    `SRTCLRI EQU ${address("SRTCLRI")}`,
    `SRTCLRS EQU ${address("SRTCLRS")}`,
    `SRTHEP EQU ${address("SRTHEAPP")}`,
    `SRTIMGE EQU ${offset("SRTIMGE")}`,
    `SRTGBASE EQU ${offset("SRTGBASE")}`,
    `SRTGEND EQU ${offset("SRTGEND")}`,
    `SRTQROOT EQU ${offset("SRTQROOT")}`,
    `SRTQENDR EQU ${offset("SRTQENDR")}`,
    `SRTSYMB EQU ${offset("SRTSYMB")}`,
    `SRTSYME EQU ${offset("SRTSYME")}`,
    `SRTLOW EQU ${address("SRTLOWSP")}`,
    `SRTZERO EQU ${address("SRTZERO")}`,
    `SRTPRI EQU ${address("SRTPRINT")}`,
    `SRTQPUT EQU ${address("SRTQPUT")}`,
    `SRTQBLD EQU ${address("SRTQBLD")}`,
    `SRTCONS EQU ${address("SRTCONS")}`,
    `SRTCAR EQU ${address("SRTCAR")}`,
    `SRTCDR EQU ${address("SRTCDR")}`,
    `SRTPAIRP EQU ${address("SRTPAIRP")}`,
    `SRTNULLP EQU ${address("SRTNULLP")}`,
  ];
  const lines = [
    "; Runtime image generated from image.asm.",
    "SRTIMAGE:",
  ];
  for (let index = 0; index < payload.length; index += 32) {
    const bytes = [...payload.slice(index, index + 32)].map((byte) =>
      `$${byte.toString(16).padStart(2, "0")}`
    );
    lines.push(`        DB ${bytes.join(",")}`);
  }
  lines.push("SRTIEND:");
  return {
    length: payload.length,
    values: values.join("\n") + "\n",
    template: lines.join("\n") + "\n",
  };
}

async function readOptional(url: URL): Promise<string | undefined> {
  try {
    return await Deno.readTextFile(url);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}

if (import.meta.main) {
  const root = new URL("../../", import.meta.url);
  const generated = await generateScopeRuntimeFiles(root);
  const outputs: [string, string][] = [
    [VALUES_PATH, generated.values],
    [TEMPLATE_PATH, generated.template],
  ];
  if (Deno.args.includes("--check")) {
    const stale = [];
    for (const [path, text] of outputs) {
      if (await readOptional(new URL(path, root)) !== text) stale.push(path);
    }
    if (stale.length > 0) {
      console.error(
        `Generated runtime files are out of date: ${stale.join(", ")}\n` +
          "Run `deno task generate:runtime` and commit the result.",
      );
      Deno.exit(1);
    }
    console.log(
      `Scope-control runtime template is current: ${generated.length} bytes`,
    );
  } else {
    for (const [path, text] of outputs) {
      await Deno.writeTextFile(new URL(path, root), text);
    }
    console.log(`Scope-control runtime template: ${generated.length} bytes`);
  }
}
