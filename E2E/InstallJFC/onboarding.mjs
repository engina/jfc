import {AppiumClient} from "../ScenarioExecutor/appium.mjs";

const expectedState = process.argv[2];
const appiumUrl = process.argv[3] ?? "http://127.0.0.1:4723";
if (!new Set(["untrusted", "trusted"]).has(expectedState)) {
  throw new Error("usage: onboarding.mjs untrusted|trusted [appium-url]");
}

const client = new AppiumClient(appiumUrl);

async function count(name) {
  return (await client.findElements("accessibility id", name)).length;
}

await client.createSession();
try {
  await client.execute("macos: activateApp", [
    {bundleId: "io.e10n.jfc"},
  ]);
  const observed = {
    onboardingButton: await count("Open System Settings"),
    grantedIndicator: await count("Granted"),
    runningIndicator: await count("Running"),
    stopButton: await count("Stop JFC"),
  };

  if (expectedState === "untrusted") {
    if (observed.onboardingButton !== 1) {
      throw new Error(
        `expected one first-run permission button; observed ${JSON.stringify(observed)}`,
      );
    }
    if (
      observed.grantedIndicator !== 0
      || observed.runningIndicator !== 0
      || observed.stopButton !== 0
    ) {
      throw new Error(`fresh install was already trusted: ${JSON.stringify(observed)}`);
    }
  } else if (
    observed.onboardingButton !== 0
    || observed.grantedIndicator !== 1
    || observed.runningIndicator !== 1
    || observed.stopButton !== 1
  ) {
    throw new Error(`installed JFC is not trusted and running: ${JSON.stringify(observed)}`);
  }

  process.stdout.write(`${JSON.stringify({status: "passed", expectedState, observed})}\n`);
} finally {
  await client.deleteSession();
}
