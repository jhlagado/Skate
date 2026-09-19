/** Isolated ATOM experiment, using a fault-injectable BDOS boundary oracle. */
import assert from "node:assert/strict";
import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";
import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import { fileURLToPath } from "node:url";

export async function machine() {
  const result = await assembleAtomProject({
    root: fileURLToPath(new URL(".", import.meta.url)),
    entry: "patch.asm",
    assembler: undefined,
    target: undefined,
    maxInstructions: 100000000,
    maxCycles: 1000000000,
    sink: undefined,
  });
  const image = materializeAtomGeneration(result.generation)!;
  const symbols = new Map<string, number>(result.generation.symbols.map(
    (s: { name: string; value: number }) => [s.name.toLowerCase(), s.value],
  ));
  const address = (name: string) => symbols.get(name.toLowerCase())!;
  const memory = new Uint8Array(65536);
  memory.set(image.bytes, image.base);
  memory[5] = 0xc9;
  const runtime = createZ80Runtime({ memory, startAddress: address("RPATCH") });
  const cpu = runtime.cpu, mem = runtime.hardware.memory;
  let lowest = 0xd002;
  const hardware = runtime.hardware as typeof runtime.hardware & {
    memWrite: (address: number, value: number) => void;
  };
  hardware.memWrite = (p: number, value: number) => {
    assert.ok(
      (p >= address("RPWORK") && p < address("RPWEND")) ||
        (p >= 0xc800 && p < 0xd000),
      `write outside owned storage: ${p.toString(16)}`,
    );
    if (p >= 0xc800) lowest = Math.min(lowest, p);
    mem[p] = value;
  };
  function patch(
    file: Uint8Array,
    offset: number,
    bytes: Uint8Array,
    failure: { read?: number; write?: number } = {},
  ) {
    const disk = new Uint8Array(Math.ceil(file.length / 128) * 128).fill(0x1a);
    disk.set(file);
    mem.fill(0xa5, address("RPWORK"), address("RPWEND"));
    mem[address("RPLIMIT")] = file.length & 255;
    mem[address("RPLIMIT") + 1] = file.length >>> 8;
    mem.set(bytes, 0xa000);
    mem[0xd000] = 0x34;
    mem[0xd001] = 0xbe;
    cpu.pc = address("RPATCH");
    cpu.sp = 0xd000;
    cpu.ix = 0x1357;
    cpu.iy = 0x2468;
    cpu.h = offset >>> 8;
    cpu.l = offset & 255;
    cpu.d = 0xa0;
    cpu.e = 0;
    cpu.b = bytes.length;
    cpu.flags.C = 1;
    let dma = 0,
      dmaSelections = 0,
      reads = 0,
      writes = 0,
      steps = 0,
      cycles = 0;
    lowest = 0xd000;
    while (cpu.pc !== 0xbe34) {
      assert.ok(
        ++steps < 10000 && !runtime.isHalted(),
        "patch failed to return",
      );
      if (cpu.pc === 5) {
        const fn = cpu.c, fcb = cpu.d * 256 + cpu.e;
        let status = 0;
        if (fn === 26) {
          dmaSelections++;
          dma = fcb;
          assert.equal(dma, address("RPBUFFER"));
        } else {
          assert.equal(fcb, address("RPFCB"));
          const n = mem[fcb + 33] + 256 * mem[fcb + 34] + 65536 * mem[fcb + 35];
          assert.ok(n * 128 + 128 <= disk.length, "transfer outside file");
          if (fn === 33) {
            if (++reads === failure.read) status = 6;
            else {for (let i = 0; i < 128; i++) {
                hardware.memWrite(dma + i, disk[n * 128 + i]);
              }}
          } else if (fn === 34) {
            if (++writes === failure.write) status = 2;
            else disk.set(mem.subarray(dma, dma + 128), n * 128);
          } else throw new Error(`unexpected BDOS ${fn}`);
        }
        cpu.a = status;
        cpu.b =
          cpu.c =
          cpu.d =
          cpu.e =
          cpu.h =
          cpu.l =
            0xcc;
        cpu.ix = cpu.iy = 0xdddd;
        cpu.flags.C = 1;
      }
      cycles += runtime.step().cycles ?? 0;
    }
    assert.equal(cpu.sp, 0xd002);
    assert.equal(cpu.ix, 0x1357);
    assert.equal(cpu.iy, 0x2468);
    assert.deepEqual(mem.slice(0xa000, 0xa000 + bytes.length), bytes);
    assert.equal(mem[0xd000] + 256 * mem[0xd001], 0xbe34);
    assert.ok(
      mem.slice(address("RPFCB"), address("RPFCB") + 33).every((x) =>
        x === 0xa5
      ),
      "helper changed FCB file identity/extent state",
    );
    return {
      disk,
      dmaSelections,
      status: cpu.a,
      carry: cpu.flags.C,
      reads,
      writes,
      steps,
      cycles,
      stack: 0xd000 - lowest,
    };
  }
  return {
    patch,
    code: address("RPEND") - address("RPATCH"),
    work: address("RPWEND") - address("RPWORK"),
  };
}
