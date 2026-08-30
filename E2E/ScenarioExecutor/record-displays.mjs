import {MultiDisplayRecorder} from "./recording.mjs";

function usage() {
  return "usage: record-displays.mjs --output DIR [--duration SECONDS] [--fps FPS] [--appium URL]";
}

function parsePositiveInteger(value, option) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${option} must be a positive integer`);
  }
  return parsed;
}

function parseArguments(argv) {
  const options = {
    output: null,
    duration: 5,
    fps: 10,
    appiumUrl: "http://127.0.0.1:4723",
  };
  const args = [...argv];
  while (args.length) {
    const option = args.shift();
    const value = args.shift();
    if (!value) throw new Error(`missing value for ${option}\n${usage()}`);
    if (option === "--output") options.output = value;
    else if (option === "--duration") {
      options.duration = parsePositiveInteger(value, option);
    } else if (option === "--fps") {
      options.fps = parsePositiveInteger(value, option);
    } else if (option === "--appium") options.appiumUrl = value;
    else throw new Error(`unknown option: ${option}\n${usage()}`);
  }
  if (!options.output) throw new Error(usage());
  return options;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const recorder = new MultiDisplayRecorder(options);
  try {
    await recorder.open();
    await recorder.start();
    await sleep(options.duration * 1_000);
    const manifest = await recorder.stop(options.output);
    process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
  } finally {
    await recorder.close();
  }
}

main().catch((error) => {
  console.error(error.stack ?? error.message);
  process.exitCode = 1;
});
