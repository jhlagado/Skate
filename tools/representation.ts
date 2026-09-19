/** Non-production architecture model. This does not execute Z80 code. */
export const SCALAR = 0;
export const REF = 1;
export const RAW = 2;
export const INTEGER = 3;
export const AUX = 6;
export const ESC = 7;
export const MASK = 0x1fff;
export const FALSE = 0xfe00;
export const NIL = 0xfe02;
export const UNBOUND = 0xfe05;

export type Value = readonly [tag: number, payload: number];
export type Cell = readonly [payload: number, tagAndLink: number];
export type Heap = readonly (Cell | null)[];
export type ScalarClass =
  | "number"
  | "immediate"
  | "primitive"
  | "character"
  | "invalid";

function require(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function cellAt(heap: Heap, index: number): Cell {
  const cell = heap[index];
  require(cell !== null && cell !== undefined, `Missing cell ${index}`);
  return cell;
}

export function reference(kind: number, index: number): Value {
  require(
    kind >= 0 && kind < 5 && index >= 0 && index <= MASK,
    "Invalid reference",
  );
  return [REF, (kind << 13) | index];
}

export function classify(bits: number): ScalarClass {
  const nan = (bits & 0x7c00) === 0x7c00 && (bits & 0x03ff) !== 0;
  if (!nan || bits === 0x7e00) return "number";
  if (bits >= FALSE && bits <= UNBOUND) return "immediate";
  if (bits >= 0xfe20 && bits <= 0xfe3c) return "primitive";
  if (bits >= 0xff00 && bits <= 0xffff) return "character";
  return "invalid";
}

export function ordinary([tag, payload]: Value, link: number): Cell {
  require(
    (tag === SCALAR || tag === REF || tag === INTEGER) && link >= 0 &&
      link <= MASK,
    "Invalid ordinary cell",
  );
  return [payload, (tag << 13) | link];
}

export function escaped(
  car: Value,
  cdr: Value,
  auxiliary: number,
): readonly [Cell, Cell] {
  return [
    [car[1], 0xe000 | auxiliary],
    [cdr[1], 0xc000 | (car[0] << 3) | cdr[0]],
  ];
}

export function decodePair(heap: Heap, index: number): readonly [Value, Value] {
  const [payload, word] = cellAt(heap, index);
  const tag = word >>> 13;
  const link = word & MASK;
  if (tag === SCALAR || tag === REF || tag === INTEGER) {
    return [[tag, payload], link ? reference(0, link) : [SCALAR, NIL]];
  }
  require(tag === ESC && link !== 0, "Invalid pair anchor");
  const [cdrPayload, metadata] = cellAt(heap, link);
  require(
    (metadata >>> 13) === AUX && (metadata & 0x1fc0) === 0,
    "Invalid auxiliary cell",
  );
  return [[(metadata >>> 3) & 7, payload], [metadata & 7, cdrPayload]];
}

function valueEdges([tag, payload]: Value): number[] {
  const subtype = payload >>> 13;
  const index = payload & MASK;
  return tag === REF && (subtype === 0 || subtype === 2 || subtype === 3) &&
      index !== 0
    ? [index]
    : [];
}

export function edges(heap: Heap, index: number): number[] {
  const [payload, word] = cellAt(heap, index);
  const tag = word >>> 13;
  const link = word & MASK;
  if (tag === SCALAR || tag === REF || tag === RAW || tag === INTEGER) {
    return [
      ...(link ? [link] : []),
      ...(tag === RAW ? [] : valueEdges([tag, payload])),
    ];
  }
  if (tag === ESC) {
    const [car, cdr] = decodePair(heap, index);
    return [link, ...valueEdges(car), ...valueEdges(cdr)];
  }
  require(tag === AUX, "Unknown physical tag");
  return [];
}

export function markFixedpoint(
  heap: Heap,
  roots: Iterable<number>,
): { marked: Set<number>; passes: number } {
  const marked = new Set(roots);
  let passes = 0;
  while (true) {
    const before = marked.size;
    passes++;
    for (let index = 1; index < heap.length; index++) {
      if (marked.has(index)) {
        for (const child of edges(heap, index)) marked.add(child);
      }
    }
    if (marked.size === before) return { marked, passes };
  }
}

/** Independent traversal strategy; shares only the model's edge decoder. */
export function markReference(
  heap: Heap,
  roots: Iterable<number>,
): Set<number> {
  const marked = new Set<number>();
  const pending = [...roots];
  while (pending.length > 0) {
    const index = pending.pop()!;
    if (!marked.has(index)) {
      marked.add(index);
      pending.push(...edges(heap, index));
    }
  }
  return marked;
}

export function markBounded(
  heap: Heap,
  roots: Iterable<number>,
  capacity: number,
): { marked: Set<number>; overflow: boolean } {
  let marked = new Set<number>();
  const pending: number[] = [];
  let overflow = false;
  function visit(index: number) {
    if (marked.has(index)) return;
    marked.add(index);
    if (pending.length < capacity) pending.push(index);
    else overflow = true;
  }
  for (const root of roots) visit(root);
  while (pending.length > 0) {
    for (const child of edges(heap, pending.pop()!)) visit(child);
  }
  if (overflow) marked = markFixedpoint(heap, marked).marked;
  return { marked, overflow };
}
