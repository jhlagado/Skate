/** Readability gate for the compact rewrite; prototype sources are preserved. */
import { relative } from "node:path";
import { fileURLToPath } from "node:url";

export const NORMAL_LINES = 500;
export const HARD_LINES = 1000;
export const SOURCE_ROOTS = [
  "src",
  "tests/compact",
  "tools/c0",
  "examples/compact",
  "docs/c0/experiments",
  "docs/c0/fixtures",
] as const;
const sourceExtension = /\.(asm|asmi|inc|ts|js|mjs|sk8)$/i;

export function physicalLines(source: string): number {
  if (source.length === 0) return 0;
  const lines = source.split(/\r\n|\r|\n/);
  return lines.length - (lines.at(-1) === "" ? 1 : 0);
}

export function lineStatus(lines: number): "ok" | "review" | "fail" {
  return lines > HARD_LINES ? "fail" : lines > NORMAL_LINES ? "review" : "ok";
}

export interface SourceCount {
  path: string;
  lines: number;
  status: ReturnType<typeof lineStatus>;
}

export async function inspectSources(root: URL): Promise<SourceCount[]> {
  const counts: SourceCount[] = [];
  async function visit(directory: URL): Promise<void> {
    let entries: Deno.DirEntry[];
    try {
      entries = await Array.fromAsync(Deno.readDir(directory));
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) return;
      throw error;
    }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const path = new URL(
        `${encodeURIComponent(entry.name)}${entry.isDirectory ? "/" : ""}`,
        directory,
      );
      if (entry.isSymlink) {
        throw new Error(`Source gate cannot audit symlink: ${path.pathname}`);
      }
      if (entry.isDirectory) await visit(path);
      else if (entry.isFile && sourceExtension.test(entry.name)) {
        const lines = physicalLines(await Deno.readTextFile(path));
        counts.push({
          path: relative(fileURLToPath(root), fileURLToPath(path)),
          lines,
          status: lineStatus(lines),
        });
      }
    }
  }
  for (const scope of SOURCE_ROOTS) await visit(new URL(`${scope}/`, root));
  return counts;
}

if (import.meta.main) {
  const counts = await inspectSources(new URL("../../", import.meta.url));
  for (const item of counts.filter((item) => item.status !== "ok")) {
    console.log(
      `${item.status.toUpperCase()} ${item.path}: ${item.lines} physical lines`,
    );
  }
  const failures = counts.filter((item) => item.status === "fail").length;
  const reviews = counts.filter((item) => item.status === "review").length;
  console.log(
    `${counts.length} compact source files; ${reviews} above ${NORMAL_LINES}; ${failures} above ${HARD_LINES}.`,
  );
  console.log(
    "Source organization only; native size and feasibility are separate gates.",
  );
  if (failures) Deno.exit(1);
}
