// Report which runtime routines can write the C register (byte 2 of a value
// in transport), directly or through the routines they call or fall into.
// Usage: deno run -A register-census.ts <repo> [ROUTINE...]
// With no routine names it prints only the total.
import { scan } from "../labels/labels.ts";

type Routine = {
  name: string;
  writes: string[];
  calls: Set<string>;
  restoresBC: boolean;
};

// Instructions that change C (or all of BC).
const WRITES_C =
  /^(LD\s+C\s*,|LD\s+BC\s*,|POP\s+BC|INC\s+B?C\b|DEC\s+B?C\b|LDIR|LDDR|CPIR|CPDR|INIR|INDR|OTIR|OTDR|EXX|IN\s+C|(SRL|SLA|SRA|RR|RL|RRC|RLC)\s+C\b|EX\s+.*BC)/i;
// Error exits never return, so what they clobber does not matter.
const NO_RETURN = new Set(["ERROR", "RT_UNDEF", "OUT_FAIL", "*INDIRECT*"]);
const CONDITION = /^(NZ|Z|NC|C|PO|PE|P|M)\s*,\s*/i;

const [root, ...names] = Deno.args;
const { lines } = await scan(root, "src/runtime/image.asm");
const routines = new Map<string, Routine>();
let current: Routine | undefined;
let flowEnds = true;
for (const line of lines) {
  let code = line.code;
  const label = /^([A-Za-z_][A-Za-z0-9_]*):/.exec(code);
  if (label && !/\bEQU\b/i.test(code)) {
    const next: Routine = {
      name: label[1].toUpperCase(),
      writes: [],
      calls: new Set(),
      restoresBC: false,
    };
    if (current && !flowEnds) current.calls.add(next.name);
    routines.set(next.name, next);
    current = next;
    code = code.slice(label[0].length);
  } else code = code.replace(/^\.[A-Za-z0-9_]+:/, "");
  const text = code.trim();
  if (!current || !text) continue;
  if (/^(DB|DW|DS|DEFB|DEFW|DEFS)\b/i.test(text)) {
    flowEnds = true;
    continue;
  }
  const where = `${line.file}:${line.index + 1} ${text}`;
  if (/^PUSH\s+BC/i.test(text)) current.restoresBC = true;
  if (WRITES_C.test(text)) current.writes.push(where);
  const jump = /^(CALL|JP|JR)\s+(.*)$/i.exec(text);
  if (jump) {
    const target = jump[2].replace(CONDITION, "").trim().toUpperCase();
    if (/^\((HL|IX|IY)\)$/.test(target)) current.calls.add("*INDIRECT*");
    else if (/^(5|0*5H)$/.test(target)) current.writes.push(`${where} (BDOS)`);
    else current.calls.add(target);
  }
  flowEnds = /^(RET|JP|JR)\b/i.test(text) &&
    !/^(RET|JP|JR)\s+(NZ|Z|NC|C|PO|PE|P|M)\b/i.test(text);
}
// A POP BC in a routine that also pushes BC is taken as a restore.
for (const r of routines.values()) {
  if (r.restoresBC) r.writes = r.writes.filter((w) => !/POP\s+BC/i.test(w));
}

function path(name: string, seen = new Set<string>()): string[] {
  const r = routines.get(name);
  if (!r || seen.has(name) || NO_RETURN.has(name)) return [];
  seen.add(name);
  if (r.writes.length) return [name];
  for (const callee of r.calls) {
    const rest = path(callee, seen);
    if (rest.length) return [name, ...rest];
  }
  return [];
}

if (names.length === 0) {
  const count = [...routines.keys()].filter((n) => path(n).length).length;
  console.log(`${count} of ${routines.size} runtime routines can write C`);
}
for (const name of names.map((n) => n.toUpperCase())) {
  if (!routines.has(name)) {
    console.log(`${name.padEnd(9)} not a runtime routine`);
    continue;
  }
  const chain = path(name);
  const first = chain.length ? routines.get(chain.at(-1)!)!.writes[0] : "";
  console.log(
    `${name.padEnd(9)} ${
      chain.length ? `writes C: ${chain.join(" > ")} at ${first}` : "keeps C"
    }`,
  );
}
