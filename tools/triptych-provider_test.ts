import assert from "node:assert/strict";
import { EffectProtocolError } from "./effect-protocol.ts";
import {
  createTriptychClient,
  RecordingTriptychBackend,
  TRIPTYCH_CAPABILITY,
  TriptychEffectProvider,
} from "./triptych-provider.ts";
import { EffectClient, ProviderTransport } from "./effect-protocol.ts";

function exercise(client: EffectClient): void {
  client.sendControl(TRIPTYCH_CAPABILITY.video, Uint8Array.of(0x10, 0x20));
  client.sendControl(TRIPTYCH_CAPABILITY.sound, Uint8Array.of(0x30, 0x40));
  client.sendText("ordinary");
}

Deno.test("independent Triptych backends receive the same transcript", () => {
  const first = new RecordingTriptychBackend();
  const second = new RecordingTriptychBackend();
  exercise(createTriptychClient(first));
  exercise(createTriptychClient(second));
  assert.deepEqual(second.transcript, first.transcript);
  assert.deepEqual(first.transcript, [
    { domain: "video", bytes: Uint8Array.of(0x10, 0x20) },
    { domain: "sound", bytes: Uint8Array.of(0x30, 0x40) },
  ]);
});

Deno.test("unsupported Triptych capabilities fail without backend writes", () => {
  const backend = new RecordingTriptychBackend();
  const client = createTriptychClient(backend);
  assert.throws(
    () => client.sendControl(0x0102, Uint8Array.of(1)),
    (error) =>
      error instanceof EffectProtocolError && error.code === "unsupported",
  );
  assert.deepEqual(backend.transcript, []);
});

Deno.test("ordinary controls pass through beside reserved Triptych handles", () => {
  const backend = new RecordingTriptychBackend();
  const provider = new TriptychEffectProvider(backend);
  const client = new EffectClient(new ProviderTransport(provider));
  client.sendControl(0, Uint8Array.of(0x1b, 0x5b, 0x32, 0x4a));
  client.sendControl(7, Uint8Array.of(0x10));
  assert.deepEqual(backend.transcript, []);
});

Deno.test("Triptych provider retains ordinary input and query services", () => {
  const backend = new RecordingTriptychBackend({
    video: Uint8Array.of(0xaa),
  });
  const provider = new TriptychEffectProvider(backend);
  provider.setQueryReply(7, Uint8Array.of(1), Uint8Array.of(2));
  provider.queueEvent({
    type: "key",
    source: 3,
    sequence: 4,
    key: "ArrowUp",
    modifiers: 0,
  });
  const client = new EffectClient(new ProviderTransport(provider));
  assert.deepEqual(
    client.query(7, Uint8Array.of(1)),
    Uint8Array.of(2),
  );
  assert.deepEqual(client.readEvent(), {
    type: "key",
    source: 3,
    sequence: 4,
    key: "ArrowUp",
    modifiers: 0,
  });
  assert.deepEqual(
    client.request({
      type: "control",
      capability: TRIPTYCH_CAPABILITY.video,
      bytes: Uint8Array.of(9),
    }),
    { status: "ok", bytes: Uint8Array.of(0xaa) },
  );
});
