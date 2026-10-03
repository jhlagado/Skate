// Apply label rename maps across sources, tools, tests and docs.
// Usage: deno run -A apply.ts <repo> <maps-dir> [--dry]
// Map file: { "globals": { "OLD": "NEW" | ".NEW" }, "privates": { "OWNER_OLD": { ".OLD": ".NEW" } } }
import { ENTRIES } from "./demote.ts";
import { includeOrder, scan, walkFiles } from "./labels.ts";

const [root, mapsDir, flag] = Deno.args;
const dry = flag === "--dry";
const globals = new Map<string, string>();
const privates = new Map<string, Map<string, string>>();
for await (const p of walkFiles(mapsDir, [".json"])) {
  const m = JSON.parse(await Deno.readTextFile(p));
  for (const [o, n] of Object.entries<string>(m.globals ?? {})) {
    const O = o.toUpperCase();
    if (O === n.toUpperCase()) continue;
    if (globals.has(O) && globals.get(O)!.toUpperCase() !== n.toUpperCase()) {
      throw new Error(
        `${p}: ${O} mapped twice: ${globals.get(O)} vs ${n}`,
      );
    }
    globals.set(O, n);
  }
  for (
    const [owner, pm] of Object.entries<Record<string, string>>(
      m.privates ?? {},
    )
  ) {
    const k = owner.toUpperCase();
    const mm = privates.get(k) ?? privates.set(k, new Map()).get(k)!;
    for (const [o, n] of Object.entries(pm)) {
      if (o.toUpperCase() !== n.toUpperCase()) mm.set(o.toUpperCase(), n);
    }
  }
}
const goodName = (n: string) => {
  const bare = n.replace(/^\./, "");
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(bare) && bare.length <= 8;
};
for (const [o, n] of globals) {
  if (!goodName(n)) throw new Error(`bad name ${o} -> ${n}`);
}
for (const [owner, pm] of privates) {
  for (const [o, n] of pm) {
    if (!n.startsWith(".") || !goodName(n)) {
      throw new Error(`bad private name ${owner} ${o} -> ${n}`);
    }
  }
}

// Reject maps that would define a name twice in one image or in one
// private scope, before touching any file.
const clashes: string[] = [];
for (const e of ENTRIES) {
  const { defs } = await scan(root, e);
  const seen = new Map<string, string>();
  let oldOwner = "", newOwner = "";
  let scope = new Map<string, string>();
  for (const d of defs) {
    const where = `${d.file}:${d.line + 1}`;
    let name: string;
    if (d.kind === "private") {
      name = (privates.get(oldOwner)?.get(d.name) ?? d.name).toUpperCase();
    } else {
      name = (globals.get(d.name) ?? d.name).toUpperCase();
    }
    if (d.kind === "label") oldOwner = d.name;
    if (name.startsWith(".")) {
      const prior = scope.get(name);
      if (prior && prior !== where) {
        clashes.push(`${e}: ${name} in ${newOwner} at ${prior} and ${where}`);
      }
      scope.set(name, where);
      continue;
    }
    const prior = seen.get(name);
    if (prior && prior !== where) {
      clashes.push(`${e}: ${name} at ${prior} and ${where}`);
    }
    seen.set(name, where);
    if (d.kind === "label") {
      newOwner = name;
      scope = new Map();
    }
  }
}
if (clashes.length) {
  console.log(clashes.join("\n"));
  throw new Error(`${clashes.length} name clashes`);
}

const asmFiles = new Set<string>();
for (const e of ENTRIES) {
  for (const f of await includeOrder(root, e)) asmFiles.add(f);
}
asmFiles.add("src/runtime/template.inc");

const report: string[] = [];
let changedFiles = 0, replacements = 0;

// Index of the comment on a line, or -1, ignoring semicolons in strings.
function commentAt(line: string): number {
  let q: string | null = null;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) {
      if (c === q) q = null;
      continue;
    }
    if (c === ";") return i;
    if (c === '"' || (c === "'" && !/AF$/i.test(line.slice(0, i)))) q = c;
  }
  return -1;
}

// Keep a trailing comment in its column, or one space after longer code.
function realign(before: string, after: string): string {
  const at = commentAt(before);
  if (at <= 0 || before.slice(0, at).trim() === "") return after;
  const now = commentAt(after);
  const code = after.slice(0, now).trimEnd();
  return code.padEnd(Math.max(at, code.length + 1)) + after.slice(now);
}

function rewriteAsm(text: string): string {
  let owner = "";
  return text.split("\n").map((line) => {
    const def = /^([A-Za-z_][A-Za-z0-9_]*):/.exec(line);
    const isEqu = /^[A-Za-z_][A-Za-z0-9_]*:?\s+EQU\b/i.test(line);
    const prevOwner = owner;
    if (def && !isEqu) owner = def[1].toUpperCase();
    if (/^%/.test(line)) return line;
    return realign(line, rewriteLine(line, def, isEqu, prevOwner));
  }).join("\n");

  function rewriteLine(
    line: string,
    def: RegExpExecArray | null,
    isEqu: boolean,
    prevOwner: string,
  ): string {
    // Rewrite identifiers outside string literals; comments included.
    let out = "", i = 0, q: string | null = null, inComment = false;
    while (i < line.length) {
      const c = line[i];
      if (!inComment && q) {
        out += c;
        if (c === q) q = null;
        i++;
        continue;
      }
      if (!inComment && c === ";") inComment = true;
      if (!inComment && (c === '"' || (c === "'" && !/AF$/i.test(out)))) {
        q = c;
        out += c;
        i++;
        continue;
      }
      const m = /^\.?[A-Za-z_][A-Za-z0-9_]*/.exec(line.slice(i));
      const prev = line[i - 1];
      if (m && !(prev && /[A-Za-z0-9_$%]/.test(prev))) {
        const tok = m[0], T = tok.toUpperCase();
        let rep = tok;
        if (tok.startsWith(".")) {
          // Private: the owner is the global in force on this line (the label itself owns a same-line definition).
          const own = def && !isEqu ? owner : (owner || prevOwner);
          const r = privates.get(own)?.get(T);
          if (r) rep = r;
        } else if (!inComment || tok === T) {
          const r = globals.get(T);
          if (r) rep = r;
        }
        if (rep !== tok) replacements++;
        out += rep;
        i += tok.length;
        continue;
      }
      out += c;
      i++;
    }
    return out;
  }
}

function rewriteOther(file: string, text: string): string {
  return text.replace(
    /(?<![A-Za-z0-9_.$])[A-Z_][A-Z0-9_]*(?![A-Za-z0-9_]|\.[A-Za-z])/g,
    (tok, off) => {
      const r = globals.get(tok);
      if (!r || r.startsWith(".")) return tok;
      replacements++;
      const ln = text.slice(0, off).split("\n").length;
      report.push(`${file}:${ln}: ${tok} -> ${r}`);
      return r;
    },
  );
}

for (const f of asmFiles) {
  const t = await Deno.readTextFile(`${root}/${f}`);
  const n = rewriteAsm(t);
  if (n !== t) {
    changedFiles++;
    if (!dry) await Deno.writeTextFile(`${root}/${f}`, n);
  }
}
for (const dir of ["tools", "tests", "docs", "README.md"]) {
  const path = `${root}/${dir}`;
  const it = dir.endsWith(".md")
    ? [path]
    : walkFiles(path, [".ts", ".mjs", ".js", ".md", ".json"]);
  for await (const p of it) {
    const rel = p.slice(root.length + 1);
    // The rename tooling and its plan quote old names on purpose.
    if (rel.startsWith("tools/labels/")) continue;
    if (rel === "docs/label-renaming-plan.md") continue;
    const t = await Deno.readTextFile(p);
    const n = rewriteOther(rel, t);
    if (n !== t) {
      changedFiles++;
      if (!dry) await Deno.writeTextFile(p, n);
    }
  }
}
await Deno.writeTextFile(
  `${root}/build/label-apply-report.txt`,
  report.join("\n") + "\n",
);
console.log(
  `${
    dry ? "would change" : "changed"
  } ${changedFiles} files, ${replacements} replacements, ${report.length} outside asm`,
);
