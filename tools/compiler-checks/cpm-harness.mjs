// Shared CP/M 2.2 harness for the Triptych-hosted proofs.
//
// Every proof boots the same Triptych CPU firmware from the CP/M 2.2 system
// disk, drives the console through the serial port and waits for the CCP
// prompt.  This module holds that common machinery so each proof only states
// its own cases and checks.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { assembleTriptychCpuFirmware } from "../../../triptych/tools/cpm22-native-image.mjs";

export const triptychRoot = fileURLToPath(
  new URL("../../../triptych/", import.meta.url),
);

const require = createRequire(import.meta.url);
/** The Triptych WASM host exports (TriptychCpu, CpmDisk, ...). */
export const triptychHost = require(
  join(triptychRoot, "dist", "wasm", "triptych_host_wasm.js"),
);
export const { TriptychCpu } = triptychHost;

export { predictHeapLimit } from "./heap-layout.mjs";

/** CP/M 2.2 data directory: 64 entries of 32 bytes after the system tracks. */
export const directoryOffset = 52 * 128;
export const directoryEntries = 64;

/** Assemble the Triptych firmware and read the stock CP/M 2.2 disk image. */
export async function loadCpmSystem() {
  const firmware = await assembleTriptychCpuFirmware(triptychRoot);
  const sourceDisk = await Deno.readFile(
    join(triptychRoot, "third_party", "cpm22", "cpm22.img"),
  );
  return { firmware, sourceDisk };
}

/**
 * Patch the firmware's CCP, BDOS and BIOS into the system tracks, pad the
 * image to whole 512-byte sectors and leave the data directory empty.
 */
export function makeSystemDisk(firmware, sourceDisk) {
  const system = Uint8Array.from(sourceDisk);
  system.set(firmware.ccp, 0x0000);
  system.set(firmware.bdos, 0x0800);
  system.set(firmware.bios, 0x1600);
  const disk = new Uint8Array(Math.ceil(system.length / 512) * 512);
  disk.set(system);
  disk.fill(0xe5, directoryOffset, directoryOffset + directoryEntries * 32);
  return disk;
}

/** List the directory entries (name and allocated block count) on a disk. */
export function directoryFiles(image) {
  const files = [];
  for (let index = 0; index < directoryEntries; index += 1) {
    const offset = directoryOffset + index * 32;
    if (image[offset] !== 0) continue;
    const raw = String.fromCharCode(...image.slice(offset + 1, offset + 12));
    const base = raw.slice(0, 8).trimEnd();
    const extension = raw.slice(8).trimEnd();
    const name = extension ? `${base}.${extension}` : base;
    let blocks = 0;
    for (let byte = 16; byte < 32; byte += 1) {
      if (image[offset + byte] !== 0) blocks += 1;
    }
    files.push({ name, blocks });
  }
  return files;
}

/** Summarise directory use on the 241-block CP/M 2.2 data area. */
export function diskStats(image) {
  const files = directoryFiles(image);
  const usedBlocks = files.reduce((sum, file) => sum + file.blocks, 0);
  return {
    bytes: image.length,
    files: files.length,
    usedBlocks,
    freeBlocks: 241 - usedBlocks,
  };
}

export function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Read a little-endian word from the machine's RAM. */
export function readWord(machine, address) {
  const bytes = machine.read_ram(address, 2);
  return bytes[0] | bytes[1] << 8;
}

/**
 * Return the text a program printed: everything after the echoed command line
 * and before the next CCP prompt.
 */
export function programOutput(output) {
  const commandEnd = output.indexOf("\r\r\n");
  const prompt = output.lastIndexOf("\r\nA>");
  assert.ok(commandEnd >= 0 && prompt > commandEnd, JSON.stringify(output));
  return output.slice(commandEnd + 3, prompt);
}

/**
 * Drive a booted machine's console.  The transcript accumulates every byte
 * the machine has written to the serial port.
 *
 * `promptAttempts` bounds how many 50,000-instruction slices a wait for the
 * prompt may take; it may be a number or a function of the description.
 */
export function createCpmSession(machine, { promptAttempts = 1800 } = {}) {
  const decoder = new TextDecoder("ascii");
  const encoder = new TextEncoder();
  const session = {
    transcript: "",
    /** Run one slice, collect its output and require that CP/M is running. */
    slice(instructions, cycles, haltMessage) {
      const status = machine.run_slice(instructions, cycles);
      session.transcript += decoder.decode(machine.take_serial_output());
      assert.notEqual(status, 0, haltMessage);
      return status;
    },
    /** Queue console input for the machine. */
    send(text) {
      assert.ok(machine.enqueue_serial_input(encoder.encode(text)));
    },
    /**
     * Run until the transcript beyond `offset` ends with the CCP prompt and
     * return the instructions and T-states the wait consumed.
     */
    runUntilPrompt(offset, description) {
      const limit = typeof promptAttempts === "function"
        ? promptAttempts(description)
        : promptAttempts;
      let instructions = 0n;
      let tstates = 0n;
      for (let attempt = 0; attempt < limit; attempt += 1) {
        session.slice(
          50_000,
          500_000,
          `CP/M halted while waiting for ${description}`,
        );
        instructions += machine.last_steps();
        tstates += machine.last_tstates();
        if (
          session.transcript.length > offset &&
          session.transcript.endsWith("A>")
        ) {
          return {
            instructions: Number(instructions),
            tstates: Number(tstates),
          };
        }
      }
      throw new Error(
        `Timed out waiting for ${description}: ${
          JSON.stringify(session.transcript.slice(-500))
        }`,
      );
    },
    /**
     * Type a command, wait for the prompt and require `expected` in the
     * output.  Returns the output with the instructions and T-states used.
     */
    runCommandMeasured(command, expected, description) {
      const start = session.transcript.length;
      session.send(`${command}\r`);
      const metrics = session.runUntilPrompt(start, description);
      const output = session.transcript.slice(start);
      assert.ok(
        output.includes(expected),
        `${description}: expected ${JSON.stringify(expected)} in ${
          JSON.stringify(output)
        }`,
      );
      return { output, ...metrics };
    },
    /** Type a command, wait for the prompt and return the command's output. */
    runCommand(command, expected, description) {
      return session.runCommandMeasured(command, expected, description).output;
    },
  };
  return session;
}
