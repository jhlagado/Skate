/** Measured address budget for the production CP/M compiler image. */

export const NATIVE_COMPILER_LOAD = 0x0100;
export const NATIVE_COMPILER_STACK_GUARD = 0xa000;
export const NATIVE_PAIR_OVERLAY_BASE = 0xb000;
export const NATIVE_PAIR_OVERLAY_END = 0xc000;
export const NATIVE_MACRO_ARENA_BASE = 0xc000;

/** CP/M transient-area tops used by the compiler memory-map gate. */
export const NATIVE_COMPILER_PROFILES = Object.freeze(
  {
    "cpm-64k": 0xe400,
    "cpm-32k": 0x8000,
  } as const,
);

export type NativeCompilerProfile = keyof typeof NATIVE_COMPILER_PROFILES;

export interface NativeBudgetImage {
  readonly end: number;
}

export type NativeBudgetAddress = (name: string) => number;

export interface NativeBudgetSpan {
  readonly name: string;
  readonly start: number;
  readonly end: number;
  readonly bytes: number;
}

export interface NativeCompilerBudget {
  readonly entry: number;
  readonly imageEnd: number;
  readonly imageBytes: number;
  readonly stackGuard: number;
  readonly imageToStackGap: number;
  readonly spans: readonly NativeBudgetSpan[];
}

export interface NativeCompilerMap {
  readonly profile: NativeCompilerProfile;
  readonly tpaTop: number;
  readonly imageEnd: number;
  readonly stackGuard: number;
  readonly pairOverlay: { readonly start: number; readonly end: number };
  readonly macroArena: {
    readonly start: number;
    readonly end: number;
    readonly bytes: number;
  };
  readonly errors: readonly string[];
  readonly accepted: boolean;
}

/**
 * Check the fixed compiler intervals before a source package is admitted.
 *
 * The compiler uses the low image, a guarded native stack, the transient pair
 * overlay, and the macro arena in that order.  Keeping this check in the host
 * budget tool gives the CP/M proof and the native entry point the same profile
 * vocabulary; a 32K target fails explicitly because its TPA ends below the
 * macro arena rather than failing later as an accidental overwrite.
 */
export function planNativeCompilerMap(
  profile: NativeCompilerProfile,
  imageEnd: number,
): NativeCompilerMap {
  const tpaTop = NATIVE_COMPILER_PROFILES[profile];
  const errors: string[] = [];
  if (!Number.isInteger(imageEnd) || imageEnd <= NATIVE_COMPILER_LOAD) {
    errors.push("compiler image is empty or below its entry");
  }
  if (imageEnd > NATIVE_COMPILER_STACK_GUARD) {
    errors.push("compiler image overlaps the native stack guard");
  }
  if (NATIVE_COMPILER_STACK_GUARD > NATIVE_PAIR_OVERLAY_BASE) {
    errors.push("native stack guard overlaps the pair overlay");
  }
  if (NATIVE_PAIR_OVERLAY_END !== NATIVE_MACRO_ARENA_BASE) {
    errors.push("pair overlay does not meet the macro arena");
  }
  if (tpaTop <= NATIVE_MACRO_ARENA_BASE) {
    errors.push("profile TPA does not reach the macro arena");
  }
  return {
    profile,
    tpaTop,
    imageEnd,
    stackGuard: NATIVE_COMPILER_STACK_GUARD,
    pairOverlay: {
      start: NATIVE_PAIR_OVERLAY_BASE,
      end: NATIVE_PAIR_OVERLAY_END,
    },
    macroArena: {
      start: NATIVE_MACRO_ARENA_BASE,
      end: tpaTop,
      bytes: Math.max(0, tpaTop - NATIVE_MACRO_ARENA_BASE),
    },
    errors,
    accepted: errors.length === 0,
  };
}

function span(
  address: NativeBudgetAddress,
  name: string,
  startLabel: string,
  endLabel: string,
): NativeBudgetSpan {
  const start = address(startLabel);
  const end = address(endLabel);
  if (end < start) {
    throw new RangeError(`${name} span is reversed`);
  }
  return { name, start, end, bytes: end - start };
}

/** Measure the production `compiler/skate.asm` image without executing it. */
export function measureNativeCompilerBudget(
  image: NativeBudgetImage,
  address: NativeBudgetAddress,
): NativeCompilerBudget {
  const entry = address("N6MAIN");
  if (entry !== NATIVE_COMPILER_LOAD) {
    throw new RangeError(
      `production compiler entry is $${entry.toString(16)}, expected $0100`,
    );
  }
  if (image.end <= entry || image.end > NATIVE_COMPILER_STACK_GUARD) {
    throw new RangeError("production compiler overlaps its native stack guard");
  }
  const spans = [
    span(address, "compiler evaluator and lowering", "N6MAIN", "N4OBJ"),
    span(address, "NOBJ skeleton", "N4OBJ", "N4OBJEND"),
    span(address, "CP/M source adapter", "CSOPEN", "CSWEND"),
    span(address, "reader and tables", "RINIT", "RWEND"),
    span(address, "lexer and tables", "LEXINIT", "LEXWEND"),
    span(address, "decimal parser workspace", "DPARSE", "DWEND"),
    span(address, "interner and tables", "IINIT", "IWEND"),
  ];
  return {
    entry,
    imageEnd: image.end,
    imageBytes: image.end - entry,
    stackGuard: NATIVE_COMPILER_STACK_GUARD,
    imageToStackGap: NATIVE_COMPILER_STACK_GUARD - image.end,
    spans,
  };
}

export function renderNativeCompilerBudget(
  budget: NativeCompilerBudget,
  map?: NativeCompilerMap,
): string {
  const hex = (value: number) =>
    `$${value.toString(16).toUpperCase().padStart(4, "0")}`;
  const lines = [
    "# Native compiler memory budget",
    "",
    `Entry: ${hex(budget.entry)}`,
    `Image: ${hex(budget.entry)}..${
      hex(budget.imageEnd)
    } (${budget.imageBytes} B)`,
    `Native stack guard: ${hex(budget.stackGuard)}`,
    `Image-to-stack gap: ${budget.imageToStackGap} B`,
    "",
    "| Span | Start | End | Bytes |",
    "| --- | ---: | ---: | ---: |",
    ...budget.spans.map((item) =>
      `| ${item.name} | ${hex(item.start)} | ${hex(item.end)} | ${item.bytes} |`
    ),
    ...(map === undefined ? [] : [
      "",
      `Profile: ${map.profile}`,
      `TPA top: ${hex(map.tpaTop)}`,
      `Pair overlay: ${hex(map.pairOverlay.start)}..${
        hex(map.pairOverlay.end)
      }`,
      `Macro arena: ${hex(map.macroArena.start)}..${
        hex(map.macroArena.end)
      } (${map.macroArena.bytes} B)`,
      `Profile accepted: ${map.accepted ? "yes" : "no"}`,
      ...(map.errors.length === 0
        ? []
        : map.errors.map((error) => `Profile error: ${error}`)),
    ]),
    "",
  ];
  return lines.join("\n");
}

if (import.meta.main) {
  const { loadAssembly } = await import("../tests/z80.ts");
  const assembled = await loadAssembly("compiler/skate.asm");
  const budget = measureNativeCompilerBudget(
    assembled.image,
    assembled.address,
  );
  console.log(
    renderNativeCompilerBudget(
      budget,
      planNativeCompilerMap("cpm-64k", budget.imageEnd),
    ),
  );
}
