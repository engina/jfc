import assert from "node:assert/strict";
import test from "node:test";

import {selectClockSample} from "./clock-alignment.mjs";

test("selects the clock sample with the lowest round trip", () => {
  const selected = selectClockSample([
    {roundTripMilliseconds: 15, guestMinusHostMilliseconds: 3},
    {roundTripMilliseconds: 4, guestMinusHostMilliseconds: 2},
    {roundTripMilliseconds: 8, guestMinusHostMilliseconds: 1},
  ]);
  assert.equal(selected.guestMinusHostMilliseconds, 2);
});
