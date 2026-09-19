/** Compile the implemented Scheme subset to an NOBJ object and CP/M COM. */
import { basename, dirname, extname, join, resolve } from "node:path";
import {
  compileM10,
  compileM10Package,
  SKATE_TPA_PROFILES,
  type SkateTpaProfileName,
} from "./m7-compiler.ts";
import { publishFiles } from "./link.ts";
import { readSourcePackage } from "./source-package.ts";

function usage(): never {
  console.error(
    "Usage: deno task compile source.sk8|package.skm output.com [cpm-64k|cpm-32k]",
  );
  Deno.exit(2);
}

if (import.meta.main) {
  if (Deno.args.length < 2 || Deno.args.length > 3) usage();
  const [sourcePath, outputPath, profileName = "cpm-64k"] = Deno.args;
  if (sourcePath === undefined || outputPath === undefined) usage();
  try {
    if (!(profileName in SKATE_TPA_PROFILES)) {
      throw new RangeError(
        `Unknown CP/M profile ${JSON.stringify(profileName)}`,
      );
    }
    const profile = SKATE_TPA_PROFILES[profileName as SkateTpaProfileName];
    const compiled = extname(sourcePath).toLowerCase() === ".skm"
      ? await compileM10Package(await readSourcePackage(sourcePath), {
        tpaProfile: profile,
      })
      : await compileM10(await Deno.readFile(sourcePath), sourcePath, {
        tpaProfile: profile,
      });
    const output = resolve(outputPath);
    if (extname(output).toLowerCase() !== ".com") {
      throw new TypeError("Output path must end in .COM");
    }
    await Deno.mkdir(dirname(output), { recursive: true });
    const objectPath = join(
      dirname(output),
      `${basename(output, extname(output))}.nobj`,
    );
    await publishFiles([
      { path: output, bytes: compiled.comBytes },
      { path: objectPath, bytes: compiled.objectBytes },
    ]);
    console.log(
      `${output}: ${compiled.comBytes.length} bytes at $0100 (${profileName}); ${compiled.resultKind} result at $${
        compiled.resultAddress.toString(16).padStart(4, "0")
      }`,
    );
    console.log(
      `${objectPath}: ${compiled.objectBytes.length} bytes, NOBJ 1.0`,
    );
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exitCode = 1;
  }
}
