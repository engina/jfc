import {appendFileSync, writeFileSync} from "node:fs";

function monotonicNanoseconds() {
  return process.hrtime.bigint();
}

export class ActionTimingLog {
  constructor({filename, scenario}) {
    this.filename = filename;
    this.scenario = scenario;
    writeFileSync(filename, "");
  }

  write(value) {
    appendFileSync(this.filename, `${JSON.stringify({
      schemaVersion: 1,
      scenario: this.scenario,
      epochMilliseconds: Date.now(),
      monotonicNanoseconds: monotonicNanoseconds().toString(),
      ...value,
    })}\n`);
  }

  beginAction(action, control) {
    const started = monotonicNanoseconds();
    this.write({kind: "actionStarted", action, control});
    const phase = (name, operation) => {
      const phaseStarted = monotonicNanoseconds();
      try {
        const result = operation();
        this.write({
          kind: "phaseCompleted",
          action,
          control,
          phase: name,
          durationMilliseconds: Number(monotonicNanoseconds() - phaseStarted) / 1e6,
        });
        return result;
      } catch (error) {
        this.write({kind: "phaseFailed", action, control, phase: name, error: error.message});
        throw error;
      }
    };
    const beginPhase = (name) => {
      const phaseStarted = monotonicNanoseconds();
      return {
        complete: () => this.write({
          kind: "phaseCompleted",
          action,
          control,
          phase: name,
          durationMilliseconds: Number(monotonicNanoseconds() - phaseStarted) / 1e6,
        }),
        fail: (error) => this.write({
          kind: "phaseFailed",
          action,
          control,
          phase: name,
          error: error.message,
        }),
      };
    };
    return {
      phaseSync: phase,
      beginPhase,
      phase: async (name, operation) => {
        const phaseStarted = monotonicNanoseconds();
        try {
          const result = await operation();
          this.write({
            kind: "phaseCompleted",
            action,
            control,
            phase: name,
            durationMilliseconds: Number(monotonicNanoseconds() - phaseStarted) / 1e6,
          });
          return result;
        } catch (error) {
          this.write({kind: "phaseFailed", action, control, phase: name, error: error.message});
          throw error;
        }
      },
      complete: (status, verificationFailures = []) => this.write({
        kind: "actionCompleted",
        action,
        control,
        status,
        verificationFailures,
        durationMilliseconds: Number(monotonicNanoseconds() - started) / 1e6,
      }),
      fail: (error) => this.write({
        kind: "actionFailed",
        action,
        control,
        error: error.message,
        durationMilliseconds: Number(monotonicNanoseconds() - started) / 1e6,
      }),
    };
  }
}
