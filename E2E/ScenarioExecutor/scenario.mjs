const WINDOW_TOKEN = /^([a-z][a-z0-9-]*)(?:\.([1-9][0-9]*))?(\*)?$/;
const CONTROL_TOKEN = /^([a-z][a-z0-9-]*)(?:\.([1-9][0-9]*))?\.([a-z][a-z0-9-]*)$/;

export class ScenarioValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ScenarioValidationError";
  }
}

function windowKey(app, index) {
  return index ? `${app}.${index}` : app;
}

function parseWindowToken(value) {
  if (typeof value !== "string") {
    throw new ScenarioValidationError("window entries must be strings");
  }
  const match = WINDOW_TOKEN.exec(value);
  if (!match) {
    throw new ScenarioValidationError(`invalid window token: ${value}`);
  }
  const [, app, index, activeMarker] = match;
  return {
    app,
    index: index ? Number(index) : 1,
    key: windowKey(app, index),
    active: Boolean(activeMarker),
  };
}

export function parseControlReference(value) {
  if (typeof value !== "string") {
    throw new ScenarioValidationError("control references must be strings");
  }
  const match = CONTROL_TOKEN.exec(value);
  if (!match) {
    throw new ScenarioValidationError(`invalid control reference: ${value}`);
  }
  const [, app, index, control] = match;
  return {
    app,
    index: index ? Number(index) : 1,
    window: windowKey(app, index),
    control,
    key: value,
  };
}

function validateWindows(value, label) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new ScenarioValidationError(`${label} must be a nonempty display array`);
  }
  const seen = new Set();
  let activeCount = 0;
  const displays = value.map((displayValue, offset) => {
    if (!Array.isArray(displayValue)) {
      throw new ScenarioValidationError(`${label}[${offset}] must be an array`);
    }
    const windows = displayValue.map(parseWindowToken);
    for (const window of windows) {
      if (seen.has(window.key)) {
        throw new ScenarioValidationError(`duplicate window: ${window.key}`);
      }
      seen.add(window.key);
      if (window.active) activeCount += 1;
    }
    return {display: offset + 1, windows};
  });
  if (activeCount !== 1) {
    throw new ScenarioValidationError(
      `${label} must contain exactly one active marker; found ${activeCount}`,
    );
  }
  return displays;
}

function sameWindows(left, right) {
  const leftKeys = new Set(
    left.flatMap(({windows}) => windows.map(({key}) => key)),
  );
  const rightKeys = new Set(
    right.flatMap(({windows}) => windows.map(({key}) => key)),
  );
  return leftKeys.size === rightKeys.size
    && [...leftKeys].every((key) => rightKeys.has(key));
}

function validateAction(value, declaredWindows) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ScenarioValidationError("actions must be JSON objects");
  }
  const keys = Object.keys(value);
  if (keys.some((key) => key !== "click" && key !== "expect")) {
    throw new ScenarioValidationError(`unknown action key: ${keys.join(", ")}`);
  }
  if (!("click" in value) && !("expect" in value)) {
    throw new ScenarioValidationError("an action must contain click or expect");
  }

  const click = "click" in value ? parseControlReference(value.click) : null;
  if (click && !declaredWindows.has(click.window)) {
    throw new ScenarioValidationError(`click references undeclared window: ${click.window}`);
  }

  let expectedWindows = null;
  const expectedValues = [];
  if ("expect" in value) {
    if (!value.expect || typeof value.expect !== "object" || Array.isArray(value.expect)) {
      throw new ScenarioValidationError("expect must be a JSON object");
    }
    for (const [target, expected] of Object.entries(value.expect)) {
      if (target === "windows") {
        expectedWindows = validateWindows(expected, "expect.windows");
        continue;
      }
      const reference = parseControlReference(target);
      if (!declaredWindows.has(reference.window)) {
        throw new ScenarioValidationError(
          `expectation references undeclared window: ${reference.window}`,
        );
      }
      expectedValues.push({target: reference, expected});
    }
  }
  return {click, expect: {windows: expectedWindows, values: expectedValues}};
}

export function loadScenario(source) {
  let value;
  try {
    value = JSON.parse(source);
  } catch (error) {
    throw new ScenarioValidationError(`invalid JSON: ${error.message}`);
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ScenarioValidationError("scenario must be a JSON object");
  }
  const unknown = Object.keys(value).filter(
    (key) => key !== "windows" && key !== "actions",
  );
  if (unknown.length) {
    throw new ScenarioValidationError(`unknown scenario key: ${unknown.join(", ")}`);
  }

  const windows = validateWindows(value.windows, "windows");
  const declaredWindows = new Set(
    windows.flatMap((display) => display.windows.map(({key}) => key)),
  );
  if (!Array.isArray(value.actions) || value.actions.length === 0) {
    throw new ScenarioValidationError("actions must be a nonempty array");
  }
  const actions = value.actions.map((action) =>
    validateAction(action, declaredWindows),
  );
  for (const action of actions) {
    if (action.expect.windows && !sameWindows(windows, action.expect.windows)) {
      throw new ScenarioValidationError(
        "expect.windows must contain the declared windows",
      );
    }
  }
  return {windows, actions};
}
