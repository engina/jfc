#!/usr/bin/env node

import { spawn } from "node:child_process";
import { constants as fsConstants } from "node:fs";
import {
  access,
  mkdir,
  mkdtemp,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const DEFAULT_CHROME =
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

function usage() {
  console.error(
    "Usage: node scripts/render-svg-frames.mjs <input.svg> <output-dir> " +
      "[--duration 18] [--fps 30] [--width 1600] [--height 720]",
  );
}

function parsePositiveNumber(value, flag) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`${flag} must be a positive number`);
  }
  return parsed;
}

function parseArguments(argv) {
  if (argv.length < 2) {
    usage();
    process.exit(2);
  }

  const options = {
    input: resolve(argv[0]),
    output: resolve(argv[1]),
    duration: 18,
    fps: 30,
    width: 1600,
    height: 720,
  };

  for (let index = 2; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (value === undefined) {
      throw new Error(`Missing value for ${flag}`);
    }

    switch (flag) {
      case "--duration":
        options.duration = parsePositiveNumber(value, flag);
        break;
      case "--fps":
        options.fps = parsePositiveNumber(value, flag);
        break;
      case "--width":
        options.width = parsePositiveNumber(value, flag);
        break;
      case "--height":
        options.height = parsePositiveNumber(value, flag);
        break;
      default:
        throw new Error(`Unknown option: ${flag}`);
    }
  }

  for (const key of ["fps", "width", "height"]) {
    if (!Number.isInteger(options[key])) {
      throw new Error(`--${key} must be an integer`);
    }
  }

  return options;
}

class DevToolsConnection {
  constructor(webSocket) {
    this.webSocket = webSocket;
    this.nextID = 1;
    this.pending = new Map();

    webSocket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (!message.id) return;

      const request = this.pending.get(message.id);
      if (!request) return;

      this.pending.delete(message.id);
      if (message.error) {
        request.reject(
          new Error(`${request.method}: ${message.error.message}`),
        );
      } else {
        request.resolve(message.result);
      }
    });

    webSocket.addEventListener("close", () => {
      for (const request of this.pending.values()) {
        request.reject(new Error("Chrome DevTools connection closed"));
      }
      this.pending.clear();
    });
  }

  send(method, params = {}, sessionId) {
    const id = this.nextID++;
    return new Promise((resolvePromise, rejectPromise) => {
      this.pending.set(id, {
        method,
        resolve: resolvePromise,
        reject: rejectPromise,
      });
      this.webSocket.send(
        JSON.stringify({ id, method, params, ...(sessionId && { sessionId }) }),
      );
    });
  }

  close() {
    this.webSocket.close();
  }
}

async function connectWebSocket(url) {
  const webSocket = new WebSocket(url);
  await new Promise((resolvePromise, rejectPromise) => {
    webSocket.addEventListener("open", resolvePromise, { once: true });
    webSocket.addEventListener(
      "error",
      () => rejectPromise(new Error("Could not connect to Chrome DevTools")),
      { once: true },
    );
  });
  return new DevToolsConnection(webSocket);
}

function waitForDevTools(chrome) {
  return new Promise((resolvePromise, rejectPromise) => {
    let stderr = "";
    const timeout = setTimeout(() => {
      rejectPromise(new Error("Timed out waiting for Chrome DevTools"));
    }, 15_000);

    chrome.stderr.setEncoding("utf8");
    chrome.stderr.on("data", (chunk) => {
      stderr += chunk;
      const match = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) {
        clearTimeout(timeout);
        resolvePromise(match[1]);
      }
    });

    chrome.once("exit", (code) => {
      clearTimeout(timeout);
      rejectPromise(
        new Error(`Chrome exited before DevTools was ready (code ${code})`),
      );
    });
  });
}

async function waitForPageLoad(connection, sessionId) {
  for (;;) {
    const { result } = await connection.send(
      "Runtime.evaluate",
      { expression: "document.readyState", returnByValue: true },
      sessionId,
    );
    if (result.value === "complete") return;
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
  }
}

async function prepareOutputDirectory(output) {
  await mkdir(dirname(output), { recursive: true });
  try {
    await mkdir(output);
  } catch (error) {
    if (error.code === "EEXIST") {
      throw new Error(`Output directory already exists: ${output}`);
    }
    throw error;
  }
}

function waitForProcessExit(child, timeoutMilliseconds) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve(true);
  }

  return new Promise((resolvePromise) => {
    const timeout = setTimeout(() => {
      child.removeListener("exit", handleExit);
      resolvePromise(false);
    }, timeoutMilliseconds);
    const handleExit = () => {
      clearTimeout(timeout);
      resolvePromise(true);
    };
    child.once("exit", handleExit);
  });
}

async function stopChrome(chrome) {
  if (chrome.exitCode !== null || chrome.signalCode !== null) return;

  chrome.kill("SIGTERM");
  if (await waitForProcessExit(chrome, 2_000)) return;

  chrome.kill("SIGKILL");
  await waitForProcessExit(chrome, 2_000);
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  await access(options.input, fsConstants.R_OK);
  await access(DEFAULT_CHROME, fsConstants.X_OK);
  await prepareOutputDirectory(options.output);

  const profileDirectory = await mkdtemp(`${tmpdir()}/jfc-svg-render-`);
  const chrome = spawn(
    DEFAULT_CHROME,
    [
      "--headless=new",
      "--disable-background-networking",
      "--disable-component-update",
      "--disable-default-apps",
      "--disable-extensions",
      "--disable-gpu",
      "--hide-scrollbars",
      "--mute-audio",
      "--no-first-run",
      "--remote-debugging-address=127.0.0.1",
      "--remote-debugging-port=0",
      `--user-data-dir=${profileDirectory}`,
      "about:blank",
    ],
    { stdio: ["ignore", "ignore", "pipe"] },
  );

  let connection;
  try {
    const devToolsURL = await waitForDevTools(chrome);
    connection = await connectWebSocket(devToolsURL);

    const { targetId } = await connection.send("Target.createTarget", {
      url: "about:blank",
    });
    const { sessionId } = await connection.send("Target.attachToTarget", {
      targetId,
      flatten: true,
    });

    await connection.send("Page.enable", {}, sessionId);
    await connection.send("Runtime.enable", {}, sessionId);
    await connection.send(
      "Emulation.setDeviceMetricsOverride",
      {
        width: options.width,
        height: options.height,
        deviceScaleFactor: 1,
        mobile: false,
      },
      sessionId,
    );
    await connection.send(
      "Page.navigate",
      { url: pathToFileURL(options.input).href },
      sessionId,
    );
    await waitForPageLoad(connection, sessionId);

    const frameCount = Math.round(options.duration * options.fps);
    const digits = String(frameCount - 1).length;
    console.log(
      `Rendering ${frameCount} frames at ${options.width}x${options.height}, ` +
        `${options.fps} fps...`,
    );

    await connection.send(
      "Runtime.evaluate",
      {
        expression: `(() => {
          const svg = document.documentElement;
          svg.pauseAnimations();
          svg.setCurrentTime(0);
          for (const animation of document.getAnimations()) {
            animation.pause();
            animation.currentTime = 0;
          }
        })()`,
      },
      sessionId,
    );

    for (let frame = 0; frame < frameCount; frame += 1) {
      const seconds = frame / options.fps;
      await connection.send(
        "Runtime.evaluate",
        {
          expression: `(() => {
            const seconds = ${seconds};
            document.documentElement.setCurrentTime(seconds);
            for (const animation of document.getAnimations()) {
              animation.currentTime = seconds * 1000;
            }
          })()`,
        },
        sessionId,
      );

      const { data } = await connection.send(
        "Page.captureScreenshot",
        {
          format: "png",
          fromSurface: true,
          captureBeyondViewport: false,
        },
        sessionId,
      );
      const filename = `frame-${String(frame).padStart(digits, "0")}.png`;
      await writeFile(resolve(options.output, filename), data, "base64");

      if ((frame + 1) % options.fps === 0 || frame + 1 === frameCount) {
        console.log(`Rendered ${frame + 1}/${frameCount}`);
      }
    }

    await writeFile(
      resolve(options.output, "frames.json"),
      `${JSON.stringify(
        {
          source: basename(options.input),
          duration: options.duration,
          fps: options.fps,
          width: options.width,
          height: options.height,
          frameCount,
          filenamePattern: `frame-%0${digits}d.png`,
        },
        null,
        2,
      )}\n`,
    );
  } catch (error) {
    await rm(options.output, { recursive: true, force: true });
    throw error;
  } finally {
    connection?.close();
    await stopChrome(chrome);
    try {
      await rm(profileDirectory, {
        recursive: true,
        force: true,
        maxRetries: 5,
        retryDelay: 100,
      });
    } catch (error) {
      console.warn(
        `Could not remove temporary Chrome profile ${profileDirectory}: ` +
          error.message,
      );
    }
  }

  console.log(`Frames written to ${options.output}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
