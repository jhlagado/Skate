import assert from "node:assert/strict";
import { join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { createZ80Runtime } from "@jhlagado/z80-runtime";

import { loadAssembly } from "../../tests/z80.ts";
import { EffectClient, ProviderTransport } from "../../tools/effect-client.ts";
import { decodeEffectCommand } from "../../tools/effect-commands.ts";
import { TriptychEffectProvider } from "../../tools/triptych-provider.ts";
import {
  decodeEffectFrame,
  EffectProtocolError,
} from "../../tools/effect-wire.ts";
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
const artifactArgument = Deno.args.find((argument) =>
  argument.startsWith("--write-artifact=")
);
const artifactPath = artifactArgument?.slice("--write-artifact=".length);
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
const providerImage = await loadAssembly(
  "src/runtime/image.asm",
);
assert.equal(compiler.image.base, 0);
assert.equal(
  providerImage.image.bytes.length - 0x100,
  compiler.address("SRTLEN"),
);
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compiler.image.bytes.slice(0x100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "SKATE.RT",
  bytes: providerImage.image.bytes.slice(0x100),
  padByte: 0x1a,
});
disk = installCpm22File(disk, {
  name: "TRACE.SK8",
  bytes: new TextEncoder().encode(
    `${await Deno.readTextFile(
      "examples/applications/provider-trace.sk8",
    )}\x1a`,
  ),
  padByte: 0x1a,
});

const machine = new TriptychCpu(firmware.bootRom);
const decoder = new TextDecoder("ascii");
const encoder = new TextEncoder();
let transcript = "";

function runUntilPrompt(offset, description) {
  for (let attempt = 0; attempt < 1_800; attempt += 1) {
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

function runCommand(command, expected, description) {
  const start = transcript.length;
  assert.ok(machine.enqueue_serial_input(encoder.encode(`${command}\r`)));
  runUntilPrompt(start, description);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  return output;
}

function runProgram(command, input, expected, description) {
  const start = transcript.length;
  assert.ok(machine.enqueue_serial_input(encoder.encode(`${command}\r`)));
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while starting ${description}`);
    if (transcript.slice(start).includes(`${command}\r\r\n`)) break;
  }
  assert.ok(transcript.slice(start).includes(`${command}\r\r\n`));
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted before input for ${description}`);
  }
  assert.ok(machine.enqueue_serial_input(encoder.encode(input)));
  runUntilPrompt(start, description);
  const output = programOutput(transcript.slice(start));
  assert.equal(output, expected, `${description}: unexpected output`);
  return output;
}

function programOutput(output) {
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  return output.slice(commandEnd + 3, prompt);
}

function createTriptychEffectClient() {
  const backend = { submit: () => new Uint8Array(0) };
  const provider = new TriptychEffectProvider(backend);
  const delegate = new ProviderTransport(provider);
  const textWrites = [];
  const transport = {
    transact(request) {
      const command = decodeEffectCommand(decodeEffectFrame(request));
      if (command.type === "text") textWrites.push(command.bytes.slice());
      return delegate.transact(request);
    },
  };
  return { client: new EffectClient(transport), textWrites };
}

function runBareProgram(bytes, effects, vectors, inputBytes) {
  const memory = new Uint8Array(65_536);
  memory.set(bytes, 0x100);
  memory[0] = 0x76; // HALT after the generated runtime's CP/M return jump.
  memory[5] = 0xc9; // Guard: reaching the legacy CP/M vector is rejected below.
  const outputTrap = 0xff00;
  const inputTrap = 0xff03;
  for (
    const [vector, target] of [
      [vectors.output, outputTrap],
      [vectors.input, inputTrap],
    ]
  ) {
    const offset = vector - 0x100;
    assert.ok(offset >= 0 && offset + 2 < bytes.length);
    memory[vector] = 0xc3; // JP target: the vector is part of the image ABI.
    memory[vector + 1] = target & 0xff;
    memory[vector + 2] = target >>> 8;
  }
  memory[outputTrap] = 0xc9;
  memory[inputTrap] = 0xc9;
  const runtime = createZ80Runtime({ memory, startAddress: 0x100 });
  const input = [...inputBytes];
  const output = [];
  for (let steps = 0; !runtime.isHalted(); steps += 1) {
    assert.ok(
      steps < 2_000_000,
      "generated program exceeded the step budget",
    );
    if (runtime.cpu.pc === outputTrap) {
      output.push(runtime.cpu.a);
      effects.client.sendText(String.fromCharCode(runtime.cpu.a));
    } else if (runtime.cpu.pc === inputTrap) {
      runtime.cpu.a = input.shift() ?? 0;
    } else if (runtime.cpu.pc === 5) {
      throw new Error("generated program entered the CP/M BDOS vector");
    }
    runtime.step();
  }
  return Uint8Array.from(output);
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the CP/M boot prompt");
  runCommand("SKATE TRACE.SK8", "COMPILED\r\n", "compile TRACE.SK8");
  const compiledDisk = machine.export_drive(0);
  const generated = readCpm22File(compiledDisk, "TRACE.COM");
  if (artifactPath) await Deno.writeFile(artifactPath, generated);
  const cpmSession = runProgram("TRACE", "Q", "QQ\r\n", "run TRACE.COM");
  const cpmOutput = cpmSession.slice(1); // CP/M function 1 echoes the input byte.

  const effects = createTriptychEffectClient();
  const bareOutput = runBareProgram(generated, effects, {
    output: providerImage.address("SRTOUTV"),
    input: providerImage.address("SRTINV"),
  }, ["Q".charCodeAt(0)]);
  assert.deepEqual(
    new TextEncoder().encode(cpmOutput),
    bareOutput,
    "bare provider output must match CP/M output",
  );
  assert.deepEqual(
    Uint8Array.from(effects.textWrites.flatMap((bytes) => [...bytes])),
    bareOutput,
  );

  assert.throws(
    () => effects.client.sendControl(0x0102, Uint8Array.of(1)),
    (error) =>
      error instanceof EffectProtocolError && error.code === "unsupported",
  );
  console.log(JSON.stringify(
    {
      status: "passed",
      source: "TRACE.SK8",
      generatedBytes: generated.length,
      trace: [...bareOutput],
      limitation:
        "The image includes a CP/M default adapter; native/WASM hosts patch SRTOUTV and SRTINV to their byte gateway before running.",
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
