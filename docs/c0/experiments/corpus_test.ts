import assert from "node:assert/strict";
import {
  checkCorpusFixture,
  DATA_COUNT,
  GLOBAL_COUNT,
  PART_NAMES,
} from "./corpus.ts";

Deno.test("C0 weather corpus is checked in, ordered and lexically valid", async () => {
  const metrics = await checkCorpusFixture();
  assert.deepEqual(metrics.manifestParts, PART_NAMES);
  assert.equal(metrics.globalCount, GLOBAL_COUNT);
  assert.ok(metrics.sourceBytes >= 8192);
  assert.ok(metrics.sourceBytes < 65535);
  assert.deepEqual(metrics.partForms, {
    "DATA01.SK8": 224,
    "GROUPS.SK8": 14,
    "REPORTS.SK8": 19,
  });
  assert.ok(metrics.partBytes["DATA01.SK8"]! < 65535);
  assert.ok(metrics.partBytes["GROUPS.SK8"]! < 65535);
  assert.ok(metrics.partBytes["REPORTS.SK8"]! < 65535);
  assert.ok(metrics.maxListDepth >= 8);
  assert.ok(metrics.referencesToLaterGlobals > 0);
  assert.ok(metrics.allGlobalsUsed);
  assert.ok(metrics.readerSymbols > 0);
  assert.equal(metrics.readerStrings, 0);
  assert.equal(metrics.readerStringBytes, 0);
  assert.equal(metrics.quotedLiteralOccurrences, DATA_COUNT + 1);
  assert.equal(metrics.distinctQuotedLiteralContents, DATA_COUNT + 1);
  assert.ok(metrics.numericLiteralOccurrences > DATA_COUNT * 4);
  assert.ok(metrics.ordinaryGlobalNameMax <= 16);
  assert.ok(metrics.maxIdentifierLength <= 31);
  assert.ok(metrics.unmeasured.length >= 3);
  for (
    const day of Array.from({ length: DATA_COUNT }, (_, index) => index + 1)
  ) {
    assert.equal(
      metrics
        .dataReferenceCounts[`daily-sample-${String(day).padStart(3, "0")}`],
      1,
    );
  }
});

Deno.test("C0 expected output is derived from the weather specification", async () => {
  const metrics = await checkCorpusFixture();
  const rows = Array.from({ length: DATA_COUNT }, (_, index) => {
    const day = index + 1;
    const low = (day % 17) - 8;
    return { day, low, high: low + 12 + (day % 5), rain: day % 20 };
  });
  const rain = rows.reduce((sum, row) => sum + row.rain, 0);
  const high = rows.reduce((sum, row) => sum + row.high, 0);
  const hot = rows.filter((row) => row.high > 20).length;
  const wet = rows.filter((row) => row.rain > 0).length;
  const hotHeavyRain =
    rows.filter((row) => row.high > 20 && row.rain > 10).length;
  const summary = `(${rows.length} ${rain} ${high} ${hot} ${wet} ` +
    `${rows[0]!.day} ${rows[0]!.low} ${rows.length} ${hotHeavyRain})`;
  assert.deepEqual(metrics.expected, {
    count: rows.length,
    totalRain: rain,
    totalHigh: high,
    hotDays: hot,
    wetDays: wet,
    hotHeavyRain,
    firstDay: rows[0]!.day,
    firstLow: rows[0]!.low,
    counterResult: rows.length,
    outputs: {
      r: `${rain}\r\n37\r\n#t\r\n`,
      R: `${rain}\r\n37\r\n#t\r\n`,
      h: `${hot}\r\n37\r\n#t\r\n`,
      other: `${summary}\r\n37\r\n#t\r\n`,
    },
  });
  assert.equal(
    metrics.expected.outputs.other,
    "(224 2100 3120 26 213 1 -7 224 12)\r\n37\r\n#t\r\n",
  );
  assert.equal(metrics.referencesToLaterGlobals, 2);
});

Deno.test("C0 evidence JSON matches the checked-in source bytes", async () => {
  const metrics = await checkCorpusFixture();
  const evidence = JSON.parse(
    await Deno.readTextFile(new URL("./corpus-evidence.json", import.meta.url)),
  );
  assert.deepEqual(evidence, metrics);
});
