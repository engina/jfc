import {createHash} from "node:crypto";

export function fixtureCounterFromWindowTitle(title) {
  const match = / — ([0-9]+)$/.exec(title);
  if (!match) throw new Error(`fixture counter missing from window title: ${title}`);
  return Number(match[1]);
}

export function normalizeWindowState(displays, identifiedWindows, activeWindow) {
  return displays.map(({display}) =>
    identifiedWindows
      .filter(({record}) => record.display === display)
      .sort((left, right) => right.record.zIndex - left.record.zIndex)
      .map(({key}) => (key === activeWindow ? `${key}*` : key)),
  );
}

export function makeScenarioResult({
  scenarioName,
  scenarioSource,
  durationMs,
  assertions,
}) {
  return {
    schemaVersion: 1,
    scenario: scenarioName,
    scenarioSha256: createHash("sha256").update(scenarioSource).digest("hex"),
    status: assertions.every(({status}) => status === "passed") ? "passed" : "failed",
    durationMs,
    assertions,
  };
}
