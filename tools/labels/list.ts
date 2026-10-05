// List every definition in the named files with its rename status.
// Usage: deno run -A list.ts <repo> <file>...
// Each label prints as KEEP (stays global; "pinned" when a tool or test
// looks it up) or PRIV (may become private) with the kept global that would
// own it, plus the files that reference it from elsewhere.
import { analyse, ENTRIES } from "./demote.ts";
import { scan } from "./labels.ts";

const [root, ...files] = Deno.args;
const wanted = new Set(files.map((f) => f.replace(/^\.\//, "")));
const res = await analyse(root);
const done = new Set<string>();
for (const [i, r] of res.entries()) {
  const { defs, refs } = await scan(root, ENTRIES[i]);
  const demoted = new Set(r.demote.map((d) => d.order));
  const users = new Map<string, Set<string>>();
  for (const ref of refs) {
    if (ref.privateRef) continue;
    const s = users.get(ref.name) ?? users.set(ref.name, new Set()).get(
      ref.name,
    )!;
    s.add(ref.file);
  }
  let owner = "";
  for (const d of defs) {
    const key = `${d.file}:${d.line}`;
    if (d.kind === "label" && !demoted.has(d.order)) owner = d.name;
    if (!wanted.has(d.file) || done.has(key)) continue;
    done.add(key);
    const elsewhere = [...(users.get(d.name) ?? [])].filter((f) =>
      f !== d.file
    );
    let status: string;
    if (d.kind === "equ") status = "EQU ";
    else if (d.kind === "private") status = `priv of ${owner}`;
    else if (demoted.has(d.order)) status = `PRIV under ${owner}`;
    else status = "KEEP";
    const pinned = r.pinned.has(d.name) ? " pinned" : "";
    console.log(
      `${d.file}:${d.line + 1}\t${d.name}\t${status}${pinned}${
        elsewhere.length ? "\tused in " + elsewhere.join(" ") : ""
      }`,
    );
  }
}
