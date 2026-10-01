/** Adapt effect text and key events to the byte provider used by ports. */

import { EffectClient } from "./effect-client.ts";
import type { EffectResponse } from "./effect-commands.ts";
import { EffectPendingError, EffectProtocolError } from "./effect-wire.ts";
import {
  PORT_REPLY_BYTES,
  PortError,
  type PortProvider,
  type PortReadResult,
} from "./effect-ports.ts";

export interface EffectPortHandles {
  readonly input: number;
  readonly output: number;
  readonly error: number;
}

function portCode(error: unknown): PortError["code"] {
  if (error instanceof PortError) return error.code;
  if (error instanceof EffectPendingError) return "would-block";
  if (error instanceof EffectProtocolError) {
    return protocolPortCode(error.code);
  }
  return "transport";
}

function protocolPortCode(
  code: EffectProtocolError["code"],
): PortError["code"] {
  switch (code) {
    case "capacity":
      return "capacity";
    case "unsupported":
      return "unsupported";
    case "empty":
      return "would-block";
    case "device":
      return "device";
    case "malformed":
    case "invalid-command":
    case "invalid-event":
    case "truncated":
    case "checksum":
    case "version":
      return "malformed";
  }
}

function byteText(text: string): Uint8Array {
  const bytes: number[] = [];
  for (const character of text) {
    const codePoint = character.codePointAt(0)!;
    if (codePoint > 0xff) {
      throw new PortError(
        "malformed",
        "effect text contains a character outside Skate's byte range",
      );
    }
    bytes.push(codePoint);
  }
  return Uint8Array.from(bytes);
}

function errorResult(error: unknown): PortReadResult {
  if (error instanceof PortError) {
    return {
      status: "error",
      code: error.code,
      message: error.message,
      protocolCode: error.protocolCode,
    };
  }
  if (error instanceof EffectProtocolError) {
    return {
      status: "error",
      code: protocolPortCode(error.code),
      message: error.message,
      protocolCode: error.code,
    };
  }
  return {
    status: "error",
    code: portCode(error),
    message: error instanceof Error ? error.message : String(error),
  };
}

function requireEffectSuccess(response: EffectResponse): void {
  if (response.status === "ok") return;
  if (response.status === "pending") {
    throw new PortError(
      "would-block",
      `effect task ${response.task} is pending`,
    );
  }
  if (response.status === "empty") {
    throw new PortError("would-block", "effect provider has no reply");
  }
  throw new PortError(
    protocolPortCode(response.code),
    response.message,
    response.code,
  );
}

/**
 * Effect provider for the byte-oriented port boundary. Input is supplied by
 * normalized text or key events; output is sent as ordinary effect text.
 * Control and device commands remain separate from this adapter.
 */
export class EffectPortProvider implements PortProvider {
  private pending: Uint8Array<ArrayBufferLike> = new Uint8Array(0);

  constructor(
    private readonly client: EffectClient,
    private readonly handles: EffectPortHandles = {
      input: 1,
      output: 2,
      error: 3,
    },
  ) {}

  read(handle: number, maximum: number): PortReadResult {
    if (!Number.isInteger(maximum) || maximum < 1) {
      return {
        status: "error",
        code: "malformed",
        message: "effect read size must be a positive integer",
      };
    }
    if (maximum > PORT_REPLY_BYTES) {
      return {
        status: "error",
        code: "capacity",
        message: `effect read size exceeds ${PORT_REPLY_BYTES} bytes`,
      };
    }
    if (handle !== this.handles.input) {
      return {
        status: "error",
        code: "wrong-direction",
        message: "effect output is not readable",
      };
    }
    if (this.pending.length > 0) return this.take(maximum);
    try {
      const event = this.client.readEvent("normalized");
      if (event === null) return { status: "empty" };
      let text: string | undefined;
      if (event.type === "text") text = event.text;
      else if (event.type === "key") text = event.text;
      if (text === undefined || text.length === 0) {
        return {
          status: "error",
          code: "device",
          message: "event has no text for read-char",
        };
      }
      const bytes = byteText(text);
      if (bytes.length > PORT_REPLY_BYTES) {
        return {
          status: "error",
          code: "capacity",
          message: `effect text exceeds ${PORT_REPLY_BYTES} bytes`,
        };
      }
      this.pending = bytes;
      return this.take(maximum);
    } catch (error) {
      return errorResult(error);
    }
  }

  write(handle: number, bytes: Uint8Array): void {
    if (handle !== this.handles.output && handle !== this.handles.error) {
      throw new PortError("wrong-direction", "effect input is not writable");
    }
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      throw new PortError("malformed", "effect text must contain bytes");
    }
    try {
      requireEffectSuccess(this.client.request({ type: "text", bytes }));
    } catch (error) {
      if (error instanceof PortError) throw error;
      throw new PortError(
        portCode(error),
        error instanceof Error ? error.message : String(error),
        error instanceof EffectProtocolError ? error.code : undefined,
      );
    }
  }

  close(): void {
    throw new PortError("unsupported", "standard effect ports are permanent");
  }

  flush(): void {
    // The synchronous text request is committed before it returns.
  }

  private take(maximum: number): PortReadResult {
    const count = Math.min(maximum, this.pending.length);
    const bytes = this.pending.slice(0, count);
    this.pending = this.pending.slice(count);
    return { status: "data", bytes };
  }
}
