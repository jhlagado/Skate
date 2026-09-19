import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { compileM5 } from "./m5-compiler.ts";
import { assembleTriptychCpuFirmware } from "../../triptych/tools/cpm22-native-image.mjs";
import { installCpm22File } from "../../triptych/tools/lib/cpm22-disk.mjs";

const triptychRoot = fileURLToPath(new URL("../../triptych/", import.meta.url));
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

const backingLength = Math.ceil(systemDisk.length / 512) * 512;
const backing = new Uint8Array(backingLength);
backing.set(systemDisk);
const addSource = await Deno.readFile(
  new URL("../examples/add.sk8", import.meta.url),
);
const addCompiled = await compileM5(addSource, "examples/add.sk8");
const controlSource = await Deno.readFile(
  new URL("../examples/control.sk8", import.meta.url),
);
const controlCompiled = await compileM5(
  controlSource,
  "examples/control.sk8",
);
const addDisk = installCpm22File(backing, {
  name: "SKADD.COM",
  bytes: addCompiled.comBytes,
  padByte: 0x1a,
});
const disk = installCpm22File(addDisk, {
  name: "SKCTRL.COM",
  bytes: controlCompiled.comBytes,
  padByte: 0x1a,
});

const machine = new TriptychCpu(firmware.bootRom);
let transcript = "";
const decoder = new TextDecoder("ascii");
const promptStart = "A>";
function runUntilPrompt(offset, description) {
  for (let slice = 0; slice < 1500; slice += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while waiting for ${description}`);
    if (transcript.length > offset && transcript.endsWith(promptStart)) return;
  }
  throw new Error(
    `Timed out waiting for ${description}: ${
      JSON.stringify(transcript.slice(-500))
    }`,
  );
}
function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  const runProgram = (name, expected, description) => {
    const commandStart = transcript.length;
    assert.ok(
      machine.enqueue_serial_input(new TextEncoder().encode(name + "\r")),
      "CP/M accepted the command input",
    );
    runUntilPrompt(commandStart, description);
    const commandTranscript = transcript.slice(commandStart);
    assert.ok(
      commandTranscript.includes(expected),
      `the executable printed ${JSON.stringify(expected)}: ${
        JSON.stringify(commandTranscript)
      }`,
    );
    assert.ok(
      !commandTranscript.includes("NUMERIC ERROR"),
      `an unselected expression ran: ${JSON.stringify(commandTranscript)}`,
    );
    assert.ok(
      commandTranscript.endsWith("A>"),
      "BDOS function 0 returned to the CCP prompt",
    );
    return commandTranscript;
  };
  const addTranscript = runProgram("SKADD", "42\r\n", "prompt after SKADD.COM");
  const controlTranscript = runProgram(
    "SKCTRL",
    "42\r\n",
    "prompt after SKCTRL.COM",
  );
  console.log(JSON.stringify(
    {
      status: "passed",
      programs: [
        {
          source: "examples/add.sk8",
          expression: "(+ 40 2)",
          object: {
            bytes: addCompiled.objectBytes.length,
            sha256: sha256(addCompiled.objectBytes),
          },
          com: {
            bytes: addCompiled.comBytes.length,
            sha256: sha256(addCompiled.comBytes),
          },
          transcript: addTranscript,
        },
        {
          source: "examples/control.sk8",
          expression: "(begin (+ 1 2) (if #f (+ 32767 1) (+ 20 22)))",
          object: {
            bytes: controlCompiled.objectBytes.length,
            sha256: sha256(controlCompiled.objectBytes),
          },
          com: {
            bytes: controlCompiled.comBytes.length,
            sha256: sha256(controlCompiled.comBytes),
          },
          transcript: controlTranscript,
        },
      ],
      runtime: {
        base: controlCompiled.runtimeBase,
        length: controlCompiled.runtimeLength,
      },
      machine: "Triptych WebAssembly Z80 host with CP/M 2.2",
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
