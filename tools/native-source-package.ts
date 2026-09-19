/** Bounded 8.3 manifest contract for the native CP/M source loader. */
import {
  createSourcePackage,
  type SourcePackage,
  type SourcePart,
} from "./source-package.ts";

export const MAX_NATIVE_MANIFEST_BYTES = 2048;
export const MAX_NATIVE_MANIFEST_PARTS = 32;

export type NativeManifestErrorCode =
  | "capacity"
  | "empty"
  | "invalid"
  | "duplicate"
  | "missing";

export class NativeManifestError extends Error {
  constructor(
    readonly code: NativeManifestErrorCode,
    message: string,
    readonly line?: number,
  ) {
    super(message);
    this.name = "NativeManifestError";
  }
}

function allowedNameByte(byte: number): boolean {
  return (
    byte >= 0x30 && byte <= 0x39 ||
    byte >= 0x41 && byte <= 0x5a ||
    byte >= 0x61 && byte <= 0x7a ||
    [
      0x24,
      0x25,
      0x27,
      0x2d,
      0x5f,
      0x40,
      0x7e,
      0x60,
      0x7b,
      0x7d,
      0x5e,
      0x23,
      0x26,
      0x21,
      0x28,
      0x29,
    ].includes(byte)
  );
}

function normalizeName(text: string, line: number): string {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    throw new NativeManifestError("invalid", "manifest line is empty", line);
  }
  const dot = trimmed.indexOf(".");
  if (dot !== trimmed.lastIndexOf(".")) {
    throw new NativeManifestError(
      "invalid",
      "manifest names use one 8.3 extension",
      line,
    );
  }
  const base = dot < 0 ? trimmed : trimmed.slice(0, dot);
  const extension = dot < 0 ? "" : trimmed.slice(dot + 1);
  if (base.length < 1 || base.length > 8 || extension.length > 3) {
    throw new NativeManifestError(
      "invalid",
      "manifest name is not an 8.3 filename",
      line,
    );
  }
  if (
    [...base, ...extension].some((character) =>
      !allowedNameByte(character.charCodeAt(0))
    )
  ) {
    throw new NativeManifestError(
      "invalid",
      "manifest name contains a CP/M-invalid character",
      line,
    );
  }
  return extension.length === 0
    ? base.toUpperCase()
    : `${base.toUpperCase()}.${extension.toUpperCase()}`;
}

/** Parse the native flat manifest without allocating an unbounded line list. */
export function parseNativeManifest(bytes: Uint8Array): string[] {
  if (!(bytes instanceof Uint8Array)) {
    throw new TypeError("native manifest must be bytes");
  }
  if (bytes.length > MAX_NATIVE_MANIFEST_BYTES) {
    throw new NativeManifestError(
      "capacity",
      `manifest exceeds ${MAX_NATIVE_MANIFEST_BYTES} bytes`,
    );
  }
  const names: string[] = [];
  const seen = new Set<string>();
  let lineBytes: number[] = [];
  let line = 1;
  const finish = (): void => {
    if (lineBytes.length === 0) {
      line++;
      return;
    }
    const text = String.fromCharCode(...lineBytes);
    const name = normalizeName(text, line);
    if (seen.has(name)) {
      throw new NativeManifestError(
        "duplicate",
        `manifest repeats ${JSON.stringify(name)}`,
        line,
      );
    }
    seen.add(name);
    names.push(name);
    if (names.length > MAX_NATIVE_MANIFEST_PARTS) {
      throw new NativeManifestError(
        "capacity",
        `manifest exceeds ${MAX_NATIVE_MANIFEST_PARTS} parts`,
        line,
      );
    }
    lineBytes = [];
    line++;
  };
  for (let index = 0; index < bytes.length; index++) {
    const byte = bytes[index]!;
    if (byte === 0x1a) break;
    if (byte === 0x0d) {
      finish();
      if (bytes[index + 1] === 0x0a) index++;
      continue;
    }
    if (byte === 0x0a) {
      finish();
      continue;
    }
    if (byte < 0x20 || byte > 0x7e) {
      throw new NativeManifestError(
        "invalid",
        "manifest contains a non-ASCII control byte",
        line,
      );
    }
    lineBytes.push(byte);
    if (lineBytes.length > 12) {
      throw new NativeManifestError(
        "invalid",
        "manifest line exceeds an 8.3 filename",
        line,
      );
    }
  }
  if (lineBytes.length > 0) finish();
  if (names.length === 0) {
    throw new NativeManifestError("empty", "manifest contains no source parts");
  }
  return names;
}

/** Resolve a parsed manifest against CP/M-named bytes for host proof tests. */
export function createNativeSourcePackage(
  manifest: Uint8Array,
  parts: ReadonlyMap<string, Uint8Array>,
): SourcePackage {
  const names = parseNativeManifest(manifest);
  const resolved: SourcePart[] = names.map((name, index) => {
    const bytes = parts.get(name);
    if (bytes === undefined) {
      throw new NativeManifestError(
        "missing",
        `manifest part ${JSON.stringify(name)} is missing`,
        index + 1,
      );
    }
    return { name, bytes };
  });
  return createSourcePackage(resolved);
}
