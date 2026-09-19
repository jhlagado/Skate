import assert from "node:assert/strict";
import { linkSkateObjects } from "../../../../tools/link.ts";
import {
  assembleFixture,
  linkOptions,
  payloadObject,
  providerObject,
  ROOTBASE,
  STACKLOW,
  STACKTOP,
  WORKSPACE_BYTES,
} from "./provider_fixture.ts";

Deno.test("prepared placement rejects overlap, stack crossing and TPA overflow", async () => {
  const [providerAssembly, payloadAssembly] = await assembleFixture();
  const provider = providerObject(providerAssembly);
  assert.throws(
    () => {
      const overlap = payloadObject(payloadAssembly, ROOTBASE);
      linkSkateObjects([
        { id: "provider", bytes: provider.serialized },
        { id: "payload", bytes: overlap.serialized },
      ], linkOptions(ROOTBASE));
    },
    /overlap/i,
  );
  assert.throws(
    () => {
      const stackCrossingBase = STACKLOW - WORKSPACE_BYTES + 1;
      assert.equal(stackCrossingBase + WORKSPACE_BYTES, STACKLOW + 1);
      assert.ok(stackCrossingBase + WORKSPACE_BYTES <= STACKTOP);
      const stackCrossing = payloadObject(
        payloadAssembly,
        stackCrossingBase,
      );
      linkSkateObjects([
        { id: "provider", bytes: provider.serialized },
        { id: "payload", bytes: stackCrossing.serialized },
      ], linkOptions(stackCrossingBase));
    },
    /stack allocation overlaps a linked section/i,
  );
  assert.throws(
    () => {
      const tpaOverflowBase = STACKTOP - WORKSPACE_BYTES + 1;
      assert.equal(tpaOverflowBase + WORKSPACE_BYTES, STACKTOP + 1);
      const overflow = payloadObject(
        payloadAssembly,
        tpaOverflowBase,
      );
      linkSkateObjects([
        { id: "provider", bytes: provider.serialized },
        { id: "payload", bytes: overflow.serialized },
      ], linkOptions(tpaOverflowBase));
    },
    /SECTION run extent does not fit its REGION/i,
  );
});
