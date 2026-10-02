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

const countArgument = Deno.args.find((argument) =>
  argument.startsWith("--count=")
);
let count = countArgument === undefined
  ? 3000
  : Number.parseInt(countArgument.slice("--count=".length), 10);
const tailArgument = Deno.args.find((argument) =>
  argument.startsWith("--tail=")
);
const tail = tailArgument === undefined
  ? ""
  : decodeURIComponent(tailArgument.slice("--tail=".length));
const tailLengthArgument = Deno.args.find((argument) =>
  argument.startsWith("--tail-length=")
);
let tailLength = tailLengthArgument === undefined
  ? undefined
  : Number.parseInt(tailLengthArgument.slice("--tail-length=".length), 10);
if (tailLength !== undefined) {
  assert.ok(
    Number.isInteger(tailLength) && tailLength >= 0 && tailLength <= 1000,
    "tail length must be an integer from 0 through 1000",
  );
}
const expectedImageArgument = Deno.args.find((argument) =>
  argument.startsWith("--expect-image=")
);
const expectedImage = expectedImageArgument === undefined
  ? undefined
  : Number.parseInt(expectedImageArgument.slice("--expect-image=".length), 10);
const expectedComArgument = Deno.args.find((argument) =>
  argument.startsWith("--expect-com=")
);
const expectedCom = expectedComArgument === undefined
  ? undefined
  : Number.parseInt(expectedComArgument.slice("--expect-com=".length), 10);
assert.ok(
  Number.isInteger(count) && count > 0 && count <= 10000,
  "count must be an integer from 1 through 10000",
);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const provider = await loadAssembly("src/runtime/image.asm");
const compilerBytes = compiler.image.bytes.slice(0x0100);
const runtimeBytes = provider.image.bytes.slice(0x0100);
assert.equal(runtimeBytes.length, compiler.address("SRTLEN"));
// --fill-image=N sizes the program so the published image is exactly N bytes
// whatever the runtime length: each top-level `1` emits FORM_BYTES and the
// closing string literal adds one byte per character over a fixed overhead.
const fillArgument = Deno.args.find((argument) =>
  argument.startsWith("--fill-image=")
);
if (fillArgument !== undefined) {
  const FORM_BYTES = 5;
  const FIXED_BYTES = 8;
  const target = Number.parseInt(
    fillArgument.slice("--fill-image=".length),
    10,
  );
  const free = target - runtimeBytes.length - FIXED_BYTES;
  count = Math.floor(free / FORM_BYTES);
  tailLength = free - count * FORM_BYTES;
}
const source = [
  Array.from({ length: count }, () => "1").join(" "),
  tailLength === undefined ? "" : `"${"a".repeat(tailLength)}"`,
  tail,
].filter((part) => part.length !== 0).join(" ");
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compilerBytes,
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: runtimeBytes,
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "LARGE.SK8",
  bytes: new TextEncoder().encode(`${source}\x1a`),
  padByte: 0x1a,
});

const machine = new TriptychCpu(firmware.bootRom);
const cpm = createCpmSession(machine, { promptAttempts: 2400 });
const { runUntilPrompt, runCommand } = cpm;
try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  runCommand("SKATE LARGE.SK8", "COMPILED\r\n", "compile LARGE.SK8");
  const image = machine.export_drive(0);
  const com = readCpm22File(image, "LARGE.COM");
  const aso = readCpm22File(image, "LARGE.ASO");
  const measurement = validateAso(aso, com, "LARGE.COM");
  if (expectedImage !== undefined) {
    assert.equal(measurement.imageBytes, expectedImage);
  }
  if (expectedCom !== undefined) {
    assert.equal(com.length, expectedCom);
  }
  runCommand("ERA LARGE.COM", "A>", "remove LARGE.COM");
  runCommand("ERA LARGE.ASO", "A>", "remove LARGE.ASO");
  runCommand("ERA LARGE.SK8", "A>", "remove LARGE.SK8");
  console.log(JSON.stringify(
    {
      status: "passed",
      forms: count,
      tailLength: tailLength ?? 0,
      compilerBytes: compilerBytes.length,
      runtimeBytes: runtimeBytes.length,
      imageEnd: compiler.image.end,
      comBytes: com.length,
      imageBytes: measurement.imageBytes,
      asoBytes: measurement.asoBytes,
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
