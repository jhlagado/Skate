import {
  DEFAULT_EFFECT_LIMITS,
  type EffectFrame,
  EffectFrameDecoder,
  type EffectLimits,
  EffectProtocolError,
  encodeEffectFrame,
} from "./effect-wire.ts";
import {
  encodeEffectText,
  type MixedEffectItem,
  MixedEffectStreamDecoder,
} from "./effect-stream.ts";

export type CpmEffectMode = "text" | "raw" | "mixed";

export interface CpmConsoleSettings {
  readonly echo: boolean;
  readonly lineEditing: boolean;
  readonly translateCrLf: boolean;
  readonly translateCtrlZ: boolean;
}

export interface CpmByteChannel {
  writeByte(value: number): void;
  readByte(): number | null;
  configure(settings: CpmConsoleSettings): void;
}

/**
 * The two running-program operations used by Skate's `read-char` and
 * `write-char` primitives. The operation meanings and status values belong
 * to z80-services' byteGateway/0 contract; this structural interface keeps
 * Skate independent of a particular provider package.
 */
export interface SkateConsoleByteGateway {
  writeOutputByte(value: number): void;
  readInputByte(): number | null;
}

/** Byte-channel fixture for CP/M and Triptych adapter tests. */
export class RecordingCpmByteChannel implements CpmByteChannel {
  readonly output: number[] = [];
  readonly settings: CpmConsoleSettings[] = [];
  private readonly input: number[];

  constructor(input: Uint8Array = new Uint8Array(0)) {
    this.input = [...input];
  }

  writeByte(value: number): void {
    if (!Number.isInteger(value) || value < 0 || value > 0xff) {
      throw new RangeError("CP/M byte must be an integer from 0 through 255");
    }
    this.output.push(value);
  }

  readByte(): number | null {
    const value = this.input.shift();
    return value === undefined ? null : value;
  }

  configure(settings: CpmConsoleSettings): void {
    this.settings.push({ ...settings });
  }

  feed(bytes: Uint8Array): void {
    this.input.push(...bytes);
  }
}

/**
 * Adapt the shared byte gateway to Skate's CP/M console channel. Echo, line
 * editing, CR/LF and Control-Z policy remain in the surrounding Skate
 * adapter; this class only forwards validated bytes.
 */
export class ByteGatewayCpmByteChannel implements CpmByteChannel {
  readonly settings: CpmConsoleSettings[] = [];

  constructor(private readonly gateway: SkateConsoleByteGateway) {}

  writeByte(value: number): void {
    if (!Number.isInteger(value) || value < 0 || value > 0xff) {
      throw new RangeError("CP/M byte must be an integer from 0 through 255");
    }
    this.gateway.writeOutputByte(value);
  }

  readByte(): number | null {
    const value = this.gateway.readInputByte();
    if (value === null) return null;
    if (!Number.isInteger(value) || value < 0 || value > 0xff) {
      throw new RangeError(
        "byte gateway returned a value outside 0 through 255",
      );
    }
    return value;
  }

  configure(settings: CpmConsoleSettings): void {
    this.settings.push({ ...settings });
  }
}

/** CP/M-side mode and byte adapter for text, raw frames and mixed streams. */
export class CpmEffectAdapter {
  private mode: CpmEffectMode = "text";
  private mixedDecoder: MixedEffectStreamDecoder;
  private rawDecoder: EffectFrameDecoder;

  constructor(
    private readonly channel: CpmByteChannel,
    private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
  ) {
    this.mixedDecoder = new MixedEffectStreamDecoder(limits);
    this.rawDecoder = new EffectFrameDecoder(limits);
    this.enterText();
  }

  enterText(): void {
    this.mode = "text";
    this.resetDecoders();
    this.channel.configure({
      echo: true,
      lineEditing: true,
      translateCrLf: true,
      translateCtrlZ: true,
    });
  }

  enterRaw(): void {
    this.mode = "raw";
    this.resetDecoders();
    this.channel.configure({
      echo: false,
      lineEditing: false,
      translateCrLf: false,
      translateCtrlZ: false,
    });
  }

  enterMixed(): void {
    this.mode = "mixed";
    this.resetDecoders();
    this.channel.configure({
      echo: false,
      lineEditing: false,
      translateCrLf: false,
      translateCtrlZ: false,
    });
  }

  sendText(bytes: Uint8Array): void {
    if (!(bytes instanceof Uint8Array)) {
      throw new EffectProtocolError("malformed", "CP/M text must be bytes");
    }
    if (this.mode === "raw") {
      throw new EffectProtocolError(
        "unsupported",
        "Text is unavailable in raw mode",
      );
    }
    const encoded = this.mode === "mixed" ? encodeEffectText(bytes) : bytes;
    this.write(encoded);
  }

  sendFrame(frame: EffectFrame): void {
    if (this.mode === "text") {
      throw new EffectProtocolError(
        "unsupported",
        "Frames need raw or mixed mode",
      );
    }
    this.write(encodeEffectFrame(frame, this.limits));
  }

  readAvailable(): MixedEffectItem[] {
    const bytes: number[] = [];
    for (;;) {
      const value = this.channel.readByte();
      if (value === null) break;
      if (!Number.isInteger(value) || value < 0 || value > 0xff) {
        throw new EffectProtocolError(
          "malformed",
          "CP/M channel returned a bad byte",
        );
      }
      bytes.push(value);
    }
    if (bytes.length === 0) return [];
    const chunk = Uint8Array.from(bytes);
    if (this.mode === "text") return [{ type: "text", bytes: chunk }];
    if (this.mode === "mixed") return this.mixedDecoder.push(chunk);
    return this.rawDecoder.push(chunk).map((frame) => ({
      type: "frame",
      frame,
    }));
  }

  finish(): void {
    if (this.mode === "mixed") this.mixedDecoder.finish();
    if (this.mode === "raw") this.rawDecoder.finish();
  }

  private write(bytes: Uint8Array): void {
    for (const byte of bytes) this.channel.writeByte(byte);
  }

  private resetDecoders(): void {
    this.mixedDecoder = new MixedEffectStreamDecoder(this.limits);
    this.rawDecoder = new EffectFrameDecoder(this.limits);
  }
}
