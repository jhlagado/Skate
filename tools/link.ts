/** Shared NOBJ linking and recoverable CP/M publication helpers. */
import { linkNobj1, parseNobj1 } from "@jhlagado/z80-tool-services";
import {
  DEFAULT_SKATE_TPA_PROFILE,
  type SkateTpaProfile,
  validateSkateTpaProfile,
} from "./m7-compiler.ts";
import {
  type SkateBootAllocation,
  validateSkatePlacedContracts,
} from "./skate-contract.ts";

export interface SerializedNobj1 {
  readonly id: string;
  readonly bytes: Uint8Array;
}

type LinkOptions = Parameters<typeof linkNobj1>[1];
type LinkResult = ReturnType<typeof linkNobj1>;
type LinkObject = Parameters<typeof linkNobj1>[0][number];
type TargetLayout = LinkOptions["target"];

/** Build the flat CP/M target view for a selected transient-memory profile. */
export function skateTargetLayout(
  profile: SkateTpaProfile = DEFAULT_SKATE_TPA_PROFILE,
): TargetLayout {
  validateSkateTpaProfile(profile);
  return {
    regions: [{
      id: profile.id,
      addressSpaceKey: "z80.cpu",
      storageKey: "cpm.ram",
      base: profile.base,
      capacity: profile.capacity,
      imageFill: profile.imageFill,
      permissions: profile.permissions,
      banked: profile.banked,
    }],
    visibility: [],
  };
}

/** Decode and link committed NOBJ objects without mutating their byte streams. */
export function linkSkateObjects(
  inputs: readonly SerializedNobj1[],
  options: Omit<LinkOptions, "target"> & {
    readonly profile?: SkateTpaProfile;
    readonly allocations?: readonly SkateBootAllocation[];
  },
): LinkResult {
  const objects: LinkObject[] = inputs.map(({ id, bytes }) => ({
    id,
    object: parseNobj1(bytes),
  }));
  const linked = linkNobj1(objects, {
    ...options,
    target: skateTargetLayout(options.profile),
  });
  validateSkatePlacedContracts(objects, linked, options.allocations);
  const profile = options.profile ?? DEFAULT_SKATE_TPA_PROFILE;
  for (const allocation of options.allocations ?? []) {
    if (
      allocation.stack.address !== profile.stackLow ||
      allocation.stack.bytes !== profile.stackCapacity
    ) {
      throw new RangeError(
        "Skate stack allocation does not match target profile",
      );
    }
  }
  for (const placement of linked.placements) {
    const owner = objects.find(({ id }) => id === placement.objectId)!;
    const section = owner.object.sections.find(({ id }: { id: number }) =>
      id === placement.sectionId
    )!;
    if (placement.runAddress + section.length > profile.stackLow) {
      throw new RangeError(
        "Skate object placement exceeds the native-stack guard",
      );
    }
  }
  return linked;
}

export interface PublicationIO {
  readonly writeFile: (path: string, bytes: Uint8Array) => Promise<void>;
  readonly rename: (from: string, to: string) => Promise<void>;
  readonly remove: (path: string) => Promise<void>;
  readonly exists: (path: string) => Promise<boolean>;
  /** Optional restart-time read used to recover an interrupted generation. */
  readonly readFile?: (path: string) => Promise<Uint8Array>;
}

const denoPublicationIO: PublicationIO = {
  writeFile: (path, bytes) => Deno.writeFile(path, bytes),
  rename: (from, to) => Deno.rename(from, to),
  remove: (path) => Deno.remove(path),
  readFile: (path) => Deno.readFile(path),
  exists: async (path) => {
    try {
      await Deno.stat(path);
      return true;
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) return false;
      throw error;
    }
  },
};

interface PublicationEntry {
  readonly path: string;
  readonly staged: string;
  readonly backup: string;
  hadPrevious: boolean;
  published: boolean;
}

interface PublicationManifest {
  readonly version: 1;
  readonly token: string;
  readonly entries: readonly {
    readonly path: string;
    readonly staged: string;
    readonly backup: string;
  }[];
}

let publicationSerial = 0;

function publicationToken(): string {
  publicationSerial = (publicationSerial + 1) & 0xffff;
  return `${Date.now().toString(36)}-${publicationSerial.toString(36)}`;
}

async function removeIfPresent(io: PublicationIO, path: string): Promise<void> {
  if (await io.exists(path)) await io.remove(path);
}

function markerPath(path: string): string {
  return `${path}.skate-generation`;
}

function manifestBytes(manifest: PublicationManifest): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(manifest));
}

/**
 * Recover a generation left by a process that stopped after staging or while
 * renaming.  The marker names every bounded temporary file; a previous file is
 * preferred whenever both a final and a backup exist.  Returns true when a
 * marker was found and consumed.
 */
export async function recoverPublication(
  paths: readonly string[],
  io: PublicationIO = denoPublicationIO,
): Promise<boolean> {
  if (paths.length === 0 || io.readFile === undefined) return false;
  const marker = markerPath(paths[0]!);
  if (!await io.exists(marker)) return false;
  const raw = await io.readFile(marker);
  let manifest: PublicationManifest;
  try {
    manifest = JSON.parse(new TextDecoder().decode(raw)) as PublicationManifest;
  } catch {
    throw new Error("invalid Skate generation marker");
  }
  if (
    manifest.version !== 1 ||
    !manifest.token ||
    manifest.entries.length !== paths.length ||
    manifest.entries.some((entry, index) => entry.path !== paths[index])
  ) {
    throw new Error("Skate generation marker does not match its files");
  }
  for (const entry of [...manifest.entries].reverse()) {
    await removeIfPresent(io, entry.staged);
  }
  for (const entry of [...manifest.entries].reverse()) {
    if (await io.exists(entry.backup)) {
      await removeIfPresent(io, entry.path);
      await io.rename(entry.backup, entry.path);
    }
  }
  await io.remove(marker);
  return true;
}

/**
 * Publish one or more related files as one staged generation.
 *
 * All bytes are written to sibling staging files first. Existing targets are
 * moved to sibling recovery names before the generation is installed. Any
 * failed install restores every target whose previous bytes were moved; a
 * recovery file is deliberately left in place if restoration itself fails.
 */
export async function publishFiles(
  files: readonly { readonly path: string; readonly bytes: Uint8Array }[],
  io: PublicationIO = denoPublicationIO,
): Promise<void> {
  if (files.length === 0) throw new RangeError("publication needs one file");
  await recoverPublication(files.map(({ path }) => path), io);
  const token = publicationToken();
  const entries: PublicationEntry[] = files.map(({ path }, index) => ({
    path,
    staged: `${path}.skate-stage-${token}-${index}`,
    backup: `${path}.skate-previous-${token}`,
    hadPrevious: false,
    published: false,
  }));
  const marker = markerPath(entries[0]!.path);
  const manifest: PublicationManifest = {
    version: 1,
    token,
    entries: entries.map(({ path, staged, backup }) => ({
      path,
      staged,
      backup,
    })),
  };

  try {
    await io.writeFile(marker, manifestBytes(manifest));
    for (let index = 0; index < entries.length; index += 1) {
      await io.writeFile(entries[index]!.staged, files[index]!.bytes);
    }
  } catch (error) {
    await Promise.allSettled(entries.map(({ staged }) => io.remove(staged)));
    await removeIfPresent(io, marker);
    throw error;
  }

  try {
    for (const entry of entries) {
      const hadPrevious = await io.exists(entry.path);
      if (hadPrevious) await io.rename(entry.path, entry.backup);
      entry.hadPrevious = hadPrevious;
    }
    for (const entry of entries) {
      await io.rename(entry.staged, entry.path);
      entry.published = true;
    }
  } catch (error) {
    for (const entry of [...entries].reverse()) {
      if (entry.published) {
        await removeIfPresent(io, entry.path).catch(() => undefined);
      }
      if (entry.hadPrevious) {
        try {
          if (await io.exists(entry.backup)) {
            await io.rename(entry.backup, entry.path);
          }
        } catch {
          // Keep the recovery file when the target cannot be restored yet.
        }
      } else {
        await removeIfPresent(io, entry.backup).catch(() => undefined);
      }
      await removeIfPresent(io, entry.staged).catch(() => undefined);
    }
    await removeIfPresent(io, marker).catch(() => undefined);
    throw error;
  }

  await Promise.allSettled(
    entries.map(({ backup, hadPrevious }) =>
      hadPrevious ? removeIfPresent(io, backup) : Promise.resolve()
    ),
  );
  await removeIfPresent(io, marker);
}

/** Publish a CP/M transient image, retaining a previous valid image on error. */
export async function publishCom(
  path: string,
  bytes: Uint8Array,
  io: PublicationIO = denoPublicationIO,
): Promise<void> {
  await publishFiles([{ path, bytes }], io);
}
