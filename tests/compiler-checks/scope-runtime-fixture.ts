import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";

export function writeWord(memory: Uint8Array, address: number, value: number) {
  memory[address] = value & 255;
  memory[address + 1] = value >>> 8;
}

export function readWord(memory: Uint8Array, address: number) {
  return memory[address] | memory[address + 1] << 8;
}

export async function managedRuntime(withPairs = false) {
  const assembled = await loadAssembly(
    "src/compiler/scope/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  const imageEnd = (assembled.image.end + 0xff) & 0xff00;
  const closureMapBytes = assembled.address("SRTCLMK") -
    assembled.address("SRTCLBM");
  const bindingMapBytes = assembled.address("SRTMPEND") -
    assembled.address("SRTBMB");
  memory.fill(0, imageEnd, 0xe000);
  memory.fill(
    0,
    assembled.address("SRTCLBM"),
    assembled.address("SRTCLBM") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("SRTCLMK"),
    assembled.address("SRTCLMK") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("SRTBMB"),
    assembled.address("SRTBMB") + bindingMapBytes,
  );
  memory.fill(
    0,
    assembled.address("SRTCFREE"),
    assembled.address("SRTCFREE") + 130,
  );
  memory.fill(
    0,
    assembled.address("SRTCLOWN"),
    assembled.address("SRTCLOWN") + 128,
  );
  memory.fill(
    0,
    assembled.address("SRTCLUSE"),
    assembled.address("SRTCLUSE") + 128,
  );
  memory.fill(
    0,
    assembled.address("SRTCLPBA"),
    assembled.address("SRTCLPBA") + 128,
  );
  memory.fill(
    0,
    assembled.address("SRTBPGS"),
    assembled.address("SRTBPGS") + 128,
  );
  writeWord(memory, assembled.address("SRTCLCUR"), 0);
  writeWord(memory, assembled.address("SRTBEND"), 0);
  writeWord(memory, assembled.address("SRTHEAPP"), 0xc000);
  // Test descriptors live in the transient area, beyond the assembled image.
  // Keep the published-image bound above them while the allocator still uses
  // the real image end for its first managed page.
  writeWord(memory, assembled.address("SRTIMGE"), 0xc200);
  writeWord(memory, assembled.address("SRTGBASE"), 0);
  writeWord(memory, assembled.address("SRTGEND"), 0);
  writeWord(memory, assembled.address("SRTQROOT"), 0);
  writeWord(memory, assembled.address("SRTQENDR"), 0);
  writeWord(memory, assembled.address("SRTENV"), 0);
  writeWord(memory, assembled.address("SRTCENV"), 0);
  writeWord(memory, assembled.address("SRTOPS"), assembled.address("SRTOPB"));
  writeWord(memory, assembled.address("SRTQSP"), assembled.address("SRTQBASE"));
  memory[assembled.address("SRTSLOTS")] = 0;
  memory[assembled.address("SRTCENVN")] = 0;
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTQACTV")] = 0;
  memory[assembled.address("SRTCRON")] = 0;

  function call(label: string, hl = 0) {
    cpu.h = hl >>> 8;
    cpu.l = hl & 255;
    cpu.pc = assembled.address(label);
    cpu.sp = 0xdff0;
    writeWord(memory, cpu.sp, 0xef00);
    let steps = 0;
    while (cpu.pc !== 0xef00) {
      assert.ok(++steps < 50_000_000, `${label} did not return`);
      assembled.runtime.step();
    }
    assert.equal(cpu.sp, 0xdff2, `${label} stack`);
    return {
      carry: cpu.flags.C,
      tag: cpu.a,
      payload: (cpu.h << 8) | cpu.l,
    };
  }

  assert.equal(call("SRTGPINI", imageEnd).carry, 0);

  if (withPairs) {
    assert.equal(call("SRTPIN").carry, 0);
  }

  return { assembled, memory, cpu, call };
}
