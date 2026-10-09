import assert from "node:assert/strict";
import {
  managedRuntime,
  readWord,
  writeWord,
} from "./scope-runtime-fixture.ts";

Deno.test("four-byte bindings descend, load and store with a reserved byte", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime();
  const first = call("HEAP_NEW");
  assert.equal(first.carry, 0);
  assert.equal(first.payload, readWord(memory, assembled.address("BND_BASE")));
  assert.equal(
    readWord(memory, assembled.address("BND_TOP")),
    first.payload + 0x100,
  );

  cpu.d = first.payload >>> 8;
  cpu.e = first.payload & 255;
  cpu.a = 3;
  cpu.c = 0;
  cpu.h = 0x12;
  cpu.l = 0x34;
  const stored = call("HEAP_PUT", 0x1234);
  assert.equal(stored.tag, 3);
  assert.equal(stored.payload, 0x1234);
  assert.equal(memory[first.payload + 2], 0);
  assert.equal(memory[first.payload + 3], 0x53);

  const loaded = call("HEAP_GET", first.payload);
  assert.equal(loaded.tag, 3);
  assert.equal(loaded.payload, 0x1234);

  cpu.d = first.payload >>> 8;
  cpu.e = first.payload & 255;
  cpu.a = 3;
  cpu.c = 0;
  cpu.h = 0xab;
  cpu.l = 0xcd;
  const changed = call("HEAP_SET", 0xabcd);
  assert.equal(changed.payload, 0xabcd);
  assert.equal(memory[first.payload + 2], 0);
  assert.equal(memory[first.payload + 3], 0x53);
});

Deno.test("unreachable bindings return to a same-sized free block", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime();
  const binding = call("HEAP_NEW").payload;
  cpu.d = binding >>> 8;
  cpu.e = binding & 255;
  cpu.a = 3;
  call("HEAP_PUT", 0x1234);
  const map = 0xd700;
  writeWord(memory, map, binding);
  memory[map + 2] = 0;
  memory[map + 3] = 0x20; // Promoted.
  writeWord(memory, assembled.address("ENV_CUR"), map);
  memory[assembled.address("SLOT_CNT")] = 1;

  call("GC");
  assert.equal(memory[binding + 3] & 0xe0, 0x40);

  writeWord(memory, assembled.address("ENV_CUR"), 0);
  memory[assembled.address("SLOT_CNT")] = 0;
  call("GC");
  assert.equal(readWord(memory, assembled.address("BND_FREE")), 0);
  assert.equal(memory[assembled.address("BND_CNT")], 0);

  const reused = call("HEAP_NEW");
  assert.equal(reused.payload, binding);
  assert.equal(memory[binding + 3], 0x40);
});

Deno.test("retained binding pages rebuild free cells after repeated collection", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const allocated: number[] = [];
  for (let index = 0; index < 64; index++) {
    allocated.push(call("HEAP_NEW").payload);
  }
  const survivor = allocated[0];
  const map = 0xd700;
  writeWord(memory, map, survivor);
  memory[map + 2] = 0;
  memory[map + 3] = 0x20; // Promoted.
  writeWord(memory, assembled.address("ENV_CUR"), map);
  memory[assembled.address("SLOT_CNT")] = 1;

  call("GC");
  assert.notEqual(
    readWord(memory, assembled.address("BND_FREE")),
    0,
    "the first collection should expose the dead cells",
  );
  call("GC");
  assert.notEqual(
    readWord(memory, assembled.address("BND_FREE")),
    0,
    "a retained page must rebuild its dead cells on the second collection",
  );

  const reused = call("HEAP_NEW").payload;
  assert.notEqual(reused, survivor);
  assert.ok(
    allocated.includes(reused),
    `binding allocation escaped the retained page: ${reused.toString(16)}`,
  );
  assert.equal(memory[reused + 3], 0x40);
});

Deno.test("an active uninitialized binding remains allocated through collection", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const binding = call("HEAP_NEW").payload;
  const map = 0xd700;
  writeWord(memory, map, binding);
  memory[map + 2] = 0;
  memory[map + 3] = 0x20; // Promoted.
  writeWord(memory, assembled.address("ENV_CUR"), map);
  memory[assembled.address("SLOT_CNT")] = 1;

  call("GC");
  assert.equal(memory[binding + 3], 0x40);
  assert.notEqual(call("HEAP_NEW").payload, binding);
});

Deno.test("virgin binding flags cannot keep a page alive", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const freeBefore = readWord(memory, assembled.address("PAGE_CAP"));
  const binding = call("HEAP_NEW").payload;
  const page = readWord(memory, assembled.address("BND_BASE"));
  const virgin = page + 4;

  // A stale mark-looking byte in an unallocated slot must not pin the page.
  memory[virgin + 3] = 0x80; // Marked but never allocated.
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), freeBefore - 1);
  call("GC");

  assert.equal(readWord(memory, assembled.address("BND_CNT")), 0);
  assert.equal(readWord(memory, assembled.address("PAGE_CAP")), freeBefore);
  assert.equal(memory[virgin + 3], 0);
  assert.equal(call("HEAP_NEW").payload, binding);
});

Deno.test("tail-owned cells clear their old value and initialization state", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const binding = call("HEAP_NEW").payload;
  const map = 0xd700;
  const descriptor = 0xe300;
  writeWord(memory, map, binding);
  memory[map + 2] = 0;
  memory[map + 3] = 0x20; // Promoted.
  writeWord(memory, assembled.address("ENV_CUR"), map);
  writeWord(memory, assembled.address("DESC_CUR"), descriptor);
  memory[assembled.address("SLOT_CNT")] = 1;
  memory[descriptor + 5] = 1; // One mask byte each:
  memory[descriptor + 6] = 1; // owned slots,
  memory[descriptor + 7] = 0; // captured slots.
  memory[binding] = 0x34;
  memory[binding + 1] = 0x12;
  memory[binding + 3] = 0x53;

  call("ENV_OWN");
  assert.deepEqual([...memory.slice(binding, binding + 4)], [0, 0, 0, 0x40]);
});

Deno.test("promoted recursive clear resets heap binding metadata", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime();
  const binding = call("HEAP_NEW").payload;
  const map = 0xd700;
  memory[binding] = 0x34;
  memory[binding + 1] = 0x12;
  memory[binding + 2] = 0;
  memory[binding + 3] = 0x53;
  writeWord(memory, map, binding);
  memory[map + 2] = 0;
  memory[map + 3] = 0x20; // Promoted.
  writeWord(memory, assembled.address("ENV_CUR"), map);
  memory[assembled.address("SLOT_CNT")] = 1;
  cpu.b = 0;

  call("FRM_CLR");

  assert.deepEqual([...memory.slice(binding, binding + 4)], [
    0x34,
    0x12,
    0,
    0x40,
  ]);
});

Deno.test("promotion keeps an inline pair live when allocation collects", async () => {
  const { assembled, memory, cpu, call } = await managedRuntime(true);
  const map = 0xd700;
  const pair = call("PAIR_NEW");
  assert.equal(pair.tag, 1);

  // Leave one binding unreachable so the forced collection can reclaim
  // storage for the promotion allocation.
  const dead = call("HEAP_NEW").payload;
  writeWord(memory, map, pair.payload);
  memory[map + 2] = 0;
  memory[map + 3] = 0x10 | pair.tag; // Initialized inline value.
  writeWord(memory, map + 4, 0x1357);
  memory[map + 6] = 3;
  memory[map + 7] = 1;
  writeWord(memory, assembled.address("ENV_CUR"), map);
  memory[assembled.address("SLOT_CNT")] = 2;

  // Exhaust the current page.  Allocate every remaining page through the
  // page manager so the binding-page directory stays structurally valid while
  // the next binding allocation is forced through collection.
  writeWord(
    memory,
    assembled.address("BND_NEXT"),
    readWord(memory, assembled.address("BND_END")),
  );
  for (let index = 0; index < 256; index++) {
    const page = call("PAGE_NEW", 1);
    if (page.carry) break;
    assert.equal(page.payload & 0xff, 0);
    assert.ok(index < 255, "page manager did not report exhaustion");
  }

  cpu.a = 0;
  const promoted = call("SLOT_BOX");
  assert.equal(promoted.carry, 0);
  assert.equal(readWord(memory, assembled.address("CNT_GC")), 1);
  assert.equal(memory[map + 3], 0x20);
  assert.deepEqual(
    [...memory.slice(map + 4, map + 8)],
    [0x57, 0x13, 3, 1],
  );
  const cell = readWord(memory, map);
  assert.equal(cell, dead);
  const loaded = call("HEAP_GET", cell);
  assert.equal(loaded.tag, pair.tag);
  assert.equal(loaded.payload, pair.payload);
  cpu.a = 1;
  assert.equal(call("PAIR_CHK", pair.payload).carry, 0);
});

Deno.test("closure classes round at the supported 128-slot boundary", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const slots = assembled.address("CL_COUNT");
  const rounded = assembled.address("CL_SIZE");
  const index = assembled.address("CL_CLASS");
  for (
    const [count, size, classIndex] of [[0, 4, 0], [1, 4, 0], [127, 256, 63], [
      128,
      260,
      64,
    ]]
  ) {
    memory[slots] = count;
    call("SLAB_SZ");
    assert.equal(readWord(memory, rounded), size, `slot count ${count}`);
    assert.equal(memory[index], classIndex, `class ${count}`);
  }
});

Deno.test("closure creation clears every uncaptured environment byte", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xe300;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 3;
  memory[descriptor + 5] = 0; // No mask bytes.

  const closure = call("HEAP_LAM", descriptor);
  assert.equal(closure.tag, 2);
  const extent = readWord(memory, assembled.address("CL_SIZE"));
  assert.equal(extent, 8);
  assert.deepEqual(
    [...memory.slice(closure.payload + 2, closure.payload + extent)],
    [0, 0, 0, 0, 0, 0],
  );
});

Deno.test("activation maps stay above the heap's floor", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const guard = 0xa000;
  writeWord(memory, assembled.address("STK_FLR"), guard);
  // ENV_NEW pushes its return below the map, into the page above the heap.
  memory.fill(0xa5, 0x9b00, guard - 0x100);
  const descriptor = 0xe300;
  writeWord(memory, assembled.address("DESC_CUR"), descriptor);
  memory[descriptor + 5] = 0; // No mask bytes.
  memory[assembled.address("SLOT_CNT")] = 1;
  writeWord(memory, assembled.address("ENV_CUR"), 0);

  // POP HL in ENV_NEW advances this return stack by two bytes.  Four bytes
  // for one active slot therefore put the candidate map exactly at the floor.
  cpu.pc = assembled.address("ENV_NEW");
  cpu.sp = guard + 2;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 1_000_000, "activation setup did not return");
    assembled.runtime.step();
  }

  assert.equal(readWord(memory, assembled.address("ENV_CUR")), guard);
  assert.deepEqual(
    [...memory.slice(0x9b00, guard - 0x100)],
    new Array(0x400).fill(0xa5),
  );
});

Deno.test("large closures own and release a contiguous two-page run", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xe300;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 128;

  const closure = call("HEAP_LAM", descriptor);
  assert.equal(closure.tag, 2);
  const closureBase = closure.payload;
  assert.equal(memory[assembled.address("CL_OWNER")], 0x41);
  assert.equal(memory[assembled.address("CL_OWNER") + 1], 0xff);
  assert.equal(
    readWord(memory, assembled.address("CL_TOP")),
    closureBase + 0x200,
  );

  const root = 0xd800;
  writeWord(memory, root, closure.payload);
  memory[root + 2] = 0; // Clear extension byte.
  memory[root + 3] = 0x12;
  writeWord(memory, assembled.address("G_BASE"), root);
  writeWord(memory, assembled.address("G_END"), root + 4);
  call("GC");
  assert.equal(memory[assembled.address("CL_OWNER")], 0x41);

  writeWord(memory, assembled.address("G_BASE"), 0);
  writeWord(memory, assembled.address("G_END"), 0);
  call("GC");
  assert.equal(memory[assembled.address("CL_OWNER")], 0);
  assert.equal(memory[assembled.address("CL_OWNER") + 1], 0);
  assert.equal(call("HEAP_LAM", descriptor).payload, closureBase);
});

Deno.test("dead closures are reclaimed by class and live closures remain published", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xe300;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;
  memory[descriptor + 5] = 0; // No mask bytes.

  const dead = call("HEAP_LAM", descriptor);
  const live = call("HEAP_LAM", descriptor);
  assert.equal(dead.tag, 2);
  const closureBase = dead.payload;
  assert.equal(live.payload, closureBase + 4);

  const root = 0x7000;
  writeWord(memory, root, live.payload);
  memory[root + 2] = 0; // Clear extension byte.
  memory[root + 3] = 0x12;
  writeWord(memory, assembled.address("G_BASE"), root);
  writeWord(memory, assembled.address("G_END"), root + 4);
  call("GC");
  writeWord(memory, assembled.address("CL_OBJ"), dead.payload);
  assert.equal(call("GC_ISOBJ").tag, 0, "dead closure start was retained");
  writeWord(memory, assembled.address("CL_OBJ"), live.payload);
  assert.notEqual(call("GC_ISOBJ").tag, 0, "live closure start was lost");
  const freeHead = readWord(memory, assembled.address("CL_FREE"));
  assert.ok(freeHead >= closureBase && freeHead < closureBase + 0x100);

  const reused = call("HEAP_LAM", descriptor);
  assert.equal(reused.tag, 2);
  assert.equal(reused.payload, freeHead);

  writeWord(memory, assembled.address("G_BASE"), 0);
  writeWord(memory, assembled.address("G_END"), 0);
  call("GC");
  assert.equal(memory[assembled.address("CL_OWNER")], 0);
  const republished = call("HEAP_LAM", descriptor);
  assert.equal(republished.payload, closureBase);
});

Deno.test("closure pages share the pool with binding pages", async () => {
  const { assembled, call } = await managedRuntime();
  const binding = call("HEAP_NEW");
  assert.equal(binding.carry, 0);
  const descriptor = 0xe300;
  const memory = assembled.runtime.hardware.memory;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;
  const closure = call("HEAP_LAM", descriptor);
  assert.equal(closure.tag, 2);
  assert.notEqual(closure.payload >>> 8, binding.payload >>> 8);
  assert.notEqual(memory[assembled.address("BND_CNT")], 0);
});

Deno.test("a two-page closure claims adjacent pages in the shared pool", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xe300;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 128;
  const closure = call("HEAP_LAM", descriptor);
  assert.equal(closure.tag, 2);
  const owners = assembled.address("CL_OWNER");
  assert.equal(memory[owners], 0x41);
  assert.equal(memory[owners + 1], 0xff);
});

Deno.test("a live two-page closure does not hide a later dead page", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const wideDescriptor = 0xe300;
  const narrowDescriptor = 0xc130;
  writeWord(memory, wideDescriptor, 0x4000);
  memory[wideDescriptor + 3] = 128;
  writeWord(memory, narrowDescriptor, 0x4000);
  memory[narrowDescriptor + 3] = 1;

  const wide = call("HEAP_LAM", wideDescriptor);
  const narrow = call("HEAP_LAM", narrowDescriptor);
  const wideBase = wide.payload;
  assert.equal(narrow.payload, wideBase + 0x200);
  const root = 0xd800;
  writeWord(memory, root, wide.payload);
  memory[root + 2] = 0; // Clear extension byte.
  memory[root + 3] = 0x12;
  writeWord(memory, assembled.address("G_BASE"), root);
  writeWord(memory, assembled.address("G_END"), root + 4);
  call("GC");

  const owners = assembled.address("CL_OWNER");
  assert.equal(memory[owners], 0x41);
  assert.equal(memory[owners + 1], 0xff);
  assert.equal(memory[owners + 2], 0);
  writeWord(memory, assembled.address("CL_OBJ"), narrow.payload);
  assert.equal(call("GC_ISOBJ").tag, 0);
  const reused = call("HEAP_LAM", narrowDescriptor);
  assert.ok(
    reused.payload >= narrow.payload && reused.payload < narrow.payload + 0x100,
  );
});

Deno.test("a partial closure slab can refill every freed slot", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xe300;
  const root = 0xd800;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;

  const allocated: number[] = [];
  for (let index = 0; index < 64; index++) {
    allocated.push(call("HEAP_LAM", descriptor).payload);
  }
  writeWord(memory, root, allocated[0]);
  memory[root + 2] = 0; // Clear extension byte.
  memory[root + 3] = 0x12;
  writeWord(memory, assembled.address("G_BASE"), root);
  writeWord(memory, assembled.address("G_END"), root + 4);
  call("GC");

  const refilled = new Set<number>();
  for (let index = 0; index < 63; index++) {
    refilled.add(call("HEAP_LAM", descriptor).payload);
  }
  assert.equal(refilled.size, 63);
  for (const address of refilled) {
    assert.ok(address >= allocated[1] && address < allocated[0] + 0x100);
  }
});

Deno.test("closure churn beyond sixteen kilobytes reuses a bounded live set", async () => {
  const { assembled, memory, call } = await managedRuntime();
  const descriptor = 0xe300;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 128;
  const root = 0xd800;
  const owners = assembled.address("CL_OWNER");
  const cumulativeBytes = 8 * 32 * 260;
  assert.ok(cumulativeBytes > 16 * 1024);

  let firstBase = 0;
  for (let batch = 0; batch < 8; batch++) {
    let live = 0;
    for (let index = 0; index < 32; index++) {
      live = call("HEAP_LAM", descriptor).payload;
      if (batch === 0 && index === 0) firstBase = live;
    }
    writeWord(memory, root, live);
    memory[root + 2] = 0; // Clear extension byte.
    memory[root + 3] = 0x12;
    writeWord(memory, assembled.address("G_BASE"), root);
    writeWord(memory, assembled.address("G_END"), root + 4);
    call("GC");

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
    readWord(memory, assembled.address("CL_TOP")) >= firstBase + 0x200,
  );
});

Deno.test("a closure capture keeps a pair alive and releases both together", async () => {
  const { assembled, memory, call } = await managedRuntime(true);
  const descriptor = 0xe300;
  const map = 0xd700;
  const root = 0xd800;
  writeWord(memory, descriptor, 0x4000);
  memory[descriptor + 3] = 1;
  memory[descriptor + 5] = 1; // One mask byte each:
  memory[descriptor + 6] = 0; // owned slots,
  memory[descriptor + 7] = 1; // captured slots.

  const pair = call("PAIR_NEW");
  assert.equal(pair.tag, 1);
  const binding = call("HEAP_NEW").payload;
  const cpu = assembled.runtime.cpu;
  cpu.d = binding >>> 8;
  cpu.e = binding & 255;
  cpu.a = 1;
  call("HEAP_PUT", pair.payload);
  writeWord(memory, map, binding);
  memory[map + 2] = 0;
  memory[map + 3] = 0x20; // Promoted.
  writeWord(memory, assembled.address("ENV_CUR"), map);
  memory[assembled.address("SLOT_CNT")] = 1;
  const closure = call("HEAP_LAM", descriptor);
  writeWord(memory, assembled.address("ENV_CUR"), 0);
  memory[assembled.address("SLOT_CNT")] = 0;

  // Close the graph through the pair's CDR so collection must handle a cycle.
  writeWord(memory, pair.payload + 4, closure.payload);
  memory[pair.payload + 7] = 2;

  writeWord(memory, root, closure.payload);
  memory[root + 2] = 0; // Clear extension byte.
  memory[root + 3] = 0x12;
  writeWord(memory, assembled.address("G_BASE"), root);
  writeWord(memory, assembled.address("G_END"), root + 4);
  call("GC");
  cpu.a = 1;
  assert.equal(call("PAIR_CHK", pair.payload).carry, 0);

  writeWord(memory, assembled.address("G_BASE"), 0);
  writeWord(memory, assembled.address("G_END"), 0);
  call("GC");
  cpu.a = 1;
  assert.equal(call("PAIR_CHK", pair.payload).carry, 1);
});
