import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/z80-runtime";

import { loadAssembly } from "../../tests/z80.ts";
import { EffectClient, ProviderTransport } from "../../tools/effect-client.ts";
import { decodeEffectCommand } from "../../tools/effect-commands.ts";
import { TriptychEffectProvider } from "../../tools/triptych-provider.ts";
import {
  decodeEffectFrame,
  EffectProtocolError,
} from "../../tools/effect-wire.ts";
import {
  installCpm22File,
  readCpm22File,
} from "../../../triptych/tools/lib/cpm22-disk.mjs";
import {
  createCpmSession,
  loadCpmSystem,
  makeSystemDisk,
  programOutput,
  TriptychCpu,
} from "./cpm-harness.mjs";

const artifactArgument = Deno.args.find((argument) =>
  argument.startsWith("--write-artifact=")
);
const artifactPath = artifactArgument?.slice("--write-artifact=".length);
const { firmware, sourceDisk } = await loadCpmSystem();
const backing = makeSystemDisk(firmware, sourceDisk);

const compiler = await loadAssembly("src/compiler/scope/compiler.asm");
const providerImage = await loadAssembly(
  "src/runtime/image.asm",
);
assert.equal(compiler.image.base, 0);
assert.equal(
  providerImage.image.bytes.length - 0x100,
  compiler.address("RT_SIZE"),
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
      "tests/fixtures/provider-trace.sk8",
    )}\x1a`,
  ),
  padByte: 0x1a,
});

const machine = new TriptychCpu(firmware.bootRom);
const cpm = createCpmSession(machine);
const { runUntilPrompt, runCommand } = cpm;

function runProgram(command, input, expected, description) {
  const start = cpm.transcript.length;
  cpm.send(`${command}\r`);
  for (let attempt = 0; attempt < 120; attempt += 1) {
    cpm.slice(50_000, 500_000, `CP/M halted while starting ${description}`);
    if (cpm.transcript.slice(start).includes(`${command}\r\r\n`)) break;
  }
  assert.ok(cpm.transcript.slice(start).includes(`${command}\r\r\n`));
  for (let attempt = 0; attempt < 8; attempt += 1) {
    cpm.slice(50_000, 500_000, `CP/M halted before input for ${description}`);
  }
  cpm.send(input);
  runUntilPrompt(start, description);
  const output = programOutput(cpm.transcript.slice(start));
  assert.equal(output, expected, `${description}: unexpected output`);
  return output;
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
    assert.ok(offset >= 0 && offset + 1 < bytes.length);
    memory[vector] = target & 0xff; // Provider cells hold a service address.
    memory[vector + 1] = target >>> 8;
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
      runtime.cpu.f &= 0xfe; // Carry clear acknowledges successful byte output.
      output.push(runtime.cpu.a);
      effects.client.sendText(String.fromCharCode(runtime.cpu.a));
    } else if (runtime.cpu.pc === inputTrap) {
      runtime.cpu.a = input.shift() ?? 0;
      runtime.cpu.f &= 0xfe; // Carry clear acknowledges successful byte input.
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
    output: providerImage.address("CON_PUT"),
    input: providerImage.address("CON_GET"),
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
        "The image includes a CP/M default adapter; native/WASM hosts patch CON_PUT and CON_GET to their byte gateway before running.",
    },
    null,
    2,
  ));
} finally {
  machine.free();
}
