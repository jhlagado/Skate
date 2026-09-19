/** Host-only C0 model. The arena is exact; native code and control-state costs are unmeasured. */
export const NAME_COUNT = 288;
export const DIRECTORY_STRIDE = 6;
export const SPELLING_BYTES = 4608;
export const MAX_NAME_BYTES = 31;
export const DIRECTORY_BYTES = NAME_COUNT * DIRECTORY_STRIDE;
export const ARENA_BYTES = DIRECTORY_BYTES + SPELLING_BYTES;

export interface NamePoolMetrics {
  readonly liveNames: number;
  readonly liveSpellingBytes: number;
  readonly allocatedSpellingBytes: number;
  readonly peakLiveNames: number;
  readonly peakLiveSpellingBytes: number;
  readonly peakAllocatedSpellingBytes: number;
  readonly compactions: number;
}

/**
 * Directory entry: offset:u16, length:u8, flags:u8, meta:u16.
 * Zero length means free. Offsets are relative to the spelling region.
 *
 * No name strings or lookup tables survive an operation outside this arena.
 * The scalar counters model separately accounted compiler control state, not
 * additional directory/spelling storage. ASCII identifier grammar belongs to
 * the caller; this pool checks encoding and byte length only.
 */
export class NamePool {
  readonly #arena: Uint8Array;
  #liveNames = 0;
  #liveBytes = 0;
  #allocatedBytes = 0;
  #peakNames = 0;
  #peakLiveBytes = 0;
  #peakAllocatedBytes = 0;
  #compactions = 0;

  /** Owns and clears exactly this view; callers must not mutate its contents. */
  constructor(arena = new Uint8Array(ARENA_BYTES)) {
    if (arena.length !== ARENA_BYTES) {
      throw new RangeError(`arena must contain exactly ${ARENA_BYTES} bytes`);
    }
    this.#arena = arena;
    arena.fill(0);
  }

  intern(name: string): number {
    if (name.length === 0 || name.length > MAX_NAME_BYTES) {
      throw new RangeError("identifier length must be 1..31 ASCII bytes");
    }
    for (let i = 0; i < name.length; i++) {
      if (name.charCodeAt(i) > 127) {
        throw new TypeError("identifier is not ASCII");
      }
    }

    let free = -1;
    for (let id = 0; id < NAME_COUNT; id++) {
      const entry = id * DIRECTORY_STRIDE;
      const length = this.#arena[entry + 2];
      if (length === 0) {
        if (free < 0) free = id;
      } else if (length === name.length) {
        const start = DIRECTORY_BYTES + this.#word(entry);
        let equal = true;
        for (let i = 0; i < length; i++) {
          if (this.#arena[start + i] !== name.charCodeAt(i)) {
            equal = false;
            break;
          }
        }
        if (equal) return id;
      }
    }

    // Refusal must precede compaction or any arena/control-state mutation.
    if (free < 0) throw new RangeError("name directory capacity");
    if (this.#liveBytes + name.length > SPELLING_BYTES) {
      throw new RangeError("name spelling capacity");
    }
    if (this.#allocatedBytes + name.length > SPELLING_BYTES) this.#compact();

    const entry = free * DIRECTORY_STRIDE;
    const offset = this.#allocatedBytes;
    for (let i = 0; i < name.length; i++) {
      this.#arena[DIRECTORY_BYTES + offset + i] = name.charCodeAt(i);
    }
    this.#putWord(entry, offset);
    this.#arena[entry + 2] = name.length;
    this.#arena[entry + 3] = 0;
    this.#putWord(entry + 4, 0);
    this.#liveNames++;
    this.#liveBytes += name.length;
    this.#allocatedBytes += name.length;
    this.#peakNames = Math.max(this.#peakNames, this.#liveNames);
    this.#peakLiveBytes = Math.max(this.#peakLiveBytes, this.#liveBytes);
    this.#peakAllocatedBytes = Math.max(
      this.#peakAllocatedBytes,
      this.#allocatedBytes,
    );
    return free;
  }

  /** The resolver must first remove every reference to this ID. No refcount is inferred. */
  release(id: number): void {
    const entry = this.#entry(id);
    this.#liveBytes -= this.#arena[entry + 2];
    this.#liveNames--;
    this.#arena.fill(0, entry, entry + DIRECTORY_STRIDE);
    // Leave holes until append space runs out; release itself never compacts.
  }

  spelling(id: number): string {
    const entry = this.#entry(id);
    const start = DIRECTORY_BYTES + this.#word(entry);
    let name = "";
    for (let i = 0; i < this.#arena[entry + 2]; i++) {
      name += String.fromCharCode(this.#arena[start + i]);
    }
    return name;
  }

  getFlags(id: number): number {
    return this.#arena[this.#entry(id) + 3];
  }

  setFlags(id: number, value: number): void {
    const entry = this.#entry(id);
    this.#unsigned(value, 255);
    this.#arena[entry + 3] = value;
  }

  getMeta(id: number): number {
    return this.#word(this.#entry(id) + 4);
  }

  setMeta(id: number, value: number): void {
    const entry = this.#entry(id);
    this.#unsigned(value, 65535);
    this.#putWord(entry + 4, value);
  }

  snapshot(): NamePoolMetrics {
    return {
      liveNames: this.#liveNames,
      liveSpellingBytes: this.#liveBytes,
      allocatedSpellingBytes: this.#allocatedBytes,
      peakLiveNames: this.#peakNames,
      peakLiveSpellingBytes: this.#peakLiveBytes,
      peakAllocatedSpellingBytes: this.#peakAllocatedBytes,
      compactions: this.#compactions,
    };
  }

  #entry(id: number): number {
    this.#unsigned(id, NAME_COUNT - 1);
    const entry = id * DIRECTORY_STRIDE;
    if (this.#arena[entry + 2] === 0) throw new RangeError("inactive name id");
    return entry;
  }

  #unsigned(value: number, maximum: number): void {
    if (!Number.isInteger(value) || value < 0 || value > maximum) {
      throw new RangeError(`expected integer in 0..${maximum}`);
    }
  }

  #word(at: number): number {
    return this.#arena[at] | (this.#arena[at + 1] << 8);
  }

  #putWord(at: number, value: number): void {
    this.#arena[at] = value & 255;
    this.#arena[at + 1] = value >>> 8;
  }

  #compact(): void {
    let read = 0, write = 0;
    // Stable IDs forbid sorting the directory. Select the next old extent by
    // scanning it instead: constant auxiliary storage, quadratic directory work.
    // Ascending old offsets and downward moves preserve every unread spelling.
    for (let moved = 0; moved < this.#liveNames; moved++) {
      let selected = -1, offset = SPELLING_BYTES;
      for (let id = 0; id < NAME_COUNT; id++) {
        const entry = id * DIRECTORY_STRIDE;
        if (this.#arena[entry + 2] === 0) continue;
        const candidate = this.#word(entry);
        if (candidate >= read && candidate < offset) {
          selected = entry;
          offset = candidate;
        }
      }
      const length = this.#arena[selected + 2];
      this.#arena.copyWithin(
        DIRECTORY_BYTES + write,
        DIRECTORY_BYTES + offset,
        DIRECTORY_BYTES + offset + length,
      );
      this.#putWord(selected, write);
      read = offset + length;
      write += length;
    }
    this.#allocatedBytes = write;
    this.#compactions++;
  }
}
