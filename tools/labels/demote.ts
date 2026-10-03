// Find global labels that can become private: every reference lies inside the
// segment between the surrounding labels that stay global, in the same file.
import { Def, scan, walkFiles } from "./labels.ts";

export const ENTRIES = [
  "src/runtime/image.asm",
  "src/compiler/scope/compiler.asm",
  "tests/cpm-effects.asm",
];

export async function externalNames(root: string) {
  const names = new Set<string>();
  for (const dir of ["tools", "tests"]) {
    for await (
      const p of walkFiles(`${root}/${dir}`, [".ts", ".mjs", ".js"])
    ) {
      if (p.includes("/labels/")) continue;
      const text = await Deno.readTextFile(p);
      for (const m of text.matchAll(/[A-Za-z_][A-Za-z0-9_]*/g)) {
        names.add(m[0].toUpperCase());
      }
    }
  }
  return names;
}

export async function analyse(root: string) {
  const ext = await externalNames(root);
  const result: { entry: string; demote: Def[]; keep: Def[]; defs: Def[] }[] =
    [];
  for (const entry of ENTRIES) {
    const { defs, refs, lines, files } = await scan(root, entry);
    const labels = defs.filter((d) => d.kind === "label");
    const refsBy = new Map<string, number[]>();
    for (const r of refs) {
      if (!r.privateRef) {
        (refsBy.get(r.name) ?? refsBy.set(r.name, []).get(r.name)!).push(
          r.order,
        );
      }
    }
    const fileOf = new Map(labels.map((d) => [d.order, d.file]));
    const fileEnd = new Map<string, number>();
    for (const l of lines) fileEnd.set(l.file, (fileEnd.get(l.file) ?? 0) + 1);
    {
      let acc = 0;
      for (const f of files) {
        acc += fileEnd.get(f)!;
        fileEnd.set(f, acc);
      }
    }
    const kept = labels.map(() => true);
    const pinned = (d: Def) => ext.has(d.name) || d.file.endsWith(".inc");
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = 0; i < labels.length; i++) {
        if (!kept[i] || pinned(labels[i])) continue;
        let p = i - 1;
        while (p >= 0 && !kept[p]) p--;
        let n = i + 1;
        while (n < labels.length && !kept[n]) n++;
        if (p < 0 || labels[p].file !== labels[i].file) continue; // needs an owning global in this file
        const lo = labels[p].order;
        const hi = n < labels.length && labels[n].file === labels[i].file
          ? labels[n].order
          : fileEnd.get(labels[i].file)!;
        const rs = refsBy.get(labels[i].name) ?? [];
        if (rs.every((o) => o > lo && o < hi)) {
          kept[i] = false;
          changed = true;
        }
      }
    }
    void fileOf;
    result.push({
      entry,
      defs,
      demote: labels.filter((_, i) => !kept[i]),
      keep: labels.filter((_, i) => kept[i]),
    });
  }
  return result;
}

if (import.meta.main) {
  const res = await analyse(Deno.args[0]);
  for (const r of res) {
    const equs = r.defs.filter((d) => d.kind === "equ").length;
    console.log(
      r.entry,
      "labels",
      r.demote.length + r.keep.length,
      "demotable",
      r.demote.length,
      "kept",
      r.keep.length,
      "equ",
      equs,
    );
  }
}
