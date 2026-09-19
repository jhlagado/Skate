/** Diagnostic host reader command; output is an event trace, not an object file. */
import { SourceReader } from "./reader.ts";

function* fileBytes(file: Deno.FsFile): Generator<number> {
  const buffer = new Uint8Array(256);
  for (;;) {
    const length = file.readSync(buffer);
    if (length === null) return;
    yield* buffer.subarray(0, length);
  }
}

if (import.meta.main) {
  if (Deno.args.length !== 1) {
    console.error("Usage: deno task read path/to/source.sk8");
    Deno.exit(2);
  }
  try {
    using file = Deno.openSync(Deno.args[0], { read: true });
    const reader = new SourceReader(fileBytes(file), Deno.args[0]);
    for (const event of reader.events()) console.log(JSON.stringify(event));
    console.log(
      JSON.stringify({
        kind: "complete",
        symbols: reader.symbols.count,
        strings: reader.strings.count,
      }),
    );
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exitCode = 1;
  }
}
