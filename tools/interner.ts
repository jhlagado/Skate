export interface InternerOptions {
  kind: "symbol" | "string";
  maxEntries: number;
  maxBytes: number;
}

/** Packed, bounded permanent-table builder. Returned IDs are zero-based. */
export class ByteInterner {
  readonly #kind: "symbol" | "string";
  readonly #stride: number;
  readonly #descriptors: Uint8Array;
  readonly #pool: Uint8Array;
  #count = 0;
  #usedBytes = 0;

  constructor({ kind, maxEntries, maxBytes }: InternerOptions) {
    if (kind !== "symbol" && kind !== "string") {
      throw new TypeError("Interner kind must be symbol or string");
    }
    if (!Number.isInteger(maxEntries) || maxEntries < 0 || maxEntries > 8192) {
      throw new RangeError("Interner entry capacity must be 0..8192");
    }
    if (!Number.isInteger(maxBytes) || maxBytes < 0 || maxBytes > 65536) {
      throw new RangeError("Interner pool capacity must be 0..65536 bytes");
    }
    this.#kind = kind;
    this.#stride = kind === "symbol" ? 3 : 4;
    this.#descriptors = new Uint8Array(maxEntries * this.#stride);
    this.#pool = new Uint8Array(maxBytes);
  }

  get count(): number {
    return this.#count;
  }

  get usedBytes(): number {
    return this.#usedBytes;
  }

  /** Reuses equal byte strings; a failed insertion leaves both tables intact. */
  intern(bytes: Uint8Array): number {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("Interned data must be a Uint8Array");
    }
    const length = bytes.length;
    if (this.#kind === "symbol") {
      if (length < 1 || length > 31) {
        throw new RangeError("Symbol length must be 1..31 bytes");
      }
      if (bytes.some((byte) => byte > 127)) {
        throw new RangeError("Symbol bytes must be ASCII");
      }
    } else if (length > 255) {
      throw new RangeError("String length must be 0..255 bytes");
    }

    for (let id = 0; id < this.#count; id++) {
      const descriptor = id * this.#stride;
      if (this.#descriptors[descriptor + 2] !== length) continue;
      const offset = this.#descriptors[descriptor] |
        (this.#descriptors[descriptor + 1] << 8);
      let equal = true;
      for (let i = 0; i < length; i++) {
        if (this.#pool[offset + i] !== bytes[i]) {
          equal = false;
          break;
        }
      }
      if (equal) return id;
    }

    if (this.#count * this.#stride === this.#descriptors.length) {
      throw new RangeError(`${this.#kind} table capacity exhausted`);
    }
    if (
      this.#usedBytes > 65535 || this.#usedBytes + length > this.#pool.length
    ) {
      throw new RangeError(`${this.#kind} pool capacity exhausted`);
    }
    const descriptor = this.#count * this.#stride;
    this.#descriptors[descriptor] = this.#usedBytes & 255;
    this.#descriptors[descriptor + 1] = this.#usedBytes >>> 8;
    this.#descriptors[descriptor + 2] = length;
    this.#pool.set(bytes, this.#usedBytes);
    this.#usedBytes += length;
    return this.#count++;
  }

  /** Copies only occupied bytes, with little-endian offsets and lengths. */
  snapshot(): { descriptors: Uint8Array; pool: Uint8Array } {
    return {
      descriptors: this.#descriptors.slice(0, this.#count * this.#stride),
      pool: this.#pool.slice(0, this.#usedBytes),
    };
  }
}
