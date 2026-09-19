import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssembly } from "../tests/z80.ts";
import { encodeNobj1, parseNobj1 } from "@jhlagado/z80-tool-services";
import { assembleTriptychCpuFirmware } from "../../triptych/tools/cpm22-native-image.mjs";
import {
  installCpm22File,
  readCpm22File,
} from "../../triptych/tools/lib/cpm22-disk.mjs";
import { linkTargetStreams, toPhysicalNobjRecords } from "./target-linker.ts";
import { SKATE_TPA_PROFILES } from "./m7-compiler.ts";

const environmentLimit = "((lambda (x) (begin " +
  Array.from({ length: 17 }, () => "(lambda () x)").join(" ") +
  ")) 1)";
const macroTableLimit = Array.from(
  { length: 9 },
  (_, index) => `(define-syntax m${index} (syntax-rules () ((m${index} x) x)))`,
).join(" ");
const arenaLimit = "(" + "1 ".repeat(600) + ")";

const triptychRoot = fileURLToPath(new URL("../../triptych/", import.meta.url));
const require = createRequire(import.meta.url);
const { TriptychCpu } = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);
const firmware = await assembleTriptychCpuFirmware(triptychRoot);
const sourceDisk = await Deno.readFile(
  join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
);
const systemDisk = Uint8Array.from(sourceDisk);
systemDisk.set(firmware.ccp, 0x0000);
systemDisk.set(firmware.bdos, 0x0800);
systemDisk.set(firmware.bios, 0x1600);
const backing = new Uint8Array(Math.ceil(systemDisk.length / 512) * 512);
backing.set(systemDisk);

const compiler = await loadAssembly("compiler/skate.asm");
assert.equal(compiler.image.base, 0);
assert.equal(compiler.address("N6MAIN"), 0x0100);
assert.ok(compiler.address("N4OBJEND") < 0xa000);
const compilerBytes = compiler.image.bytes.slice(0x0100);
let disk = installCpm22File(backing, {
  name: "SKATE.COM",
  bytes: compilerBytes,
  padByte: 0x1a,
});

for (
  const [name, text] of [
    ["ID.SK8", "((lambda (x) x) 42)"],
    ["ADD.SK8", "(+ 40 2)"],
    ["NESTED.SK8", "(+ (+ 1 2) 3)"],
    ["CONS.SK8", "(cons 40 2)"],
    [
      "MACRO.SK8",
      "(define-syntax inc (syntax-rules () ((inc x) (+ x 1)))) (inc 41)",
    ],
    ["QUOTE.SK8", "(quote (1 2))"],
    ["SUM.SK8", "((lambda (a b) (+ a b)) 17 25)"],
    ["HIGH.SK8", "((lambda (f x) (+ (f x) (f x))) (lambda (v) (+ v 1)) 20)"],
    ["TAIL.SK8", "((lambda (x) (begin 0 (+ x 1))) 41)"],
    ["CAPTURE.SK8", "(((lambda (x) (lambda () x)) 42))"],
    [
      "SET.SK8",
      "(((lambda (x) (lambda () (begin (set! x (+ x 1)) x))) 41))",
    ],
    [
      "SHARE.SK8",
      "((lambda (x) (begin ((lambda () (set! x (+ x 1)))) ((lambda () x)))) 41)",
    ],
    [
      "LOOP.SK8",
      "((lambda (self n) (if (zero? n) 42 (self self (- n 1)))) " +
      "(lambda (self n) (if (zero? n) 42 (self self (- n 1)))) 30000)",
    ],
    ["CAR.SK8", "(car '(40 . 2))"],
    ["CDR.SK8", "(cdr '(1 . 42))"],
    ["LISTCAR.SK8", "(car (list 40 2))"],
    ["CONSCDR.SK8", "(cdr (cons 1 42))"],
    [
      "GLOBALS.SK8",
      "(define (inc value) (+ value 1)) (define answer (inc 41)) answer",
    ],
    ["FORWARD.SK8", "(define get (lambda () answer)) (define answer 42) (get)"],
    [
      "SHADOW.SK8",
      "(define value 1) (set! value 41) " +
      "(define + (lambda (left right) (- left right))) (+ 5 3)",
    ],
    ["MACLIM.SK8", macroTableLimit],
    ["ARENA.SK8", arenaLimit],
    ["LET.SK8", "(let ((left 40) (right 2)) (+ left right))"],
    ["COND.SK8", "(cond ((= 1 2) 0) ((= 2 2) 42) (else 7))"],
    ["AND.SK8", "(and #t 1 2)"],
    ["OR.SK8", "(or #f 42)"],
    ["PRED.SK8", "(boolean? #t)"],
    ["ARITY.SK8", "((lambda (x) x) 1 2)"],
    ["OVERLOOP.SK8", "(+ 32767 1)"],
    ["ENVFULL.SK8", environmentLimit],
    [
      "BADREF.SK8",
      "(define get (lambda () answer)) (get) (define answer 42)",
    ],
  ]
) {
  disk = installCpm22File(disk, {
    name,
    bytes: new TextEncoder().encode(text + "\x1a"),
    padByte: 0x1a,
  });
}

const machine = new TriptychCpu(firmware.bootRom);
let transcript = "";
const decoder = new TextDecoder("ascii");
function runUntilPrompt(offset, description) {
  for (let slice = 0; slice < 1800; slice += 1) {
    const status = machine.run_slice(50_000, 500_000);
    transcript += decoder.decode(machine.take_serial_output());
    assert.notEqual(status, 0, `CP/M halted while waiting for ${description}`);
    if (transcript.length > offset && transcript.endsWith("A>")) return;
  }
  throw new Error(
    `Timed out waiting for ${description}: ${transcript.slice(-500)}`,
  );
}
function runCommand(command, expected, description) {
  const start = transcript.length;
  assert.ok(
    machine.enqueue_serial_input(new TextEncoder().encode(command + "\r")),
  );
  runUntilPrompt(start, description);
  const output = transcript.slice(start);
  assert.ok(output.includes(expected), JSON.stringify(output));
  return output;
}
function eraseGenerated(base) {
  runCommand("ERA " + base + ".COM", "", base + " COM cleanup");
  runCommand("ERA " + base + ".NOB", "", base + " NOB cleanup");
}
function assertAbsent(image, name) {
  assert.throws(() => readCpm22File(image, name), /is absent/);
}
function assertGeneratedCom(image, name, messageBytes, codeBytes = 128) {
  const bytes = readCpm22File(image, name);
  const logicalLength = codeBytes + messageBytes.length;
  assert.deepEqual(
    [...bytes.slice(14, 17)],
    [1, messageBytes.length & 0xff, messageBytes.length >> 8],
    `${name}: launch-stub message length is wrong`,
  );
  assert.equal(
    bytes.length >= logicalLength,
    true,
    `${name}: COM image is shorter than its launch stub and message`,
  );
  assert.deepEqual(
    [...bytes.slice(codeBytes, logicalLength)],
    [...messageBytes],
    `${name}: COM message payload is wrong`,
  );
  assert.equal(
    bytes[logicalLength],
    0x1a,
    `${name}: COM image is not padded immediately after its message`,
  );
}

const bootDescriptor = Uint8Array.from([
  1,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0x80,
  2,
  0xcb,
  2,
  8,
  0,
  16,
  0,
  0,
  16,
  16,
  0,
  16,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
]);
const storageDescriptor = Uint8Array.from([
  0,
  0x11,
  0x88,
  0x11,
  0,
  0x11,
  0x20,
  0x11,
  0x20,
  0x11,
  0x30,
  0x11,
  0x40,
  0x11,
  2,
  0,
  0x48,
  0x11,
  16,
  0,
]);
const topDescriptor = Uint8Array.from([0, 0, 0, 0, 0, 0, 0, 0]);

const runtimeContract = {
  key: "org.skate.runtime",
  majorVersion: 2,
  minorVersion: 0,
};

async function numericProviderObject() {
  const assembled = await loadAssembly("tests/nobj-link-runtime-4200.asm");
  const base = 0x4200;
  const bytes = assembled.image.bytes.slice(base);
  const serviceNames = [
    ["numeric.classify", "nclass"],
    ["numeric.add", "nadd"],
    ["numeric.sub", "nsub"],
    ["numeric.mul", "nmul"],
    ["numeric.div", "ndiv"],
    ["numeric.negate", "nneg"],
    ["heap.initialize", "hinit"],
    ["collector.configure", "gcset"],
    ["execution.initialize", "rtinit"],
    ["execution.packet-new", "rtpknew"],
    ["execution.invoke", "rtinvoke"],
    ["pairs.cons", "rtconsp"],
    ["execution.literal-init", "rtlit"],
  ];
  const symbols = serviceNames.map(([_, name], index) => {
    const address = assembled.symbols.get(name);
    assert.notEqual(address, undefined, `provider is missing ${name}`);
    return {
      id: index + 1,
      binding: "local",
      valueKind: 1,
      sectionId: 1,
      offset: address - base,
    };
  });
  const object = encodeNobj1({
    begin: { targetId: 1 },
    contracts: [{ id: 1, ...runtimeContract, data: new Uint8Array(4) }],
    regions: [{
      id: 1,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: 0x0100,
      capacity: 0xe300,
      imageFill: 0,
      permissions: 7,
      banked: false,
    }],
    sections: [{
      id: 1,
      storageKind: 1,
      permissions: 7,
      alignment: 1,
      length: bytes.length,
      runRegionId: 1,
      runPlacement: "fixed",
      runOffset: base - 0x0100,
      loadPlacement: "same",
      loadRegionId: 1,
      loadOffset: 0,
      fill: 0,
    }],
    ranges: [],
    images: [{ sectionId: 1, offset: 0, bytes }],
    patches: [],
    symbols,
    relocations: [],
    metadata: [],
    layout: { mode: "module", entrySymbolId: 1 },
  });
  return {
    bytes: object,
    services: serviceNames.map(([key], index) => ({
      key,
      symbolId: index + 1,
    })),
    addresses: Object.fromEntries(
      serviceNames.map(([key, name]) => [key, assembled.symbols.get(name)]),
    ),
  };
}

try {
  machine.install_drive(0, disk, true);
  runUntilPrompt(0, "the boot prompt");
  for (
    const [sourceName, outputName, expected] of [
      ["ID.SK8", "ID.COM", "42\r\n"],
      ["ADD.SK8", "ADD.COM", "42\r\n"],
      ["NESTED.SK8", "NESTED.COM", "6\r\n"],
      ["CONS.SK8", "CONS.COM", "(40 . 2)\r\n"],
      ["MACRO.SK8", "MACRO.COM", "42\r\n"],
      ["SUM.SK8", "SUM.COM", "42\r\n"],
      ["HIGH.SK8", "HIGH.COM", "42\r\n"],
      ["TAIL.SK8", "TAIL.COM", "42\r\n"],
      ["CAPTURE.SK8", "CAPTURE.COM", "42\r\n"],
      ["SET.SK8", "SET.COM", "42\r\n"],
      ["SHARE.SK8", "SHARE.COM", "42\r\n"],
      ["LOOP.SK8", "LOOP.COM", "42\r\n"],
      ["CAR.SK8", "CAR.COM", "40\r\n"],
      ["CDR.SK8", "CDR.COM", "42\r\n"],
      ["LISTCAR.SK8", "LISTCAR.COM", "40\r\n"],
      ["CONSCDR.SK8", "CONSCDR.COM", "42\r\n"],
      ["GLOBALS.SK8", "GLOBALS.COM", "42\r\n"],
      ["FORWARD.SK8", "FORWARD.COM", "42\r\n"],
      ["SHADOW.SK8", "SHADOW.COM", "2\r\n"],
      ["LET.SK8", "LET.COM", "42\r\n"],
      ["COND.SK8", "COND.COM", "42\r\n"],
      ["AND.SK8", "AND.COM", "2\r\n"],
      ["OR.SK8", "OR.COM", "42\r\n"],
      ["PRED.SK8", "PRED.COM", "#t\r\n"],
    ]
  ) {
    runCommand("SKATE " + sourceName, "COMPILED\r\n", sourceName);
    const generated = readCpm22File(machine.export_drive(0), outputName);
    const text = decoder.decode(generated);
    assert.ok(
      text.includes(expected),
      `${outputName}: ${JSON.stringify(text)}`,
    );
    if (sourceName === "ID.SK8") {
      assertGeneratedCom(
        machine.export_drive(0),
        outputName,
        Uint8Array.from([0x34, 0x32, 13, 10]),
        128,
      );
    }
    if (sourceName === "ADD.SK8") {
      const addObject = objectFrom(machine.export_drive(0), "ADD.NOB");
      const addImage = addObject.images.find(({ sectionId }) =>
        sectionId === 5
      );
      assert.ok(addImage, "flat arithmetic code image is missing");
      assert.deepEqual(
        [...addImage.bytes],
        [
          0x3e,
          3,
          0x21,
          40,
          0,
          0x06,
          3,
          0x11,
          2,
          0,
          0xcd,
          0,
          0,
          0xc9,
        ],
        "flat arithmetic code slot is wrong",
      );
      assert.equal(
        addObject.relocations.find(({ siteSectionId, siteOffset }) =>
          siteSectionId === 5 && siteOffset === 11
        )?.targetSymbolId,
        7,
        "flat arithmetic call does not target numeric.add",
      );
      assert.equal(addObject.commit.recordCount, 66);
    }
    if (sourceName === "NESTED.SK8") {
      const nestedObject = objectFrom(machine.export_drive(0), "NESTED.NOB");
      assert.equal(nestedObject.commit.recordCount, 67);
      assertRuntimeEnvelope(nestedObject, "nested object", 198, 2);
      const nestedImage = nestedObject.images.find(({ sectionId }) =>
        sectionId === 5
      );
      assert.ok(nestedImage, "nested arithmetic code image is missing");
      assert.deepEqual(
        [...nestedImage.bytes],
        [
          0x3e,
          3,
          0x21,
          1,
          0,
          0xf5,
          0xe5,
          0x3e,
          3,
          0x21,
          2,
          0,
          0x47,
          0x54,
          0x5d,
          0xe1,
          0xf1,
          0xcd,
          0,
          0,
          0xf5,
          0xe5,
          0x3e,
          3,
          0x21,
          3,
          0,
          0x47,
          0x54,
          0x5d,
          0xe1,
          0xf1,
          0xcd,
          0,
          0,
          0xc9,
        ],
        "nested arithmetic code image is wrong",
      );
      assert.deepEqual(
        nestedObject.relocations.filter(({ siteSectionId, siteOffset }) =>
          siteSectionId === 5 && [18, 33].includes(siteOffset)
        ).map(({ siteOffset, targetSymbolId, use }) => ({
          siteOffset,
          targetSymbolId,
          use,
        })),
        [
          { siteOffset: 18, targetSymbolId: 7, use: 1 },
          { siteOffset: 33, targetSymbolId: 7, use: 1 },
        ],
        "nested arithmetic relocation set is wrong",
      );
    }
    if (sourceName === "CONS.SK8") {
      const pairObject = objectFrom(machine.export_drive(0), "CONS.NOB");
      assert.equal(pairObject.commit.recordCount, 69);
      assertRuntimeEnvelope(pairObject, "pair object", 203);
      const pairImage = pairObject.images.find(({ sectionId }) =>
        sectionId === 5
      );
      assert.ok(pairImage, "pair code image is missing");
      assert.deepEqual(
        [...pairImage.bytes.slice(0, 16)],
        [0x18, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "pair entry stub is wrong",
      );
      assert.deepEqual(
        [...pairImage.bytes.slice(16, 60)],
        [
          0x01,
          0x02,
          0x00,
          0xcd,
          0x00,
          0x00,
          0x21,
          0x00,
          0x00,
          0x36,
          0x03,
          0x23,
          0x11,
          0x28,
          0x00,
          0x73,
          0x23,
          0x72,
          0x23,
          0x36,
          0x00,
          0x23,
          0x36,
          0x03,
          0x23,
          0x11,
          0x02,
          0x00,
          0x73,
          0x23,
          0x72,
          0x23,
          0x36,
          0x00,
          0x11,
          0x00,
          0x00,
          0x01,
          0x02,
          0x00,
          0xcd,
          0x00,
          0x00,
          0xc9,
        ],
        "pair body is wrong",
      );
      assert.deepEqual(
        pairObject.relocations.filter(({ siteSectionId, siteOffset }) =>
          siteSectionId === 5 && [20, 23, 51, 57].includes(siteOffset)
        ).map(({ siteOffset, targetSymbolId, use }) => ({
          siteOffset,
          targetSymbolId,
          use,
        })),
        [
          { siteOffset: 20, targetSymbolId: 18, use: 1 },
          { siteOffset: 23, targetSymbolId: 21, use: 2 },
          { siteOffset: 51, targetSymbolId: 20, use: 2 },
          { siteOffset: 57, targetSymbolId: 19, use: 1 },
        ],
        "pair relocation set is wrong",
      );
    }
    if (sourceName !== "ID.SK8") eraseGenerated(outputName.slice(0, -4));
  }

  const idObject = objectFrom(machine.export_drive(0), "ID.NOB");
  assert.equal(idObject.commit.recordCount, 66);
  assert.deepEqual(
    idObject.sections.map(({ id, length, runOffset }) => ({
      id,
      length,
      runOffset,
    })),
    [
      { id: 1, length: 512, runOffset: 0 },
      { id: 2, length: 4, runOffset: 512 },
      { id: 3, length: 2, runOffset: 768 },
      { id: 4, length: 136, runOffset: 4096 },
      { id: 5, length: 9, runOffset: 0 },
    ],
  );
  assertRuntimeEnvelope(idObject, "scalar object");
  const idCodeImage = idObject.images.find(({ sectionId }) => sectionId === 5);
  assert.ok(idCodeImage, "scalar code image is missing");
  assert.deepEqual(
    [...idCodeImage.bytes],
    [0x3e, 3, 0x21, 42, 0, 0xcd, 0, 0, 0xc9],
    "scalar value-return stub is wrong",
  );
  const idMessage = idObject.sections.find(({ id }) => id === 2);
  assert.ok(idMessage, "scalar result section is missing");
  assert.equal(idMessage.length, 4);
  const idMessageImage = idObject.images.find(({ sectionId }) =>
    sectionId === 2
  );
  assert.ok(idMessageImage, "scalar result image is missing");
  assert.deepEqual([...idMessageImage.bytes], [0x34, 0x32, 13, 10]);
  const idRecipe = idObject.sections.find(({ id }) => id === 3);
  assert.ok(idRecipe, "scalar recipe section is missing");
  assert.equal(idRecipe.length, 2);
  const idRecipeImage = idObject.images.find(({ sectionId }) =>
    sectionId === 3
  );
  assert.ok(idRecipeImage, "scalar recipe image is missing");
  assert.deepEqual([...idRecipeImage.bytes], [0, 0]);

  runCommand("SKATE QUOTE.SK8", "COMPILED\r\n", "quoted recipe publication");
  runCommand("QUOTE", "(1 2)\r\n", "generated structural result");
  const quoteObject = objectFrom(machine.export_drive(0), "QUOTE.NOB");
  assertGeneratedCom(
    machine.export_drive(0),
    "QUOTE.COM",
    Uint8Array.from([40, 49, 32, 50, 41, 13, 10]),
    128,
  );
  assert.deepEqual(
    quoteObject.sections.map(({ id, length, runOffset }) => ({
      id,
      length,
      runOffset,
    })),
    [
      { id: 1, length: 512, runOffset: 0 },
      { id: 2, length: 7, runOffset: 512 },
      { id: 3, length: 13, runOffset: 768 },
      { id: 4, length: 136, runOffset: 4096 },
      { id: 5, length: 8, runOffset: 0 },
    ],
  );
  assert.equal(quoteObject.commit.recordCount, 66);
  assertRuntimeEnvelope(quoteObject, "quoted object");
  const quoteCodeImage = quoteObject.images.find(({ sectionId }) =>
    sectionId === 5
  );
  assert.ok(quoteCodeImage, "quoted code image is missing");
  assert.deepEqual(
    [...quoteCodeImage.bytes],
    [0xc9, 0, 0, 0, 0, 0xcd, 0, 0],
    "quoted value-return stub must not embed a compiler-arena pointer",
  );
  const quoteMessage = quoteObject.sections.find(({ id }) => id === 2);
  assert.ok(quoteMessage, "quoted result section is missing");
  assert.equal(quoteMessage.length, 7);
  const quoteMessageImage = quoteObject.images.find(({ sectionId }) =>
    sectionId === 2
  );
  assert.ok(quoteMessageImage, "quoted result image is missing");
  assert.deepEqual([...quoteMessageImage.bytes], [40, 49, 32, 50, 41, 13, 10]);
  const quoteRecipe = quoteObject.sections.find(({ id }) => id === 3);
  assert.ok(quoteRecipe, "quoted recipe section is missing");
  assert.equal(quoteRecipe.length, 13);
  const quoteImage = quoteObject.images.find(({ sectionId }) =>
    sectionId === 3
  );
  assert.ok(quoteImage, "quoted recipe image is missing");
  assert.deepEqual(
    [...quoteImage.bytes],
    [
      11,
      0,
      0x83,
      1,
      0,
      0x83,
      2,
      0,
      0x80,
      2,
      0xfe,
      0,
      0,
    ],
  );
  eraseGenerated("QUOTE");

  for (
    const [sourceName, outputName] of [
      ["ARITY.SK8", "ARITY.COM"],
      ["OVERLOOP.SK8", "OVERLOOP.COM"],
      ["MACLIM.SK8", "MACLIM.COM"],
      ["ARENA.SK8", "ARENA.COM"],
      ["ENVFULL.SK8", "ENVFULL.COM"],
      ["BADREF.SK8", "BADREF.COM"],
    ]
  ) {
    runCommand("SKATE " + sourceName, "COMPILE ERROR\r\n", sourceName);
    const image = machine.export_drive(0);
    assertAbsent(image, outputName);
    assertAbsent(image, sourceName.replace(".SK8", ".NOB"));
  }

  runCommand("SKATE ID.SK8", "COMPILED\r\n", "repeat procedure compilation");
  runCommand("ID", "42\r\n", "generated ID.COM");

  // Re-link ADD.NOB with the real ATOM numeric provider, then boot the linked
  // COM on a fresh CP/M instance.  The ordinary publication above remains the
  // static-result fixture; this separate run proves the relocatable entry and
  // generated service call on the target-facing path.
  runCommand("SKATE ADD.SK8", "COMPILED\r\n", "linked arithmetic compilation");
  const addObjectBytes = committed(
    readCpm22File(machine.export_drive(0), "ADD.NOB"),
  );
  const provider = await numericProviderObject();
  const linkProgram = (objectBytes) =>
    linkTargetStreams(
      [
        { id: "program", records: toPhysicalNobjRecords(objectBytes) },
        { id: "runtime", records: toPhysicalNobjRecords(provider.bytes) },
      ],
      {
        mainObjectId: "program",
        profile: SKATE_TPA_PROFILES["cpm-64k"],
        providers: [{
          id: "skate-runtime-v2",
          objectId: "runtime",
          supports: [runtimeContract],
          services: provider.services.map(({ key, symbolId }) => ({
            contract: runtimeContract,
            key,
            symbolId,
          })),
        }],
        allocations: [{
          objectId: "program",
          bss: { address: 0x1100, bytes: 136 },
          roots: { address: 0x1100, bytes: 32 },
          activations: { address: 0x1120, bytes: 16 },
          bitmap: { address: 0x1140, bytes: 8 },
          heap: { address: 0x1148, bytes: 64 },
          workspace: [{ address: 0x1130, bytes: 16 }],
          stack: {
            address: SKATE_TPA_PROFILES["cpm-64k"].stackLow,
            bytes: SKATE_TPA_PROFILES["cpm-64k"].stackCapacity,
          },
        }],
      },
    );
  const linked = linkProgram(addObjectBytes);
  assert.equal(linked.linked.entry?.address, 0x0100);
  const runtimePlacement = linked.linked.placements.find(({ objectId }) =>
    objectId === "runtime"
  );
  assert.ok(runtimePlacement, "linked image has no runtime placement");
  assert.equal(runtimePlacement.runAddress, 0x4200);
  assert.ok(
    linked.comBytes.length > runtimePlacement.runAddress - 0x0100,
    "linked image omits provider",
  );
  assert.equal(
    linked.comBytes[203] | linked.comBytes[204] << 8,
    provider.addresses["numeric.add"],
    "linked generated slot does not call numeric.add",
  );
  const linkedDisk = installCpm22File(machine.export_drive(0), {
    name: "ADD.COM",
    bytes: linked.comBytes,
    padByte: 0x1a,
  });
  const linkedMachine = new TriptychCpu(firmware.bootRom);
  let linkedOutput = "";
  try {
    linkedMachine.install_drive(0, linkedDisk, true);
    let linkedTranscript = "";
    let linkedOffset = 0;
    const waitForLinkedPrompt = (description) => {
      for (let slice = 0; slice < 1800; slice += 1) {
        const status = linkedMachine.run_slice(50_000, 500_000);
        linkedTranscript += decoder.decode(linkedMachine.take_serial_output());
        assert.notEqual(
          status,
          0,
          `CP/M halted while waiting for linked ${description}`,
        );
        if (
          linkedTranscript.length > linkedOffset &&
          linkedTranscript.endsWith("A>")
        ) return;
      }
      throw new Error(
        `Timed out waiting for linked ${description}: ${
          linkedTranscript.slice(-500)
        }`,
      );
    };
    waitForLinkedPrompt("boot");
    linkedOffset = linkedTranscript.length;
    assert.ok(
      linkedMachine.enqueue_serial_input(new TextEncoder().encode("ADD\r")),
    );
    waitForLinkedPrompt("ADD");
    linkedOutput = linkedTranscript.slice(linkedOffset);
    assert.ok(
      linkedOutput.includes("42\r\n"),
      linkedTranscript,
    );
  } finally {
    linkedMachine.free();
  }

  // The nested arithmetic object must take the same target-facing path.  Its
  // two generated CALL operands are independent relocations, so this run
  // proves both the NOBJ record stream and the linked execution result.
  runCommand("SKATE NESTED.SK8", "COMPILED\r\n", "linked nested compilation");
  const nestedObjectBytes = committed(
    readCpm22File(machine.export_drive(0), "NESTED.NOB"),
  );
  const nestedLinked = linkProgram(nestedObjectBytes);
  const nestedCodePlacement = nestedLinked.linked.placements.find(({
    objectId,
    sectionId,
  }) => objectId === "program" && sectionId === 5);
  assert.ok(nestedCodePlacement, "linked nested image has no code placement");
  const nestedCodeOffset = nestedCodePlacement.runAddress - 0x0100;
  assert.equal(
    nestedLinked.comBytes[nestedCodeOffset + 18] |
      nestedLinked.comBytes[nestedCodeOffset + 19] << 8,
    provider.addresses["numeric.add"],
    "linked nested inner call does not target numeric.add",
  );
  assert.equal(
    nestedLinked.comBytes[nestedCodeOffset + 33] |
      nestedLinked.comBytes[nestedCodeOffset + 34] << 8,
    provider.addresses["numeric.add"],
    "linked nested outer call does not target numeric.add",
  );
  const nestedDisk = installCpm22File(machine.export_drive(0), {
    name: "NESTED.COM",
    bytes: nestedLinked.comBytes,
    padByte: 0x1a,
  });
  const nestedMachine = new TriptychCpu(firmware.bootRom);
  try {
    nestedMachine.install_drive(0, nestedDisk, true);
    let nestedTranscript = "";
    let nestedOffset = 0;
    const waitForNestedPrompt = (description) => {
      for (let slice = 0; slice < 1800; slice += 1) {
        const status = nestedMachine.run_slice(50_000, 500_000);
        nestedTranscript += decoder.decode(nestedMachine.take_serial_output());
        assert.notEqual(
          status,
          0,
          `CP/M halted while waiting for linked ${description}`,
        );
        if (
          nestedTranscript.length > nestedOffset &&
          nestedTranscript.endsWith("A>")
        ) return;
      }
      throw new Error(
        `Timed out waiting for linked nested ${description}: ${
          nestedTranscript.slice(-500)
        }`,
      );
    };
    waitForNestedPrompt("boot");
    nestedOffset = nestedTranscript.length;
    assert.ok(
      nestedMachine.enqueue_serial_input(new TextEncoder().encode("NESTED\r")),
    );
    waitForNestedPrompt("NESTED");
    assert.ok(
      nestedTranscript.slice(nestedOffset).includes("6\r\n"),
      nestedTranscript,
    );
  } finally {
    nestedMachine.free();
  }

  // The generated pair body must execute through the same provider boundary,
  // rather than merely surviving the static NOBJ shape checks above.  Its
  // packet-new and pairs.cons operands are placement relocations; the two
  // root-base operands must resolve to the caller's linked root arena.
  runCommand("SKATE CONS.SK8", "COMPILED\r\n", "linked pair compilation");
  const consObjectBytes = committed(
    readCpm22File(machine.export_drive(0), "CONS.NOB"),
  );
  const consLinked = linkProgram(consObjectBytes);
  const consCodePlacement = consLinked.linked.placements.find(({
    objectId,
    sectionId,
  }) => objectId === "program" && sectionId === 5);
  assert.ok(consCodePlacement, "linked pair image has no code placement");
  const consCodeOffset = consCodePlacement.runAddress - 0x0100;
  assert.equal(
    consLinked.comBytes[consCodeOffset + 20] |
      consLinked.comBytes[consCodeOffset + 21] << 8,
    provider.addresses["execution.packet-new"],
    "linked pair packet allocation does not target packet-new",
  );
  assert.equal(
    consLinked.comBytes[consCodeOffset + 23] |
      consLinked.comBytes[consCodeOffset + 24] << 8,
    0x1108,
    "linked pair first root-base operand is wrong",
  );
  assert.equal(
    consLinked.comBytes[consCodeOffset + 51] |
      consLinked.comBytes[consCodeOffset + 52] << 8,
    0x1100,
    "linked pair service root-base operand is wrong",
  );
  assert.equal(
    consLinked.comBytes[consCodeOffset + 57] |
      consLinked.comBytes[consCodeOffset + 58] << 8,
    provider.addresses["pairs.cons"],
    "linked pair constructor does not target pairs.cons",
  );
  const consDisk = installCpm22File(machine.export_drive(0), {
    name: "CONS.COM",
    bytes: consLinked.comBytes,
    padByte: 0x1a,
  });
  const consMachine = new TriptychCpu(firmware.bootRom);
  let consOutput = "";
  try {
    consMachine.install_drive(0, consDisk, true);
    let consTranscript = "";
    let consOffset = 0;
    const waitForConsPrompt = (description) => {
      for (let slice = 0; slice < 1800; slice += 1) {
        const status = consMachine.run_slice(50_000, 500_000);
        consTranscript += decoder.decode(consMachine.take_serial_output());
        assert.notEqual(
          status,
          0,
          `CP/M halted while waiting for linked ${description}`,
        );
        if (
          consTranscript.length > consOffset &&
          consTranscript.endsWith("A>")
        ) return;
      }
      throw new Error(
        `Timed out waiting for linked ${description}: ${
          consTranscript.slice(-500)
        }`,
      );
    };
    waitForConsPrompt("boot");
    consOffset = consTranscript.length;
    assert.ok(
      consMachine.enqueue_serial_input(new TextEncoder().encode("CONS\r")),
    );
    waitForConsPrompt("CONS");
    consOutput = consTranscript.slice(consOffset);
    assert.ok(
      consOutput.includes("#<>\r\n"),
      consTranscript,
    );
  } finally {
    consMachine.free();
  }

  // The quoted-data path uses the same provider placement but exercises the
  // runtime-owned recipe installer before the ordinary result printer runs.
  runCommand("SKATE QUOTE.SK8", "COMPILED\r\n", "linked quote compilation");
  const quoteObjectBytes = committed(
    readCpm22File(machine.export_drive(0), "QUOTE.NOB"),
  );
  const quoteLinked = linkProgram(quoteObjectBytes);
  assert.equal(
    quoteLinked.comBytes[396] | quoteLinked.comBytes[397] << 8,
    provider.addresses["execution.literal-init"],
    "linked literal installer relocation is wrong",
  );
  const quoteDisk = installCpm22File(machine.export_drive(0), {
    name: "QUOTE.COM",
    bytes: quoteLinked.comBytes,
    padByte: 0x1a,
  });
  const quoteMachine = new TriptychCpu(firmware.bootRom);
  let quoteOutput = "";
  try {
    quoteMachine.install_drive(0, quoteDisk, true);
    let quoteTranscript = "";
    let quoteOffset = 0;
    const waitForQuotePrompt = (description) => {
      for (let slice = 0; slice < 1800; slice += 1) {
        const status = quoteMachine.run_slice(50_000, 500_000);
        quoteTranscript += decoder.decode(quoteMachine.take_serial_output());
        assert.notEqual(
          status,
          0,
          `CP/M halted while waiting for linked ${description}`,
        );
        if (
          quoteTranscript.length > quoteOffset &&
          quoteTranscript.endsWith("A>")
        ) return;
      }
      throw new Error(
        `Timed out waiting for linked ${description}: ${
          quoteTranscript.slice(-500)
        }`,
      );
    };
    waitForQuotePrompt("boot");
    quoteOffset = quoteTranscript.length;
    assert.ok(
      quoteMachine.enqueue_serial_input(new TextEncoder().encode("QUOTE\r")),
    );
    waitForQuotePrompt("QUOTE");
    quoteOutput = quoteTranscript.slice(quoteOffset);
    // The linked runtime proves the pair result with its supported reference
    // marker.  Readable pair traversal remains a later printer milestone.
    assert.ok(quoteOutput.includes("#<>\r\n"), quoteTranscript);
  } finally {
    quoteMachine.free();
  }
  console.log(JSON.stringify(
    {
      status: "passed",
      compilerBytes: compilerBytes.length,
      compilerCode: compiler.address("N4OBJ") - compiler.address("N6MAIN"),
      evaluatorCode: compiler.address("N6OP") - compiler.address("N6MAIN"),
      readerCode: compiler.address("REND") - compiler.address("RINIT"),
      templateBytes: compiler.address("N4OBJEND") - compiler.address("N4OBJ"),
      linkedProvider: {
        placement: runtimePlacement.runAddress,
        comBytes: linked.comBytes.length,
        output: linkedOutput,
      },
      linkedLiteral: {
        comBytes: quoteLinked.comBytes.length,
        output: quoteOutput,
      },
      linkedPair: {
        comBytes: consLinked.comBytes.length,
        output: consOutput,
      },
      transcript,
      platform: "Triptych WASM with CP/M 2.2",
    },
    null,
    2,
  ));
} finally {
  machine.free();
}

function committed(bytes) {
  let cursor = 0;
  while (cursor + 3 <= bytes.length) {
    const kind = bytes[cursor];
    const length = bytes[cursor + 1] | bytes[cursor + 2] << 8;
    const end = cursor + 3 + length;
    if (end > bytes.length) break;
    if (kind === 12) return bytes.slice(0, end);
    cursor = end;
  }
  throw new Error("generated NOBJ has no complete COMMIT");
}

function objectFrom(image, name) {
  return parseNobj1(committed(readCpm22File(image, name)));
}

function assertInitializedDescriptors(object, description) {
  const image = object.images.find(({ sectionId }) => sectionId === 1);
  assert.ok(image, `${description}: initialized code image is missing`);
  assert.deepEqual(
    [...image.bytes.slice(0, 12)],
    [
      0x31,
      0x00,
      0xe4,
      0xcd,
      0x0c,
      0x01,
      0xcd,
      0x00,
      0x02,
      0xc3,
      0x08,
      0x02,
    ],
    `${description}: descriptor-driven launch sequence is wrong`,
  );
  assert.deepEqual(
    [...image.bytes.slice(399, 439)],
    [...bootDescriptor],
    `${description}: BOOTDESC bytes are wrong`,
  );
  assert.deepEqual(
    [...image.bytes.slice(439, 459)],
    [...storageDescriptor],
    `${description}: STORDESC bytes are wrong`,
  );
  assert.deepEqual(
    [...image.bytes.slice(459, 467)],
    [...topDescriptor],
    `${description}: TOPDESC bytes are wrong`,
  );
  // Generated instructions live in allocated section 5.  Section 1 is the
  // fixed startup image and is checked here only for its launch descriptors.
}

function assertRuntimeEnvelope(
  object,
  description,
  generatedRelocation = 198,
  dynamicCount = description === "pair object" ? 4 : 1,
) {
  assert.deepEqual(
    object.sections.filter(({ id }) => id === 4).map(({
      id,
      storageKind,
      permissions,
      length,
      runOffset,
    }) => ({ id, storageKind, permissions, length, runOffset })),
    [{ id: 4, storageKind: 2, permissions: 3, length: 136, runOffset: 4096 }],
    `${description}: zero-init runtime envelope is wrong`,
  );
  assert.deepEqual(
    object.ranges.map(({ id, sectionId, view, offset, length }) => ({
      id,
      sectionId,
      view,
      offset,
      length,
    })),
    [
      { id: 1, sectionId: 4, view: "run", offset: 0, length: 32 },
      { id: 2, sectionId: 4, view: "run", offset: 32, length: 16 },
      { id: 3, sectionId: 4, view: "run", offset: 48, length: 16 },
      { id: 4, sectionId: 4, view: "run", offset: 64, length: 8 },
      { id: 5, sectionId: 4, view: "run", offset: 72, length: 64 },
      { id: 6, sectionId: 1, view: "run", offset: 399, length: 40 },
      { id: 7, sectionId: 1, view: "run", offset: 439, length: 20 },
      { id: 8, sectionId: 1, view: "run", offset: 459, length: 8 },
      { id: 9, sectionId: 1, view: "run", offset: 467, length: 28 },
    ],
    `${description}: runtime envelope ranges are wrong`,
  );
  assert.deepEqual(
    object.images.map(({ sectionId }) => sectionId),
    [1, 2, 3, 5],
    `${description}: initialized section set is wrong`,
  );
  assert.deepEqual(
    object.relocations.filter(({ siteSectionId }) => siteSectionId === 1).map(({
      siteSectionId,
      siteOffset,
      kind,
      use,
      targetSymbolId,
      addend,
    }) => ({
      siteSectionId,
      siteOffset,
      kind,
      use,
      targetSymbolId,
      addend,
    })),
    [
      {
        siteSectionId: 1,
        siteOffset: 4,
        kind: 1,
        use: 1,
        targetSymbolId: 14,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 7,
        kind: 1,
        use: 1,
        targetSymbolId: 26,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 10,
        kind: 1,
        use: 1,
        targetSymbolId: 13,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 109,
        kind: 1,
        use: 1,
        targetSymbolId: 15,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 122,
        kind: 1,
        use: 1,
        targetSymbolId: 16,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 131,
        kind: 1,
        use: 1,
        targetSymbolId: 17,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: generatedRelocation,
        kind: 1,
        use: 1,
        targetSymbolId: 2,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 212,
        kind: 1,
        use: 1,
        targetSymbolId: 18,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 215,
        kind: 1,
        use: 2,
        targetSymbolId: 21,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 243,
        kind: 1,
        use: 2,
        targetSymbolId: 20,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 249,
        kind: 1,
        use: 1,
        targetSymbolId: 19,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 274,
        kind: 1,
        use: 1,
        targetSymbolId: 18,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 325,
        kind: 1,
        use: 1,
        targetSymbolId: 22,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 396,
        kind: 1,
        use: 1,
        targetSymbolId: 23,
        addend: 0,
      },
      {
        siteSectionId: 1,
        siteOffset: 385,
        kind: 1,
        use: 1,
        targetSymbolId: 24,
        addend: 10,
      },
      {
        siteSectionId: 1,
        siteOffset: 459,
        kind: 1,
        use: 1,
        targetSymbolId: 25,
        addend: 0,
      },
    ],
    `${description}: relocation contract is wrong`,
  );
  const dynamicRelocations = object.relocations.filter(({ siteSectionId }) =>
    siteSectionId === 5
  );
  assert.equal(
    dynamicRelocations.length,
    dynamicCount,
    `${description}: dynamic relocation count is wrong`,
  );
  assertInitializedDescriptors(object, description);
}
