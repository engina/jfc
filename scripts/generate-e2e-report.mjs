#!/usr/bin/env node

import {mkdir, writeFile} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";

import {collectLatestRuns, renderReport} from "../E2E/Report/report.mjs";

const repositoryRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const artifactsDirectory = path.resolve(
  process.argv[2] ?? path.join(repositoryRoot, "E2E/Artifacts"),
);
const outputFile = path.resolve(
  process.argv[3] ?? path.join(artifactsDirectory, "report.html"),
);
const scenariosDirectory = path.join(repositoryRoot, "E2E/Scenarios");

await mkdir(path.dirname(outputFile), {recursive: true});
const runs = await collectLatestRuns(artifactsDirectory, scenariosDirectory);
await writeFile(outputFile, renderReport(runs), "utf8");
process.stdout.write(`Generated report for ${runs.length} scenarios:\n${outputFile}\n`);
