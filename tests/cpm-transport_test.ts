import assert from "node:assert/strict";
import { loadAssembly } from "./z80.ts";

type Mode = "read" | "write";

async function transportMachine() {
  const { runtime, address } = await loadAssembly("tests/cpm-transport.asm");
  const cpu = runtime.cpu;
  const mem = runtime.hardware.memory;
  const workStart = address("CTREERR");
  const workEnd = address("CTWBUF") + 128;
  let inputRecords: Uint8Array[] = [];
  let readFailure = 1;
  let writeFailure = 0;
  let openFailure = 0;
  let deleteFailure = 0;
  let renameFailure = 0;
  let makeFailure = 0;
  let closeFailure = 0;
  let dma = 0;
  let reads = 0;
  let writes = 0;
  const written: Uint8Array[] = [];
  const calls: { fn: number; fcb: number }[] = [];
  const renames: { source: Uint8Array; destination: Uint8Array }[] = [];

  (runtime.hardware as typeof runtime.hardware & {
    memWrite: (address: number, value: number) => void;
  }).memWrite = (p, value) => {
    const work = p >= workStart && p < workEnd;
    const stack = p >= 0xef00 && p < 0xf000;
    assert.ok(work || stack, `unexpected transport write at ${p.toString(16)}`);
    mem[p] = value;
  };
  mem[5] = 0xc9; // Return from the injected BDOS call.

  function bdos(): void {
    const fn = cpu.c;
    const fcb = cpu.d * 256 + cpu.e;
    calls.push({ fn, fcb });
    if (fn === 15) {
      cpu.a = openFailure;
    } else if (fn === 19) {
      cpu.a = deleteFailure;
    } else if (fn === 23) {
      renames.push({
        source: mem.slice(fcb, fcb + 12),
        destination: mem.slice(fcb + 16, fcb + 28),
      });
      cpu.a = renameFailure;
    } else if (fn === 22) {
      cpu.a = makeFailure;
    } else if (fn === 16) {
      cpu.a = closeFailure;
    } else if (fn === 26) {
      dma = fcb;
      cpu.a = 0;
    } else if (fn === 20) {
      const record = inputRecords[reads++];
      if (record) mem.set(record, dma);
      cpu.a = record ? 0 : readFailure;
    } else if (fn === 21) {
      writes++;
      written.push(mem.slice(dma, dma + 128));
      cpu.a = writeFailure;
    } else {
      throw new Error(`unexpected BDOS function ${fn}`);
    }
    // Deliberately destroy scratch registers; CTBDOS must restore only IX/IY.
    cpu.ix = 0;
    cpu.iy = 0;
    cpu.b =
      cpu.c =
      cpu.d =
      cpu.e =
      cpu.h =
      cpu.l =
        0xaa;
  }

  function call(
    name: string,
    value = 0,
    hlArgument?: number,
    deArgument?: number,
  ): { carry: number; value: number } {
    cpu.pc = address(name);
    cpu.sp = 0xf000;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.a = value;
    if (name === "CTOPENR") {
      hlArgument ??= 0x8000;
    }
    if (name === "CTOPENW") {
      hlArgument ??= 0x8100;
    }
    if (hlArgument !== undefined) {
      cpu.h = hlArgument >>> 8;
      cpu.l = hlArgument & 255;
    }
    if (deArgument !== undefined) {
      cpu.d = deArgument >>> 8;
      cpu.e = deArgument & 255;
    }
    mem[0xf000] = 0;
    mem[0xf001] = 0xff;
    let steps = 0;
    while (cpu.pc !== 0xff00) {
      assert.ok(++steps < 100_000, `${name} did not return`);
      if (cpu.pc === 5) bdos();
      runtime.step();
    }
    assert.equal(cpu.sp, 0xf002, `${name} balances SP`);
    assert.equal(cpu.ix, 0x1357, `${name} preserves IX`);
    assert.equal(cpu.iy, 0x2468, `${name} preserves IY`);
    return { carry: cpu.flags.C, value: cpu.a };
  }

  function prefix(addressValue: number, name: string, ext: string): void {
    const bytes = new TextEncoder().encode(
      `\0${name.padEnd(8, " ").slice(0, 8)}${ext.padEnd(3, " ").slice(0, 3)}`,
    );
    assert.equal(bytes.length, 12);
    mem.set(bytes, addressValue);
  }

  function reset(): void {
    inputRecords = [];
    readFailure = 1;
    writeFailure = 0;
    openFailure = 0;
    deleteFailure = 0;
    renameFailure = 0;
    makeFailure = 0;
    closeFailure = 0;
    dma = 0;
    reads = 0;
    writes = 0;
    written.length = 0;
    calls.length = 0;
    renames.length = 0;
    mem.fill(0, 0x8000, 0x8100);
    mem.fill(0, workStart, workEnd);
  }

  prefix(0x8000, "INPUT", "BIN");
  prefix(0x8100, "OUTPUT", "BIN");
  return {
    address,
    call,
    reset,
    mem,
    cpu,
    written,
    calls,
    renames,
    setInput(records: Uint8Array[]) {
      inputRecords = records;
    },
    setReadFailure(value: number) {
      readFailure = value;
    },
    setWriteFailure(value: number) {
      writeFailure = value;
    },
    setOpenFailure(value: number) {
      openFailure = value;
    },
    setDeleteFailure(value: number) {
      deleteFailure = value;
    },
    setRenameFailure(value: number) {
      renameFailure = value;
    },
    setMakeFailure(value: number) {
      makeFailure = value;
    },
    setCloseFailure(value: number) {
      closeFailure = value;
    },
    getReads: () => reads,
    getWrites: () => writes,
    getDma: () => dma,
  };
}

Deno.test("CP/M transport reads raw records and preserves the FCB contract", async () => {
  const m = await transportMachine();
  const records = Array.from(
    { length: 3 },
    (_, record) =>
      Uint8Array.from({ length: 128 }, (_, i) => (record * 128 + i) & 255),
  );
  m.setInput(records);
  assert.deepEqual(m.call("CTOPENR", 0), { carry: 0, value: 0 });
  assert.deepEqual(
    [...m.mem.slice(m.address("CTINFCB") + 12, m.address("CTINFCB") + 36)],
    new Array(24).fill(0),
  );
  assert.deepEqual(m.call("CTREAD"), { carry: 0, value: records[0]![0] });
  assert.equal(m.getDma(), m.address("CTRBUF"));
  for (const value of records[0]!.slice(1)) {
    assert.deepEqual(m.call("CTREAD"), { carry: 0, value });
  }
  for (const record of records.slice(1)) {
    for (const value of record) {
      assert.deepEqual(m.call("CTREAD"), { carry: 0, value });
    }
  }
  assert.deepEqual(m.call("CTREAD"), { carry: 1, value: 0 });
  assert.deepEqual(m.call("CTREAD"), { carry: 1, value: 0 });
  assert.equal(m.getReads(), 4);
  assert.deepEqual(m.call("CTCLOSER"), { carry: 0, value: 0 });
  assert.deepEqual(m.call("CTCLOSER"), { carry: 0, value: 0 });
  assert.equal(m.calls.filter(({ fn }) => fn === 26).length, 4);
});

Deno.test("CP/M transport writes complete and short records without an extra record", async () => {
  const m = await transportMachine();
  const bytes = Uint8Array.from({ length: 257 }, (_, i) => i & 255);
  assert.deepEqual(m.call("CTOPENW", 0), { carry: 0, value: 0 });
  for (const value of bytes) {
    assert.deepEqual(m.call("CTWRITE", value), { carry: 0, value: 0 });
  }
  assert.deepEqual(m.call("CTCLOSEW"), { carry: 0, value: 0 });
  assert.equal(m.getWrites(), 3);
  assert.equal(m.written.length, 3);
  assert.deepEqual([...m.written[0]!], [...bytes.slice(0, 128)]);
  assert.deepEqual([...m.written[1]!], [...bytes.slice(128, 256)]);
  assert.deepEqual(
    [...m.written[2]!.slice(0, 1)],
    [bytes[256]],
  );
  assert.ok(m.written[2]!.slice(1).every((value) => value === 26));
  assert.equal(m.calls.filter(({ fn }) => fn === 21).length, 3);

  m.reset();
  assert.deepEqual(m.call("CTOPENW"), { carry: 0, value: 0 });
  for (const value of Uint8Array.from({ length: 128 }, (_, i) => i)) {
    assert.deepEqual(m.call("CTWRITE", value), { carry: 0, value: 0 });
  }
  assert.deepEqual(m.call("CTCLOSEW"), { carry: 0, value: 0 });
  assert.equal(m.getWrites(), 1, "an exact record count is not padded");
});

Deno.test("CP/M transport reports sticky open, read, write and close failures", async () => {
  const m = await transportMachine();
  m.setOpenFailure(255);
  assert.deepEqual(m.call("CTOPENR"), { carry: 1, value: 1 });
  assert.deepEqual(m.call("CTREAD"), { carry: 1, value: 1 });
  assert.deepEqual(m.call("CTCLOSER"), { carry: 1, value: 1 });

  m.reset();
  m.setInput([]);
  m.setReadFailure(2);
  assert.deepEqual(m.call("CTOPENR"), { carry: 0, value: 0 });
  assert.deepEqual(m.call("CTREAD"), { carry: 1, value: 2 });
  m.setCloseFailure(255);
  assert.deepEqual(m.call("CTREAD"), { carry: 1, value: 2 });
  assert.deepEqual(m.call("CTCLOSER"), { carry: 1, value: 2 });

  m.reset();
  m.setMakeFailure(255);
  assert.deepEqual(m.call("CTOPENW"), { carry: 1, value: 1 });
  assert.deepEqual(m.call("CTWRITE", 7), { carry: 1, value: 1 });
  assert.deepEqual(m.call("CTCLOSEW"), { carry: 1, value: 1 });

  m.reset();
  assert.deepEqual(m.call("CTOPENW"), { carry: 0, value: 0 });
  m.setWriteFailure(2); // CP/M disk-full/write error.
  for (const value of new Uint8Array(128)) m.call("CTWRITE", value);
  m.setCloseFailure(255);
  assert.deepEqual(m.call("CTCLOSEW"), { carry: 1, value: 2 });
  assert.deepEqual(m.call("CTCLOSEW"), { carry: 1, value: 2 });

  m.reset();
  assert.deepEqual(m.call("CTOPENW"), { carry: 0, value: 0 });
  m.setCloseFailure(255);
  assert.deepEqual(m.call("CTCLOSEW"), { carry: 1, value: 3 });
  assert.deepEqual(m.call("CTCLOSEW"), { carry: 1, value: 3 });
  assert.deepEqual(m.call("CTWRITE", 1), { carry: 1, value: 3 });
});

Deno.test("CP/M transport keeps the BDOS vector and private DMA ownership explicit", async () => {
  const m = await transportMachine();
  m.setInput([new Uint8Array(128).fill(0x5a)]);
  assert.deepEqual(m.call("CTOPENR"), { carry: 0, value: 0 });
  assert.deepEqual(m.call("CTREAD"), { carry: 0, value: 0x5a });
  const dmaCalls = m.calls.filter(({ fn }) => fn === 26);
  assert.equal(dmaCalls.length, 1);
  assert.equal(dmaCalls[0]!.fcb, m.address("CTRBUF"));
  assert.ok(m.calls.every(({ fn }) => [15, 20, 26].includes(fn)));
});

Deno.test("CP/M transport deletes and renames through the BDOS vector", async () => {
  const m = await transportMachine();
  const input = [...m.mem.slice(0x8000, 0x800c)];
  const output = [...m.mem.slice(0x8100, 0x810c)];
  const fcb = m.address("CTINFCB");

  assert.deepEqual(m.call("CTDELETE", 0, 0x8000), { carry: 0, value: 0 });
  assert.deepEqual(m.calls.at(-1), { fn: 19, fcb });
  assert.deepEqual([...m.mem.slice(fcb, fcb + 12)], input);
  assert.ok([...m.mem.slice(fcb + 12, fcb + 36)].every((value) => value === 0));

  m.setDeleteFailure(255); // Missing files are already clean for rollback.
  assert.deepEqual(m.call("CTDELETE", 0, 0x8000), { carry: 0, value: 0 });
  m.setDeleteFailure(2);
  assert.deepEqual(m.call("CTDELETE", 0, 0x8000), { carry: 1, value: 2 });

  m.reset();
  m.mem.set(input, 0x8000);
  m.mem.set(output, 0x8100);
  assert.deepEqual(m.call("CTRENAME", 0, 0x8000, 0x8100), {
    carry: 0,
    value: 0,
  });
  assert.deepEqual(m.renames, [{
    source: Uint8Array.from(input),
    destination: Uint8Array.from(output),
  }]);
  assert.ok([...m.mem.slice(fcb + 12, fcb + 16)].every((value) => value === 0));
  assert.ok([...m.mem.slice(fcb + 28, fcb + 36)].every((value) => value === 0));

  m.setRenameFailure(2);
  assert.deepEqual(m.call("CTRENAME", 0, 0x8000, 0x8100), {
    carry: 1,
    value: 2,
  });
});
