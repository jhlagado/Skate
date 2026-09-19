import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { inspectSources, lineStatus, physicalLines } from "./check-source.ts";

Deno.test("file-size gate counts comments and blank lines under all newline conventions", () => {
  assert.equal(physicalLines(""), 0);
  assert.equal(physicalLines("; purpose\n\nRET\n"), 3);
  assert.equal(physicalLines("; purpose\r\n\r\nRET"), 3);
  assert.equal(physicalLines("; purpose\r\rRET\r"), 3);
  assert.equal(physicalLines("RET"), 1);
});

Deno.test("source traversal audits filenames containing URL syntax", async () => {
  const root = await Deno.makeTempDir({
    dir: "/tmp",
    prefix: "skate-quality-",
  });
  try {
    const directory = `${root}/src/parser#draft`;
    await Deno.mkdir(directory, { recursive: true });
    await Deno.writeTextFile(
      `${directory}/name%20.asm`,
      "; explained\n".repeat(1001),
    );
    const counts = await inspectSources(pathToFileURL(`${root}/`));
    assert.deepEqual(counts, [{
      path: "src/parser#draft/name%20.asm",
      lines: 1001,
      status: "fail",
    }]);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("normal and hard file limits distinguish exact boundary and first excess", () => {
  for (
    const [lines, status] of [
      [499, "ok"],
      [500, "ok"],
      [501, "review"],
      [999, "review"],
      [1000, "review"],
      [1001, "fail"],
    ] as const
  ) {
    const source = "; comment remains part of readability budget\n".repeat(
      lines,
    );
    assert.equal(lineStatus(physicalLines(source)), status);
    assert.equal(lineStatus(physicalLines(source.slice(0, -1))), status);
  }
});
