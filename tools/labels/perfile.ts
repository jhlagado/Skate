import { analyse } from "./demote.ts";
const res = await analyse(Deno.args[0]);
const rows = new Map<
  string,
  { keep: number; demote: number; equ: number; priv: number; sample: string[] }
>();
for (const r of res) {
  for (const d of r.defs) {
    const row = rows.get(d.file) ??
      rows.set(d.file, { keep: 0, demote: 0, equ: 0, priv: 0, sample: [] }).get(
        d.file,
      )!;
    if (d.kind === "equ") row.equ++;
    if (d.kind === "private") row.priv++;
  }
}
for (const r of res) {
  for (const d of r.keep) {
    const x = rows.get(d.file)!;
    x.keep++;
    if (x.sample.length < 6) x.sample.push(d.name);
  }
  for (const d of r.demote) rows.get(d.file)!.demote++;
}
for (const [f, x] of [...rows].sort()) {
  console.log(
    f.padEnd(55),
    String(x.keep).padStart(4),
    String(x.demote).padStart(4),
    String(x.equ).padStart(3),
    String(x.priv).padStart(3),
    x.sample.join(" "),
  );
}
