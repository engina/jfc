import {execFileSync} from "node:child_process";

import {AppiumClient} from "../ScenarioExecutor/appium.mjs";

const action = process.argv[2];
const appiumUrl = process.argv[3] ?? "http://127.0.0.1:4723";
if (!new Set(["recover", "start", "stop", "status"]).has(action)) {
  throw new Error("usage: agent-lifecycle.mjs recover|start|stop|status [appium-url]");
}

const client = new AppiumClient(appiumUrl);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function count(identifier) {
  return (await client.findElements("accessibility id", identifier)).length;
}

async function readState() {
  return {
    granted: await count("Granted"),
    running: await count("Running"),
    stopped: await count("Stopped"),
    startButton: await count("Start JFC"),
    stopButton: await count("Stop JFC"),
  };
}

function matches(state, expected) {
  if (state.granted !== 1) return false;
  if (expected === "running") {
    return state.running === 1 && state.stopButton === 1
      && state.stopped === 0 && state.startButton === 0;
  }
  return state.stopped === 1 && state.startButton === 1
    && state.running === 0 && state.stopButton === 0;
}

async function waitForState(expected) {
  let state;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    state = await readState();
    if (matches(state, expected)) return state;
    await sleep(250);
  }
  throw new Error(`JFC did not become ${expected}: ${JSON.stringify(state)}`);
}

await client.createSession();
try {
  execFileSync("/usr/bin/open", ["-a", "/Applications/JFC.app"], {
    encoding: "utf8",
    timeout: 10_000,
  });
  await sleep(1_000);
  await client.execute("macos: activateApp", [
    {bundleId: "io.e10n.jfc"},
  ]);

  let recovery;
  if (action === "recover") {
    const before = Number(
      execFileSync("/usr/bin/pgrep", ["-x", "JFCClickAgent"], {
        encoding: "utf8",
        timeout: 10_000,
      }).trim(),
    );
    execFileSync("/bin/kill", [String(before)], {
      encoding: "utf8",
      timeout: 10_000,
    });
    let after;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      await sleep(250);
      try {
        after = Number(
          execFileSync("/usr/bin/pgrep", ["-x", "JFCClickAgent"], {
            encoding: "utf8",
            timeout: 10_000,
          }).trim(),
        );
      } catch {
        continue;
      }
      if (after !== before) break;
    }
    if (!after || after === before) {
      throw new Error(`click agent did not recover after terminating pid ${before}`);
    }
    recovery = {before, after};
  } else if (action !== "status") {
    const buttonName = action === "start" ? "Start JFC" : "Stop JFC";
    const buttons = await client.findElements("accessibility id", buttonName);
    if (buttons.length !== 1) {
      throw new Error(`expected one ${buttonName}; observed ${buttons.length}`);
    }
    await client.clickElement(buttons[0]);
  }

  const expected = action === "stop" ? "stopped" : "running";
  const state = await waitForState(expected);
  process.stdout.write(
    `${JSON.stringify({status: "passed", action, state, ...(recovery && {recovery})})}\n`,
  );
} finally {
  await client.deleteSession();
}
