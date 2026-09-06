import {execFileSync, spawn} from "node:child_process";
import {copyFile, mkdir, mkdtemp, rm, stat, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";

const FFMPEG = "/opt/homebrew/bin/ffmpeg";
const START_TIMEOUT_MS = 5_000;
const STOP_TIMEOUT_MS = 10_000;
const STDERR_LIMIT = 64 * 1024;

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export function listScreenDevices() {
  let output = "";
  try {
    execFileSync(
      FFMPEG,
      ["-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""],
      {encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]},
    );
  } catch (error) {
    output = `${error.stdout ?? ""}\n${error.stderr ?? ""}`;
  }
  const devices = [...output.matchAll(/\[(\d+)\]\s+Capture screen (\d+)/g)]
    .map((match) => ({deviceId: Number(match[1]), screenIndex: Number(match[2])}))
    .sort((left, right) => left.screenIndex - right.screenIndex);
  if (devices.length === 0) {
    throw new Error("FFmpeg reported no AVFoundation screen devices");
  }
  return devices;
}

export function recordingArguments({deviceId, fps, outputPath}) {
  return [
    "-hide_banner",
    "-loglevel",
    "warning",
    "-y",
    "-f",
    "avfoundation",
    "-capture_cursor",
    "1",
    "-capture_mouse_clicks",
    "1",
    "-drop_late_frames",
    "0",
    "-framerate",
    `${fps}`,
    "-i",
    `${deviceId}`,
    "-an",
    "-c:v",
    "libx264",
    "-preset",
    "ultrafast",
    "-tune",
    "zerolatency",
    "-pix_fmt",
    "yuv420p",
    "-fps_mode",
    "passthrough",
    "-movflags",
    "+faststart",
    outputPath,
  ];
}

function launchCapture({device, fps, outputPath}) {
  const child = spawn(
    FFMPEG,
    recordingArguments({deviceId: device.deviceId, fps, outputPath}),
    {stdio: ["pipe", "ignore", "pipe"]},
  );
  const capture = {
    child,
    completion: null,
    device,
    outputPath,
    status: null,
    stderr: "",
  };
  child.stderr.setEncoding("utf8");
  child.stdin.on("error", () => {});
  child.stderr.on("data", (chunk) => {
    capture.stderr = `${capture.stderr}${chunk}`.slice(-STDERR_LIMIT);
  });
  capture.completion = new Promise((resolve) => {
    child.once("error", (error) => {
      capture.status ??= {error};
      resolve(capture.status);
    });
    child.once("close", (code, signal) => {
      capture.status ??= {code, signal};
      resolve(capture.status);
    });
  });
  return capture;
}

function captureError(capture, message) {
  const detail = capture.stderr.trim();
  return new Error(detail ? `${message}: ${detail}` : message);
}

async function waitForCaptureStart(capture) {
  const deadline = Date.now() + START_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (capture.status) {
      throw captureError(capture, "FFmpeg screen recorder exited during startup");
    }
    try {
      const metadata = await stat(capture.outputPath);
      if (metadata.size > 0) return;
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    await sleep(50);
  }
  throw captureError(capture, "timed out waiting for FFmpeg screen recorder");
}

async function stopCapture(capture) {
  if (!capture.status) {
    capture.child.stdin.write("q\n");
    capture.child.stdin.end();
  }
  const timeout = Symbol("timeout");
  const status = await Promise.race([
    capture.completion,
    sleep(STOP_TIMEOUT_MS).then(() => timeout),
  ]);
  if (status === timeout) {
    capture.child.kill("SIGKILL");
    await capture.completion;
    throw captureError(capture, "FFmpeg screen recorder did not stop cleanly");
  }
  if (status.error) {
    throw captureError(capture, `FFmpeg screen recorder failed: ${status.error.message}`);
  }
  if (status.code !== 0) {
    throw captureError(
      capture,
      `FFmpeg screen recorder exited with code ${status.code}, signal ${status.signal}`,
    );
  }
}

export class MultiDisplayRecorder {
  constructor({fps = 10} = {}) {
    this.fps = fps;
    this.devices = listScreenDevices();
    this.captures = [];
    this.temporaryDirectory = null;
    this.startedAt = null;
    this.recording = false;
  }

  async open() {
    if (!this.temporaryDirectory) {
      this.temporaryDirectory = await mkdtemp(path.join(tmpdir(), "jfc-e2e-recording-"));
    }
  }

  async start() {
    if (!this.temporaryDirectory) throw new Error("recorder is not open");
    this.startedAt = new Date();
    this.captures = this.devices.map((device) =>
      launchCapture({
        device,
        fps: this.fps,
        outputPath: path.join(this.temporaryDirectory, `display-${device.screenIndex + 1}.mp4`),
      }),
    );
    try {
      await Promise.all(this.captures.map(waitForCaptureStart));
      this.recording = true;
    } catch (error) {
      await Promise.all(this.captures.map((capture) => stopCapture(capture).catch(() => {})));
      throw error;
    }
  }

  async stop(outputDirectory) {
    if (!this.recording) throw new Error("recorder is not running");
    try {
      await Promise.all(this.captures.map(stopCapture));
    } finally {
      this.recording = false;
    }
    await mkdir(outputDirectory, {recursive: true});

    const recordings = [];
    for (const capture of this.captures) {
      const {device, outputPath} = capture;
      const filename = `display-${device.screenIndex + 1}.mp4`;
      const destination = path.join(outputDirectory, filename);
      await copyFile(outputPath, destination);
      const metadata = await stat(destination);
      if (metadata.size === 0) {
        throw new Error(`FFmpeg returned an empty recording for ${filename}`);
      }
      recordings.push({
        ...device,
        display: device.screenIndex + 1,
        filename,
        bytes: metadata.size,
      });
    }

    const stoppedAt = new Date();
    const manifest = {
      status: "passed",
      startedAt: this.startedAt.toISOString(),
      stoppedAt: stoppedAt.toISOString(),
      durationSeconds: (stoppedAt - this.startedAt) / 1_000,
      fps: this.fps,
      dropLateFrames: false,
      outputFrameRateMode: "passthrough",
      recordings,
    };
    await writeFile(
      path.join(outputDirectory, "recordings.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    await this.cleanup();
    return manifest;
  }

  async cleanup() {
    this.captures = [];
    if (this.temporaryDirectory) {
      await rm(this.temporaryDirectory, {recursive: true, force: true});
      this.temporaryDirectory = null;
    }
  }

  async close() {
    if (this.captures.length > 0) {
      await Promise.all(this.captures.map((capture) => stopCapture(capture).catch(() => {})));
    }
    this.recording = false;
    await this.cleanup();
  }
}
