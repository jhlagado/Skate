import assert from "node:assert/strict";
import { loadAssembly } from "../z80.ts";

function writeWord(memory: Uint8Array, address: number, value: number) {
  memory[address] = value & 255;
  memory[address + 1] = value >>> 8;
}

async function managedRuntime(withPairs = false) {
  const assembled = await loadAssembly(
    "src/runtime/image.asm",
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

Deno.test("three-byte bindings descend, load and store without changing their shape", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime();
  const first = call("SRTCELL");
  assert.equal(first.carry, 0);
  assert.equal(first.payload, readWord(memory, assembled.address("SRTBPGBA")));
  assert.equal(
    readWord(memory, assembled.address("SRTBEND")),
    first.payload + 0x100,
  );

  cpu.d = first.payload >>> 8;
  cpu.e = first.payload & 255;
  cpu.a = 3;
  cpu.h = 0x12;
  cpu.l = 0x34;
  const stored = call("SRTBSTOR", 0x1234);
  assert.equal(stored.tag, 3);
  assert.equal(stored.payload, 0x1234);
  assert.equal(memory[first.payload + 2], 0x2b);

  const loaded = call("SRTBLOAD", first.payload);
  assert.equal(loaded.tag, 3);
  assert.equal(loaded.payload, 0x1234);

  cpu.d = first.payload >>> 8;
  cpu.e = first.payload & 255;
  cpu.a = 3;
  cpu.h = 0xab;
  cpu.l = 0xcd;
  const changed = call("SRTBSET", 0xabcd);
  assert.equal(changed.payload, 0xabcd);
  assert.equal(memory[first.payload + 2], 0x2b);
});

Deno.test("unreachable bindings return to a same-sized free block", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime();
  const binding = call("SRTCELL").payload;
  cpu.d = binding >>> 8;
  cpu.e = binding & 255;
  cpu.a = 3;
  call("SRTBSTOR", 0x1234);
  const map = 0xd700;
  writeWord(memory, map, binding);
  writeWord(memory, assembled.address("SRTENV"), map);
  memory[assembled.address("SRTSLOTS")] = 1;

  call("SRTGC");
  assert.equal(memory[binding + 2] & 0x70, 0x20);

  writeWord(memory, assembled.address("SRTENV"), 0);
  memory[assembled.address("SRTSLOTS")] = 0;
  call("SRTGC");
  assert.equal(readWord(memory, assembled.address("SRTBHEAD")), 0);
  assert.equal(memory[assembled.address("SRTBPGN")], 0);

  const reused = call("SRTCELL");
  assert.equal(reused.payload, binding);
  assert.equal(memory[binding + 2], 0x20);
});

Deno.test("retained binding pages rebuild free cells after repeated collection", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const allocated: number[] = [];
  for (let index = 0; index < 85; index++) {
    allocated.push(call("SRTCELL").payload);
  }
  const survivor = allocated[0];
  const map = 0xd700;
  writeWord(memory, map, survivor);
  writeWord(memory, assembled.address("SRTENV"), map);
  memory[assembled.address("SRTSLOTS")] = 1;

  call("SRTGC");
  assert.notEqual(
    readWord(memory, assembled.address("SRTBHEAD")),
    0,
    "the first collection should expose the dead cells",
  );
  call("SRTGC");
  assert.notEqual(
    readWord(memory, assembled.address("SRTBHEAD")),
    0,
    "a retained page must rebuild its dead cells on the second collection",
  );

  const reused = call("SRTCELL").payload;
  assert.notEqual(reused, survivor);
  assert.ok(
    allocated.includes(reused),
    `binding allocation escaped the retained page: ${reused.toString(16)}`,
  );
  assert.equal(memory[reused + 2], 0x20);
});

Deno.test("an active uninitialized binding remains allocated through collection", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const binding = call("SRTCELL").payload;
  const map = 0xd700;
  writeWord(memory, map, binding);
  writeWord(memory, assembled.address("SRTENV"), map);
  memory[assembled.address("SRTSLOTS")] = 1;

  call("SRTGC");
  assert.equal(memory[binding + 2], 0x20);
  assert.notEqual(call("SRTCELL").payload, binding);
});

Deno.test("virgin binding flags cannot keep a page alive", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const freeBefore = readWord(memory, assembled.address("SRTPGFRE"));
  const binding = call("SRTCELL").payload;
  const page = readWord(memory, assembled.address("SRTBPGBA"));
  const virgin = page + 3;

  // A stale mark-looking byte in an unallocated slot must not pin the page.
  memory[virgin + 2] = 0x40;
  assert.equal(readWord(memory, assembled.address("SRTPGFRE")), freeBefore - 1);
  call("SRTGC");

  assert.equal(readWord(memory, assembled.address("SRTBPGN")), 0);
  assert.equal(readWord(memory, assembled.address("SRTPGFRE")), freeBefore);
  assert.equal(memory[virgin + 2], 0);
  assert.equal(call("SRTCELL").payload, binding);
});

Deno.test("tail-owned cells clear their old value and initialization state", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const binding = call("SRTCELL").payload;
  const map = 0xd700;
  const descriptor = 0xc100;
  writeWord(memory, map, binding);
  writeWord(memory, assembled.address("SRTENV"), map);
  writeWord(memory, assembled.address("SRTDESC"), descriptor);
  memory[assembled.address("SRTSLOTS")] = 1;
  memory[descriptor + 12] = 1;
  memory[binding] = 0x34;
  memory[binding + 1] = 0x12;
  memory[binding + 2] = 0x2b;

  call("SRTOWN");
  assert.deepEqual([...memory.slice(binding, binding + 3)], [0, 0, 0x20]);
});

Deno.test("closure classes round at the supported 128-slot boundary", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const slots = assembled.address("SRTCLN");
  const rounded = assembled.address("SRTCLSZ");
  const index = assembled.address("SRTCLIDX");
  for (
    const [count, size, classIndex] of [[0, 4, 0], [1, 4, 0], [127, 256, 63], [
      128,
      260,
      64,
    ]]
  ) {
    memory[slots] = count;
    call("SRTCLSIZ");
    assert.equal(readWord(memory, rounded), size, `slot count ${count}`);
    assert.equal(memory[index], classIndex, `class ${count}`);
  }
});

Deno.test("large closures own and release a contiguous two-page run", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xc100;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 128;

  const closure = call("SRTMAKE", descriptor);
  assert.equal(closure.tag, 2);
  const closureBase = closure.payload;
  assert.equal(memory[assembled.address("SRTCLOWN")], 0x41);
  assert.equal(memory[assembled.address("SRTCLOWN") + 1], 0xff);
  assert.equal(
    readWord(memory, assembled.address("SRTCLCUR")),
    closureBase + 0x200,
  );

  const root = 0xd800;
  writeWord(memory, root, closure.payload);
  memory[root + 2] = 2;
  memory[root + 3] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), root);
  writeWord(memory, assembled.address("SRTGEND"), root + 4);
  call("SRTGC");
  assert.equal(memory[assembled.address("SRTCLOWN")], 0x41);

  writeWord(memory, assembled.address("SRTGBASE"), 0);
  writeWord(memory, assembled.address("SRTGEND"), 0);
  call("SRTGC");
  assert.equal(memory[assembled.address("SRTCLOWN")], 0);
  assert.equal(memory[assembled.address("SRTCLOWN") + 1], 0);
  assert.equal(call("SRTMAKE", descriptor).payload, closureBase);
});

Deno.test("dead closures are reclaimed by class and live closures remain published", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xc100;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;
  memory[descriptor + 28] = 0;

  const dead = call("SRTMAKE", descriptor);
  const live = call("SRTMAKE", descriptor);
  assert.equal(dead.tag, 2);
  const closureBase = dead.payload;
  assert.equal(live.payload, closureBase + 4);

  const root = 0x7000;
  writeWord(memory, root, live.payload);
  memory[root + 2] = 2;
  memory[root + 3] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), root);
  writeWord(memory, assembled.address("SRTGEND"), root + 4);
  call("SRTGC");
  writeWord(memory, assembled.address("SRTCLOBJ"), dead.payload);
  assert.equal(call("SRTCLSTA").tag, 0, "dead closure start was retained");
  writeWord(memory, assembled.address("SRTCLOBJ"), live.payload);
  assert.notEqual(call("SRTCLSTA").tag, 0, "live closure start was lost");
  const freeHead = readWord(memory, assembled.address("SRTCFREE"));
  assert.ok(freeHead >= closureBase && freeHead < closureBase + 0x100);

  const reused = call("SRTMAKE", descriptor);
  assert.equal(reused.tag, 2);
  assert.equal(reused.payload, freeHead);

  writeWord(memory, assembled.address("SRTGBASE"), 0);
  writeWord(memory, assembled.address("SRTGEND"), 0);
  call("SRTGC");
  assert.equal(memory[assembled.address("SRTCLOWN")], 0);
  const republished = call("SRTMAKE", descriptor);
  assert.equal(republished.payload, closureBase);
});

Deno.test("closure pages share the pool with binding pages", async () => {
  const { assembled, call } = await managedRuntime();
  const binding = call("SRTCELL");
  assert.equal(binding.carry, 0);
  const descriptor = 0xc100;
  const memory = assembled.runtime.hardware.memory;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;
  const closure = call("SRTMAKE", descriptor);
  assert.equal(closure.tag, 2);
  assert.notEqual(closure.payload >>> 8, binding.payload >>> 8);
  assert.notEqual(memory[assembled.address("SRTBPGN")], 0);
});

Deno.test("a two-page closure claims adjacent pages in the shared pool", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xc100;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 128;
  const closure = call("SRTMAKE", descriptor);
  assert.equal(closure.tag, 2);
  const owners = assembled.address("SRTCLOWN");
  assert.equal(memory[owners], 0x41);
  assert.equal(memory[owners + 1], 0xff);
});

Deno.test("a live two-page closure does not hide a later dead page", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const wideDescriptor = 0xc100;
  const narrowDescriptor = 0xc130;
  writeWord(memory, wideDescriptor, 0x4000);
  memory[wideDescriptor + 3] = 128;
  writeWord(memory, narrowDescriptor, 0x4000);
  memory[narrowDescriptor + 3] = 1;

  const wide = call("SRTMAKE", wideDescriptor);
  const narrow = call("SRTMAKE", narrowDescriptor);
  const wideBase = wide.payload;
  assert.equal(narrow.payload, wideBase + 0x200);
  const root = 0xd800;
  writeWord(memory, root, wide.payload);
  memory[root + 2] = 2;
  memory[root + 3] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), root);
  writeWord(memory, assembled.address("SRTGEND"), root + 4);
  call("SRTGC");

  const owners = assembled.address("SRTCLOWN");
  assert.equal(memory[owners], 0x41);
  assert.equal(memory[owners + 1], 0xff);
  assert.equal(memory[owners + 2], 0);
  writeWord(memory, assembled.address("SRTCLOBJ"), narrow.payload);
  assert.equal(call("SRTCLSTA").tag, 0);
  const reused = call("SRTMAKE", narrowDescriptor);
  assert.ok(
    reused.payload >= narrow.payload && reused.payload < narrow.payload + 0x100,
  );
});

Deno.test("a partial closure slab can refill every freed slot", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xc100;
  const root = 0xd800;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;

  const allocated: number[] = [];
  for (let index = 0; index < 64; index++) {
    allocated.push(call("SRTMAKE", descriptor).payload);
  }
  writeWord(memory, root, allocated[0]);
  memory[root + 2] = 2;
  memory[root + 3] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), root);
  writeWord(memory, assembled.address("SRTGEND"), root + 4);
  call("SRTGC");

  const refilled = new Set<number>();
  for (let index = 0; index < 63; index++) {
    refilled.add(call("SRTMAKE", descriptor).payload);
  }
  assert.equal(refilled.size, 63);
  for (const address of refilled) {
    assert.ok(address >= allocated[1] && address < allocated[0] + 0x100);
  }
});

Deno.test("closure churn beyond sixteen kilobytes reuses a bounded live set", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xc100;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 128;
  const root = 0xd800;
  const owners = assembled.address("SRTCLOWN");
  const cumulativeBytes = 8 * 32 * 260;
  assert.ok(cumulativeBytes > 16 * 1024);

  let firstBase = 0;
  for (let batch = 0; batch < 8; batch++) {
    let live = 0;
    for (let index = 0; index < 32; index++) {
      live = call("SRTMAKE", descriptor).payload;
      if (batch === 0 && index === 0) firstBase = live;
    }
    writeWord(memory, root, live);
    memory[root + 2] = 2;
    memory[root + 3] = 1;
    writeWord(memory, assembled.address("SRTGBASE"), root);
    writeWord(memory, assembled.address("SRTGEND"), root + 4);
    call("SRTGC");

    let ownedPages = 0;
    for (let page = 0; page < 128; page++) {
      if (memory[owners + page] !== 0) ownedPages++;
    }
    assert.equal(
      ownedPages,
      2,
      `batch ${batch} retained more than one closure`,
    );
  }
  assert.ok(
    readWord(memory, assembled.address("SRTCLCUR")) >= firstBase + 0x200,
  );
});

Deno.test("a closure capture keeps a pair alive and releases both together", async () => {
  const { assembled, memory, call } = await managedRuntime(true);
  const descriptor = 0xc100;
  const map = 0xd700;
  const root = 0xd800;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;
  memory[descriptor + 28] = 1;

  const pair = call("SRTMAKEP");
  assert.equal(pair.tag, 1);
  const binding = call("SRTCELL").payload;
  const cpu = assembled.runtime.cpu;
  cpu.d = binding >>> 8;
  cpu.e = binding & 255;
  cpu.a = 1;
  call("SRTBSTOR", pair.payload);
  writeWord(memory, map, binding);
  writeWord(memory, assembled.address("SRTENV"), map);
  memory[assembled.address("SRTSLOTS")] = 1;
  const closure = call("SRTMAKE", descriptor);
  writeWord(memory, assembled.address("SRTENV"), 0);
  memory[assembled.address("SRTSLOTS")] = 0;

  // Close the graph through the pair's CDR so collection must handle a cycle.
  writeWord(memory, pair.payload + 2, closure.payload);
  memory[pair.payload + 4] = (memory[pair.payload + 4] & 0xc7) | 0x10;

  writeWord(memory, root, closure.payload);
  memory[root + 2] = 2;
  memory[root + 3] = 1;
  writeWord(memory, assembled.address("SRTGBASE"), root);
  writeWord(memory, assembled.address("SRTGEND"), root + 4);
  call("SRTGC");
  cpu.a = 1;
  assert.equal(call("SRTPCHK", pair.payload).carry, 0);

  writeWord(memory, assembled.address("SRTGBASE"), 0);
  writeWord(memory, assembled.address("SRTGEND"), 0);
  call("SRTGC");
  cpu.a = 1;
  assert.equal(call("SRTPCHK", pair.payload).carry, 1);
});

function readWord(memory: Uint8Array, address: number) {
  return memory[address] | memory[address + 1] << 8;
}
