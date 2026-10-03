// Reassemble every entry and require byte-identical images and preserved symbol values.
// Usage: deno run -A verify.ts <repo> <baseline.json> <maps-dir>
import { walkFiles } from "./labels.ts";

type Print = {
  error?: string;
  hash: string;
  length: number;
  symbols: [string, number][];
};
const [root, basePath, mapsDir] = Deno.args;
const base = JSON.parse(await Deno.readTextFile(basePath));
const globals = new Map<string, string>();
for await (const p of walkFiles(mapsDir, [".json"])) {
  const m = JSON.parse(await Deno.readTextFile(p));
  for (const [o, n] of Object.entries<string>(m.globals ?? {})) {
    globals.set(o.toUpperCase(), n.toUpperCase());
  }
}
const cmd = new Deno.Command("deno", {
  args: [
    "run",
    "--config",
    `${root}/deno.runtime.json`,
    "-A",
    `${root}/tools/.fingerprint.ts`,
    root,
  ],
  stdout: "piped",
  stderr: "piped",
});
await Deno.copyFile(
  new URL("./fingerprint.ts", import.meta.url),
  `${root}/tools/.fingerprint.ts`,
);
const out = await cmd.output();
await Deno.remove(`${root}/tools/.fingerprint.ts`);
const now = JSON.parse(new TextDecoder().decode(out.stdout));
let ok = true;
for (const [entry, b] of Object.entries<Print>(base)) {
  const n: Print = now[entry];
  if (n.error) {
    console.log(`FAIL ${entry}: ${n.error.slice(0, 2000)}`);
    ok = false;
    continue;
  }
  if (n.hash !== b.hash) {
    console.log(`FAIL ${entry}: image differs (${b.length} -> ${n.length})`);
    ok = false;
  }
  const syms = new Map<string, number>(n.symbols);
  let missing = 0;
  for (const [name, value] of b.symbols) {
    if (name.startsWith(".")) continue;
    const to = globals.get(name) ?? name;
    if (to.startsWith(".")) continue;
    if (syms.get(to) !== value) {
      if (missing++ < 10) {
        console.log(
          `FAIL ${entry}: ${name} -> ${to} = ${syms.get(to)} expected ${value}`,
        );
      }
      ok = false;
    }
  }
  console.log(
    `${entry}: ${n.length} bytes, ${n.symbols.length} symbols${
      n.hash === b.hash ? ", identical" : ""
    }`,
  );
}
console.log(ok ? "VERIFIED" : "FAILED");
if (!ok) Deno.exit(1);
