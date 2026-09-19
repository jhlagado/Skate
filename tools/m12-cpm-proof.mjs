import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { compileM10, SKATE_TPA_PROFILES } from "./m7-compiler.ts";
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
  new URL("../examples/make-adder.sk8", import.meta.url),
);
const addCompiled = await compileM10(addSource, "examples/make-adder.sk8");
const controlSource = await Deno.readFile(
  new URL("../examples/shared-counter.sk8", import.meta.url),
);
const controlCompiled = await compileM10(
  controlSource,
  "examples/shared-counter.sk8",
);
const addDisk = installCpm22File(backing, {
  name: "SKADD.COM",
  bytes: addCompiled.comBytes,
  padByte: 0x1a,
});
const counterDisk = installCpm22File(addDisk, {
  name: "SKCTRL.COM",
  bytes: controlCompiled.comBytes,
  padByte: 0x1a,
});

const rejected = await compileM10(
  new TextEncoder().encode("42"),
  "too-large.sk8",
  {
    tpaProfile: {
      ...SKATE_TPA_PROFILES["cpm-64k"],
      capacity: 0xef00,
      stackLow: 0xe000,
      stackTop: 0xf000,
    },
  },
);
const disk = installCpm22File(counterDisk, {
  name: "SKREJECT.COM",
  bytes: rejected.comBytes,
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
      !commandTranscript.includes("RUNTIME ERROR"),
      `an unselected expression ran: ${JSON.stringify(commandTranscript)}`,
    );
    assert.ok(
      commandTranscript.endsWith("A>"),
      "BDOS function 0 returned to the CCP prompt",
    );
    return commandTranscript;
  };
  const addTranscript = runProgram("SKADD", "12\r\n", "prompt after SKADD.COM");
  const controlTranscript = runProgram(
    "SKCTRL",
    "2\r\n",
    "prompt after SKCTRL.COM",
  );
  runProgram("SKADD", "12\r\n", "repeat closure invocation");
  runProgram("SKCTRL", "2\r\n", "repeat shared mutation");
  const rejectionStart = transcript.length;
  assert.ok(
    machine.enqueue_serial_input(new TextEncoder().encode("SKREJECT\r")),
  );
  // Observe the loaded program before it executes, then watch rejection up to BDOS.
  let foundEntry = false;
  for (let i = 0; i < 10_000_000; i++) {
    const state = machine.cpu_state();
    const pc = state.pc();
    state.free();
    if (pc === 0x100) {
      foundEntry = true;
      break;
    }
    machine.step(false);
  }
  assert.ok(foundEntry, "CP/M loaded the oversized-profile program");
  const residentBefore = machine.read_ram(0xec00, 0x1400);
  let reachedBdos = false;
  for (let i = 0; i < 100; i++) {
    const state = machine.cpu_state();
    const pc = state.pc();
    const sp = state.sp();
    state.free();
    assert.ok(sp < 0xec00, "rejection retains a transient-memory stack");
    if (pc === 5) {
      reachedBdos = true;
      break;
    }
    machine.step(false);
  }
  assert.ok(reachedBdos, "startup rejects before runtime initialization");
  assert.deepEqual(machine.read_ram(0xec00, 0x1400), residentBefore);
  runUntilPrompt(rejectionStart, "memory rejection returns to prompt");
  const rejectionTranscript = transcript.slice(rejectionStart);
  assert.ok(rejectionTranscript.includes("INSUFFICIENT MEMORY\r\n"));
  runProgram("SKADD", "12\r\n", "normal program after rejection");
  console.log(JSON.stringify(
    {
      status: "passed",
      rejectionTranscript,
      repeatedPrograms: ["SKADD", "SKCTRL"],
      residentPreservation:
        "$EC00–$FFFF unchanged before rejection enters BDOS",
      programs: [
        {
          source: "examples/make-adder.sk8",
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
          source: "examples/shared-counter.sk8",
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
