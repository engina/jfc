import {execFileSync} from "node:child_process";
import path from "node:path";
import {fileURLToPath} from "node:url";

import {AppiumClient} from "../ScenarioExecutor/appium.mjs";

const action = process.argv[2];
const appiumUrl = process.argv[3] ?? "http://127.0.0.1:4723";
if (!new Set(["status", "grant"]).has(action)) {
  throw new Error("usage: accessibility-permission.mjs status|grant [appium-url]");
}

const here = path.dirname(fileURLToPath(import.meta.url));
const pointerScript = path.resolve(here, "../ScenarioExecutor/pointer.swift");
const authorizationScript = path.join(here, "complete-authorization.jxa");
const virtualHIDClick = "/usr/local/libexec/jfc-e2e-virtual-hid-click";
const virtualHIDJob = "system/io.e10n.jfc.e2e.virtual-hid";
const client = new AppiumClient(appiumUrl);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function findExactlyOne(identifier) {
  const elements = await client.findElements("accessibility id", identifier);
  if (elements.length !== 1) {
    throw new Error(`expected one ${identifier}; observed ${elements.length}`);
  }
  return elements[0];
}

async function openAccessibilitySettings() {
  await client.execute("macos: activateApp", [
    {bundleId: "io.e10n.jfc"},
  ]);
  const onboardingButtons = await client.findElements(
    "accessibility id",
    "Open System Settings",
  );
  if (onboardingButtons.length === 1) {
    await client.clickElement(onboardingButtons[0]);
    await sleep(1_500);
  }
  await client.execute("macos: activateApp", [
    {bundleId: "com.apple.systempreferences"},
  ]);
}

async function readToggle() {
  const element = await findExactlyOne("JFC Click Agent_Toggle");
  return {
    element,
    value: await client.elementAttribute(element, "value"),
    rect: await client.elementRect(element),
  };
}

function completeAuthorizationPrompt() {
  const password = process.env.JFC_E2E_VM_PASSWORD;
  if (!password || /[\r\n]/.test(password)) {
    throw new Error("JFC_E2E_VM_PASSWORD must contain one non-empty line");
  }
  execFileSync(
    "/usr/bin/osascript",
    ["-l", "JavaScript", authorizationScript],
    {input: password, encoding: "utf8", timeout: 10_000},
  );
}

function startVirtualHID() {
  execFileSync(
    "/usr/bin/sudo",
    ["-n", "/bin/launchctl", "kickstart", virtualHIDJob],
    {encoding: "utf8", timeout: 10_000},
  );
}

function stopVirtualHID() {
  execFileSync(
    "/usr/bin/sudo",
    ["-n", "/bin/launchctl", "kill", "SIGTERM", virtualHIDJob],
    {encoding: "utf8", timeout: 10_000},
  );
}

async function waitForVirtualHID() {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    await sleep(250);
    const output = execFileSync(
      "/bin/launchctl",
      ["print", virtualHIDJob],
      {encoding: "utf8", timeout: 10_000},
    );
    if (/^\s*state = running$/m.test(output)) return;
  }
  throw new Error("VirtualHID LaunchDaemon did not start");
}

function positionPointer(rect) {
  const x = rect.x + rect.width / 2;
  const y = rect.y + rect.height / 2;
  return JSON.parse(
    execFileSync(
      "xcrun",
      ["swift", pointerScript, String(x), String(y)],
      {encoding: "utf8", timeout: 30_000},
    ),
  );
}

async function readJFCState() {
  await client.execute("macos: activateApp", [
    {bundleId: "io.e10n.jfc"},
  ]);
  return {
    onboardingButton: (
      await client.findElements("accessibility id", "Open System Settings")
    ).length,
    grantedIndicator: (
      await client.findElements("accessibility id", "Granted")
    ).length,
    runningIndicator: (
      await client.findElements("accessibility id", "Running")
    ).length,
    stopButton: (
      await client.findElements("accessibility id", "Stop JFC")
    ).length,
  };
}

async function main() {
  await client.createSession();
  let virtualHIDStarted = false;
  try {
    await openAccessibilitySettings();
    const before = await readToggle();
    const result = {
      action,
      toggleBefore: {value: before.value, rect: before.rect},
    };

    if (action === "grant") {
      if (String(before.value) !== "0") {
        throw new Error(
          `Accessibility toggle must begin off; observed ${before.value}`,
        );
      }
      startVirtualHID();
      virtualHIDStarted = true;
      await waitForVirtualHID();
      result.pointer = positionPointer(before.rect);
      result.click = execFileSync("/usr/bin/sudo", ["-n", virtualHIDClick], {
        encoding: "utf8",
        timeout: 30_000,
      }).trim();
      await sleep(750);
      completeAuthorizationPrompt();

      let after = null;
      for (let attempt = 0; attempt < 40; attempt += 1) {
        await sleep(250);
        after = await readToggle();
        if (String(after.value) === "1") break;
      }
      result.toggleAfter = {value: after.value, rect: after.rect};
      if (String(after.value) !== "1") {
        throw new Error(`Accessibility toggle did not turn on; observed ${after.value}`);
      }
      await sleep(1_000);
    }

    result.jfc = await readJFCState();
    if (
      action === "grant"
      && (result.jfc.onboardingButton !== 0
        || result.jfc.grantedIndicator !== 1
        || result.jfc.runningIndicator !== 1
        || result.jfc.stopButton !== 1)
    ) {
      throw new Error(
        `JFC did not become trusted and running: ${JSON.stringify(result.jfc)}`,
      );
    }
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } finally {
    if (virtualHIDStarted) {
      try {
        stopVirtualHID();
      } catch {
        // The one-shot test must still release the Appium session.
      }
    }
    await client.deleteSession();
  }
}

await main();
