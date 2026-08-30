import {readdir, readFile} from "node:fs/promises";
import path from "node:path";

const RUN_DIRECTORY = /^scenario-([0-9]{8}T[0-9]{6}Z)$/;

function embeddedJSON(value) {
  return JSON.stringify(value).replaceAll("<", "\\u003c");
}

async function readJSON(filename) {
  return JSON.parse(await readFile(filename, "utf8"));
}

export function stateDifferences(expected = {}, actual = {}) {
  const sameValue = (left, right) => JSON.stringify(left) === JSON.stringify(right);
  const rows = [];
  if (Array.isArray(expected.windows)) {
    const actualWindows = Array.isArray(actual.windows) ? actual.windows : [];
    const displayCount = Math.max(expected.windows.length, actualWindows.length);
    for (let offset = 0; offset < displayCount; offset += 1) {
      if (!sameValue(expected.windows[offset], actualWindows[offset])) {
        rows.push({
          label: `D${offset + 1} windows`,
          expected: expected.windows[offset],
          actual: actualWindows[offset],
        });
      }
    }
  }
  const keys = new Set([
    ...Object.keys(expected).filter((key) => key !== "windows"),
    ...Object.keys(actual).filter((key) => key !== "windows"),
  ]);
  for (const key of keys) {
    if (!sameValue(expected[key], actual[key])) {
      rows.push({label: key, expected: expected[key], actual: actual[key]});
    }
  }
  return rows;
}

export async function collectLatestRuns(artifactsDirectory, scenariosDirectory) {
  const entries = await readdir(artifactsDirectory, {withFileTypes: true});
  const latest = new Map();
  for (const entry of entries) {
    const match = entry.isDirectory() ? RUN_DIRECTORY.exec(entry.name) : null;
    if (!match) continue;
    let result;
    try {
      result = await readJSON(path.join(artifactsDirectory, entry.name, "result.json"));
    } catch {
      continue;
    }
    if (
      result.schemaVersion !== 1
      || typeof result.scenario !== "string"
      || !Array.isArray(result.assertions)
    ) {
      continue;
    }
    let scenario;
    try {
      scenario = await readJSON(path.join(scenariosDirectory, result.scenario));
    } catch {
      continue;
    }
    const previous = latest.get(result.scenario);
    if (!previous || entry.name > previous.artifactDirectory) {
      latest.set(result.scenario, {
        artifactDirectory: entry.name,
        recordedAt: match[1],
        result,
        scenario,
      });
    }
  }
  return [...latest.values()].sort((left, right) =>
    left.result.scenario.localeCompare(right.result.scenario),
  );
}

export function renderReport(runs, generatedAt = new Date().toISOString()) {
  const data = embeddedJSON({generatedAt, runs});
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>JFC E2E results</title>
    <style>
      :root {
        color-scheme: light dark;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        --background: light-dark(#f4f4f6, #111216);
        --card: light-dark(#fff, #1b1c22);
        --border: light-dark(#d7d7dc, #343640);
        --muted: light-dark(#5f626b, #a8abb5);
        --pass: light-dark(#087f3f, #54d68a);
        --fail: light-dark(#b42318, #ff786e);
        --shadow: light-dark(0 16px 44px #24262d14, 0 16px 44px #0006);
      }
      * { box-sizing: border-box; }
      body { background: var(--background); line-height: 1.45; margin: 0; padding: 32px; }
      header, main { margin: 0 auto; max-width: 1500px; }
      header { align-items: end; display: flex; justify-content: space-between; }
      h1, h2, h3, p { margin: 0; }
      h1 { letter-spacing: -0.035em; }
      .muted { color: var(--muted); }
      #summary { font-size: 18px; margin-top: 8px; }
      #runs { display: grid; gap: 24px; margin-top: 28px; }
      article {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 14px;
        box-shadow: var(--shadow);
        overflow: hidden;
      }
      .heading { align-items: center; border-bottom: 1px solid var(--border); display: flex; gap: 12px; padding: 20px; }
      .heading .time { margin-left: auto; }
      .badge { border: 1px solid currentColor; border-radius: 999px; padding: 3px 9px; }
      .passed { color: var(--pass); }
      .failed { color: var(--fail); }
      .content { display: grid; gap: 20px; padding: 20px; }
      .state-block { background: var(--background); border-radius: 10px; padding: 14px; }
      .section-label { color: var(--muted); font-size: 12px; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
      .displays { display: grid; gap: 8px; grid-template-columns: repeat(3, 1fr); margin-top: 10px; }
      .display { border: 1px solid var(--border); border-radius: 8px; min-height: 78px; padding: 10px; }
      .display-order { font-size: 12px; }
      .stack { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
      .window { background: var(--card); border: 1px solid var(--border); border-radius: 6px; padding: 5px 7px; }
      .window.active { border-color: var(--pass); color: var(--pass); }
      .values { display: grid; gap: 6px 12px; grid-template-columns: max-content 1fr; margin-top: 10px; }
      .actions { display: grid; gap: 12px; }
      .action-step { border: 1px solid var(--border); border-radius: 10px; overflow: hidden; }
      .action-heading { align-items: center; display: flex; gap: 10px; padding: 11px 14px; }
      .action-heading .badge { margin-left: auto; }
      .action-body { border-top: 1px solid var(--border); display: grid; gap: 12px; grid-template-columns: minmax(180px, 0.36fr) minmax(0, 1fr); padding: 12px; }
      .action-command { align-content: center; display: grid; gap: 8px; padding: 10px; }
      code { background: var(--background); border-radius: 5px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; padding: 3px 6px; }
      .diff { background: color-mix(in srgb, var(--fail) 8%, transparent); border-top: 1px solid var(--fail); color: var(--fail); display: grid; gap: 8px; padding: 12px 14px; }
      .diff-row { align-items: start; display: grid; gap: 8px; grid-template-columns: minmax(120px, 0.35fr) 1fr 1fr; }
      .diff-value { display: grid; gap: 3px; }
      .diff-value code { color: inherit; overflow-wrap: anywhere; white-space: pre-wrap; }
      .artifacts { border-top: 1px solid var(--border); display: grid; gap: 12px; padding-top: 18px; }
      .artifact-heading { align-items: baseline; display: flex; justify-content: space-between; }
      video { background: #000; border-radius: 10px; display: block; max-height: 620px; width: 100%; }
      .screenshots { display: grid; gap: 12px; grid-template-columns: repeat(3, 1fr); }
      figure { border: 1px solid var(--border); border-radius: 10px; margin: 0; overflow: hidden; }
      figure img { aspect-ratio: 16 / 10; background: #000; display: block; object-fit: contain; width: 100%; }
      figcaption { align-items: center; display: flex; justify-content: space-between; padding: 9px 11px; }
      .artifact-links { display: flex; flex-wrap: wrap; gap: 12px; }
      a { color: inherit; }
      details { border-top: 1px solid var(--border); padding: 14px 20px; }
      .all-artifacts { border: 1px solid var(--border); border-radius: 8px; padding: 0; }
      .all-artifacts summary { padding: 11px 13px; }
      .all-artifacts[open] summary { border-bottom: 1px solid var(--border); }
      .all-artifacts-body { display: grid; gap: 12px; padding: 12px; }
      summary { cursor: pointer; }
      pre { overflow: auto; white-space: pre-wrap; }
      .empty { padding: 60px 0; text-align: center; }
      @media (max-width: 800px) {
        body { padding: 18px; }
        header { align-items: start; flex-direction: column; gap: 8px; }
        .displays, .screenshots, .action-body { grid-template-columns: 1fr; }
        .diff-row { grid-template-columns: 1fr; }
        .heading { align-items: start; flex-wrap: wrap; }
        .heading .time { margin-left: 0; width: 100%; }
      }
    </style>
  </head>
  <body>
    <header>
      <div>
        <h1>JFC E2E results</h1>
        <p id="summary" class="muted"></p>
      </div>
      <p id="generated" class="muted"></p>
    </header>
    <main id="runs"></main>
    <script id="report-data" type="application/json">${data}</script>
    <script>
      (() => {
        "use strict";
        const data = JSON.parse(document.querySelector("#report-data").textContent);
        const runsElement = document.querySelector("#runs");
        const passed = data.runs.filter(({result}) => result.status === "passed").length;
        document.querySelector("#summary").textContent =
          data.runs.length + " scenarios · " + passed + " passed · "
          + (data.runs.length - passed) + " failed";
        document.querySelector("#generated").textContent =
          "Generated " + new Date(data.generatedAt).toLocaleString();

        const element = (name, className, text) => {
          const result = document.createElement(name);
          if (className) result.className = className;
          if (text !== undefined) result.textContent = text;
          return result;
        };

        const stateDifferences = ${stateDifferences.toString()};

        const appendState = (parent, state) => {
          if (Array.isArray(state?.windows)) {
            const displays = element("div", "displays");
            state.windows.forEach((windows, offset) => {
              const display = element("div", "display");
              display.append(element("strong", "", "D" + (offset + 1)));
              display.append(element("div", "display-order muted", "back → front"));
              const stack = element("div", "stack");
              if (windows.length === 0) stack.append(element("span", "muted", "empty"));
              for (const windowName of windows) {
                const active = windowName.endsWith("*");
                stack.append(element(
                  "span",
                  "window" + (active ? " active" : ""),
                  active ? windowName.slice(0, -1) + " ★" : windowName,
                ));
              }
              display.append(stack);
              displays.append(display);
            });
            parent.append(displays);
          }
          const values = Object.entries(state ?? {}).filter(([key]) => key !== "windows");
          if (values.length > 0) {
            const valueGrid = element("div", "values");
            for (const [key, value] of values) {
              valueGrid.append(element("strong", "", key));
              valueGrid.append(element("span", "", JSON.stringify(value)));
            }
            parent.append(valueGrid);
          }
        };

        const printable = (value) => value === undefined ? "missing" : JSON.stringify(value);

        const appendDiff = (parent, expected, actual) => {
          const rows = stateDifferences(expected, actual);
          if (rows.length === 0) {
            rows.push({label: "assertion", expected: "passed", actual: "failed"});
          }

          const diff = element("div", "diff");
          diff.append(element("strong", "", "Mismatch"));
          for (const row of rows) {
            const diffRow = element("div", "diff-row");
            diffRow.append(element("strong", "", row.label));
            for (const [label, value] of [["Expected", row.expected], ["Actual", row.actual]]) {
              const valueBlock = element("div", "diff-value");
              valueBlock.append(element("span", "section-label", label));
              valueBlock.append(element("code", "", printable(value)));
              diffRow.append(valueBlock);
            }
            diff.append(diffRow);
          }
          parent.append(diff);
        };

        for (const run of data.runs) {
          const card = element("article");
          const heading = element("div", "heading");
          heading.append(element("h2", "", run.result.scenario));
          heading.append(element(
            "span",
            "badge " + (run.result.status === "passed" ? "passed" : "failed"),
            run.result.status,
          ));
          heading.append(element("span", "time muted", run.recordedAt));
          card.append(heading);

          const content = element("div", "content");
          const initial = element("section", "state-block");
          initial.append(element("div", "section-label", "Initial state"));
          appendState(initial, {windows: run.scenario.windows});
          content.append(initial);

          const actions = element("section", "actions");
          run.scenario.actions.forEach((action, index) => {
            const actionNumber = index + 1;
            const assertion = run.result.assertions.find(
              ({afterAction}) => afterAction === actionNumber,
            );
            const status = assertion?.status ?? "failed";
            const step = element("section", "action-step");
            const actionHeading = element("div", "action-heading");
            actionHeading.append(element("strong", "", "Action " + actionNumber));
            actionHeading.append(element(
              "span",
              "badge " + (status === "passed" ? "passed" : "failed"),
              status,
            ));
            step.append(actionHeading);

            const actionBody = element("div", "action-body");
            const command = element("div", "action-command");
            command.append(element("div", "section-label", "Action"));
            if (action.click) {
              const description = element("div");
              description.append("Click ", element("code", "", action.click));
              command.append(description);
            } else {
              command.append(element("span", "", "Inspect state"));
            }
            actionBody.append(command);

            const expected = element("div", "state-block");
            expected.append(element("div", "section-label", "Expected output state"));
            appendState(expected, action.expect ?? {});
            actionBody.append(expected);
            step.append(actionBody);

            if (status !== "passed") {
              appendDiff(step, action.expect ?? {}, assertion?.state ?? {});
            }
            actions.append(step);
          });
          content.append(actions);

          const artifacts = element("section", "artifacts");
          const artifactHeading = element("div", "artifact-heading");
          artifactHeading.append(element("h3", "", "Mosaic recording"));
          artifactHeading.append(element("span", "muted", "D1 · D2 · D3"));
          artifacts.append(artifactHeading);

          const video = element("video");
          video.controls = true;
          video.preload = "metadata";
          video.src = run.artifactDirectory + "/mosaic.mp4";
          artifacts.append(video);

          const allArtifacts = element("details", "all-artifacts");
          allArtifacts.append(element("summary", "", "All artifacts…"));
          const allArtifactsBody = element("div", "all-artifacts-body");
          const screenshots = element("div", "screenshots");
          const artifactLinks = element("div", "artifact-links");
          const mosaicLink = element("a", "", "Open mosaic video");
          mosaicLink.href = run.artifactDirectory + "/mosaic.mp4";
          mosaicLink.target = "_blank";
          mosaicLink.rel = "noreferrer";
          artifactLinks.append(mosaicLink);
          for (let display = 1; display <= 3; display += 1) {
            const screenshotURL = run.artifactDirectory + "/displays/display-" + display + ".png";
            const recordingURL = run.artifactDirectory + "/display-" + display + ".mp4";
            const figure = element("figure");
            const imageLink = element("a");
            imageLink.href = screenshotURL;
            imageLink.target = "_blank";
            imageLink.rel = "noreferrer";
            const screenshot = element("img");
            screenshot.src = screenshotURL;
            screenshot.alt = "Display " + display + " final screenshot";
            screenshot.loading = "lazy";
            imageLink.append(screenshot);
            figure.append(imageLink);
            const caption = element("figcaption");
            caption.append(element("strong", "", "D" + display));
            const recording = element("a", "", "video");
            recording.href = recordingURL;
            recording.target = "_blank";
            recording.rel = "noreferrer";
            caption.append(recording);
            figure.append(caption);
            screenshots.append(figure);
          }
          allArtifactsBody.append(screenshots);
          allArtifactsBody.append(artifactLinks);
          allArtifacts.append(allArtifactsBody);
          artifacts.append(allArtifacts);
          content.append(artifacts);
          card.append(content);

          const technical = element("details");
          technical.append(element("summary", "", "Technical details…"));
          technical.append(element("strong", "", "Scenario recipe"));
          technical.append(element("pre", "", JSON.stringify(run.scenario, null, 2)));
          technical.append(element("strong", "", "Result JSON"));
          technical.append(element("pre", "", JSON.stringify(run.result, null, 2)));
          card.append(technical);
          runsElement.append(card);
        }
        if (data.runs.length === 0) {
          runsElement.append(element("p", "empty muted", "No current result files found."));
        }
      })();
    </script>
  </body>
</html>
`;
}
