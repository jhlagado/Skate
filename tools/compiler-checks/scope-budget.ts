/** Measure the scope compiler image against the compact compiler gates. */

import { loadAssembly } from "../../tests/z80.ts";

export const SCOPE_LOAD = 0x0100;
export const SCOPE_CORE_LIMIT = 16_384;
export const SCOPE_ALLOCATION_LIMIT = 57_120;
export const SCOPE_STACK_TOP = 0xe020;
export const SCOPE_STACK_RESERVE = 2_048;
export const SCOPE_STAGE_GUARD = 256;
export const SCOPE_STRING_POOL_BYTES = 1_024;

export interface ScopeControlBudget {
  readonly imageEnd: number;
  readonly imageBytes: number;
  readonly coreRemaining: number;
  readonly allocationRemaining: number;
  readonly allocationBytes: number;
  readonly stackGap: number;
  readonly stageGap: number;
  readonly stagedOutputLimit: number;
  readonly stagedOutputGuard: number;
  readonly fixedTableBytes: number;
  readonly globalSlotCapacity: number;
  readonly localSlotCapacity: number;
  readonly fixupCapacity: number;
  readonly symbolCapacity: number;
}

export function measureScopeControlBudget(
  image: { end: number },
  address: (label: string) => number,
): ScopeControlBudget {
  const entry = address("SCMAIN");
  if (entry !== SCOPE_LOAD) {
    throw new RangeError(`scope compiler entry is $${entry.toString(16)}`);
  }
  const imageBytes = image.end - entry;
  const stageGap = address("SCSTAGE") - image.end;
  if (stageGap < SCOPE_STAGE_GUARD) {
    throw new RangeError(
      `scope compiler image leaves only ${stageGap} B before SCSTAGE`,
    );
  }
  const stagedOutputLimit = address("SCEND") - address("SCSTAGE");
  const fixedTableBytes = address("SCWEND") - address("SCGKEYS");
  const stringPoolEnd = address("SCSTRPL") + SCOPE_STRING_POOL_BYTES;
  const stackFloor = SCOPE_STACK_TOP - SCOPE_STACK_RESERVE;
  if (stringPoolEnd > address("SCPMETA")) {
    throw new RangeError(
      `string pool crosses procedure metadata at $${
        stringPoolEnd.toString(16)
      }`,
    );
  }
  if (address("SCRECEND") > stackFloor) {
    throw new RangeError(
      `replay workspace crosses stack reserve at $${
        address("SCRECEND").toString(16)
      }`,
    );
  }
  if (address("SCRECFR") >= address("SCRECEND")) {
    throw new RangeError("replay workspace has no capacity");
  }
  const allocationBytes = imageBytes + stagedOutputLimit + fixedTableBytes +
    SCOPE_STACK_RESERVE;
  return {
    imageEnd: image.end,
    imageBytes,
    coreRemaining: SCOPE_CORE_LIMIT - imageBytes,
    allocationRemaining: SCOPE_ALLOCATION_LIMIT - allocationBytes,
    allocationBytes,
    stackGap: SCOPE_STACK_TOP - image.end,
    stageGap,
    stagedOutputLimit,
    stagedOutputGuard: address("SCEND"),
    fixedTableBytes,
    globalSlotCapacity: 256,
    localSlotCapacity: 128,
    fixupCapacity: 320,
    symbolCapacity: 320,
  };
}

export function renderScopeControlBudget(
  budget: ScopeControlBudget,
): string {
  const hex = (value: number) =>
    `$${value.toString(16).toUpperCase().padStart(4, "0")}`;
  return [
    "# Scope compiler budget",
    "",
    `Image: ${hex(SCOPE_LOAD)}..${
      hex(budget.imageEnd)
    } exclusive (${budget.imageBytes} B)`,
    `Original core target: ${SCOPE_CORE_LIMIT} B; difference ${budget.coreRemaining} B`,
    `Compiler-to-stage gap: ${budget.stageGap} B; guard ${SCOPE_STAGE_GUARD} B`,
    `Fixed tables: ${budget.fixedTableBytes} B; guarded stack: ${SCOPE_STACK_RESERVE} B`,
    `Live allocation: ${budget.allocationBytes} B; gate ${SCOPE_ALLOCATION_LIMIT} B; remaining ${budget.allocationRemaining} B`,
    `Native stack: top ${hex(SCOPE_STACK_TOP)}; image gap ${budget.stackGap} B`,
    `ASO replay window: ${budget.stagedOutputLimit} B below ${
      hex(budget.stagedOutputGuard)
    }`,
    `Tables: ${budget.globalSlotCapacity} globals, ${budget.localSlotCapacity} simultaneous locals, ${budget.fixupCapacity} slot fixups, ${budget.symbolCapacity} symbol entries`,
    "",
  ].join("\n");
}

if (import.meta.main) {
  const assembled = await loadAssembly(
    "src/compiler/scope/compiler.asm",
  );
  console.log(renderScopeControlBudget(
    measureScopeControlBudget(assembled.image, assembled.address),
  ));
}
