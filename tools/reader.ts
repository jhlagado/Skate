/** Streaming host reference for M4; no syntax tree or source-file buffer. */
import { ByteInterner } from "./interner.ts";
import { parseNumericToken, type Value } from "./numeric.ts";

export interface Position {
  readonly source: string;
  readonly offset: number;
  readonly line: number;
  readonly column: number;
}

/** Maps a package-wide byte offset back to its authored source part. */
export interface SourceLocator {
  locate(offset: number): {
    readonly source: string;
    readonly line: number;
    readonly column: number;
  };
}

export class ReadError extends Error {
  constructor(
    readonly code: "syntax" | "capacity" | "encoding",
    readonly at: Position,
    message: string,
  ) {
    super(`${at.source}:${at.line}:${at.column}: ${message}`);
    this.name = "ReadError";
  }
}

export interface ReaderLimits {
  numericBytes: number;
  nesting: number;
  symbols: number;
  nameBytes: number;
  strings: number;
  stringBytes: number;
}
export const DEFAULT_READER_LIMITS: Readonly<ReaderLimits> = Object.freeze({
  numericBytes: 64,
  nesting: 64,
  symbols: 1024,
  nameBytes: 8192,
  strings: 256,
  stringBytes: 8192,
});

type Body =
  | { kind: "open" | "close" | "quote" | "dot" }
  | { kind: "value"; value: Value }
  | { kind: "symbol"; id: number }
  | { kind: "string"; id: number };
export type ReadEvent = Body & { readonly at: Position };
const whitespace = (b: number) => b === 32 || b === 9 || b === 10 || b === 13;
const delimiter = (b: number | null) =>
  b === null || whitespace(b) ||
  b === 40 || b === 41 || b === 39 || b === 34 || b === 59;
const initial = /^[A-Za-z!$%&*/:<=>?^_~+\-]$/;
const identifier = /^[A-Za-z!$%&*/:<=>?^_~+\-][A-Za-z0-9!$%&*/:<=>?^_~+\-]*$/;
const hex = (b: number | null) =>
  b === null
    ? -1
    : b >= 48 && b <= 57
    ? b - 48
    : b >= 65 && b <= 70
    ? b - 55
    : b >= 97 && b <= 102
    ? b - 87
    : -1;

class Input {
  private look: number | null | undefined;
  private offset = 0;
  private line = 1;
  private column = 1;
  private cr = false;
  constructor(
    private bytes: Iterator<number>,
    private source: string | SourceLocator,
  ) {}
  position(): Position {
    if (typeof this.source !== "string") {
      return { ...this.source.locate(this.offset), offset: this.offset };
    }
    return {
      source: this.source,
      offset: this.offset,
      line: this.line,
      column: this.column,
    };
  }
  peek(): number | null {
    if (this.look === undefined) {
      const next = this.bytes.next();
      this.look = next.done ? null : next.value;
      if (
        this.look !== null &&
        (!Number.isInteger(this.look) || this.look < 0 || this.look > 127)
      ) {
        throw new ReadError(
          "encoding",
          this.position(),
          "Source must contain ASCII bytes",
        );
      }
    }
    return this.look;
  }
  take(): number | null {
    const b = this.peek();
    if (b === null) return null;
    this.look = undefined;
    this.offset++;
    if (b === 13) {
      this.line++;
      this.column = 1;
    } else if (b === 10) {
      if (!this.cr) this.line++;
      this.column = 1;
    } else this.column++;
    this.cr = b === 13;
    return b;
  }
}

/** One reader owns its tables. Consume events to EOF before accepting output. */
export class SourceReader {
  readonly symbols: ByteInterner;
  readonly strings: ByteInterner;
  readonly limits: Readonly<ReaderLimits>;
  private input: Input;
  private started = false;
  constructor(
    bytes: Iterable<number>,
    source: string | SourceLocator = "<input>",
    limits: Partial<ReaderLimits> = {},
  ) {
    this.limits = Object.freeze({ ...DEFAULT_READER_LIMITS, ...limits });
    for (const [name, value] of Object.entries(this.limits)) {
      if (!Number.isInteger(value) || value < 1 || value > 65535) {
        throw new RangeError(`Invalid ${name} capacity`);
      }
    }
    this.symbols = new ByteInterner({
      kind: "symbol",
      maxEntries: this.limits.symbols,
      maxBytes: this.limits.nameBytes,
    });
    this.strings = new ByteInterner({
      kind: "string",
      maxEntries: this.limits.strings,
      maxBytes: this.limits.stringBytes,
    });
    this.input = new Input(bytes[Symbol.iterator](), source);
  }
  private fail(
    at: Position,
    message: string,
    code: ReadError["code"] = "syntax",
  ): never {
    throw new ReadError(code, at, message);
  }
  private intern(table: ByteInterner, bytes: number[], at: Position): number {
    try {
      return table.intern(Uint8Array.from(bytes));
    } catch (error) {
      if (error instanceof RangeError) this.fail(at, error.message, "capacity");
      throw error;
    }
  }
  private *tokens(): Generator<ReadEvent> {
    const input = this.input;
    for (;;) {
      let b = input.peek();
      if (b === null) return;
      if (whitespace(b)) {
        input.take();
        continue;
      }
      if (b === 59) {
        while ((b = input.peek()) !== null && b !== 10 && b !== 13) {
          input.take();
        }
        continue;
      }
      const at = input.position();
      input.take();
      if (b === 40 || b === 41 || b === 39) {
        yield { kind: b === 40 ? "open" : b === 41 ? "close" : "quote", at };
        continue;
      }
      if (b === 34) {
        const bytes: number[] = [];
        for (;;) {
          let c = input.take();
          if (c === null) this.fail(at, "Unterminated string");
          if (c === 34) break;
          if (c === 92) {
            c = input.take();
            if (c === 120) {
              const hi = hex(input.take()), lo = hex(input.take());
              if (hi < 0 || lo < 0 || input.take() !== 59) {
                this.fail(at, "Expected string escape \\xHH;");
              }
              c = hi * 16 + lo;
            } else {
              const escapes: Record<number, number> = {
                34: 34,
                92: 92,
                110: 10,
                114: 13,
                116: 9,
              };
              if (c === null || !(c in escapes)) {
                this.fail(at, "Invalid string escape");
              }
              c = escapes[c];
            }
          } else if (c < 32 || c === 127) {
            this.fail(at, "Use an escape for string control bytes");
          }
          if (bytes.length === 255) {
            this.fail(at, "String exceeds 255 decoded bytes", "capacity");
          }
          bytes.push(c);
        }
        yield { kind: "string", id: this.intern(this.strings, bytes, at), at };
        continue;
      }
      if (b === 35) {
        const c = input.take();
        if (c === 116 || c === 102) {
          if (!delimiter(input.peek())) {
            this.fail(at, "Boolean requires a delimiter");
          }
          yield { kind: "value", value: [0, c === 116 ? 0xfe01 : 0xfe00], at };
          continue;
        }
        if (c !== 92) this.fail(at, "Unsupported # syntax");
        const first = input.take();
        if (
          first === null || whitespace(first) || first < 32 || first === 127
        ) this.fail(at, "Expected character after #\\");
        let text = String.fromCharCode(first);
        if (!delimiter(first)) {
          while (!delimiter(input.peek())) {
            if (text.length === 7) this.fail(at, "Invalid character name");
            text += String.fromCharCode(input.take()!);
          }
        }
        let value: number;
        if (text.length === 1) value = first;
        else if (text === "space") value = 32;
        else if (text === "newline") value = 10;
        else if (/^x[0-9A-Fa-f]{2}$/.test(text)) {
          value = parseInt(text.slice(1), 16);
        } else this.fail(at, "Invalid character name");
        if (!delimiter(input.peek())) {
          this.fail(at, "Character requires a delimiter");
        }
        yield { kind: "value", value: [0, 0xff00 | value], at };
        continue;
      }
      if (b < 32 || b === 127) this.fail(at, "Unexpected control byte");
      let text = String.fromCharCode(b);
      const bound = Math.max(31, this.limits.numericBytes);
      while (!delimiter(input.peek())) {
        if (text.length === bound) {
          this.fail(at, "Token exceeds configured capacity", "capacity");
        }
        text += String.fromCharCode(input.take()!);
      }
      if (text === ".") {
        yield { kind: "dot", at };
        continue;
      }
      // `...` is reserved for the P6 syntax-rules expander. It is still
      // rejected everywhere else by the compiler's ordinary identifier rules.
      if (text === "...") {
        yield {
          kind: "symbol",
          id: this.intern(this.symbols, [46, 46, 46], at),
          at,
        };
        continue;
      }
      const numericLooking = /^[+-]?(?:[0-9]|\.[0-9])/.test(text) ||
        /^[+-](?:inf|nan)\./.test(text);
      if (numericLooking && text.length > this.limits.numericBytes) {
        this.fail(at, "Numeric token exceeds configured capacity", "capacity");
      }
      let value: Value | null;
      try {
        value = parseNumericToken(text);
      } catch (error) {
        if (error instanceof RangeError || error instanceof SyntaxError) {
          this.fail(at, error.message);
        }
        throw error;
      }
      if (value !== null) {
        yield { kind: "value", value, at };
        continue;
      }
      if (!initial.test(text[0]) || !identifier.test(text)) {
        this.fail(at, "Invalid identifier or unsupported syntax");
      }
      if (text.length > 31) {
        this.fail(at, "Identifier exceeds 31 bytes", "capacity");
      }
      yield {
        kind: "symbol",
        id: this.intern(
          this.symbols,
          Array.from(text, (c) => c.charCodeAt(0)),
          at,
        ),
        at,
      };
    }
  }
  *events(): Generator<ReadEvent> {
    if (this.started) throw new Error("Reader can only be consumed once");
    this.started = true;
    type Frame = {
      kind: "list";
      at: Position;
      items: number;
      tail: "none" | "need" | "done";
    } | { kind: "quote"; at: Position };
    const frames: Frame[] = [];
    const complete = () => {
      while (frames.at(-1)?.kind === "quote") frames.pop();
      const parent = frames.at(-1);
      if (parent?.kind === "list") {
        if (parent.tail === "need") parent.tail = "done";
        else parent.items = 1;
      }
    };
    for (const event of this.tokens()) {
      const parent = frames.at(-1);
      if (event.kind === "close") {
        if (!parent || parent.kind !== "list") {
          this.fail(event.at, "Unexpected closing parenthesis");
        }
        if (parent.tail === "need") {
          this.fail(event.at, "Dot requires a following datum");
        }
        frames.pop();
        complete();
      } else if (event.kind === "dot") {
        if (
          parent?.kind !== "list" || !parent.items || parent.tail !== "none"
        ) {
          this.fail(
            event.at,
            "Dot requires preceding list data and exactly one tail",
          );
        }
        parent.tail = "need";
      } else {
        if (parent?.kind === "list" && parent.tail === "done") {
          this.fail(
            event.at,
            "Only a closing parenthesis may follow a dotted tail",
          );
        }
        if (event.kind === "open" || event.kind === "quote") {
          if (frames.length === this.limits.nesting) {
            this.fail(event.at, "Reader nesting capacity exceeded", "capacity");
          }
          frames.push(
            event.kind === "open"
              ? { kind: "list", at: event.at, items: 0, tail: "none" }
              : { kind: "quote", at: event.at },
          );
        } else complete();
      }
      yield event;
    }
    const pending = frames.at(-1);
    if (pending) {
      this.fail(
        pending.at,
        pending.kind === "quote" ? "Quote requires a datum" : "Unclosed list",
      );
    }
  }
}
