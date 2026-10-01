/** Small provider-side event helpers kept separate from Scheme text ports. */

import type { EffectClient } from "./effect-client.ts";
import type { EffectEvent } from "./effect-events.ts";

export const EVENT_EMPTY = Symbol("skate-event-empty");

export type NormalizedEvent = Exclude<EffectEvent, { readonly type: "raw" }>;
export type KeyEvent = Extract<EffectEvent, { readonly type: "key" }>;
export type PointerEvent = Extract<EffectEvent, {
  readonly type: "pointer";
}>;

/** Read one normalized event without turning an empty queue into an event. */
export class EventLibrary {
  constructor(private readonly client: EffectClient) {}

  read(): NormalizedEvent | typeof EVENT_EMPTY {
    const event = this.client.readEvent("normalized");
    if (event === null) return EVENT_EMPTY;
    if (event.type === "raw") {
      throw new Error("normalized event provider returned raw data");
    }
    return event;
  }

  readText(): string | typeof EVENT_EMPTY {
    const event = this.read();
    if (event === EVENT_EMPTY) return event;
    if (event.type === "text") return event.text;
    if (event.type === "key" && event.text !== undefined) return event.text;
    return "";
  }

  readKey(): KeyEvent | typeof EVENT_EMPTY | null {
    const event = this.read();
    if (event === EVENT_EMPTY || event.type === "key") return event;
    return null;
  }

  readPointer(): PointerEvent | typeof EVENT_EMPTY | null {
    const event = this.read();
    if (event === EVENT_EMPTY || event.type === "pointer") return event;
    return null;
  }
}

export function isKeyEvent(event: NormalizedEvent): event is KeyEvent {
  return event.type === "key";
}

export function isPointerEvent(
  event: NormalizedEvent,
): event is PointerEvent {
  return event.type === "pointer";
}
