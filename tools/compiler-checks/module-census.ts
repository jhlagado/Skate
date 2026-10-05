/**
 * Report where the compiler and runtime bytes are, by directory and by file.
 *
 * Each label's span runs to the next label in address order, so a file's
 * total is the bytes its labels cover.  Only labels defined in files that an
 * image actually includes are counted, so runtime addresses the compiler
 * imports as EQUs are not mistaken for its own code.
 */

import { loadAssembly } from "../../tests/z80.ts";

// Collect the files an entry includes, directly or through other includes.
async function includedFiles(
  path: string,
  found = new Set<string>(),
): Promise<Set<string>> {
  if (found.has(path)) return found;
  found.add(path);
  const text = await Deno.readTextFile(path);
  const directory = path.replace(/\/[^/]*$/, "");
  for (const match of text.matchAll(/^\s*%INCLUDE\s+"([^"]+)"/gim)) {
    const resolved: string[] = [];
    for (const part of `${directory}/${match[1]}`.split("/")) {
      if (part === "..") resolved.pop();
      else if (part !== ".") resolved.push(part);
    }
    await includedFiles(resolved.join("/"), found);
  }
  return found;
}

const topFiles = Number(
  Deno.args.find((argument) => argument.startsWith("--top="))?.slice(6) ?? 25,
);

for (
  const [name, path] of [
    ["compiler", "src/compiler/scope/compiler.asm"],
    ["runtime", "src/runtime/image.asm"],
  ]
) {
  const labelFile = new Map<string, string>();
  for (const file of await includedFiles(path)) {
    for (const line of (await Deno.readTextFile(file)).split("\n")) {
      const match = line.match(/^([A-Za-z_.][A-Za-z0-9_.]*):/);
      if (match && !/\bEQU\b/i.test(line)) {
        labelFile.set(match[1].toLowerCase(), file);
      }
    }
  }
  const { image, symbols } = await loadAssembly(path);
  const end = image.base + image.bytes.length;
  const labels = [...symbols]
    .filter(([label, address]) =>
      labelFile.has(label) && address >= 0x100 && address < end
    )
    .sort((left, right) => left[1] - right[1]);
  const byFile = new Map<string, number>();
  const byDirectory = new Map<string, number>();
  for (let index = 0; index < labels.length; index += 1) {
    const span = (index + 1 < labels.length ? labels[index + 1][1] : end) -
      labels[index][1];
    const file = labelFile.get(labels[index][0])!;
    byFile.set(file, (byFile.get(file) ?? 0) + span);
    const directory = file.split("/").slice(0, 3).join("/").replace(
      /\.(asm|inc)$/,
      "",
    );
    byDirectory.set(directory, (byDirectory.get(directory) ?? 0) + span);
  }
  console.log(`\n## ${name}: ${image.bytes.length - 0x100} B after 0100H`);
  for (
    const [directory, bytes] of [...byDirectory].sort((a, b) => b[1] - a[1])
  ) {
    console.log(String(bytes).padStart(6), directory);
  }
  console.log(`-- largest ${topFiles} files`);
  for (
    const [file, bytes] of [...byFile].sort((a, b) => b[1] - a[1]).slice(
      0,
      topFiles,
    )
  ) {
    console.log(String(bytes).padStart(6), file);
  }
}
