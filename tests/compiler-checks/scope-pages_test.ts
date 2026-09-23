import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";

function writeWord(memory: Uint8Array, address: number, value: number) {
  memory[address] = value & 255;
  memory[address + 1] = value >>> 8;
}

function readWord(memory: Uint8Array, address: number) {
  return memory[address] | (memory[address + 1] << 8);
}

async function pageRuntime() {
  const assembled = await loadAssembly(
    "src/compiler/scope/runtime/image.asm",
  );
  const memory = assembled.runtime.hardware.memory;
  const cpu = assembled.runtime.cpu;
  function call(name: string, hl = 0, de = 0) {
    cpu.h = hl >>> 8;
    cpu.l = hl & 255;
    cpu.d = de >>> 8;
    cpu.e = de & 255;
    cpu.pc = assembled.address(name);
    cpu.sp = 0xdff0;
    writeWord(memory, cpu.sp, 0xef00);
    let steps = 0;
    while (cpu.pc !== 0xef00) {
      assert.ok(++steps < 1_000_000, `${name} did not return`);
      assembled.runtime.step();
    }
    assert.equal(cpu.sp, 0xdff2, `${name} stack`);
    return {
      carry: cpu.flags.C,
      status: cpu.a,
      hl: cpu.h * 256 + cpu.l,
    };
  }
  return { assembled, memory, cpu, call };
}

function runStartup(
  assembled: Awaited<ReturnType<typeof loadAssembly>>,
  memory: Uint8Array,
  imageEnd: number,
  patchFailure: boolean,
) {
  const cpu = assembled.runtime.cpu;
  writeWord(memory, assembled.address("SRTIMGE"), imageEnd);
  const transfer = assembled.address("SRTCALL");
  memory[transfer] = 0xc3;
  writeWord(memory, transfer + 1, 0xef00);
  if (patchFailure) {
    const failure = assembled.address("SRTERROR");
    memory[failure] = 0xc3;
    writeWord(memory, failure + 1, 0xef00);
  }
  cpu.pc = assembled.address("SRTSTART");
  cpu.sp = 0xdff0;
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 1_000_000, "SRTSTART did not reach its probe exit");
    assembled.runtime.step();
  }
}

Deno.test("page setup rejects an image at the managed boundary", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory.fill(0xa5, 0x8f00, 0x9000);
  const before = memory.slice(0x8f00, 0x9000);
  const result = call("SRTGPINI", 0x9000);
  assert.equal(result.carry, 1);
  assert.equal(result.status, 2);
  assert.deepEqual(memory.slice(0x8f00, 0x9000), before);
  assert.equal(memory[assembled.address("SRTPGOK")], 0);
});

Deno.test("one-page gaps reserve management before the high extent", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const result = call("SRTGPINI", 0x8e01);
  assert.equal(result.carry, 0);
  assert.equal(readWord(memory, assembled.address("SRTPGBAS")), 0x8f00);
  assert.equal(readWord(memory, assembled.address("SRTPGLOW")), 1);
  assert.equal(readWord(memory, assembled.address("SRTPGCNT")), 9);
  assert.equal(readWord(memory, assembled.address("SRTPGMET")), 1);
  assert.equal(readWord(memory, assembled.address("SRTPGFRE")), 8);
  assert.equal(readWord(memory, assembled.address("SRTPGFRB")), 0xb800);
  const high = call("SRTGPALL", 1);
  assert.equal(high.carry, 0);
  assert.equal(high.hl, 0xb800);
  assert.equal(call("SRTGPREL", high.hl, 1).carry, 0);
});

Deno.test("small images use the pages below the legacy map origin", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const result = call("SRTGPINI", 0x3659);
  assert.equal(result.carry, 0);
  assert.equal(readWord(memory, assembled.address("SRTPGBAS")), 0x3700);
  assert.equal(readWord(memory, assembled.address("SRTPGFRB")), 0x3800);
  const first = call("SRTGPALL", 1);
  assert.equal(first.carry, 0);
  assert.equal(first.hl, 0x3800);
  assert.equal(call("SRTGPREL", first.hl, 1).carry, 0);
});

Deno.test("a lower managed ceiling shortens the high extent without overlap", async () => {
  const { memory, call, assembled } = await pageRuntime();
  writeWord(memory, assembled.address("SRTHEAPP"), 0xba00);
  const lower = call("SRTGPINI", 0x8e01);
  assert.equal(lower.carry, 0);
  assert.equal(readWord(memory, assembled.address("SRTPGHIG")), 2);
  assert.equal(readWord(memory, assembled.address("SRTPGCNT")), 3);
  assert.equal(readWord(memory, assembled.address("SRTPGFRE")), 2);
  const first = call("SRTGPALL", 2);
  assert.equal(first.carry, 0);
  assert.equal(first.hl, 0xb800);
  assert.equal(call("SRTGPALL", 1).carry, 1);

  writeWord(memory, assembled.address("SRTHEAPP"), 0xc000);
  const full = call("SRTGPINI", 0x8e01);
  assert.equal(full.carry, 0);
  assert.equal(readWord(memory, assembled.address("SRTPGHIG")), 8);
  assert.equal(readWord(memory, assembled.address("SRTPGFRE")), 8);
});

Deno.test("runtime startup publishes page readiness and rejects an invalid image", async () => {
  const { assembled, memory, call } = await pageRuntime();
  memory.fill(0xa5, 0x8f00, 0x9000);
  runStartup(assembled, memory, 0x8f00, false);
  assert.equal(memory[assembled.address("SRTPGOK")], 1);
  assert.equal(readWord(memory, assembled.address("SRTPGBAS")), 0x8f00);
  assert.equal(readWord(memory, assembled.address("SRTPGFRE")), 7);
  assert.equal(memory[assembled.address("SRTPSLBN")], 1);
  assert.ok(
    [...memory.slice(
      assembled.address("SRTBMB"),
      assembled.address("SRTMPEND"),
    )].every((value) => value === 0),
    "binding-start bitmap was not cleared at startup",
  );
  const high = call("SRTGPALL", 1);
  assert.equal(high.carry, 0);
  assert.equal(high.hl, 0xb900);

  memory.fill(0xa5, 0x8f00, 0x9000);
  const beforeFailure = memory.slice(0x8f00, 0x9000);
  runStartup(assembled, memory, 0x9000, true);
  assert.equal(memory[assembled.address("SRTPGOK")], 0);
  assert.deepEqual([...memory.slice(0x8f00, 0x9000)], [...beforeFailure]);
});

Deno.test("page runs honor bitmap boundaries, fragmentation and canaries", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory.fill(0xa5, 0x6000, 0x9000);
  memory.fill(0xa5, 0x9000, 0xb800);
  memory.fill(0xa5, 0xc000, 0xdfe0);
  const result = call("SRTGPINI", 0x6f00);
  assert.equal(result.carry, 0);
  const address = (name: string) => assembled.address(name);
  assert.equal(readWord(memory, address("SRTPGBAS")), 0x6f00);
  assert.equal(readWord(memory, address("SRTPGLOW")), 33);
  assert.equal(readWord(memory, address("SRTPGCNT")), 41);
  assert.equal(readWord(memory, address("SRTPGBYT")), 6);
  assert.equal(readWord(memory, address("SRTPGMET")), 1);
  assert.equal(readWord(memory, address("SRTPGFRE")), 40);
  assert.equal(readWord(memory, address("SRTPGFRB")), 0x7000);
  const bitmap = readWord(memory, address("SRTPGBMA"));
  assert.deepEqual(
    [...memory.slice(bitmap, bitmap + 6)],
    [0xfe, 0xff, 0xff, 0xff, 0xff, 0x01],
  );
  const directory = readWord(memory, address("SRTPGDIR"));
  assert.equal(memory[directory], 2);
  assert.equal(memory[directory + 1], 0);
  assert.equal(memory[directory + 16], 0);
  assert.equal(memory[directory + 17], 0);
  const lowCanary = memory.slice(0x6000, 0x6f00);
  const stackCanary = memory.slice(0xc000, 0xdfe0);

  const first = call("SRTGPALL", 3);
  assert.equal(first.carry, 0);
  assert.equal(first.hl, 0x7000);
  const second = call("SRTGPALL", 2);
  assert.equal(second.carry, 0);
  assert.equal(second.hl, 0x7300);
  assert.equal(readWord(memory, address("SRTPGFRE")), 35);
  assert.ok([...memory.slice(0x7000, 0x7500)].every((value) => value === 0xa5));

  assert.equal(call("SRTGPREL", first.hl, 3).carry, 0);
  const fragmented = call("SRTGPALL", 4);
  assert.equal(fragmented.carry, 0);
  assert.equal(fragmented.hl, 0x7500);
  assert.equal(call("SRTGPREL", second.hl, 2).carry, 0);
  const reused = call("SRTGPALL", 3);
  assert.equal(reused.carry, 0);
  assert.equal(reused.hl, 0x7000);
  assert.equal(call("SRTGPREL", reused.hl, 3).carry, 0);
  const beforeDoubleFree = memory.slice(bitmap, bitmap + 6);
  const doubleFree = call("SRTGPREL", reused.hl, 3);
  assert.equal(doubleFree.carry, 1);
  assert.equal(doubleFree.status, 2);
  assert.deepEqual([...memory.slice(bitmap, bitmap + 6)], [
    ...beforeDoubleFree,
  ]);
  assert.equal(call("SRTGPREL", fragmented.hl, 4).carry, 0);

  const five = call("SRTGPALL", 5);
  assert.equal(five.carry, 0);
  assert.equal(five.hl, 0x7000);
  const seven = call("SRTGPALL", 7);
  assert.equal(seven.carry, 0);
  assert.equal(seven.hl, 0x7500);
  assert.equal(readWord(memory, address("SRTPGFRE")), 28);
  const lowRemainder = call("SRTGPALL", 20);
  assert.equal(lowRemainder.carry, 0);
  assert.equal(lowRemainder.hl, 0x7c00);
  assert.equal(readWord(memory, address("SRTPGFRE")), 8);
  const highOne = call("SRTGPALL", 1);
  assert.equal(highOne.carry, 0);
  assert.equal(highOne.hl, 0xb800);
  assert.equal(readWord(memory, address("SRTPGFRE")), 7);
  assert.equal(call("SRTGPREL", five.hl, 5).carry, 0);
  assert.equal(call("SRTGPREL", seven.hl, 7).carry, 0);
  assert.equal(call("SRTGPREL", lowRemainder.hl, 20).carry, 0);
  assert.equal(call("SRTGPREL", highOne.hl, 1).carry, 0);
  assert.equal(readWord(memory, address("SRTPGFRE")), 40);
  assert.deepEqual(
    [...memory.slice(bitmap, bitmap + 6)],
    [0xfe, 0xff, 0xff, 0xff, 0xff, 0x01],
  );
  assert.deepEqual([...memory.slice(0x6000, 0x6f00)], [...lowCanary]);
  assert.deepEqual([...memory.slice(0xc000, 0xdfe0)], [...stackCanary]);

  const lowAll = call("SRTGPALL", 32);
  assert.equal(lowAll.carry, 0);
  assert.equal(lowAll.hl, 0x7000);
  assert.equal(readWord(memory, address("SRTPGFRE")), 8);
  const highAll = call("SRTGPALL", 8);
  assert.equal(highAll.carry, 0);
  assert.equal(highAll.hl, 0xb800);
  assert.equal(readWord(memory, address("SRTPGFRE")), 0);
  const exhausted = call("SRTGPALL", 1);
  assert.equal(exhausted.carry, 1);
  assert.equal(exhausted.status, 1);
  assert.equal(readWord(memory, address("SRTPGFRE")), 0);
  assert.equal(call("SRTGPREL", highAll.hl, 8).carry, 0);
  const highAgain = call("SRTGPALL", 8);
  assert.equal(highAgain.carry, 0);
  assert.equal(highAgain.hl, 0xb800);
  assert.equal(readWord(memory, address("SRTPGFRE")), 0);
  assert.equal(call("SRTGPREL", highAgain.hl, 8).carry, 0);
  assert.equal(call("SRTGPREL", lowAll.hl, 32).carry, 0);
  assert.equal(readWord(memory, address("SRTPGFRE")), 40);
  assert.deepEqual([...memory.slice(0x6000, 0x6f00)], [...lowCanary]);
  assert.deepEqual(
    [...memory.slice(0x9000, 0xb800)],
    [...new Uint8Array(0x2800).fill(0xa5)],
  );
  assert.deepEqual([...memory.slice(0xc000, 0xdfe0)], [...stackCanary]);
});

Deno.test("page release rejects the protected intervals", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory.fill(0xa5, 0x8f00, 0x9000);
  const result = call("SRTGPINI", 0x8f00);
  assert.equal(result.carry, 0);
  for (const address of [0x8e00, 0x8f00, 0x9000, 0xb800, 0xc000, 0xdf00]) {
    const rejected = call("SRTGPREL", address, 1);
    assert.equal(rejected.carry, 1, `release ${address.toString(16)}`);
    assert.equal(rejected.status, 2);
  }
  assert.equal(readWord(memory, assembled.address("SRTPGFRE")), 8);
});
