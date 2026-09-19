/**
 * Bounded, source-level syntax-rules expansion for the host Skate compiler.
 *
 * The expander deliberately produces an ordinary source stream. The existing
 * compiler, reader tables and generated runtime therefore remain the authority
 * for language semantics after expansion. Syntax objects retain their source
 * position so the serialized stream can map diagnostics back to authored code.
 */
import { formatNumber, type Value } from "./numeric.ts";
import {
  type Position,
  type ReadEvent,
  type SourceLocator,
  SourceReader,
} from "./reader.ts";

export interface SyntaxRulesLimits {
  /** Maximum nested macro rewrites for one form. */
  readonly maxExpansionDepth: number;
  /** Maximum total macro rewrites in one source package. */
  readonly maxExpansionSteps: number;
  /** Maximum compile-time macro definitions in one source package. */
  readonly maxMacroDefinitions: number;
  /** Maximum values matched or emitted by one ellipsis repetition. */
  readonly maxRepetitions: number;
  /** Maximum serialized bytes after expansion. */
  readonly maxOutputBytes: number;
}

export const DEFAULT_SYNTAX_RULES_LIMITS: Readonly<SyntaxRulesLimits> = Object
  .freeze({
    maxExpansionDepth: 128,
    maxExpansionSteps: 65535,
    maxMacroDefinitions: 256,
    maxRepetitions: 510,
    maxOutputBytes: 0xffff,
  });

export type SyntaxRulesErrorCode = "syntax" | "capacity" | "phase";

export class SyntaxRulesError extends Error {
  constructor(
    readonly code: SyntaxRulesErrorCode,
    readonly at: Position,
    message: string,
  ) {
    super(
      `${at.source}:${at.line}:${at.column}: syntax-rules ${message}`,
    );
    this.name = "SyntaxRulesError";
  }
}

export interface SyntaxSymbol {
  readonly kind: "symbol";
  readonly name: string;
  readonly at: Position;
}

export interface SyntaxValue {
  readonly kind: "value";
  readonly value: Value;
  readonly at: Position;
}

export interface SyntaxString {
  readonly kind: "string";
  readonly bytes: Uint8Array;
  readonly at: Position;
}

export interface SyntaxList {
  readonly kind: "list";
  readonly items: readonly SyntaxDatum[];
  readonly tail: SyntaxDatum | null;
  readonly at: Position;
}

export interface SyntaxQuote {
  readonly kind: "quote";
  readonly datum: SyntaxDatum;
  readonly at: Position;
}

export type SyntaxDatum =
  | SyntaxSymbol
  | SyntaxValue
  | SyntaxString
  | SyntaxList
  | SyntaxQuote;

export interface ExpandedSource {
  readonly bytes: Uint8Array;
  readonly sourceName: string | SourceLocator;
  readonly changed: boolean;
  readonly macroDefinitions: number;
  readonly expansionSteps: number;
}

interface MacroDefinition {
  readonly name: string;
  readonly literals: ReadonlySet<string>;
  readonly clauses: readonly MacroClause[];
  readonly freeNames: ReadonlySet<string>;
  readonly at: Position;
}

interface MacroClause {
  readonly pattern: SyntaxList;
  readonly template: SyntaxDatum;
  readonly variables: ReadonlySet<string>;
}

type Binding = SyntaxDatum | readonly Binding[];
type Bindings = Map<string, Binding>;

/** Names introduced by one template expansion and the lexical aliases they use. */
interface TemplateContext {
  readonly scope: string;
  readonly reserved: Set<string>;
  readonly nextName: { value: number };
  readonly bindings: Map<string, string>;
}

/** Use-site lexical names and any alpha-renamed spelling emitted for them. */
type LexicalBindings = ReadonlyMap<string, string>;

function isBindingArray(value: Binding): value is readonly Binding[] {
  return Array.isArray(value);
}

interface ExpansionState {
  readonly limits: Readonly<SyntaxRulesLimits>;
  readonly macros: Map<string, MacroDefinition>;
  readonly freeIdentifiers: Set<string>;
  readonly reservedNames: Set<string>;
  definitions: number;
  steps: number;
  nextScope: number;
  nextUseName: number;
}

const CORE_IDENTIFIERS = new Set([
  "if",
  "begin",
  "lambda",
  "define",
  "set!",
  "let",
  "cond",
  "and",
  "or",
  "quote",
  "syntax-rules",
  "define-syntax",
  "+",
  "-",
  "*",
  "/",
  "=",
  "<",
  ">",
  "<=",
  ">=",
  "cons",
  "car",
  "cdr",
  "null?",
  "pair?",
  "list",
  "eq?",
  "not",
  "number?",
  "boolean?",
  "symbol?",
  "procedure?",
  "string?",
  "char?",
  "display",
  "write",
  "newline",
  "read-char",
  "eof-object?",
  "apply",
]);

function symbol(
  name: string,
  at: Position,
): SyntaxSymbol {
  return { kind: "symbol", name, at };
}

function list(
  items: readonly SyntaxDatum[],
  at: Position,
  tail: SyntaxDatum | null = null,
): SyntaxList {
  return { kind: "list", items, tail, at };
}

function isSymbol(
  datum: SyntaxDatum | undefined,
  name?: string,
): datum is SyntaxSymbol {
  return datum?.kind === "symbol" &&
    (name === undefined || datum.name === name);
}

function isList(datum: SyntaxDatum | undefined): datum is SyntaxList {
  return datum?.kind === "list";
}

function isProperList(datum: SyntaxDatum | undefined): datum is SyntaxList {
  return isList(datum) && datum.tail === null;
}

function isEllipsis(datum: SyntaxDatum | undefined): datum is SyntaxSymbol {
  return isSymbol(datum, "...");
}

function symbolText(
  reader: SourceReader,
  id: number,
): string {
  const table = reader.symbols.snapshot();
  const descriptor = id * 3;
  const offset = table.descriptors[descriptor]! |
    (table.descriptors[descriptor + 1]! << 8);
  const length = table.descriptors[descriptor + 2]!;
  return String.fromCharCode(...table.pool.subarray(offset, offset + length));
}

function stringBytes(
  reader: SourceReader,
  id: number,
): Uint8Array {
  const table = reader.strings.snapshot();
  const descriptor = id * 4;
  const offset = table.descriptors[descriptor]! |
    (table.descriptors[descriptor + 1]! << 8);
  const length = table.descriptors[descriptor + 2]! |
    (table.descriptors[descriptor + 3]! << 8);
  return table.pool.slice(offset, offset + length);
}

function parseDatums(
  reader: SourceReader,
): SyntaxDatum[] {
  const events = [...reader.events()];
  let index = 0;

  function next(at: Position, context: string): ReadEvent {
    const event = events[index++];
    if (event === undefined) {
      throw new SyntaxRulesError("syntax", at, `expected ${context}`);
    }
    return event;
  }

  function parseOne(): SyntaxDatum {
    const event = next(
      events.at(-1)?.at ?? {
        source: "<input>",
        offset: 0,
        line: 1,
        column: 1,
      },
      "a datum",
    );
    switch (event.kind) {
      case "symbol":
        return symbol(symbolText(reader, event.id), event.at);
      case "value":
        return { kind: "value", value: event.value, at: event.at };
      case "string":
        return {
          kind: "string",
          bytes: stringBytes(reader, event.id),
          at: event.at,
        };
      case "quote":
        return { kind: "quote", datum: parseOne(), at: event.at };
      case "open": {
        const items: SyntaxDatum[] = [];
        let tail: SyntaxDatum | null = null;
        for (;;) {
          const peek = events[index];
          if (peek === undefined) {
            throw new SyntaxRulesError(
              "syntax",
              event.at,
              "expected closing parenthesis",
            );
          }
          if (peek.kind === "close") {
            index++;
            return list(items, event.at, tail);
          }
          if (peek.kind === "dot") {
            index++;
            if (items.length === 0 || tail !== null) {
              throw new SyntaxRulesError(
                "syntax",
                peek.at,
                "dot requires preceding list data and one tail",
              );
            }
            tail = parseOne();
            const close = next(
              peek.at,
              "closing parenthesis after dotted tail",
            );
            if (close.kind !== "close") {
              throw new SyntaxRulesError(
                "syntax",
                close.at,
                "only a closing parenthesis may follow a dotted tail",
              );
            }
            return list(items, event.at, tail);
          }
          items.push(parseOne());
        }
      }
      case "close":
        throw new SyntaxRulesError(
          "syntax",
          event.at,
          "unexpected closing parenthesis",
        );
      case "dot":
        throw new SyntaxRulesError("syntax", event.at, "unexpected dot");
    }
  }

  const forms: SyntaxDatum[] = [];
  while (index < events.length) forms.push(parseOne());
  return forms;
}

function datumEqual(left: SyntaxDatum, right: SyntaxDatum): boolean {
  if (left.kind !== right.kind) return false;
  if (left.kind === "symbol" && right.kind === "symbol") {
    return left.name === right.name;
  }
  if (left.kind === "value" && right.kind === "value") {
    return left.value[0] === right.value[0] && left.value[1] === right.value[1];
  }
  if (left.kind === "string" && right.kind === "string") {
    return left.bytes.length === right.bytes.length &&
      left.bytes.every((byte, index) => byte === right.bytes[index]);
  }
  if (left.kind === "quote" && right.kind === "quote") {
    return datumEqual(left.datum, right.datum);
  }
  if (left.kind === "list" && right.kind === "list") {
    return left.items.length === right.items.length &&
      left.items.every((item, index) =>
        datumEqual(item, right.items[index]!)
      ) &&
      (left.tail === null
        ? right.tail === null
        : right.tail !== null && datumEqual(left.tail, right.tail));
  }
  return false;
}

function mergeBindings(
  target: Bindings,
  source: Bindings,
): boolean {
  for (const [name, value] of source) {
    const previous = target.get(name);
    if (previous !== undefined && !bindingEqual(previous, value)) return false;
    target.set(name, value);
  }
  return true;
}

function bindingEqual(left: Binding, right: Binding): boolean {
  if (isBindingArray(left) || isBindingArray(right)) {
    return isBindingArray(left) && isBindingArray(right) &&
      left.length === right.length &&
      left.every((item, index) => bindingEqual(item, right[index]!));
  }
  return datumEqual(left as SyntaxDatum, right as SyntaxDatum);
}

function repeatedBindings(
  repetitions: readonly Bindings[],
  repeatedNames: ReadonlySet<string> = new Set(),
): Bindings {
  const names = new Set<string>(repeatedNames);
  for (const repetition of repetitions) {
    for (const name of repetition.keys()) names.add(name);
  }
  const result: Bindings = new Map();
  for (const name of names) {
    const values: Binding[] = [];
    for (const repetition of repetitions) {
      const value = repetition.get(name);
      if (value === undefined) {
        // A variable in a repeated pattern must be bound by every repetition.
        return new Map();
      }
      values.push(value);
    }
    result.set(name, values);
  }
  return result;
}

function patternVariableNames(
  pattern: SyntaxDatum,
  variables: ReadonlySet<string>,
): Set<string> {
  const names = new Set<string>();
  function visit(node: SyntaxDatum): void {
    if (node.kind === "symbol") {
      if (variables.has(node.name)) names.add(node.name);
      return;
    }
    if (node.kind === "list") {
      for (const item of node.items) visit(item);
      if (node.tail !== null) visit(node.tail);
    } else if (node.kind === "quote") {
      visit(node.datum);
    }
  }
  visit(pattern);
  return names;
}

function matchNode(
  pattern: SyntaxDatum,
  input: SyntaxDatum,
  literals: ReadonlySet<string>,
  variables: ReadonlySet<string>,
  limits: Readonly<SyntaxRulesLimits>,
): Bindings | null {
  if (pattern.kind === "symbol") {
    if (pattern.name === "_") return new Map();
    if (pattern.name === "...") return null;
    if (literals.has(pattern.name)) {
      return isSymbol(input, pattern.name) ? new Map() : null;
    }
    if (!variables.has(pattern.name)) return null;
    const result: Bindings = new Map();
    result.set(pattern.name, input);
    return result;
  }
  if (pattern.kind !== "list") {
    return datumEqual(pattern, input) ? new Map() : null;
  }
  if (input.kind !== "list") return null;
  const matched = matchSequence(
    pattern.items,
    input.items,
    literals,
    variables,
    limits,
  );
  if (matched === null) return null;
  if (pattern.tail === null) return input.tail === null ? matched : null;
  if (input.tail === null) return null;
  const tail = matchNode(
    pattern.tail,
    input.tail,
    literals,
    variables,
    limits,
  );
  if (tail === null || !mergeBindings(matched, tail)) return null;
  return matched;
}

function matchSequence(
  patterns: readonly SyntaxDatum[],
  inputs: readonly SyntaxDatum[],
  literals: ReadonlySet<string>,
  variables: ReadonlySet<string>,
  limits: Readonly<SyntaxRulesLimits>,
): Bindings | null {
  function matchAt(patternIndex: number, inputIndex: number): Bindings | null {
    if (patternIndex === patterns.length) {
      return inputIndex === inputs.length ? new Map() : null;
    }
    const pattern = patterns[patternIndex]!;
    const repeated = isEllipsis(patterns[patternIndex + 1]);
    if (repeated) {
      const remaining = inputs.length - inputIndex;
      if (remaining > limits.maxRepetitions) {
        throw new SyntaxRulesError(
          "capacity",
          pattern.at,
          `ellipsis repetition exceeds ${limits.maxRepetitions} values`,
        );
      }
      // Prefer the longest match; a later literal or fixed pattern still gets
      // a chance through the bounded backtracking loop.
      for (let count = remaining; count >= 0; count--) {
        const repetitions: Bindings[] = [];
        let matched = true;
        for (let offset = 0; offset < count; offset++) {
          const repetition = matchNode(
            pattern,
            inputs[inputIndex + offset]!,
            literals,
            variables,
            limits,
          );
          if (repetition === null) {
            matched = false;
            break;
          }
          repetitions.push(repetition);
        }
        if (!matched) continue;
        const repeated = repeatedBindings(
          repetitions,
          patternVariableNames(pattern, variables),
        );
        if (
          repetitions.length > 0 &&
          patternVariableNames(pattern, variables).size > 0 &&
          repeated.size === 0
        ) continue;
        const rest = matchAt(patternIndex + 2, inputIndex + count);
        if (rest !== null && mergeBindings(repeated, rest)) return repeated;
      }
      return null;
    }
    if (inputIndex >= inputs.length) return null;
    const one = matchNode(
      pattern,
      inputs[inputIndex]!,
      literals,
      variables,
      limits,
    );
    if (one === null) return null;
    const rest = matchAt(patternIndex + 1, inputIndex + 1);
    if (rest === null || !mergeBindings(one, rest)) return null;
    return one;
  }
  return matchAt(0, 0);
}

function bindingAtPath(
  binding: Binding,
  path: readonly number[],
  at: Position,
): Binding {
  let current = binding;
  for (const index of path) {
    if (!Array.isArray(current) || current[index] === undefined) {
      throw new SyntaxRulesError(
        "syntax",
        at,
        "template ellipsis depth does not match its pattern",
      );
    }
    current = current[index]!;
  }
  return current;
}

function templateRepeatCount(
  datum: SyntaxDatum,
  bindings: Bindings,
  path: readonly number[],
  limits: Readonly<SyntaxRulesLimits>,
): number | null {
  const counts: number[] = [];
  function visit(node: SyntaxDatum): void {
    if (node.kind === "symbol") {
      const binding = bindings.get(node.name);
      if (binding !== undefined) {
        const selected = bindingAtPath(binding, path, node.at);
        if (Array.isArray(selected)) counts.push(selected.length);
      }
      return;
    }
    if (node.kind === "list") {
      for (const item of node.items) visit(item);
      if (node.tail !== null) visit(node.tail);
    } else if (node.kind === "quote") visit(node.datum);
  }
  visit(datum);
  if (counts.length === 0) return null;
  const count = counts[0]!;
  if (count > limits.maxRepetitions) {
    throw new SyntaxRulesError(
      "capacity",
      datum.at,
      `ellipsis expansion exceeds ${limits.maxRepetitions} values`,
    );
  }
  if (counts.some((value) => value !== count)) {
    throw new SyntaxRulesError(
      "syntax",
      datum.at,
      "template variables under one ellipsis have different lengths",
    );
  }
  return count;
}

function childTemplateContext(parent: TemplateContext): TemplateContext {
  return {
    scope: parent.scope,
    reserved: parent.reserved,
    nextName: parent.nextName,
    bindings: new Map(parent.bindings),
  };
}

function freshBinding(
  context: TemplateContext,
): string {
  let generated: string;
  do {
    generated = `${context.scope}_${context.nextName.value.toString(36)}`;
    context.nextName.value++;
  } while (context.reserved.has(generated));
  context.reserved.add(generated);
  return generated;
}

function expandQuotedTemplate(
  datum: SyntaxDatum,
  bindings: Bindings,
  path: readonly number[],
): SyntaxDatum {
  if (datum.kind === "symbol") {
    const binding = bindings.get(datum.name);
    if (binding === undefined) return datum;
    const selected = bindingAtPath(binding, path, datum.at);
    if (isBindingArray(selected)) return datum;
    return selected as SyntaxDatum;
  }
  if (datum.kind === "quote") {
    return {
      kind: "quote",
      datum: expandQuotedTemplate(datum.datum, bindings, path),
      at: datum.at,
    };
  }
  if (datum.kind !== "list") return datum;
  return list(
    datum.items.map((item) => expandQuotedTemplate(item, bindings, path)),
    datum.at,
    datum.tail === null
      ? null
      : expandQuotedTemplate(datum.tail, bindings, path),
  );
}

function expandTemplateBinding(
  datum: SyntaxDatum,
  bindings: Bindings,
  literals: ReadonlySet<string>,
  state: ExpansionState,
  context: TemplateContext,
  path: readonly number[],
): { readonly datum: SyntaxDatum; readonly context: TemplateContext } {
  if (!isProperList(datum) || datum.items.length !== 2) {
    return {
      datum: expandTemplate(datum, bindings, literals, state, context, path),
      context,
    };
  }
  const name = datum.items[0]!;
  const value = datum.items[1]!;
  const child = childTemplateContext(context);
  let expandedName: SyntaxDatum;
  if (isSymbol(name) && !bindings.has(name.name)) {
    const generated = freshBinding(context);
    child.bindings.set(name.name, generated);
    expandedName = symbol(generated, name.at);
  } else {
    expandedName = expandTemplate(
      name,
      bindings,
      literals,
      state,
      context,
      path,
    );
  }
  const expandedValue = expandTemplate(
    value,
    bindings,
    literals,
    state,
    context,
    path,
  );
  return {
    datum: list([expandedName, expandedValue], datum.at, datum.tail),
    context: child,
  };
}

function expandTemplateFormals(
  datum: SyntaxDatum,
  bindings: Bindings,
  literals: ReadonlySet<string>,
  state: ExpansionState,
  context: TemplateContext,
  path: readonly number[],
): { readonly datum: SyntaxDatum; readonly context: TemplateContext } {
  const child = childTemplateContext(context);
  const introduce = (formal: SyntaxDatum): SyntaxDatum => {
    if (!isSymbol(formal) || bindings.has(formal.name)) {
      return expandTemplate(formal, bindings, literals, state, context, path);
    }
    const generated = freshBinding(context);
    child.bindings.set(formal.name, generated);
    return symbol(generated, formal.at);
  };
  if (!isList(datum)) return { datum: introduce(datum), context: child };
  return {
    datum: list(
      datum.items.map(introduce),
      datum.at,
      datum.tail === null ? null : introduce(datum.tail),
    ),
    context: child,
  };
}

function expandTemplateTail(
  datum: SyntaxDatum,
  bindings: Bindings,
  literals: ReadonlySet<string>,
  state: ExpansionState,
  context: TemplateContext,
  path: readonly number[],
): SyntaxDatum {
  if (datum.kind === "symbol") {
    const binding = bindings.get(datum.name);
    if (binding !== undefined) {
      const selected = bindingAtPath(binding, path, datum.at);
      if (isBindingArray(selected)) {
        return list(
          selected.map((item) => item as SyntaxDatum),
          datum.at,
        );
      }
    }
  }
  return expandTemplate(datum, bindings, literals, state, context, path);
}

function expandTemplate(
  datum: SyntaxDatum,
  bindings: Bindings,
  literals: ReadonlySet<string>,
  state: ExpansionState,
  context: TemplateContext,
  path: readonly number[] = [],
): SyntaxDatum {
  if (datum.kind === "symbol") {
    if (datum.name === "...") {
      throw new SyntaxRulesError(
        "syntax",
        datum.at,
        "ellipsis has no template body",
      );
    }
    const binding = bindings.get(datum.name);
    if (binding !== undefined) {
      const selected = bindingAtPath(binding, path, datum.at);
      if (isBindingArray(selected)) {
        throw new SyntaxRulesError(
          "syntax",
          datum.at,
          "a repeated pattern variable needs an ellipsis in the template",
        );
      }
      return selected as SyntaxDatum;
    }
    const introduced = context.bindings.get(datum.name);
    if (introduced !== undefined) return symbol(introduced, datum.at);
    // A free template identifier is a definition-site reference. Preserve its
    // spelling; only identifiers in binding positions receive fresh names.
    return datum;
  }
  if (datum.kind === "value" || datum.kind === "string") return datum;
  if (datum.kind === "quote") {
    return {
      kind: "quote",
      datum: expandQuotedTemplate(datum.datum, bindings, path),
      at: datum.at,
    };
  }
  const head = datum.items[0];
  if (isSymbol(head, "let") && datum.items.length >= 3) {
    const rawBindings = datum.items[1]!;
    const outer = context;
    const bodyContext = childTemplateContext(outer);
    const expandedBindings: SyntaxDatum[] = [];
    if (isList(rawBindings)) {
      for (let index = 0; index < rawBindings.items.length; index++) {
        const item = rawBindings.items[index]!;
        if (isEllipsis(rawBindings.items[index + 1])) {
          const count = templateRepeatCount(item, bindings, path, state.limits);
          if (count === null) {
            throw new SyntaxRulesError(
              "syntax",
              item.at,
              "ellipsis has no pattern variable to repeat",
            );
          }
          for (let repetition = 0; repetition < count; repetition++) {
            const expanded = expandTemplateBinding(
              item,
              bindings,
              literals,
              state,
              bodyContext,
              [...path, repetition],
            );
            expandedBindings.push(expanded.datum);
            for (const [name, value] of expanded.context.bindings) {
              bodyContext.bindings.set(name, value);
            }
          }
          index++;
        } else {
          const expanded = expandTemplateBinding(
            item,
            bindings,
            literals,
            state,
            bodyContext,
            path,
          );
          expandedBindings.push(expanded.datum);
          for (const [name, value] of expanded.context.bindings) {
            bodyContext.bindings.set(name, value);
          }
        }
      }
    }
    const body = datum.items.slice(2).map((item) =>
      expandTemplate(item, bindings, literals, state, bodyContext, path)
    );
    return list(
      [
        head,
        list(
          expandedBindings,
          rawBindings.at,
          rawBindings.kind === "list" ? rawBindings.tail : null,
        ),
        ...body,
      ],
      datum.at,
      datum.tail === null
        ? null
        : expandTemplate(datum.tail, bindings, literals, state, context, path),
    );
  }
  if (isSymbol(head, "lambda") && datum.items.length >= 3) {
    const formals = expandTemplateFormals(
      datum.items[1]!,
      bindings,
      literals,
      state,
      context,
      path,
    );
    const body = datum.items.slice(2).map((item) =>
      expandTemplate(item, bindings, literals, state, formals.context, path)
    );
    return list([head, formals.datum, ...body], datum.at, datum.tail);
  }
  if (isSymbol(head, "define") && datum.items.length >= 3) {
    const target = datum.items[1]!;
    if (isList(target) && target.items.length > 0) {
      const formals = expandTemplateFormals(
        list(target.items.slice(1), target.at, target.tail),
        bindings,
        literals,
        state,
        context,
        path,
      );
      const defined = expandTemplate(
        target.items[0]!,
        bindings,
        literals,
        state,
        context,
        path,
      );
      const body = datum.items.slice(2).map((item) =>
        expandTemplate(item, bindings, literals, state, formals.context, path)
      );
      return list(
        [
          head,
          list(
            [defined, ...(formals.datum as SyntaxList).items],
            target.at,
            formals.datum.kind === "list" ? formals.datum.tail : null,
          ),
          ...body,
        ],
        datum.at,
        datum.tail,
      );
    }
    return list(
      [
        head,
        expandTemplate(target, bindings, literals, state, context, path),
        ...datum.items.slice(2).map((item) =>
          expandTemplate(item, bindings, literals, state, context, path)
        ),
      ],
      datum.at,
      datum.tail,
    );
  }
  const items: SyntaxDatum[] = [];
  for (let index = 0; index < datum.items.length; index++) {
    const item = datum.items[index]!;
    if (isEllipsis(datum.items[index + 1])) {
      const count = templateRepeatCount(item, bindings, path, state.limits);
      if (count === null) {
        throw new SyntaxRulesError(
          "syntax",
          item.at,
          "ellipsis has no pattern variable to repeat",
        );
      }
      for (let repetition = 0; repetition < count; repetition++) {
        items.push(
          expandTemplate(
            item,
            bindings,
            literals,
            state,
            context,
            [...path, repetition],
          ),
        );
      }
      index++;
    } else {
      items.push(
        expandTemplate(item, bindings, literals, state, context, path),
      );
    }
  }
  const tail = datum.tail === null ? null : expandTemplateTail(
    datum.tail,
    bindings,
    literals,
    state,
    context,
    path,
  );
  return list(items, datum.at, tail);
}

function validatePatternNode(
  datum: SyntaxDatum,
  literals: ReadonlySet<string>,
  variables: Set<string>,
  at: Position,
): void {
  if (datum.kind === "symbol") {
    if (
      datum.name === "..." || datum.name === "_" || literals.has(datum.name)
    ) return;
    if (variables.has(datum.name)) {
      throw new SyntaxRulesError(
        "syntax",
        datum.at,
        `pattern variable ${JSON.stringify(datum.name)} occurs more than once`,
      );
    }
    variables.add(datum.name);
    return;
  }
  if (datum.kind !== "list") {
    if (datum.kind === "quote") {
      validatePatternNode(datum.datum, literals, variables, at);
    }
    return;
  }
  for (let index = 0; index < datum.items.length; index++) {
    if (isEllipsis(datum.items[index])) {
      if (index === 0 || isEllipsis(datum.items[index - 1])) {
        throw new SyntaxRulesError(
          "syntax",
          datum.items[index]!.at,
          "ellipsis needs a preceding pattern",
        );
      }
      continue;
    }
    validatePatternNode(datum.items[index]!, literals, variables, at);
  }
  if (datum.tail !== null) {
    validatePatternNode(datum.tail, literals, variables, at);
  }
}

function validateTemplateNode(
  datum: SyntaxDatum,
): void {
  if (datum.kind === "quote") {
    validateTemplateNode(datum.datum);
    return;
  }
  if (datum.kind !== "list") return;
  for (let index = 0; index < datum.items.length; index++) {
    if (isEllipsis(datum.items[index])) {
      if (index === 0 || isEllipsis(datum.items[index - 1])) {
        throw new SyntaxRulesError(
          "syntax",
          datum.items[index]!.at,
          "ellipsis needs a preceding template",
        );
      }
      continue;
    }
    validateTemplateNode(datum.items[index]!);
  }
  if (datum.tail !== null) validateTemplateNode(datum.tail);
}

function templateFreeNames(
  datum: SyntaxDatum,
  variables: ReadonlySet<string>,
  literals: ReadonlySet<string>,
): Set<string> {
  const names = new Set<string>();
  function visit(node: SyntaxDatum, bound: ReadonlySet<string>): void {
    if (node.kind === "symbol") {
      if (
        node.name !== "..." && node.name !== "_" &&
        !variables.has(node.name) && !literals.has(node.name) &&
        !CORE_IDENTIFIERS.has(node.name) && !bound.has(node.name)
      ) {
        names.add(node.name);
      }
      return;
    }
    if (node.kind === "quote") return;
    if (node.kind !== "list") return;
    const head = node.items[0];
    const headName = head?.kind === "symbol" ? head.name : undefined;
    if (headName === "let" && node.items.length >= 3) {
      const rawBindings = node.items[1]!;
      const bodyStart = headName === "let" && rawBindings.kind === "symbol"
        ? 3
        : 2;
      const bodyBound = new Set(bound);
      if (rawBindings.kind === "symbol") bodyBound.add(rawBindings.name);
      const bindingList = rawBindings.kind === "symbol"
        ? node.items[2]!
        : rawBindings;
      if (bindingList.kind === "list") {
        for (const binding of bindingList.items) {
          if (binding.kind !== "list" || binding.items.length < 2) {
            visit(binding, bound);
            continue;
          }
          const name = binding.items[0];
          if (name.kind === "symbol") bodyBound.add(name.name);
          for (const value of binding.items.slice(1)) visit(value, bound);
        }
      }
      for (const body of node.items.slice(bodyStart)) visit(body, bodyBound);
      return;
    }
    if (headName === "lambda" && node.items.length >= 3) {
      const bodyBound = new Set(bound);
      for (const name of formalNames(node.items[1]!)) bodyBound.add(name);
      for (const body of node.items.slice(2)) visit(body, bodyBound);
      return;
    }
    if (headName === "define" && node.items.length >= 3) {
      const target = node.items[1]!;
      if (target.kind === "list" && target.items.length > 0) {
        const bodyBound = new Set(bound);
        for (
          const name of formalNames(
            list(target.items.slice(1), target.at, target.tail),
          )
        ) {
          bodyBound.add(name);
        }
        for (const body of node.items.slice(2)) visit(body, bodyBound);
      } else {
        for (const body of node.items.slice(2)) visit(body, bound);
      }
      return;
    }
    if (headName === "set!" && node.items.length >= 3) {
      for (const value of node.items.slice(2)) visit(value, bound);
      return;
    }
    for (const item of node.items) visit(item, bound);
    if (node.tail !== null) visit(node.tail, bound);
  }
  visit(datum, new Set());
  return names;
}

function parseMacro(
  form: SyntaxList,
): MacroDefinition {
  if (
    form.tail !== null || form.items.length !== 3 ||
    !isSymbol(form.items[1]) || !isList(form.items[2])
  ) {
    throw new SyntaxRulesError(
      "syntax",
      form.at,
      "define-syntax requires a name and syntax-rules transformer",
    );
  }
  const name = form.items[1].name;
  const transformer = form.items[2];
  if (
    transformer.tail !== null || transformer.items.length < 3 ||
    !isSymbol(transformer.items[0], "syntax-rules") ||
    !isProperList(transformer.items[1])
  ) {
    throw new SyntaxRulesError(
      "syntax",
      transformer.at,
      "define-syntax requires a syntax-rules transformer",
    );
  }
  const literalNames = new Set<string>();
  for (const literal of transformer.items[1].items) {
    if (!isSymbol(literal) || literal.name === "...") {
      throw new SyntaxRulesError(
        "syntax",
        literal.at,
        "syntax-rules literals must be identifiers",
      );
    }
    if (literalNames.has(literal.name)) {
      throw new SyntaxRulesError(
        "syntax",
        literal.at,
        `duplicate syntax-rules literal ${JSON.stringify(literal.name)}`,
      );
    }
    literalNames.add(literal.name);
  }
  const clauses: MacroClause[] = [];
  for (const clauseDatum of transformer.items.slice(2)) {
    if (!isProperList(clauseDatum) || clauseDatum.items.length !== 2) {
      throw new SyntaxRulesError(
        "syntax",
        clauseDatum.at,
        "each syntax-rules clause needs one pattern and one template",
      );
    }
    const pattern = clauseDatum.items[0]!;
    if (!isList(pattern) || pattern.items.length === 0) {
      throw new SyntaxRulesError(
        "syntax",
        pattern.at,
        "a syntax-rules pattern must be a nonempty list",
      );
    }
    const patternHead = pattern.items[0]!;
    if (
      !isSymbol(patternHead) ||
      (patternHead.name !== name && patternHead.name !== "_")
    ) {
      throw new SyntaxRulesError(
        "syntax",
        patternHead.at,
        `pattern must begin with ${JSON.stringify(name)} or _`,
      );
    }
    const variables = new Set<string>();
    for (const item of pattern.items.slice(1)) {
      validatePatternNode(item, literalNames, variables, pattern.at);
    }
    if (pattern.tail !== null) {
      validatePatternNode(pattern.tail, literalNames, variables, pattern.at);
    }
    const template = clauseDatum.items[1]!;
    validateTemplateNode(template);
    clauses.push({ pattern, template, variables });
  }
  if (clauses.length === 0) {
    throw new SyntaxRulesError(
      "syntax",
      transformer.at,
      "syntax-rules needs a clause",
    );
  }
  const freeNames = new Set<string>();
  for (const clause of clauses) {
    for (
      const name of templateFreeNames(
        clause.template,
        clause.variables,
        literalNames,
      )
    ) {
      freeNames.add(name);
    }
  }
  return { name, literals: literalNames, clauses, freeNames, at: form.at };
}

function matchFixedPrefix(
  patterns: readonly SyntaxDatum[],
  inputs: readonly SyntaxDatum[],
  literals: ReadonlySet<string>,
  variables: ReadonlySet<string>,
  limits: Readonly<SyntaxRulesLimits>,
): Bindings | null {
  if (patterns.length !== inputs.length) return null;
  const bindings: Bindings = new Map();
  for (let index = 0; index < patterns.length; index++) {
    const matched = matchNode(
      patterns[index]!,
      inputs[index]!,
      literals,
      variables,
      limits,
    );
    if (matched === null || !mergeBindings(bindings, matched)) return null;
  }
  return bindings;
}

function reserveSymbolNames(
  datum: SyntaxDatum,
  reserved: Set<string>,
): void {
  if (datum.kind === "symbol") {
    reserved.add(datum.name);
  } else if (datum.kind === "list") {
    for (const item of datum.items) reserveSymbolNames(item, reserved);
    if (datum.tail !== null) reserveSymbolNames(datum.tail, reserved);
  } else if (datum.kind === "quote") {
    reserveSymbolNames(datum.datum, reserved);
  }
}

function expandMacro(
  macro: MacroDefinition,
  input: SyntaxList,
  state: ExpansionState,
): SyntaxDatum {
  for (const clause of macro.clauses) {
    const pattern = clause.pattern;
    if (
      input.items.length === 0 ||
      pattern.items.length === 0 ||
      !isSymbol(input.items[0], macro.name) &&
        !isSymbol(pattern.items[0], "_")
    ) continue;
    if (pattern.tail === null && input.tail !== null) continue;
    let bindings: Bindings | null;
    if (
      pattern.tail !== null &&
      input.tail === null &&
      isSymbol(pattern.tail) &&
      clause.variables.has(pattern.tail.name) &&
      !pattern.items.slice(1).some(isEllipsis)
    ) {
      const prefix = pattern.items.slice(1);
      const actual = input.items.slice(1);
      if (actual.length < prefix.length) continue;
      bindings = matchFixedPrefix(
        prefix,
        actual.slice(0, prefix.length),
        macro.literals,
        clause.variables,
        state.limits,
      );
      if (bindings !== null) {
        bindings.set(
          pattern.tail.name,
          actual.slice(prefix.length),
        );
      }
    } else {
      if (pattern.tail !== null && input.tail === null) continue;
      bindings = matchSequence(
        pattern.items.slice(1),
        input.items.slice(1),
        macro.literals,
        clause.variables,
        state.limits,
      );
    }
    if (bindings === null) continue;
    if (pattern.tail !== null && input.tail !== null) {
      const tail = matchNode(
        pattern.tail,
        input.tail,
        macro.literals,
        clause.variables,
        state.limits,
      );
      if (tail === null || !mergeBindings(bindings, tail)) continue;
    }
    const scope = `$m${state.nextScope.toString(36)}`;
    state.nextScope++;
    // Transformer keywords are definition-site bindings. Preserve the names
    // of all macros already visible so nested and recursive rewrites remain
    // macro calls instead of becoming fresh ordinary identifiers.
    const templateLiterals = new Set([
      ...macro.literals,
      ...state.macros.keys(),
    ]);
    const reserved = new Set<string>();
    reserveSymbolNames(input, reserved);
    return expandTemplate(
      clause.template,
      bindings,
      templateLiterals,
      state,
      {
        scope,
        reserved,
        nextName: { value: 0 },
        bindings: new Map(),
      },
    );
  }
  throw new SyntaxRulesError(
    "syntax",
    input.at,
    `no syntax-rules pattern matches ${JSON.stringify(macro.name)}`,
  );
}

function freshUseBinding(state: ExpansionState): string {
  let name: string;
  do {
    name = `$u${state.nextUseName.toString(36)}`;
    state.nextUseName++;
  } while (state.reservedNames.has(name));
  state.reservedNames.add(name);
  return name;
}

function useBindingName(name: string, state: ExpansionState): string {
  return state.freeIdentifiers.has(name) ? freshUseBinding(state) : name;
}

function renameUseFormals(
  formals: SyntaxDatum,
  state: ExpansionState,
  bound: Map<string, string>,
): SyntaxDatum {
  const rename = (formal: SyntaxDatum): SyntaxDatum => {
    if (formal.kind !== "symbol" || formal.name === "...") return formal;
    const emitted = useBindingName(formal.name, state);
    bound.set(formal.name, emitted);
    return emitted === formal.name ? formal : symbol(emitted, formal.at);
  };
  if (formals.kind !== "list") return rename(formals);
  return list(
    formals.items.map(rename),
    formals.at,
    formals.tail === null ? null : rename(formals.tail),
  );
}

function renameUseBindingList(
  bindingList: SyntaxDatum,
  state: ExpansionState,
  bound: Map<string, string>,
): SyntaxDatum {
  if (bindingList.kind !== "list") return bindingList;
  const items = bindingList.items.map((binding) => {
    if (binding.kind !== "list" || binding.items.length === 0) return binding;
    const name = binding.items[0];
    if (name.kind !== "symbol") return binding;
    const emitted = useBindingName(name.name, state);
    bound.set(name.name, emitted);
    return list(
      [
        emitted === name.name ? name : symbol(emitted, name.at),
        ...binding.items.slice(1),
      ],
      binding.at,
      binding.tail,
    );
  });
  return list(items, bindingList.at, bindingList.tail);
}

function expandForm(
  datum: SyntaxDatum,
  state: ExpansionState,
  depth = 0,
  bound: LexicalBindings = new Map(),
): SyntaxDatum {
  if (depth > state.limits.maxExpansionDepth) {
    throw new SyntaxRulesError(
      "capacity",
      datum.at,
      `macro expansion exceeds depth ${state.limits.maxExpansionDepth}`,
    );
  }
  if (datum.kind === "quote") return datum;
  if (datum.kind === "symbol") {
    const emitted = bound.get(datum.name);
    return emitted === undefined ? datum : symbol(emitted, datum.at);
  }
  if (datum.kind !== "list") return datum;
  const head = datum.items[0];
  const headName = head?.kind === "symbol" ? head.name : undefined;
  if (headName === "quote") return datum;
  if (headName === "define-syntax") {
    throw new SyntaxRulesError(
      "phase",
      datum.at,
      "define-syntax is only valid at top level or in a top-level begin",
    );
  }
  if (headName !== undefined) {
    const macro = bound.has(headName) ? undefined : state.macros.get(headName);
    if (macro !== undefined) {
      state.steps++;
      if (state.steps > state.limits.maxExpansionSteps) {
        throw new SyntaxRulesError(
          "capacity",
          datum.at,
          `macro expansion exceeds ${state.limits.maxExpansionSteps} rewrites`,
        );
      }
      const macroBound = new Map(bound);
      // Template free references resolve in the macro's definition context;
      // do not apply a use-site alpha-renaming map to those identifiers.
      for (const name of macro.freeNames) macroBound.delete(name);
      return expandForm(
        expandMacro(macro, datum, state),
        state,
        depth + 1,
        macroBound,
      );
    }
  }

  if (isSymbol(head, "lambda") && datum.items.length >= 3) {
    const formals = datum.items[1]!;
    const bodyBound = new Map(bound);
    const emittedFormals = renameUseFormals(formals, state, bodyBound);
    return list(
      [
        head,
        emittedFormals,
        ...datum.items.slice(2).map((item) =>
          expandForm(item, state, depth, bodyBound)
        ),
      ],
      datum.at,
      datum.tail === null ? null : expandForm(datum.tail, state, depth, bound),
    );
  }

  if (isSymbol(head, "let") && datum.items.length >= 3) {
    const rawBindings = datum.items[1]!;
    if (isSymbol(rawBindings)) {
      // Named let binds its procedure name in the body as well as the
      // binding variables. The initializer expressions remain outer-scoped.
      const bindingList = datum.items[2]!;
      const bodyBound = new Map(bound);
      const emittedName = useBindingName(rawBindings.name, state);
      bodyBound.set(rawBindings.name, emittedName);
      const emittedBindingList = renameUseBindingList(
        bindingList,
        state,
        bodyBound,
      );
      return list(
        [
          head,
          emittedName === rawBindings.name
            ? rawBindings
            : symbol(emittedName, rawBindings.at),
          expandLetBindings(emittedBindingList, state, depth, bound),
          ...datum.items.slice(3).map((item) =>
            expandForm(item, state, depth, bodyBound)
          ),
        ],
        datum.at,
        datum.tail === null
          ? null
          : expandForm(datum.tail, state, depth, bound),
      );
    }
    const bodyBound = new Map(bound);
    const emittedBindingList = renameUseBindingList(
      rawBindings,
      state,
      bodyBound,
    );
    return list(
      [
        head,
        expandLetBindings(emittedBindingList, state, depth, bound),
        ...datum.items.slice(2).map((item) =>
          expandForm(item, state, depth, bodyBound)
        ),
      ],
      datum.at,
      datum.tail === null ? null : expandForm(datum.tail, state, depth, bound),
    );
  }

  if (isSymbol(head, "define") && datum.items.length >= 3) {
    const target = datum.items[1]!;
    if (isList(target) && target.items.length > 0) {
      const formals = list(target.items.slice(1), target.at, target.tail);
      const bodyBound = new Map(bound);
      const emittedFormals = renameUseFormals(formals, state, bodyBound);
      return list(
        [
          head,
          list(
            [
              target.items[0]!,
              ...(emittedFormals.kind === "list" ? emittedFormals.items : []),
            ],
            target.at,
            emittedFormals.kind === "list" ? emittedFormals.tail : null,
          ),
          ...datum.items.slice(2).map((item) =>
            expandForm(item, state, depth, bodyBound)
          ),
        ],
        datum.at,
        datum.tail === null
          ? null
          : expandForm(datum.tail, state, depth, bound),
      );
    }
    return list(
      [
        head,
        target,
        ...datum.items.slice(2).map((item) =>
          expandForm(item, state, depth, bound)
        ),
      ],
      datum.at,
      datum.tail === null ? null : expandForm(datum.tail, state, depth, bound),
    );
  }

  if (isSymbol(head, "set!") && datum.items.length >= 3) {
    const target = datum.items[1]!;
    const emittedTarget = target.kind === "symbol"
      ? bound.get(target.name) === undefined
        ? target
        : symbol(bound.get(target.name)!, target.at)
      : target;
    return list(
      [
        head,
        emittedTarget,
        ...datum.items.slice(2).map((item) =>
          expandForm(item, state, depth, bound)
        ),
      ],
      datum.at,
      datum.tail === null ? null : expandForm(datum.tail, state, depth, bound),
    );
  }

  const items = datum.items.map((item) =>
    expandForm(item, state, depth, bound)
  );
  const tail = datum.tail === null
    ? null
    : expandForm(datum.tail, state, depth, bound);
  return list(items, datum.at, tail);
}

function formalNames(formals: SyntaxDatum): Set<string> {
  const names = new Set<string>();
  function visit(node: SyntaxDatum): void {
    if (node.kind === "symbol") {
      if (node.name !== "...") names.add(node.name);
      return;
    }
    if (node.kind === "list") {
      for (const item of node.items) visit(item);
      if (node.tail !== null) visit(node.tail);
    }
  }
  visit(formals);
  return names;
}

function expandLetBindings(
  datum: SyntaxDatum,
  state: ExpansionState,
  depth: number,
  bound: LexicalBindings,
): SyntaxDatum {
  if (!isList(datum)) return expandForm(datum, state, depth, bound);
  const items = datum.items.map((binding) => {
    if (!isList(binding) || binding.items.length < 2) {
      return expandForm(binding, state, depth, bound);
    }
    return list(
      [
        binding.items[0]!,
        ...binding.items.slice(1).map((item) =>
          expandForm(item, state, depth, bound)
        ),
      ],
      binding.at,
      binding.tail === null
        ? null
        : expandForm(binding.tail, state, depth, bound),
    );
  });
  return list(
    items,
    datum.at,
    datum.tail === null ? null : expandForm(datum.tail, state, depth, bound),
  );
}

function processTopForms(
  forms: readonly SyntaxDatum[],
  state: ExpansionState,
): SyntaxDatum[] {
  const output: SyntaxDatum[] = [];
  for (const form of forms) {
    if (isList(form) && isSymbol(form.items[0], "define-syntax")) {
      const macro = parseMacro(form);
      if (state.macros.has(macro.name)) {
        throw new SyntaxRulesError(
          "syntax",
          form.at,
          `macro ${JSON.stringify(macro.name)} is defined more than once`,
        );
      }
      state.definitions++;
      if (state.definitions > state.limits.maxMacroDefinitions) {
        throw new SyntaxRulesError(
          "capacity",
          form.at,
          `macro definitions exceed ${state.limits.maxMacroDefinitions}`,
        );
      }
      state.macros.set(macro.name, macro);
      for (const name of macro.freeNames) state.freeIdentifiers.add(name);
      continue;
    }
    if (isList(form) && isSymbol(form.items[0], "begin")) {
      // Handle compile-time definitions before descending through the runtime
      // sequence; expandForm intentionally rejects nested define-syntax forms.
      const inner = processTopForms(form.items.slice(1), state);
      output.push(list([form.items[0]!, ...inner], form.at, form.tail));
      continue;
    }
    const expanded = expandForm(form, state);
    if (isList(expanded) && isSymbol(expanded.items[0], "begin")) {
      // A top-level begin is a sequencing boundary in M10. Process its
      // compile-time definitions in order while retaining runtime forms.
      const inner = processTopForms(expanded.items.slice(1), state);
      output.push(
        list([expanded.items[0]!, ...inner], expanded.at, expanded.tail),
      );
    } else {
      output.push(expanded);
    }
  }
  return output;
}

function checkLimits(limits: SyntaxRulesLimits): Readonly<SyntaxRulesLimits> {
  for (const [name, value] of Object.entries(limits)) {
    if (!Number.isInteger(value) || value < 1 || value > 0xffff) {
      throw new RangeError(`Invalid syntax-rules ${name} limit`);
    }
  }
  return Object.freeze({ ...limits });
}

function hex(byte: number): string {
  return byte.toString(16).toUpperCase().padStart(2, "0");
}

function valueText(value: Value): string {
  if (value[0] !== 0) return formatNumber(value);
  if (value[1] === 0xfe00) return "#f";
  if (value[1] === 0xfe01) return "#t";
  if ((value[1] & 0xff00) === 0xff00) {
    const character = value[1] & 0xff;
    if (character === 32) return "#\\space";
    if (character === 10) return "#\\newline";
    if (
      character >= 33 && character <= 126 &&
      ![34, 39, 40, 41, 59].includes(character)
    ) return `#\\${String.fromCharCode(character)}`;
    return `#\\x${hex(character)};`;
  }
  return formatNumber(value);
}

function stringText(bytes: Uint8Array): string {
  let result = '"';
  for (const byte of bytes) {
    if (byte === 34) result += '\\"';
    else if (byte === 92) result += "\\\\";
    else if (byte === 10) result += "\\n";
    else if (byte === 13) result += "\\r";
    else if (byte === 9) result += "\\t";
    else if (byte < 32 || byte === 127 || byte > 126) {
      result += `\\x${hex(byte)};`;
    } else result += String.fromCharCode(byte);
  }
  return result + '"';
}

class SourceWriter {
  readonly bytes: number[] = [];
  readonly origins: Position[] = [];

  constructor(private readonly limit: number) {}

  write(text: string, at: Position): void {
    for (let index = 0; index < text.length; index++) {
      if (this.bytes.length >= this.limit) {
        throw new SyntaxRulesError(
          "capacity",
          at,
          `expanded source exceeds ${this.limit} bytes`,
        );
      }
      const byte = text.charCodeAt(index);
      if (byte > 127) {
        throw new SyntaxRulesError(
          "syntax",
          at,
          "expanded identifiers and source text must be ASCII",
        );
      }
      this.bytes.push(byte);
      this.origins.push(at);
    }
  }

  locator(): SourceLocator {
    const origins = this.origins.slice();
    return {
      locate(offset) {
        if (origins.length === 0) {
          return { source: "<expanded>", line: 1, column: 1 };
        }
        return origins[Math.min(Math.max(offset, 0), origins.length - 1)]!;
      },
    };
  }
}

function serializeDatum(
  datum: SyntaxDatum,
  writer: SourceWriter,
): void {
  switch (datum.kind) {
    case "symbol":
      writer.write(datum.name, datum.at);
      return;
    case "value":
      writer.write(valueText(datum.value), datum.at);
      return;
    case "string":
      writer.write(stringText(datum.bytes), datum.at);
      return;
    case "quote":
      writer.write("'", datum.at);
      serializeDatum(datum.datum, writer);
      return;
    case "list":
      writer.write("(", datum.at);
      datum.items.forEach((item, index) => {
        if (index > 0) writer.write(" ", item.at);
        serializeDatum(item, writer);
      });
      if (datum.tail !== null) {
        writer.write(" . ", datum.tail.at);
        serializeDatum(datum.tail, writer);
      }
      writer.write(")", datum.at);
      return;
  }
}

function serializeForms(
  forms: readonly SyntaxDatum[],
  limits: Readonly<SyntaxRulesLimits>,
): { readonly bytes: Uint8Array; readonly sourceName: SourceLocator } {
  const writer = new SourceWriter(limits.maxOutputBytes);
  for (const [index, form] of forms.entries()) {
    if (index > 0) writer.write("\n", form.at);
    serializeDatum(form, writer);
  }
  return {
    bytes: Uint8Array.from(writer.bytes),
    sourceName: writer.locator(),
  };
}

/** Expand ordered top-level syntax-rules definitions into an ordinary source stream. */
export function expandSyntaxRules(
  sourceBytes: Uint8Array,
  sourceName: string | SourceLocator = "<input>",
  options: Partial<SyntaxRulesLimits> = {},
): ExpandedSource {
  if (!(sourceBytes instanceof Uint8Array)) {
    throw new TypeError("Syntax-rules source must be bytes");
  }
  const limits = checkLimits({
    ...DEFAULT_SYNTAX_RULES_LIMITS,
    ...options,
  });
  const reader = new SourceReader(sourceBytes, sourceName);
  const forms = parseDatums(reader);
  const state: ExpansionState = {
    limits,
    macros: new Map(),
    freeIdentifiers: new Set(),
    reservedNames: new Set(),
    definitions: 0,
    steps: 0,
    nextScope: 0,
    nextUseName: 0,
  };
  for (const form of forms) reserveSymbolNames(form, state.reservedNames);
  const expanded = processTopForms(forms, state);
  if (state.definitions === 0) {
    return {
      bytes: sourceBytes.slice(),
      sourceName,
      changed: false,
      macroDefinitions: 0,
      expansionSteps: state.steps,
    };
  }
  const serialized = serializeForms(expanded, limits);
  return {
    ...serialized,
    changed: true,
    macroDefinitions: state.definitions,
    expansionSteps: state.steps,
  };
}
