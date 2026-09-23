# External effects

Skate programs use ordinary bytes for standard input and standard output. A
host may also provide a separate command channel for terminals, video, sound,
input devices and bounded file operations. The command channel is optional;
text-only programs continue to work on a normal CP/M console.

The provider protocol is synchronous and byte-oriented. It does not add device
registers or host file descriptors to Scheme values. A provider owns the
meaning of each capability and reports unsupported operations as checked
errors.

## Stream format

Version one uses the two-byte marker `ESC ~` (`1B 7E`). A frame contains:

```text
ESC ~ version kind opcode correlation:u16 length:u16 payload crc16:u16
```

Words are little-endian. The CRC is CRC-16/CCITT over the header after the
marker through the payload. The standard payload limit is 1,024 bytes and a
complete frame is at most 1,035 bytes. Providers may select smaller limits.

When text and commands share a serial stream, ordinary text passes through and
literal `ESC` bytes are doubled. `ESC ~` starts a frame. A malformed or
unfinished frame is reported as a protocol error instead of being printed as
text.

## Operations and capabilities

The command set contains text output, control commands, normalized or raw input
events, bounded queries and optional host-side polling. Capability numbers are
owned by the provider. The current Triptych profile reserves `0100` for video,
`0101` for sound and `0200` for the bounded file service. Other values in the
`0200`–`02FF` range are reserved and rejected.

The file service provides staged open, read, write, status, synchronise and
close operations. Paths, handles, chunks and status records are bounded. A
failed write is discarded so the previous committed file remains available.

The CP/M bridge provides direct console bytes where the portable BDOS contract
is sufficient. Full raw framing and device commands require a provider that
can carry every byte, such as a Triptych serial channel. The bridge does not
expose Z80 port addresses or hardware-specific Scheme primitives.

The provider modules and deterministic tests in `tools/` are the reference
host implementation. They can be used by a terminal or harness without
requiring a particular video or sound backend.
