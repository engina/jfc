import {createHash} from "node:crypto";

function sameValue(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

export function verifyJFCOffControl({scenarioName, scenarioSource, scenario, result}) {
  const fail = (message) => {
    throw new Error(`${scenarioName}: ${message}`);
  };

  const expectedHash = createHash("sha256").update(scenarioSource).digest("hex");
  if (result.scenario !== scenarioName) fail(`result names ${result.scenario}`);
  if (result.scenarioSha256 !== expectedHash) fail("scenario hash does not match");
  if (result.status !== "failed") fail(`expected failed result; got ${result.status}`);
  if (scenario.actions.length !== 1 || result.assertions.length !== 1) {
    fail("control qualification requires exactly one action and assertion");
  }

  const action = scenario.actions[0];
  const assertion = result.assertions[0];
  if (assertion.afterAction !== 1 || assertion.status !== "failed") {
    fail("first action was not recorded as failed");
  }
  if (typeof action.click !== "string" || !action.click.endsWith(".play")) {
    fail("control action must click a fixture play target");
  }

  const counter = `${action.click.slice(0, -".play".length)}.counter`;
  if (action.expect?.[counter] !== 1) {
    fail(`${counter} must expect exactly one accepted click`);
  }
  if (assertion.state?.[counter] !== 0) {
    fail(`${counter} must remain zero with JFC stopped`);
  }
  if (!sameValue(assertion.state?.windows, action.expect?.windows)) {
    fail("window activation/order differed from the positive expectation");
  }

  const expectedKeys = Object.keys(action.expect ?? {}).sort();
  const actualKeys = Object.keys(assertion.state ?? {}).sort();
  if (!sameValue(actualKeys, expectedKeys)) {
    fail(`observed state keys differ: expected ${expectedKeys}; got ${actualKeys}`);
  }

  return {
    scenario: scenarioName,
    target: action.click,
    expectedAcceptedClicks: 1,
    actualAcceptedClicks: 0,
  };
}
