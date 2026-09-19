import assert from "node:assert/strict";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { compileM10, SKATE_TPA_PROFILES } from "../tools/m7-compiler.ts";

Deno.test("startup rejects a smaller CP/M machine before using its private stack", async () => {
  const compiled = await compileM10(new TextEncoder().encode("42"));
  const memory = new Uint8Array(65536);
  memory.set(compiled.comBytes, 0x100);
  memory.fill(0xa5, 0x8000);
  memory.set([0xc3, 0x06, 0x80], 5);
  const machine = createZ80Runtime({ memory, startAddress: 0x100 });
  const { cpu } = machine;
  const ram = machine.hardware.memory;
  const before = ram.slice();
  cpu.sp = 0x7f00;
  let output = "";
  let steps = 0;
  while (cpu.pc !== 0 && ++steps < 100) {
    if (cpu.pc === 5) {
      assert.equal(cpu.c, 9);
      assert.equal(cpu.sp, 0x7efe);
      let address = (cpu.d << 8) | cpu.e;
      while (ram[address] !== 36) {
        output += String.fromCharCode(ram[address++]!);
      }
      cpu.pc = ram[cpu.sp]! | (ram[cpu.sp + 1]! << 8);
      cpu.sp += 2;
    } else machine.step();
  }
  assert.equal(cpu.pc, 0, "reject through the CP/M warm-boot vector");
  assert.equal(cpu.sp, 0x7f00);
  assert.equal(output, "INSUFFICIENT MEMORY\r\n");
  assert.deepEqual(ram.slice(0, 0x7efe), before.slice(0, 0x7efe));
  assert.deepEqual(ram.slice(0x7f00), before.slice(0x7f00));
});

Deno.test("packed COM jumps over its runtime and leaves only alignment padding", async () => {
  for (const profile of Object.values(SKATE_TPA_PROFILES)) {
    const compiled = await compileM10(
      new TextEncoder().encode("42"),
      "packed.sk8",
      {
        tpaProfile: profile,
      },
    );
    assert.equal(compiled.entryAddress, 0x100);
    assert.equal(compiled.runtimeBase, 0x103);
    assert.equal(compiled.comBytes[0], 0xc3);
    assert.equal(
      compiled.comBytes[1]! | (compiled.comBytes[2]! << 8),
      compiled.programAddress,
    );
    const padding = compiled.programAddress -
      (compiled.runtimeBase + compiled.runtimeLength);
    assert.ok(padding >= 0 && padding <= 3);
    assert.equal(compiled.programAddress % 4, 0);
    assert.equal(
      compiled.comBytes.length,
      3 + compiled.runtimeLength + padding + compiled.callerImageBytes,
    );
    assert.ok(
      compiled.programAddress + compiled.callerImageBytes <=
        compiled.stackLowAddress,
    );
  }
});

Deno.test("packed program rejects a profile whose stack would overlap the caller", async () => {
  await assert.rejects(
    () =>
      compileM10(new TextEncoder().encode("42"), "small-profile.sk8", {
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
