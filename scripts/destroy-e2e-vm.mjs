#!/usr/bin/env node

import {execFile} from "node:child_process";
import {readFile, unlink} from "node:fs/promises";
import path from "node:path";
import {promisify} from "node:util";

import {validateDisposableVMState} from "../E2E/VM/state.mjs";
import {listVMs, runUTM} from "../E2E/VM/utm.mjs";

const execFileAsync = promisify(execFile);
const statePath = path.resolve(
  process.argv[2] ?? ".build/e2e-vm/current.json",
);
const guestHost = process.argv[3] ?? "mac-vm";
const state = validateDisposableVMState(
  JSON.parse(await readFile(statePath, "utf8")),
);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function registeredClone() {
  const vms = await listVMs();
  const baseline = vms.find(({uuid}) => uuid === state.baseline.uuid);
  if (!baseline || baseline.name !== state.baseline.name) {
    throw new Error("immutable baseline identity no longer matches VM state");
  }
  const clone = vms.find(({uuid}) => uuid === state.clone.uuid);
  if (clone && clone.name !== state.clone.name) {
    throw new Error("clone UUID is registered under an unexpected name");
  }
  return {baseline, clone};
}

let {clone} = await registeredClone();
if (!clone) throw new Error("disposable clone is no longer registered");

if (clone.status !== "stopped") {
  try {
    await execFileAsync(
      "/usr/bin/ssh",
      [
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=5",
        guestHost,
        "/usr/bin/osascript -e 'tell application \"System Events\" to shut down'",
      ],
      {encoding: "utf8", timeout: 20_000},
    );
  } catch {
    // Status polling below determines whether guest shutdown succeeded.
  }

  for (let attempt = 0; attempt < 90; attempt += 1) {
    clone = (await registeredClone()).clone;
    if (clone?.status === "stopped") break;
    await sleep(1_000);
  }
}

if (clone?.status !== "stopped") {
  try {
    await runUTM(["stop", "--hide", "--force", state.clone.uuid], {
      timeout: 30_000,
    });
  } catch {
    // UTM can report an Apple-event error after accepting the stop request.
  }
  for (let attempt = 0; attempt < 30; attempt += 1) {
    clone = (await registeredClone()).clone;
    if (clone?.status === "stopped") break;
    await sleep(1_000);
  }
}
if (clone?.status !== "stopped") {
  throw new Error(`disposable clone did not stop; observed ${clone?.status}`);
}

try {
  await runUTM(["delete", "--hide", state.clone.uuid], {timeout: 120_000});
} catch {
  // Registration is authoritative; verify deletion below.
}
for (let attempt = 0; attempt < 60; attempt += 1) {
  clone = (await registeredClone()).clone;
  if (!clone) break;
  await sleep(1_000);
}
if (clone) throw new Error("disposable clone remained registered after deletion");

const {baseline} = await registeredClone();
if (baseline.status !== "stopped") {
  throw new Error(`immutable baseline changed state: ${baseline.status}`);
}
await unlink(statePath);
process.stdout.write(
  `${JSON.stringify({
    status: "deleted",
    clone: state.clone,
    baseline,
    statePath,
  })}\n`,
);
