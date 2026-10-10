// The runtime's memory layout, modelled for the proofs and unit tests.

/**
 * Predict the runtime's HEAP_LIM, where its stack starts, as PAGE_INI lays
 * memory out: the collector maps take 40 bytes for each heap page, above the
 * fixed bands (at RT_TOP) as far as they fit below the BDOS, and below
 * RT_OPLO otherwise; the heap ends at the highest page that leaves room.
 */
export function predictHeapLimit(imageEnd, bdosBase, opLo, top) {
  const base = (imageEnd + 0xff) >> 8;
  const highTop = Math.max(bdosBase >> 8, top >> 8) << 8;
  for (let end = opLo >> 8; end - base >= 4; end -= 1) {
    const pages = end - base;
    let high = top;
    let low = end << 8;
    for (const size of [16 * pages, 16 * pages, 8 * pages]) {
      if (high + size <= highTop) high += size;
      else low += size;
    }
    if (low <= opLo) return end << 8;
  }
  throw new Error(`no heap layout for an image ending at ${imageEnd}`);
}
