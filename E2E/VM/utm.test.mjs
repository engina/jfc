import assert from "node:assert/strict";
import test from "node:test";

import {parseUTMList} from "./utm.mjs";

test("parses UTM list output without truncating names", () => {
  const output = `UUID                                 Status   Name
8BC4EB4B-F453-4ECB-8937-D091D57AE291 started  JFC macOS 14
F686D935-20B5-4D17-851C-B36BCC2D6D78 stopped  JFC macOS 14 - preinstall baseline
`;
  assert.deepEqual(parseUTMList(output), [
    {
      uuid: "8BC4EB4B-F453-4ECB-8937-D091D57AE291",
      status: "started",
      name: "JFC macOS 14",
    },
    {
      uuid: "F686D935-20B5-4D17-851C-B36BCC2D6D78",
      status: "stopped",
      name: "JFC macOS 14 - preinstall baseline",
    },
  ]);
});

test("ignores headers, blank lines, and diagnostics", () => {
  assert.deepEqual(parseUTMList("UUID Status Name\nwarning\n\n"), []);
});
