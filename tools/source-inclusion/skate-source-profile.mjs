import {
  createNodeSourceReader,
  resolveSourceProject,
  SourcePreparationError,
} from "@jhlagado/z80-tool-services/source-preparation";

const space = 32;
const open = 40;
const close = 41;
const quote = 34;
const semicolon = 59;
const backslash = 92;
const decoder = new TextDecoder("utf-8", { fatal: true });
const encoder = new TextEncoder();

function fail(code, message, snapshot, offset) {
  const before = snapshot.originalBytes.subarray(0, offset);
  let line = 1;
  let column = 1;
  for (const byte of before) {
    if (byte === 10) {
      line += 1;
      column = 1;
    } else if (byte !== 13) {
      column += 1;
    }
  }
  throw new SourcePreparationError("source", code, message, {
    source: snapshot.logicalIdentity,
    offset,
    line,
    column,
  });
}

function trivia(bytes, start) {
  let i = start;
  while (i < bytes.length) {
    if (bytes[i] === semicolon) {
      while (i < bytes.length && bytes[i] !== 10 && bytes[i] !== 13) i += 1;
    } else if (
      bytes[i] === space || bytes[i] === 9 || bytes[i] === 10 || bytes[i] === 13
    ) {
      i += 1;
    } else {
      break;
    }
  }
  return i;
}

function tokenEnd(bytes, start) {
  let i = start;
  while (
    i < bytes.length &&
    ![open, close, quote, semicolon, space, 9, 10, 13].includes(bytes[i])
  ) {
    i += 1;
  }
  return i;
}

function stringEnd(bytes, start, snapshot) {
  let i = start + 1;
  while (i < bytes.length) {
    if (bytes[i] === backslash) {
      i += 2;
    } else if (bytes[i++] === quote) {
      return i;
    }
  }
  fail(
    "unterminated-string",
    "unterminated string while preparing source",
    snapshot,
    start,
  );
}

function datumEnd(bytes, start, snapshot, depth = 0) {
  if (depth > 255) {
    fail(
      "form-depth",
      "source form exceeds preparation depth",
      snapshot,
      start,
    );
  }
  let i = trivia(bytes, start);
  if (i >= bytes.length) return i;
  if (bytes[i] === 39 || bytes[i] === 96 || bytes[i] === 44) {
    return datumEnd(bytes, i + 1, snapshot, depth + 1);
  }
  if (bytes[i] === quote) return stringEnd(bytes, i, snapshot);
  if (bytes[i] === open) {
    const beginning = i++;
    while (true) {
      i = trivia(bytes, i);
      if (i >= bytes.length) {
        fail(
          "unterminated-form",
          "unterminated form while preparing source",
          snapshot,
          beginning,
        );
      }
      if (bytes[i] === close) return i + 1;
      i = datumEnd(bytes, i, snapshot, depth + 1);
    }
  }
  if (bytes[i] === close) {
    fail("unexpected-close", "unexpected closing parenthesis", snapshot, i);
  }
  if (bytes[i] === 35 && bytes[i + 1] === backslash) {
    i += 2;
    if (i < bytes.length) i += 1;
    return tokenEnd(bytes, i);
  }
  return tokenEnd(bytes, i);
}

function includeHead(bytes, start) {
  if (bytes[start] !== open) return false;
  const name = trivia(bytes, start + 1);
  const end = tokenEnd(bytes, name);
  return end - name === 7 &&
    [105, 110, 99, 108, 117, 100, 101].every((byte, index) =>
      bytes[name + index] === byte
    );
}

function includeForm(bytes, start, snapshot) {
  let i = tokenEnd(bytes, trivia(bytes, start + 1));
  const dependencies = [];
  while (true) {
    i = trivia(bytes, i);
    if (i >= bytes.length) {
      fail("invalid-include", "unterminated include form", snapshot, start);
    }
    if (bytes[i] === close) {
      if (dependencies.length === 0) {
        fail(
          "invalid-include",
          "include needs at least one quoted filename",
          snapshot,
          start,
        );
      }
      return { end: i + 1, dependencies };
    }
    if (bytes[i] !== quote) {
      fail(
        "invalid-include",
        "include filenames must be quoted strings",
        snapshot,
        i,
      );
    }
    const end = stringEnd(bytes, i, snapshot);
    const raw = bytes.subarray(i + 1, end - 1);
    if (raw.length === 0 || raw.includes(backslash)) {
      fail(
        "invalid-include",
        "include filenames must be nonempty literal paths",
        snapshot,
        i,
      );
    }
    let specifier;
    try {
      specifier = decoder.decode(raw);
    } catch {
      fail("invalid-include", "include filename is not UTF-8", snapshot, i);
    }
    dependencies.push({
      specifier,
      location: { source: snapshot.logicalIdentity, offset: i },
    });
    i = end;
  }
}

function inspect(snapshot) {
  const originalBytes = snapshot.originalBytes;
  const logicalEnd = originalBytes.indexOf(26);
  const bytes = logicalEnd < 0
    ? originalBytes
    : originalBytes.subarray(0, logicalEnd);
  const compilerBytes = originalBytes.slice();
  const dependencies = [];
  const maskedRanges = [];
  let leading = true;
  let i = 0;
  while ((i = trivia(bytes, i)) < bytes.length) {
    if (includeHead(bytes, i)) {
      if (!leading) {
        fail(
          "late-include",
          "include must precede ordinary top-level forms",
          snapshot,
          i,
        );
      }
      const form = includeForm(bytes, i, snapshot);
      dependencies.push(...form.dependencies);
      maskedRanges.push({
        source: snapshot.logicalIdentity,
        start: i,
        end: form.end,
      });
      for (let j = i; j < form.end; j += 1) {
        if (bytes[j] !== 10 && bytes[j] !== 13) compilerBytes[j] = space;
      }
      i = form.end;
    } else {
      leading = false;
      i = datumEnd(bytes, i, snapshot);
    }
  }
  return { state: undefined, compilerBytes, dependencies, maskedRanges };
}

export function createSkateSourceProfile() {
  return { inspectEntry: inspect, inspectDependency: inspect };
}

export async function resolveSkateSource({ root, entry, reader, limits }) {
  const sourceReader = reader ?? await createNodeSourceReader(root);
  return resolveSourceProject({
    reader: sourceReader,
    entry,
    profile: createSkateSourceProfile(),
    configuration: undefined,
    limits,
  });
}

export function createSkmManifest(parts) {
  const names = new Set();
  const lines = [];
  for (const part of parts) {
    const name = part.logicalIdentity.split("/").at(-1).toUpperCase();
    if (!/^[A-Z0-9_]{1,8}\.SK8$/.test(name) || names.has(name)) {
      throw new SourcePreparationError(
        "project",
        "invalid-cpm-part",
        `CP/M part name is invalid or duplicated: ${name}`,
      );
    }
    names.add(name);
    lines.push(name);
  }
  const bytes = encoder.encode(`${lines.join("\n")}\n`);
  if (bytes.length > 2048) {
    throw new SourcePreparationError(
      "project",
      "manifest-capacity",
      "Skate manifest exceeds 2048 bytes",
    );
  }
  return bytes;
}
