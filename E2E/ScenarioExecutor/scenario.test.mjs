import assert from "node:assert/strict";
import test from "node:test";

import {
  loadScenario,
  parseControlReference,
  ScenarioValidationError,
} from "./scenario.mjs";

const agreedScenario = {
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

test("loads the agreed JSON scenario", () => {
  const scenario = loadScenario(JSON.stringify(agreedScenario));
  assert.equal(scenario.windows.length, 3);
  assert.deepEqual(
    scenario.windows[1].windows.map(({key, active}) => ({key, active})),
    [
      {key: "brave.1", active: false},
      {key: "vscode", active: true},
    ],
  );
  assert.equal(scenario.actions[0].click.key, "brave.2.play");
  assert.equal(scenario.actions[0].expect.values[0].expected, 1);
});

test("requires exactly one active window", () => {
  const invalid = structuredClone(agreedScenario);
  invalid.windows = [["brave.1"], ["vscode"]];
  assert.throws(() => loadScenario(JSON.stringify(invalid)), /exactly one active/);
});

test("rejects duplicate windows", () => {
  const invalid = structuredClone(agreedScenario);
  invalid.windows = [["brave.1*"], ["brave.1"]];
  assert.throws(() => loadScenario(JSON.stringify(invalid)), /duplicate window/);
});

test("rejects undeclared action targets", () => {
  const invalid = structuredClone(agreedScenario);
  invalid.actions[0].click = "brave.3.play";
  assert.throws(() => loadScenario(JSON.stringify(invalid)), /undeclared window/);
});

test("rejects expected layouts with a different window set", () => {
  const invalid = structuredClone(agreedScenario);
  invalid.actions[0].expect.windows = [[], ["vscode"], ["brave.2*"]];
  assert.throws(() => loadScenario(JSON.stringify(invalid)), /declared windows/);
});

test("parses indexed and implicit first-window controls", () => {
  assert.equal(parseControlReference("brave.2.play").window, "brave.2");
  assert.equal(parseControlReference("vscode.editor").window, "vscode");
});

test("rejects invalid JSON", () => {
  assert.throws(() => loadScenario("windows: []"), ScenarioValidationError);
});
