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

test("accepts the exact three-display geometry", () => {
  assert.deepEqual(displayReadinessMismatches(readyState(), manifest), []);
});

test("rejects a missing virtual display", () => {
  const state = readyState();
  state.displays.pop();
  assert.deepEqual(displayReadinessMismatches(state, manifest), [
    "display count is 2; expected 3",
    "D3 is missing",
  ]);
});

test("rejects shifted AppKit and Core Graphics geometry", () => {
  const state = readyState();
  state.displays[1].frame = {...state.displays[1].frame, x: 1400};
  state.displays[2].coreGraphicsBounds = {
    ...state.displays[2].coreGraphicsBounds,
    y: 10,
  };
  assert.deepEqual(displayReadinessMismatches(state, manifest), [
    "D2 AppKit frame is 1400,-534 2560x1440; expected 1450,-534 2560x1440",
    "D3 Core Graphics bounds are 4010,10 2560x1440; expected 4010,0 2560x1440",
  ]);
});
