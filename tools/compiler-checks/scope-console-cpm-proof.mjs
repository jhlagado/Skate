import assert from "node:assert/strict";
import { join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../../tests/z80.ts";
import { validateAso } from "./aso-proof.mjs";
import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";

const triptychRoot = fileURLToPath(
  new URL("../../../triptych/", import.meta.url),
);
const require = createRequire(import.meta.url);
const { TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);
const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
);
const systemDisk = Uint8Array.from(sourceDisk);
systemDisk.set(firmware.ccp, 0x0000);
systemDisk.set(firmware.bdos, 0x0800);
systemDisk.set(firmware.bios, 0x1600);
const backing = new Uint8Array(Math.ceil(systemDisk.length / 512) * 512);
backing.set(systemDisk);
backing.fill(0xe5, 52 * 128, 52 * 128 + 64 * 32);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly(
  "src/runtime/image.asm",
);
assert.equal(compiler.image.base, 0);
assert.equal(provider.image.bytes.length - 0x100, compiler.address("SRTLEN"));
const heapPointerAddress = provider.address("SRTHEAPP");
const lowStackAddress = provider.address("SRTLOWSP");
const bindingAllocationAddress = provider.address("SRTBCNT");
const closureAllocationAddress = provider.address("SRTCCNT");
const pairAllocationAddress = provider.address("SRTPCNT");
const collectionCountAddress = provider.address("SRTGCNT");
const frameCountAddress = provider.address("SRTACNT");
const stackGuardBase = 0xd400;
const stackTop = 0xe400;
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
disk = installCpm22File(disk, {
  name: "IO.SK8",
  bytes: await Deno.readFile("libraries/io.sk8"),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "INPUT.TXT",
  bytes: Uint8Array.from([0x41, 0x42, 0x0d, 0x0a]),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "INPUT.BIN",
  bytes: Uint8Array.from([0x00, 0x1a, 0x0d, 0x0a]),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "CHARS.TXT",
  bytes: new TextEncoder().encode(
    String.raw`#\x41 #\space #\newline #\( #\x` + "\r\n",
  ),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "CRLF.TXT",
  bytes: Uint8Array.from([0x41, 0x0d, 0x0a, 0x42, 0x0d, 0x0a]),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "DATUM.TXT",
  bytes: new TextEncoder().encode("(1 2) foo\r\n"),
  padByte: 0x1a,
});
const vector64Input = `#(${Array(64).fill("1").join(" ")})\r`;
const vector65Input = `#(${Array(65).fill("1").join(" ")})\r`;

const cases = [
  [
    "CHAROUT.SK8",
    "(begin (write-char #\\A) (write-char #\\space) (write-char #\\B) (newline))",
    "A B\r\n",
  ],
  [
    "CHARPRNT.SK8",
    "(begin (write #\\A) (display #\\B) (newline))",
    "#\\AB\r\n",
  ],
  [
    "CHARCTL.SK8",
    "(begin (write #\\newline) (write #\\x00) (write #\\x7f) (newline))",
    "#\\newline#\\x00#\\x7f\r\n",
  ],
  [
    "DISPLAYP.SK8",
    "(display (list #\\A #\\B))",
    "(A B)",
  ],
  [
    "DISPZERO.SK8",
    "(begin (display #t) (display '()) (newline))",
    "#t()\r\n",
  ],
  [
    "CHARPRED.SK8",
    "(begin (write (char? #\\A)) (write (char? 1)) (write (procedure? read-char)) (write (procedure? write-char)) (newline))",
    "#t#f#t#t\r\n",
  ],
  [
    "READPRED.SK8",
    "(begin (write (procedure? read)) (write (number? read)) (newline))",
    "#t#f\r\n",
  ],
  [
    "PORTPRED.SK8",
    "(begin (write (port? (current-input-port))) (write (input-port? (current-input-port))) (write (output-port? (current-input-port))) (write (output-port? (current-output-port))) (write (output-port? (current-error-port))) (write (procedure? (current-output-port))) (newline))",
    "#t#t#f#t#t#f\r\n",
  ],
  [
    "PORTWRIT.SK8",
    "(begin (write-char #\\A (current-output-port)) (write #t (current-error-port)) (newline (current-output-port)))",
    "A#t\r\n",
  ],
  [
    "FILEIN.SK8",
    '(let ((p (open-input-file "INPUT.TXT"))) (write-char (read-char p)) (write-char (read-char p)) (close-port p) (newline))',
    "AB\r\n",
  ],
  [
    "FILEOUT.SK8",
    '(let ((p (open-output-file "OUTPUT.TXT"))) (write-char #\\A p) (newline p) (close-port p) (display "ok"))',
    "ok",
  ],
  [
    "BININ.SK8",
    '(let ((p (open-input-binary-file "INPUT.BIN"))) (write (read-char p)) (write (read-char p)) (write (read-char p)) (write (read-char p)) (newline))',
    "#\\x00#\\x1a#\\x0d#\\newline\r\n",
  ],
  [
    "BINOUT.SK8",
    '(let ((p (open-output-binary-file "OUTPUT.BIN"))) (write-char #\\x00 p) (write-char #\\x1a p) (write-char #\\x0d p) (write-char #\\x0a p) (close-port p) (display "ok"))',
    "ok",
  ],
  [
    "READCHAR.SK8",
    "(begin (display (read-char)) (newline))",
    "QQ\r\n",
    "Q",
  ],
  [
    "PORTREAD.SK8",
    "(begin (display (read-char (current-input-port))) (newline))",
    "QQ\r\n",
    "Q",
  ],
  [
    "READDATA.SK8",
    '(begin (display ">") (write (read)) (newline))',
    ">42\r42\r\n",
    "42\r",
  ],
  [
    "READSTR.SK8",
    "(begin (write (read)) (newline))",
    '"hello""hello"\r\n',
    '"hello"\r',
  ],
  [
    "READSYM.SK8",
    "(begin (write (eq? (read) 'alpha)) (newline))",
    "alpha\r#t\r\n",
    "alpha\r",
  ],
  [
    "SYMINTER.SK8",
    "(let ((a (read))) (write (eq? a (read))) (newline))",
    "alpha alpha\r#t\r\n",
    "alpha alpha\r",
  ],
  [
    "RDVEC0.SK8",
    "(begin (write (vector-length (read))) (newline))",
    "#()0\r\n",
    "#()\r",
  ],
  [
    "RDVNEST.SK8",
    "(let ((v (read))) (write (vector? v)) (write (vector-length v)) (write (vector-length (vector-ref v 0))) (newline))",
    "#(#(1 2) 3)#t22\r\n",
    "#(#(1 2) 3)\r",
  ],
  [
    "RDVEC64.SK8",
    "(begin (write (vector-length (read))) (newline))",
    `${vector64Input.slice(0, -1)}64\r\n`,
    vector64Input,
  ],
  [
    "RDVEC65.SK8",
    "(read)",
    "RUNTIME ERROR\r\n",
    vector65Input,
    false,
  ],
  [
    "RDVECBAD.SK8",
    "(read)",
    "RUNTIME ERROR\r\n",
    "#(1 . 2\r",
    false,
  ],
  [
    "REDEMPTY.SK8",
    "(begin (write (read)) (newline))",
    '""""\r\n',
    '""\r',
  ],
  [
    "READESC.SK8",
    "(begin (write (string-length (read))) (newline))",
    '"a\\n\\x41;"3\r\n',
    '"a\\n\\x41;"\r',
  ],
  [
    "RDSTR255.SK8",
    "(begin (write (string-length (read))) (newline))",
    `"${"a".repeat(255)}"255\r\n`,
    `"${"a".repeat(255)}"\r`,
  ],
  [
    "RDSTROV.SK8",
    "(read)",
    "RUNTIME ERROR\r\n",
    `"${"a".repeat(256)}"\r`,
    false,
  ],
  [
    "CRONLY.SK8",
    "(begin (write (read-char)) (newline))",
    "\r#\\newline\r\n",
    "\r",
  ],
  [
    "CRPORT.SK8",
    "(begin (write (read-char (current-input-port))) (newline))",
    "\r#\\newline\r\n",
    "\r",
  ],
  [
    "IODEMO.SK8",
    '(include "IO.SK8") (begin (prompt "Name: ") (write-line (read-line)))',
    "Name: Ada\rAda\r\n",
    "Ada\r",
  ],
  [
    "IOEXPL.SK8",
    '(include "IO.SK8") (begin (prompt-to "Name: " (current-output-port)) (write-line-to (read-line-from (current-input-port)) (current-error-port)))',
    "Name: Ada\rAda\r\n",
    "Ada\r",
  ],
  [
    "IOEMPTY.SK8",
    '(include "IO.SK8") (begin (write (read-line)) (newline))',
    '\r""\r\n',
    "\r",
  ],
  [
    "IOEOF.SK8",
    '(include "IO.SK8") (begin (write (read-line)) (newline))',
    "\x1a#<eof>\r\n",
    "\x1a",
  ],
  [
    "IOFINAL.SK8",
    '(include "IO.SK8") (begin (display (read-line)) (newline))',
    "Ada\x1aAda\r\n",
    "Ada\x1a",
  ],
  [
    "IOLIMIT.SK8",
    '(include "IO.SK8") (begin (write (string-length (read-line))) (newline))',
    `${"a".repeat(255)}\r255\r\n`,
    `${"a".repeat(255)}\r`,
  ],
  [
    "IOCOPY.SK8",
    '(include "IO.SK8") (begin (display "[") (write (copy-stream)) (display "]") (newline))',
    "[aa\r\r\nbb\r\r\n\x1a4]\r\n",
    ["a", "\r", "b", "\r", "\x1a"],
  ],
  [
    "IOOVER.SK8",
    '(include "IO.SK8") (read-line)',
    "RUNTIME ERROR\r\n",
    `${"a".repeat(256)}\r`,
    false,
  ],
  [
    "EOFCHAR.SK8",
    "(begin (write (eof-object? (read-char))) (newline))",
    "\x1a#t\r\n",
    "\x1a",
  ],
  [
    "EOFWRITE.SK8",
    "(begin (write (read-char)) (newline))",
    "\x1a#<eof>\r\n",
    "\x1a",
  ],
  [
    "EOFDSPLY.SK8",
    "(begin (display (read-char)) (newline))",
    "\x1a#<eof>\r\n",
    "\x1a",
  ],
  [
    "PRINTPRC.SK8",
    "(begin (display car) (write car) (display (lambda (x) x)) (newline))",
    "#<procedure>#<procedure>#<procedure>\r\n",
  ],
  [
    "PRINTVEC.SK8",
    "(begin (write (vector 1 (vector 2 3) '(4))) (display (vector)) (newline))",
    "#(1 #(2 3) (4))#()\r\n",
  ],
  [
    "PRINTPRT.SK8",
    "(begin (display (current-output-port)) (write (list (current-input-port))) (newline))",
    "#<port>(#<port>)\r\n",
  ],
  [
    "PRINTESC.SK8",
    "(begin (call/ec (lambda (k) (display k))) (newline))",
    "#<procedure>\r\n",
  ],
  [
    "WRITESTR.SK8",
    String
      .raw`(begin (write "q\"b\\n\nt\tr\r") (write (string #\x01 #\x7f)) (display "q\"b") (newline))`,
    String.raw`"q\"b\\n\nt\tr\r""\x01;\x7f;"q"b` + "\r\n",
  ],
  [
    "DISPLIST.SK8",
    '(begin (display (list #\\a "b c" \'d #\\space)) (write (list #\\a "b c" \'d #\\space)) (newline))',
    '(a b c d  )(#\\a "b c" d #\\space)\r\n',
  ],
  [
    "RDCHARS.SK8",
    '(let ((p (open-input-file "CHARS.TXT"))) (write (read p)) (write (read p)) (write (read p)) (write (read p)) (write (read p)) (write (read p)) (close-port p) (newline))',
    String.raw`#\A#\space#\newline#\(#\x#<eof>` + "\r\n",
  ],
  [
    "RNDTRIP.SK8",
    String
      .raw`(begin (let ((o (open-output-file "RT.TXT"))) (write (list "a\"\\\n" #\space #\x01 #\a 'sym -12 (vector 1 #\b "c")) o) (close-port o)) (let ((i (open-input-file "RT.TXT"))) (write (read i)) (close-port i) (newline)))`,
    String.raw`("a\"\\\n" #\space #\x01 #\a sym -12 #(1 #\b "c"))` + "\r\n",
  ],
  [
    "LONGLST.SK8",
    "(define (build n acc) (if (zero? n) acc (build (- n 1) (cons 0 acc)))) (display (build 1200 '()))",
    `(${Array(1200).fill("0").join(" ")})`,
  ],
  [
    "DEEPNEST.SK8",
    "(define (nest n acc) (if (zero? n) acc (nest (- n 1) (cons acc '())))) (write (nest 1200 '()))",
    "RUNTIME ERROR\r\n",
    "",
    false,
  ],
  [
    "FILECRLF.SK8",
    '(let ((p (open-input-file "CRLF.TXT"))) (write (read-char p)) (write (read-char p)) (write (read-char p)) (write (read-char p)) (write (read-char p)) (close-port p) (newline))',
    String.raw`#\A#\newline#\B#\newline#<eof>` + "\r\n",
  ],
  [
    "FILELINE.SK8",
    '(include "IO.SK8") (let ((p (open-input-file "CRLF.TXT"))) (write (read-line-from p)) (write (read-line-from p)) (write (read-line-from p)) (close-port p) (newline))',
    '"A""B"#<eof>\r\n',
  ],
  [
    "FILECOPY.SK8",
    '(include "IO.SK8") (let ((p (open-input-file "CRLF.TXT"))) (write (copy-stream-from-to p (current-output-port))) (close-port p) (newline))',
    "A\r\nB\r\n4\r\n",
  ],
  [
    "READDFLT.SK8",
    '(let ((p (open-input-file "DATUM.TXT"))) (write (read p)) (write (read)) (close-port p) (newline))',
    "(1 2)42\r42\r\n",
    "42\r",
  ],
  [
    "MIXCLOSE.SK8",
    '(let ((p (open-input-file "INPUT.TXT"))) (write (read p)) (write (read p)) (close-port p) (write (read-char)) (newline))',
    String.raw`AB#<eof>Q#\Q` + "\r\n",
    "Q",
  ],
  [
    "MIXOPEN.SK8",
    '(let ((p (open-input-file "INPUT.TXT"))) (write (read p)) (write (read-char)) (write (read-char p)) (close-port p) (newline))',
    String.raw`ABQ#\Q#\newline` + "\r\n",
    "Q",
  ],
  [
    "FILEPRED.SK8",
    '(let ((p (open-input-file "INPUT.TXT")) (q (open-output-file "PRED.TXT"))) (write (output-port? p)) (write (input-port? p)) (write (output-port? q)) (write (input-port? q)) (close-port p) (close-port q) (newline))',
    "#f#t#t#f\r\n",
  ],
  [
    "FILEERR.SK8",
    `(let ((p (open-output-file "PART.TXT"))) (display "${
      "0123456789".repeat(13)
    }" p) (car 1))`,
    "RUNTIME ERROR\r\n",
  ],
  [
    "FILEEXIT.SK8",
    '(let ((p (open-output-file "EXIT.TXT"))) (display "kept" p) (display "ok"))',
    "ok",
  ],
  [
    "CLOSE2.SK8",
    '(let ((p (open-output-file "TWICE.TXT")) (q (open-input-file "INPUT.TXT"))) (close-port p) (close-port p) (close-port q) (close-port q) (display "ok"))',
    "ok",
  ],
  [
    "ADVENTUR.SK8",
    await Deno.readTextFile("examples/applications/advent.sk8"),
    "You are at a fork. Choose left or right: l\r\nYou take the left path.",
    "l",
  ],
];
const errorCases = [
  ["BADWCHAR.SK8", "(write-char 1)"],
  ["BADRCHAR.SK8", "(read-char 1)"],
  ["BADINPRT.SK8", "(read-char (current-output-port))"],
  ["BADOUTP.SK8", "(write-char #\\A (current-input-port))"],
  ["BADCURR.SK8", "(current-input-port 1)"],
  ["CLOSEPRT.SK8", "(close-port (current-output-port))"],
  ["FILEMISS.SK8", '(open-input-file "MISSING.TXT")'],
  ["FILEPATH.SK8", '(open-input-file "A/B.TXT")'],
  ["FILELONG.SK8", '(open-input-file "ABCDEFGHI.TXT")'],
];
// `--only=NAME,NAME` limits a development run to the named programs.
const onlyArgument = Deno.args.find((argument) =>
  argument.startsWith("--only=")
);
if (onlyArgument) {
  const selected = new Set(
    onlyArgument.slice("--only=".length).split(",").map((name) =>
      name.endsWith(".SK8") ? name : `${name}.SK8`
    ),
  );
  for (const list of [cases, errorCases]) {
    for (let index = list.length - 1; index >= 0; index -= 1) {
      if (!selected.has(list[index][0])) list.splice(index, 1);
    }
  }
}
for (const [name, source] of [...cases, ...errorCases]) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(source + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
const decoder = new TextDecoder("ascii");
let transcript = "";
function readWord(address) {
  const bytes = machine.read_ram(address, 2);
  return bytes[0] | bytes[1] << 8;
}
function prepareStackMeasurement() {
  machine.write_ram(
    stackGuardBase,
    new Uint8Array(stackTop - stackGuardBase).fill(0xa5),
  );
}
function observedStackLow() {
  const bytes = machine.read_ram(stackGuardBase, stackTop - stackGuardBase);
  const offset = bytes.findIndex((value) => value !== 0xa5);
  return offset < 0 ? stackTop : stackGuardBase + offset;
}
function runUntilPrompt(offset, description) {
  for (let attempt = 0; attempt < 1800; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while waiting for ${description}`);
    if (transcript.length > offset && transcript.endsWith("A>")) return;
  }
  throw new Error(
    `Timed out waiting for ${description}: ${
      JSON.stringify(transcript.slice(-500))
    }`,
  );
}
function command(command, expected, description) {
  const start = transcript.length;
  assert.ok(
    machine.enqueue_serial_input(new TextEncoder().encode(command + "\r")),
  );
  runUntilPrompt(start, description);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  return output;
}
function runProgram(name, input, expected, exact = true) {
  const start = transcript.length;
  const commandBytes = new TextEncoder().encode(
    name.replace(".SK8", "") + "\r",
  );
  assert.ok(machine.enqueue_serial_input(commandBytes));
  const commandEcho = `${name.replace(".SK8", "")}\r\r\n`;
  let atProgramEntry = false;
  for (let attempt = 0; attempt < 2_000_000; attempt += 1) {
    const state = machine.cpu_state();
    try {
      if (
        state.pc() === 0x0100 && transcript.slice(start).includes(commandEcho)
      ) {
        atProgramEntry = true;
        break;
      }
    } finally {
      state.free();
    }
    const status = machine.run_slice(1, 500);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while starting ${name}`);
  }
  assert.ok(transcript.slice(start).includes(commandEcho));
  assert.ok(
    atProgramEntry,
    `${name}: did not stop at COM entry before execution`,
  );
  prepareStackMeasurement();
  const inputChunks = Array.isArray(input) ? input : [input];
  if (inputChunks.some((chunk) => chunk.length > 0)) {
    // Let the running program reach its blocking console read before sending
    // the byte.  This keeps the proof independent of execution speed.
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const status = machine.run_slice(50_000, 500_000);
      transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(status, 0, `CP/M halted before input for ${name}`);
    }
    for (const chunk of inputChunks) {
      if (chunk.length > 0) {
        assert.ok(
          machine.enqueue_serial_input(new TextEncoder().encode(chunk)),
        );
      }
      for (let attempt = 0; attempt < 8; attempt += 1) {
        const status = machine.run_slice(50_000, 500_000);
        transcript += decoder.decode(machine.take_serial_output());
        assert.notEqual(status, 0, `CP/M halted before input for ${name}`);
      }
    }
  }
  runUntilPrompt(start, `run ${name}`);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  const programOutput = output.slice(commandEnd + 3, prompt);
  if (exact) {
    assert.equal(programOutput, expected, `${name}: unexpected program output`);
  } else {
    assert.ok(
      programOutput.endsWith(expected),
      `${name}: expected output to end with ${JSON.stringify(expected)}, got ${
        JSON.stringify(programOutput)
      }`,
    );
  }
  return output;
}

// `--keep-going` records program-output failures and reports them together.
const keepGoing = Deno.args.includes("--keep-going");
const failures = [];
function checkCase(name, check) {
  if (!keepGoing) return check();
  try {
    return check();
  } catch (error) {
    failures.push(`${name}: ${String(error.message).slice(0, 400)}`);
  }
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const measurements = [];
  for (const [name, , expected, input = "", exact = true] of cases) {
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
    checkCase(name, () => runProgram(name, input, expected, exact));
    if (name === "FILEOUT.SK8") {
      const outputFile = readCpm22File(machine.export_drive(0), "OUTPUT.TXT");
      assert.deepEqual(
        [...outputFile.slice(0, 3)],
        [0x41, 0x0d, 0x0a],
        "FILEOUT.SK8: CP/M text file bytes",
      );
    }
    if (name === "BINOUT.SK8") {
      const outputFile = readCpm22File(machine.export_drive(0), "OUTPUT.BIN");
      assert.deepEqual(
        [...outputFile.slice(0, 4)],
        [0x00, 0x1a, 0x0d, 0x0a],
        "BINOUT.SK8: binary file bytes",
      );
    }
    if (name === "FILEERR.SK8") {
      checkCase(name, () => {
        const outputFile = readCpm22File(machine.export_drive(0), "PART.TXT");
        assert.equal(
          decoder.decode(outputFile.slice(0, 131)),
          "0123456789".repeat(13) + "\x1a",
          "FILEERR.SK8: bytes written before the error",
        );
      });
    }
    if (name === "FILEEXIT.SK8") {
      checkCase(name, () => {
        const outputFile = readCpm22File(machine.export_drive(0), "EXIT.TXT");
        assert.equal(
          decoder.decode(outputFile.slice(0, 5)),
          "kept\x1a",
          "FILEEXIT.SK8: bytes written before normal exit",
        );
      });
    }
    const nativeLowSp = readWord(lowStackAddress);
    const observedLowSp = observedStackLow();
    if (name === "LONGLST.SK8") {
      checkCase(name, () =>
        assert.ok(
          observedLowSp >= 0xd500,
          `LONGLST.SK8: printing used stack down to ${
            observedLowSp.toString(16)
          }`,
        ));
    }
    const heapEnd = readWord(heapPointerAddress);
    assert.ok(nativeLowSp >= 0xd400, `${name}: native stack crossed its guard`);
    assert.ok(
      observedLowSp < stackTop,
      `${name}: no stack writes were observed`,
    );
    assert.ok(heapEnd < nativeLowSp, `${name}: heap and stack collided`);
    measurements[measurements.length - 1].lowSp = nativeLowSp;
    measurements[measurements.length - 1].observedLowSp = observedLowSp;
    measurements[measurements.length - 1].heapEnd = heapEnd;
    measurements[measurements.length - 1].bindingAllocations = readWord(
      bindingAllocationAddress,
    );
    measurements[measurements.length - 1].closureAllocations = readWord(
      closureAllocationAddress,
    );
    measurements[measurements.length - 1].pairAllocations = readWord(
      pairAllocationAddress,
    );
    measurements[measurements.length - 1].collections = readWord(
      collectionCountAddress,
    );
    measurements[measurements.length - 1].activations = readWord(
      frameCountAddress,
    );
    command(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    command(`ERA ${name.replace(".SK8", ".ASO")}`, "A>", `remove ${name}`);
  }
  for (const [name] of errorCases) {
    command(`SKATE ${name}`, "COMPILED\r\n", `compile ${name}`);
    checkCase(name, () => runProgram(name, "", "RUNTIME ERROR\r\n"));
    command(`ERA ${name.replace(".SK8", ".COM")}`, "A>", `remove ${name}`);
    command(`ERA ${name.replace(".SK8", ".ASO")}`, "A>", `remove ${name}`);
  }
  if (failures.length > 0) {
    console.log(JSON.stringify({ status: "failed", failures }, null, 2));
    Deno.exit(1);
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
