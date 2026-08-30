import assert from "node:assert/strict";
import test from "node:test";

import {renderReport, stateDifferences} from "./report.mjs";

test("diffs expected and actual display state and values", () => {
  assert.deepEqual(
    stateDifferences(
      {
        windows: [[], ["brave.1", "vscode"], ["brave.2*"]],
        "brave.2.counter": 1,
      },
      {
        windows: [[], ["brave.1", "vscode*"], ["brave.2"]],
        "brave.2.counter": 0,
      },
    ),
    [
      {
        label: "D2 windows",
        expected: ["brave.1", "vscode"],
        actual: ["brave.1", "vscode*"],
      },
      {
        label: "D3 windows",
        expected: ["brave.2*"],
        actual: ["brave.2"],
      },
      {label: "brave.2.counter", expected: 1, actual: 0},
    ],
  );
});

test("renders a self-contained static report", () => {
  const html = renderReport(
    [
      {
        artifactDirectory: "scenario-20260830T052730Z",
        recordedAt: "20260830T052730Z",
        scenario: {
          windows: [[], ["vscode*"], ["brave.2"]],
          actions: [
            {
              click: "brave.2.play",
              expect: {
                windows: [[], ["vscode"], ["brave.2*"]],
                "brave.2.counter": 1,
              },
            },
          ],
        },
        result: {
          schemaVersion: 1,
          scenario: "setup-smoke.json",
          status: "passed",
          assertions: [
            {
              afterAction: 1,
              status: "passed",
              state: {windows: [[], ["vscode"], ["brave.2*"]]},
            },
          ],
        },
      },
    ],
    "2026-08-30T05:30:00.000Z",
  );

  assert.match(html, /^<!doctype html>/);
  assert.match(html, /setup-smoke\.json/);
  assert.match(html, /scenario-20260830T052730Z/);
  assert.match(html, /type="application\/json"/);
  assert.match(html, /Initial state/);
  assert.match(html, /Expected output state/);
  assert.match(html, /Click /);
  assert.match(html, /All artifacts…/);
  assert.match(html, /Mismatch/);
  assert.match(html, /Expected/);
  assert.match(html, /Actual/);
  assert.match(html, /const screenshotURL = .*\/displays\/display-/);
  assert.match(html, /const recordingURL = .*\/display-/);
  assert.match(html, /mosaic\.mp4/);
  assert.doesNotMatch(html, /<video/);
  assert.doesNotMatch(html, /fetch\(/);
  const scripts = [...html.matchAll(/<script(?: [^>]*)?>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 2);
  assert.doesNotThrow(() => new Function(scripts[1][1]));
});
