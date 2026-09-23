import {
  checkedBytes,
  checkLimits,
  decodeEffectFrame,
  DEFAULT_EFFECT_LIMITS,
  type EffectFrame,
  type EffectLimits,
  EffectPendingError,
  EffectProtocolError,
  encodeEffectFrame,
  integer,
} from "./effect-wire.ts";
import {
  decodeEffectCommand,
  decodeEffectResponse,
  type EffectCommand,
  EffectCommandOpcode,
  type EffectReadMode,
  type EffectResponse,
  encodeEffectCommand,
  encodeEffectResponse,
} from "./effect-commands.ts";
import {
  decodeEffectEvent,
  type EffectEvent,
  encodeEffectEvent,
} from "./effect-events.ts";

function textBytes(value: string): Uint8Array {
  if (typeof value !== "string") {
    throw new EffectProtocolError("invalid-event", "text must be text");
  }
  return new TextEncoder().encode(value);
}

export interface EffectProvider {
  handle(request: EffectFrame): EffectFrame;
}

export interface EffectTransport {
  transact(request: Uint8Array): Uint8Array;
}

/** Adapter used by tests and modern harnesses to exercise the wire contract. */
export class ProviderTransport implements EffectTransport {
  constructor(
    private readonly provider: EffectProvider,
    private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
  ) {}

  transact(request: Uint8Array): Uint8Array {
    const frame = decodeEffectFrame(request, this.limits);
    return encodeEffectFrame(this.provider.handle(frame), this.limits);
  }
}

/** Synchronous client: one request is sent and one response is received. */
export class EffectClient {
  private nextCorrelation = 1;

  constructor(
    private readonly transport: EffectTransport,
    private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
  ) {}

  request(command: EffectCommand): EffectResponse {
    const correlation = this.nextCorrelation;
    this.nextCorrelation = this.nextCorrelation === 0xffff
      ? 1
      : this.nextCorrelation + 1;
    const request = encodeEffectCommand(command, correlation, this.limits);
    const responseFrame = decodeEffectFrame(
      this.transport.transact(request),
      this.limits,
    );
    if (
      responseFrame.kind !== "response" ||
      responseFrame.correlation !== correlation
    ) {
      throw new EffectProtocolError(
        "malformed",
        "Effect response correlation does not match request",
      );
    }
    if (responseFrame.opcode !== commandOpcode(command)) {
      throw new EffectProtocolError(
        "malformed",
        "Effect response opcode does not match request",
      );
    }
    return decodeEffectResponse(responseFrame);
  }

  sendText(text: string): void {
    const response = this.request({ type: "text", bytes: textBytes(text) });
    requireOk(response);
  }

  sendControl(capability: number, bytes: Uint8Array): void {
    requireOk(this.request({ type: "control", capability, bytes }));
  }

  readEvent(mode: EffectReadMode = "normalized"): EffectEvent | null {
    const response = this.request({ type: "read-event", mode });
    if (response.status === "empty") return null;
    if (response.status === "pending") {
      throw new EffectPendingError(response.task);
    }
    if (response.status === "error") {
      throw new EffectProtocolError(response.code, response.message);
    }
    return decodeEffectEvent(response.bytes);
  }

  query(capability: number, bytes: Uint8Array): Uint8Array {
    const response = this.request({ type: "query", capability, bytes });
    return requireOk(response);
  }

  poll(task: number): EffectResponse {
    return this.request({ type: "poll", task });
  }
}

function commandOpcode(command: EffectCommand): number {
  return command.type === "read-event"
    ? EffectCommandOpcode.readEvent
    : EffectCommandOpcode[command.type];
}

function requireOk(response: EffectResponse): Uint8Array {
  if (response.status === "ok") return response.bytes;
  if (response.status === "empty") {
    throw new EffectProtocolError(
      "empty",
      "Effect provider returned no result",
    );
  }
  if (response.status === "pending") {
    throw new EffectPendingError(response.task);
  }
  throw new EffectProtocolError(response.code, response.message);
}

export interface RecordedControl {
  readonly capability: number;
  readonly bytes: Uint8Array;
}

/** Deterministic reference provider for protocol and Triptych harness tests. */
export class RecordingEffectProvider implements EffectProvider {
  readonly textWrites: Uint8Array[] = [];
  readonly controls: RecordedControl[] = [];
  private readonly events: EffectEvent[] = [];
  private readonly queries = new Map<string, Uint8Array>();

  constructor(private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS) {
    checkLimits(limits);
  }

  queueEvent(event: EffectEvent): void {
    if (this.events.length >= this.limits.maxEventQueue) {
      throw new EffectProtocolError("capacity", "Effect event queue is full");
    }
    const encoded = encodeEffectEvent(event, this.limits);
    if (encoded.length + 1 > this.limits.maxPayloadBytes) {
      throw new EffectProtocolError(
        "capacity",
        "Effect event does not fit in a response frame",
      );
    }
    this.events.push(decodeEffectEvent(encoded));
  }

  setQueryReply(
    capability: number,
    request: Uint8Array,
    reply: Uint8Array,
  ): void {
    integer(capability, "capability", 0xffff);
    const key = `${capability}:${hex(request)}`;
    this.queries.set(key, checkedBytes(reply, "query reply").slice());
  }

  handle(request: EffectFrame): EffectFrame {
    try {
      const command = decodeEffectCommand(request);
      let response: EffectResponse;
      if (command.type === "text") {
        this.textWrites.push(command.bytes.slice());
        response = { status: "ok", bytes: new Uint8Array(0) };
      } else if (command.type === "control") {
        this.controls.push({
          capability: command.capability,
          bytes: command.bytes.slice(),
        });
        response = { status: "ok", bytes: new Uint8Array(0) };
      } else if (command.type === "read-event") {
        const event = this.events[0];
        if (event === undefined) response = { status: "empty" };
        else if (command.mode === "raw" && event.type !== "raw") {
          response = {
            status: "error",
            code: "device",
            message: "Raw mode needs a raw event",
          };
        } else if (command.mode === "normalized" && event.type === "raw") {
          response = {
            status: "error",
            code: "device",
            message: "Normalized mode received a raw event",
          };
        } else {
          this.events.shift();
          response = {
            status: "ok",
            bytes: encodeEffectEvent(event, this.limits),
          };
        }
      } else if (command.type === "poll") {
        response = {
          status: "error",
          code: "unsupported",
          message: "Recording provider does not defer effect requests",
        };
      } else {
        const reply = this.queries.get(
          `${command.capability}:${hex(command.bytes)}`,
        );
        response = reply === undefined
          ? { status: "error", code: "device", message: "No query reply" }
          : { status: "ok", bytes: reply.slice() };
      }
      return decodeEffectFrame(
        encodeEffectResponse(
          response,
          request.correlation,
          request.opcode,
          this.limits,
        ),
        this.limits,
      );
    } catch (error) {
      const protocol = error instanceof EffectProtocolError
        ? error
        : new EffectProtocolError("malformed", String(error));
      return decodeEffectFrame(
        encodeEffectResponse(
          { status: "error", code: protocol.code, message: protocol.message },
          request.correlation,
          request.opcode,
          this.limits,
        ),
        this.limits,
      );
    }
  }
}

function hex(bytes: Uint8Array): string {
  let result = "";
  for (const byte of bytes) result += byte.toString(16).padStart(2, "0");
  return result;
}
