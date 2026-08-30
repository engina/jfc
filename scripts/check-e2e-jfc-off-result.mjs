#!/usr/bin/env node

import {readdir, readFile} from "node:fs/promises";
import path from "node:path";

import {verifyJFCOffControl} from "../E2E/ScenarioExecutor/jfc-off-control.mjs";

const [artifactsDirectory, scenarioPath] = process.argv.slice(2);
if (!artifactsDirectory || !scenarioPath) {
  throw new Error("usage: check-e2e-jfc-off-result.mjs <artifacts-dir> <scenario.json>");
}

const scenarioName = path.basename(scenarioPath);
const scenarioSource = await readFile(scenarioPath, "utf8");
const scenario = JSON.parse(scenarioSource);
const entries = (await readdir(artifactsDirectory, {withFileTypes: true}))
  .filter((entry) => entry.isDirectory() && /^scenario-[0-9]{8}T[0-9]{6}Z$/.test(entry.name))
  .sort((left, right) => right.name.localeCompare(left.name));

let latest = null;
for (const entry of entries) {
  try {
    const result = JSON.parse(
      await readFile(path.join(artifactsDirectory, entry.name, "result.json"), "utf8"),
    );
    if (result.scenario === scenarioName) {
      latest = {entry: entry.name, result};
      break;
    }
  } catch {
    // Ignore incomplete artifact directories from interrupted runs.
  }
}
if (!latest) throw new Error(`${scenarioName}: no completed control artifact found`);

const verification = verifyJFCOffControl({
  scenarioName,
  scenarioSource,
  scenario,
  result: latest.result,
});
process.stdout.write(
  `CONTROL PASSED ${verification.scenario}: ${verification.target} accepted `
    + `${verification.actualAcceptedClicks}/${verification.expectedAcceptedClicks} clicks `
    + `(${latest.entry})\n`,
);
