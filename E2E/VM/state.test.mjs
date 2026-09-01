import assert from "node:assert/strict";
import test from "node:test";

import {validateDisposableVMState} from "./state.mjs";

const valid = {
  schemaVersion: 1,
  baseline: {
    uuid: "F686D935-20B5-4D17-851C-B36BCC2D6D78",
    name: "JFC macOS 14 - preinstall baseline",
  },
  clone: {
    uuid: "7158D3D2-A56A-4D31-A4CF-2AE58E364AE1",
    name: "JFC E2E disposable - 20260901T050546Z - 123",
  },
};

test("accepts an exact disposable clone state", () => {
  assert.equal(validateDisposableVMState(valid), valid);
});

test("rejects the baseline as a deletion target", () => {
  const state = structuredClone(valid);
  state.clone = structuredClone(state.baseline);
  assert.throws(
    () => validateDisposableVMState(state),
    /clone UUID equals immutable baseline/,
  );
});

test("rejects a VM outside the disposable naming boundary", () => {
  const state = structuredClone(valid);
  state.clone.name = "JFC macOS 14";
  assert.throws(() => validateDisposableVMState(state), /disposable JFC clone/);
});
