import {execFileSync} from "node:child_process";

import {AppiumClient} from "../ScenarioExecutor/appium.mjs";

const action = process.argv[2];
const appiumUrl = process.argv[3] ?? "http://127.0.0.1:4723";
if (!new Set(["enable", "disable", "hidden-running", "stopped"]).has(action)) {
  throw new Error(
    "usage: start-at-login.mjs enable|disable|hidden-running|stopped [appium-url]",
  );
}

const bundleIdentifier = "io.e10n.jfc";

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function processCount(name) {
  try {
    return execFileSync("/usr/bin/pgrep", ["-x", name], {
      encoding: "utf8",
      timeout: 10_000,
    }).trim().split(/\s+/).filter(Boolean).length;
  } catch (error) {
    if (error.status === 1) return 0;
    throw error;
  }
}

function toggleIsOn(value) {
  return new Set(["1", "true", "yes", "on", "checked"]).has(
    String(value).trim().toLowerCase(),
  );
}

async function waitForStatus(client, expected) {
  let observed = null;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const elements = await client.findElements(
      "accessibility id",
      "Start at Login Status",
    );
    if (elements.length === 1) {
      observed = {
        label: await client.elementAttribute(elements[0], "label"),
        value: await client.elementAttribute(elements[0], "value"),
        title: await client.elementAttribute(elements[0], "title"),
      };
      if (Object.values(observed).some((value) => String(value).includes(expected))) {
        return observed;
      }
    } else if (elements.length > 1) {
      throw new Error(`expected one Start at Login status; observed ${elements.length}`);
    }
    await sleep(250);
  }
  throw new Error(
    `Start at Login status did not become ${expected}: ${JSON.stringify(observed)}`,
  );
}

async function waitForToggle(client) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const toggles = await client.findElements(
      "accessibility id",
      "Start at Login Toggle",
    );
    if (toggles.length === 1) return toggles[0];
    if (toggles.length > 1) {
      throw new Error(`expected one Start at Login toggle; observed ${toggles.length}`);
    }
    await sleep(250);
  }
  throw new Error("Start at Login toggle did not appear");
}

async function setRegistration(client, enabled) {
  execFileSync("/usr/bin/open", ["-a", "/Applications/JFC.app"], {
    encoding: "utf8",
    timeout: 10_000,
  });
  await sleep(1_000);
  await client.execute("macos: activateApp", [{bundleId: bundleIdentifier}]);

  const toggle = await waitForToggle(client);
  let value = await client.elementAttribute(toggle, "value");
  if (toggleIsOn(value) !== enabled) {
    await client.clickElement(toggle);
  }

  let status = null;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    value = await client.elementAttribute(toggle, "value");
    if (toggleIsOn(value) === enabled) break;
    await sleep(250);
  }
  if (toggleIsOn(value) !== enabled) {
    throw new Error(
      `Start at Login did not become ${enabled ? "enabled" : "disabled"}: `
        + JSON.stringify({toggleValue: value}),
    );
  }
  status = await waitForStatus(client, enabled ? "Enabled" : "Disabled");
  return {toggleValue: value, serviceStatus: status};
}

async function hiddenApplicationState(client) {
  const application = await client.execute("macos: appleScript", [{
    language: "JavaScript",
    timeout: 60_000,
    script: `
ObjC.import("AppKit");
const applications = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(
  "${bundleIdentifier}",
).js;
if (applications.length !== 1) {
  throw new Error("expected one JFC running application; observed " + applications.length);
}
const application = applications[0];
JSON.stringify({
  activationPolicy: Number(application.activationPolicy),
  active: Boolean(application.active),
  hidden: Boolean(application.hidden),
});
`,
  }]);
  const window = await client.execute("macos: appleScript", [{
    timeout: 60_000,
    script: `
tell application "System Events"
  tell application process "JFC"
    set visibleWindowCount to count of (windows whose visible is true)
    return (visibleWindowCount as text) & "|" & (frontmost as text)
  end tell
end tell
`,
  }]);
  const [visibleWindowCount, frontmost] = window.trim().split("|");
  return {
    ...JSON.parse(application.trim()),
    visibleWindowCount: Number(visibleWindowCount),
    frontmost: frontmost.trim().toLowerCase() === "true",
  };
}

const processes = {
  jfc: processCount("JFC"),
  clickAgent: processCount("JFCClickAgent"),
  loginItem: processCount("JFCLoginItem"),
};

if (action === "stopped") {
  if (processes.jfc !== 0 || processes.clickAgent !== 0 || processes.loginItem !== 0) {
    throw new Error(`JFC started after Start at Login was disabled: ${JSON.stringify(processes)}`);
  }
  process.stdout.write(
    `${JSON.stringify({status: "passed", action, processes})}\n`,
  );
  process.exit(0);
}

const client = new AppiumClient(appiumUrl);
await client.createSession();
try {
  if (action === "enable" || action === "disable") {
    const enabled = action === "enable";
    const service = await setRegistration(client, enabled);
    process.stdout.write(
      `${JSON.stringify({status: "passed", action, service})}\n`,
    );
  } else {
    const application = await hiddenApplicationState(client);
    if (processes.jfc !== 1 || processes.clickAgent !== 1 || processes.loginItem !== 0) {
      throw new Error(`unexpected login-launch processes: ${JSON.stringify(processes)}`);
    }
    if (
      application.activationPolicy !== 1
      || application.active
      || application.visibleWindowCount !== 0
      || application.frontmost
    ) {
      throw new Error(`login launch was not hidden and accessory: ${JSON.stringify(application)}`);
    }
    process.stdout.write(
      `${JSON.stringify({
        status: "passed",
        action,
        processes,
        application,
      })}\n`,
    );
  }
} finally {
  await client.deleteSession();
}
