import assert from "node:assert/strict";
import { Buffer } from "node:buffer";

import {
  type AsoEvent,
  createAsoSink,
  createAsoWriter,
  encodeAsoImage,
  materializeAso,
  readAsoOperations,
  replayAsoWindows,
} from "../tools/aso.ts";

function join(chunks: readonly Uint8Array[]): Uint8Array {
  const length = chunks.reduce((total, chunk) => total + chunk.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

function encode(events: readonly AsoEvent[], bytewise = false): Uint8Array {
  const chunks: Uint8Array[] = [];
  const begin = events[0];
  assert.equal(begin?.kind, "begin");
  const writer = createAsoWriter({
    origin: begin.origin,
    fill: begin.fill,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  for (const event of events.slice(1)) {
    if (event.kind === "commit") writer.commit(event);
    else if (event.kind === "image" && bytewise) {
      for (let index = 0; index < event.bytes.length; index += 1) {
        writer.image(
          event.address + index,
          event.bytes.subarray(index, index + 1),
        );
      }
    } else if (event.kind === "image" || event.kind === "patch") {
      writer[event.kind](event.address, event.bytes);
    }
  }
  return join(chunks);
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((value) => value.toString(16).padStart(2, "0")).join(
    "",
  );
}

Deno.test("ASO writes and reads a forward patch byte for byte", () => {
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin: 0x100,
    fill: 0,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  writer.image(0x100, Uint8Array.of(0x3e, 0, 0));
  writer.patch(0x101, Uint8Array.of(1));
  writer.image(0x105, Uint8Array.of(0xc9));
  writer.commit({ highWater: 0x106, finalCursor: 0x106 });

  const bytes = join(chunks);
  assert.equal(
    hex(bytes),
    "41534f01000100010001033e0000020101010101050101c900060100060100",
  );
  const events = readAsoOperations([bytes]);
  assert.deepEqual(materializeAso([bytes]), {
    origin: 0x100,
    fill: 0,
    highWater: 0x106,
    finalCursor: 0x106,
    bytes: Uint8Array.of(0x3e, 1, 0, 0, 0, 0xc9),
  });
  assert.deepEqual(encode(events, true), bytes);
});

Deno.test("ASO preserves fill gaps and permits a patch into an earlier gap", () => {
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin: 0x100,
    fill: 0xff,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  writer.image(0x103, Uint8Array.of(0));
  writer.patch(0x101, Uint8Array.of(0x55));
  writer.commit({ highWater: 0x104, finalCursor: 0x104 });
  const image = materializeAso(chunks);
  assert.deepEqual(image.bytes, Uint8Array.of(0xff, 0x55, 0xff, 0));
});

Deno.test("ASO handles a two-byte patch across a CP/M record boundary", () => {
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin: 0x100,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  writer.image(0x100, new Uint8Array(0x81));
  writer.patch(0x17f, Uint8Array.of(0x34, 0x12));
  writer.commit({ highWater: 0x181, finalCursor: 0x181 });
  const image = materializeAso(chunks);
  assert.equal(image.bytes[0x7f], 0x34);
  assert.equal(image.bytes[0x80], 0x12);
});

Deno.test("ASO replays a large image through bounded windows", () => {
  const source = new Uint8Array(0xff00);
  for (let index = 0; index < source.length; index += 1) {
    source[index] = (index * 37 + 11) & 0xff;
  }
  const patches = [
    { address: 0x100, bytes: Uint8Array.of(0xa1, 0xb2) },
    { address: 0x48ff, bytes: Uint8Array.of(0xc3, 0xd4) },
    { address: 0x9100, bytes: Uint8Array.of(0xe5, 0xf6) },
    { address: 0xfffe, bytes: Uint8Array.of(0x17, 0x28) },
  ];
  const aso = encodeAsoImage({
    origin: 0x100,
    bytes: source,
    fill: 0xee,
    patches,
  });
  const expected = materializeAso([aso]);
  const output = new Uint8Array(expected.bytes.length);
  const windows: number[] = [];
  const result = replayAsoWindows(
    () => [aso],
    {
      windowBytes: 0x4800,
      write(address, bytes) {
        windows.push(bytes.length);
        output.set(bytes, address - expected.origin);
      },
    },
  );
  assert.equal(result.origin, expected.origin);
  assert.equal(result.highWater, expected.highWater);
  assert.equal(result.finalCursor, expected.finalCursor);
  assert.equal(result.windows, 4);
  assert.deepEqual(windows, [0x4800, 0x4800, 0x4800, 0x2700]);
  assert.deepEqual(output, expected.bytes);
});

Deno.test("ASO window replay validates the source before writing", () => {
  const header = Uint8Array.of(0x41, 0x53, 0x4f, 1, 0, 1, 0);
  let writes = 0;
  assert.throws(
    () =>
      replayAsoWindows(
        () => [header],
        { windowBytes: 16, write: () => writes += 1 },
      ),
    /truncated|missing END/,
  );
  assert.equal(writes, 0);
  assert.throws(
    () =>
      replayAsoWindows(
        () => [header],
        { windowBytes: 0, write: () => {} },
      ),
    /window size/,
  );
});

Deno.test("ASO window replay rejects changed passes and async writers", () => {
  const first = encodeAsoImage({
    origin: 0x100,
    bytes: Uint8Array.of(1, 2, 3, 4),
  });
  const second = encodeAsoImage({
    origin: 0x200,
    bytes: Uint8Array.of(1, 2, 3, 4),
  });
  let pass = 0;
  assert.throws(
    () =>
      replayAsoWindows(
        () => [pass++ === 0 ? first : second],
        { windowBytes: 2, write: () => {} },
      ),
    /source changed/,
  );
  assert.throws(
    () =>
      replayAsoWindows(
        () => [first],
        { windowBytes: 2, write: async () => {} },
      ),
    /synchronous/,
  );
});

Deno.test("ASO image encoding does not mutate Buffer or patch views", () => {
  const source = Buffer.from([1, 2, 3, 4]);
  const patch = source.subarray(1, 3);
  const bytes = encodeAsoImage({
    origin: 0x100,
    bytes: source,
    patches: [{ address: 0x101, bytes: patch }],
  });
  assert.deepEqual([...source], [1, 2, 3, 4]);
  assert.deepEqual([...materializeAso([bytes]).bytes], [1, 2, 3, 4]);
});

Deno.test("ASO address sink keeps logical image and patch addresses", () => {
  const sink = createAsoSink({ origin: 0x100, fill: 0xff });
  sink.image(0x103, Uint8Array.of(0));
  sink.patch(0x101, Uint8Array.of(0x55));
  const bytes = sink.finish(0x104);
  assert.deepEqual(
    materializeAso([bytes]).bytes,
    Uint8Array.of(0xff, 0x55, 0xff, 0),
  );
  assert.throws(() => sink.image(0x104, Uint8Array.of(1)), /closed/);
});

Deno.test("ASO address sink closes after invalid finish geometry", () => {
  const highWaterSink = createAsoSink({ origin: 0x100 });
  highWaterSink.image(0x100, Uint8Array.of(1));
  assert.throws(() => highWaterSink.finish(0x100), /high-water/);
  assert.throws(() => highWaterSink.finish(0x101), /closed/);

  const cursorSink = createAsoSink({ origin: 0x100 });
  cursorSink.image(0x100, Uint8Array.of(1));
  assert.throws(() => cursorSink.finish(0x101, 0x102), /final cursor/);
  assert.throws(() => cursorSink.patch(0x100, Uint8Array.of(2)), /closed/);
});

Deno.test("ASO represents the exclusive address-space endpoint", () => {
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin: 0xfffe,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  writer.image(0xfffe, Uint8Array.of(0xaa, 0xbb));
  writer.commit({ highWater: 0x10000, finalCursor: 0x10000 });
  const image = materializeAso(chunks);
  assert.equal(image.highWater, 0x10000);
  assert.deepEqual(image.bytes, Uint8Array.of(0xaa, 0xbb));
});

Deno.test("ASO accepts exact CP/M padding and rejects extra bytes", () => {
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin: 0x100,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  writer.image(0x100, Uint8Array.of(1));
  writer.commit({ highWater: 0x101, finalCursor: 0x101 });
  const bytes = join(chunks);
  const padding = new Uint8Array((128 - (bytes.length % 128)) % 128).fill(0x1a);
  assert.equal(
    readAsoOperations([join([bytes, padding])]).at(-1)?.kind,
    "commit",
  );
  assert.throws(
    () => readAsoOperations([join([bytes, padding, Uint8Array.of(0x1a)])]),
    /padding/,
  );
});

Deno.test("ASO accepts one-byte chunks and a backward final cursor", () => {
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin: 0x100,
    fill: 0xaa,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  writer.image(0x100, Uint8Array.of(1, 2, 3, 4));
  writer.commit({ highWater: 0x104, finalCursor: 0x102 });
  const bytes = join(chunks);
  const oneByteChunks = Array.from(bytes, (value) => Uint8Array.of(value));
  assert.deepEqual(
    readAsoOperations(oneByteChunks),
    readAsoOperations([bytes]),
  );
  assert.deepEqual(
    materializeAso(oneByteChunks).bytes,
    Uint8Array.of(1, 2, 3, 4),
  );
});

Deno.test("ASO permits a reservation-only extent", () => {
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin: 0x100,
    fill: 0xff,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  writer.commit({ highWater: 0x104, finalCursor: 0x102 });
  const image = materializeAso(chunks);
  assert.equal(image.highWater, 0x104);
  assert.deepEqual(image.bytes, new Uint8Array(4).fill(0xff));
});

Deno.test("ASO rejects malformed streams before yielding COMMIT", () => {
  const header = Uint8Array.of(0x41, 0x53, 0x4f, 1, 0, 1, 0);
  const end = Uint8Array.of(0, 4, 1, 0, 4, 1, 0);
  const cases = [
    join([header]),
    join([header, Uint8Array.of(3), end]),
    join([header, Uint8Array.of(1, 0, 1, 0), end]),
    join([header, Uint8Array.of(2, 0, 1, 1, 1), end]),
    join([header, Uint8Array.of(1, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1), end]),
  ];
  for (const bytes of cases) {
    const seen: string[] = [];
    assert.throws(() => {
      for (const event of readAsoOperations([bytes])) seen.push(event.kind);
    }, /ASO:/);
    assert.ok(!seen.includes("commit"));
  }
});

Deno.test("ASO writer closes after invalid input or output failure", () => {
  const writer = createAsoWriter({ origin: 0x100, write: () => {} });
  assert.throws(() => writer.image(0x100, new Uint8Array()), /length/);
  assert.throws(
    () => writer.commit({ highWater: 0x101, finalCursor: 0x101 }),
    /closed/,
  );
  const patchWriter = createAsoWriter({ origin: 0x100, write: () => {} });
  assert.throws(() => patchWriter.patch(0x100, Uint8Array.of(1)), /PATCH/);

  let writes = 0;
  const broken = createAsoWriter({
    origin: 0x100,
    write: () => {
      writes += 1;
      if (writes === 2) throw new Error("disk full");
    },
  });
  broken.image(0x100, Uint8Array.of(0));
  assert.throws(
    () => broken.commit({ highWater: 0x101, finalCursor: 0x101 }),
    /disk full/,
  );
  assert.throws(
    () => broken.commit({ highWater: 0x101, finalCursor: 0x101 }),
    /closed/,
  );
});
