import assert from "node:assert/strict";

import {
  EffectClient,
  EffectPortProvider,
  PortError,
  type PortProvider,
  ProviderTransport,
  RecordingEffectProvider,
} from "../../tools/effect-protocol.ts";
import {
  managedRuntime,
  readWord,
  writeWord,
} from "./scope-runtime-fixture.ts";

function runWithProvider(
  assembled: Awaited<ReturnType<typeof managedRuntime>>["assembled"],
  memory: Uint8Array,
  cpu: Awaited<ReturnType<typeof managedRuntime>>["cpu"],
  provider: PortProvider,
  label: string,
  setup: () => void = () => {},
  expectBalancedStack = true,
  expectError = false,
) {
  const putHook = 0xf100;
  const getHook = 0xf110;
  const stopAddress = expectError ? 0xef10 : 0xef00;
  const errorAddress = assembled.address("ERROR");
  let enteredError = false;
  let bdosTextCall = false;
  let diagnosticWrites = 0;
  writeWord(memory, assembled.address("CON_PUT"), putHook);
  writeWord(memory, assembled.address("CON_GET"), getHook);
  setup();
  // A failed provider call takes the runtime's checked diagnostic path. The
  // fixture returns from BDOS and turns the final fatal jump into the test
  // sentinel so the carry contract can be exercised without a full CP/M boot.
  if (expectError) {
    memory[0] = 0xc3;
    memory[1] = stopAddress & 0xff;
    memory[2] = stopAddress >>> 8;
  }
  memory[5] = 0xc9;
  cpu.pc = assembled.address(label);
  cpu.sp = 0xb3f0;
  writeWord(memory, cpu.sp, stopAddress);
  let steps = 0;
  while (cpu.pc !== stopAddress) {
    assert.ok(++steps < 2_000_000, `${label} did not return`);
    if (cpu.pc === errorAddress) enteredError = true;
    if (cpu.pc === 5) {
      bdosTextCall ||= cpu.c === 9;
      const returnAddress = readWord(memory, cpu.sp);
      cpu.sp += 2;
      cpu.pc = returnAddress;
      continue;
    }
    if (cpu.pc === putHook || cpu.pc === getHook) {
      const returnAddress = readWord(memory, cpu.sp);
      cpu.sp += 2;
      if (cpu.pc === putHook) {
        if (enteredError) diagnosticWrites += 1;
        try {
          provider.write(2, Uint8Array.of(cpu.a));
          cpu.flags.C = 0;
        } catch {
          cpu.flags.C = 1;
        }
      } else {
        const result = provider.read(1, 1);
        if (result.status === "data" && result.bytes.length === 1) {
          cpu.a = result.bytes[0]!;
          cpu.flags.C = 0;
        } else {
          cpu.a = 0;
          cpu.flags.C = 1;
        }
      }
      cpu.pc = returnAddress;
      continue;
    }
    assembled.runtime.step();
  }
  if (expectBalancedStack) assert.equal(cpu.sp, 0xb3f2, `${label} stack`);
  if (expectError) {
    assert.ok(enteredError, `${label} did not enter ERROR`);
    assert.ok(
      diagnosticWrites > 0,
      `${label} did not send diagnostics through the provider`,
    );
    assert.ok(!bdosTextCall, `${label} bypassed the provider with BDOS 9`);
  }
  return { tag: cpu.a, payload: (cpu.h << 8) | cpu.l };
}

Deno.test("runtime text services can use an effect provider without source changes", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const effects = new RecordingEffectProvider();
  effects.queueEvent({
    type: "text",
    source: 1,
    sequence: 1,
    text: "A\r\n",
  });
  const client = new EffectClient(new ProviderTransport(effects));
  const provider = new EffectPortProvider(client);

  const text = assembled.address("WR_TRUE");
  runWithProvider(assembled, memory, cpu, provider, "OUT_TEXT", () => {
    memory[0xf300] = 79;
    memory[0xf301] = 75;
    memory[0xf302] = 0x24;
    cpu.d = 0xf3;
    cpu.e = 0x00;
  });
  runWithProvider(assembled, memory, cpu, provider, "IN_NEXT");
  assert.equal(cpu.a, 0);
  assert.equal((cpu.h << 8) | cpu.l, 0xff41);
  runWithProvider(assembled, memory, cpu, provider, "IN_NEXT");
  assert.equal(cpu.a, 0);
  assert.equal((cpu.h << 8) | cpu.l, 0xff0a);

  // The fixed readable-value messages use the same service, rather than BDOS
  // function nine, so host and CP/M output have one observable byte path.
  runWithProvider(assembled, memory, cpu, provider, "WR_SEND", () => {
    cpu.d = text >>> 8;
    cpu.e = text & 0xff;
  });
  assert.deepEqual(
    effects.textWrites.flatMap((bytes) => [...bytes]),
    [79, 75, 35, 116],
  );
});

Deno.test("provider carry failures use the checked runtime path", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const failing: PortProvider = {
    read: () => ({
      status: "error",
      code: "device",
      message: "input is unavailable",
    }),
    write: () => {
      throw new PortError("device", "output is unavailable");
    },
    close: () => {},
  };

  runWithProvider(
    assembled,
    memory,
    cpu,
    failing,
    "OUT_CHAR",
    () => {
      cpu.a = 0x41;
    },
    false,
    true,
  );
  runWithProvider(
    assembled,
    memory,
    cpu,
    failing,
    "IN_BYTE",
    () => {},
    false,
    true,
  );
});

Deno.test("runtime error messages use the selected output provider", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const effects = new RecordingEffectProvider();
  const client = new EffectClient(new ProviderTransport(effects));
  const provider = new EffectPortProvider(client);
  runWithProvider(
    assembled,
    memory,
    cpu,
    provider,
    "ERROR",
    () => {},
    false,
    true,
  );
  assert.equal(
    new TextDecoder().decode(
      Uint8Array.from(effects.textWrites.flatMap((bytes) => [...bytes])),
    ),
    "RUNTIME ERROR\r\n",
  );
});
