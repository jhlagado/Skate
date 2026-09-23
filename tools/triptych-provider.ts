/** Provider-side routing for the logical Triptych video and sound handles. */

import {
  decodeEffectCommand,
  type EffectCommand,
  type EffectResponse,
  encodeEffectResponse,
} from "./effect-commands.ts";
import {
  decodeEffectFrame,
  DEFAULT_EFFECT_LIMITS,
  type EffectFrame,
  type EffectLimits,
  EffectProtocolError,
} from "./effect-wire.ts";
import {
  EffectClient,
  type EffectProvider,
  ProviderTransport,
  RecordingEffectProvider,
} from "./effect-client.ts";
import type { EffectEvent } from "./effect-events.ts";

/** Logical handles; a backend may map them to its own physical interface. */
export const TRIPTYCH_CAPABILITY = Object.freeze({
  video: 0x0100,
  sound: 0x0101,
});
const TRIPTYCH_CAPABILITY_END = 0x01ff;

export type TriptychDomain = keyof typeof TRIPTYCH_CAPABILITY;

export interface TriptychCommand {
  readonly domain: TriptychDomain;
  readonly bytes: Uint8Array;
}

export interface TriptychBackend {
  submit(domain: TriptychDomain, bytes: Uint8Array): Uint8Array;
}

/** Deterministic backend used to compare provider transcripts. */
export class RecordingTriptychBackend implements TriptychBackend {
  readonly transcript: TriptychCommand[] = [];

  constructor(
    private readonly replies: Partial<Record<TriptychDomain, Uint8Array>> = {},
  ) {}

  submit(domain: TriptychDomain, bytes: Uint8Array): Uint8Array {
    const command = { domain, bytes: bytes.slice() };
    this.transcript.push(command);
    return this.replies[domain]?.slice() ?? new Uint8Array(0);
  }
}

/** Route logical Triptych controls while retaining ordinary provider services. */
export class TriptychEffectProvider implements EffectProvider {
  private readonly general: RecordingEffectProvider;

  constructor(
    private readonly backend: TriptychBackend,
    private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
  ) {
    this.general = new RecordingEffectProvider(limits);
  }

  queueEvent(
    event: EffectEvent,
  ): void {
    this.general.queueEvent(event);
  }

  setQueryReply(
    capability: number,
    request: Uint8Array,
    reply: Uint8Array,
  ): void {
    this.general.setQueryReply(capability, request, reply);
  }

  handle(request: EffectFrame): EffectFrame {
    let command: EffectCommand;
    try {
      command = decodeEffectCommand(request);
    } catch (error) {
      return this.error(request, error);
    }
    if (command.type !== "control") return this.general.handle(request);
    const domain = this.domain(command.capability);
    if (domain === undefined) {
      if (
        command.capability < 0x0100 ||
        command.capability > TRIPTYCH_CAPABILITY_END
      ) {
        return this.general.handle(request);
      }
      return this.error(
        request,
        new EffectProtocolError(
          "unsupported",
          `Triptych capability ${command.capability} is unsupported`,
        ),
      );
    }
    try {
      const bytes = this.backend.submit(domain, command.bytes);
      return this.response(request, { status: "ok", bytes });
    } catch (error) {
      return this.error(request, error);
    }
  }

  private domain(capability: number): TriptychDomain | undefined {
    if (capability === TRIPTYCH_CAPABILITY.video) return "video";
    if (capability === TRIPTYCH_CAPABILITY.sound) return "sound";
    return undefined;
  }

  private response(
    request: EffectFrame,
    response: EffectResponse,
  ): EffectFrame {
    return decodeEffectFrame(
      encodeEffectResponse(
        response,
        request.correlation,
        request.opcode,
        this.limits,
      ),
      this.limits,
    );
  }

  private error(request: EffectFrame, error: unknown): EffectFrame {
    const protocol = error instanceof EffectProtocolError
      ? error
      : new EffectProtocolError("device", String(error));
    return this.response(request, {
      status: "error",
      code: protocol.code,
      message: protocol.message,
    });
  }
}

/** Build a client connected to a logical Triptych backend. */
export function createTriptychClient(backend: TriptychBackend): EffectClient {
  return new EffectClient(
    new ProviderTransport(new TriptychEffectProvider(backend)),
  );
}
