import {execFileSync} from "node:child_process";
import {mkdtempSync} from "node:fs";
import {readFile} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

import {AppiumClient} from "./appium.mjs";
import {MultiDisplayRecorder} from "./recording.mjs";
import {
  fixtureCounterFromWindowTitle,
  makeScenarioResult,
  normalizeWindowState,
} from "./result.mjs";
import {loadScenario} from "./scenario.mjs";

const APP = {
  brave: {
    bundleID: "com.brave.Browser",
    processName: "Brave Browser",
  },
  vscode: {
    bundleID: "com.microsoft.VSCode",
    processName: "Code",
  },
};

const CONTROL_LABEL = {
  play: "JFC click target",
  counter: "JFC accepted click count",
};

const VIRTUAL_HID_CLICK = "/usr/local/libexec/jfc-e2e-virtual-hid-click";
const VIRTUAL_HID_JOB = "system/io.e10n.jfc.e2e.virtual-hid";

const here = path.dirname(fileURLToPath(import.meta.url));

function usage() {
  return "usage: executor.mjs <scenario.json> --fixture <index.html> [--recordings DIR] [--appium URL]";
}

function parseArguments(argv) {
  const args = [...argv];
  const scenarioPath = args.shift();
  let fixturePath = null;
  let recordingsPath = null;
  let appiumUrl = "http://127.0.0.1:4723";
  while (args.length) {
    const option = args.shift();
    if (option === "--fixture") fixturePath = args.shift();
    else if (option === "--recordings") recordingsPath = args.shift();
    else if (option === "--appium") appiumUrl = args.shift();
    else throw new Error(`unknown option: ${option}`);
  }
  if (!scenarioPath || !fixturePath) throw new Error(usage());
  return {scenarioPath, fixturePath, recordingsPath, appiumUrl};
}

function appleString(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function predicateString(value) {
  return value.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function runAppleScript(client, script, timeout = 60_000) {
  return await client.execute("macos: appleScript", [{script, timeout}]);
}

async function runJXA(client, script) {
  const value = await client.execute("macos: appleScript", [
    {script, language: "JavaScript", timeout: 60_000},
  ]);
  return value.trim();
}

function allWindows(displays) {
  return displays.flatMap(({display, windows}) =>
    windows.map((window) => ({...window, display})),
  );
}

function validateRuntimeVocabulary(scenario) {
  const windows = allWindows(scenario.windows);
  for (const window of windows) {
    if (!APP[window.app]) {
      throw new Error(`unsupported application: ${window.app}`);
    }
  }
  const vscode = windows.filter(({app}) => app === "vscode");
  if (vscode.length > 1 || (vscode[0] && vscode[0].key !== "vscode")) {
    throw new Error("the executor supports one window named vscode");
  }
  const braveIndexes = windows
    .filter(({app}) => app === "brave")
    .map(({index}) => index)
    .sort((left, right) => left - right);
  braveIndexes.forEach((index, offset) => {
    if (index !== offset + 1) {
      throw new Error("Brave windows must be consecutively numbered from brave.1");
    }
  });
  for (const action of scenario.actions) {
    const references = [action.click, ...action.expect.values.map(({target}) => target)]
      .filter(Boolean);
    for (const reference of references) {
      if (!CONTROL_LABEL[reference.control]) {
        throw new Error(`unsupported control: ${reference.control}`);
      }
    }
  }
}

async function queryDisplays(client) {
  const source = `
ObjC.import("AppKit");
const screens = $.NSScreen.screens.js;
const mainHeight = Number(screens[0].frame.size.height);
const result = screens.map((screen, offset) => {
  const frame = screen.frame;
  const x = Number(frame.origin.x);
  const appKitY = Number(frame.origin.y);
  const width = Number(frame.size.width);
  const height = Number(frame.size.height);
  return {
    index: offset + 1,
    name: ObjC.unwrap(screen.localizedName),
    x,
    y: mainHeight - (appKitY + height),
    width,
    height,
  };
});
JSON.stringify(result);
`;
  return JSON.parse(await runJXA(client, source));
}

function canonicalFrame(app, screen) {
  const margin = 40;
  const width = Math.round(screen.width * 0.62) - margin;
  const height = screen.height - margin * 2;
  const x =
    app === "vscode"
      ? screen.x + margin
      : screen.x + Math.round(screen.width * 0.38);
  return {x, y: screen.y + margin, width, height};
}

async function terminateApplications(client, scenario) {
  const apps = new Set(allWindows(scenario.windows).map(({app}) => app));
  for (const app of apps) {
    await client.execute("macos: terminateApp", [{bundleId: APP[app].bundleID}]);
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const exists = await runAppleScript(
        client,
        `tell application "System Events" to return exists application process ${appleString(APP[app].processName)}`,
      );
      if (exists.trim() === "false") break;
      await sleep(250);
      if (attempt === 39) throw new Error(`${app} did not terminate`);
    }
  }
}

async function launchVSCode(client) {
  const script = `do shell script "/usr/bin/open -na '/Applications/Visual Studio Code.app'"`;
  await runAppleScript(client, script);
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const result = await runAppleScript(
      client,
      'tell application "System Events" to return exists application process "Code"',
    );
    if (result.trim() === "true") {
      const count = await runAppleScript(
        client,
        'tell application "System Events" to tell application process "Code" to return count of windows',
      );
      if (Number(count.trim()) > 0) return;
    }
    await sleep(250);
  }
  throw new Error("VS Code did not create a window");
}

async function launchBraveWindows(client, braveWindows, fixturePath) {
  if (braveWindows.length === 0) return;
  const profile = mkdtempSync(path.join(os.tmpdir(), "jfc-e2e-brave-"));
  await client.execute("macos: launchApp", [
    {
      bundleId: APP.brave.bundleID,
      arguments: [
        `--user-data-dir=${profile}`,
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-session-crashed-bubble",
      ],
    },
  ]);
  const fixtureURL = pathToFileURL(fixturePath);
  const urls = braveWindows.map((window) => {
    const url = new URL(fixtureURL);
    url.searchParams.set("window", window.key);
    return url.href;
  });

  const lines = [
    'tell application "Brave Browser"',
    `set URL of active tab of window 1 to ${appleString(urls[0])}`,
  ];
  for (const url of urls.slice(1)) {
    lines.push("set createdWindow to make new window");
    lines.push(`set URL of active tab of createdWindow to ${appleString(url)}`);
  }
  lines.push("return count of windows");
  lines.push("end tell");
  const count = Number((await runAppleScript(client, lines.join("\n"))).trim());
  if (count !== braveWindows.length) {
    throw new Error(`expected ${braveWindows.length} Brave windows; found ${count}`);
  }

  for (let attempt = 0; attempt < 40; attempt += 1) {
    const titles = await runAppleScript(
      client,
      'tell application "Brave Browser" to return name of every window',
    );
    if (braveWindows.every(({key}) => titles.includes(`${key} — JFC Click Fixture`))) {
      return;
    }
    await sleep(250);
  }
  throw new Error("Brave fixture window titles did not become ready");
}

async function setWindowGeometry(client, scenario, screens) {
  const windows = allWindows(scenario.windows);
  const braveLines = [
    'tell application "System Events"',
    'tell application process "Brave Browser"',
  ];
  for (const window of windows.filter(({app}) => app === "brave")) {
    const frame = canonicalFrame(window.app, screens[window.display - 1]);
    braveLines.push("repeat with candidateWindow in every window");
    braveLines.push(
      `if name of candidateWindow starts with ${appleString(`${window.key} —`)} then`,
    );
    braveLines.push(`set position of candidateWindow to {${frame.x}, ${frame.y}}`);
    braveLines.push(`set size of candidateWindow to {${frame.width}, ${frame.height}}`);
    braveLines.push("end if");
    braveLines.push("end repeat");
  }
  braveLines.push("end tell");
  braveLines.push("end tell");
  if (braveLines.length > 4) await runAppleScript(client, braveLines.join("\n"));

  const vscode = windows.find(({app}) => app === "vscode");
  if (vscode) {
    const frame = canonicalFrame(vscode.app, screens[vscode.display - 1]);
    const script = `
tell application "System Events"
  tell application process "Code"
    set position of window 1 to {${frame.x}, ${frame.y}}
    set size of window 1 to {${frame.width}, ${frame.height}}
  end tell
end tell
`;
    await runAppleScript(client, script);
  }
}

function raiseScript(window) {
  if (window.app === "vscode") {
    return `tell application "System Events" to tell application process "Code" to perform action "AXRaise" of window 1`;
  }
  return `
tell application "System Events"
  tell application process "Brave Browser"
    repeat with candidateWindow in every window
      if name of candidateWindow starts with ${appleString(`${window.key} —`)} then perform action "AXRaise" of candidateWindow
    end repeat
  end tell
end tell
`;
}

async function applyStackingAndFocus(client, displays) {
  for (const display of displays) {
    for (const window of display.windows) {
      await runAppleScript(client, raiseScript(window));
    }
  }
  const active = allWindows(displays).find(({active}) => active);
  await client.execute("macos: activateApp", [{bundleId: APP[active.app].bundleID}]);
  await runAppleScript(client, raiseScript(active));
  await sleep(300);
}

async function queryFocusedWindowTitle(client, active) {
  const script = `
tell application "System Events"
  tell application process ${appleString(APP[active.app].processName)}
    set focusedWindow to value of attribute "AXFocusedWindow"
    return name of focusedWindow
  end tell
end tell
`;
  return (await runAppleScript(client, script)).trim();
}

async function locateControl(client, reference) {
  if (reference.app !== "brave") {
    throw new Error(`control lookup is not implemented for ${reference.app}`);
  }
  const title = predicateString(`${reference.window} — JFC Click Fixture`);
  const windows = await client.findElements(
    "predicate string",
    `elementType == 4 AND title BEGINSWITH "${title}"`,
  );
  if (windows.length !== 1) {
    throw new Error(`expected one AX window for ${reference.window}; found ${windows.length}`);
  }
  const label = predicateString(CONTROL_LABEL[reference.control]);
  const controls = await client.findElements(
    "predicate string",
    `label == "${label}"`,
    windows[0],
  );
  if (controls.length !== 1) {
    throw new Error(`expected one AX control for ${reference.key}; found ${controls.length}`);
  }
  return {
    elementId: controls[0],
    rect: await client.elementRect(controls[0]),
  };
}

async function resolveControls(client, scenario) {
  const references = new Map();
  for (const action of scenario.actions) {
    if (action.click) references.set(action.click.key, action.click);
    for (const {target} of action.expect.values) {
      references.set(target.key, target);
    }
  }
  const result = {};
  for (const reference of references.values()) {
    await client.execute("macos: activateApp", [{bundleId: APP.brave.bundleID}]);
    await runAppleScript(
      client,
      raiseScript({app: reference.app, key: reference.window}),
    );
    await sleep(150);
    result[reference.key] = await locateControl(client, reference);
  }
  return result;
}

function readMachineState() {
  const output = execFileSync("xcrun", ["swift", path.join(here, "state.swift")], {
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
  });
  return JSON.parse(output);
}

function positionPointer(rect) {
  const x = rect.x + rect.width / 2;
  const y = rect.y + rect.height / 2;
  const output = execFileSync(
    "xcrun",
    ["swift", path.join(here, "pointer.swift"), String(x), String(y)],
    {encoding: "utf8", timeout: 30_000},
  );
  return JSON.parse(output);
}

function startVirtualHIDDaemon() {
  execFileSync(
    "/usr/bin/sudo",
    ["-n", "/bin/launchctl", "kickstart", VIRTUAL_HID_JOB],
    {encoding: "utf8", timeout: 10_000},
  );
}

async function assertDaemonRunning() {
  await sleep(500);
  const output = execFileSync("/bin/launchctl", ["print", VIRTUAL_HID_JOB], {
    encoding: "utf8",
    timeout: 10_000,
  });
  if (!/^\s*state = running$/m.test(output)) {
    throw new Error("VirtualHID LaunchDaemon is not running");
  }
}

async function stopVirtualHIDDaemon() {
  execFileSync(
    "/usr/bin/sudo",
    ["-n", "/bin/launchctl", "kill", "SIGTERM", VIRTUAL_HID_JOB],
    {encoding: "utf8", timeout: 10_000},
  );
  await sleep(300);
}

function sendVirtualHIDClick() {
  return execFileSync("/usr/bin/sudo", ["-n", VIRTUAL_HID_CLICK], {
    encoding: "utf8",
    timeout: 30_000,
  }).trim();
}

function identifyWindow(record, declared) {
  if (record.layer !== 0) return null;
  if (record.bundleID === APP.vscode.bundleID) {
    return declared.some(({key}) => key === "vscode") ? "vscode" : null;
  }
  if (record.bundleID === APP.brave.bundleID) {
    return declared.find(({key}) => record.title.startsWith(`${key} —`))?.key ?? null;
  }
  return null;
}

function identifyWindows(state, declared) {
  return state.windows
    .map((record) => ({record, key: identifyWindow(record, declared)}))
    .filter(({key}) => key);
}

function observedControlValue(reference, identifiedWindows) {
  if (reference.app === "brave" && reference.control === "counter") {
    const window = identifiedWindows.find(({key}) => key === reference.window);
    if (!window) throw new Error(`window not found for ${reference.key}`);
    return fixtureCounterFromWindowTitle(window.record.title);
  }
  throw new Error(`control value lookup is not implemented for ${reference.key}`);
}

function verifyState(scenario, state, controls, focusedWindowTitle) {
  if (!state.screenCaptureAllowed) {
    throw new Error("Screen Recording is required to verify global window order");
  }
  const declared = allWindows(scenario.windows);
  const identified = identifyWindows(state, declared);
  const checks = [];
  const addCheck = (name, pass, actual, expected) => {
    checks.push({name, pass, actual, expected});
  };

  addCheck(
    "display count",
    state.displays.length === scenario.windows.length,
    state.displays.length,
    scenario.windows.length,
  );
  addCheck(
    "declared window count",
    identified.length === declared.length,
    identified.length,
    declared.length,
  );

  for (const window of declared) {
    const matches = identified.filter(({key}) => key === window.key);
    addCheck(`${window.key} unique`, matches.length === 1, matches.length, 1);
    addCheck(
      `${window.key} display`,
      matches[0]?.record.display === window.display,
      matches[0]?.record.display,
      window.display,
    );
  }

  const bravePIDs = new Set(
    identified
      .filter(({record}) => record.bundleID === APP.brave.bundleID)
      .map(({record}) => record.pid),
  );
  addCheck("Brave process count", bravePIDs.size === 1, bravePIDs.size, 1);

  for (const display of scenario.windows) {
    const expected = [...display.windows].reverse().map(({key}) => key);
    const actual = identified
      .filter(({record}) => record.display === display.display)
      .sort((left, right) => left.record.zIndex - right.record.zIndex)
      .map(({key}) => key);
    addCheck(
      `D${display.display} front-to-back`,
      JSON.stringify(actual) === JSON.stringify(expected),
      actual,
      expected,
    );
  }

  const active = declared.find(({active}) => active);
  const expectedApplicationIsFrontmost =
    state.frontmostBundleID === APP[active.app].bundleID;
  addCheck(
    "frontmost application",
    expectedApplicationIsFrontmost,
    state.frontmostBundleID,
    APP[active.app].bundleID,
  );
  const focusedWindow =
    active.app === "vscode"
      ? identified.find(
        ({key, record}) => key === "vscode" && record.title === focusedWindowTitle,
      )?.key
      : identified.find(
        ({key}) => key === active.key && focusedWindowTitle.startsWith(`${key} —`),
      )?.key;
  addCheck("AX focused window", focusedWindow === active.key, focusedWindow, active.key);

  addCheck(
    "control lookup count",
    Object.keys(controls).length > 0,
    Object.keys(controls).length,
    "> 0",
  );
  return {
    checks,
    windows: identified,
    focusedWindow: expectedApplicationIsFrontmost ? focusedWindow : null,
  };
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const source = await readFile(options.scenarioPath, "utf8");
  const scenario = loadScenario(source);
  validateRuntimeVocabulary(scenario);
  const client = new AppiumClient(options.appiumUrl);
  let virtualHIDDaemonStarted = false;
  let recorder = null;
  await client.createSession();
  try {
    const screens = await queryDisplays(client);
    if (screens.length !== scenario.windows.length) {
      throw new Error(
        `scenario declares ${scenario.windows.length} displays; VM reports ${screens.length}`,
      );
    }
    await terminateApplications(client, scenario);
    const declared = allWindows(scenario.windows);
    if (declared.some(({app}) => app === "vscode")) await launchVSCode(client);
    await launchBraveWindows(
      client,
      declared.filter(({app}) => app === "brave"),
      options.fixturePath,
    );
    await setWindowGeometry(client, scenario, screens);
    const controls = await resolveControls(client, scenario);
    await applyStackingAndFocus(client, scenario.windows);
    const active = declared.find(({active}) => active);
    const focusedWindowTitle = await queryFocusedWindowTitle(client, active);
    const state = readMachineState();
    const setupVerification = verifyState(
      scenario,
      state,
      controls,
      focusedWindowTitle,
    );
    const failedSetupCheck = setupVerification.checks.find(({pass}) => !pass);
    if (failedSetupCheck) {
      throw new Error(
        `${failedSetupCheck.name}: expected ${failedSetupCheck.expected}; got ${failedSetupCheck.actual}`,
      );
    }
    if (options.recordingsPath) {
      recorder = new MultiDisplayRecorder({appiumUrl: options.appiumUrl});
      await recorder.open();
      await recorder.start();
      await sleep(750);
    }
    startVirtualHIDDaemon();
    virtualHIDDaemonStarted = true;
    await assertDaemonRunning();
    const assertions = [];
    for (const [index, action] of scenario.actions.entries()) {
      if (action.click) {
        const control = controls[action.click.key];
        positionPointer(control.rect);
        sendVirtualHIDClick();
        await sleep(300);
      }

      const actualState = {};
      let assertionPassed = true;
      let postActionState = null;
      let identifiedPostActionWindows = null;
      if (action.expect.windows) {
        const expectedActive = allWindows(action.expect.windows).find(({active}) => active);
        const expectedFocusedTitle = await queryFocusedWindowTitle(client, expectedActive);
        postActionState = readMachineState();
        const windowVerification = verifyState(
          {windows: action.expect.windows},
          postActionState,
          controls,
          expectedFocusedTitle,
        );
        identifiedPostActionWindows = windowVerification.windows;
        assertionPassed = windowVerification.checks.every(({pass}) => pass);
        actualState.windows = normalizeWindowState(
          action.expect.windows,
          windowVerification.windows,
          windowVerification.focusedWindow,
        );
      }

      if (action.expect.values.length > 0) {
        postActionState ??= readMachineState();
        identifiedPostActionWindows ??= identifyWindows(
          postActionState,
          allWindows(scenario.windows),
        );
        for (const {target, expected} of action.expect.values) {
          let actual = null;
          try {
            actual = observedControlValue(target, identifiedPostActionWindows);
          } catch {
            assertionPassed = false;
          }
          actualState[target.key] = actual;
          if (actual !== expected) {
            assertionPassed = false;
          }
        }
      }

      if (action.expect.windows || action.expect.values.length > 0) {
        assertions.push({
          afterAction: index + 1,
          status: assertionPassed ? "passed" : "failed",
          state: actualState,
        });
      }
    }
    if (recorder) {
      await sleep(750);
      await recorder.stop(options.recordingsPath);
    }
    const result = makeScenarioResult({
      scenarioName: path.basename(options.scenarioPath),
      scenarioSource: source,
      assertions,
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    if (result.status === "failed") process.exitCode = 1;
  } finally {
    try {
      if (virtualHIDDaemonStarted) await stopVirtualHIDDaemon();
    } finally {
      try {
        if (recorder?.recording) {
          await recorder.stop(options.recordingsPath).catch(() => {});
        }
        await recorder?.close();
      } finally {
        await client.deleteSession().catch(() => {});
      }
    }
  }
}

main().catch((error) => {
  console.error(error.stack ?? error.message);
  process.exitCode = 1;
});
