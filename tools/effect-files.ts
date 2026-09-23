import {
  checkedBytes,
  decodeEffectFrame,
  DEFAULT_EFFECT_LIMITS,
  type EffectFrame,
  type EffectLimits,
  EffectPendingError,
  EffectProtocolError,
  integer,
  readWord,
  writeWord,
} from "./effect-wire.ts";
import {
  decodeEffectCommand,
  type EffectCommand,
  type EffectResponse,
  encodeEffectResponse,
} from "./effect-commands.ts";
import {
  EffectClient,
  type EffectProvider,
  ProviderTransport,
} from "./effect-client.ts";

/** Capability range reserved for bounded provider file services. */
export const FILE_CAPABILITY = 0x0200;
const FILE_CAPABILITY_END = 0x02ff;
const MAX_FILE_PATH_BYTES = 64;
const FILE_STATUS_BYTES = 6;

export type FileMode = "read" | "write";

export interface FileHandleStatus {
  readonly mode: FileMode;
  readonly position: number;
  readonly length: number;
  readonly dirty: boolean;
}

/** Storage interface used by a file provider; the provider owns path policy. */
export interface FileBackend {
  open(path: string, mode: FileMode): number;
  read(handle: number, maximum: number): Uint8Array;
  write(handle: number, bytes: Uint8Array): void;
  close(handle: number): void;
  sync(handle: number): void;
  status(handle: number): FileHandleStatus;
  /** Discard an in-progress operation after a provider or device failure. */
  abort(handle: number): void;
}

export { MemoryFileBackend } from "./effect-files-memory.ts";

export class FileEffectProvider implements EffectProvider {
  constructor(
    private readonly inner: EffectProvider,
    private readonly backend: FileBackend,
    private readonly limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
  ) {}

  handle(request: EffectFrame): EffectFrame {
    let command: EffectCommand;
    try {
      command = decodeEffectCommand(request);
    } catch (error) {
      return this.error(request, error);
    }
    const capability = command.type === "control" || command.type === "query"
      ? command.capability
      : undefined;
    if (capability === undefined || capability !== FILE_CAPABILITY) {
      if (
        capability !== undefined &&
        capability >= FILE_CAPABILITY &&
        capability <= FILE_CAPABILITY_END
      ) {
        return this.error(
          request,
          new EffectProtocolError(
            "unsupported",
            "File capability is unsupported",
          ),
        );
      }
      return this.inner.handle(request);
    }
    if (command.type !== "control") {
      return this.error(
        request,
        new EffectProtocolError(
          "invalid-command",
          "File operations use control requests",
        ),
      );
    }
    let handle: number | undefined;
    try {
      const operation = decodeFileOperation(command.bytes, this.limits);
      if (operation.type !== "open") handle = operation.handle;
      const bytes = this.execute(operation);
      return this.response(request, { status: "ok", bytes });
    } catch (error) {
      if (handle !== undefined) {
        try {
          this.backend.abort(handle);
        } catch {
          // Preserve the original device error if cleanup also fails.
        }
      }
      return this.error(request, error);
    }
  }

  private execute(operation: FileOperation): Uint8Array {
    switch (operation.type) {
      case "open": {
        const handle = this.backend.open(operation.path, operation.mode);
        validHandle(handle);
        const bytes = new Uint8Array(2);
        writeWord(bytes, 0, handle);
        return bytes;
      }
      case "read": {
        const bytes = checkedBytes(
          this.backend.read(operation.handle, operation.maximum),
          "file read",
        );
        if (bytes.length > operation.maximum) {
          throw new EffectProtocolError(
            "device",
            "File backend returned more bytes than requested",
          );
        }
        return bytes;
      }
      case "write":
        this.backend.write(operation.handle, operation.bytes);
        return new Uint8Array(0);
      case "close":
        this.backend.close(operation.handle);
        return new Uint8Array(0);
      case "sync":
        this.backend.sync(operation.handle);
        return new Uint8Array(0);
      case "status":
        return encodeStatus(this.backend.status(operation.handle));
    }
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

type FileOperation =
  | { readonly type: "open"; readonly path: string; readonly mode: FileMode }
  | { readonly type: "read"; readonly handle: number; readonly maximum: number }
  | {
    readonly type: "write";
    readonly handle: number;
    readonly bytes: Uint8Array;
  }
  | { readonly type: "close"; readonly handle: number }
  | { readonly type: "sync"; readonly handle: number }
  | { readonly type: "status"; readonly handle: number };

function decodeFileOperation(
  bytes: Uint8Array,
  limits: EffectLimits,
): FileOperation {
  if (bytes.length < 1) {
    throw new EffectProtocolError("invalid-command", "File operation is empty");
  }
  const opcode = bytes[0];
  if (opcode === 1) {
    if (bytes.length < 3 || (bytes[1] !== 0 && bytes[1] !== 1)) {
      throw new EffectProtocolError(
        "invalid-command",
        "Open needs a mode and path",
      );
    }
    const pathBytes = bytes.slice(2);
    if (
      pathBytes.length === 0 ||
      pathBytes.length > MAX_FILE_PATH_BYTES ||
      pathBytes.some((value) => value < 0x20 || value === 0x7f)
    ) {
      throw new EffectProtocolError(
        "invalid-command",
        "File path is not valid",
      );
    }
    return {
      type: "open",
      mode: bytes[1] === 0 ? "read" : "write",
      path: decodePath(pathBytes),
    };
  }
  if (bytes.length < 3) {
    throw new EffectProtocolError("invalid-command", "File handle is missing");
  }
  const handle = readWord(bytes, 1);
  if (handle === 0) {
    throw new EffectProtocolError("invalid-command", "File handle is zero");
  }
  if (opcode === 2) {
    if (bytes.length !== 5) {
      throw new EffectProtocolError(
        "invalid-command",
        "Read needs a maximum length",
      );
    }
    const maximum = readWord(bytes, 3);
    if (maximum > limits.maxPayloadBytes - 1) {
      throw new EffectProtocolError(
        "capacity",
        "Read exceeds the response limit",
      );
    }
    return { type: "read", handle, maximum };
  }
  if (opcode === 3) {
    if (bytes.length - 3 > limits.maxPayloadBytes - 1) {
      throw new EffectProtocolError(
        "capacity",
        "Write exceeds the request limit",
      );
    }
    return { type: "write", handle, bytes: bytes.slice(3) };
  }
  if (bytes.length !== 3) {
    throw new EffectProtocolError(
      "invalid-command",
      "File operation has extra bytes",
    );
  }
  if (opcode === 4) return { type: "close", handle };
  if (opcode === 5) return { type: "status", handle };
  if (opcode === 6) return { type: "sync", handle };
  throw new EffectProtocolError(
    "unsupported",
    `File operation ${opcode} is unsupported`,
  );
}

function encodeStatus(status: FileHandleStatus): Uint8Array {
  if (status.mode !== "read" && status.mode !== "write") {
    throw new EffectProtocolError("device", "File status mode is invalid");
  }
  if (typeof status.dirty !== "boolean") {
    throw new EffectProtocolError(
      "device",
      "File status dirty flag is invalid",
    );
  }
  try {
    integer(status.position, "file position", 0xffff);
    integer(status.length, "file length", 0xffff);
  } catch (error) {
    throw new EffectProtocolError("capacity", String(error));
  }
  const bytes = new Uint8Array(FILE_STATUS_BYTES);
  bytes[0] = status.mode === "write" ? 1 : 0;
  bytes[1] = status.dirty ? 1 : 0;
  writeWord(bytes, 2, status.position);
  writeWord(bytes, 4, status.length);
  return bytes;
}

/** Client for the bounded file operations carried by the provider boundary. */
export class EffectFileClient {
  constructor(private readonly client: EffectClient) {}

  open(path: string, mode: FileMode): number {
    if (typeof path !== "string") {
      throw new RangeError("file path must be text");
    }
    if (mode !== "read" && mode !== "write") {
      throw new RangeError("file mode must be read or write");
    }
    const pathBytes = encodePath(path);
    if (
      pathBytes.length === 0 ||
      pathBytes.length > MAX_FILE_PATH_BYTES ||
      pathBytes.some((value) => value < 0x20 || value === 0x7f)
    ) {
      throw new RangeError("File path is not valid");
    }
    const payload = new Uint8Array(pathBytes.length + 2);
    payload[0] = 1;
    payload[1] = mode === "write" ? 1 : 0;
    payload.set(pathBytes, 2);
    const result = this.command(payload);
    if (result.length !== 2) {
      throw new EffectProtocolError("malformed", "Open reply is invalid");
    }
    const handle = readWord(result, 0);
    if (handle === 0) {
      throw new EffectProtocolError("malformed", "Open returned zero handle");
    }
    return handle;
  }

  read(handle: number, maximum: number): Uint8Array {
    validHandle(handle);
    integer(maximum, "read length", 0xffff);
    const payload = new Uint8Array(5);
    payload[0] = 2;
    writeWord(payload, 1, handle);
    writeWord(payload, 3, maximum);
    const bytes = this.command(payload);
    if (bytes.length > maximum) {
      throw new EffectProtocolError(
        "malformed",
        "File provider returned more bytes than requested",
      );
    }
    return bytes;
  }

  write(handle: number, bytes: Uint8Array): void {
    validHandle(handle);
    checkedBytes(bytes, "file write");
    const payload = new Uint8Array(bytes.length + 3);
    payload[0] = 3;
    writeWord(payload, 1, handle);
    payload.set(bytes, 3);
    this.expectEmpty(this.command(payload));
  }

  close(handle: number): void {
    this.expectEmpty(this.command(handlePayload(4, handle)));
  }

  sync(handle: number): void {
    this.expectEmpty(this.command(handlePayload(6, handle)));
  }

  status(handle: number): FileHandleStatus {
    const bytes = this.command(handlePayload(5, handle));
    if (bytes.length !== FILE_STATUS_BYTES) {
      throw new EffectProtocolError("malformed", "Status reply is invalid");
    }
    if (
      (bytes[0] !== 0 && bytes[0] !== 1) ||
      (bytes[1] !== 0 && bytes[1] !== 1)
    ) {
      throw new EffectProtocolError("malformed", "Status flags are invalid");
    }
    return {
      mode: bytes[0] === 1 ? "write" : "read",
      dirty: bytes[1] === 1,
      position: readWord(bytes, 2),
      length: readWord(bytes, 4),
    };
  }

  private command(payload: Uint8Array): Uint8Array {
    const response = this.client.request({
      type: "control",
      capability: FILE_CAPABILITY,
      bytes: payload,
    });
    if (response.status === "ok") return response.bytes;
    if (response.status === "pending") {
      throw new EffectPendingError(response.task);
    }
    if (response.status === "error") {
      throw new EffectProtocolError(response.code, response.message);
    }
    throw new EffectProtocolError("empty", "File operation returned no result");
  }

  private expectEmpty(bytes: Uint8Array): void {
    if (bytes.length !== 0) {
      throw new EffectProtocolError(
        "malformed",
        "File operation returned bytes",
      );
    }
  }
}

function handlePayload(opcode: number, handle: number): Uint8Array {
  validHandle(handle);
  const payload = new Uint8Array(3);
  payload[0] = opcode;
  writeWord(payload, 1, handle);
  return payload;
}

function validHandle(handle: number): void {
  integer(handle, "file handle", 0xffff);
  if (handle === 0) throw new RangeError("file handle must be nonzero");
}

function decodePath(bytes: Uint8Array): string {
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(
      bytes,
    );
  } catch {
    throw new EffectProtocolError("invalid-command", "File path is not UTF-8");
  }
}

function encodePath(path: string): Uint8Array {
  const bytes = new TextEncoder().encode(path);
  try {
    const roundTrip = new TextDecoder("utf-8", {
      fatal: true,
      ignoreBOM: true,
    }).decode(bytes);
    if (roundTrip !== path) {
      throw new RangeError("File path is not well formed");
    }
  } catch {
    throw new RangeError("File path is not well formed");
  }
  return bytes;
}

export function createFileClient(
  provider: EffectProvider,
  backend: FileBackend,
  limits: EffectLimits = DEFAULT_EFFECT_LIMITS,
): EffectFileClient {
  return new EffectFileClient(
    new EffectClient(
      new ProviderTransport(
        new FileEffectProvider(provider, backend, limits),
        limits,
      ),
      limits,
    ),
  );
}
