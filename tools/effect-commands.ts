import {
  checkedBytes,
  DEFAULT_EFFECT_LIMITS,
  type EffectFrame,
  type EffectLimits,
  EffectProtocolError,
  encodeEffectFrame,
  integer,
  readWord,
  taskNumber,
  writeWord,
} from "./effect-wire.ts";
import type { EffectProtocolErrorCode } from "./effect-wire.ts";

export const EffectCommandOpcode = Object.freeze({
  text: 1,
  control: 2,
  readEvent: 3,
  query: 4,
  poll: 5,
});

export type EffectReadMode = "normalized" | "raw";

export type EffectCommand =
  | { readonly type: "text"; readonly bytes: Uint8Array }
  | {
    readonly type: "control";
    readonly capability: number;
    readonly bytes: Uint8Array;
  }
  | { readonly type: "read-event"; readonly mode: EffectReadMode }
  | {
    readonly type: "query";
    readonly capability: number;
    readonly bytes: Uint8Array;
  }
  | { readonly type: "poll"; readonly task: number };

function commandPayload(command: EffectCommand): Uint8Array {
  switch (command.type) {
    case "text":
      return checkedBytes(command.bytes, "text").slice();
    case "control":
    case "query": {
      integer(command.capability, "capability", 0xffff);
      const bytes = checkedBytes(command.bytes, command.type).slice();
      const payload = new Uint8Array(bytes.length + 2);
      writeWord(payload, 0, command.capability);
      payload.set(bytes, 2);
      return payload;
    }
    case "read-event": {
      if (command.mode !== "normalized" && command.mode !== "raw") {
        throw new EffectProtocolError(
          "invalid-command",
          "read-event mode must be normalized or raw",
        );
      }
      return Uint8Array.of(command.mode === "raw" ? 1 : 0);
    }
    case "poll": {
      taskNumber(command.task, "task");
      const payload = new Uint8Array(2);
      writeWord(payload, 0, command.task);
      return payload;
    }
  }
}

export function encodeEffectCommand(
  command: EffectCommand,
  correlation: number,
  limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
): Uint8Array {
  const opcode = command.type === "read-event"
    ? EffectCommandOpcode.readEvent
    : EffectCommandOpcode[command.type];
  return encodeEffectFrame({
    kind: "request",
    opcode,
    correlation,
    payload: commandPayload(command),
  }, limits);
}

export function decodeEffectCommand(frame: EffectFrame): EffectCommand {
  if (frame.kind !== "request") {
    throw new EffectProtocolError(
      "invalid-command",
      "Expected an effect request",
    );
  }
  const payload = frame.payload;
  switch (frame.opcode) {
    case EffectCommandOpcode.text:
      return { type: "text", bytes: payload.slice() };
    case EffectCommandOpcode.control:
    case EffectCommandOpcode.query:
      if (payload.length < 2) {
        throw new EffectProtocolError(
          "invalid-command",
          "Capability command needs a two-byte handle",
        );
      }
      return {
        type: frame.opcode === EffectCommandOpcode.control
          ? "control"
          : "query",
        capability: readWord(payload, 0),
        bytes: payload.slice(2),
      };
    case EffectCommandOpcode.readEvent:
      if (payload.length !== 1 || (payload[0] !== 0 && payload[0] !== 1)) {
        throw new EffectProtocolError(
          "invalid-command",
          "read-event needs a normalized/raw mode byte",
        );
      }
      return {
        type: "read-event",
        mode: payload[0] === 1 ? "raw" : "normalized",
      };
    case EffectCommandOpcode.poll:
      if (payload.length !== 2) {
        throw new EffectProtocolError(
          "invalid-command",
          "poll needs a two-byte task ID",
        );
      }
      {
        const task = readWord(payload, 0);
        if (task === 0) {
          throw new EffectProtocolError(
            "invalid-command",
            "poll task ID must be nonzero",
          );
        }
        return { type: "poll", task };
      }
    default:
      throw new EffectProtocolError(
        "unsupported",
        `Unsupported effect command opcode ${frame.opcode}`,
      );
  }
}

export type EffectResponse =
  | { readonly status: "ok"; readonly bytes: Uint8Array }
  | { readonly status: "empty" }
  | { readonly status: "pending"; readonly task: number }
  | {
    readonly status: "error";
    readonly code: EffectProtocolErrorCode;
    readonly message: string;
  };

export const EffectResponseStatus = Object.freeze({
  ok: 0,
  empty: 1,
  error: 2,
  pending: 3,
});
const responseStatusName: Record<
  number,
  "ok" | "empty" | "error" | "pending"
> = {
  0: "ok",
  1: "empty",
  2: "error",
  3: "pending",
};
export const EffectErrorCode = Object.freeze(
  {
    malformed: 0,
    version: 1,
    truncated: 2,
    checksum: 3,
    capacity: 4,
    unsupported: 5,
    "invalid-command": 6,
    "invalid-event": 7,
    empty: 8,
    device: 9,
  } satisfies Record<EffectProtocolErrorCode, number>,
);
const errorCodeList = Object.freeze(
  [
    "malformed",
    "version",
    "truncated",
    "checksum",
    "capacity",
    "unsupported",
    "invalid-command",
    "invalid-event",
    "empty",
    "device",
  ] satisfies EffectProtocolErrorCode[],
);

function errorCodeIndex(code: EffectProtocolErrorCode): number {
  const index = errorCodeList.indexOf(code);
  return index < 0 ? 0 : index;
}

export function encodeEffectResponse(
  response: EffectResponse,
  correlation: number,
  opcode: number,
  limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
): Uint8Array {
  let payload: Uint8Array;
  if (response.status === "ok") {
    payload = new Uint8Array(response.bytes.length + 1);
    payload[0] = EffectResponseStatus.ok;
    payload.set(response.bytes, 1);
  } else if (response.status === "empty") {
    payload = Uint8Array.of(EffectResponseStatus.empty);
  } else if (response.status === "pending") {
    taskNumber(response.task, "task");
    payload = new Uint8Array(3);
    payload[0] = EffectResponseStatus.pending;
    writeWord(payload, 1, response.task);
  } else {
    const message = new TextEncoder().encode(response.message);
    payload = new Uint8Array(message.length + 2);
    payload[0] = EffectResponseStatus.error;
    payload[1] = errorCodeIndex(response.code);
    payload.set(message, 2);
  }
  return encodeEffectFrame({
    kind: "response",
    opcode,
    correlation,
    payload,
  }, limits);
}

export function decodeEffectResponse(frame: EffectFrame): EffectResponse {
  if (frame.kind !== "response" || frame.payload.length < 1) {
    throw new EffectProtocolError(
      "malformed",
      "Expected a nonempty effect response",
    );
  }
  const status = responseStatusName[frame.payload[0]!];
  if (status === undefined) {
    throw new EffectProtocolError(
      "malformed",
      "Effect response status is invalid",
    );
  }
  if (status === "ok") return { status, bytes: frame.payload.slice(1) };
  if (status === "empty") {
    if (frame.payload.length !== 1) {
      throw new EffectProtocolError(
        "malformed",
        "Empty response has a payload",
      );
    }
    return { status };
  }
  if (status === "pending") {
    if (frame.payload.length !== 3) {
      throw new EffectProtocolError(
        "malformed",
        "Pending response needs one task ID",
      );
    }
    const task = readWord(frame.payload, 1);
    if (task === 0) {
      throw new EffectProtocolError(
        "malformed",
        "Pending response task ID must be nonzero",
      );
    }
    return { status, task };
  }
  if (frame.payload.length < 2) {
    throw new EffectProtocolError(
      "malformed",
      "Error response lacks an error code",
    );
  }
  const code = errorCodeList[frame.payload[1]!];
  if (code === undefined) {
    throw new EffectProtocolError(
      "malformed",
      "Error response code is invalid",
    );
  }
  return {
    status,
    code,
    message: new TextDecoder().decode(frame.payload.slice(2)),
  };
}
