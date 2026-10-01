import assert from "node:assert/strict";

import {
  EffectClient,
  EVENT_EMPTY,
  EventLibrary,
  isKeyEvent,
  isPointerEvent,
  ProviderTransport,
  RecordingEffectProvider,
} from "./effect-protocol.ts";

Deno.test("event helpers preserve keyboard and pointer records", () => {
  const provider = new RecordingEffectProvider();
  provider.queueEvent({
    type: "key",
    source: 3,
    sequence: 10,
    key: "ArrowLeft",
    modifiers: 1,
  });
  provider.queueEvent({
    type: "pointer",
    source: 3,
    sequence: 11,
    x: -4,
    y: 12,
    buttons: 2,
  });
  const events = new EventLibrary(
    new EffectClient(new ProviderTransport(provider)),
  );
  const key = events.readKey();
  assert.notEqual(key, EVENT_EMPTY);
  if (key === null) throw new Error("key selector returned null");
  if (key === EVENT_EMPTY) throw new Error("key event was empty");
  assert.equal(isKeyEvent(key), true);
  const pointer = events.readPointer();
  assert.notEqual(pointer, EVENT_EMPTY);
  if (pointer === null) throw new Error("pointer selector returned null");
  if (pointer === EVENT_EMPTY) throw new Error("pointer event was empty");
  assert.equal(isPointerEvent(pointer), true);
  assert.equal(events.read(), EVENT_EMPTY);
});

Deno.test("event text is available without changing read-char", () => {
  const provider = new RecordingEffectProvider();
  provider.queueEvent({
    type: "text",
    source: 4,
    sequence: 1,
    text: "hello",
  });
  const events = new EventLibrary(
    new EffectClient(new ProviderTransport(provider)),
  );
  assert.equal(events.readText(), "hello");
  assert.equal(events.readKey(), EVENT_EMPTY);
});
