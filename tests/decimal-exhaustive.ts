/** Optional native proof across every finite binary16 printer output. */
import assert from "node:assert/strict";
import { decimalMachine } from "./decimal-machine.ts";
import { formatNumber } from "../tools/numeric.ts";

export async function verifyDecimalRoundTrips() {
  const machine = await decimalMachine();
  let count = 0;
  for (let magnitude = 0; magnitude < 0x7c00; magnitude++) {
    for (const sign of [0, 0x8000]) {
      const bits = magnitude | sign;
      const token = formatNumber([0, bits]);
      const actual = machine.parse(token);
      assert.equal(actual.carry, 0, token);
      assert.deepEqual([actual.tag, actual.bits], [0, bits], token);
      count++;
    }
  }
  assert.equal(count, 63488);
  console.log("Native decimal finite roundtrips", count, machine.census());
}

if (import.meta.main) await verifyDecimalRoundTrips();
