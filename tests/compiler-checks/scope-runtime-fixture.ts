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
    "src/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  const imageEnd = (assembled.image.end + 0xff) & 0xff00;
  const closureMapBytes = assembled.address("GC_MARKS") -
    assembled.address("CL_MAP");
  const bindingMapBytes = assembled.address("RT_HIGH") -
    assembled.address("BND_MAP");
  memory.fill(0, imageEnd, 0xe000);
  memory.fill(
    0,
    assembled.address("CL_MAP"),
    assembled.address("CL_MAP") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("GC_MARKS"),
    assembled.address("GC_MARKS") + closureMapBytes,
  );
  memory.fill(
    0,
    assembled.address("BND_MAP"),
    assembled.address("BND_MAP") + bindingMapBytes,
  );
  memory.fill(
    0,
    assembled.address("CL_FREE"),
    assembled.address("CL_FREE") + 130,
  );
  memory.fill(
    0,
    assembled.address("CL_OWNER"),
    assembled.address("CL_OWNER") + 128,
  );
  memory.fill(
    0,
    assembled.address("CL_LIVE"),
    assembled.address("CL_LIVE") + 128,
  );
  memory.fill(
    0,
    assembled.address("CL_PHYS"),
    assembled.address("CL_PHYS") + 128,
  );
  memory.fill(
    0,
    assembled.address("BND_PHYS"),
    assembled.address("BND_PHYS") + 128,
  );
  writeWord(memory, assembled.address("CL_TOP"), 0);
  writeWord(memory, assembled.address("BND_TOP"), 0);
  writeWord(memory, assembled.address("HEAP_LIM"), 0xc000);
  // Test descriptors live in the transient area, beyond the assembled image.
  // Keep the published-image bound above them while the allocator still uses
  // the real image end for its first managed page.
  writeWord(memory, assembled.address("RT_LIMIT"), 0xc200);
  writeWord(memory, assembled.address("G_BASE"), 0);
  writeWord(memory, assembled.address("G_END"), 0);
  writeWord(memory, assembled.address("QT_START"), 0);
  writeWord(memory, assembled.address("QT_STOP"), 0);
  writeWord(memory, assembled.address("ENV_CUR"), 0);
  writeWord(memory, assembled.address("ENV_RET"), 0);
  writeWord(memory, assembled.address("OPS_SP"), assembled.address("RT_OPLO"));
  writeWord(memory, assembled.address("QT_SP"), assembled.address("RT_QTLO"));
  memory[assembled.address("SLOT_CNT")] = 0;
  memory[assembled.address("ENV_RCNT")] = 0;
  memory[assembled.address("ARG_CNT")] = 0;
  memory[assembled.address("QT_HELD")] = 0;
  memory[assembled.address("GC_HOLD")] = 0;

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

  assert.equal(call("PAGE_INI", imageEnd).carry, 0);

  if (withPairs) {
    assert.equal(call("PAIR_INI").carry, 0);
  }

  return { assembled, memory, cpu, call };
}
