/** Byte-backed host binding model. Native code, captures and execution are unproved. */
import assert from "node:assert/strict";
import {
  ARENA_BYTES,
  DIRECTORY_STRIDE,
  NAME_COUNT,
  NamePool,
} from "./name-pool.ts";
import { StagedOutput } from "./tail-chains.ts";
const BIND = ARENA_BYTES, GROUP = BIND + 64 * 4, SCOPE = GROUP + 64 * 12;
const NONE = 0xffff, GLOBAL = 1, DECLARED = 2, OPEN = 1, PIN = 0x80;
export interface Position {
  part: number;
  offset: number;
}
type Destination =
  | { kind: "local"; depth: number; slot: number }
  | { kind: "wait"; owner: number }
  | { kind: "global" };
const bytes = (...words: number[]) =>
  Uint8Array.from(words.flatMap((n) => [n & 255, n >>> 8]));

export class BindingResolver {
  readonly arena = new Uint8Array(8192);
  readonly names = new NamePool(this.arena.subarray(0, ARENA_BYTES));
  readonly output = new StagedOutput();
  private bindings = 0;
  private scopes = 0;
  private groups = 0;
  private pending = 0;
  private peakBindings = 0;
  private peakScopes = 0;
  private peakGroups = 0;
  private peakPending = 0;
  private dynamicGlobals = 0;
  private globalSlots: number;
  constructor(readonly predefined: readonly string[] = []) {
    assert.ok(
      predefined.length < 0x8000 &&
        new Set(predefined).size === predefined.length,
    );
    this.globalSlots = predefined.length;
    for (let g = 0; g < 64; g++) this.put(GROUP + g * 12, NONE);
  }
  private word(at: number) {
    return this.arena[at] + 256 * this.arena[at + 1];
  }
  private put(at: number, n: number) {
    this.arena[at] = n & 255;
    this.arena[at + 1] = n >>> 8;
  }
  private active(id: number) {
    return id < NAME_COUNT && this.arena[id * DIRECTORY_STRIDE + 2] !== 0;
  }
  private lookup(name: string): number | undefined {
    const p = this.predefined.indexOf(name);
    if (p >= 0) return 0x8000 + p;
    for (let id = 0; id < NAME_COUNT; id++) {
      if (this.active(id) && this.names.spelling(id) === name) return id;
    }
  }
  private id(name: string) {
    try {
      return this.lookup(name) ?? this.names.intern(name);
    } catch (error) {
      this.output.failed = true;
      throw error;
    }
  }
  private globalSlot(id: number) {
    return id >= 0x8000 ? id - 0x8000 : this.predefined.length + id;
  }
  private position(p: Position) {
    if (!Number.isInteger(p.part) || p.part < 0 || p.part >= 255) {
      this.output.failed = true;
      throw new Error("source part capacity");
    }
    if (!Number.isInteger(p.offset) || p.offset < 0 || p.offset > 65535) {
      this.output.failed = true;
      throw new Error("source offset capacity");
    }
  }
  private capacity(count: number, limit: number, what: string) {
    if (count >= limit) {
      this.output.failed = true;
      throw new Error(`${what} capacity`);
    }
  }
  private ready() {
    if (this.output.failed) throw new Error("abandoned generation");
  }
  private fail(why: string): never {
    this.output.failed = true;
    throw new Error(why);
  }

  /** Mark the private generation unusable after a source-side capacity error. */
  abort() {
    this.output.failed = true;
  }

  /** Stage a let binder without adding a second persistent name table. */
  stage(name: string): number {
    this.ready();
    try {
      const id = this.names.intern(name);
      this.names.setFlags(id, this.names.getFlags(id) | PIN);
      return id;
    } catch (error) {
      this.output.failed = true;
      throw error;
    }
  }

  /** Drop one staged binder owner; callers retain the pin while another owner remains. */
  unstage(id: number, retain: boolean) {
    this.ready();
    const flags = this.names.getFlags(id);
    this.names.setFlags(id, retain ? flags : flags & ~PIN);
  }
  private sample() {
    this.peakBindings = Math.max(this.peakBindings, this.bindings);
    this.peakScopes = Math.max(this.peakScopes, this.scopes);
    this.peakGroups = Math.max(this.peakGroups, this.groups);
    this.peakPending = Math.max(this.peakPending, this.pending);
  }
  enterScope() {
    this.ready();
    this.capacity(this.scopes, 48, "scope");
    const at = SCOPE + this.scopes * 8;
    this.arena.fill(0, at, at + 8);
    this.arena[at] = this.scopes === 0 ? 255 : this.scopes - 1;
    this.arena[at + 1] = OPEN;
    this.arena[at + 2] = this.scopes + 1;
    this.arena[at + 4] = this.bindings;
    this.scopes++;
    this.sample();
  }
  private destination(
    id: number | undefined,
    start = this.scopes - 1,
  ): Destination {
    for (let s = start; s >= 0; s--) {
      for (let b = this.bindings - 1; b >= 0; b--) {
        const at = BIND + b * 4;
        if (this.arena[at + 3] === s && this.word(at) === id) {
          return { kind: "local", depth: s + 1, slot: this.arena[at + 2] };
        }
      }
      if (this.arena[SCOPE + s * 8 + 1] & OPEN) {
        return { kind: "wait", owner: s };
      }
    }
    return { kind: "global" };
  }
  declare(name: string): number {
    this.ready();
    const existing = this.lookup(name);
    if (this.scopes === 0) {
      const id = this.id(name);
      if (id >= 0x8000) return this.globalSlot(id);
      const flags = this.names.getFlags(id);
      if (!(flags & GLOBAL)) {
        this.dynamicGlobals++;
        this.globalSlots = Math.max(this.globalSlots, this.globalSlot(id) + 1);
      }
      if ((flags & GLOBAL) && !(flags & DECLARED)) {
        this.output.rewrite(
          this.names.getMeta(id),
          bytes(NONE, this.globalSlot(id)),
          true,
        );
        this.pending--;
      }
      this.names.setFlags(id, flags | GLOBAL | DECLARED);
      this.names.setMeta(id, 0);
      return this.globalSlot(id);
    }
    const s = this.scopes - 1, at = SCOPE + s * 8;
    assert.ok(this.arena[at + 1] & OPEN, "definition region sealed");
    for (let b = this.arena[at + 4]; b < this.bindings; b++) {
      if (this.word(BIND + b * 4) === existing) {
        throw new Error("duplicate local binding");
      }
    }
    this.capacity(this.bindings, 64, "binding");
    const id = this.id(name), slot = this.arena[at + 3];
    const b = BIND + this.bindings * 4;
    this.put(b, id);
    this.arena[b + 2] = slot;
    this.arena[b + 3] = s;
    this.bindings++;
    this.arena[at + 3]++;
    this.sample();
    for (let g = 0; g < 64; g++) {
      if (
        this.word(GROUP + g * 12) === id && this.arena[GROUP + g * 12 + 2] === s
      ) this.resolveGroup(g, { kind: "local", depth: s + 1, slot });
    }
    return slot;
  }
  private findGroup(id: number | undefined, owner: number, procedure: number) {
    for (let g = 0; g < 64; g++) {
      const at = GROUP + g * 12;
      if (
        this.word(at) === id && this.arena[at + 2] === owner &&
        this.word(at + 10) === procedure
      ) return g;
    }
    return -1;
  }
  private freeGroup() {
    for (let g = 0; g < 64; g++) {
      if (this.word(GROUP + g * 12) === NONE) return g;
    }
    this.output.failed = true;
    throw new Error("group capacity");
  }
  private emit(operands: Uint8Array) {
    return this.output.append(Uint8Array.of(0xcd, 0, 1, ...operands));
  }
  private globalOperands(id: number, p: Position, operand: number): Uint8Array {
    if (id >= 0x8000) return bytes(NONE, this.globalSlot(id));
    const flags = this.names.getFlags(id);
    if (flags & GLOBAL) return bytes(NONE, this.globalSlot(id));
    this.names.setFlags(id, flags | GLOBAL);
    this.names.setMeta(id, operand);
    this.dynamicGlobals++;
    this.globalSlots = Math.max(this.globalSlots, this.globalSlot(id) + 1);
    this.pending++;
    this.sample();
    return Uint8Array.of(p.part, p.offset & 255, p.offset >>> 8, 0);
  }
  use(name: string, p: Position, originProcedure = 0): { site: number } {
    this.ready();
    this.position(p);
    if (
      !Number.isInteger(originProcedure) || originProcedure < 0 ||
      originProcedure > 65535
    ) {
      this.output.failed = true;
      throw new Error("procedure key capacity");
    }
    if (this.output.length + 7 > this.output.bytes.length) {
      this.output.failed = true;
      throw new Error("output capacity");
    }
    const existing = this.lookup(name), dest = this.destination(existing);
    let group = dest.kind === "wait"
      ? this.findGroup(existing, dest.owner, originProcedure)
      : -1;
    if (dest.kind === "wait" && group < 0) this.freeGroup(); // Preflight before interning.
    const id = this.id(name), site = this.output.length, operand = site + 3;
    if (dest.kind === "local") {
      this.emit(bytes(this.scopes - dest.depth, dest.slot));
    } else if (dest.kind === "global") {
      this.emit(this.globalOperands(id, p, operand));
    } else {
      this.emit(bytes(this.scopes, NONE));
      if (group < 0) {
        group = this.freeGroup();
        const at = GROUP + group * 12;
        this.put(at, id);
        this.arena[at + 2] = dest.owner;
        this.put(at + 3, operand);
        this.put(at + 5, operand);
        this.arena[at + 7] = p.part;
        this.put(at + 8, p.offset);
        this.put(at + 10, originProcedure);
        this.groups++;
      } else {
        const at = GROUP + group * 12;
        this.output.rewrite(this.word(at + 5) + 2, bytes(operand));
        this.put(at + 5, operand);
      }
      this.pending++;
      this.sample();
    }
    return { site };
  }
  private clearGroup(g: number) {
    const at = GROUP + g * 12;
    this.arena.fill(0, at, at + 12);
    this.put(at, NONE);
    this.groups--;
  }
  private resolveGroup(g: number, dest: Destination) {
    const at = GROUP + g * 12,
      id = this.word(at),
      head = this.word(at + 3),
      tail = this.word(at + 5);
    if (dest.kind === "wait") {
      const other = this.findGroup(id, dest.owner, this.word(at + 10));
      if (other < 0) this.arena[at + 2] = dest.owner;
      else {
        const to = GROUP + other * 12;
        assert.notEqual(this.word(to + 5), tail, "aliased binding groups");
        this.output.rewrite(this.word(to + 5) + 2, bytes(head));
        this.put(to + 5, tail);
        if (
          this.arena[at + 7] < this.arena[to + 7] ||
          (this.arena[at + 7] === this.arena[to + 7] &&
            this.word(at + 8) < this.word(to + 8))
        ) {
          this.arena[to + 7] = this.arena[at + 7];
          this.put(to + 8, this.word(at + 8));
        }
        this.clearGroup(g);
      }
      return;
    }
    let operand = head, visited = 0;
    const bound = this.pending; // Count before global conversion can add a diagnostic hold.
    while (true) {
      if (++visited > bound) this.fail("binding chain cycle");
      const data = this.output.read(operand, 4),
        depth = data[0] + 256 * data[1],
        next = data[2] + 256 * data[3];
      if (operand === tail) {
        if (next !== NONE) this.fail("unterminated binding chain");
      } else if (next === NONE || next + 4 > this.output.length) {
        this.fail("invalid binding link");
      }
      if (dest.kind === "local") {
        if (depth < dest.depth) this.fail("negative lexical distance");
        this.output.rewrite(
          operand,
          bytes(depth - dest.depth, dest.slot),
          true,
        );
      } else {
        const first = id < 0x8000 && !(this.names.getFlags(id) & GLOBAL);
        const replacement = this.globalOperands(id, {
          part: this.arena[at + 7],
          offset: this.word(at + 8),
        }, operand);
        this.output.rewrite(operand, replacement, !first);
      }
      this.pending--;
      if (operand === tail) break;
      operand = next;
    }
    this.clearGroup(g);
    this.releaseUnusedName(id);
  }
  seal() {
    this.ready();
    assert.ok(this.scopes > 0, "package cannot seal as a local scope");
    const s = this.scopes - 1;
    this.arena[SCOPE + s * 8 + 1] &= ~OPEN;
    for (let g = 0; g < 64; g++) {
      if (
        this.word(GROUP + g * 12) !== NONE &&
        this.arena[GROUP + g * 12 + 2] === s
      ) {
        this.resolveGroup(g, this.destination(this.word(GROUP + g * 12), s));
      }
    }
  }
  reopenDefinitions() {
    this.ready();
    assert.ok(this.scopes > 0);
    this.arena[SCOPE + (this.scopes - 1) * 8 + 1] |= OPEN;
  }
  leaveScope() {
    this.seal();
    const s = this.scopes - 1, at = SCOPE + s * 8, mark = this.arena[at + 4];
    this.arena.fill(0, BIND + mark * 4, BIND + this.bindings * 4);
    this.bindings = mark;
    this.arena.fill(0, at, at + 8);
    this.scopes--;
    for (let id = 0; id < NAME_COUNT; id++) this.releaseUnusedName(id);
  }
  releaseUnusedName(id: number) {
    if (!this.active(id) || this.names.getFlags(id) !== 0) return;
    for (let b = 0; b < this.bindings; b++) {
      if (this.word(BIND + b * 4) === id) return;
    }
    for (let g = 0; g < 64; g++) if (this.word(GROUP + g * 12) === id) return;
    this.names.release(id);
  }
  finish() {
    this.ready();
    if (this.scopes || this.groups || this.bindings) {
      this.fail("unfinished binding scopes");
    }
    for (let id = 0; id < NAME_COUNT; id++) {
      if (this.active(id)) {
        const flags = this.names.getFlags(id);
        if ((flags & GLOBAL) && !(flags & DECLARED)) {
          const p = this.output.read(this.names.getMeta(id), 4);
          this.fail(
            `undefined ${this.names.spelling(id)} at ${p[0]}:${
              p[1] + 256 * p[2]
            }`,
          );
        }
      }
    }
    if (this.pending) this.fail("unfinished binding sites");
  }
  snapshot() {
    return {
      names: this.names.snapshot(),
      liveBindings: this.bindings,
      peakBindings: this.peakBindings,
      liveScopes: this.scopes,
      peakScopes: this.peakScopes,
      liveGroups: this.groups,
      peakGroups: this.peakGroups,
      pendingSites: this.pending,
      peakPendingSites: this.peakPending,
      dynamicGlobals: this.dynamicGlobals,
      globalSlots: this.globalSlots,
      arenaBytes: 8192,
      nameBytes: ARENA_BYTES,
      bindingBytes: 256,
      groupBytes: 768,
      scopeBytes: 384,
      reservedLiteralIdentityBytes: 384,
      reservedControlBytes: 64,
    };
  }
}
