import assert from "node:assert/strict";
import {
  managedRuntime,
  readWord,
  writeWord,
} from "./scope-runtime-fixture.ts";

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
  memory[map + 2] = 0;
  memory[map + 3] = 2;
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
  memory[map + 2] = 0;
  memory[map + 3] = 2;
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
  memory[map + 2] = 0;
  memory[map + 3] = 2;
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
  memory[map + 2] = 0;
  memory[map + 3] = 2;
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

Deno.test("promotion keeps an inline pair live when allocation collects", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  const map = 0xd700;
  const pair = call("SRTMAKEP");
  assert.equal(pair.tag, 1);

  // Leave one binding unreachable so the forced collection can reclaim
  // storage for the promotion allocation.
  const dead = call("SRTCELL").payload;
  writeWord(memory, map, pair.payload);
  memory[map + 2] = pair.tag;
  memory[map + 3] = 1;
  writeWord(memory, map + 4, 0x1357);
  memory[map + 6] = 3;
  memory[map + 7] = 1;
  writeWord(memory, assembled.address("SRTENV"), map);
  memory[assembled.address("SRTSLOTS")] = 2;

  // Exhaust the current page.  Allocate every remaining page through the
  // page manager so the binding-page directory stays structurally valid while
  // the next binding allocation is forced through collection.
  writeWord(
    memory,
    assembled.address("SRTBPGP"),
    readWord(memory, assembled.address("SRTBPGED")),
  );
  for (let index = 0; index < 256; index++) {
    const page = call("SRTGPALL", 1);
    if (page.carry) break;
    assert.equal(page.payload & 0xff, 0);
    assert.ok(index < 255, "page manager did not report exhaustion");
  }

  cpu.a = 0;
  const promoted = call("SRTPROM");
  assert.equal(promoted.carry, 0);
  assert.equal(readWord(memory, assembled.address("SRTGCNT")), 1);
  assert.equal(memory[map + 3], 2);
  assert.deepEqual(
    [...memory.slice(map + 4, map + 8)],
    [0x57, 0x13, 3, 1],
  );
  const cell = readWord(memory, map);
  assert.equal(cell, dead);
  const loaded = call("SRTBLOAD", cell);
  assert.equal(loaded.tag, pair.tag);
  assert.equal(loaded.payload, pair.payload);
  cpu.a = 1;
  assert.equal(call("SRTPCHK", pair.payload).carry, 0);
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

Deno.test("closure creation clears every uncaptured environment byte", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xc100;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 3;
  memory[descriptor + 28] = 0;

  const closure = call("SRTMAKE", descriptor);
  assert.equal(closure.tag, 2);
  const extent = readWord(memory, assembled.address("SRTCLSZ"));
  assert.equal(extent, 8);
  assert.deepEqual(
    [...memory.slice(closure.payload + 2, closure.payload + extent)],
    [0, 0, 0, 0, 0, 0],
  );
});

Deno.test("activation maps keep helper calls above the collector worklist", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const guard = assembled.address("SRTSTKGU");
  const worklistEnd = assembled.address("SRTMKBE");
  assert.equal(guard, worklistEnd + 0x100);

  memory.fill(0xa5, 0xd000, worklistEnd);
  const descriptor = 0xc100;
  writeWord(memory, assembled.address("SRTDESC"), descriptor);
  memory[descriptor + 12] = 0;
  memory[descriptor + 28] = 0;
  memory[assembled.address("SRTSLOTS")] = 1;
  writeWord(memory, assembled.address("SRTENV"), 0);

  // POP HL in SRTENVIN advances this return stack by two bytes.  Four bytes
  // for one active slot therefore put the candidate map exactly at the guard.
  cpu.pc = assembled.address("SRTENVIN");
  cpu.sp = guard + 2;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 1_000_000, "activation setup did not return");
    assembled.runtime.step();
  }

  assert.equal(readWord(memory, assembled.address("SRTENV")), guard);
  assert.deepEqual(
    [...memory.slice(0xd000, worklistEnd)],
    new Array(0x400).fill(0xa5),
  );
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
  memory[map + 2] = 0;
  memory[map + 3] = 2;
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
