import { basename, dirname, resolve } from "node:path";
import {
  createSkmManifest,
  resolveSkateSource,
} from "./skate-source-profile.mjs";

if (Deno.args.length !== 3) {
  console.error("usage: prepare-skate-source ROOT ENTRY OUTPUT-DIRECTORY");
  Deno.exit(2);
}

const [root, entry, output] = Deno.args;
const project = await resolveSkateSource({ root, entry });
const manifest = createSkmManifest(project.parts);
const outputPath = resolve(output);
if (outputPath === resolve(root)) {
  throw new Error("output must differ from the source root");
}
const manifestName = `${
  basename(entry).replace(/\.SK8$/i, "").toUpperCase()
}.SKM`;
if (!/^[A-Z0-9_]{1,8}\.SKM$/.test(manifestName)) {
  throw new Error("entry needs a CP/M 8.3 .SK8 name");
}
await Deno.mkdir(dirname(outputPath), { recursive: true });
try {
  await Deno.lstat(outputPath);
  throw new Error(`output already exists: ${outputPath}`);
} catch (error) {
  if (!(error instanceof Deno.errors.NotFound)) throw error;
}
const temporary = await Deno.makeTempDir({
  dir: dirname(outputPath),
  prefix: ".skate-source-",
});
try {
  for (const part of project.parts) {
    const name = basename(part.logicalIdentity).toUpperCase();
    await Deno.writeFile(resolve(temporary, name), part.compilerBytes);
  }
  await Deno.writeFile(resolve(temporary, manifestName), manifest);
  await Deno.rename(temporary, outputPath);
} catch (error) {
  await Deno.remove(temporary, { recursive: true });
  throw error;
}
console.log(resolve(outputPath, manifestName));
