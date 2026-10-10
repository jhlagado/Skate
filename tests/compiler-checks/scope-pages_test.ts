import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";
import { predictHeapLimit } from "../../tools/compiler-checks/heap-layout.mjs";

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
  // Unless a test says otherwise, PAGE_NEW may pass the soft line, as it may
  // after a collection.
  function call(name: string, hl = 0, de = 0, hard = true) {
    if (name === "PAGE_NEW") {
      memory[assembled.address("PAGE_HRD")] = hard ? 1 : 0;
    }
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

// Without a BDOS the maps all sit below the fixed bands, 40 bytes a heap
// page, and the heap ends at the highest page that leaves them room.
function heapLimit(
  assembled: Awaited<ReturnType<typeof loadAssembly>>,
  imageEnd: number,
) {
  return predictHeapLimit(
    imageEnd,
    0,
    assembled.address("RT_OPLO"),
    assembled.address("RT_TOP"),
  );
}

Deno.test("page setup rejects an image that leaves too few pages", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory.fill(0xa5, 0xcb00, 0xcc00);
  const before = memory.slice(0xcb00, 0xcc00);
  const result = call("PAGE_INI", 0xcc00);
  assert.equal(result.carry, 1);
  assert.equal(result.status, 2);
  assert.deepEqual(memory.slice(0xcb00, 0xcc00), before);
  assert.equal(memory[assembled.address("PAGE_OK")], 0);
});

Deno.test("the smallest heap holds page management and three pages", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const result = call("PAGE_INI", 0xc901);
  assert.equal(result.carry, 0);
  assert.equal(readWord(memory, assembled.address("PAGE_ORG")), 0xca00);
  assert.equal(readWord(memory, assembled.address("HEAP_LIM")), 0xce00);
  assert.equal(readWord(memory, assembled.address("PAGE_LO")), 4);
  assert.equal(readWord(memory, assembled.address("PAGE_CNT")), 4);
  assert.equal(readWord(memory, assembled.address("PAGE_SYS")), 1);
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), 3);
  assert.equal(call("PAGE_NEW", 3).carry, 0);
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

Deno.test("the maps cover the heap and sit between it and the bands", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const full = call("PAGE_INI", 0x8e01);
  assert.equal(full.carry, 0);
  const limit = readWord(memory, assembled.address("HEAP_LIM"));
  assert.equal(limit, heapLimit(assembled, 0x8e01));
  assert.equal(limit, 0xc600);
  const pages = (limit - 0x8f00) >> 8;
  assert.equal(memory[assembled.address("MAP_PGS")], pages);
  assert.equal(readWord(memory, assembled.address("MAP_LEN")), 16 * pages);
  assert.equal(readWord(memory, assembled.address("CL_MAP")), limit);
  assert.equal(
    readWord(memory, assembled.address("GC_MARKS")),
    limit + 16 * pages,
  );
  assert.equal(
    readWord(memory, assembled.address("BND_MAP")),
    limit + 32 * pages,
  );
  assert.ok(limit + 40 * pages <= assembled.address("RT_OPLO"));
  assert.equal(readWord(memory, assembled.address("PAGE_HI")), 0);
  assert.equal(readWord(memory, assembled.address("PAGE_LO")), pages);
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), pages - 1);
  const last = call("PAGE_NEW", pages - 1);
  assert.equal(last.carry, 0);
  assert.equal(last.hl, 0x9000);
  assert.equal(call("PAGE_NEW", 1).carry, 1);
});

Deno.test("the maps go above the bands when the BDOS leaves room", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory[5] = 0xc3;
  writeWord(memory, 6, 0xf206);
  assert.equal(call("PAGE_INI", 0x8e01).carry, 0);
  const limit = readWord(memory, assembled.address("HEAP_LIM"));
  assert.equal(
    limit,
    predictHeapLimit(
      0x8e01,
      0xf206,
      assembled.address("RT_OPLO"),
      assembled.address("RT_TOP"),
    ),
  );
  const top = assembled.address("RT_TOP");
  const pages = (limit - 0x8f00) >> 8;
  assert.equal(readWord(memory, assembled.address("CL_MAP")), top);
  assert.equal(
    readWord(memory, assembled.address("GC_MARKS")),
    top + 16 * pages,
  );
  assert.ok(limit > 0xc600, "the heap gained the room the maps left");
  memory[5] = 0;
});

Deno.test("the heap stays 4 KB below the stack until a collection", async () => {
  const { memory, call, assembled } = await pageRuntime();
  assert.equal(call("PAGE_INI", 0xa201).carry, 0);
  assert.equal(readWord(memory, assembled.address("HEAP_LIM")), 0xc900);
  // Pages A400H..B8FFH lie below the soft line, B900H, 16 pages below
  // HEAP_LIM; the next would pass it.
  const below = call("PAGE_NEW", 21, 0, false);
  assert.equal(below.carry, 0);
  assert.equal(below.hl, 0xa400);
  const soft = call("PAGE_NEW", 1, 0, false);
  assert.equal(soft.carry, 1);
  assert.equal(soft.status, 1);
  const hard = call("PAGE_NEW", 1, 0, true);
  assert.equal(hard.carry, 0);
  assert.equal(hard.hl, 0xb900);
  assert.equal(memory[assembled.address("PAGE_HRD")], 0);
});

Deno.test("runtime startup publishes page readiness and rejects an invalid image", async () => {
  const { assembled, memory, call } = await pageRuntime();
  runStartup(assembled, memory, 0x8f00, false);
  assert.equal(memory[assembled.address("PAGE_OK")], 1);
  assert.equal(readWord(memory, assembled.address("PAGE_ORG")), 0x8f00);
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), 53);
  assert.equal(memory[assembled.address("PS_COUNT")], 1);
  const bindingMap = readWord(memory, assembled.address("BND_MAP"));
  assert.ok(
    [...memory.slice(
      bindingMap,
      bindingMap + readWord(memory, assembled.address("MAP_LEN")) / 2,
    )].every((value) => value === 0),
    "binding-start bitmap was not cleared at startup",
  );
  const next = call("PAGE_NEW", 1);
  assert.equal(next.carry, 0);
  assert.equal(next.hl, 0x9100);

  // An image that leaves too few pages is refused before anything is written.
  memory.fill(0xa5, 0xcb00, 0xcc00);
  const beforeFailure = memory.slice(0xcb00, 0xcc00);
  runStartup(assembled, memory, 0xcc00, true);
  assert.equal(memory[assembled.address("PAGE_OK")], 0);
  assert.deepEqual([...memory.slice(0xcb00, 0xcc00)], [...beforeFailure]);
});

Deno.test("page runs honor bitmap boundaries, fragmentation and canaries", async () => {
  const { memory, call, assembled } = await pageRuntime();
  memory.fill(0xa5, 0x6000, 0xb800);
  memory.fill(0xa5, 0xb800, 0xd300);
  memory.fill(0xa5, 0xc000, 0xdfe0);
  const result = call("PAGE_INI", 0x6f00);
  assert.equal(result.carry, 0);
  const address = (name: string) => assembled.address(name);
  assert.equal(readWord(memory, address("PAGE_ORG")), 0x6f00);
  assert.equal(readWord(memory, address("PAGE_LO")), 83);
  assert.equal(readWord(memory, address("PAGE_CNT")), 83);
  assert.equal(readWord(memory, address("PAGE_LEN")), 11);
  assert.equal(readWord(memory, address("PAGE_SYS")), 1);
  assert.equal(readWord(memory, address("PAGE_CAP")), 82);
  assert.equal(readWord(memory, address("PAGE_MIN")), 0x7000);
  const bitmap = readWord(memory, address("PAGE_MAP"));
  assert.deepEqual(
    [...memory.slice(bitmap, bitmap + 11)],
    [0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x07],
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
  assert.equal(readWord(memory, address("PAGE_CAP")), 77);
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
  const beforeDoubleFree = memory.slice(bitmap, bitmap + 11);
  const doubleFree = call("PAGE_REL", reused.hl, 3);
  assert.equal(doubleFree.carry, 1);
  assert.equal(doubleFree.status, 2);
  assert.deepEqual([...memory.slice(bitmap, bitmap + 11)], [
    ...beforeDoubleFree,
  ]);
  assert.equal(call("PAGE_REL", fragmented.hl, 4).carry, 0);

  const five = call("PAGE_NEW", 5);
  assert.equal(five.carry, 0);
  assert.equal(five.hl, 0x7000);
  const seven = call("PAGE_NEW", 7);
  assert.equal(seven.carry, 0);
  assert.equal(seven.hl, 0x7500);
  assert.equal(readWord(memory, address("PAGE_CAP")), 70);
  const lowRemainder = call("PAGE_NEW", 20);
  assert.equal(lowRemainder.carry, 0);
  assert.equal(lowRemainder.hl, 0x7c00);
  assert.equal(readWord(memory, address("PAGE_CAP")), 50);
  const highOne = call("PAGE_NEW", 1);
  assert.equal(highOne.carry, 0);
  assert.equal(highOne.hl, 0x9000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 49);
  assert.equal(call("PAGE_REL", five.hl, 5).carry, 0);
  assert.equal(call("PAGE_REL", seven.hl, 7).carry, 0);
  assert.equal(call("PAGE_REL", lowRemainder.hl, 20).carry, 0);
  assert.equal(call("PAGE_REL", highOne.hl, 1).carry, 0);
  assert.equal(readWord(memory, address("PAGE_CAP")), 82);
  assert.deepEqual(
    [...memory.slice(bitmap, bitmap + 11)],
    [0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x07],
  );
  assert.deepEqual([...memory.slice(0x6000, 0x6f00)], [...lowCanary]);
  assert.deepEqual([...memory.slice(0xc000, 0xdfe0)], [...stackCanary]);

  const lowAll = call("PAGE_NEW", 32);
  assert.equal(lowAll.carry, 0);
  assert.equal(lowAll.hl, 0x7000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 50);
  const highAll = call("PAGE_NEW", 50);
  assert.equal(highAll.carry, 0);
  assert.equal(highAll.hl, 0x9000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 0);
  const exhausted = call("PAGE_NEW", 1);
  assert.equal(exhausted.carry, 1);
  assert.equal(exhausted.status, 1);
  assert.equal(readWord(memory, address("PAGE_CAP")), 0);
  assert.equal(call("PAGE_REL", highAll.hl, 50).carry, 0);
  const highAgain = call("PAGE_NEW", 50);
  assert.equal(highAgain.carry, 0);
  assert.equal(highAgain.hl, 0x9000);
  assert.equal(readWord(memory, address("PAGE_CAP")), 0);
  assert.equal(call("PAGE_REL", highAgain.hl, 50).carry, 0);
  assert.equal(call("PAGE_REL", lowAll.hl, 32).carry, 0);
  assert.equal(readWord(memory, address("PAGE_CAP")), 82);
  assert.deepEqual([...memory.slice(0x6000, 0x6f00)], [...lowCanary]);
  assert.deepEqual([...memory.slice(0xc000, 0xdfe0)], [...stackCanary]);
});

Deno.test("page release rejects the protected intervals", async () => {
  const { memory, call, assembled } = await pageRuntime();
  const result = call("PAGE_INI", 0x8f00);
  assert.equal(result.carry, 0);
  for (const address of [0x8e00, 0x8f00, 0xb800, 0xc000, 0xce00, 0xdf00]) {
    const rejected = call("PAGE_REL", address, 1);
    assert.equal(rejected.carry, 1, `release ${address.toString(16)}`);
    assert.equal(rejected.status, 2);
  }
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), 54);
});
