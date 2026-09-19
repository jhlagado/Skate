/** Host model: bounded tail handles; links occupy eventual machine operands. */
import assert from "node:assert/strict";

const NONE = 0xffff;
const CALL = 0xcd, JP = 0xc3;
export const HANDLE_COUNT = 64;
export const HANDLE_BYTES = HANDLE_COUNT * 4;
export const OUTPUT_CAPACITY = 0xe400 - 0x0100;
export const EMPTY = -1;
export interface ResolvedPatch {
  offset: number;
  bytes: Uint8Array;
}

/** Disk oracle only. Its backing array and final patches are not resident RAM. */
export class StagedOutput {
  readonly bytes: Uint8Array;
  readonly patches: ResolvedPatch[] = [];
  length = 0;
  reads = 0;
  writes = 0;
  spoolWrites = 0;
  failed = false;
  failRead = Infinity;
  failWrite = Infinity;
  failSpoolWrite = Infinity;
  constructor(capacity = OUTPUT_CAPACITY) {
    assert.ok(
      Number.isInteger(capacity) && capacity > 0 && capacity <= OUTPUT_CAPACITY,
      "output capacity bounds",
    );
    this.bytes = new Uint8Array(capacity);
  }
  private ready() {
    if (this.failed) throw new Error("abandoned generation");
  }
  private bounds(offset: number, count: number) {
    assert.ok(
      Number.isInteger(offset) && offset >= 0 && count > 0 &&
        offset + count <= this.length,
      "output site bounds",
    );
  }
  append(bytes: Uint8Array): number {
    this.ready();
    if (this.length + bytes.length > this.bytes.length) {
      this.failed = true;
      throw new Error("output capacity");
    }
    const offset = this.length;
    if (++this.writes === this.failWrite) {
      this.failed = true;
      throw new Error("output write");
    }
    this.bytes.set(bytes, offset);
    this.length += bytes.length;
    return offset;
  }
  read(offset: number, count: number): Uint8Array {
    this.ready();
    this.bounds(offset, count);
    if (++this.reads === this.failRead) {
      this.failed = true;
      throw new Error("output read");
    }
    return this.bytes.slice(offset, offset + count);
  }
  rewrite(offset: number, bytes: Uint8Array, resolved = false) {
    this.ready();
    this.bounds(offset, bytes.length);
    if (++this.writes === this.failWrite) {
      this.failed = true;
      throw new Error("output write");
    }
    this.bytes.set(bytes, offset);
    if (resolved) {
      // The staged-COM change and resolved-PATCH spool append are distinct I/O.
      if (++this.spoolWrites === this.failSpoolWrite) {
        this.failed = true;
        throw new Error("patch spool write");
      }
      this.patches.push({ offset, bytes: bytes.slice() });
    }
  }
}
const word = (bytes: Uint8Array, offset: number) =>
  bytes[offset] + 256 * bytes[offset + 1];
const putWord = (bytes: Uint8Array, offset: number, value: number) => {
  bytes[offset] = value & 255;
  bytes[offset + 1] = value >>> 8;
};

/**
 * Handles are linear: merge consumes both inputs and returns one owner; resolve
 * consumes its owner. EMPTY is the only chain with no owned handle. Links are
 * monotonic because tail branches are emitted and concatenated in source order.
 * This invariant is specific to tail chains, not grouped lexical-use chains.
 * Numeric ordinals can be reused; callers must never keep stale copies after
 * merge/resolve. Four-byte handles cannot detect an old owner after ID reuse.
 */
export class TailChains {
  readonly handles = new Uint8Array(HANDLE_BYTES).fill(255);
  private outstanding = 0;
  private live = 0;
  private high = 0;
  private peakSites = 0;
  constructor(readonly output: StagedOutput) {}
  private extent(handle: number): [number, number] {
    assert.ok(
      Number.isInteger(handle) && handle >= 0 && handle < HANDLE_COUNT,
      "handle bounds",
    );
    const at = handle * 4;
    const head = word(this.handles, at), tail = word(this.handles, at + 2);
    assert.ok(head !== NONE && head <= tail, "consumed or invalid handle");
    return [head, tail];
  }
  private clear(handle: number) {
    this.handles.fill(255, handle * 4, handle * 4 + 4);
    this.live--;
  }
  private callBytes(site: number): Uint8Array {
    const bytes = this.output.read(site, 3);
    assert.equal(bytes[0], CALL, "pending site opcode");
    return bytes;
  }
  private terminal(site: number) {
    assert.equal(word(this.callBytes(site), 1), NONE, "nonterminal tail");
  }
  candidate(): number {
    let free = -1;
    for (let i = 0; i < HANDLE_COUNT; i++) {
      if (word(this.handles, i * 4) === NONE) {
        free = i;
        break;
      }
    }
    if (free === -1) throw new Error("tail handle capacity");
    // Append validates output capacity before any handle state is committed.
    const site = this.output.append(Uint8Array.of(CALL, 255, 255));
    putWord(this.handles, free * 4, site);
    putWord(this.handles, free * 4 + 2, site);
    this.live++;
    this.outstanding++;
    this.high = Math.max(this.high, this.live);
    this.peakSites = Math.max(this.peakSites, this.outstanding);
    return free;
  }
  knownCall(target: number) {
    this.checkTarget(target);
    return this.output.append(Uint8Array.of(CALL, target & 255, target >>> 8));
  }
  merge(left: number, right: number): number {
    if (left === EMPTY) {
      if (right !== EMPTY) this.extent(right);
      return right;
    }
    if (right === EMPTY) {
      this.extent(left);
      return left;
    }
    assert.notEqual(left, right, "duplicate handle");
    const [head, tail] = this.extent(left),
      [otherHead, otherTail] = this.extent(right);
    assert.ok(
      tail + 3 <= otherHead,
      "tail chains out of emission order or aliased",
    );
    this.terminal(tail);
    this.terminal(otherTail);
    // Only a temporary link changes here; it must not enter the final PATCH spool.
    this.output.rewrite(
      tail + 1,
      Uint8Array.of(otherHead & 255, otherHead >>> 8),
    );
    this.clear(left);
    this.clear(right);
    putWord(this.handles, left * 4, head);
    putWord(this.handles, left * 4 + 2, otherTail);
    this.live++;
    return left;
  }
  private checkTarget(target: number) {
    assert.ok(
      Number.isInteger(target) && target >= 0x0100 && target < 0xe400,
      "target bounds",
    );
  }
  resolve(handle: number, tail: boolean, target: number) {
    this.checkTarget(target);
    if (handle === EMPTY) return;
    const [head, last] = this.extent(handle);
    let site = head, visited = 0;
    while (true) {
      assert.ok(
        ++visited <= this.outstanding,
        "chain exceeds pending-site bound",
      );
      const next = word(this.callBytes(site), 1);
      if (site === last) assert.equal(next, NONE, "tail not terminated");
      else {assert.ok(
          next >= site + 3 && next <= last,
          "invalid or cyclic link",
        );}
      // Read the link before replacing the eventual instruction and recording
      // its sole final patch. An I/O failure abandons the private generation.
      this.output.rewrite(
        site,
        Uint8Array.of(tail ? JP : CALL, target & 255, target >>> 8),
        true,
      );
      if (site === last) break;
      site = next;
    }
    this.outstanding -= visited;
    this.clear(handle);
  }
  /** Required before accepting this component's output, not a publication API. */
  finish() {
    if (this.output.failed) throw new Error("abandoned generation");
    if (this.live !== 0 || this.outstanding !== 0) {
      this.output.failed = true;
      throw new Error("unfinished tail sites");
    }
  }
  get metrics() {
    return {
      handleBytes: HANDLE_BYTES,
      scalarCounterBytes: 8,
      liveHandles: this.live,
      peakHandles: this.high,
      outstandingSites: this.outstanding,
      peakSites: this.peakSites,
    };
  }
}
