import assert from "node:assert/strict";

import { managedRuntime, writeWord } from "./scope-runtime-fixture.ts";

function installBdosReader(memory: Uint8Array, cursor: number, queue: number) {
  const routine = 0xf100;
  memory[5] = 0xc3; // JP routine.
  memory[6] = routine & 0xff;
  memory[7] = routine >>> 8;
  memory[routine] = 0x2a; // LD HL,(cursor).
  memory[routine + 1] = cursor & 0xff;
  memory[routine + 2] = cursor >>> 8;
  memory[routine + 3] = 0x7e; // LD A,(HL).
  memory[routine + 4] = 0x23; // INC HL.
  memory[routine + 5] = 0x22; // LD (cursor),HL.
  memory[routine + 6] = cursor & 0xff;
  memory[routine + 7] = cursor >>> 8;
  memory[routine + 8] = 0xc9; // RET.
  writeWord(memory, cursor, queue);
}

Deno.test("native text input folds repeated CR and split CR/LF", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const queue = 0xf200;
  const cursor = 0xf204;
  memory.set([13, 13, 10, 65], queue);
  installBdosReader(memory, cursor, queue);
  memory[assembled.address("SRTARGC")] = 0;
  memory[assembled.address("SRTINCR")] = 0;

  function readChar() {
    cpu.pc = assembled.address("SRTRDCH");
    cpu.sp = 0xdff2;
    cpu.ix = 0xef00;
    let steps = 0;
    while (cpu.pc !== 0xef00) {
      assert.ok(++steps < 50_000_000, "SRTRDCH did not return");
      assembled.runtime.step();
    }
    assert.equal(cpu.sp, 0xdff2);
    return { tag: cpu.a, payload: (cpu.h << 8) | cpu.l };
  }

  const first = readChar();
  assert.equal(first.tag, 0);
  assert.equal(first.payload, 0xff0a);

  const second = readChar();
  assert.equal(second.tag, 0);
  assert.equal(second.payload, 0xff0a);

  const afterCrLf = readChar();
  assert.equal(afterCrLf.tag, 0);
  assert.equal(afterCrLf.payload, 0xff41);
});

Deno.test("native direct CP/M output accepts byte FF", async () => {
  const { assembled, memory, cpu } = await managedRuntime();
  const capture = 0xf204;
  const routine = 0xf100;
  memory[5] = 0xc3; // JP the test BDOS routine.
  memory[6] = routine & 0xff;
  memory[7] = routine >>> 8;
  memory[routine] = 0x7b; // LD A,E: function two receives the byte in E.
  memory[routine + 1] = 0x32; // LD (capture),A.
  memory[routine + 2] = capture & 0xff;
  memory[routine + 3] = capture >>> 8;
  memory[routine + 4] = 0xc9; // RET.
  memory[capture] = 0;

  cpu.a = 0xff;
  cpu.pc = assembled.address("SRTCH");
  cpu.sp = 0xdff0;
  writeWord(memory, cpu.sp, 0xef00);
  let steps = 0;
  while (cpu.pc !== 0xef00) {
    assert.ok(++steps < 50_000_000, "SRTCH did not return");
    assembled.runtime.step();
  }
  assert.equal(cpu.sp, 0xdff2);
  assert.equal(memory[capture], 0xff);
});
