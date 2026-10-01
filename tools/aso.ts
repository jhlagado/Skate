/**
 * ASO v1 operations used by the Skate compiler output path.
 *
 * ASO is an ordered stream of image bytes and final-byte patches.  It is
 * deliberately an absolute image format; symbols and relocations belong to a
 * future object format, not this stream.
 */

const ASO_LIMIT = 0x10000;
const IMAGE_LIMIT = 128;
const PATCH_LIMIT = 2;

export interface AsoGeometry {
  readonly highWater: number;
  readonly finalCursor: number;
}

export interface AsoBegin {
  readonly kind: "begin";
  readonly origin: number;
  readonly fill: number;
}

export interface AsoBytes {
  readonly kind: "image" | "patch";
  readonly address: number;
  readonly bytes: Uint8Array;
}

export interface AsoCommit extends AsoGeometry {
  readonly kind: "commit";
}

export type AsoEvent = AsoBegin | AsoBytes | AsoCommit;

export interface AsoWriter {
  image(address: number, bytes: Uint8Array): void;
  patch(address: number, bytes: Uint8Array): void;
  commit(geometry: AsoGeometry): void;
  abort(): void;
}

export interface AsoImagePatch {
  readonly address: number;
  readonly bytes: Uint8Array;
}

export interface AsoAddressSink {
  image(address: number, bytes: Uint8Array): void;
  patch(address: number, bytes: Uint8Array): void;
  finish(highWater: number, finalCursor?: number): Uint8Array;
  abort(): void;
}

function integer(
  value: number,
  minimum: number,
  maximum: number,
  name: string,
): void {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`ASO: invalid ${name}`);
  }
}

function bytesRequired(bytes: Uint8Array): void {
  if (!(bytes instanceof Uint8Array)) {
    throw new TypeError("ASO: expected bytes");
  }
}

function record(kind: number, address: number, bytes: Uint8Array): Uint8Array {
  const result = new Uint8Array(4 + bytes.length);
  result[0] = kind;
  result[1] = address & 0xff;
  result[2] = (address >>> 8) & 0xff;
  result[3] = bytes.length;
  result.set(bytes, 4);
  return result;
}

function endpoint(value: number): Uint8Array {
  return Uint8Array.of(value & 0xff, (value >>> 8) & 0xff, value >>> 16);
}

/** Create a synchronous ASO writer. The caller owns tentative-file cleanup. */
export function createAsoWriter(options: {
  readonly origin: number;
  readonly fill?: number;
  readonly write: (bytes: Uint8Array) => void;
}): AsoWriter {
  const { origin, fill = 0, write } = options;
  integer(origin, 0, 0xffff, "origin");
  integer(fill, 0, 0xff, "fill");
  if (typeof write !== "function") throw new TypeError("ASO: missing writer");

  const pending = new Uint8Array(IMAGE_LIMIT);
  let pendingLength = 0;
  let pendingStart = origin;
  let imageEnd = origin;
  let open = true;
  let busy = false;

  const emit = (bytes: Uint8Array): void => {
    const result = (write as (value: Uint8Array) => unknown)(bytes);
    if (
      result !== null &&
      typeof result === "object" &&
      typeof (result as { then?: unknown }).then === "function"
    ) {
      throw new Error("ASO: writer callback must be synchronous");
    }
  };
  const flush = (): void => {
    if (pendingLength === 0) return;
    emit(record(1, pendingStart, pending.subarray(0, pendingLength)));
    pendingLength = 0;
  };
  const operation = (action: () => void): void => {
    if (busy) throw new Error("ASO: reentrant writer call");
    if (!open) throw new Error("ASO: writer is closed");
    busy = true;
    try {
      action();
    } catch (error) {
      open = false;
      pendingLength = 0;
      throw error;
    } finally {
      busy = false;
    }
  };

  emit(Uint8Array.of(
    0x41,
    0x53,
    0x4f,
    1,
    origin & 0xff,
    (origin >>> 8) & 0xff,
    fill,
  ));

  return Object.freeze({
    image(address: number, bytes: Uint8Array): void {
      operation(() => {
        bytesRequired(bytes);
        integer(address, origin, 0xffff, "IMAGE address");
        integer(bytes.length, 1, ASO_LIMIT - address, "IMAGE length");
        if (address < imageEnd) {
          throw new RangeError("ASO: descending or overlapping IMAGE");
        }
        if (pendingLength !== 0 && address !== imageEnd) flush();
        for (const value of bytes) {
          if (pendingLength === 0) pendingStart = address;
          pending[pendingLength++] = value;
          address += 1;
          if (pendingLength === IMAGE_LIMIT) flush();
        }
        imageEnd = address;
      });
    },

    patch(address: number, bytes: Uint8Array): void {
      operation(() => {
        bytesRequired(bytes);
        integer(address, origin, 0xffff, "PATCH address");
        integer(bytes.length, 1, PATCH_LIMIT, "PATCH length");
        if (address + bytes.length > imageEnd) {
          throw new RangeError("ASO: PATCH precedes IMAGE");
        }
        flush();
        emit(record(2, address, bytes));
      });
    },

    commit(geometry: AsoGeometry): void {
      operation(() => {
        integer(geometry.highWater, imageEnd, ASO_LIMIT, "high-water mark");
        integer(
          geometry.finalCursor,
          origin,
          geometry.highWater,
          "final cursor",
        );
        flush();
        emit(Uint8Array.of(
          0,
          ...endpoint(geometry.highWater),
          ...endpoint(geometry.finalCursor),
        ));
        open = false;
      });
    },

    abort(): void {
      if (busy) throw new Error("ASO: reentrant writer call");
      open = false;
      pendingLength = 0;
    },
  });
}

/**
 * Encode a complete absolute image and its resolved two-byte fixups as ASO.
 * The image is copied with patch sites cleared; PATCH records then restore the
 * values that a linker or compiler resolved after laying out the image.
 */
export function encodeAsoImage(options: {
  readonly origin: number;
  readonly bytes: Uint8Array;
  readonly fill?: number;
  readonly patches?: readonly AsoImagePatch[];
}): Uint8Array {
  const { origin, bytes, fill = 0, patches = [] } = options;
  integer(origin, 0, 0xffff, "origin");
  bytesRequired(bytes);
  integer(bytes.length, 1, ASO_LIMIT - origin, "IMAGE length");
  const image = new Uint8Array(bytes);
  const ordered = [...patches].sort((left, right) =>
    left.address - right.address
  );
  let previousEnd = origin;
  for (const patch of ordered) {
    bytesRequired(patch.bytes);
    integer(patch.address, origin, 0xffff, "PATCH address");
    integer(patch.bytes.length, 1, PATCH_LIMIT, "PATCH length");
    const offset = patch.address - origin;
    if (patch.address < previousEnd) {
      throw new RangeError("ASO: overlapping PATCH records");
    }
    if (offset + patch.bytes.length > image.length) {
      throw new RangeError("ASO: PATCH precedes IMAGE");
    }
    for (let index = 0; index < patch.bytes.length; index += 1) {
      image[offset + index] = 0;
    }
    previousEnd = patch.address + patch.bytes.length;
  }

  const sink = createAsoSink({ origin, fill });
  sink.image(origin, image);
  for (const patch of ordered) sink.patch(patch.address, patch.bytes);
  return sink.finish(origin + image.length);
}

/** Create a logical-address ASO sink for one absolute image. */
export function createAsoSink(options: {
  readonly origin: number;
  readonly fill?: number;
}): AsoAddressSink {
  const { origin, fill = 0 } = options;
  integer(origin, 0, 0xffff, "origin");
  integer(fill, 0, 0xff, "fill");
  const chunks: Uint8Array[] = [];
  const writer = createAsoWriter({
    origin,
    fill,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  let imageEnd = origin;
  let open = true;
  const ensureOpen = (): void => {
    if (!open) throw new Error("ASO: sink is closed");
  };
  const closeOnError = <T>(action: () => T): T => {
    try {
      return action();
    } catch (error) {
      open = false;
      throw error;
    }
  };
  const output = (): Uint8Array => {
    const result = new Uint8Array(
      chunks.reduce((total, chunk) => total + chunk.length, 0),
    );
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result;
  };
  return {
    image(address, bytes) {
      ensureOpen();
      closeOnError(() => {
        writer.image(address, bytes);
        imageEnd = Math.max(imageEnd, address + bytes.length);
      });
    },
    patch(address, bytes) {
      ensureOpen();
      closeOnError(() => writer.patch(address, bytes));
    },
    finish(highWater, finalCursor = highWater) {
      ensureOpen();
      closeOnError(() => {
        integer(highWater, imageEnd, ASO_LIMIT, "high-water mark");
        integer(finalCursor, origin, highWater, "final cursor");
        writer.commit({ highWater, finalCursor });
      });
      open = false;
      return output();
    },
    abort() {
      if (open) {
        try {
          writer.abort();
        } finally {
          open = false;
          chunks.length = 0;
        }
      }
    },
  };
}

function* records(chunks: Iterable<Uint8Array>): Generator<AsoEvent> {
  const iterator = chunks[Symbol.iterator]();
  let chunk: Uint8Array<ArrayBufferLike> = new Uint8Array();
  let index = 0;
  let offset = 0;
  let exhausted = false;
  const nextByte = (required = true): number | undefined => {
    while (index === chunk.length) {
      const next = iterator.next();
      exhausted = Boolean(next.done);
      if (next.done) {
        if (required) throw new Error("ASO: truncated stream or missing END");
        return undefined;
      }
      bytesRequired(next.value);
      chunk = next.value as Uint8Array<ArrayBufferLike>;
      index = 0;
    }
    offset += 1;
    return chunk[index++];
  };
  const byte = (): number => nextByte()!;
  const word = (): number => byte() | (byte() << 8);
  const endpointValue = (): number => word() | (byte() << 16);

  try {
    if (byte() !== 0x41 || byte() !== 0x53 || byte() !== 0x4f || byte() !== 1) {
      throw new Error("ASO: invalid magic or version");
    }
    const origin = word();
    const fill = byte();
    integer(origin, 0, 0xffff, "origin");
    yield { kind: "begin", origin, fill };

    let imageEnd = origin;
    let previousKind = 0;
    let previousLength = 0;
    for (;;) {
      const kind = byte();
      if (kind === 0) {
        const highWater = endpointValue();
        const finalCursor = endpointValue();
        integer(highWater, imageEnd, ASO_LIMIT, "high-water mark");
        integer(finalCursor, origin, highWater, "final cursor");
        const padding = (128 - (offset % 128)) % 128;
        let trailing = 0;
        for (
          let value = nextByte(false);
          value !== undefined;
          value = nextByte(false)
        ) {
          trailing += 1;
          if (value !== 0x1a || trailing > padding) {
            throw new Error("ASO: invalid trailing padding");
          }
        }
        if (trailing !== 0 && trailing !== padding) {
          throw new Error("ASO: incomplete trailing padding");
        }
        yield { kind: "commit", highWater, finalCursor };
        return;
      }
      if (kind !== 1 && kind !== 2) throw new Error("ASO: unknown record kind");
      const address = word();
      const length = byte();
      integer(address, origin, 0xffff, "record address");
      integer(
        length,
        1,
        kind === 1 ? IMAGE_LIMIT : PATCH_LIMIT,
        "record length",
      );
      if (address + length > ASO_LIMIT) {
        throw new Error("ASO: record exceeds address space");
      }
      if (kind === 1) {
        if (address < imageEnd) {
          throw new Error("ASO: descending or overlapping IMAGE");
        }
        if (
          previousKind === 1 && previousLength < IMAGE_LIMIT &&
          address === imageEnd
        ) {
          throw new Error("ASO: non-canonical adjacent IMAGE");
        }
        imageEnd = address + length;
      } else if (address + length > imageEnd) {
        throw new Error("ASO: PATCH precedes IMAGE");
      }
      const bytes = new Uint8Array(length);
      for (let i = 0; i < length; i += 1) bytes[i] = byte();
      yield { kind: kind === 1 ? "image" : "patch", address, bytes };
      previousKind = kind;
      previousLength = length;
    }
  } finally {
    if (!exhausted) iterator.return?.();
  }
}

/** Decode an ASO stream, accepting at most one exact CP/M padding tail. */
export function readAsoOperations(chunks: Iterable<Uint8Array>): AsoEvent[] {
  return [...records(chunks)];
}

export interface AsoImage {
  readonly origin: number;
  readonly fill: number;
  readonly highWater: number;
  readonly finalCursor: number;
  readonly bytes: Uint8Array;
}

export interface AsoWindowReplayResult extends AsoGeometry {
  readonly origin: number;
  readonly fill: number;
  readonly windows: number;
}

export interface AsoWindowReplayOptions {
  /** Maximum number of materialized image bytes retained for one pass. */
  readonly windowBytes: number;
  /** Receive each completed window in ascending address order. */
  readonly write: (address: number, bytes: Uint8Array) => unknown;
}

type AsoSource = () => Iterable<Uint8Array>;

function openAsoSource(source: AsoSource): Iterable<Uint8Array> {
  return source();
}

function readAsoGeometry(source: AsoSource): {
  readonly origin: number;
  readonly fill: number;
  readonly highWater: number;
  readonly finalCursor: number;
} {
  let origin: number | undefined;
  let fill: number | undefined;
  let commit: AsoCommit | undefined;
  for (const event of records(openAsoSource(source))) {
    if (event.kind === "begin") {
      if (origin !== undefined) throw new Error("ASO: repeated header");
      origin = event.origin;
      fill = event.fill;
    } else if (event.kind === "commit") {
      commit = event;
    }
  }
  if (origin === undefined || fill === undefined || commit === undefined) {
    throw new Error("ASO: incomplete operation stream");
  }
  return {
    origin,
    fill,
    highWater: commit.highWater,
    finalCursor: commit.finalCursor,
  };
}

/**
 * Replay an ASO source through bounded output windows.
 *
 * `source` must be reopenable and must return the same ASO bytes for every
 * pass because each window is a separate ordered scan of the stream. The
 * callback must consume the supplied buffer before returning; it is borrowed
 * and may be reused by a later implementation.
 */
export function replayAsoWindows(
  source: AsoSource,
  options: AsoWindowReplayOptions,
): AsoWindowReplayResult {
  integer(options.windowBytes, 1, ASO_LIMIT, "window size");
  if (typeof options.write !== "function") {
    throw new TypeError("ASO: missing window writer");
  }
  const geometry = readAsoGeometry(source);
  let windows = 0;
  for (
    let start = geometry.origin;
    start < geometry.highWater;
    start += options.windowBytes
  ) {
    const end = Math.min(start + options.windowBytes, geometry.highWater);
    const buffer = new Uint8Array(end - start).fill(geometry.fill);
    let passOrigin: number | undefined;
    let passFill: number | undefined;
    let passCommit: AsoCommit | undefined;
    for (const event of records(openAsoSource(source))) {
      if (event.kind === "begin") {
        passOrigin = event.origin;
        passFill = event.fill;
        if (passOrigin !== geometry.origin || passFill !== geometry.fill) {
          throw new Error("ASO: source changed between replay passes");
        }
        continue;
      }
      if (event.kind === "commit") {
        passCommit = event;
        continue;
      }
      const eventEnd = event.address + event.bytes.length;
      const overlapStart = Math.max(start, event.address);
      const overlapEnd = Math.min(end, eventEnd);
      if (overlapStart >= overlapEnd) continue;
      const sourceOffset = overlapStart - event.address;
      const targetOffset = overlapStart - start;
      buffer.set(
        event.bytes.subarray(
          sourceOffset,
          sourceOffset + overlapEnd - overlapStart,
        ),
        targetOffset,
      );
    }
    if (
      passOrigin !== geometry.origin || passFill !== geometry.fill ||
      passCommit?.highWater !== geometry.highWater ||
      passCommit?.finalCursor !== geometry.finalCursor
    ) {
      throw new Error("ASO: source changed between replay passes");
    }
    const result = options.write(start, buffer);
    if (
      result !== null && typeof result === "object" &&
      typeof (result as { then?: unknown }).then === "function"
    ) {
      throw new Error("ASO: window writer must be synchronous");
    }
    windows += 1;
  }
  return { ...geometry, windows };
}

/** Materialize an ASO stream in host memory for tests and reference tooling. */
export function materializeAso(chunks: Iterable<Uint8Array>): AsoImage {
  const events = readAsoOperations(chunks);
  const begin = events[0];
  const commit = events.at(-1);
  if (begin?.kind !== "begin" || commit?.kind !== "commit") {
    throw new Error("ASO: incomplete operation stream");
  }
  const bytes = new Uint8Array(commit.highWater - begin.origin).fill(
    begin.fill,
  );
  for (const event of events) {
    if (event.kind === "image" || event.kind === "patch") {
      bytes.set(event.bytes, event.address - begin.origin);
    }
  }
  return {
    origin: begin.origin,
    fill: begin.fill,
    highWater: commit.highWater,
    finalCursor: commit.finalCursor,
    bytes,
  };
}
