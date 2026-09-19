import assert from "node:assert/strict";
import { executionMachine } from "./execution-machine.ts";

const STACK_TOP = 0xf000;

async function readyMachine() {
  const machine = await executionMachine();
  machine.run("TESTINIT");
  assert.equal(machine.memory[machine.address("TERROR")], 0);

  machine.run("TMAKEC");
  const index = machine.word(machine.address("TCLOIDX"));
  assert.ok(index > 0 && index < 128);
  const cell = machine.address("HEAPBASE") + index * 4;
  assert.equal(machine.word(cell), machine.address("TPDESC"));
  assert.equal(machine.memory[cell + 2], 0);
  assert.equal(machine.memory[cell + 3], 0x40);
  return machine;
}

function assertResult(machine: Awaited<ReturnType<typeof readyMachine>>) {
  const base = machine.address("ROOTBASE");
  assert.deepEqual([...machine.memory.slice(base, base + 4)], [3, 42, 0, 0]);
}

function assertOneArgumentFrame(
  machine: Awaited<ReturnType<typeof readyMachine>>,
) {
  const payload = machine.word(machine.address("TOBSENV"));
  assert.equal(machine.memory[machine.address("TOBSECT")], 1);
  assert.equal(payload >>> 13, 3);
  const environmentIndex = payload & 0x1fff;
  const environment = machine.address("HEAPBASE") + environmentIndex * 4;
  assert.equal(machine.word(environment), 0xfe02);
  const firstBinding = machine.word(environment + 2) & 0x1fff;
  assert.ok(firstBinding > 0);

  const binding = machine.address("HEAPBASE") + firstBinding * 4;
  assert.equal(machine.word(binding), 42);
  const bindingLink = machine.word(binding + 2);
  assert.equal(bindingLink >>> 13, 3);
  assert.equal(bindingLink & 0x1fff, 0);
}

function assertTwoArgumentFrame(
  machine: Awaited<ReturnType<typeof readyMachine>>,
) {
  const payload = machine.word(machine.address("TOBSENV"));
  assert.equal(machine.memory[machine.address("TOBSECT")], 1);
  assert.equal(payload >>> 13, 3);
  const environment = machine.address("HEAPBASE") + (payload & 0x1fff) * 4;
  assert.equal(machine.word(environment), 0xfe02);

  const firstIndex = machine.word(environment + 2) & 0x1fff;
  const first = machine.address("HEAPBASE") + firstIndex * 4;
  assert.equal(machine.word(first), 42);
  const firstLink = machine.word(first + 2);
  assert.equal(firstLink >>> 13, 3);
  const secondIndex = firstLink & 0x1fff;
  assert.ok(secondIndex > 0);

  const second = machine.address("HEAPBASE") + secondIndex * 4;
  assert.equal(machine.word(second), 99);
  const secondLink = machine.word(second + 2);
  assert.equal(secondLink >>> 13, 3);
  assert.equal(secondLink & 0x1fff, 0);
  assert.equal(machine.memory[machine.address("T2TAG0")], 3);
  assert.equal(machine.word(machine.address("T2VAL0")), 42);
}

function assertReturnedEntry(
  machine: Awaited<ReturnType<typeof readyMachine>>,
  continuation: string,
) {
  const rootBase = machine.address("ROOTBASE");
  const activationBase = machine.address("ACTBASE");

  assertResult(machine);
  assert.equal(machine.cpu.sp, STACK_TOP + 2);
  assert.equal(machine.cpu.ix, 0);
  assert.equal(machine.cpu.iy, rootBase + 4);
  assert.equal(machine.word(machine.address("TOBSSP")), STACK_TOP - 2);
  assert.equal(
    machine.word(machine.address("TOBSRET")),
    machine.address(continuation),
  );
  assert.equal(machine.word(machine.address("TOBSIX")), activationBase);
  assert.equal(machine.word(machine.address("TOBSIY")), rootBase + 12);
  assert.equal(machine.word(machine.address("RTROOTP")), rootBase + 4);
  assert.equal(machine.word(machine.address("RTROOTMX")), rootBase + 12);
  assert.equal(machine.word(machine.address("RTACTCUR")), activationBase);
  assert.equal(machine.word(machine.address("RTACTHI")), activationBase + 10);
  assert.equal(machine.memory[machine.address("TERROR")], 0);
  assertOneArgumentFrame(machine);
}

function writesIn(
  writes: number[],
  start: number,
  end: number,
) {
  return writes.filter((address) => address >= start && address < end);
}

Deno.test("M7 direct and computed calls share the return and root ABI", async () => {
  const machine = await readyMachine();

  machine.run("RUNDIR");
  assertReturnedEntry(machine, "DIRCONT");

  machine.run("RUNIND");
  assertReturnedEntry(machine, "INCONT");
});

Deno.test("M7 tail calls reuse one continuation and activation", async () => {
  const machine = await readyMachine();
  const result = machine.run("RUNTAIL", 500_000);
  const rootBase = machine.address("ROOTBASE");
  const activationBase = machine.address("ACTBASE");

  assertResult(machine);
  assert.equal(machine.cpu.sp, STACK_TOP + 2);
  assert.equal(machine.cpu.ix, 0);
  assert.equal(machine.cpu.iy, rootBase + 4);
  assert.equal(machine.word(machine.address("TOBSSP")), STACK_TOP - 2);
  assert.equal(
    machine.word(machine.address("TOBSRET")),
    machine.address("TAILCONT"),
  );
  assert.equal(machine.word(machine.address("TOBSIX")), activationBase);
  assert.equal(machine.word(machine.address("TOBSIY")), rootBase + 12);
  assert.equal(machine.memory[machine.address("TTLCNT")], 26);
  assert.equal(machine.memory[machine.address("TTLLEFT")], 0);
  assert.equal(machine.word(machine.address("RTROOTP")), rootBase + 4);
  assert.equal(machine.word(machine.address("RTROOTMX")), rootBase + 24);
  assert.equal(machine.word(machine.address("RTACTCUR")), activationBase);
  assert.equal(machine.word(machine.address("RTACTHI")), activationBase + 10);
  assert.ok(result.stackBytes < 32);
  assertOneArgumentFrame(machine);
});

Deno.test("M7 lexical slots preserve argument order across a two-cell chain", async () => {
  const machine = await readyMachine();
  machine.run("RUN2ARG");

  const rootBase = machine.address("ROOTBASE");
  assert.deepEqual([...machine.memory.slice(rootBase, rootBase + 4)], [
    3,
    99,
    0,
    0,
  ]);
  assert.equal(machine.cpu.sp, STACK_TOP + 2);
  assert.equal(machine.cpu.ix, 0);
  assert.equal(machine.cpu.iy, rootBase + 4);
  assertTwoArgumentFrame(machine);
});

Deno.test("M7 frame allocation collects with the closure and arguments rooted", async () => {
  const machine = await readyMachine();
  machine.run("RUNGCFRE", 1_000_000);

  assertResult(machine);
  assert.equal(machine.word(machine.address("HFCOUNT")), 124);
  assert.equal(machine.word(machine.address("RTROOTCT")), 1);
  assert.equal(machine.memory[machine.address("TERROR")], 0);
  assertOneArgumentFrame(machine);
});

Deno.test("M7 wrong arity fails before publishing an activation", async () => {
  const machine = await readyMachine();
  const result = machine.runToError("RUNARERR");
  const activationBase = machine.address("ACTBASE");

  assert.equal(result.code, 2);
  assert.equal(machine.cpu.ix, 0);
  assert.equal(machine.cpu.iy, machine.address("ROOTBASE") + 8);
  assert.equal(machine.word(machine.address("RTACTCUR")), activationBase);
  assert.equal(machine.word(machine.address("RTACTHI")), activationBase);
  assert.deepEqual(
    writesIn(result.writes, activationBase, machine.address("ACTEND")),
    [],
  );
});

Deno.test("M7 root-capacity failure leaves the reserved roots untouched", async () => {
  const machine = await readyMachine();
  const rootBase = machine.address("ROOTBASE");
  const rootsBefore = [...machine.memory.slice(rootBase, rootBase + 12)];
  const result = machine.runToError("RUNROOTC");

  assert.equal(result.code, 3);
  assert.deepEqual(
    [...machine.memory.slice(rootBase, rootBase + 12)],
    rootsBefore,
  );
  assert.deepEqual(
    writesIn(result.writes, rootBase, machine.address("ROOTEND")),
    [],
  );
  assert.equal(machine.cpu.iy, rootBase);
  assert.equal(machine.word(machine.address("RTROOTP")), rootBase);
  assert.equal(machine.word(machine.address("RTROOTMX")), rootBase);
});

Deno.test("M7 oversized frame fails before heap or activation writes", async () => {
  const machine = await readyMachine();
  machine.run("TMAKEBIG");

  const heapBase = machine.address("HEAPBASE");
  const heapBefore = [...machine.memory.slice(heapBase, heapBase + 4 * 128)];
  const activationBase = machine.address("ACTBASE");
  const activationBefore = [...machine.memory.slice(
    activationBase,
    machine.address("ACTEND"),
  )];
  const freeBefore = machine.word(machine.address("HFCOUNT"));
  const result = machine.runToError("RUNBIGFR");

  assert.equal(result.code, 3);
  assert.deepEqual(
    [...machine.memory.slice(heapBase, heapBase + 4 * 128)],
    heapBefore,
  );
  assert.deepEqual(
    [...machine.memory.slice(activationBase, machine.address("ACTEND"))],
    activationBefore,
  );
  assert.equal(machine.word(machine.address("HFCOUNT")), freeBefore);
  assert.equal(machine.word(machine.address("RTACTCUR")), activationBase);
  assert.equal(machine.word(machine.address("RTACTHI")), activationBase);
});

Deno.test("M7 string descriptor extent rejects the first wrapping count", async () => {
  const machine = await readyMachine();
  const result = machine.runToError("RSTRMAX");
  assert.equal(result.code, 4);
});
