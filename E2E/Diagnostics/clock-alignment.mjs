import {execFileSync} from "node:child_process";
import {writeFileSync} from "node:fs";

export function selectClockSample(samples) {
  if (samples.length === 0) throw new Error("clock alignment requires samples");
  return [...samples].sort(
    (left, right) => left.roundTripMilliseconds - right.roundTripMilliseconds,
  )[0];
}

export function measureClock(host, probes = 5) {
  const samples = [];
  for (let index = 0; index < probes; index += 1) {
    const before = Date.now();
    const guest = Number(execFileSync("/usr/bin/ssh", [
      host,
      "/opt/homebrew/bin/node -e 'process.stdout.write(String(Date.now()))'",
    ], {encoding: "utf8"}));
    const after = Date.now();
    const midpoint = before + (after - before) / 2;
    samples.push({
      beforeHostEpochMilliseconds: before,
      guestEpochMilliseconds: guest,
      afterHostEpochMilliseconds: after,
      roundTripMilliseconds: after - before,
      guestMinusHostMilliseconds: guest - midpoint,
    });
  }
  return {
    schemaVersion: 1,
    recordedAt: new Date().toISOString(),
    samples,
    selected: selectClockSample(samples),
  };
}

function main() {
  const [host, output] = process.argv.slice(2);
  if (!host || !output) {
    throw new Error("usage: clock-alignment.mjs HOST OUTPUT.json");
  }
  writeFileSync(output, `${JSON.stringify(measureClock(host), null, 2)}\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main();
  } catch (error) {
    console.error(error.stack ?? error.message);
    process.exitCode = 1;
  }
}
