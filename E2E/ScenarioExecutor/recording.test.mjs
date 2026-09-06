import assert from "node:assert/strict";
import test from "node:test";

import {recordingArguments} from "./recording.mjs";

test("records AVFoundation frames without late-frame or output-rate dropping", () => {
  const args = recordingArguments({
    deviceId: 7,
    fps: 10,
    outputPath: "/tmp/display.mp4",
  });

  assert.deepEqual(
    args.slice(args.indexOf("-drop_late_frames"), args.indexOf("-drop_late_frames") + 2),
    ["-drop_late_frames", "0"],
  );
  assert.ok(args.indexOf("-drop_late_frames") < args.indexOf("-i"));
  assert.deepEqual(
    args.slice(args.indexOf("-fps_mode"), args.indexOf("-fps_mode") + 2),
    ["-fps_mode", "passthrough"],
  );
  assert.equal(args.includes("-r"), false);
  assert.deepEqual(
    args.slice(args.indexOf("-capture_mouse_clicks"), args.indexOf("-capture_mouse_clicks") + 2),
    ["-capture_mouse_clicks", "1"],
  );
});
