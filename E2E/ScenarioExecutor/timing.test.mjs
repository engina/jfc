import assert from "node:assert/strict";
import {mkdtempSync, readFileSync, rmSync} from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {ActionTimingLog} from "./timing.mjs";

test("records actions and phases without pointer coordinates", async () => {
  const directory = mkdtempSync(path.join(os.tmpdir(), "jfc-timing-test-"));
  try {
    const filename = path.join(directory, "timings.jsonl");
    const log = new ActionTimingLog({filename, scenario: "example.json"});
    const action = log.beginAction(1, "brave.1.play");
    action.phaseSync("pointerPositioning", () => 42);
    await action.phase("postClickSettle", async () => 42);
    action.complete("failed", [{
      name: "frontmost application",
      actual: "com.microsoft.VSCode",
      expected: "com.brave.Browser",
    }]);
    const source = readFileSync(filename, "utf8");
    const entries = source.trim().split("\n").map(JSON.parse);
    assert.deepEqual(entries.map(({kind}) => kind), [
      "actionStarted",
      "phaseCompleted",
      "phaseCompleted",
      "actionCompleted",
    ]);
    assert.equal(entries[0].control, "brave.1.play");
    assert.deepEqual(entries.at(-1).verificationFailures, [{
      name: "frontmost application",
      actual: "com.microsoft.VSCode",
      expected: "com.brave.Browser",
    }]);
    assert.doesNotMatch(source, /\"x\"|\"y\"|coordinates/i);
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});
