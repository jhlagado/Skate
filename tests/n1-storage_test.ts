import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM10, SKATE_TPA_PROFILES } from "../tools/m7-compiler.ts";

function wordAt(memory: Uint8Array, address: number): number {
  return memory[address]! | (memory[address + 1]! << 8);
}

for (const profile of ["cpm-64k", "cpm-32k"] as const) {
  Deno.test(`N1 places adaptive runtime storage in ${profile}`, async () => {
    const compiled = await compileM10(
      new TextEncoder().encode("(+ 1 2)"),
      `n1-${profile}.sk8`,
      { tpaProfile: SKATE_TPA_PROFILES[profile] },
    );
    const bss = compiled.object.sections.find(({ storageKind }) =>
      storageKind === 2
    );
    assert.ok(bss);
    assert.equal(bss!.length, compiled.bssBytes);
    assert.equal(bss!.runPlacement, "allocate");
    assert.equal(
      compiled.bssEndAddress,
      compiled.bssBaseAddress + compiled.bssBytes,
    );
    assert.ok(compiled.bssEndAddress <= compiled.stackLowAddress);
    assert.ok(compiled.heapCells > 512);
    assert.ok(compiled.heapCells <= 8192);
    const nextCells = compiled.heapCells + 1;
    if (nextCells <= 8192) {
      const nextBssBytes = compiled.bssBytes + 4 +
        (Math.ceil(nextCells / 8) - Math.ceil(compiled.heapCells / 8));
      assert.ok(
        compiled.bssBaseAddress + nextBssBytes > compiled.stackLowAddress,
        "planner did not choose the largest fitting heap",
      );
    }
    assert.ok(
      compiled.comBytes.length < compiled.bssEndAddress - compiled.entryAddress,
    );
    assert.ok(compiled.heapBaseAddress > compiled.bssBaseAddress + 4736);
  });
}

function executeCom(compiled: Awaited<ReturnType<typeof compileM10>>): {
  readonly output: string;
  readonly memory: Uint8Array;
} {
  const memory = new Uint8Array(0x10000);
  memory.fill(0xa5);
  memory.set(compiled.comBytes, compiled.entryAddress);
  memory.set([0xc3, 0x06, 0xf0], 5);
  const machine = createZ80Runtime({
    memory,
    startAddress: compiled.entryAddress,
  });
  const { cpu } = machine;
  const ram = machine.hardware.memory;
  cpu.pc = compiled.entryAddress;
  cpu.sp = compiled.stackTopAddress;
  let output = "";
  let steps = 0;
  while (cpu.pc !== 0xff00) {
    assert.ok(++steps < 1_000_000, "N1 image did not terminate");
    if (cpu.pc !== 5) {
      machine.step();
      continue;
    }
    if (cpu.c === 0) {
      cpu.pc = 0xff00;
      continue;
    }
    if (cpu.c === 2) {
      output += String.fromCharCode(cpu.e);
    } else if (cpu.c === 9) {
      let address = (cpu.d << 8) | cpu.e;
      let length = 0;
      while (ram[address] !== 0x24) {
        output += String.fromCharCode(ram[address]!);
        address = (address + 1) & 0xffff;
        assert.ok(++length < 256, "N1 diagnostic string is unterminated");
      }
    } else {
      assert.fail(`unexpected BDOS function ${cpu.c}`);
    }
    const returnAddress = wordAt(ram, cpu.sp);
    cpu.sp += 2;
    cpu.pc = returnAddress;
  }
  return { output, memory: ram };
}

Deno.test("N1 clears the zero-init section before running generated code", async () => {
  const compiled = await compileM10(
    new TextEncoder().encode("(+ 1 2)"),
    "n1-zero.sk8",
  );
  const { output, memory: ram } = executeCom(compiled);
  assert.equal(output, "3\r\n");
  // Startup may legitimately populate the active prefixes. The untouched
  // tails prove that the poisoned BSS was cleared before the runtime ran.
  for (
    let address = wordAt(ram, compiled.rootHighWaterAddress) + 4;
    address < compiled.rootBaseAddress + 4096;
    address++
  ) {
    assert.equal(
      ram[address],
      0,
      `root BSS byte $${address.toString(16)} was not cleared`,
    );
  }
  for (
    let address = wordAt(ram, compiled.activationHighWaterAddress);
    address < compiled.activationBaseAddress + 640;
    address++
  ) {
    assert.equal(
      ram[address],
      0,
      `activation BSS byte $${address.toString(16)} was not cleared`,
    );
  }
});

Deno.test("N1 keeps the 512-cell execution path on both profiles", async () => {
  for (const profile of ["cpm-64k", "cpm-32k"] as const) {
    const compiled = await compileM10(
      new TextEncoder().encode("(+ 1 2)"),
      `n1-512-${profile}.sk8`,
      { heapCells: 512, tpaProfile: SKATE_TPA_PROFILES[profile] },
    );
    assert.equal(executeCom(compiled).output, "3\r\n");
  }
});

Deno.test("N1 rejects a profile with no room before linking an image", async () => {
  await assert.rejects(
    () =>
      compileM10(new TextEncoder().encode("42"), "n1-small.sk8", {
        tpaProfile: {
          ...SKATE_TPA_PROFILES["cpm-32k"],
          capacity: 0x4000,
          stackLow: 0x3100,
          stackTop: 0x4100,
        },
      }),
    /caller exceeds the selected profile's stack guard/,
  );
});
