/** Provider-neutral ANSI and Triptych command helpers for P3. */
import { EffectClient } from "./effect-protocol.ts";

const encoder = new TextEncoder();

export const ANSI_TERMINAL = Object.freeze({
  clear: "\x1b[2J",
  home: "\x1b[H",
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  underline: "\x1b[4m",
  reverse: "\x1b[7m",
  eraseLine: "\x1b[2K",
  cursorUp: "\x1b[A",
  cursorDown: "\x1b[B",
  cursorRight: "\x1b[C",
  cursorLeft: "\x1b[D",
});

export const ANSI_FOREGROUND = Object.freeze({
  black: "\x1b[30m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
  white: "\x1b[37m",
});

export const ANSI_BACKGROUND = Object.freeze({
  black: "\x1b[40m",
  red: "\x1b[41m",
  green: "\x1b[42m",
  yellow: "\x1b[43m",
  blue: "\x1b[44m",
  magenta: "\x1b[45m",
  cyan: "\x1b[46m",
  white: "\x1b[47m",
});

export type AnsiColor = keyof typeof ANSI_FOREGROUND;

export interface TerminalLibrary {
  readonly clear: () => void;
  readonly home: () => void;
  readonly reset: () => void;
  readonly bold: () => void;
  readonly underline: () => void;
  readonly reverse: () => void;
  readonly eraseLine: () => void;
  readonly cursorUp: () => void;
  readonly cursorDown: () => void;
  readonly cursorRight: () => void;
  readonly cursorLeft: () => void;
  readonly cursor: (row: number, column: number) => void;
  readonly foreground: (color: AnsiColor) => void;
  readonly background: (color: AnsiColor) => void;
  readonly write: (text: string) => void;
  readonly line: (text: string) => void;
  /** Send a provider-specific VDP command through the P2 control capability. */
  readonly vdp: (
    capability: number,
    command: number,
    bytes?: Uint8Array,
  ) => void;
}

function control(client: EffectClient, sequence: string): void {
  client.sendControl(0, encoder.encode(sequence));
}

function coordinate(value: number, name: string): number {
  if (!Number.isInteger(value) || value < 1 || value > 0xffff) {
    throw new RangeError(`${name} must be an integer from 1 through 65535`);
  }
  return value;
}

function vdp(
  client: EffectClient,
  capability: number,
  command: number,
  bytes: Uint8Array = new Uint8Array(0),
): void {
  if (!Number.isInteger(command) || command < 0 || command > 0xff) {
    throw new RangeError("VDP command must be a byte");
  }
  const payload = new Uint8Array(bytes.length + 1);
  payload[0] = command;
  payload.set(bytes, 1);
  client.sendControl(capability, payload);
}

/** Build the host reference library over any P2 provider. */
export function createTerminalLibrary(client: EffectClient): TerminalLibrary {
  return {
    clear: () => control(client, ANSI_TERMINAL.clear),
    home: () => control(client, ANSI_TERMINAL.home),
    reset: () => control(client, ANSI_TERMINAL.reset),
    bold: () => control(client, ANSI_TERMINAL.bold),
    underline: () => control(client, ANSI_TERMINAL.underline),
    reverse: () => control(client, ANSI_TERMINAL.reverse),
    eraseLine: () => control(client, ANSI_TERMINAL.eraseLine),
    cursorUp: () => control(client, ANSI_TERMINAL.cursorUp),
    cursorDown: () => control(client, ANSI_TERMINAL.cursorDown),
    cursorRight: () => control(client, ANSI_TERMINAL.cursorRight),
    cursorLeft: () => control(client, ANSI_TERMINAL.cursorLeft),
    cursor: (row, column) =>
      control(
        client,
        `\x1b[${coordinate(row, "row")};${coordinate(column, "column")}H`,
      ),
    foreground: (color) => control(client, ANSI_FOREGROUND[color]),
    background: (color) => control(client, ANSI_BACKGROUND[color]),
    write: (text) => client.sendText(text),
    line: (text) => {
      client.sendText(text);
      client.sendText("\r\n");
    },
    vdp: (capability, command, bytes) =>
      vdp(client, capability, command, bytes),
  };
}
