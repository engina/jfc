import {execFileSync} from "node:child_process";
import {closeSync, openSync, writeSync} from "node:fs";
import os from "node:os";
import {performance} from "node:perf_hooks";
import {setTimeout as sleep} from "node:timers/promises";

export async function interruptibleSleep(milliseconds, signal) {
  try {
    await sleep(milliseconds, undefined, {signal});
  } catch (error) {
    if (error.name !== "AbortError") throw error;
  }
}

function command(filename, args) {
  return execFileSync(filename, args, {encoding: "utf8"}).trim();
}

function optionalCommand(filename, args) {
  try {
    return {status: "ok", output: command(filename, args)};
  } catch (error) {
    return {status: "unavailable", error: error.message};
  }
}

function numeric(value) {
  const parsed = Number(String(value).replaceAll(",", ""));
  return Number.isFinite(parsed) ? parsed : null;
}

export function parseVMStat(source) {
  const pageSize = numeric(/page size of (\d+) bytes/.exec(source)?.[1]);
  const pages = {};
  for (const match of source.matchAll(/^([^:]+):\s+([0-9.,]+)\.?$/gm)) {
    pages[match[1].trim()] = numeric(match[2]);
  }
  const bytes = (name) => pageSize === null || pages[name] === undefined
    ? null
    : pages[name] * pageSize;
  return {
    memory: {
      pageSizeBytes: pageSize,
      freeBytes: bytes("Pages free"),
      activeBytes: bytes("Pages active"),
      inactiveBytes: bytes("Pages inactive"),
      speculativeBytes: bytes("Pages speculative"),
      wiredBytes: bytes("Pages wired down"),
      compressedBytes: bytes("Pages occupied by compressor"),
    },
    paging: {
      faults: pages["Translation faults"] ?? null,
      copyOnWriteFaults: pages["Pages copy-on-write"] ?? null,
      pageIns: pages["Pageins"] ?? null,
      pageOuts: pages["Pageouts"] ?? null,
      swapIns: pages["Swapins"] ?? null,
      swapOuts: pages["Swapouts"] ?? null,
    },
  };
}

function sizeBytes(value, unit) {
  const multiplier = {K: 1024, M: 1024 ** 2, G: 1024 ** 3, T: 1024 ** 4}[unit];
  return numeric(value) * multiplier;
}

export function parseSwapUsage(source) {
  const match = /total\s*=\s*([0-9.]+)([KMGT])\s+used\s*=\s*([0-9.]+)([KMGT])\s+free\s*=\s*([0-9.]+)([KMGT])/i.exec(source);
  if (!match) throw new Error(`unrecognized vm.swapusage output: ${source}`);
  return {
    totalBytes: sizeBytes(match[1], match[2].toUpperCase()),
    usedBytes: sizeBytes(match[3], match[4].toUpperCase()),
    freeBytes: sizeBytes(match[5], match[6].toUpperCase()),
  };
}

function cpuTimes() {
  return os.cpus().map(({times}) => ({...times}));
}

export function cpuUtilization(previous, current) {
  const perCore = current.map((times, index) => {
    const before = previous[index] ?? times;
    const total = Object.keys(times).reduce(
      (sum, key) => sum + Math.max(0, times[key] - before[key]),
      0,
    );
    const idle = Math.max(0, times.idle - before.idle);
    return total === 0 ? 0 : (total - idle) / total;
  });
  return {
    utilization: perCore.length === 0
      ? 0
      : perCore.reduce((sum, value) => sum + value, 0) / perCore.length,
    perCore,
    loadAverage: os.loadavg(),
  };
}

export function parseProcesses(source) {
  return source.split("\n").flatMap((line) => {
    const match = /^\s*(\d+)\s+(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+(\d+)\s+(.+?)\s*$/.exec(line);
    if (!match) return [];
    return [{
      pid: Number(match[1]),
      parentPID: Number(match[2]),
      cpuPercent: Number(match[3]),
      memoryPercent: Number(match[4]),
      residentKilobytes: Number(match[5]),
      command: match[6],
    }];
  });
}

export function isRelevantProcessCommand(commandName) {
  return /(?:^|\/)(?:JFC|JFCClickAgent|Brave Browser|Code|node|UTM|utm|Virtualization|WindowServer|kernel_task|qemu-system-aarch64|WebDriverAgentRunner-Runner|Karabiner-VirtualHIDDevice-Daemon)$/.test(
    commandName,
  ) || /jfc-e2e/i.test(commandName);
}

function boundedProcesses() {
  const processes = parseProcesses(command("/bin/ps", [
    "-axo", "pid=,ppid=,%cpu=,%mem=,rss=,comm=",
  ]));
  const selected = new Map();
  const add = (process) => selected.set(process.pid, process);
  processes.filter(({command: name}) => isRelevantProcessCommand(name)).forEach(add);
  [...processes]
    .sort((left, right) => right.cpuPercent - left.cpuPercent)
    .slice(0, 8)
    .forEach(add);
  [...processes]
    .sort((left, right) => right.residentKilobytes - left.residentKilobytes)
    .slice(0, 8)
    .forEach(add);
  return [...selected.values()].sort((left, right) => left.pid - right.pid);
}

function identity(role, samplingIntervalSeconds) {
  return {
    kind: "identity",
    schemaVersion: 1,
    role,
    recordedAt: new Date().toISOString(),
    hostname: os.hostname(),
    platform: os.platform(),
    release: os.release(),
    architecture: os.arch(),
    samplingIntervalSeconds,
    model: optionalCommand("/usr/sbin/sysctl", ["-n", "hw.model"]),
    logicalCPUCount: os.cpus().length,
    totalMemoryBytes: os.totalmem(),
    osVersion: optionalCommand("/usr/bin/sw_vers", ["-productVersion"]),
    kernel: optionalCommand("/usr/bin/uname", ["-a"]),
  };
}

function parseArguments(argv) {
  const result = {role: null, output: null, intervalSeconds: 2};
  const args = [...argv];
  while (args.length > 0) {
    const option = args.shift();
    if (option === "--role") result.role = args.shift();
    else if (option === "--output") result.output = args.shift();
    else if (option === "--interval") result.intervalSeconds = Number(args.shift());
    else throw new Error(`unknown option: ${option}`);
  }
  if (!["host", "guest"].includes(result.role) || !result.output) {
    throw new Error("usage: conditions.mjs --role host|guest --output FILE [--interval SECONDS]");
  }
  if (
    !Number.isFinite(result.intervalSeconds)
    || result.intervalSeconds < 0.5
    || result.intervalSeconds > 3600
  ) {
    throw new Error("diagnostics interval must be between 0.5 and 3600 seconds");
  }
  return result;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const output = openSync(options.output, "w");
  const write = (value) => writeSync(output, `${JSON.stringify(value)}\n`);
  let stopping = false;
  let sleepController = null;
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.on(signal, () => {
      stopping = true;
      sleepController?.abort();
    });
  }

  write(identity(options.role, options.intervalSeconds));
  let previousCPU = cpuTimes();
  let nextSample = performance.now();
  let sampleCount = 0;
  while (!stopping) {
    const started = performance.now();
    const currentCPU = cpuTimes();
    const vm = parseVMStat(command("/usr/bin/vm_stat", []));
    write({
      kind: "sample",
      schemaVersion: 1,
      role: options.role,
      recordedAt: new Date().toISOString(),
      epochMilliseconds: Date.now(),
      monotonicNanoseconds: process.hrtime.bigint().toString(),
      scheduledLagMilliseconds: Math.max(0, started - nextSample),
      cpu: cpuUtilization(previousCPU, currentCPU),
      memory: vm.memory,
      paging: vm.paging,
      swap: parseSwapUsage(command("/usr/sbin/sysctl", ["-n", "vm.swapusage"])),
      io: {iostat: command("/usr/sbin/iostat", ["-Id", "-c", "1"])},
      thermal: optionalCommand("/usr/bin/pmset", ["-g", "therm"]),
      processes: boundedProcesses(),
      collectionMilliseconds: performance.now() - started,
    });
    previousCPU = currentCPU;
    sampleCount += 1;
    nextSample += options.intervalSeconds * 1000;
    const delay = Math.max(0, nextSample - performance.now());
    if (delay > 0 && !stopping) {
      sleepController = new AbortController();
      try {
        await interruptibleSleep(delay, sleepController.signal);
      } finally {
        sleepController = null;
      }
    }
  }
  write({
    kind: "complete",
    schemaVersion: 1,
    role: options.role,
    recordedAt: new Date().toISOString(),
    sampleCount,
  });
  closeSync(output);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error.stack ?? error.message);
    process.exitCode = 1;
  });
}
