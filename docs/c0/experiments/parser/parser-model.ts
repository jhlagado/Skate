/** Independent host grammar model used to state expected traces for fixtures. */

export const TOKEN = Object.freeze({
  EOF: 0,
  OPEN: 1,
  CLOSE: 2,
  ATOM: 3,
  IF: 4,
  BEGIN: 5,
  LAMBDA: 6,
  NAME: 7,
});

export const ACTION = Object.freeze({
  ATOM_ACTION: 1,
  NAME_ACTION: 2,
  TOP: 3,
  IF_OPEN: 4,
  IF_TEST: 5,
  IF_THEN: 6,
  IF_ALT: 7,
  IF_ABSENT: 8,
  IF_END: 9,
  BEGIN_OPEN: 10,
  BEGIN_END: 11,
  LAMBDA_OPEN: 12,
  PARAMETER: 13,
  PARAMS_END: 14,
  BODY_VALUE: 15,
  LAMBDA_END: 16,
  APP_OPEN: 17,
  OPERATOR: 18,
  ARGUMENT: 19,
  APP_END: 20,
});

export interface TraceRecord {
  readonly action: number;
  readonly index: number;
}

export interface ReferenceResult {
  readonly ok: boolean;
  readonly code: number;
  readonly index: number;
  readonly actions: readonly TraceRecord[];
  readonly consumed: number;
}

/**
 * This parser is intentionally ordinary host code.  Native execution sees
 * only the resulting fixture bytes; it never calls or consults this model.
 */
export function referenceParse(input: readonly number[]): ReferenceResult {
  const tokens = input.map((token) => token === 0 ? 255 : token);
  let cursor = 0,
    depth = 0,
    failure: { code: number; index: number } | null = null;
  const actions: TraceRecord[] = [];

  function peek(): number {
    return cursor < tokens.length ? tokens[cursor]! : TOKEN.EOF;
  }

  function fail(code = 128): false {
    failure ??= { code, index: cursor };
    return false;
  }

  function act(action: number): boolean {
    actions.push({ action, index: cursor });
    return true;
  }

  function take(expected: number): boolean {
    if (peek() !== expected) return fail();
    if (expected === TOKEN.OPEN) {
      if (depth >= 32) return fail(129);
      depth++;
    } else if (expected === TOKEN.CLOSE) {
      depth--;
    }
    cursor++;
    return true;
  }

  function expr(): boolean {
    switch (peek()) {
      case TOKEN.ATOM:
        if (!act(ACTION.ATOM_ACTION)) return false;
        return take(TOKEN.ATOM);
      case TOKEN.NAME:
        if (!act(ACTION.NAME_ACTION)) return false;
        return take(TOKEN.NAME);
      case TOKEN.OPEN:
        if (!take(TOKEN.OPEN)) return false;
        return list();
      default:
        return fail();
    }
  }

  function list(): boolean {
    switch (peek()) {
      case TOKEN.IF:
        return ifForm();
      case TOKEN.BEGIN:
        return beginForm();
      case TOKEN.LAMBDA:
        return lambdaForm();
      default:
        return application();
    }
  }

  function ifForm(): boolean {
    if (!take(TOKEN.IF) || !act(ACTION.IF_OPEN)) return false;
    if (!expr() || !act(ACTION.IF_TEST)) return false;
    if (!expr() || !act(ACTION.IF_THEN)) return false;
    if (peek() === TOKEN.CLOSE) {
      if (!act(ACTION.IF_ABSENT)) return false;
    } else {
      if (!expr() || !act(ACTION.IF_ALT)) return false;
    }
    if (!take(TOKEN.CLOSE)) return false;
    return act(ACTION.IF_END);
  }

  function beginForm(): boolean {
    if (!take(TOKEN.BEGIN) || !act(ACTION.BEGIN_OPEN)) return false;
    while (peek() !== TOKEN.CLOSE) {
      if (!expr() || !act(ACTION.BODY_VALUE)) return false;
    }
    if (!take(TOKEN.CLOSE)) return false;
    return act(ACTION.BEGIN_END);
  }

  function lambdaForm(): boolean {
    if (!take(TOKEN.LAMBDA) || !act(ACTION.LAMBDA_OPEN)) return false;
    if (!take(TOKEN.OPEN)) return false;
    while (peek() !== TOKEN.CLOSE) {
      if (peek() !== TOKEN.NAME) return fail();
      if (!act(ACTION.PARAMETER) || !take(TOKEN.NAME)) return false;
    }
    if (!take(TOKEN.CLOSE) || !act(ACTION.PARAMS_END)) return false;
    if (!expr() || !act(ACTION.BODY_VALUE)) return false;
    while (peek() !== TOKEN.CLOSE) {
      if (!expr() || !act(ACTION.BODY_VALUE)) return false;
    }
    if (!take(TOKEN.CLOSE)) return false;
    return act(ACTION.LAMBDA_END);
  }

  function application(): boolean {
    if (!act(ACTION.APP_OPEN)) return false;
    if (!expr() || !act(ACTION.OPERATOR)) return false;
    while (peek() !== TOKEN.CLOSE) {
      if (!expr() || !act(ACTION.ARGUMENT)) return false;
    }
    if (!take(TOKEN.CLOSE)) return false;
    return act(ACTION.APP_END);
  }

  while (peek() !== TOKEN.EOF) {
    if (peek() === TOKEN.CLOSE || !expr()) break;
    if (!act(ACTION.TOP)) break;
  }
  if (failure === null && peek() !== TOKEN.EOF) fail();
  if (failure === null && cursor !== tokens.length) fail();
  const result = failure as { code: number; index: number } | null;
  return {
    ok: result === null,
    code: result === null ? 0 : result.code,
    index: result === null ? cursor : result.index,
    actions,
    consumed: cursor,
  };
}

export interface NamedCase {
  readonly name: string;
  readonly tokens: readonly number[];
}

export function nestApplications(depth: number): number[] {
  return [
    ...Array.from({ length: depth }, () => TOKEN.OPEN),
    TOKEN.ATOM,
    ...Array.from({ length: depth }, () => TOKEN.CLOSE),
  ];
}

/** Applications nested as arguments keep HARGS live across each inner form. */
export function nestArgumentApplications(depth: number): number[] {
  let expression: number[] = [TOKEN.ATOM];
  for (let count = 0; count < depth; count++) {
    expression = [TOKEN.OPEN, TOKEN.ATOM, ...expression, TOKEN.CLOSE];
  }
  return expression;
}

/** A second body expression keeps the enclosing HSEQ live across each form. */
export function nestBeginExpressions(depth: number): number[] {
  let expression: number[] = [TOKEN.ATOM];
  for (let count = 0; count < depth; count++) {
    expression = [
      TOKEN.OPEN,
      TOKEN.BEGIN,
      TOKEN.ATOM,
      ...expression,
      TOKEN.CLOSE,
    ];
  }
  return expression;
}

/** Lambdas whose nested expression is a later body value exercise HSEQ. */
export function nestLambdaLaterBodies(depth: number): number[] {
  let expression: number[] = [TOKEN.ATOM];
  for (let count = 0; count < depth; count++) {
    expression = [
      TOKEN.OPEN,
      TOKEN.LAMBDA,
      TOKEN.OPEN,
      TOKEN.CLOSE,
      TOKEN.ATOM,
      ...expression,
      TOKEN.CLOSE,
    ];
  }
  return expression;
}

export function nestLambdas(depth: number): number[] {
  const prefix = Array.from(
    { length: depth },
    () => [TOKEN.OPEN, TOKEN.LAMBDA, TOKEN.OPEN, TOKEN.CLOSE],
  ).flat();
  return [
    ...prefix,
    TOKEN.ATOM,
    ...Array.from({ length: depth }, () => TOKEN.CLOSE),
  ];
}

export function nestIfs(depth: number): number[] {
  if (depth === 0) return [TOKEN.ATOM];
  return [
    TOKEN.OPEN,
    TOKEN.IF,
    ...nestIfs(depth - 1),
    TOKEN.ATOM,
    TOKEN.CLOSE,
  ];
}

/** Deterministic malformed/partial fixtures, independent of native parsing. */
export function generatedTokenLists(count: number): number[][] {
  let state = 0x13579bdf;
  const cases: number[][] = [];
  const next = (): number => {
    state = Math.imul(state, 1664525) + 1013904223;
    return state >>> 0;
  };
  for (let caseNo = 0; caseNo < count; caseNo++) {
    const length = next() % 25;
    const tokens: number[] = [];
    for (let index = 0; index < length; index++) {
      tokens.push(next() & 255);
    }
    cases.push(tokens);
  }
  return cases;
}

export const HAND_CASES: readonly NamedCase[] = [
  { name: "empty", tokens: [] },
  { name: "atom", tokens: [TOKEN.ATOM] },
  { name: "name", tokens: [TOKEN.NAME] },
  { name: "application-one", tokens: [TOKEN.OPEN, TOKEN.ATOM, TOKEN.CLOSE] },
  {
    name: "application-many",
    tokens: [TOKEN.OPEN, TOKEN.ATOM, TOKEN.ATOM, TOKEN.NAME, TOKEN.CLOSE],
  },
  {
    name: "nested-operator",
    tokens: [
      TOKEN.OPEN,
      TOKEN.OPEN,
      TOKEN.NAME,
      TOKEN.CLOSE,
      TOKEN.ATOM,
      TOKEN.CLOSE,
    ],
  },
  {
    name: "if-two-operand",
    tokens: [TOKEN.OPEN, TOKEN.IF, TOKEN.ATOM, TOKEN.ATOM, TOKEN.CLOSE],
  },
  {
    name: "if-three-operand",
    tokens: [
      TOKEN.OPEN,
      TOKEN.IF,
      TOKEN.ATOM,
      TOKEN.ATOM,
      TOKEN.ATOM,
      TOKEN.CLOSE,
    ],
  },
  { name: "begin-empty", tokens: [TOKEN.OPEN, TOKEN.BEGIN, TOKEN.CLOSE] },
  {
    name: "begin-many",
    tokens: [TOKEN.OPEN, TOKEN.BEGIN, TOKEN.ATOM, TOKEN.NAME, TOKEN.CLOSE],
  },
  {
    name: "lambda-empty-parameters",
    tokens: [
      TOKEN.OPEN,
      TOKEN.LAMBDA,
      TOKEN.OPEN,
      TOKEN.CLOSE,
      TOKEN.ATOM,
      TOKEN.CLOSE,
    ],
  },
  {
    name: "lambda-parameters-body",
    tokens: [
      TOKEN.OPEN,
      TOKEN.LAMBDA,
      TOKEN.OPEN,
      TOKEN.NAME,
      TOKEN.NAME,
      TOKEN.CLOSE,
      TOKEN.ATOM,
      TOKEN.NAME,
      TOKEN.CLOSE,
    ],
  },
  { name: "missing-operator", tokens: [TOKEN.OPEN, TOKEN.CLOSE] },
  { name: "missing-if-test", tokens: [TOKEN.OPEN, TOKEN.IF, TOKEN.CLOSE] },
  { name: "unfinished-begin-open", tokens: [TOKEN.OPEN, TOKEN.BEGIN] },
  {
    name: "unfinished-begin-body",
    tokens: [TOKEN.OPEN, TOKEN.BEGIN, TOKEN.ATOM],
  },
  {
    name: "unfinished-lambda-formals",
    tokens: [TOKEN.OPEN, TOKEN.LAMBDA, TOKEN.OPEN],
  },
  {
    name: "unfinished-lambda-body",
    tokens: [TOKEN.OPEN, TOKEN.LAMBDA, TOKEN.OPEN, TOKEN.CLOSE],
  },
  {
    name: "unfinished-lambda-close",
    tokens: [
      TOKEN.OPEN,
      TOKEN.LAMBDA,
      TOKEN.OPEN,
      TOKEN.CLOSE,
      TOKEN.ATOM,
    ],
  },
  {
    name: "unfinished-application-argument",
    tokens: [TOKEN.OPEN, TOKEN.ATOM, TOKEN.ATOM],
  },
  {
    name: "extra-if-operand",
    tokens: [
      TOKEN.OPEN,
      TOKEN.IF,
      TOKEN.ATOM,
      TOKEN.ATOM,
      TOKEN.ATOM,
      TOKEN.ATOM,
      TOKEN.CLOSE,
    ],
  },
  {
    name: "malformed-formals",
    tokens: [
      TOKEN.OPEN,
      TOKEN.LAMBDA,
      TOKEN.OPEN,
      TOKEN.ATOM,
      TOKEN.CLOSE,
      TOKEN.ATOM,
      TOKEN.CLOSE,
    ],
  },
  { name: "reserved-value", tokens: [TOKEN.IF] },
  { name: "trailing-close", tokens: [TOKEN.CLOSE] },
  { name: "unfinished-application", tokens: [TOKEN.OPEN, TOKEN.ATOM] },
  {
    name: "unfinished-if",
    tokens: [TOKEN.OPEN, TOKEN.IF, TOKEN.ATOM, TOKEN.ATOM],
  },
  {
    name: "unfinished-if-close",
    tokens: [TOKEN.OPEN, TOKEN.IF, TOKEN.ATOM, TOKEN.ATOM, TOKEN.ATOM],
  },
  { name: "unknown-token", tokens: [42] },
  { name: "embedded-zero", tokens: [TOKEN.ATOM, 0, TOKEN.NAME] },
];
