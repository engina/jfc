#!/usr/bin/env node

import {mkdir, readFile, rename, writeFile} from "node:fs/promises";
import path from "node:path";

import {listVMs, runUTM} from "../E2E/VM/utm.mjs";

const baselineUUID = (
  process.env.JFC_E2E_BASELINE_UUID
  ?? "F686D935-20B5-4D17-851C-B36BCC2D6D78"
).toUpperCase();
const baselineName =
  process.env.JFC_E2E_BASELINE_NAME
  ?? "JFC macOS 14 - preinstall baseline";
const statePath = path.resolve(
  process.argv[2] ?? ".build/e2e-vm/current.json",
);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function runIdentifier() {
  return new Date().toISOString().replace(/[-:.]/g, "").replace("Z", "Z");
}

async function writeState(state) {
  await mkdir(path.dirname(statePath), {recursive: true});
  const temporaryPath = `${statePath}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(state, null, 2)}\n`, {
    flag: "wx",
  });
  await rename(temporaryPath, statePath);
}

try {
  await readFile(statePath);
  throw new Error(`VM state already exists: ${statePath}`);
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

const before = await listVMs();
const baseline = before.find(({uuid}) => uuid === baselineUUID);
if (!baseline) throw new Error(`UTM baseline is not registered: ${baselineUUID}`);
if (baseline.name !== baselineName) {
  throw new Error(
    `UTM baseline name mismatch: expected ${baselineName}; observed ${baseline.name}`,
  );
}
if (baseline.status !== "stopped") {
  throw new Error(`UTM baseline must be stopped; observed ${baseline.status}`);
}

const cloneName = `JFC E2E disposable - ${runIdentifier()} - ${process.pid}`;
if (before.some(({name}) => name === cloneName)) {
  throw new Error(`generated clone name already exists: ${cloneName}`);
}

await runUTM(
  ["clone", "--hide", baseline.uuid, "--name", cloneName],
  {timeout: 20 * 60_000},
);

let clone = null;
for (let attempt = 0; attempt < 30; attempt += 1) {
  clone = (await listVMs()).find(({name}) => name === cloneName);
  if (clone) break;
  await sleep(1_000);
}
if (!clone) throw new Error(`cloned VM was not registered: ${cloneName}`);
if (clone.uuid === baseline.uuid) {
  throw new Error("UTM clone unexpectedly reused the baseline UUID");
}

const state = {
  schemaVersion: 1,
  status: "cloned",
  createdAt: new Date().toISOString(),
  baseline: {uuid: baseline.uuid, name: baseline.name},
  clone: {uuid: clone.uuid, name: clone.name},
  guestHost: "test-user@tests-Virtual-Machine.local",
};
await writeState(state);

try {
  await runUTM(["start", "--hide", clone.uuid], {timeout: 120_000});
} catch (error) {
  // UTM may report an Apple-event error after successfully starting. Status is
  // the authoritative result and is checked below.
  state.startDiagnostic = `${error.stderr ?? error.message}`.trim();
}

let started = null;
for (let attempt = 0; attempt < 120; attempt += 1) {
  started = (await listVMs()).find(({uuid}) => uuid === clone.uuid);
  if (started?.status === "started") break;
  await sleep(1_000);
}
if (started?.status !== "started") {
  throw new Error(
    `cloned VM did not start; observed ${started?.status ?? "not registered"}`,
  );
}

state.status = "started";
state.startedAt = new Date().toISOString();
await writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`);
process.stdout.write(`${JSON.stringify({...state, statePath})}\n`);
