import assert from "node:assert/strict";
import {
  decodeEffectFrame,
  EffectProtocolError,
  encodeEffectFrame,
} from "./effect-protocol.ts";
import { CpmEffectAdapter, RecordingCpmByteChannel } from "./cpm-effects.ts";

const text = (value: string) => new TextEncoder().encode(value);

const request = encodeEffectFrame({
  kind: "request",
  opcode: 2,
  correlation: 7,
  payload: Uint8Array.of(0x00, 0x01, 0x02),
});

Deno.test("CP/M text mode preserves ordinary bytes and console settings", () => {
  const channel = new RecordingCpmByteChannel();
  const adapter = new CpmEffectAdapter(channel);
  adapter.sendText(text("hello\r\n"));
  assert.deepEqual(channel.output, [...text("hello\r\n")]);
  assert.deepEqual(channel.settings.at(-1), {
    echo: true,
    lineEditing: true,
    translateCrLf: true,
    translateCtrlZ: true,
  });
  assert.throws(
    () => adapter.sendFrame(decodeEffectFrame(request)),
    (error) =>
      error instanceof EffectProtocolError && error.code === "unsupported",
  );
});

Deno.test("mixed mode escapes text and carries a frame without CP/M translation", () => {
  const channel = new RecordingCpmByteChannel();
  const adapter = new CpmEffectAdapter(channel);
  adapter.enterMixed();
  adapter.sendText(text("A\x1b~B"));
  adapter.sendFrame(decodeEffectFrame(request));
  adapter.sendText(text("Z"));
  assert.deepEqual(channel.output, [
    ...text("A\x1b\x1b~B"),
    ...request,
    ...text("Z"),
  ]);
  assert.deepEqual(channel.settings.at(-1), {
    echo: false,
    lineEditing: false,
    translateCrLf: false,
    translateCtrlZ: false,
  });

  channel.feed(Uint8Array.from(channel.output));
  const items = adapter.readAvailable();
  assert.deepEqual(items.map((item) => item.type), ["text", "frame", "text"]);
  assert.deepEqual(items[0], { type: "text", bytes: text("A\x1b~B") });
  assert.deepEqual(items[1], {
    type: "frame",
    frame: decodeEffectFrame(request),
  });
  assert.deepEqual(items[2], { type: "text", bytes: text("Z") });
});

Deno.test("raw mode carries zero bytes and rejects an incomplete frame at finish", () => {
  const channel = new RecordingCpmByteChannel();
  const adapter = new CpmEffectAdapter(channel);
  adapter.enterRaw();
  adapter.sendFrame(decodeEffectFrame(request));
  channel.feed(request);
  const items = adapter.readAvailable();
  assert.deepEqual(items, [{
    type: "frame",
    frame: decodeEffectFrame(request),
  }]);
  channel.feed(request.slice(0, 3));
  assert.deepEqual(adapter.readAvailable(), []);
  assert.throws(
    () => adapter.finish(),
    (error) =>
      error instanceof EffectProtocolError && error.code === "truncated",
  );
});

Deno.test("leaving raw mode resets the decoder and restores text behavior", () => {
  const channel = new RecordingCpmByteChannel();
  const adapter = new CpmEffectAdapter(channel);
  adapter.enterRaw();
  channel.feed(request.slice(0, 4));
  assert.deepEqual(adapter.readAvailable(), []);
  adapter.enterText();
  channel.feed(text("ready"));
  assert.deepEqual(adapter.readAvailable(), [{
    type: "text",
    bytes: text("ready"),
  }]);
  assert.deepEqual(channel.settings.at(-1), {
    echo: true,
    lineEditing: true,
    translateCrLf: true,
    translateCtrlZ: true,
  });
});
