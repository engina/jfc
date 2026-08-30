import assert from "node:assert/strict";
import test from "node:test";

import {
  fixtureCounterFromWindowTitle,
  makeScenarioResult,
  normalizeWindowState,
} from "./result.mjs";

test("normalizes a window snapshot to DSL order", () => {
  const displays = [
    {display: 1},
    {display: 2},
    {display: 3},
  ];
  const windows = [
    {key: "brave.2", record: {display: 3, zIndex: 4}},
    {key: "vscode", record: {display: 2, zIndex: 5}},
    {key: "brave.1", record: {display: 2, zIndex: 6}},
  ];

  assert.deepEqual(normalizeWindowState(displays, windows, "brave.2"), [
    [],
    ["brave.1", "vscode"],
    ["brave.2*"],
  ]);
});

test("reads the fixture counter from its window title", () => {
  assert.equal(
    fixtureCounterFromWindowTitle("brave.2 — JFC Click Fixture — 1"),
    1,
  );
  assert.throws(() => fixtureCounterFromWindowTitle("unrelated window"));
});

test("builds a compact result without duplicated scenario internals", () => {
  const result = makeScenarioResult({
    scenarioName: "setup-smoke.json",
    scenarioSource: "{}\n",
    assertions: [
      {
        afterAction: 1,
        status: "passed",
        state: {
          windows: [[], ["brave.1", "vscode"], ["brave.2*"]],
          "brave.2.counter": 1,
        },
      },
    ],
  });

  assert.deepEqual(Object.keys(result), [
    "schemaVersion",
    "scenario",
    "scenarioSha256",
    "status",
    "assertions",
  ]);
  assert.equal(result.scenarioSha256.length, 64);
  assert.equal(result.assertions[0].state["brave.2.counter"], 1);
  for (const redundant of [
    "setup",
    "actions",
    "expect",
    "controls",
    "recording",
    "artifacts",
  ]) {
    assert.equal(redundant in result, false);
  }
});
