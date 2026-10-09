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
    "src/runtime/image.asm",
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
  writeWord(memory, assembled.address("RT_LIMIT"), imageEnd);
  const transfer = assembled.address("RT_CALL");
  memory[transfer] = 0xc3;
  writeWord(memory, transfer + 1, 0xef00);
  if (patchFailure) {
    const failure = assembled.address("ERROR");
    memory[failure] = 0xc3;
    writeWord(memory, failure + 1, 0xef00);
  }
  cpu.pc = assembled.address("START");
  cpu.sp = 0xdff0;
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 1_000_000, "START did not reach its probe exit");
    assembled.runtime.step();
  }
}

Deno.test("page setup rejects an image at the managed boundary", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory.fill(0xa5, 0xa400, 0xa500);
  const before = memory.slice(0xa400, 0xa500);
  const result = call("PAGE_INI", 0xa500);
  assert.equal(result.carry, 1);
  assert.equal(result.status, 2);
  assert.deepEqual(memory.slice(0xa400, 0xa500), before);
  assert.equal(memory[assembled.address("PAGE_OK")], 0);
});

Deno.test("a one-page gap holds only page management", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const result = call("PAGE_INI", 0xa301);
  assert.equal(result.carry, 0);
  assert.equal(readWord(memory, assembled.address("PAGE_ORG")), 0xa400);
  assert.equal(readWord(memory, assembled.address("PAGE_LO")), 1);
  assert.equal(readWord(memory, assembled.address("PAGE_CNT")), 1);
  assert.equal(readWord(memory, assembled.address("PAGE_SYS")), 1);
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), 0);
  const none = call("PAGE_NEW", 1);
  assert.equal(none.carry, 1);
  assert.equal(none.status, 1);
});

Deno.test("small images use the pages below the legacy map origin", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const result = call("PAGE_INI", 0x3659);
  assert.equal(result.carry, 0);
  assert.equal(readWord(memory, assembled.address("PAGE_ORG")), 0x3700);
  assert.equal(readWord(memory, assembled.address("PAGE_MIN")), 0x3800);
  const first = call("PAGE_NEW", 1);
  assert.equal(first.carry, 0);
  assert.equal(first.hl, 0x3800);
  assert.equal(call("PAGE_REL", first.hl, 1).carry, 0);
});

Deno.test("the heap is one extent from the image to the maps", async () => {
  const { memory, call, assembled } = await pageRuntime();
  writeWord(memory, assembled.address("HEAP_LIM"), 0xad00);
  assert.equal(call("PAGE_INI", 0x8e01).carry, 1);

  writeWord(memory, assembled.address("HEAP_LIM"), 0xc000);
  const full = call("PAGE_INI", 0x8e01);
  assert.equal(full.carry, 0);
  assert.equal(readWord(memory, assembled.address("PAGE_HI")), 0);
  assert.equal(readWord(memory, assembled.address("PAGE_LO")), 22);
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), 21);
  const last = call("PAGE_NEW", 21);
  assert.equal(last.carry, 0);
  assert.equal(last.hl, 0x9000);
  assert.equal(call("PAGE_NEW", 1).carry, 1);
});

Deno.test("runtime startup publishes page readiness and rejects an invalid image", async () => {
  const { assembled, memory, call } = await pageRuntime();
  runStartup(assembled, memory, 0x8f00, false);
  assert.equal(memory[assembled.address("PAGE_OK")], 1);
  assert.equal(readWord(memory, assembled.address("PAGE_ORG")), 0x8f00);
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), 20);
  assert.equal(memory[assembled.address("PS_COUNT")], 1);
  assert.ok(
    [...memory.slice(
      assembled.address("BND_MAP"),
      assembled.address("BND_MAP") + 1152,
    )].every((value) => value === 0),
    "binding-start bitmap was not cleared at startup",
  );
  const next = call("PAGE_NEW", 1);
  assert.equal(next.carry, 0);
  assert.equal(next.hl, 0x9100);

  memory.fill(0xa5, 0xa400, 0xa500);
  const beforeFailure = memory.slice(0xa400, 0xa500);
  runStartup(assembled, memory, 0xa500, true);
  assert.equal(memory[assembled.address("PAGE_OK")], 0);
  assert.deepEqual([...memory.slice(0xa400, 0xa500)], [...beforeFailure]);
});

Deno.test("page runs honor bitmap boundaries, fragmentation and canaries", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory.fill(0xa5, 0x6000, 0xa500);
  memory.fill(0xa5, 0xa500, 0xc000);
  memory.fill(0xa5, 0xc000, 0xdfe0);
  const result = call("PAGE_INI", 0x6f00);
  assert.equal(result.carry, 0);
  const address = (name: string) => assembled.address(name);
  assert.equal(readWord(memory, address("PAGE_ORG")), 0x6f00);
  assert.equal(readWord(memory, address("PAGE_LO")), 54);
  assert.equal(readWord(memory, address("PAGE_CNT")), 54);
  assert.equal(readWord(memory, address("PAGE_LEN")), 7);
  assert.equal(readWord(memory, address("PAGE_SYS")), 1);
  assert.equal(readWord(memory, address("PAGE_CAP")), 53);
  assert.equal(readWord(memory, address("PAGE_MIN")), 0x7000);
  const bitmap = readWord(memory, address("PAGE_MAP"));
  assert.deepEqual(
    [...memory.slice(bitmap, bitmap + 7)],
    [0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0x3f],
  );
  const directory = readWord(memory, address("PAGE_DIR"));
  assert.equal(memory[directory], 2);
  assert.equal(memory[directory + 1], 0);
  assert.equal(memory[directory + 16], 0);
  assert.equal(memory[directory + 17], 0);
  const lowCanary = memory.slice(0x6000, 0x6f00);
  const stackCanary = memory.slice(0xc000, 0xdfe0);

  const first = call("PAGE_NEW", 3);
  assert.equal(first.carry, 0);
  assert.equal(first.hl, 0x7000);
  const second = call("PAGE_NEW", 2);
  assert.equal(second.carry, 0);
  assert.equal(second.hl, 0x7300);
  assert.equal(readWord(memory, address("PAGE_CAP")), 48);
  assert.ok([...memory.slice(0x7000, 0x7500)].every((value) => value === 0xa5));

  assert.equal(call("PAGE_REL", first.hl, 3).carry, 0);
  const fragmented = call("PAGE_NEW", 4);
  assert.equal(fragmented.carry, 0);
  assert.equal(fragmented.hl, 0x7500);
  assert.equal(call("PAGE_REL", second.hl, 2).carry, 0);
  const reused = call("PAGE_NEW", 3);
  assert.equal(reused.carry, 0);
  assert.equal(reused.hl, 0x7000);
  assert.equal(call("PAGE_REL", reused.hl, 3).carry, 0);
  const beforeDoubleFree = memory.slice(bitmap, bitmap + 7);
  const doubleFree = call("PAGE_REL", reused.hl, 3);
  assert.equal(doubleFree.carry, 1);
  assert.equal(doubleFree.status, 2);
  assert.deepEqual([...memory.slice(bitmap, bitmap + 7)], [
    ...beforeDoubleFree,
  ]);
  assert.equal(call("PAGE_REL", fragmented.hl, 4).carry, 0);

  const five = call("PAGE_NEW", 5);
  assert.equal(five.carry, 0);
  assert.equal(five.hl, 0x7000);
  const seven = call("PAGE_NEW", 7);
  assert.equal(seven.carry, 0);
  assert.equal(seven.hl, 0x7500);
  assert.equal(readWord(memory, address("PAGE_CAP")), 41);
  const lowRemainder = call("PAGE_NEW", 20);
  assert.equal(lowRemainder.carry, 0);
  assert.equal(lowRemainder.hl, 0x7c00);
  assert.equal(readWord(memory, address("PAGE_CAP")), 21);
  const highOne = call("PAGE_NEW", 1);
  assert.equal(highOne.carry, 0);
  assert.equal(highOne.hl, 0x9000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 20);
  assert.equal(call("PAGE_REL", five.hl, 5).carry, 0);
  assert.equal(call("PAGE_REL", seven.hl, 7).carry, 0);
  assert.equal(call("PAGE_REL", lowRemainder.hl, 20).carry, 0);
  assert.equal(call("PAGE_REL", highOne.hl, 1).carry, 0);
  assert.equal(readWord(memory, address("PAGE_CAP")), 53);
  assert.deepEqual(
    [...memory.slice(bitmap, bitmap + 7)],
    [0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0x3f],
  );
  assert.deepEqual([...memory.slice(0x6000, 0x6f00)], [...lowCanary]);
  assert.deepEqual([...memory.slice(0xc000, 0xdfe0)], [...stackCanary]);

  const lowAll = call("PAGE_NEW", 32);
  assert.equal(lowAll.carry, 0);
  assert.equal(lowAll.hl, 0x7000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 21);
  const highAll = call("PAGE_NEW", 21);
  assert.equal(highAll.carry, 0);
  assert.equal(highAll.hl, 0x9000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 0);
  const exhausted = call("PAGE_NEW", 1);
  assert.equal(exhausted.carry, 1);
  assert.equal(exhausted.status, 1);
  assert.equal(readWord(memory, address("PAGE_CAP")), 0);
  assert.equal(call("PAGE_REL", highAll.hl, 21).carry, 0);
  const highAgain = call("PAGE_NEW", 21);
  assert.equal(highAgain.carry, 0);
  assert.equal(highAgain.hl, 0x9000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 0);
  assert.equal(call("PAGE_REL", highAgain.hl, 21).carry, 0);
  assert.equal(call("PAGE_REL", lowAll.hl, 32).carry, 0);
  assert.equal(readWord(memory, address("PAGE_CAP")), 53);
  assert.deepEqual([...memory.slice(0x6000, 0x6f00)], [...lowCanary]);
  assert.deepEqual(
    [...memory.slice(0xa500, 0xc000)],
    [...new Uint8Array(0x1b00).fill(0xa5)],
  );
  assert.deepEqual([...memory.slice(0xc000, 0xdfe0)], [...stackCanary]);
});

Deno.test("page release rejects the protected intervals", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const result = call("PAGE_INI", 0x8f00);
  assert.equal(result.carry, 0);
  for (const address of [0x8e00, 0x8f00, 0xa500, 0xb000, 0xc000, 0xdf00]) {
    const rejected = call("PAGE_REL", address, 1);
    assert.equal(rejected.carry, 1, `release ${address.toString(16)}`);
    assert.equal(rejected.status, 2);
  }
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), 21);
});
