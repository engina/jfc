import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import test from "node:test";

import {verifyJFCOffControl} from "./jfc-off-control.mjs";

const scenarioName = "setup-smoke.json";
const scenario = {
  windows: [[], ["brave.1", "vscode*"], ["brave.2"]],
  actions: [
    {
      click: "brave.2.play",
      expect: {
        windows: [[], ["brave.1", "vscode"], ["brave.2*"]],
        "brave.2.counter": 1,
      },
    },
  ],
};
const scenarioSource = `${JSON.stringify(scenario, null, 2)}\n`;
const scenarioSha256 = createHash("sha256").update(scenarioSource).digest("hex");

function result(state, status = "failed") {
  return {
    schemaVersion: 1,
    scenario: scenarioName,
    scenarioSha256,
    status,
    durationMs: 1,
    assertions: [{afterAction: 1, status, state}],
  };
}

test("accepts the exact expected JFC-off failure", () => {
  assert.deepEqual(
    verifyJFCOffControl({
      scenarioName,
      scenarioSource,
      scenario,
      result: result({
        windows: [[], ["brave.1", "vscode"], ["brave.2*"]],
        "brave.2.counter": 0,
      }),
    }),
    {
      scenario: scenarioName,
      target: "brave.2.play",
      expectedAcceptedClicks: 1,
      actualAcceptedClicks: 0,
    },
  );
});

test("rejects unrelated failures", () => {
  assert.throws(
    () => verifyJFCOffControl({
      scenarioName,
      scenarioSource,
      scenario,
      result: result({
        windows: [[], ["brave.1", "vscode*"], ["brave.2"]],
        "brave.2.counter": 0,
      }),
    }),
    /window activation\/order differed/,
  );
});

test("rejects a positive result while JFC is stopped", () => {
  assert.throws(
    () => verifyJFCOffControl({
      scenarioName,
      scenarioSource,
      scenario,
      result: result({
        windows: [[], ["brave.1", "vscode"], ["brave.2*"]],
        "brave.2.counter": 1,
      }, "passed"),
    }),
    /expected failed result/,
  );
});
