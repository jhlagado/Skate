# Input and output

A Scheme port identifies a stream and its direction. The standard input,
output and error ports use console byte services. File ports use the same
Scheme operations with a CP/M file behind them.

```scheme
(define output (open-output-file "HELLO.TXT"))
(display "Hello" output)
(newline output)
(close-port output)

(define input (open-input-file "HELLO.TXT"))
(display (read-char input))
(close-port input)
```

`current-input-port`, `current-output-port` and `current-error-port` return
standard ports. Character and datum operations accept an explicit port;
omitting it selects the corresponding current port. `read` parses a Scheme
datum, while `read-char` returns one byte character. `eof-object?` recognises
the end-of-input value. `write` prints datum syntax that `read` accepts:
strings are quoted with `\"`, `\\`, `\n`, `\r`, `\t` and `\xHH;` escapes,
and characters use `#\space`, `#\newline`, `#\xHH` or the character itself.
`display` prints strings and characters raw, including inside lists and
vectors. Vectors print as `#(...)`, procedures and escape procedures as
`#<procedure>` and ports as `#<port>`. Each port keeps its own lookahead and
end-of-file state.

## Files

`open-input-file` and `open-output-file` open text files.
`open-input-binary-file` and `open-output-binary-file` preserve physical bytes.
The native adapter permits four files open at a time, in any mix of input and
output, with sequential access and current-drive CP/M 8.3 names.  Each open
file takes one 256-byte heap page for its FCB, record buffer and lookahead,
and closing it returns the page, so a program pays for a file only while it
is open.  Each input keeps its own lookahead and end-of-file state, so reads
from several inputs can be interleaved freely. Lowercase names are folded
to uppercase. Drive prefixes, wildcards, directories, spaces and the CP/M
delimiters `<>=,;[]|` are rejected, as is opening for output the file that is
currently open for input.

Text input folds CR, LF and CR/LF into logical newlines and treats Control-Z
as EOF. Text output expands a newline to CR/LF. Binary ports preserve these
bytes. CP/M stores whole 128-byte records, so binary input includes the final
record's padding; applications needing exact lengths must record them in the
file format. Output replaces an existing file. Closing flushes its last
record; this native replacement does not provide the transactional guarantees
of the separate host file provider.

Use `close-port` explicitly; closing a file port that is already closed does
nothing. An open output file is also flushed and closed when the program ends
or stops with a runtime error. Invalid directions, operations on closed ports
and failed file operations take the checked runtime-error path. Opening a fifth file is a
runtime error.  Append and seeking are not implemented.

## Source helpers

Including `IO.SK8` from `libraries/io.sk8` supplies these procedures:

| Default port | Explicit ports |
| --- | --- |
| `read-line` | `read-line-from input` |
| `write-line text` | `write-line-to text output` |
| `prompt text` | `prompt-to text output` |
| `copy-stream` | `copy-stream-from-to input output` |

A line excludes its newline. EOF ends an unterminated line, or returns the EOF
object if no characters were read. Lines are limited to 255 bytes; longer
input raises a checked error. The implementation appends one character at a
time, so its allocation cost matters for sustained input.

## Providers and command streams

The CP/M console provider forwards bytes to BDOS. Replacement providers can
send them to another terminal or host. ANSI sequences are ordinary bytes to
Skate; the receiving terminal decides how to interpret them.

Video and sound libraries can encode commands for a receiving device over a
byte stream. Those command formats are separate from Scheme port operations.
A file provider may likewise use a request/reply protocol, but the native
CP/M adapter calls local file services directly. See the
[external-effects contract](public/external-effects.md).

`deno task test:cpm:console` compiles and runs the console, datum, library and
file cases, then checks the written disk records. Host-provider tests exercise
the alternative transport and handle contracts separately.
