import {readFile, writeFile} from "node:fs/promises";
import path from "node:path";

async function readJSON(filename) {
  return JSON.parse(await readFile(filename, "utf8"));
}

async function readJSONLines(filename) {
  return (await readFile(filename, "utf8"))
    .split("\n")
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        throw new Error(`${filename}:${index + 1}: ${error.message}`);
      }
    });
}

function requireField(object, field, context) {
  if (!(field in object)) throw new Error(`${context} is missing ${field}`);
}

export function validateConditionStream(entries, role) {
  const identity = entries.find(({kind}) => kind === "identity");
  const complete = entries.findLast(({kind}) => kind === "complete");
  const samples = entries.filter(({kind}) => kind === "sample");
  if (!identity || identity.role !== role) {
    throw new Error(`${role} conditions are missing identity`);
  }
  if (!Number.isFinite(identity.samplingIntervalSeconds)) {
    throw new Error(`${role} conditions are missing sampling interval`);
  }
  if (!complete || complete.role !== role) {
    throw new Error(`${role} conditions are missing completion marker`);
  }
  if (samples.length === 0 || complete.sampleCount !== samples.length) {
    throw new Error(`${role} condition sample count is incomplete`);
  }
  for (const [index, sample] of samples.entries()) {
    const context = `${role} sample ${index + 1}`;
    for (const field of [
      "epochMilliseconds",
      "monotonicNanoseconds",
      "cpu",
      "memory",
      "paging",
      "swap",
      "io",
      "thermal",
      "processes",
      "collectionMilliseconds",
    ]) {
      requireField(sample, field, context);
    }
    if (!Number.isFinite(sample.cpu.utilization)) {
      throw new Error(`${context} has invalid CPU utilization`);
    }
    if (!Array.isArray(sample.processes)) {
      throw new Error(`${context} has invalid process data`);
    }
  }
  return samples;
}

export function validateActionTimings(entries, scenario) {
  const startedActions = entries.filter(({kind}) => kind === "actionStarted");
  const completedActions = entries.filter(({kind}) => kind === "actionCompleted");
  if (
    startedActions.length !== scenario.actions.length
    || completedActions.length !== scenario.actions.length
  ) {
    throw new Error(
      `action timing count is ${startedActions.length}/${completedActions.length}; expected ${scenario.actions.length}`,
    );
  }
  return scenario.actions.map((scenarioAction, index) => {
    const action = index + 1;
    const starts = startedActions.filter((entry) => entry.action === action);
    const completions = completedActions.filter((entry) => entry.action === action);
    if (starts.length !== 1 || completions.length !== 1) {
      throw new Error(`action ${action} timing entries are not unique`);
    }
    const started = starts[0];
    const completion = completions[0];
    const expectedControl = scenarioAction.click ?? null;
    if (started.control !== expectedControl || completion.control !== expectedControl) {
      throw new Error(`action ${action} timing control does not match the scenario`);
    }
    for (const [entry, context] of [
      [started, "start"],
      [completion, "completion"],
    ]) {
      if (!Number.isFinite(entry.epochMilliseconds)) {
        throw new Error(`action ${action} ${context} has invalid wall-clock time`);
      }
      try {
        BigInt(entry.monotonicNanoseconds);
      } catch {
        throw new Error(`action ${action} ${context} has invalid monotonic time`);
      }
    }
    if (
      !["passed", "failed"].includes(completion.status)
      || !Number.isFinite(completion.durationMilliseconds)
      || completion.durationMilliseconds < 0
    ) {
      throw new Error(`action ${action} has invalid completion data`);
    }
    const phases = entries.filter((entry) =>
      entry.action === action && entry.kind === "phaseCompleted",
    );
    const expectedPhases = scenarioAction.click
      ? ["pointerPositioning", "virtualHIDClick", "postClickSettle", "postActionVerification"]
      : ["postActionVerification"];
    if (JSON.stringify(phases.map(({phase}) => phase)) !== JSON.stringify(expectedPhases)) {
      throw new Error(`action ${action} timing phases are incomplete or out of order`);
    }
    if (phases.some(({durationMilliseconds}) =>
      !Number.isFinite(durationMilliseconds) || durationMilliseconds < 0
    )) {
      throw new Error(`action ${action} has an invalid phase duration`);
    }
    return {started, completion, phases};
  });
}

function range(values) {
  const finite = values.filter(Number.isFinite);
  return finite.length === 0 ? null : {minimum: Math.min(...finite), maximum: Math.max(...finite)};
}

function counterDelta(samples, group, field) {
  const values = samples.map((sample) => sample[group]?.[field]).filter(Number.isFinite);
  return values.length < 2 ? null : values.at(-1) - values[0];
}

function processPeaks(samples) {
  const peaks = new Map();
  for (const {processes} of samples) {
    for (const process of processes) {
      const key = `${process.pid}:${process.command}`;
      const previous = peaks.get(key);
      peaks.set(key, {
        pid: process.pid,
        command: process.command,
        maximumCPUPercent: Math.max(previous?.maximumCPUPercent ?? 0, process.cpuPercent),
        maximumResidentKilobytes: Math.max(
          previous?.maximumResidentKilobytes ?? 0,
          process.residentKilobytes,
        ),
      });
    }
  }
  return [...peaks.values()]
    .sort((left, right) =>
      right.maximumCPUPercent - left.maximumCPUPercent
      || right.maximumResidentKilobytes - left.maximumResidentKilobytes,
    )
    .slice(0, 20);
}

function summarizeConditions(samples) {
  return {
    sampleCount: samples.length,
    firstRecordedAt: samples[0].recordedAt,
    lastRecordedAt: samples.at(-1).recordedAt,
    maximumScheduledLagMilliseconds: Math.max(
      ...samples.map(({scheduledLagMilliseconds}) => scheduledLagMilliseconds),
    ),
    maximumCollectionMilliseconds: Math.max(
      ...samples.map(({collectionMilliseconds}) => collectionMilliseconds),
    ),
    cpuUtilization: range(samples.map(({cpu}) => cpu.utilization)),
    freeMemoryBytes: range(samples.map(({memory}) => memory.freeBytes)),
    usedSwapBytes: range(samples.map(({swap}) => swap.usedBytes)),
    pagingDelta: {
      pageIns: counterDelta(samples, "paging", "pageIns"),
      pageOuts: counterDelta(samples, "paging", "pageOuts"),
      swapIns: counterDelta(samples, "paging", "swapIns"),
      swapOuts: counterDelta(samples, "paging", "swapOuts"),
    },
    firstIO: samples[0].io,
    lastIO: samples.at(-1).io,
    thermalStates: [...new Set(samples.map(({thermal}) => JSON.stringify(thermal)))],
    processPeaks: processPeaks(samples),
  };
}

function nearestSample(samples, epochMilliseconds) {
  return samples.reduce((nearest, sample) =>
    Math.abs(sample.epochMilliseconds - epochMilliseconds)
      < Math.abs(nearest.epochMilliseconds - epochMilliseconds)
      ? sample
      : nearest,
  );
}

export async function validateDiagnostics(directory, scenarioPath) {
  const [hostEntries, guestEntries, actions, clock, scenario] = await Promise.all([
    readJSONLines(path.join(directory, "host-conditions.jsonl")),
    readJSONLines(path.join(directory, "guest-conditions.jsonl")),
    readJSONLines(path.join(directory, "action-timings.jsonl")),
    readJSON(path.join(directory, "clock-alignment.json")),
    readJSON(scenarioPath),
  ]);
  const hostSamples = validateConditionStream(hostEntries, "host");
  const guestSamples = validateConditionStream(guestEntries, "guest");
  const actionTimings = validateActionTimings(actions, scenario);
  if (!clock.selected || !Number.isFinite(clock.selected.guestMinusHostMilliseconds)) {
    throw new Error("clock alignment is missing a selected sample");
  }
  const offset = clock.selected.guestMinusHostMilliseconds;
  const actionSamples = actionTimings.map(({started, completion, phases}) => {
    const hostEpoch = started.epochMilliseconds - offset;
    const fixtureInputTraces = actions
      .filter((entry) => entry.kind === "fixtureInputTrace" && entry.action === started.action)
      .map(({window, events}) => ({window, events}));
    return {
      action: started.action,
      control: started.control,
      guestEpochMilliseconds: started.epochMilliseconds,
      nearestHostSample: nearestSample(hostSamples, hostEpoch),
      nearestGuestSample: nearestSample(guestSamples, started.epochMilliseconds),
      phases,
      completion,
      fixtureInputTraces,
    };
  });
  const summary = {
    schemaVersion: 1,
    validatedAt: new Date().toISOString(),
    clockAlignment: clock.selected,
    host: {
      identity: hostEntries.find(({kind}) => kind === "identity"),
      ...summarizeConditions(hostSamples),
    },
    guest: {
      identity: guestEntries.find(({kind}) => kind === "identity"),
      ...summarizeConditions(guestSamples),
    },
    actions: actionSamples,
  };
  await writeFile(
    path.join(directory, "diagnostics-summary.json"),
    `${JSON.stringify(summary, null, 2)}\n`,
  );
  return summary;
}

async function main() {
  const [directory, scenarioPath] = process.argv.slice(2);
  if (!directory || !scenarioPath) {
    throw new Error("usage: validate.mjs ARTIFACT_DIRECTORY SCENARIO.json");
  }
  await validateDiagnostics(directory, scenarioPath);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error.stack ?? error.message);
    process.exitCode = 1;
  });
}
