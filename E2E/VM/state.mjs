const uuidPattern = /^[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}$/;

export function validateDisposableVMState(state) {
  if (state?.schemaVersion !== 1) {
    throw new Error("unsupported or missing VM state schema");
  }
  for (const key of ["baseline", "clone"]) {
    if (!uuidPattern.test(state[key]?.uuid ?? "")) {
      throw new Error(`invalid ${key} UUID in VM state`);
    }
    if (typeof state[key]?.name !== "string" || !state[key].name) {
      throw new Error(`invalid ${key} name in VM state`);
    }
  }
  if (state.clone.uuid === state.baseline.uuid) {
    throw new Error("disposable clone UUID equals immutable baseline UUID");
  }
  if (!state.baseline.name.endsWith(" - preinstall baseline")) {
    throw new Error("VM state does not identify a preinstall baseline");
  }
  if (!state.clone.name.startsWith("JFC E2E disposable - ")) {
    throw new Error("VM state does not identify a disposable JFC clone");
  }
  return state;
}
