import {execFile} from "node:child_process";
import {promisify} from "node:util";

const execFileAsync = promisify(execFile);

export const UTMCTL = "/Applications/UTM.app/Contents/MacOS/utmctl";

export function parseUTMList(output) {
  const lines = output.split(/\r?\n/).slice(1);
  return lines.flatMap((line) => {
    const match = line.match(
      /^([0-9A-Fa-f-]{36})\s+(\S+)\s+(.+?)\s*$/,
    );
    if (!match) return [];
    return [{uuid: match[1].toUpperCase(), status: match[2], name: match[3]}];
  });
}

export async function runUTM(args, {timeout = 60_000} = {}) {
  return await execFileAsync(UTMCTL, args, {
    encoding: "utf8",
    maxBuffer: 4 * 1024 * 1024,
    timeout,
  });
}

export async function listVMs() {
  const {stdout} = await runUTM(["list"]);
  return parseUTMList(stdout);
}
