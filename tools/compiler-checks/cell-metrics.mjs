/** Host-side summaries for the four-byte-cell baseline and later comparisons. */

export const CURRENT_HEAP_BINDING_BYTES = 3;
export const CURRENT_PAIR_BYTES = 5;
export const EXPERIMENT_HEAP_BINDING_BYTES = 4;
export const EXPERIMENT_PAIR_BYTES = 8;

function maximum(measurements, field) {
  return measurements.reduce(
    (value, measurement) => Math.max(value, measurement[field] ?? 0),
    0,
  );
}

function total(measurements, field) {
  return measurements.reduce(
    (value, measurement) => value + (measurement[field] ?? 0),
    0,
  );
}

/**
 * Summarise independent maxima and allocation traffic from one proof suite.
 * The byte totals describe allocation traffic, not peak live heap occupancy;
 * they are size-model projections and exclude page, map and free-list overhead.
 */
export function summarizeCellMeasurements(measurements) {
  if (!Array.isArray(measurements) || measurements.length === 0) {
    throw new RangeError("cell measurement suite is empty");
  }
  const pairAllocations = total(measurements, "pairAllocations");
  const bindingAllocations = total(measurements, "bindingAllocations");
  return {
    cases: measurements.length,
    maxComBytes: maximum(measurements, "comBytes"),
    maxAsoBytes: maximum(measurements, "asoBytes"),
    maxImageBytes: maximum(measurements, "imageBytes"),
    maxPairAllocations: maximum(measurements, "pairAllocations"),
    maxBindingAllocations: maximum(measurements, "bindingAllocations"),
    maxClosureAllocations: maximum(measurements, "closureAllocations"),
    maxCollections: maximum(measurements, "collections"),
    maxActivations: maximum(measurements, "activations"),
    pairAllocations,
    bindingAllocations,
    currentPairAllocationBytes: pairAllocations * CURRENT_PAIR_BYTES,
    experimentPairAllocationBytes: pairAllocations * EXPERIMENT_PAIR_BYTES,
    currentBindingAllocationBytes: bindingAllocations *
      CURRENT_HEAP_BINDING_BYTES,
    experimentBindingAllocationBytes: bindingAllocations *
      EXPERIMENT_HEAP_BINDING_BYTES,
  };
}
