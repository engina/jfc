import {execFileSync} from "node:child_process";
import {mkdir, writeFile} from "node:fs/promises";
import path from "node:path";

import {AppiumClient} from "./appium.mjs";

const FFMPEG = "/opt/homebrew/bin/ffmpeg";

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

export class MultiDisplayRecorder {
  constructor({appiumUrl = "http://127.0.0.1:4723", fps = 10} = {}) {
    this.appiumUrl = appiumUrl;
    this.fps = fps;
    this.devices = listScreenDevices();
    this.clients = [];
    this.startedAt = null;
    this.recording = false;
  }

  async open() {
    for (const _device of this.devices) {
      const client = new AppiumClient(this.appiumUrl);
      await client.createSession();
      this.clients.push(client);
    }
  }

  async start() {
    if (this.clients.length !== this.devices.length) {
      throw new Error("recorder sessions are not open");
    }
    this.startedAt = new Date();
    await Promise.all(
      this.devices.map((device, offset) =>
        this.clients[offset].execute("macos: startRecordingScreen", [
          {
            deviceId: device.deviceId,
            fps: this.fps,
            preset: "ultrafast",
            captureCursor: true,
            captureClicks: true,
            timeLimit: 300,
          },
        ]),
      ),
    );
    this.recording = true;
  }

  async stop(outputDirectory) {
    if (!this.recording) throw new Error("recorder is not running");
    const payloads = await Promise.all(
      this.clients.map((client) =>
        client.execute("macos: stopRecordingScreen", [{}]),
      ),
    );
    this.recording = false;
    await mkdir(outputDirectory, {recursive: true});

    const recordings = [];
    for (const [offset, payload] of payloads.entries()) {
      const device = this.devices[offset];
      const filename = `display-${device.screenIndex + 1}.mp4`;
      const bytes = Buffer.from(payload, "base64");
      if (bytes.length === 0) {
        throw new Error(`Mac2 returned an empty recording for ${filename}`);
      }
      await writeFile(path.join(outputDirectory, filename), bytes);
      recordings.push({
        ...device,
        display: device.screenIndex + 1,
        filename,
        bytes: bytes.length,
      });
    }

    const stoppedAt = new Date();
    const manifest = {
      status: "passed",
      startedAt: this.startedAt.toISOString(),
      stoppedAt: stoppedAt.toISOString(),
      durationSeconds: (stoppedAt - this.startedAt) / 1_000,
      fps: this.fps,
      recordings,
    };
    await writeFile(
      path.join(outputDirectory, "recordings.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    return manifest;
  }

  async close() {
    if (this.recording) {
      await Promise.all(
        this.clients.map((client) =>
          client.execute("macos: stopRecordingScreen", [{}]).catch(() => {}),
        ),
      );
      this.recording = false;
    }
    await Promise.all(
      this.clients.map((client) => client.deleteSession().catch(() => {})),
    );
    this.clients = [];
  }
}
