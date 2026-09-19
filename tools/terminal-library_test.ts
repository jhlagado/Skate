import assert from "node:assert/strict";
import {
  EffectClient,
  ProviderTransport,
  RecordingEffectProvider,
} from "./effect-protocol.ts";
import { createTerminalLibrary } from "./terminal-library.ts";

const bytes = (value: string) => new TextEncoder().encode(value);

Deno.test("terminal library records ANSI output and a provider VDP command", () => {
  const provider = new RecordingEffectProvider();
  const terminal = createTerminalLibrary(
    new EffectClient(new ProviderTransport(provider)),
  );
  terminal.clear();
  terminal.home();
  terminal.foreground("red");
  terminal.cursor(3, 5);
  terminal.write("Hello");
  terminal.line("world");
  terminal.vdp(7, 0x10, Uint8Array.of(0x20, 0x30));

  assert.deepEqual(
    provider.controls.map(({ capability, bytes: value }) => ({
      capability,
      bytes: value,
    })),
    [
      { capability: 0, bytes: bytes("\x1b[2J") },
      { capability: 0, bytes: bytes("\x1b[H") },
      { capability: 0, bytes: bytes("\x1b[31m") },
      { capability: 0, bytes: bytes("\x1b[3;5H") },
      { capability: 7, bytes: Uint8Array.of(0x10, 0x20, 0x30) },
    ],
  );
  assert.deepEqual(provider.textWrites, [
    bytes("Hello"),
    bytes("world"),
    bytes("\r\n"),
  ]);
});

Deno.test("terminal library rejects invalid coordinates and VDP opcodes", () => {
  const provider = new RecordingEffectProvider();
  const terminal = createTerminalLibrary(
    new EffectClient(new ProviderTransport(provider)),
  );
  assert.throws(() => terminal.cursor(0, 1), RangeError);
  assert.throws(() => terminal.cursor(1, 0x10000), RangeError);
  assert.throws(() => terminal.vdp(1, 0x100), RangeError);
});
