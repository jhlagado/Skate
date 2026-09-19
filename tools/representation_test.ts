import assert from "node:assert/strict";
import {
  type Cell,
  classify,
  decodePair,
  escaped,
  FALSE,
  type Heap,
  markBounded,
  markFixedpoint,
  markReference,
  MASK,
  NIL,
  ordinary,
  RAW,
  REF,
  reference,
  SCALAR,
  type Value,
} from "./representation.ts";

Deno.test("all 65536 scalar encodings have the expected classification", () => {
  const counts = {
    number: 0,
    immediate: 0,
    primitive: 0,
    character: 0,
    invalid: 0,
  };
  for (let bits = 0; bits < 65536; bits++) counts[classify(bits)]++;
  assert.deepEqual(counts, {
    number: 63491,
    immediate: 6,
    primitive: 29,
    character: 256,
    invalid: 1754,
  });
});

Deno.test("every usable link and assigned reference subtype round-trips", () => {
  for (let index = 1; index <= MASK; index++) {
    assert.equal((index << 2) >>> 2, index);
    for (let subtype = 0; subtype < 5; subtype++) {
      const [tag, payload] = reference(subtype, index);
      assert.equal(tag, REF);
      assert.equal(payload >>> 13, subtype);
      assert.equal(payload & MASK, index);
    }
    const heap: Heap = [null, ordinary([SCALAR, 0x3c00], index)];
    assert.deepEqual(decodePair(heap, 1)[1], reference(0, index));
  }
});

Deno.test("144 escaped pair combinations preserve both logical values", () => {
  const values: Value[] = [0, 0x8000, 0x3c00, 0x7e00, FALSE, NIL, 0xffff].map((
    payload,
  ) => [SCALAR, payload]);
  for (let subtype = 0; subtype < 5; subtype++) {
    values.push(reference(subtype, 17));
  }
  for (const car of values) {
    for (const cdr of values) {
      const [header, auxiliary] = escaped(car, cdr, 2);
      assert.deepEqual(decodePair([null, header, auxiliary], 1), [car, cdr]);
    }
  }
});

function mixedGraph(): Heap {
  const [header, auxiliary] = escaped(reference(2, 1), reference(0, 4), 5);
  return [
    null,
    [0xabcd, (RAW << 13) | 2],
    ordinary([SCALAR, NIL], 3),
    ordinary(reference(2, 1), 0),
    header,
    auxiliary,
    ordinary(reference(1, 7), 0),
    ordinary([SCALAR, 0], 0),
  ];
}

Deno.test("mixed closure, environment and escaped-pair cycle excludes a symbol's index", () => {
  const heap = mixedGraph();
  const expected = new Set([1, 2, 3, 4, 5, 6]);
  assert.deepEqual(markFixedpoint(heap, [4, 6]).marked, expected);
  assert.deepEqual(markReference(heap, [4, 6]), expected);
});

Deno.test("100 deterministic graphs agree across tracing strategies", () => {
  // Portable fixed-seed generator: graph coverage, not a runtime randomness API.
  let state = 15;
  function randomInt(limit: number): number {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state % limit;
  }
  for (let trial = 0; trial < 100; trial++) {
    const heap: (readonly [number, number] | null)[] = [null];
    for (let index = 1; index <= 128; index++) {
      heap.push(ordinary(reference(0, 1 + randomInt(128)), randomInt(129)));
    }
    const roots = [1 + randomInt(128)];
    const expected = markReference(heap, roots);
    assert.deepEqual(markFixedpoint(heap, roots).marked, expected);
    assert.deepEqual(markBounded(heap, roots, 2).marked, expected);
  }
});

Deno.test("reverse chain exposes scan cost but fits a one-entry worklist", () => {
  const heap: (readonly [number, number] | null)[] = [null];
  for (let index = 1; index <= 128; index++) {
    heap.push(ordinary([SCALAR, 0], index - 1));
  }
  const result = markFixedpoint(heap, [128]);
  assert.equal(result.marked.size, 128);
  assert.equal(result.passes, 128);
  assert.deepEqual(markBounded(heap, [128], 1), {
    marked: result.marked,
    overflow: false,
  });
});

Deno.test("worklist overflow preserves all reachable cells", () => {
  assert.deepEqual(markBounded(mixedGraph(), [4, 6], 1), {
    marked: new Set([1, 2, 3, 4, 5, 6]),
    overflow: true,
  });
});

Deno.test("host binary16 rounds 2049 to 2048 and preserves 2050", () => {
  assert.equal(Math.f16round(2048), 2048);
  assert.equal(Math.f16round(2049), 2048);
  assert.equal(Math.f16round(2050), 2050);
});

Deno.test("escaped CDR uniquely retains each heap reference subtype and descendants", () => {
  for (const subtype of [0, 2, 3]) {
    const [anchor, aux] = escaped([SCALAR, 0x3c00], reference(subtype, 3), 2);
    const heap: Heap = [
      null,
      anchor,
      aux,
      subtype === 2 ? [0x1234, (RAW << 13) | 4] : ordinary([SCALAR, NIL], 4),
      ordinary([SCALAR, NIL], 0),
      ordinary([SCALAR, NIL], 0),
    ];
    const expected = new Set([1, 2, 3, 4]);
    assert.deepEqual(markReference(heap, [1]), expected);
    assert.deepEqual(markFixedpoint(heap, [1]).marked, expected);
    assert.deepEqual(markBounded(heap, [1], 1).marked, expected);
  }
});
Deno.test("environment CAR is the sole path to its parent and bindings", () => {
  const heap: Heap = [
    null,
    ordinary(reference(3, 2), 0),
    ordinary([SCALAR, NIL], 3),
    ordinary([SCALAR, 0x3c00], 0),
    ordinary([SCALAR, NIL], 0),
  ];
  const expected = new Set([1, 2, 3]);
  assert.deepEqual(markReference(heap, [1]), expected);
  assert.deepEqual(markFixedpoint(heap, [1]).marked, expected);
  assert.deepEqual(markBounded(heap, [1], 1).marked, expected);
});
Deno.test("escaped CAR uniquely retains heap values and ignores numeric and permanent indices", () => {
  for (const subtype of [0, 2, 3]) {
    const [anchor, aux] = escaped(reference(subtype, 3), [3, 4], 2);
    const heap: Heap = [
      null,
      anchor,
      aux,
      ordinary([SCALAR, NIL], 0),
      ordinary([SCALAR, NIL], 0),
    ];
    assert.deepEqual(markBounded(heap, [1], 1).marked, new Set([1, 2, 3]));
  }
  for (
    const value of [
      [3, 3],
      [SCALAR, 3],
      reference(1, 3),
      reference(4, 3),
    ] as Value[]
  ) {
    const [anchor, aux] = escaped(value, value, 2);
    const heap: Heap = [null, anchor, aux, ordinary([SCALAR, NIL], 0)];
    assert.deepEqual(markBounded(heap, [1], 1).marked, new Set([1, 2]));
  }
});
Deno.test("all integer payloads round-trip in ordinary and escaped pairs without becoming edges", () => {
  for (let bits = 0; bits < 65536; bits++) {
    const value: Value = [3, bits];
    const h: Heap = [null, ordinary(value, 2), ordinary([SCALAR, NIL], 0)];
    assert.deepEqual(decodePair(h, 1)[0], value);
    assert.deepEqual(markReference(h, [1]), new Set([1, 2]));
    const [anchor, aux] = escaped(value, value, 2);
    assert.deepEqual(decodePair([null, anchor, aux], 1), [value, value]);
    assert.deepEqual(markReference([null, anchor, aux], [1]), new Set([1, 2]));
  }
});
Deno.test("capture-free closures avoid the demonstrated tail-loop retention chain", () => {
  function graph(iterations: number, capture: boolean) {
    const heap: (Cell | null)[] = [null];
    let env = 0;
    for (let i = 0; i < iterations; i++) {
      let value: Value = [SCALAR, FALSE];
      if (env) {
        const closure = heap.length;
        heap.push([0x1234, (RAW << 13) | (capture ? env : 0)]);
        value = reference(2, closure);
      }
      const next = heap.length;
      heap.push(ordinary([SCALAR, NIL], next + 1));
      heap.push(ordinary(value, 0));
      env = next;
    }
    return markReference(heap, [env]).size;
  }
  for (const n of [10, 100, 1000]) {
    assert.equal(graph(n, true), 3 * n - 1);
    assert.equal(graph(n, false), 3);
  }
});
