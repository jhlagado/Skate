// Label analysis for Skate's ATOM sources.
// Usage: deno run -A labels.ts <repo> <command>
import { dirname, join, relative } from "node:path";

// Yield every file under dir whose extension is listed.
export async function* walkFiles(
  dir: string,
  exts: string[],
): AsyncGenerator<string> {
  for await (const e of Deno.readDir(dir)) {
    const path = join(dir, e.name);
    if (e.isDirectory) yield* walkFiles(path, exts);
    else if (e.isFile && exts.some((x) => e.name.endsWith(x))) yield path;
  }
}

export type Line = { file: string; index: number; text: string; code: string };
export type Def = {
  name: string;
  file: string;
  line: number;
  kind: "label" | "equ" | "private";
  order: number;
};
export type Ref = {
  name: string;
  file: string;
  line: number;
  order: number;
  privateRef: boolean;
};

const ID = /\.?[A-Za-z_][A-Za-z0-9_]*/g;
const MNEMONICS = new Set(
  `ADC ADD AND BIT CALL CCF CP CPD CPDR CPI CPIR CPL DAA DEC DI DJNZ EI EX EXX HALT IM IN INC IND INDR INI INIR JP JR LD LDD LDDR LDI LDIR NEG NOP OR OTDR OTIR OUT OUTD OUTI POP PUSH RES RET RETI RETN RL RLA RLC RLCA RLD RR RRA RRC RRCA RRD RST SBC SCF SET SLA SRA SRL SUB XOR DB DW DS DEFB DEFW DEFS EQU ORG INCBIN ALIGN A B C D E H L I R AF BC DE HL SP IX IY IXH IXL IYH IYL NZ Z NC PO PE P M LOW HIGH AF_`
    .split(/\s+/),
);

export function stripComment(text: string): string {
  let out = "", q: string | null = null;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      out += " ";
      if (c === q) q = null;
      continue;
    }
    if (c === ";") break;
    if (c === "'" || c === '"') {
      // AF' is a register, not a quote.
      if (c === "'" && /AF$/i.test(out.trimEnd())) {
        out += " ";
        continue;
      }
      q = c;
      out += " ";
      continue;
    }
    out += c;
  }
  return out;
}

export async function includeOrder(
  root: string,
  entry: string,
  seen = new Set<string>(),
  order: string[] = [],
) {
  const full = join(root, entry);
  if (seen.has(full)) return order;
  seen.add(full);
  const text = await Deno.readTextFile(full);
  for (const m of text.matchAll(/^%INCLUDE\s+"([^"]+)"/gim)) {
    await includeOrder(
      root,
      relative(root, join(dirname(full), m[1])),
      seen,
      order,
    );
  }
  order.push(relative(root, full));
  return order;
}

export async function scan(root: string, entry: string) {
  const files = await includeOrder(root, entry);
  const lines: Line[] = [];
  const defs: Def[] = [];
  const refs: Ref[] = [];
  let order = 0;
  for (const file of files) {
    const text = await Deno.readTextFile(join(root, file));
    text.split("\n").forEach((t, index) => {
      const code = stripComment(t);
      lines.push({ file, index, text: t, code });
      let rest = code;
      let m = /^(\.?[A-Za-z_][A-Za-z0-9_]*):/.exec(code);
      if (m) {
        defs.push({
          name: m[1].toUpperCase(),
          file,
          line: index,
          kind: m[1].startsWith(".") ? "private" : "label",
          order,
        });
        rest = code.slice(m[0].length);
      } else if ((m = /^([A-Za-z_][A-Za-z0-9_]*):?\s+EQU\b/i.exec(code))) {
        defs.push({
          name: m[1].toUpperCase(),
          file,
          line: index,
          kind: "equ",
          order,
        });
        rest = code.slice(m[0].length);
      } else if (/^%/.test(code)) rest = "";
      // operand identifiers
      const toks = rest.trim();
      const mn = /^[A-Za-z]+/.exec(toks);
      let operands = toks;
      if (mn && MNEMONICS.has(mn[0].toUpperCase())) {
        operands = toks.slice(mn[0].length);
      }
      for (const id of operands.matchAll(ID)) {
        const name = id[0].toUpperCase();
        const prev = operands[id.index! - 1];
        if (prev && /[0-9$%]/.test(prev)) continue; // part of a number like 0FFH
        if (/^[0-9]/.test(name)) continue;
        if (MNEMONICS.has(name) && !name.startsWith(".")) continue;
        refs.push({
          name,
          file,
          line: index,
          order,
          privateRef: name.startsWith("."),
        });
      }
      order++;
    });
  }
  return { files, lines, defs, refs };
}

if (import.meta.main) {
  const [root, cmd] = Deno.args;
  if (cmd === "files") {
    for (
      const e of ["src/runtime/image.asm", "src/compiler/scope/compiler.asm"]
    ) console.log(e, (await includeOrder(root, e)).length);
  }
}
