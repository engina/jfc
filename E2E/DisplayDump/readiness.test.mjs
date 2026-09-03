import assert from "node:assert/strict";
import test from "node:test";

import {displayReadinessMismatches} from "./readiness.mjs";

const manifest = {
  guest: {
    displays: {
      appKit: [
        {name: "D1", x: 0, y: 0, width: 1450, height: 906},
        {name: "D2", x: 1450, y: -534, width: 2560, height: 1440},
        {name: "D3", x: 4010, y: -534, width: 2560, height: 1440},
      ],
      coreGraphics: [
        {name: "D1", x: 0, y: 0, width: 1450, height: 906},
        {name: "D2", x: 1450, y: 0, width: 2560, height: 1440},
        {name: "D3", x: 4010, y: 0, width: 2560, height: 1440},
      ],
    },
  },
};

function readyState() {
  return {
    screenCaptureAllowed: true,
    displays: manifest.guest.displays.appKit.map((frame, index) => ({
      frame,
      coreGraphicsBounds: manifest.guest.displays.coreGraphics[index],
      isMain: index === 0,
    })),
  };
}

test("accepts the recorded three-display geometry", () => {
  assert.deepEqual(displayReadinessMismatches(readyState(), manifest), []);
});

test("accepts resized and reordered non-overlapping displays", () => {
  const state = readyState();
  state.displays = [
    {
      frame: {x: 0, y: 0, width: 1920, height: 1200},
      coreGraphicsBounds: {x: 0, y: 0, width: 1920, height: 1200},
      isMain: true,
    },
    {
      frame: {x: 4480, y: -240, width: 2560, height: 1440},
      coreGraphicsBounds: {x: 4480, y: 0, width: 2560, height: 1440},
      isMain: false,
    },
    {
      frame: {x: 1920, y: -240, width: 2560, height: 1440},
      coreGraphicsBounds: {x: 1920, y: 0, width: 2560, height: 1440},
      isMain: false,
    },
  ];
  assert.deepEqual(displayReadinessMismatches(state, manifest), []);
});

test("rejects a missing virtual display", () => {
  const state = readyState();
  state.displays.pop();
  assert.deepEqual(displayReadinessMismatches(state, manifest), [
    "display count is 2; expected 3",
  ]);
});

test("rejects missing screen capture, an unusable display, and overlap", () => {
  const state = readyState();
  state.screenCaptureAllowed = false;
  state.displays[1].frame = {...state.displays[1].frame, width: 800};
  state.displays[2].coreGraphicsBounds = {
    ...state.displays[2].coreGraphicsBounds,
    x: 3_000,
  };
  assert.deepEqual(displayReadinessMismatches(state, manifest), [
    "screen capture is not authorized",
    "D2 AppKit frame is not usable: 1450,-534 800x1440",
    "D2 and D3 overlap",
  ]);
});

test("rejects an ambiguous main display", () => {
  const state = readyState();
  state.displays[1].isMain = true;
  assert.deepEqual(displayReadinessMismatches(state, manifest), [
    "main display count is 2; expected 1",
  ]);
});
