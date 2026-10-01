import assert from "node:assert/strict";
import {
  CALL_EC_TOKEN_BASE,
  CALL_EC_TOKEN_END,
  PORT_EOF,
  PORT_GENERATION_MAX,
  PORT_REPLY_BYTES,
  PORT_TOKEN_BASE,
  PortError,
  type PortProvider,
  type PortReadResult,
  PortTable,
} from "./effect-ports.ts";
import { EffectProtocolError } from "./effect-wire.ts";

const bytes = (text: string): Uint8Array => new TextEncoder().encode(text);

class ScriptedProvider implements PortProvider {
  readonly writes: { readonly handle: number; readonly bytes: Uint8Array }[] =
    [];
  readonly closes: number[] = [];
  readonly aborts: number[] = [];
  readonly reads = new Map<number, PortReadResult[]>();
  readonly closeFailures = new Map<number, PortError>();

  queue(handle: number, ...results: PortReadResult[]): void {
    this.reads.set(handle, [...(this.reads.get(handle) ?? []), ...results]);
  }

  read(handle: number, maximum: number): PortReadResult {
    const result = this.reads.get(handle)?.shift() ??
      { status: "eof" as const };
    if (result.status === "data" && result.bytes.length > maximum) {
      return {
        status: "error",
        code: "capacity",
        message: `reply ${result.bytes.length} exceeds ${maximum}`,
      };
    }
    return result;
  }

  write(handle: number, data: Uint8Array): void {
    this.writes.push({ handle, bytes: data.slice() });
  }

  close(handle: number): void {
    const failure = this.closeFailures.get(handle);
    if (failure !== undefined) throw failure;
    this.closes.push(handle);
  }

  abort(handle: number): void {
    this.aborts.push(handle);
  }
}

class CloseOnlyProvider implements PortProvider {
  readonly closes: number[] = [];

  read(): PortReadResult {
    return { status: "eof" };
  }

  write(): void {}

  close(handle: number): void {
    this.closes.push(handle);
  }
}

class UnrecoverableProvider implements PortProvider {
  read(): PortReadResult {
    return { status: "eof" };
  }

  write(): void {}

  close(): void {
    throw new PortError("device", "stuck handle");
  }
}

class CloseFailureProvider implements PortProvider {
  readonly closes: number[] = [];
  failHandle = -1;

  read(): PortReadResult {
    return { status: "eof" };
  }

  write(): void {}

  close(handle: number): void {
    this.closes.push(handle);
    if (handle === this.failHandle) {
      throw new PortError("device", "stuck handle");
    }
  }
}

class ProtocolErrorProvider implements PortProvider {
  read(): PortReadResult {
    throw new EffectProtocolError("capacity", "provider capacity");
  }

  write(): void {}

  close(): void {}
}

const standard = { input: 1, output: 2, error: 3 };

Deno.test("default ports have stable direction and protected lifetime", () => {
  const provider = new ScriptedProvider();
  const ports = new PortTable(provider, standard);
  const input = ports.currentInputPort();
  const output = ports.currentOutputPort();
  const error = ports.currentErrorPort();

  assert.equal(ports.isPort(input), true);
  assert.equal(ports.isInputPort(input), true);
  assert.equal(ports.isOutputPort(input), false);
  assert.equal(ports.isOutputPort(output), true);
  assert.equal(ports.isOutputPort(error), true);
  assert.throws(
    () => ports.closePort(output),
    (cause) => cause instanceof PortError && cause.code === "unsupported",
  );
  assert.deepEqual(provider.closes, []);
});

Deno.test("standard profile can use logical host text rules", () => {
  const provider = new ScriptedProvider();
  provider.queue(1, { status: "data", bytes: Uint8Array.of(0x1a) });
  const ports = new PortTable(provider, standard, {
    inputTranslateControlZ: false,
    outputNewline: "lf",
    errorNewline: "lf",
  });
  assert.equal(ports.readChar(ports.currentInputPort()), 0x1a);
  ports.newline(ports.currentOutputPort());
  ports.newline(ports.currentErrorPort());
  assert.deepEqual(
    provider.writes.map((write) => [write.handle, [...write.bytes]]),
    [[2, [0x0a]], [3, [0x0a]]],
  );
});

Deno.test("text input normalizes CR, LF and split CR/LF without losing bytes", () => {
  const provider = new ScriptedProvider();
  provider.queue(10, { status: "data", bytes: bytes("A\r\nB\nC") });
  provider.queue(11, { status: "data", bytes: Uint8Array.of(0x0d) });
  provider.queue(11, { status: "data", bytes: Uint8Array.of(0x0a) });
  provider.queue(11, { status: "data", bytes: Uint8Array.of(0x5a) });
  const ports = new PortTable(provider, standard);
  const first = ports.open({ handle: 10, direction: "input" });
  const split = ports.open({ handle: 11, direction: "input" });

  assert.equal(ports.readChar(first), 0x41);
  assert.equal(ports.readChar(first), 0x0a);
  assert.equal(ports.readChar(first), 0x42);
  assert.equal(ports.readChar(first), 0x0a);
  assert.equal(ports.readChar(first), 0x43);
  assert.equal(ports.readChar(split), 0x0a);
  assert.equal(ports.readChar(split), 0x5a);
});

Deno.test("Control-Z is text EOF while binary data preserves 1A", () => {
  const provider = new ScriptedProvider();
  provider.queue(12, {
    status: "data",
    bytes: Uint8Array.of(0x41, 0x1a, 0x42),
  });
  provider.queue(13, {
    status: "data",
    bytes: Uint8Array.of(0x41, 0x1a, 0x42),
  });
  const ports = new PortTable(provider, standard);
  const textInput = ports.open({
    handle: 12,
    direction: "input",
    translateControlZ: true,
  });
  const binaryInput = ports.open({
    handle: 13,
    direction: "input",
    mode: "binary",
  });

  assert.equal(ports.readChar(textInput), 0x41);
  assert.equal(ports.readChar(textInput), PORT_EOF);
  assert.equal(ports.readChar(textInput), PORT_EOF);
  assert.deepEqual(
    ports.readBytes(binaryInput, PORT_REPLY_BYTES),
    Uint8Array.of(0x41, 0x1a, 0x42),
  );
});

Deno.test("provider empty and pending results are not mistaken for EOF", () => {
  const provider = new ScriptedProvider();
  provider.queue(14, { status: "empty" }, { status: "pending", task: 9 }, {
    status: "data",
    bytes: Uint8Array.of(0x51),
  });
  const ports = new PortTable(provider, standard);
  const input = ports.open({ handle: 14, direction: "input" });

  assert.throws(
    () => ports.readChar(input),
    (cause) => cause instanceof PortError && cause.code === "would-block",
  );
  assert.throws(
    () => ports.readChar(input),
    (cause) => cause instanceof PortError && cause.code === "would-block",
  );
  assert.equal(ports.readChar(input), 0x51);
});

Deno.test("text output emits CR/LF and binary output writes every byte", () => {
  const provider = new ScriptedProvider();
  const ports = new PortTable(provider, standard);
  const textOutput = ports.open({ handle: 15, direction: "output" });
  const binaryOutput = ports.open({
    handle: 16,
    direction: "output",
    mode: "binary",
  });

  ports.writeText(textOutput, bytes("A\n"));
  ports.writeBytes(binaryOutput, Uint8Array.of(0x41, 0x1a, 0x42));
  assert.deepEqual(
    provider.writes.map((write) => [write.handle, [...write.bytes]]),
    [[15, [0x41]], [15, [0x0d, 0x0a]], [16, [0x41, 0x1a, 0x42]]],
  );
});

Deno.test("stale tokens fail after reuse and copied words remain safe", () => {
  const provider = new ScriptedProvider();
  const ports = new PortTable(provider, standard);
  const first = ports.open({ handle: 17, direction: "input" });
  const pair = { car: first, cdr: null };
  const vector = [first];
  const captured = () => first;
  assert.equal(first & 0xf000, PORT_TOKEN_BASE);
  assert.equal(first < CALL_EC_TOKEN_BASE || first > CALL_EC_TOKEN_END, true);
  assert.equal(ports.isPort(pair.car), true);
  assert.equal(ports.isPort(vector[0]), true);
  assert.equal(ports.isPort(captured()), true);

  ports.closePort(first);
  assert.equal(ports.isPort(first), true);
  const second = ports.open({ handle: 18, direction: "input" });
  assert.notEqual(second, first);
  assert.equal(ports.isPort(first), false);
  assert.throws(
    () => ports.readChar(first),
    (cause) => cause instanceof PortError && cause.code === "not-port",
  );
  assert.equal(ports.isPort(second), true);
});

Deno.test("port table admits five additional ports and rejects the sixth", () => {
  const provider = new ScriptedProvider();
  const ports = new PortTable(provider, standard);
  const opened = Array.from(
    { length: 5 },
    (_, index) => ports.open({ handle: 30 + index, direction: "input" }),
  );
  assert.equal(opened.length, 5);
  assert.throws(
    () => ports.open({ handle: 40, direction: "input" }),
    (cause) => cause instanceof PortError && cause.code === "capacity",
  );
  assert.deepEqual(provider.closes, [40]);
});

Deno.test("transactional open requires abort and releases an adopted handle", () => {
  const provider = new CloseOnlyProvider();
  const ports = new PortTable(provider, standard);
  assert.throws(
    () => ports.open({ handle: 41, direction: "output", transactional: true }),
    (cause) => cause instanceof PortError && cause.code === "unsupported",
  );
  // A provider without abort or release keeps ownership with its caller;
  // closing here could commit a writable file.
  assert.deepEqual(provider.closes, []);
});

Deno.test("provider protocol errors retain their capacity meaning", () => {
  const provider = new ProtocolErrorProvider();
  const ports = new PortTable(provider, standard);
  const input = ports.open({ handle: 42, direction: "input" });
  assert.throws(
    () => ports.readChar(input),
    (cause) => cause instanceof PortError && cause.code === "capacity",
  );
  assert.equal(
    (() => {
      try {
        ports.readChar(input);
      } catch (cause) {
        return (cause as PortError).protocolCode;
      }
      return undefined;
    })(),
    "capacity",
  );
});

Deno.test("multi-character replies remain owned by their source port", () => {
  const provider = new ScriptedProvider();
  provider.queue(50, { status: "data", bytes: bytes("abc") });
  provider.queue(51, { status: "data", bytes: bytes("XYZ") });
  const ports = new PortTable(provider, standard);
  const left = ports.open({ handle: 50, direction: "input" });
  const right = ports.open({ handle: 51, direction: "input" });

  assert.equal(ports.readChar(left), 0x61);
  assert.equal(ports.readChar(right), 0x58);
  assert.equal(ports.readChar(left), 0x62);
  assert.equal(ports.readChar(right), 0x59);
  assert.equal(ports.readChar(left), 0x63);
  assert.equal(ports.readChar(right), 0x5a);
});

Deno.test("fatal cleanup aborts transactional ports and closes ordinary ports", () => {
  const provider = new ScriptedProvider();
  const ports = new PortTable(provider, standard);
  ports.open({ handle: 60, direction: "input" });
  const transactional = ports.open({
    handle: 61,
    direction: "output",
    mode: "binary",
    transactional: true,
  });
  const result = ports.cleanup(true);
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.closed, [3]);
  assert.deepEqual(result.aborted, [4]);
  assert.deepEqual(provider.closes, [60]);
  assert.deepEqual(provider.aborts, [61]);
  assert.throws(
    () => ports.writeBytes(transactional, Uint8Array.of(1)),
    (cause) => cause instanceof PortError && cause.code === "closed",
  );
});

Deno.test("reset reports unresolved cleanup and invalidates its token", () => {
  const provider = new UnrecoverableProvider();
  const ports = new PortTable(provider, standard);
  const token = ports.open({ handle: 62, direction: "input" });
  assert.throws(() => ports.closePort(token));
  const result = ports.reset();
  assert.equal(result.failures.length, 1);
  assert.equal(ports.isPort(token), false);
});

Deno.test("generation exhaustion retires one slot and moves to the next", () => {
  const provider = new ScriptedProvider();
  const ports = new PortTable(provider, standard);
  const first = ports.open({ handle: 70, direction: "input" });
  ports.closePort(first);
  assert.equal(ports.isPort(first), true);
  let current = first;
  for (let generation = 1; generation < PORT_GENERATION_MAX - 1; generation++) {
    current = ports.open({ handle: 70 + generation, direction: "input" });
    ports.closePort(current);
  }
  ports.reset();
  const next = ports.open({ handle: 999, direction: "input" });
  assert.equal(ports.isPort(next), true);
  // The public constant documents the bounded range, and the old token cannot
  // regain access after the slot has changed generation.
  assert.equal(PORT_GENERATION_MAX, 0x1ff);
  assert.equal(ports.isPort(first), false);
});

Deno.test("poisoned generation exhaustion never reissues an old token", () => {
  const provider = new ScriptedProvider();
  const ports = new PortTable(provider, standard);
  const first = ports.open({ handle: 1_000, direction: "input" });
  ports.closePort(first);
  const old = ports.open({ handle: 1_001, direction: "input" });
  ports.closePort(old);
  for (let generation = 2; generation < PORT_GENERATION_MAX - 1; generation++) {
    const token = ports.open({
      handle: 1_000 + generation,
      direction: "input",
    });
    ports.closePort(token);
  }
  provider.closeFailures.set(2_000, new PortError("device", "stuck handle"));
  const exhausted = ports.open({ handle: 2_000, direction: "input" });
  assert.throws(() => ports.closePort(exhausted));
  ports.reset();
  assert.equal(ports.isPort(exhausted), false);
  for (let count = 0; count < PORT_GENERATION_MAX; count++) {
    const token = ports.open({ handle: 3_000 + count, direction: "input" });
    assert.notEqual(token, old);
    ports.closePort(token);
  }
});

Deno.test("retired poisoned handles are not retried without a contract", () => {
  const provider = new CloseFailureProvider();
  const ports = new PortTable(provider, standard);
  const first = ports.open({ handle: 4_000, direction: "input" });
  ports.closePort(first);
  for (let generation = 1; generation < PORT_GENERATION_MAX - 1; generation++) {
    const token = ports.open({
      handle: 4_000 + generation,
      direction: "input",
    });
    ports.closePort(token);
  }
  provider.failHandle = 5_000;
  const exhausted = ports.open({ handle: 5_000, direction: "input" });
  assert.throws(() => ports.closePort(exhausted));
  const reset = ports.reset();
  assert.equal(reset.failures.length, 1);
  const attempts = provider.closes.length;
  const retry = ports.cleanup(false);
  assert.equal(retry.failures.length, 1);
  assert.equal(provider.closes.length, attempts);
});
