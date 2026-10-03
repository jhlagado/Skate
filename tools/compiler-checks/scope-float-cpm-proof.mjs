import assert from "node:assert/strict";

import { loadAssembly } from "../../tests/z80.ts";
import { validateAso } from "./aso-proof.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import {
  createCpmSession,
  loadCpmSystem,
  makeSystemDisk,
  TriptychCpu,
} from "./cpm-harness.mjs";

const { firmware, sourceDisk } = await loadCpmSystem();
const backing = makeSystemDisk(firmware, sourceDisk);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
);
assert.equal(compiler.image.base, 0);
assert.equal(provider.image.bytes.length - 0x100, compiler.address("RT_SIZE"));
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: provider.image.bytes.slice(0x100),
  padByte: 0x1a,
});

const cases = [
  ["FLOATLIT.SK8", "(begin (display 1.5) (newline))", "1.5\r\n"],
  ["DIVINT.SK8", "(begin (display (/ 1 2)) (newline))", "0.5\r\n"],
  ["DIVUNARY.SK8", "(begin (display (/ 2)) (newline))", "0.5\r\n"],
  ["DIVFOLD.SK8", "(begin (display (/ 8 2)) (newline))", "4.0\r\n"],
  ["DIVTHREE.SK8", "(begin (display (/ 8 2 2)) (newline))", "2.0\r\n"],
  ["MIXADD.SK8", "(begin (display (+ 1 0.5)) (newline))", "1.5\r\n"],
  ["MIXSUB.SK8", "(begin (display (- 3.0 1)) (newline))", "2.0\r\n"],
  ["MIXMUL.SK8", "(begin (display (* 2.0 3)) (newline))", "6.0\r\n"],
  ["NEGATIVE.SK8", "(begin (display -1.5) (newline))", "-1.5\r\n"],
  ["SIGNZER0.SK8", "(begin (display -0.0) (newline))", "-0.0\r\n"],
  [
    "SUBNORM.SK8",
    "(begin (display 0.000000059604644775390625) (newline))",
    "0.000000059604644775390625\r\n",
  ],
  ["MAXFLT.SK8", "(begin (display 65504.0) (newline))", "65504.0\r\n"],
  ["EXP25.SK8", "(begin (display 1024.0) (newline))", "1024.0\r\n"],
  [
    "COMPARIS.SK8",
    "(begin (write (= 2048 2048.0)) (write (< 2048 2050.0)) (write (> +nan.0 1.0)) (newline))",
    "#t#t#f\r\n",
  ],
  [
    "NUMPRED.SK8",
    "(begin (write (number? 1.5)) (write (boolean? 1.5)) (newline))",
    "#t#f\r\n",
  ],
  [
    "BOOLFLT.SK8",
    "(begin (write #f) (write #t) (write (number? 0.0)) (write (boolean? 0.0)) (newline))",
    "#f#t#t#f\r\n",
  ],
  [
    "ZEROFLT.SK8",
    "(begin (write 0.0) (newline) (write 1.0) (newline) (write (if 0.0 7 8)) (newline))",
    "0.0\r\n1.0\r\n7\r\n",
  ],
  [
    "SPECIALS.SK8",
    "(begin (write +inf.0) (newline) (write -inf.0) (newline) (write +nan.0) (newline))",
    "+inf.0\r\n-inf.0\r\n+nan.0\r\n",
  ],
  ["EXACTINT.SK8", "(begin (write (+ 1 2)) (newline))", "3\r\n"],
  ["ROUNDING.SK8", "(begin (display 2049.0) (newline))", "2048.0\r\n"],
  [
    "ZEROPRED.SK8",
    "(begin (write (zero? 0.0)) (write (zero? -0.0)) (write (zero? 1.5)) (newline))",
    "#t#t#f\r\n",
  ],
  [
    "NESTED.SK8",
    "(begin (write (list 1.5 2.0)) (newline))",
    "(1.5 2.0)\r\n",
  ],
  [
    "ADJACENT.SK8",
    "(begin (display 1.5) (display 2.0) (newline))",
    "1.52.0\r\n",
  ],
  ["LETRECFL.SK8", "(letrec ((a 1.5)) (display a) (newline))", "1.5\r\n"],
  [
    "IDEFFLT.SK8",
    "((lambda () (define a 2.5) (define b (list 0.5 a)) (display b) (newline)))",
    "(0.5 2.5)\r\n",
  ],
];
const errorCases = [
  ["NODIV.SK8", "(/)"],
  ["BADDIV.SK8", "(/ #t 2)"],
];
for (const [name, source] of [...cases, ...errorCases]) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
const cpm = createCpmSession(machine);
const { runUntilPrompt, runCommand: command } = cpm;
function runProgram(name, expected) {
  const start = cpm.transcript.length;
  const stem = name.replace(".SK8", "");
  cpm.send(stem + "\r");
  const commandEcho = `${stem}\r\r\n`;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    cpm.slice(50_000, 500_000, `CP/M halted while starting ${name}`);
    if (cpm.transcript.slice(start).includes(commandEcho)) break;
  }
  assert.ok(cpm.transcript.slice(start).includes(commandEcho));
  runUntilPrompt(start, `run ${name}`);
  const output = cpm.transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  assert.equal(
    output.slice(commandEnd + 3, prompt),
    expected,
    `${name}: unexpected program output`,
  );
  return output;
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected] of cases) {
    command(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    const image = machine.export_drive(0);
    const generated = readCpm22File(image, name.replace(".SK8", ".COM"));
    const aso = readCpm22File(image, name.replace(".SK8", ".ASO"));
    const { asoBytes } = validateAso(aso, generated, name);
    measurements.push({
      name,
      comBytes: generated.length,
      asoBytes,
    });
    runProgram(name, expected);
    command(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    command(`ERA ${name.replace(".SK8", ".ASO")}`, "A>", `remove ${name}`);
  }
  for (const [name] of errorCases) {
    command(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    runProgram(name, "RUNTIME ERROR\r\n");
    command(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    command(`ERA ${name.replace(".SK8", ".ASO")}`, "A>", `remove ${name}`);
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compiler.image.bytes.length - 0x100,
      runtimeBytes: provider.image.bytes.length - 0x100,
      cases: cases.map(([name]) => name),
      largestComBytes: Math.max(
        ...measurements.map(({ comBytes }) => comBytes),
      ),
      largestAsoBytes: Math.max(
        ...measurements.map(({ asoBytes }) => asoBytes),
      ),
      measurements,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
