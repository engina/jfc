import assert from "node:assert/strict";
import {setTimeout as sleep} from "node:timers/promises";
import test from "node:test";

import {
  cpuUtilization,
  interruptibleSleep,
  isRelevantProcessCommand,
  parseProcesses,
  parseSwapUsage,
  parseVMStat,
} from "./conditions.mjs";

test("parses virtual memory, paging, and swap counters", () => {
  const vm = parseVMStat(`Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free: 10.
Pages active: 20.
Pages inactive: 30.
Pages speculative: 2.
Pages wired down: 40.
Pages occupied by compressor: 5.
Translation faults: 1,000.
Pages copy-on-write: 100.
Pageins: 25.
Pageouts: 3.
Swapins: 4.
Swapouts: 2.`);
  assert.equal(vm.memory.freeBytes, 163_840);
  assert.equal(vm.memory.compressedBytes, 81_920);
  assert.deepEqual(vm.paging, {
    faults: 1_000,
    copyOnWriteFaults: 100,
    pageIns: 25,
    pageOuts: 3,
    swapIns: 4,
    swapOuts: 2,
  });
  assert.deepEqual(
    parseSwapUsage("total = 4.00G  used = 512.00M  free = 3.50G  (encrypted)"),
    {totalBytes: 4 * 1024 ** 3, usedBytes: 512 * 1024 ** 2, freeBytes: 3.5 * 1024 ** 3},
  );
});

test("computes CPU utilization and parses bounded process input", () => {
  const cpu = cpuUtilization(
    [{user: 10, nice: 0, sys: 10, idle: 80, irq: 0}],
    [{user: 20, nice: 0, sys: 20, idle: 160, irq: 0}],
  );
  assert.equal(cpu.utilization, 0.2);
  assert.deepEqual(parseProcesses(" 12 1 3.5 1.2 4096 /Applications/JFC.app/Contents/MacOS/JFC"), [{
    pid: 12,
    parentPID: 1,
    cpuPercent: 3.5,
    memoryPercent: 1.2,
    residentKilobytes: 4096,
    command: "/Applications/JFC.app/Contents/MacOS/JFC",
  }]);
  for (const command of [
    "/Applications/UTM.app/Contents/MacOS/UTM",
    "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer",
    "/Applications/JFC.app/Contents/MacOS/JFC",
    "/Library/Application Support/org.pqrs/Karabiner-VirtualHIDDevice-Daemon",
  ]) {
    assert.equal(isRelevantProcessCommand(command), true, command);
  }
  assert.equal(isRelevantProcessCommand("/usr/bin/unrelated"), false);
});

test("interrupts a long sampling wait promptly", async () => {
  const controller = new AbortController();
  const started = performance.now();
  const waiting = interruptibleSleep(30_000, controller.signal);
  await sleep(10);
  controller.abort();
  await waiting;
  assert.ok(performance.now() - started < 1_000);
});
