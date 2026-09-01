#!/usr/bin/env node

import {spawn} from "node:child_process";
import {readFile} from "node:fs/promises";

import {displayReadinessMismatches} from "../E2E/DisplayDump/readiness.mjs";

const host = process.argv[2] ?? "mac-vm";
const timeoutSeconds = Number(process.argv[3] ?? 90);
if (!Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
  throw new Error("timeout must be a positive number of seconds");
}

const manifest = JSON.parse(
  await readFile(new URL("../E2E/VM_MANIFEST.json", import.meta.url), "utf8"),
);
const displayDumpSource = await readFile(
  new URL("../E2E/DisplayDump/main.swift", import.meta.url),
  "utf8",
);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function queryDisplays() {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "/usr/bin/ssh",
      [
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=5",
        "-o",
        "ConnectionAttempts=1",
        host,
        "/usr/bin/xcrun swift -",
      ],
      {stdio: ["pipe", "pipe", "pipe"]},
    );
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => child.kill("SIGTERM"), 20_000);
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      if (code !== 0) {
        reject(
          new Error(
            `display query exited ${code ?? signal}: ${stderr.trim() || "no diagnostic"}`,
          ),
        );
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch (error) {
        reject(new Error(`display query returned invalid JSON: ${error.message}`));
      }
    });
    child.stdin.end(displayDumpSource);
  });
}

const startedAt = Date.now();
const deadline = startedAt + timeoutSeconds * 1_000;
let attempts = 0;
let lastProblem = "no query attempted";

while (Date.now() < deadline) {
  attempts += 1;
  try {
    const state = await queryDisplays();
    const mismatches = displayReadinessMismatches(state, manifest);
    if (mismatches.length === 0) {
      process.stdout.write(
        `${JSON.stringify({
          status: "ready",
          attempts,
          durationSeconds: (Date.now() - startedAt) / 1_000,
          displays: state.displays.map((display, index) => ({
            name: manifest.guest.displays.appKit[index].name,
            frame: display.frame,
            coreGraphicsBounds: display.coreGraphicsBounds,
            isMain: display.isMain,
          })),
        })}\n`,
      );
      process.exit(0);
    }
    lastProblem = mismatches.join("; ");
  } catch (error) {
    lastProblem = error.message;
  }
  await sleep(1_000);
}

throw new Error(
  `three-display readiness timed out after ${timeoutSeconds}s and ${attempts} attempts: ${lastProblem}`,
);
