import assert from "node:assert/strict";
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  validateActionTimings,
  validateConditionStream,
  validateDiagnostics,
} from "./validate.mjs";

function sample(role, epochMilliseconds, utilization) {
  return {
    kind: "sample",
    schemaVersion: 1,
    role,
    recordedAt: new Date(epochMilliseconds).toISOString(),
    epochMilliseconds,
    monotonicNanoseconds: String(epochMilliseconds * 1_000_000),
    scheduledLagMilliseconds: 1,
    cpu: {utilization, perCore: [utilization], loadAverage: [1, 1, 1]},
    memory: {freeBytes: 1000},
    paging: {pageIns: 10, pageOuts: 2, swapIns: 0, swapOuts: 0},
    swap: {usedBytes: 100},
    io: {iostat: "disk0 1 2 3"},
    thermal: {status: "ok", output: "CPU_Scheduler_Limit = 100"},
    processes: [{
      pid: 12,
      command: "JFC",
      cpuPercent: utilization * 100,
      residentKilobytes: 4096,
    }],
    collectionMilliseconds: 20,
  };
}

function stream(role) {
  return [
    {kind: "identity", schemaVersion: 1, role, samplingIntervalSeconds: 2},
    sample(role, 1_000, 0.25),
    sample(role, 3_000, 0.5),
    {kind: "complete", schemaVersion: 1, role, sampleCount: 2},
  ];
}

function writeJSONLines(filename, entries) {
  writeFileSync(filename, `${entries.map(JSON.stringify).join("\n")}\n`);
}

test("rejects an incomplete condition stream", () => {
  assert.throws(
    () => validateConditionStream(stream("host").slice(0, -1), "host"),
    /completion marker/,
  );
});

test("validates and summarizes comparable diagnostics", async () => {
  const directory = mkdtempSync(path.join(os.tmpdir(), "jfc-diagnostics-test-"));
  try {
    writeJSONLines(path.join(directory, "host-conditions.jsonl"), stream("host"));
    writeJSONLines(path.join(directory, "guest-conditions.jsonl"), stream("guest"));
    writeJSONLines(path.join(directory, "action-timings.jsonl"), [
      {
        kind: "actionStarted",
        action: 1,
        control: "brave.1.play",
        epochMilliseconds: 2_000,
        monotonicNanoseconds: "1000",
      },
      ...[
        "pointerPositioning",
        "virtualHIDClick",
        "postClickSettle",
        "postActionVerification",
      ].map((phase) => ({
        kind: "phaseCompleted",
        action: 1,
        phase,
        durationMilliseconds: 8,
      })),
      {
        kind: "actionCompleted",
        action: 1,
        control: "brave.1.play",
        status: "passed",
        durationMilliseconds: 350,
        epochMilliseconds: 2_350,
        monotonicNanoseconds: "351000000",
      },
    ]);
    writeFileSync(path.join(directory, "clock-alignment.json"), JSON.stringify({
      selected: {roundTripMilliseconds: 4, guestMinusHostMilliseconds: 2},
    }));
    const scenarioPath = path.join(directory, "scenario.json");
    writeFileSync(scenarioPath, JSON.stringify({actions: [{click: "brave.1.play"}]}));

    const summary = await validateDiagnostics(directory, scenarioPath);
    assert.equal(summary.host.sampleCount, 2);
    assert.equal(summary.guest.cpuUtilization.maximum, 0.5);
    assert.equal(summary.actions[0].completion.status, "passed");
    assert.equal(
      JSON.parse(readFileSync(path.join(directory, "diagnostics-summary.json"))).schemaVersion,
      1,
    );
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});

test("rejects duplicate or incomplete action timing streams", () => {
  const scenario = {actions: [{click: "brave.1.play"}]};
  const entries = [
    {
      kind: "actionStarted",
      action: 1,
      control: "brave.1.play",
      epochMilliseconds: 1,
      monotonicNanoseconds: "1",
    },
    {
      kind: "actionCompleted",
      action: 1,
      control: "brave.1.play",
      status: "failed",
      durationMilliseconds: 1,
      epochMilliseconds: 2,
      monotonicNanoseconds: "2",
    },
  ];
  assert.throws(
    () => validateActionTimings(entries, scenario),
    /phases are incomplete/,
  );
});
