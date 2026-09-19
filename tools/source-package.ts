/** Ordered source parts for the host-side Skate packaging layer. */
import { dirname, normalize, resolve } from "node:path";
import { ReadError, type SourceLocator, SourceReader } from "./reader.ts";

export const MAX_SOURCE_PACKAGE_BYTES = 0xffff;

export interface SourcePart {
  readonly name: string;
  readonly bytes: Uint8Array;
}

export interface SourcePackage extends SourceLocator {
  readonly parts: readonly SourcePart[];
  readonly bytes: Uint8Array;
}

export type SourcePackageErrorCode =
  | "empty"
  | "duplicate"
  | "invalid"
  | "missing"
  | "capacity";

export class SourcePackageError extends Error {
  constructor(
    readonly code: SourcePackageErrorCode,
    message: string,
    readonly partIndex?: number,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "SourcePackageError";
  }
}

interface SourceSegment {
  readonly start: number;
  readonly end: number;
  readonly name: string;
  readonly lineStarts: readonly number[];
}

function lineStarts(bytes: Uint8Array): number[] {
  const starts = [0];
  for (let index = 0; index < bytes.length; index++) {
    const byte = bytes[index]!;
    if (byte === 13) {
      if (bytes[index + 1] === 10) index++;
      starts.push(index + 1);
    } else if (byte === 10) {
      starts.push(index + 1);
    }
  }
  return starts;
}

function segmentAt(
  segments: readonly SourceSegment[],
  offset: number,
): SourceSegment {
  for (const segment of segments) {
    if (offset < segment.end || segment === segments[segments.length - 1]) {
      return segment;
    }
  }
  throw new RangeError("Source-package offset is outside the package");
}

function localPosition(
  segment: SourceSegment,
  offset: number,
): { readonly line: number; readonly column: number } {
  const local = Math.max(
    0,
    Math.min(offset - segment.start, segment.end - segment.start),
  );
  let low = 0;
  let high = segment.lineStarts.length - 1;
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    if (segment.lineStarts[middle]! <= local) low = middle;
    else high = middle - 1;
  }
  return {
    line: low + 1,
    column: local - segment.lineStarts[low]! + 1,
  };
}

class PackageOrigin implements SourceLocator {
  constructor(private readonly segments: readonly SourceSegment[]) {}

  locate(offset: number): {
    readonly source: string;
    readonly line: number;
    readonly column: number;
  } {
    const segment = segmentAt(this.segments, offset);
    return { source: segment.name, ...localPosition(segment, offset) };
  }
}

function validatePart(part: SourcePart, index: number): void {
  if (part.bytes.length === 0) return;
  try {
    const reader = new SourceReader(part.bytes, part.name);
    for (const _event of reader.events()) {
      // Consuming the complete part validates its syntax and boundary.
    }
  } catch (error) {
    if (error instanceof ReadError) throw error;
    throw new SourcePackageError(
      "invalid",
      `Source part ${JSON.stringify(part.name)} could not be read: ${
        error instanceof Error ? error.message : String(error)
      }`,
      index,
      { cause: error },
    );
  }
}

/** Build one logical source stream while retaining authored part locations. */
export function createSourcePackage(
  parts: readonly SourcePart[],
): SourcePackage {
  if (parts.length === 0) {
    throw new SourcePackageError(
      "empty",
      "A source package needs a source part",
    );
  }

  const names = new Set<string>();
  const checked = parts.map((part, index) => {
    if (!(part instanceof Object) || typeof part.name !== "string") {
      throw new SourcePackageError(
        "invalid",
        `Source part ${index} needs a name`,
        index,
      );
    }
    const name = part.name.trim();
    if (name.length === 0) {
      throw new SourcePackageError(
        "invalid",
        `Source part ${index} needs a nonempty name`,
        index,
      );
    }
    if (names.has(name)) {
      throw new SourcePackageError(
        "duplicate",
        `Source package contains duplicate part ${JSON.stringify(name)}`,
        index,
      );
    }
    names.add(name);
    if (!(part.bytes instanceof Uint8Array)) {
      throw new SourcePackageError(
        "invalid",
        `Source part ${JSON.stringify(name)} needs Uint8Array bytes`,
        index,
      );
    }
    const checkedPart = { name, bytes: part.bytes.slice() };
    validatePart(checkedPart, index);
    return checkedPart;
  });

  const segments: SourceSegment[] = [];
  let total = 0;
  for (const [index, part] of checked.entries()) {
    const start = total;
    total += part.bytes.length;
    const end = total;
    segments.push({
      start,
      end,
      name: part.name,
      lineStarts: lineStarts(part.bytes),
    });
    if (index + 1 < checked.length) {
      const final = part.bytes[part.bytes.length - 1];
      if (final !== 10 && final !== 13) total++;
    }
  }
  if (total > MAX_SOURCE_PACKAGE_BYTES) {
    throw new SourcePackageError(
      "capacity",
      `Source package exceeds ${MAX_SOURCE_PACKAGE_BYTES} bytes`,
    );
  }

  const bytes = new Uint8Array(total);
  let cursor = 0;
  for (const [index, part] of checked.entries()) {
    bytes.set(part.bytes, cursor);
    cursor += part.bytes.length;
    if (index + 1 < checked.length) {
      const final = part.bytes[part.bytes.length - 1];
      if (final !== 10 && final !== 13) bytes[cursor++] = 10;
    }
  }
  const origin = new PackageOrigin(segments);
  return Object.freeze({
    parts: checked,
    bytes,
    locate: origin.locate.bind(origin),
  });
}

/** Parse the flat, one-source-name-per-line manifest convention. */
export function parseSourceManifest(text: string): string[] {
  if (typeof text !== "string") throw new TypeError("Manifest must be text");
  return text.split(/\r?\n/).map((line) => line.trim()).filter((line) =>
    line.length > 0
  );
}

/** Load a flat manifest and its source parts without searching or reordering. */
export async function readSourcePackage(
  manifestPath: string,
): Promise<SourcePackage> {
  const manifest = await Deno.readTextFile(manifestPath);
  const entries = parseSourceManifest(manifest);
  if (entries.length === 0) {
    throw new SourcePackageError(
      "empty",
      `Source manifest ${JSON.stringify(manifestPath)} contains no parts`,
    );
  }
  const base = dirname(resolve(manifestPath));
  const seen = new Map<string, number>();
  const parts: SourcePart[] = [];
  for (const [index, name] of entries.entries()) {
    const path = normalize(resolve(base, name));
    const previous = seen.get(path);
    if (previous !== undefined) {
      throw new SourcePackageError(
        "duplicate",
        `Manifest entry ${index + 1} duplicates entry ${previous + 1}: ${
          JSON.stringify(name)
        }`,
        index,
      );
    }
    seen.set(path, index);
    let bytes: Uint8Array;
    try {
      bytes = await Deno.readFile(path);
    } catch (error) {
      throw new SourcePackageError(
        "missing",
        `Cannot read source part ${JSON.stringify(name)} from ${
          JSON.stringify(manifestPath)
        }`,
        index,
        { cause: error },
      );
    }
    parts.push({ name, bytes });
  }
  return createSourcePackage(parts);
}
